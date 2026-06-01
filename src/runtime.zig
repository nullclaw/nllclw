const std = @import("std");
const agent = @import("./agent.zig");
const app_paths = @import("./app_paths.zig");
const config = @import("./config.zig");
const context = @import("./context.zig");
const diagnostics = @import("./diagnostics.zig");
const file_memory = @import("./adapters/file_memory.zig");
const heartbeat = @import("./heartbeat.zig");
const memory = @import("./memory.zig");
const persona = @import("./persona.zig");
const providers = @import("./providers.zig");
const runtime_completion = @import("./runtime/completion.zig");
const scheduler = @import("./scheduler.zig");
const std_http = @import("./adapters/std_http.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const TurnOptions = struct {
    schedule_destination: scheduler.Destination = .local,
};

pub const Runtime = struct {
    allocator: Allocator,
    io: Io,
    cfg: config.Owned,
    completion_target: providers.Resolved,
    http_client: std_http.Client,
    memory_store: ?file_memory.Store,
    memory_state: memory.State,
    context_prompt: []u8,
    system_prompt: []u8,

    pub fn init(allocator: Allocator, io: Io, env_map: *const std.process.Environ.Map) !Runtime {
        var loaded_config = try config.loadOwned(allocator, io, env_map);
        errdefer loaded_config.deinit(allocator);
        try fillDefaultStatePaths(allocator, env_map, &loaded_config.value);

        var completion_target = try resolveCompletionTarget(allocator, loaded_config.value.completion);
        errdefer completion_target.deinit(allocator);

        var http_client = std_http.Client.init(allocator, io);
        errdefer http_client.deinit();

        var memory_store: ?file_memory.Store = null;
        var memory_state: memory.State = .{};
        if (loaded_config.value.memory.enabled) {
            memory_store = .{ .io = io, .path = loaded_config.value.memory.path orelse return error.MissingHome };
            if (memory_store) |*store| {
                memory_state = try memory.loadState(allocator, loaded_config.value.memory, store.port());
            }
        }
        errdefer memory_state.deinit(allocator);

        const context_prompt = try context.loadSystemPrompt(allocator, io, agent.system_prompt);
        errdefer allocator.free(context_prompt);

        const system_prompt = try persona.buildPrompt(allocator, context_prompt, loaded_config.value.persona);
        errdefer allocator.free(system_prompt);

        return .{
            .allocator = allocator,
            .io = io,
            .cfg = loaded_config,
            .completion_target = completion_target,
            .http_client = http_client,
            .memory_store = memory_store,
            .memory_state = memory_state,
            .context_prompt = context_prompt,
            .system_prompt = system_prompt,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.allocator.free(self.system_prompt);
        self.allocator.free(self.context_prompt);
        self.memory_state.deinit(self.allocator);
        self.http_client.deinit();
        self.completion_target.deinit(self.allocator);
        self.cfg.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn complete(
        self: *Runtime,
        prompt: []const u8,
        stream_writer: ?*Io.Writer,
        diagnostic: *agent.Diagnostic,
    ) ![]u8 {
        return self.completeWithTurn(prompt, stream_writer, diagnostic, .{});
    }

    pub fn completeWithTurn(
        self: *Runtime,
        prompt: []const u8,
        stream_writer: ?*Io.Writer,
        diagnostic: *agent.Diagnostic,
        turn: TurnOptions,
    ) ![]u8 {
        var writer_sink: WriterStreamSink = undefined;
        const stream_sink: ?agent.StreamSink = if (stream_writer) |writer| sink: {
            writer_sink = .{ .writer = writer };
            break :sink writer_sink.sink();
        } else null;

        const text = try self.completeWithSink(prompt, stream_sink, diagnostic, turn);

        if (stream_writer) |writer| {
            const cfg = self.cfg.value;
            if (!cfg.stream or cfg.tools.enabled) try writer.writeAll(text);
            if (!std.mem.endsWith(u8, text, "\n")) try writer.writeByte('\n');
            try writer.flush();
        }
        return text;
    }

    pub fn completeWithSink(
        self: *Runtime,
        prompt: []const u8,
        stream_sink: ?agent.StreamSink,
        diagnostic: *agent.Diagnostic,
        turn: TurnOptions,
    ) ![]u8 {
        const cfg = self.cfg.value;
        if (cfg.tools.enabled) {
            return runtime_completion.withTools(
                self.allocator,
                self.io,
                self.http_client.httpClient(),
                self.completion_target,
                cfg,
                self.memory_state.history_messages,
                prompt,
                self.system_prompt,
                turn.schedule_destination,
                diagnostic,
            );
        }

        if (stream_sink) |sink| {
            if (!cfg.stream) {
                return runtime_completion.withoutStream(
                    self.allocator,
                    self.http_client.httpClient(),
                    self.completion_target,
                    cfg,
                    self.memory_state.history_messages,
                    prompt,
                    self.system_prompt,
                    diagnostic,
                );
            }
            return agent.completeResolvedWithOptions(
                self.allocator,
                self.http_client.httpClient(),
                self.completion_target,
                cfg.completion.model,
                cfg.completion.max_tokens,
                prompt,
                .{
                    .history = self.memory_state.history_messages,
                    .system_prompt = self.system_prompt,
                    .stream_sink = sink,
                },
                diagnostic,
            );
        }

        return runtime_completion.withoutStream(
            self.allocator,
            self.http_client.httpClient(),
            self.completion_target,
            cfg,
            self.memory_state.history_messages,
            prompt,
            self.system_prompt,
            diagnostic,
        );
    }

    pub fn completeAndRemember(
        self: *Runtime,
        prompt: []const u8,
        stream_writer: ?*Io.Writer,
        diagnostic: *agent.Diagnostic,
    ) ![]u8 {
        return self.completeAndRememberWithTurn(prompt, stream_writer, diagnostic, .{});
    }

    pub fn completeAndRememberWithTurn(
        self: *Runtime,
        prompt: []const u8,
        stream_writer: ?*Io.Writer,
        diagnostic: *agent.Diagnostic,
        turn: TurnOptions,
    ) ![]u8 {
        const text = try self.completeWithTurn(prompt, stream_writer, diagnostic, turn);
        errdefer self.allocator.free(text);
        try self.rememberTurn(prompt, text);
        return text;
    }

    pub fn rememberTurn(self: *Runtime, prompt: []const u8, text: []const u8) !void {
        try self.appendMemory(prompt, text);
        try self.reloadMemory();
    }

    pub fn appendMemory(self: *Runtime, prompt: []const u8, text: []const u8) !void {
        if (!self.cfg.value.memory.enabled) return;
        try memory.appendTurn(
            self.allocator,
            self.cfg.value.memory,
            (try self.memoryStore()).port(),
            prompt,
            text,
        );
    }

    pub fn reloadMemory(self: *Runtime) !void {
        if (!self.cfg.value.memory.enabled) {
            self.memory_state.deinit(self.allocator);
            self.memory_state = .{};
            return;
        }
        const next = try memory.loadState(self.allocator, self.cfg.value.memory, (try self.memoryStore()).port());
        self.memory_state.deinit(self.allocator);
        self.memory_state = next;
    }

    pub fn listMemoryFacts(self: *Runtime) !memory.Facts {
        var facts_store = try self.factStore();
        return facts_store.port().list(self.allocator, self.cfg.value.memory.max_facts);
    }

    pub fn getMemoryFact(self: *Runtime, key: []const u8) !?[]u8 {
        var facts_store = try self.factStore();
        return facts_store.port().get(self.allocator, key, self.cfg.value.memory.max_facts);
    }

    pub fn forgetMemoryFact(self: *Runtime, key: []const u8) !bool {
        var facts_store = try self.factStore();
        return facts_store.port().delete(self.allocator, key, self.cfg.value.memory.max_facts);
    }

    pub fn resetMemory(self: *Runtime) !void {
        try file_memory.clear(
            self.allocator,
            self.io,
            try self.memoryPath(),
        );
        try file_memory.clear(
            self.allocator,
            self.io,
            try self.factsPath(),
        );
        try self.reloadMemory();
    }

    pub fn listSchedules(self: *Runtime) ![]u8 {
        return scheduler.listText(
            self.allocator,
            self.io,
            try self.schedulePath(),
            self.cfg.value.tools.output_max_bytes,
        );
    }

    pub fn deleteSchedule(self: *Runtime, id: u32) !bool {
        return scheduler.delete(
            self.allocator,
            self.io,
            try self.schedulePath(),
            id,
        );
    }

    pub fn claimDueSchedules(self: *Runtime) !scheduler.DueTasks {
        return scheduler.claimDue(
            self.allocator,
            self.io,
            try self.schedulePath(),
            scheduler.currentUnixSeconds(self.io),
            scheduler.default_lease_seconds,
        );
    }

    pub fn commitDueSchedule(self: *Runtime, task: scheduler.DueTask) !bool {
        return scheduler.commitDue(
            self.allocator,
            self.io,
            try self.schedulePath(),
            task.id,
            task.lease_until,
            scheduler.currentUnixSeconds(self.io),
        );
    }

    pub fn now(self: *Runtime) i64 {
        return scheduler.currentUnixSeconds(self.io);
    }

    pub fn statusText(self: *Runtime, scope: diagnostics.Scope) ![]u8 {
        return diagnostics.format(
            self.allocator,
            self.cfg.value,
            self.memory_state.transcript.entries.len,
            scope,
            self.now(),
        );
    }

    pub fn setPersona(self: *Runtime, kind: persona.Kind) !void {
        const next_prompt = try persona.buildPrompt(self.allocator, self.context_prompt, kind);
        self.allocator.free(self.system_prompt);
        self.system_prompt = next_prompt;
        self.cfg.value.persona = kind;
    }

    pub fn personaName(self: *const Runtime) []const u8 {
        return @tagName(self.cfg.value.persona);
    }

    pub fn heartbeatPrompt(self: *Runtime) !?[]u8 {
        return heartbeat.loadPrompt(self.allocator, self.io);
    }

    pub fn runHeartbeat(self: *Runtime, writer: *Io.Writer, diagnostic: *agent.Diagnostic) !usize {
        const prompt = try self.heartbeatPrompt() orelse {
            try writer.writeAll("nllclw: no pending heartbeat tasks\n");
            try writer.flush();
            return 0;
        };
        defer self.allocator.free(prompt);

        const text = try self.complete(prompt, writer, diagnostic);
        defer self.allocator.free(text);
        try self.rememberTurn(prompt, text);
        return 1;
    }

    fn memoryStore(self: *Runtime) !*file_memory.Store {
        return if (self.memory_store) |*store| store else error.MissingHome;
    }

    fn factStore(self: *Runtime) !file_memory.FactStore {
        return .{
            .io = self.io,
            .path = try self.factsPath(),
        };
    }

    fn memoryPath(self: *Runtime) ![]const u8 {
        return self.cfg.value.memory.path orelse error.MissingHome;
    }

    fn factsPath(self: *Runtime) ![]const u8 {
        return self.cfg.value.memory.facts_path orelse error.MissingHome;
    }

    fn schedulePath(self: *Runtime) ![]const u8 {
        return self.cfg.value.schedule.path orelse error.MissingHome;
    }
};

fn fillDefaultStatePaths(
    allocator: Allocator,
    env_map: *const std.process.Environ.Map,
    cfg: *config.RuntimeConfig,
) !void {
    const state_dir = app_paths.stateDir(allocator, env_map) catch |err| switch (err) {
        error.MissingHome => null,
        else => return err,
    };
    defer if (state_dir) |dir| allocator.free(dir);

    var memory_path: ?[]u8 = null;
    errdefer if (memory_path) |path| allocator.free(path);
    if (cfg.memory.enabled) {
        memory_path = try pathInStateDir(allocator, state_dir, cfg.memory.path orelse "memory.jsonl");
    }

    var facts_path: ?[]u8 = null;
    errdefer if (facts_path) |path| allocator.free(path);
    if (cfg.memory.enabled) {
        facts_path = try pathInStateDir(allocator, state_dir, cfg.memory.facts_path orelse "facts.jsonl");
    }

    var user_tools_path: ?[]u8 = null;
    errdefer if (user_tools_path) |path| allocator.free(path);
    if (cfg.tools.enabled) {
        user_tools_path = try pathInStateDir(allocator, state_dir, cfg.tools.user_tools_path orelse "user-tools.jsonl");
    }

    var schedule_path: ?[]u8 = null;
    errdefer if (schedule_path) |path| allocator.free(path);
    if (cfg.tools.schedule_enabled) {
        if (state_dir) |dir| {
            schedule_path = try app_paths.pathInDir(allocator, dir, cfg.schedule.path orelse "schedule.jsonl");
        } else if (cfg.tools.enabled) {
            return error.MissingHome;
        }
    }

    replaceOwnedPath(allocator, &cfg.memory.path, memory_path);
    replaceOwnedPath(allocator, &cfg.memory.facts_path, facts_path);
    replaceOwnedPath(allocator, &cfg.tools.user_tools_path, user_tools_path);
    replaceOwnedPath(allocator, &cfg.schedule.path, schedule_path);
}

fn pathInStateDir(allocator: Allocator, state_dir: ?[]const u8, path: []const u8) ![]u8 {
    return app_paths.pathInDir(allocator, state_dir orelse return error.MissingHome, path);
}

fn replaceOwnedPath(allocator: Allocator, slot: *?[]const u8, replacement: ?[]u8) void {
    const path = replacement orelse return;
    if (slot.*) |old| allocator.free(old);
    slot.* = path;
}

fn resolveCompletionTarget(allocator: Allocator, cfg: config.Config) !providers.Resolved {
    return providers.resolve(allocator, .{
        .provider = cfg.provider,
        .api_key = cfg.api_key,
        .base_url = cfg.base_url,
        .allow_insecure_base_url = cfg.allow_insecure_base_url,
        .http_referer = cfg.http_referer,
        .app_title = cfg.app_title,
    });
}

test "runtime default state paths live under user state directory for enabled features" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_STATE_HOME", "/tmp/state-root");

    var cfg: config.RuntimeConfig = .{
        .completion = .{
            .provider = .openai,
            .api_key = "key",
            .model = "model",
        },
    };
    try fillDefaultStatePaths(std.testing.allocator, &map, &cfg);
    defer {
        std.testing.allocator.free(cfg.memory.path.?);
        std.testing.allocator.free(cfg.memory.facts_path.?);
        std.testing.allocator.free(cfg.tools.user_tools_path.?);
        std.testing.allocator.free(cfg.schedule.path.?);
    }

    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "memory.jsonl" }, cfg.memory.path.?);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "facts.jsonl" }, cfg.memory.facts_path.?);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "user-tools.jsonl" }, cfg.tools.user_tools_path.?);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "schedule.jsonl" }, cfg.schedule.path.?);
}

