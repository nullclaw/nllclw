const std = @import("std");
const agent = @import("../agent.zig");
const build_options = @import("build_options");
const channel_error = @import("./errors.zig");
const local = @import("./local.zig");
const repl = @import("./repl.zig");
const runtime = @import("../runtime.zig");
const setup = @import("../setup.zig");
const slash = @import("./slash.zig");
const telegram = @import("./telegram.zig");
const websocket = @import("./websocket.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_prompt_bytes = 64 * 1024;

pub const usage = usage_prefix ++ shell_usage ++ usage_suffix;

const usage_prefix =
    \\usage:
    \\  nllclw
    \\  nllclw init [--env] [--force]
    \\  nllclw uninstall [--force]
    \\  nllclw status
    \\  nllclw doctor
    \\  nllclw memory list|get|forget|reset
    \\  nllclw schedule list|delete
    \\  nllclw heartbeat
    \\  nllclw daemon
    \\  nllclw telegram
    \\  nllclw websocket
    \\  nllclw "your prompt"
    \\  echo "your prompt" | nllclw
    \\
    \\interactive:
    \\  With no prompt and a TTY stdin, nllclw opens a small chat loop.
    \\  Use :q, :quit, or exit to quit.
    \\
    \\config:
    \\  Run nllclw init to create user config outside the working directory.
    \\  OS env overrides config.json, which overrides .env in the user config dir.
    \\  NLLCLW_PROVIDER=openai|openrouter|compatible
    \\  NLLCLW_API_KEY=...
    \\  NLLCLW_MODEL=...
    \\  NLLCLW_MAX_TOKENS=...    optional output cap
    \\  NLLCLW_BASE_URL=...        required for compatible
    \\  NLLCLW_HTTP_REFERER=...    optional for OpenRouter
    \\  NLLCLW_APP_TITLE=...       optional for OpenRouter
    \\  NLLCLW_ALLOW_HTTP_BASE_URL=on|off default off; compatible localhost only
    \\  NLLCLW_PERSONA=neutral|friendly|technical|witty default neutral
    \\  NLLCLW_STREAM=on|off       default on; tool mode is non-streaming
    \\  NLLCLW_MEMORY=on|off       default on
    \\  NLLCLW_MEMORY_PATH=...     default user state dir
    \\  NLLCLW_MEMORY_MAX_MESSAGES=20
    \\  NLLCLW_MEMORY_FACTS_PATH=... default user state dir
    \\  NLLCLW_MEMORY_MAX_FACTS=64
    \\  NLLCLW_TOOLS=on|off        default on; enables local tools
    \\  NLLCLW_TOOL_MAX_ROUNDS=4
    \\  NLLCLW_TOOL_OUTPUT_MAX_BYTES=8192
    \\  NLLCLW_FILE_READ=on|off    default on; enables list_dir/read_file
    \\  NLLCLW_FILE_WRITE=on|off   default on; enables write_file/edit_file
    \\  NLLCLW_SCHEDULE_TOOLS=on|off default on; enables cron_* tools
    \\  NLLCLW_USER_TOOLS_PATH=... default user state dir
    \\  NLLCLW_SEARCH_PROVIDER=auto|tavily|brave|exa|firecrawl|duckduckgo
    \\  NLLCLW_SEARCH_TAVILY_KEY=... optional web_search key
    \\  NLLCLW_SEARCH_BRAVE_KEY=...  optional web_search key
    \\  NLLCLW_SEARCH_EXA_KEY=...    optional web_search key
    \\  NLLCLW_SEARCH_FIRECRAWL_KEY=... optional web_search key
    \\  NLLCLW_SEARCH_DUCKDUCKGO=on|off default off; no-key instant answer fallback
    \\  NLLCLW_SCHEDULE_PATH=...    default user state dir
    \\  NLLCLW_DAEMON_INTERVAL_SECONDS=60
    \\  NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
    \\  NLLCLW_TIMEZONE_OFFSET_MINUTES=0
    \\
;

const shell_usage = if (build_options.shell_tool)
    \\  NLLCLW_SHELL=on|off        default off; enables shell_exec
    \\  NLLCLW_TOOL_TIMEOUT_MS=5000
    \\
else
    "";

const usage_suffix =
    \\telegram:
    \\  NLLCLW_TELEGRAM_TOKEN=... required for nllclw telegram
    \\  NLLCLW_TELEGRAM_CHAT_ID=... required allowlist
    \\  NLLCLW_TELEGRAM_POLL_TIMEOUT=20
    \\  NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20 (0 disables)
    \\
    \\websocket:
    \\  NLLCLW_WS_HOST=127.0.0.1
    \\  NLLCLW_WS_PORT=8765
    \\  NLLCLW_WS_PATH=/ws
    \\  NLLCLW_WS_TOKEN=... required for nllclw websocket
    \\  NLLCLW_WS_ALLOW_REMOTE=on|off default off
    \\  NLLCLW_WS_RATE_LIMIT_PER_MINUTE=20 (0 disables)
    \\
;

pub fn run(init: std.process.Init.Minimal) noreturn {
    const code = runMinimal(init) catch |err| code: {
        channel_error.printTopLevel(err);
        break :code 1;
    };
    std.process.exit(code);
}

fn runMinimal(init: std.process.Init.Minimal) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    const args = try init.args.toSlice(allocator);
    if (args.len > 1 and isHelp(args[1])) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_file_writer: Io.File.Writer = .init(.stdout(), Io.Threaded.global_single_threaded.io(), &stdout_buffer);
        const stdout = &stdout_file_writer.interface;
        try writeUsage(stdout);
        try stdout.flush();
        return 0;
    }

    var threaded: Io.Threaded = .init(std.heap.page_allocator, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();

    var env_map = try std.process.Environ.createMap(init.environ, allocator);
    defer env_map.deinit();

    return runWithIo(allocator, io, &env_map, args);
}

