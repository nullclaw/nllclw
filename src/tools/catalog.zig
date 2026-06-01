const std = @import("std");
const agent = @import("../agent.zig");
const build_options = @import("build_options");
const config = @import("../config.zig");
const http = @import("../ports/http.zig");
const memory = @import("../memory.zig");
const diagnostics_tool = @import("./diagnostics.zig");
const filesystem_tool = @import("./filesystem.zig");
const macro_tool = @import("./macros.zig");
const memory_tool = @import("./memory.zig");
const registry = @import("./registry.zig");
const scheduler = @import("../scheduler.zig");
const scheduler_tool = @import("./scheduler.zig");
const shell_tool = if (build_options.shell_tool) @import("./shell.zig") else void;
const time_tool = @import("./time.zig");
const web_tool = @import("./web.zig");

const Io = std.Io;

const base_handler_capacity = 17 + macro_tool.max_tools;
pub const max_handlers = base_handler_capacity + if (build_options.shell_tool) 1 else 0;
pub const OptionsError = error{ToolCatalogFull};
const ShellClient = if (build_options.shell_tool) shell_tool.Client else void;

pub const Catalog = struct {
    tools_cfg: config.ToolsConfig,
    memory_cfg: config.MemoryConfig,
    filesystem_client: filesystem_tool.Client,
    macro_client: ?macro_tool.Client,
    memory_client: ?memory_tool.Client,
    time_client: time_tool.Client,
    web_client: web_tool.Client,
    scheduler_client: ?scheduler_tool.Client,
    diagnostics_client: diagnostics_tool.Client,
    shell_client: ShellClient,
    handlers: [max_handlers]registry.Handler = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        io: Io,
        client: http.Client,
        cfg: config.RuntimeConfig,
        facts: ?memory.FactStore,
        schedule_path: ?[]const u8,
        schedule_destination: scheduler.Destination,
        history_count: usize,
    ) !Catalog {
        return .{
            .tools_cfg = cfg.tools,
            .memory_cfg = cfg.memory,
            .filesystem_client = filesystem_tool.Client.init(io, cfg.tools.output_max_bytes),
            .macro_client = if (cfg.tools.enabled) try macro_tool.Client.init(
                allocator,
                io,
                cfg.tools.user_tools_path orelse return error.MissingHome,
                cfg.tools.output_max_bytes,
            ) else null,
            .memory_client = if (cfg.tools.enabled and cfg.memory.enabled) memory_tool.Client.init(
                facts orelse return error.MissingHome,
                cfg.memory.max_facts,
                cfg.tools.output_max_bytes,
            ) else null,
            .time_client = time_tool.Client.init(io, cfg.timezone_offset_minutes, cfg.tools.output_max_bytes),
            .web_client = web_tool.Client.init(client, cfg.search, cfg.tools.output_max_bytes),
            .scheduler_client = if (cfg.tools.enabled and cfg.tools.schedule_enabled) scheduler_tool.Client.init(
                io,
                schedule_path orelse return error.MissingHome,
                cfg.tools.output_max_bytes,
                cfg.timezone_offset_minutes,
                schedule_destination,
            ) else null,
            .diagnostics_client = diagnostics_tool.Client.initCount(io, cfg, history_count),
            .shell_client = if (comptime build_options.shell_tool) shell_tool.Client.init(
                io,
                cfg.tools.output_max_bytes,
                cfg.tools.timeout_ms,
            ) else {},
        };
    }

    pub fn deinit(self: *Catalog, allocator: std.mem.Allocator) void {
        if (self.macro_client) |*macro_client| macro_client.deinit(allocator);
        self.* = undefined;
    }

    pub fn options(self: *Catalog) OptionsError!agent.ToolOptions {
        if (!self.tools_cfg.enabled) return .{};

        var count: usize = 0;
        if (self.tools_cfg.file_read_enabled) {
            try self.appendHandler(&count, self.filesystem_client.listDirHandler());
            try self.appendHandler(&count, self.filesystem_client.readFileHandler());
        }

        if (self.tools_cfg.file_write_enabled) {
            try self.appendHandler(&count, self.filesystem_client.writeFileHandler());
            try self.appendHandler(&count, self.filesystem_client.editFileHandler());
        }

        if (self.memory_cfg.enabled) {
            const memory_client = &self.memory_client.?;
            try self.appendHandler(&count, memory_client.storeHandler());
            try self.appendHandler(&count, memory_client.recallHandler());
            try self.appendHandler(&count, memory_client.listHandler());
            try self.appendHandler(&count, memory_client.forgetHandler());
        }

        try self.appendHandler(&count, self.time_client.handler());
        const macro_client = &self.macro_client.?;
        try self.appendHandler(&count, macro_client.createHandler());
        try self.appendHandler(&count, macro_client.listHandler());
        try self.appendHandler(&count, macro_client.deleteHandler());
        for (0..macro_client.entries.items.len) |index| {
            try self.appendHandler(&count, macro_client.dynamicHandler(index));
        }

        if (self.web_client.configured()) try self.appendHandler(&count, self.web_client.handler());
        if (self.tools_cfg.schedule_enabled) {
            const scheduler_client = &self.scheduler_client.?;
            try self.appendHandler(&count, scheduler_client.setHandler());
            try self.appendHandler(&count, scheduler_client.listHandler());
            try self.appendHandler(&count, scheduler_client.deleteHandler());
        }
        try self.appendHandler(&count, self.diagnostics_client.handler());

        if (comptime build_options.shell_tool) {
            if (self.tools_cfg.shell_enabled) {
                try self.appendHandler(&count, self.shell_client.handler());
            }
        }

        return .{
            .enabled = true,
            .max_rounds = self.tools_cfg.max_rounds,
            .handlers = self.handlers[0..count],
        };
    }

    fn appendHandler(self: *Catalog, count: *usize, handler: registry.Handler) OptionsError!void {
        if (count.* >= self.handlers.len) return error.ToolCatalogFull;
        self.handlers[count.*] = handler;
        count.* += 1;
    }
};

