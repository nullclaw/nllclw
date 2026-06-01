const std = @import("std");
const types = @import("./types.zig");

const KeyField = struct {
    key: []const u8,
    field: []const u8,
    kind: ValueKind,
};

pub const ValueKind = enum {
    text,
    integer,
    text_or_integer,
    boolean,
};

const base_keys = [_]KeyField{
    .{ .key = "NLLCLW_PROVIDER", .field = "provider", .kind = .text },
    .{ .key = "NLLCLW_API_KEY", .field = "api_key", .kind = .text },
    .{ .key = "NLLCLW_MODEL", .field = "model", .kind = .text },
    .{ .key = "NLLCLW_MAX_TOKENS", .field = "max_tokens", .kind = .integer },
    .{ .key = "NLLCLW_BASE_URL", .field = "base_url", .kind = .text },
    .{ .key = "NLLCLW_ALLOW_HTTP_BASE_URL", .field = "allow_http_base_url", .kind = .boolean },
    .{ .key = "NLLCLW_HTTP_REFERER", .field = "http_referer", .kind = .text },
    .{ .key = "NLLCLW_APP_TITLE", .field = "app_title", .kind = .text },
    .{ .key = "NLLCLW_PERSONA", .field = "persona", .kind = .text },
    .{ .key = "NLLCLW_MEMORY", .field = "memory", .kind = .boolean },
    .{ .key = "NLLCLW_MEMORY_PATH", .field = "memory_path", .kind = .text },
    .{ .key = "NLLCLW_MEMORY_MAX_MESSAGES", .field = "memory_max_messages", .kind = .integer },
    .{ .key = "NLLCLW_MEMORY_FACTS_PATH", .field = "memory_facts_path", .kind = .text },
    .{ .key = "NLLCLW_MEMORY_MAX_FACTS", .field = "memory_max_facts", .kind = .integer },
    .{ .key = "NLLCLW_TOOLS", .field = "tools", .kind = .boolean },
    .{ .key = "NLLCLW_FILE_READ", .field = "file_read", .kind = .boolean },
    .{ .key = "NLLCLW_FILE_WRITE", .field = "file_write", .kind = .boolean },
    .{ .key = "NLLCLW_SCHEDULE_TOOLS", .field = "schedule_tools", .kind = .boolean },
    .{ .key = "NLLCLW_USER_TOOLS_PATH", .field = "user_tools_path", .kind = .text },
    .{ .key = "NLLCLW_TOOL_MAX_ROUNDS", .field = "tool_max_rounds", .kind = .integer },
    .{ .key = "NLLCLW_TOOL_OUTPUT_MAX_BYTES", .field = "tool_output_max_bytes", .kind = .integer },
    .{ .key = "NLLCLW_STREAM", .field = "stream", .kind = .boolean },
    .{ .key = "NLLCLW_TELEGRAM_TOKEN", .field = "telegram_token", .kind = .text },
    .{ .key = "NLLCLW_TELEGRAM_CHAT_ID", .field = "telegram_chat_id", .kind = .text_or_integer },
    .{ .key = "NLLCLW_TELEGRAM_POLL_TIMEOUT", .field = "telegram_poll_timeout", .kind = .integer },
    .{ .key = "NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE", .field = "telegram_rate_limit_per_minute", .kind = .integer },
    .{ .key = "NLLCLW_WS_HOST", .field = "websocket_host", .kind = .text },
    .{ .key = "NLLCLW_WS_PORT", .field = "websocket_port", .kind = .integer },
    .{ .key = "NLLCLW_WS_PATH", .field = "websocket_path", .kind = .text },
    .{ .key = "NLLCLW_WS_TOKEN", .field = "websocket_token", .kind = .text },
    .{ .key = "NLLCLW_WS_ALLOW_REMOTE", .field = "websocket_allow_remote", .kind = .boolean },
    .{ .key = "NLLCLW_WS_RATE_LIMIT_PER_MINUTE", .field = "websocket_rate_limit_per_minute", .kind = .integer },
    .{ .key = "NLLCLW_SEARCH_PROVIDER", .field = "search_provider", .kind = .text },
    .{ .key = "NLLCLW_SEARCH_TAVILY_KEY", .field = "search_tavily_key", .kind = .text },
    .{ .key = "NLLCLW_SEARCH_BRAVE_KEY", .field = "search_brave_key", .kind = .text },
    .{ .key = "NLLCLW_SEARCH_EXA_KEY", .field = "search_exa_key", .kind = .text },
    .{ .key = "NLLCLW_SEARCH_FIRECRAWL_KEY", .field = "search_firecrawl_key", .kind = .text },
    .{ .key = "NLLCLW_SEARCH_DUCKDUCKGO", .field = "search_duckduckgo", .kind = .boolean },
    .{ .key = "NLLCLW_SCHEDULE_PATH", .field = "schedule_path", .kind = .text },
    .{ .key = "NLLCLW_DAEMON_INTERVAL_SECONDS", .field = "daemon_interval_seconds", .kind = .integer },
    .{ .key = "NLLCLW_HEARTBEAT_INTERVAL_SECONDS", .field = "heartbeat_interval_seconds", .kind = .integer },
    .{ .key = "NLLCLW_TIMEZONE_OFFSET_MINUTES", .field = "timezone_offset_minutes", .kind = .integer },
};