fn runWithIo(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len > 1 and isHelp(args[1])) {
        try writeUsage(stdout);
        try stdout.flush();
        return 0;
    }

    if (args.len > 1 and telegram.isCommand(args[1])) {
        if (subcommandHelp(args)) {
            try writeUsage(stdout);
            try stdout.flush();
            return 0;
        }
        if (subcommandWithExtraArgs(args)) |command| {
            try stderr.print("nllclw: usage: nllclw {s}\n", .{command});
            try stderr.flush();
            return 2;
        }
        return telegram.run(std.heap.page_allocator, io, env_map, stderr, usage);
    }

    if (args.len > 1 and websocket.isCommand(args[1])) {
        if (subcommandHelp(args)) {
            try writeUsage(stdout);
            try stdout.flush();
            return 0;
        }
        if (subcommandWithExtraArgs(args)) |command| {
            try stderr.print("nllclw: usage: nllclw {s}\n", .{command});
            try stderr.flush();
            return 2;
        }
        return websocket.run(std.heap.page_allocator, io, env_map, stderr, usage);
    }

    if (args.len > 1 and setup.isCommand(args[1])) {
        return setup.run(allocator, io, env_map, args, stdout, stderr);
    }

    if (args.len > 1 and local.isCommand(args[1])) {
        return local.run(allocator, io, env_map, args, stdout, stderr);
    }

    if (args.len <= 1 and try Io.File.stdin().isTty(io)) {
        return repl.run(std.heap.page_allocator, io, env_map, stdout, stderr, usage);
    }

    return runDirect(allocator, io, env_map, args, stdout, stderr);
}

fn runDirect(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const prompt = try readPrompt(io, allocator, args);
    defer allocator.free(prompt);
    if (std.mem.trim(u8, prompt, &std.ascii.whitespace).len == 0) {
        try writeUsage(stderr);
        try stderr.flush();
        return 2;
    }
    if (try slash.runStateless(prompt, stdout)) |code| return code;

    var app_runtime = runtime.Runtime.init(allocator, io, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try writeUsage(stderr);
        try stderr.flush();
        return 2;
    };
    defer app_runtime.deinit();

    if (try slash.run(allocator, &app_runtime, prompt, stdout)) |code| return code;

    var diagnostic: agent.Diagnostic = .{};
    defer diagnostic.deinit(allocator);

    const text = app_runtime.complete(prompt, stdout, &diagnostic) catch |err| {
        try channel_error.printAppErrorWriter(stderr, err, diagnostic);
        try stderr.flush();
        return 1;
    };
    defer allocator.free(text);

    app_runtime.rememberTurn(prompt, text) catch |err| {
        try stderr.print("nllclw: warning: failed to update memory: {s}\n", .{@errorName(err)});
        try stderr.flush();
    };
    return 0;
}

fn readPrompt(io: Io, allocator: Allocator, args: []const [:0]const u8) ![]u8 {
    if (args.len > 1) return try promptFromArgs(allocator, args);

    const stdin = Io.File.stdin();
    if (try stdin.isTty(io)) return try allocator.dupe(u8, "");

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = stdin.reader(io, &stdin_buffer);
    return stdin_reader.interface.allocRemaining(allocator, .limited(max_prompt_bytes));
}