test "runtime default state paths are not required for disabled stateful features" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    var cfg: config.RuntimeConfig = .{
        .completion = .{
            .provider = .openai,
            .api_key = "key",
            .model = "model",
        },
        .memory = .{ .enabled = false },
        .tools = .{ .enabled = false },
    };
    try fillDefaultStatePaths(std.testing.allocator, &map, &cfg);

    try std.testing.expect(cfg.memory.path == null);
    try std.testing.expect(cfg.memory.facts_path == null);
    try std.testing.expect(cfg.tools.user_tools_path == null);
    try std.testing.expect(cfg.schedule.path == null);
}

test "runtime schedule path remains available when tool loop is disabled" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_STATE_HOME", "/tmp/state-root");

    var cfg: config.RuntimeConfig = .{
        .completion = .{
            .provider = .openai,
            .api_key = "key",
            .model = "model",
        },
        .memory = .{ .enabled = false },
        .tools = .{ .enabled = false },
    };
    try fillDefaultStatePaths(std.testing.allocator, &map, &cfg);
    defer std.testing.allocator.free(cfg.schedule.path.?);

    try std.testing.expect(cfg.memory.path == null);
    try std.testing.expect(cfg.tools.user_tools_path == null);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "schedule.jsonl" }, cfg.schedule.path.?);
}