const shell_keys = [_]KeyField{
    .{ .key = "NLLCLW_SHELL", .field = "shell", .kind = .boolean },
    .{ .key = "NLLCLW_TOOL_TIMEOUT_MS", .field = "tool_timeout_ms", .kind = .integer },
};

pub const ShellOnlyKey = enum {
    shell,
    tool_timeout_ms,
};

pub const Source = struct {
    provider: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    model: ?[]const u8 = null,
    max_tokens: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    allow_http_base_url: ?[]const u8 = null,
    http_referer: ?[]const u8 = null,
    app_title: ?[]const u8 = null,
    persona: ?[]const u8 = null,
    memory: ?[]const u8 = null,
    memory_path: ?[]const u8 = null,
    memory_max_messages: ?[]const u8 = null,
    memory_facts_path: ?[]const u8 = null,
    memory_max_facts: ?[]const u8 = null,
    tools: ?[]const u8 = null,
    file_read: ?[]const u8 = null,
    file_write: ?[]const u8 = null,
    schedule_tools: ?[]const u8 = null,
    user_tools_path: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    tool_max_rounds: ?[]const u8 = null,
    tool_output_max_bytes: ?[]const u8 = null,
    tool_timeout_ms: ?[]const u8 = null,
    stream: ?[]const u8 = null,
    telegram_token: ?[]const u8 = null,
    telegram_chat_id: ?[]const u8 = null,
    telegram_poll_timeout: ?[]const u8 = null,
    telegram_rate_limit_per_minute: ?[]const u8 = null,
    websocket_host: ?[]const u8 = null,
    websocket_port: ?[]const u8 = null,
    websocket_path: ?[]const u8 = null,
    websocket_token: ?[]const u8 = null,
    websocket_allow_remote: ?[]const u8 = null,
    websocket_rate_limit_per_minute: ?[]const u8 = null,
    search_provider: ?[]const u8 = null,
    search_tavily_key: ?[]const u8 = null,
    search_brave_key: ?[]const u8 = null,
    search_exa_key: ?[]const u8 = null,
    search_firecrawl_key: ?[]const u8 = null,
    search_duckduckgo: ?[]const u8 = null,
    schedule_path: ?[]const u8 = null,
    daemon_interval_seconds: ?[]const u8 = null,
    heartbeat_interval_seconds: ?[]const u8 = null,
    timezone_offset_minutes: ?[]const u8 = null,

    pub fn set(self: *Source, key: []const u8, value: []const u8) bool {
        return self.setWithFeatures(key, value, .{});
    }

    pub fn setWithFeatures(self: *Source, key: []const u8, value: []const u8, comptime features: types.Features) bool {
        if (setFromTable(self, key, value, &base_keys)) return true;
        if (comptime features.shell_tool) return setFromTable(self, key, value, &shell_keys);
        return false;
    }

    pub fn setFieldWithFeatures(self: *Source, field: []const u8, value: []const u8, comptime features: types.Features) bool {
        if (setFieldFromTable(self, field, value, &base_keys)) return true;
        if (comptime features.shell_tool) return setFieldFromTable(self, field, value, &shell_keys);
        return false;
    }

    pub fn isKnownKey(key: []const u8, comptime features: types.Features) bool {
        if (tableHasKey(key, &base_keys)) return true;
        if (comptime features.shell_tool) return tableHasKey(key, &shell_keys);
        return false;
    }

    pub fn isKnownField(field: []const u8, comptime features: types.Features) bool {
        if (tableHasField(field, &base_keys)) return true;
        if (comptime features.shell_tool) return tableHasField(field, &shell_keys);
        return false;
    }

    pub fn overlay(primary: Source, fallback: Source) Source {
        var out: Source = .{};
        inline for (@typeInfo(Source).@"struct".fields) |field| {
            @field(out, field.name) = clean(@field(primary, field.name)) orelse clean(@field(fallback, field.name));
        }
        return out;
    }

    pub fn fromEnvMap(map: *const std.process.Environ.Map, comptime features: types.Features) Source {
        var source: Source = .{};
        fillFromEnvTable(&source, map, &base_keys);
        if (comptime features.shell_tool) fillFromEnvTable(&source, map, &shell_keys);
        return source;
    }
};

comptime {
    validateSourceKeyTables();
}