pub fn promptFromArgs(allocator: Allocator, args: []const [:0]const u8) ![]u8 {
    if (args.len <= 1) return allocator.dupe(u8, "");

    var total: usize = 0;
    for (args[1..], 0..) |arg, index| {
        if (index != 0) total = std.math.add(usize, total, 1) catch return error.StreamTooLong;
        total = std.math.add(usize, total, arg.len) catch return error.StreamTooLong;
        if (total > max_prompt_bytes) return error.StreamTooLong;
    }

    const prompt = try allocator.alloc(u8, total);
    var offset: usize = 0;
    for (args[1..], 0..) |arg, index| {
        if (index != 0) {
            prompt[offset] = ' ';
            offset += 1;
        }
        @memcpy(prompt[offset..][0..arg.len], arg);
        offset += arg.len;
    }
    return prompt;
}

pub fn writeUsage(writer: *Io.Writer) !void {
    try writer.writeAll(usage);
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help");
}

fn subcommandHelp(args: []const [:0]const u8) bool {
    return args.len == 3 and isHelp(args[2]);
}

fn subcommandWithExtraArgs(args: []const [:0]const u8) ?[]const u8 {
    if (args.len <= 2 or subcommandHelp(args)) return null;
    return args[1];
}

test "promptFromArgs joins all prompt arguments" {
    const args: []const [:0]const u8 = &.{ "nllclw", "hello", "zig" };
    const prompt = try promptFromArgs(std.testing.allocator, args);
    defer std.testing.allocator.free(prompt);
    try std.testing.expectEqualStrings("hello zig", prompt);
}

test "promptFromArgs enforces the same cap as stdin prompts" {
    const capped_arg = try std.testing.allocator.allocSentinel(u8, max_prompt_bytes, 0);
    defer std.testing.allocator.free(capped_arg);
    @memset(capped_arg, 'a');
    const args: []const [:0]const u8 = &.{ "nllclw", capped_arg };

    const capped = try promptFromArgs(std.testing.allocator, args);
    defer std.testing.allocator.free(capped);
    try std.testing.expectEqual(@as(usize, max_prompt_bytes), capped.len);

    const too_long_arg = try std.testing.allocator.allocSentinel(u8, max_prompt_bytes + 1, 0);
    defer std.testing.allocator.free(too_long_arg);
    @memset(too_long_arg, 'a');
    const too_long_args: []const [:0]const u8 = &.{ "nllclw", too_long_arg };
    try std.testing.expectError(error.StreamTooLong, promptFromArgs(std.testing.allocator, too_long_args));
}

test "long-running channel commands reject extra argv before runtime init" {
    const telegram_extra: []const [:0]const u8 = &.{ "nllclw", "telegram", "extra" };
    try std.testing.expectEqualStrings("telegram", subcommandWithExtraArgs(telegram_extra).?);

    const telegram_help: []const [:0]const u8 = &.{ "nllclw", "telegram", "--help" };
    try std.testing.expect(subcommandHelp(telegram_help));
    try std.testing.expect(subcommandWithExtraArgs(telegram_help) == null);

    const websocket_help_extra: []const [:0]const u8 = &.{ "nllclw", "websocket", "--help", "extra" };
    try std.testing.expect(!subcommandHelp(websocket_help_extra));
    try std.testing.expectEqualStrings("websocket", subcommandWithExtraArgs(websocket_help_extra).?);
}

test "usage mentions init user config and required config vars" {
    try std.testing.expect(std.mem.indexOf(u8, usage, "nllclw init") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "nllclw uninstall") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "config.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, ".env") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_PROVIDER") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_API_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_MODEL") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_MAX_TOKENS") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_PERSONA") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_STREAM") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_MEMORY") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_MEMORY_FACTS_PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_TOOLS") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_ALLOW_HTTP_BASE_URL") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_FILE_READ") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_FILE_WRITE") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SCHEDULE_TOOLS") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_USER_TOOLS_PATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SEARCH_PROVIDER") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SEARCH_TAVILY_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SEARCH_BRAVE_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SEARCH_EXA_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SEARCH_FIRECRAWL_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_SEARCH_DUCKDUCKGO") != null);
    try std.testing.expectEqual(
        build_options.shell_tool,
        std.mem.indexOf(u8, usage, "NLLCLW_SHELL") != null,
    );
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_TELEGRAM_TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_TELEGRAM_CHAT_ID") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "nllclw websocket") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_WS_HOST") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "NLLCLW_WS_TOKEN") != null);
}