test "catalog keeps tools disabled when config is off" {
    var catalog = try Catalog.init(
        std.testing.allocator,
        std.testing.io,
        .{ .ptr = undefined, .post_json = undefined },
        .{
            .completion = .{
                .provider = .openai,
                .api_key = "key",
                .model = "model",
            },
            .tools = .{ .enabled = false },
        },
        null,
        null,
        .local,
        0,
    );
    defer catalog.deinit(std.testing.allocator);
    const options = try catalog.options();
    try std.testing.expect(!options.enabled);
    try std.testing.expectEqual(@as(usize, 0), options.handlers.len);
}

test "catalog exposes baseline non-mutating tools" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const user_tools_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(user_tools_path);

    var catalog = try Catalog.init(
        std.testing.allocator,
        io,
        .{ .ptr = undefined, .post_json = undefined },
        .{
            .completion = .{
                .provider = .openai,
                .api_key = "key",
                .model = "model",
            },
            .tools = .{
                .enabled = true,
                .file_read_enabled = false,
                .file_write_enabled = false,
                .schedule_enabled = false,
                .user_tools_path = user_tools_path,
            },
            .memory = .{ .enabled = false },
        },
        null,
        null,
        .local,
        0,
    );
    defer catalog.deinit(std.testing.allocator);
    const options = try catalog.options();
    try std.testing.expect(options.enabled);
    try std.testing.expectEqual(@as(usize, 5), options.handlers.len);
    try std.testing.expectEqualStrings("get_time", options.handlers[0].definition.name);
    try std.testing.expectEqualStrings("create_tool", options.handlers[1].definition.name);
    try std.testing.expectEqualStrings("list_user_tools", options.handlers[2].definition.name);
    try std.testing.expectEqualStrings("delete_user_tool", options.handlers[3].definition.name);
    try std.testing.expectEqualStrings("get_diagnostics", options.handlers[4].definition.name);
}

test "catalog exposes web search only when configured" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const user_tools_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(user_tools_path);

    var catalog = try Catalog.init(
        std.testing.allocator,
        io,
        .{ .ptr = undefined, .post_json = undefined },
        .{
            .completion = .{
                .provider = .openai,
                .api_key = "key",
                .model = "model",
            },
            .tools = .{
                .enabled = true,
                .file_read_enabled = false,
                .file_write_enabled = false,
                .schedule_enabled = false,
                .user_tools_path = user_tools_path,
            },
            .memory = .{ .enabled = false },
            .search = .{ .tavily_key = "tvly" },
        },
        null,
        null,
        .local,
        0,
    );
    defer catalog.deinit(std.testing.allocator);
    const options = try catalog.options();
    try std.testing.expectEqual(@as(usize, 6), options.handlers.len);
}

test "catalog exposes local filesystem and scheduler tools by default" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const user_tools_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(user_tools_path);
    const schedule_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(schedule_path);

    var catalog = try Catalog.init(
        std.testing.allocator,
        io,
        .{ .ptr = undefined, .post_json = undefined },
        .{
            .completion = .{
                .provider = .openai,
                .api_key = "key",
                .model = "model",
            },
            .tools = .{ .user_tools_path = user_tools_path },
            .memory = .{ .enabled = false },
        },
        null,
        schedule_path,
        .local,
        0,
    );
    defer catalog.deinit(std.testing.allocator);
    const options = try catalog.options();
    try std.testing.expectEqual(@as(usize, 12), options.handlers.len);
    const names = [_][]const u8{
        "list_dir",
        "read_file",
        "write_file",
        "edit_file",
        "get_time",
        "create_tool",
        "list_user_tools",
        "delete_user_tool",
        "cron_set",
        "cron_list",
        "cron_delete",
        "get_diagnostics",
    };
    for (names, options.handlers) |expected, handler| {
        try std.testing.expectEqualStrings(expected, handler.definition.name);
    }
}

test "catalog handler names stay reserved for user macro tools" {
    const fake_facts: memory.FactStore = .{
        .ptr = undefined,
        .put_fn = undefined,
        .get_fn = undefined,
        .list_fn = undefined,
        .delete_fn = undefined,
    };

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const user_tools_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(user_tools_path);
    const schedule_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(schedule_path);

    var catalog = try Catalog.init(
        std.testing.allocator,
        io,
        .{ .ptr = undefined, .post_json = undefined },
        .{
            .completion = .{
                .provider = .openai,
                .api_key = "key",
                .model = "model",
            },
            .tools = .{
                .user_tools_path = user_tools_path,
                .shell_enabled = true,
            },
            .search = .{ .tavily_key = "tvly" },
        },
        fake_facts,
        schedule_path,
        .local,
        0,
    );
    defer catalog.deinit(std.testing.allocator);

    const options = try catalog.options();
    for (options.handlers) |handler| {
        try std.testing.expectError(error.InvalidUserToolName, macro_tool.create(io, user_tools_path, std.testing.allocator, .{
            .name = handler.definition.name,
            .description = "Reserved name",
            .action = "Do reserved work",
        }));
    }
}