pub fn shellOnlyKey(key: []const u8) ?ShellOnlyKey {
    if (eqlParts(key, &.{ "NLLCLW_", "SHELL" })) return .shell;
    if (eqlParts(key, &.{ "NLLCLW_", "TOOL", "_TIMEOUT_MS" })) return .tool_timeout_ms;
    return null;
}

pub fn shellOnlyField(field: []const u8) ?ShellOnlyKey {
    if (std.mem.eql(u8, field, "shell")) return .shell;
    if (std.mem.eql(u8, field, "tool_timeout_ms")) return .tool_timeout_ms;
    return null;
}

pub fn anyFieldKind(field: []const u8) ?ValueKind {
    if (tableFieldKind(field, &base_keys)) |kind| return kind;
    return tableFieldKind(field, &shell_keys);
}

fn validateSourceKeyTables() void {
    @setEvalBranchQuota(10_000);
    validateKeyTable(&base_keys);
    validateKeyTable(&shell_keys);

    inline for (@typeInfo(Source).@"struct".fields) |field| {
        if (field.type != ?[]const u8) {
            @compileError("config Source field must be ?[]const u8: " ++ field.name);
        }

        const count = fieldCount(field.name, &base_keys) + fieldCount(field.name, &shell_keys);
        if (count == 0) @compileError("missing config key table entry for Source." ++ field.name);
        if (count > 1) @compileError("duplicate config key table entry for Source." ++ field.name);
    }
}

fn validateKeyTable(comptime entries: []const KeyField) void {
    inline for (entries, 0..) |entry, index| {
        if (!@hasField(Source, entry.field)) {
            @compileError("config key table references missing Source field: " ++ entry.field);
        }
        if (!std.mem.startsWith(u8, entry.key, "NLLCLW_")) {
            @compileError("config key table entry must start with NLLCLW_: " ++ entry.key);
        }

        inline for (entries[index + 1 ..]) |other| {
            if (std.mem.eql(u8, entry.key, other.key)) {
                @compileError("duplicate config key table key: " ++ entry.key);
            }
            if (std.mem.eql(u8, entry.field, other.field)) {
                @compileError("duplicate config key table field: " ++ entry.field);
            }
        }
    }
}

fn fieldCount(comptime field_name: []const u8, comptime entries: []const KeyField) comptime_int {
    var count = 0;
    inline for (entries) |entry| {
        if (std.mem.eql(u8, field_name, entry.field)) count += 1;
    }
    return count;
}

fn setFromTable(self: *Source, key: []const u8, value: []const u8, comptime entries: []const KeyField) bool {
    inline for (entries) |entry| {
        if (std.mem.eql(u8, key, entry.key)) {
            @field(self, entry.field) = value;
            return true;
        }
    }
    return false;
}

fn setFieldFromTable(self: *Source, field: []const u8, value: []const u8, comptime entries: []const KeyField) bool {
    inline for (entries) |entry| {
        if (std.mem.eql(u8, field, entry.field)) {
            @field(self, entry.field) = value;
            return true;
        }
    }
    return false;
}

fn eqlParts(value: []const u8, comptime parts: []const []const u8) bool {
    var expected_len: usize = 0;
    inline for (parts) |part| expected_len += part.len;
    if (value.len != expected_len) return false;

    var offset: usize = 0;
    inline for (parts) |part| {
        if (!std.mem.eql(u8, value[offset..][0..part.len], part)) return false;
        offset += part.len;
    }
    return true;
}

fn tableHasKey(key: []const u8, comptime entries: []const KeyField) bool {
    inline for (entries) |entry| {
        if (std.mem.eql(u8, key, entry.key)) return true;
    }
    return false;
}

fn tableHasField(field: []const u8, comptime entries: []const KeyField) bool {
    return tableFieldKind(field, entries) != null;
}

fn tableFieldKind(field: []const u8, comptime entries: []const KeyField) ?ValueKind {
    inline for (entries) |entry| {
        if (std.mem.eql(u8, field, entry.field)) return entry.kind;
    }
    return null;
}

fn clean(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    return if (trimmed.len == 0) null else trimmed;
}

fn fillFromEnvTable(
    source: *Source,
    map: *const std.process.Environ.Map,
    comptime entries: []const KeyField,
) void {
    inline for (entries) |entry| {
        @field(source, entry.field) = map.get(entry.key);
    }
}

test "source overlay falls back when primary value is blank" {
    const merged = Source.overlay(.{
        .provider = "   ",
        .api_key = "config-key",
    }, .{
        .provider = "openai",
        .api_key = "dotenv-key",
        .model = "dotenv-model",
    });

    try std.testing.expectEqualStrings("openai", merged.provider.?);
    try std.testing.expectEqualStrings("config-key", merged.api_key.?);
    try std.testing.expectEqualStrings("dotenv-model", merged.model.?);
}