test "runtime configured state paths are rooted under user state directory" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_STATE_HOME", "/tmp/state-root");

    var cfg: config.RuntimeConfig = .{
        .completion = .{
            .provider = .openai,
            .api_key = "key",
            .model = "model",
        },
        .memory = .{
            .path = try std.testing.allocator.dupe(u8, "custom/memory.jsonl"),
            .facts_path = try std.testing.allocator.dupe(u8, "custom/facts.jsonl"),
        },
        .tools = .{
            .user_tools_path = try std.testing.allocator.dupe(u8, "custom/user-tools.jsonl"),
        },
        .schedule = .{
            .path = try std.testing.allocator.dupe(u8, "custom/schedule.jsonl"),
        },
    };

    try fillDefaultStatePaths(std.testing.allocator, &map, &cfg);
    defer {
        std.testing.allocator.free(cfg.memory.path.?);
        std.testing.allocator.free(cfg.memory.facts_path.?);
        std.testing.allocator.free(cfg.tools.user_tools_path.?);
        std.testing.allocator.free(cfg.schedule.path.?);
    }

    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "custom/memory.jsonl" }, cfg.memory.path.?);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "custom/facts.jsonl" }, cfg.memory.facts_path.?);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "custom/user-tools.jsonl" }, cfg.tools.user_tools_path.?);
    try expectJoinedPath(&.{ "/tmp/state-root", "nllclw", "custom/schedule.jsonl" }, cfg.schedule.path.?);
}

fn expectJoinedPath(parts: []const []const u8, actual: []const u8) !void {
    const expected = try std.fs.path.join(std.testing.allocator, parts);
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}

const WriterStreamSink = struct {
    writer: *Io.Writer,

    fn sink(self: *WriterStreamSink) agent.StreamSink {
        return .{
            .ptr = self,
            .write_fn = write,
        };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) agent.StreamError!void {
        const self: *WriterStreamSink = @ptrCast(@alignCast(ptr));
        try self.writer.writeAll(bytes);
        try self.writer.flush();
    }
};
