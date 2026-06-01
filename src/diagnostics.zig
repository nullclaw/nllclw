const std = @import("std");
const build_options = @import("build_options");
const config = @import("./config.zig");
const search_mod = @import("./search.zig");

const Allocator = std.mem.Allocator;

pub const Scope = enum {
    quick,
    runtime,
    memory,
    rates,
    time,
    all,
};

pub fn parseScopeName(value: []const u8) ?Scope {
    const name = std.mem.trim(u8, value, &std.ascii.whitespace);
    if (std.mem.eql(u8, name, "quick")) return .quick;
    if (std.mem.eql(u8, name, "runtime")) return .runtime;
    if (std.mem.eql(u8, name, "memory")) return .memory;
    if (std.mem.eql(u8, name, "rates")) return .rates;
    if (std.mem.eql(u8, name, "time")) return .time;
    if (std.mem.eql(u8, name, "all")) return .all;
    return null;
}

pub fn format(
    allocator: Allocator,
    cfg: config.RuntimeConfig,
    history_count: usize,
    scope: Scope,
    now_seconds: i64,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;

    if (scope == .quick or scope == .all) {
        try writer.print(
            "nllclw: ok provider={s} model={s} persona={s} tools={s} memory={s}\n",
            .{
                @tagName(cfg.completion.provider),
                cfg.completion.model,
                @tagName(cfg.persona),
                onOff(cfg.tools.enabled),
                onOff(cfg.memory.enabled),
            },
        );
    }
    if (scope == .runtime or scope == .all) {
        try writer.print(
            "runtime:\n- persona={s}\n- stream={s}\n- shell_tool_built={s}\n- shell_enabled={s}\n- file_read={s}\n- file_write={s}\n- schedule_tools={s}\n- web_search_provider={s}\n- web_search_configured={s}\n",
            .{
                @tagName(cfg.persona),
                onOff(cfg.stream),
                onOff(build_options.shell_tool),
                onOff(cfg.tools.shell_enabled),
                onOff(cfg.tools.file_read_enabled),
                onOff(cfg.tools.file_write_enabled),
                onOff(cfg.tools.schedule_enabled),
                @tagName(cfg.search.provider),
                onOff(searchConfigured(cfg.search)),
            },
        );
    }
    if (scope == .memory or scope == .all) {
        try writer.print(
            "memory:\n- transcript_path={s}\n- transcript_messages={d}\n- facts_path={s}\n- max_facts={d}\n",
            .{
                pathLabel(cfg.memory.path, cfg.memory.enabled),
                history_count,
                pathLabel(cfg.memory.facts_path, cfg.memory.enabled),
                cfg.memory.max_facts,
            },
        );
    }
    if (scope == .rates or scope == .all) {
        try writer.print(
            "rates:\n- tool_max_rounds={d}\n- tool_output_max_bytes={d}\n- telegram_poll_timeout_seconds={d}\n- websocket_rate_limit_per_minute={d}\n",
            .{
                cfg.tools.max_rounds,
                cfg.tools.output_max_bytes,
                cfg.telegram.poll_timeout_seconds,
                cfg.websocket.rate_limit_per_minute,
            },
        );
    }
    if (scope == .time or scope == .all) {
        try writer.print(
            "time:\n- unix_seconds={d}\n- timezone_offset_minutes={d}\n- daemon_interval_seconds={d}\n- heartbeat_interval_seconds={d}\n- schedule_path={s}\n",
            .{
                now_seconds,
                cfg.timezone_offset_minutes,
                cfg.schedule.daemon_interval_seconds,
                cfg.schedule.heartbeat_interval_seconds,
                pathLabel(cfg.schedule.path, cfg.tools.enabled and cfg.tools.schedule_enabled),
            },
        );
    }
    return out.toOwnedSlice();
}

fn onOff(value: bool) []const u8 {
    return if (value) "on" else "off";
}

fn pathLabel(path: ?[]const u8, enabled: bool) []const u8 {
    return path orelse if (enabled) "(unresolved)" else "(disabled)";
}

fn searchConfigured(search: config.SearchConfig) bool {
    return search_mod.selectProvider(search) != null;
}

test "diagnostics formatter redacts secrets and shows key state" {
    const text = try format(std.testing.allocator, .{
        .completion = .{
            .provider = .openrouter,
            .api_key = "secret",
            .model = "model",
        },
        .tools = .{ .enabled = true },
    }, 3, .all, 123);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "provider=openrouter") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "persona=neutral") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "web_search_provider=auto") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "transcript_messages=3") != null);
}

test "diagnostics scope parsing trims whitespace but remains case-sensitive" {
    try std.testing.expectEqual(Scope.memory, parseScopeName(" memory ").?);
    try std.testing.expect(parseScopeName("Memory") == null);
}

test "diagnostics search status uses provider selection policy" {
    try std.testing.expect(!searchConfigured(.{ .brave_key = "   " }));
    try std.testing.expect(searchConfigured(.{ .brave_key = "brave" }));
    try std.testing.expect(!searchConfigured(.{
        .provider = .brave,
        .tavily_key = "tvly",
    }));
}
