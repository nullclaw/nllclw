const std = @import("std");
const config = @import("./config.zig");

pub const ValidateError = error{ UnknownKey, InvalidShell, InvalidToolTimeoutMs };

pub fn validateKnownKeys(map: *const std.process.Environ.Map, comptime features: config.Features) ValidateError!void {
    var it = map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.startsWith(u8, key, "NLLCLW_") and !config.Source.isKnownKey(key, features)) {
            if (config.shellOnlyKey(key)) |shell_key| {
                return switch (shell_key) {
                    .shell => error.InvalidShell,
                    .tool_timeout_ms => error.InvalidToolTimeoutMs,
                };
            }
            return error.UnknownKey;
        }
    }
}

pub fn fromMap(map: *const std.process.Environ.Map, comptime features: config.Features) config.Source {
    return config.Source.fromEnvMap(map, features);
}

test "env rejects unknown nllclw keys" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    try map.put("NLLCLW_UNKNOWN_KEY", "value");
    try std.testing.expectError(error.UnknownKey, validateKnownKeys(&map, .{}));
}

test "default env rejects shell-only keys" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    try map.put("NLLCLW_SHELL", "off");
    try std.testing.expectError(error.InvalidShell, validateKnownKeys(&map, .{}));

    var timeout_map = std.process.Environ.Map.init(std.testing.allocator);
    defer timeout_map.deinit();
    try timeout_map.put("NLLCLW_TOOL_TIMEOUT_MS", "5000");
    try std.testing.expectError(error.InvalidToolTimeoutMs, validateKnownKeys(&timeout_map, .{}));

    var shell_map = std.process.Environ.Map.init(std.testing.allocator);
    defer shell_map.deinit();
    try shell_map.put("NLLCLW_SHELL", "off");
    try shell_map.put("NLLCLW_TOOL_TIMEOUT_MS", "5000");
    try validateKnownKeys(&shell_map, .{ .shell_tool = true });
}

test "env source exposes security-sensitive capability flags" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    try map.put("NLLCLW_PROVIDER", "compatible");
    try map.put("NLLCLW_API_KEY", "key");
    try map.put("NLLCLW_MODEL", "model");
    try map.put("NLLCLW_MAX_TOKENS", "64");
    try map.put("NLLCLW_BASE_URL", "http://127.0.0.1:11434/v1");
    try map.put("NLLCLW_ALLOW_HTTP_BASE_URL", "on");
    try map.put("NLLCLW_PERSONA", "technical");
    try map.put("NLLCLW_TOOLS", "on");
    try map.put("NLLCLW_FILE_READ", "on");
    try map.put("NLLCLW_FILE_WRITE", "on");
    try map.put("NLLCLW_SCHEDULE_TOOLS", "on");
    try map.put("NLLCLW_USER_TOOLS_PATH", ".tools.jsonl");
    try map.put("NLLCLW_TELEGRAM_TOKEN", "123:token");
    try map.put("NLLCLW_TELEGRAM_CHAT_ID", "42");
    try map.put("NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE", "7");
    try map.put("NLLCLW_WS_HOST", "127.0.0.1");
    try map.put("NLLCLW_WS_PORT", "8766");
    try map.put("NLLCLW_WS_PATH", "/chat");
    try map.put("NLLCLW_WS_TOKEN", "ws-token");
    try map.put("NLLCLW_WS_ALLOW_REMOTE", "off");
    try map.put("NLLCLW_WS_RATE_LIMIT_PER_MINUTE", "9");
    try map.put("NLLCLW_SEARCH_PROVIDER", "brave");
    try map.put("NLLCLW_SEARCH_TAVILY_KEY", "tvly");
    try map.put("NLLCLW_SEARCH_BRAVE_KEY", "brave");
    try map.put("NLLCLW_SEARCH_EXA_KEY", "exa");
    try map.put("NLLCLW_SEARCH_FIRECRAWL_KEY", "fc");
    try map.put("NLLCLW_SEARCH_DUCKDUCKGO", "on");
    try map.put("NLLCLW_SHELL", "on");
    try map.put("NLLCLW_TOOL_TIMEOUT_MS", "2500");

    const source = fromMap(&map, .{ .shell_tool = true });
    const runtime_cfg = try config.fromSourcesWithFeatures(source, .{}, .{ .shell_tool = true });
    try std.testing.expectEqual(@as(u32, 64), runtime_cfg.completion.max_tokens.?);
    try std.testing.expect(runtime_cfg.completion.allow_insecure_base_url);
    try std.testing.expectEqual(config.PersonaKind.technical, runtime_cfg.persona);
    try std.testing.expect(runtime_cfg.tools.enabled);
    try std.testing.expect(runtime_cfg.tools.file_read_enabled);
    try std.testing.expect(runtime_cfg.tools.file_write_enabled);
    try std.testing.expect(runtime_cfg.tools.schedule_enabled);
    try std.testing.expectEqualStrings(".tools.jsonl", runtime_cfg.tools.user_tools_path.?);
    try std.testing.expect(runtime_cfg.tools.shell_enabled);
    try std.testing.expectEqual(@as(u64, 2500), runtime_cfg.tools.timeout_ms);
    try std.testing.expectEqual(@as(i64, 42), runtime_cfg.telegram.chat_id.?.id);
    try std.testing.expectEqual(@as(u32, 7), runtime_cfg.telegram.rate_limit_per_minute);
    try std.testing.expectEqualStrings("123:token", runtime_cfg.telegram.token.?);
    try std.testing.expectEqualStrings("127.0.0.1", runtime_cfg.websocket.host);
    try std.testing.expectEqual(@as(u16, 8766), runtime_cfg.websocket.port);
    try std.testing.expectEqualStrings("/chat", runtime_cfg.websocket.path);
    try std.testing.expectEqualStrings("ws-token", runtime_cfg.websocket.token.?);
    try std.testing.expect(!runtime_cfg.websocket.allow_remote);
    try std.testing.expectEqual(@as(u32, 9), runtime_cfg.websocket.rate_limit_per_minute);
    try std.testing.expectEqual(config.SearchProvider.brave, runtime_cfg.search.provider);
    try std.testing.expectEqualStrings("tvly", runtime_cfg.search.tavily_key.?);
    try std.testing.expectEqualStrings("brave", runtime_cfg.search.brave_key.?);
    try std.testing.expectEqualStrings("exa", runtime_cfg.search.exa_key.?);
    try std.testing.expectEqualStrings("fc", runtime_cfg.search.firecrawl_key.?);
    try std.testing.expect(runtime_cfg.search.duckduckgo_enabled);

    const default_source = fromMap(&map, .{});
    const default_cfg = try config.fromSources(default_source, .{});
    try std.testing.expect(!default_cfg.tools.shell_enabled);
    try std.testing.expectEqual(config.default_shell_timeout_ms, default_cfg.tools.timeout_ms);
}
