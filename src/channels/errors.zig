const std = @import("std");
const agent = @import("../agent.zig");
const build_options = @import("build_options");
const text_policy = @import("../text_policy.zig");

const Io = std.Io;

pub const max_diagnostic_body_bytes: usize = 16 * 1024;
const truncated_message = "[diagnostic body truncated]\n";

pub fn configErrorMessage(err: anyerror) []const u8 {
    if (comptime build_options.shell_tool) {
        switch (err) {
            error.InvalidShell => return "NLLCLW_SHELL must be on or off",
            error.InvalidToolTimeoutMs => return "NLLCLW_TOOL_TIMEOUT_MS must be an integer from 1 to 600000",
            else => {},
        }
    } else {
        switch (err) {
            error.InvalidShell,
            error.InvalidToolTimeoutMs,
            => return "optional shell configuration requires a binary built with -Dshell-tool=true",
            else => {},
        }
    }

    return switch (err) {
        error.MissingProvider => "set NLLCLW_PROVIDER",
        error.MissingApiKey => "set NLLCLW_API_KEY",
        error.MissingModel => "set NLLCLW_MODEL",
        error.InvalidModel => "NLLCLW_MODEL must be single-line valid UTF-8 text",
        error.MissingBaseUrl => "set NLLCLW_BASE_URL for NLLCLW_PROVIDER=compatible",
        error.EmptyBaseUrl => "NLLCLW_BASE_URL must not be empty",
        error.InvalidBaseUrl => "NLLCLW_BASE_URL must start with https://",
        error.InsecureBaseUrl => "NLLCLW_BASE_URL must use https:// unless NLLCLW_ALLOW_HTTP_BASE_URL=on for localhost",
        error.InvalidHeaderValue => "provider header values must not contain ASCII control bytes",
        error.UnknownProvider => "NLLCLW_PROVIDER must be openai, openrouter, or compatible",
        error.InvalidMaxTokens => "NLLCLW_MAX_TOKENS must be a positive integer",
        error.InvalidAllowHttpBaseUrl => "NLLCLW_ALLOW_HTTP_BASE_URL must be on or off",
        error.InvalidPersona => "NLLCLW_PERSONA must be neutral, friendly, technical, or witty",
        error.InvalidMemory => "NLLCLW_MEMORY must be on or off",
        error.InvalidMemoryPath => "NLLCLW_MEMORY_PATH must be a relative .jsonl path with valid UTF-8 and no control bytes",
        error.InvalidMemoryFactsPath => "NLLCLW_MEMORY_FACTS_PATH must be a relative .jsonl path with valid UTF-8 and no control bytes",
        error.InvalidMemoryMaxMessages => "NLLCLW_MEMORY_MAX_MESSAGES must be an integer >= 2",
        error.InvalidMemoryMaxFacts => "NLLCLW_MEMORY_MAX_FACTS must be an integer from 1 to 1024",
        error.InvalidTools => "NLLCLW_TOOLS must be on or off",
        error.InvalidFileRead => "NLLCLW_FILE_READ must be on or off",
        error.InvalidFileWrite => "NLLCLW_FILE_WRITE must be on or off",
        error.InvalidScheduleTools => "NLLCLW_SCHEDULE_TOOLS must be on or off",
        error.InvalidUserToolsPath => "NLLCLW_USER_TOOLS_PATH must be a relative .jsonl path with valid UTF-8 and no control bytes",
        error.InvalidToolMaxRounds => "NLLCLW_TOOL_MAX_ROUNDS must be an integer from 1 to 16",
        error.InvalidToolOutputMaxBytes => "NLLCLW_TOOL_OUTPUT_MAX_BYTES must be an integer from 256 to 1048576",
        error.InvalidStream => "NLLCLW_STREAM must be on or off",
        error.InvalidTelegramToken => "NLLCLW_TELEGRAM_TOKEN must be <bot-id>:<secret> using digits, letters, hyphen, or underscore",
        error.InvalidTelegramChatId => "NLLCLW_TELEGRAM_CHAT_ID must be a non-zero integer or Telegram username",
        error.InvalidTelegramPollTimeout => "NLLCLW_TELEGRAM_POLL_TIMEOUT must be an integer from 0 to 60",
        error.InvalidTelegramRateLimit => "NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE must be an integer from 0 to 10000",
        error.InvalidSearchProvider => "NLLCLW_SEARCH_PROVIDER must be auto, tavily, brave, exa, firecrawl, or duckduckgo",
        error.MissingSearchKey => "explicit NLLCLW_SEARCH_PROVIDER requires its matching NLLCLW_SEARCH_*_KEY",
        error.InvalidSearchKey => "NLLCLW_SEARCH_*_KEY values must not contain ASCII control bytes",
        error.InvalidSearchDuckDuckGo => "NLLCLW_SEARCH_DUCKDUCKGO must be on or off",
        error.InvalidSchedulePath => "NLLCLW_SCHEDULE_PATH must be a relative .jsonl path with valid UTF-8 and no control bytes",
        error.InvalidWebSocketHost => "NLLCLW_WS_HOST must be an IP literal without spaces or URL syntax",
        error.InvalidWebSocketPort => "NLLCLW_WS_PORT must be an integer from 1 to 65535",
        error.InvalidWebSocketPath => "NLLCLW_WS_PATH must start with / and be single-line valid UTF-8 without spaces, ? or #",
        error.InvalidWebSocketToken => "NLLCLW_WS_TOKEN must be 8 to 256 URL-safe ASCII characters",
        error.InvalidWebSocketAllowRemote => "NLLCLW_WS_ALLOW_REMOTE must be on or off",
        error.InvalidWebSocketRateLimit => "NLLCLW_WS_RATE_LIMIT_PER_MINUTE must be an integer from 0 to 10000",
        error.InvalidDaemonIntervalSeconds => "NLLCLW_DAEMON_INTERVAL_SECONDS must be an integer from 1 to 86400",
        error.InvalidHeartbeatIntervalSeconds => "NLLCLW_HEARTBEAT_INTERVAL_SECONDS must be an integer from 1 to 604800",
        error.InvalidTimezoneOffsetMinutes => "NLLCLW_TIMEZONE_OFFSET_MINUTES must be an integer from -840 to 840",
        error.InvalidLine => ".env contains a non-empty line without KEY=VALUE",
        error.DotenvFileTooLarge => ".env is larger than 16 KiB",
        error.ConfigJsonFileTooLarge => "config.json is larger than 16 KiB",
        error.InvalidConfigJson => "config.json must contain valid JSON",
        error.InvalidConfigJsonTopLevel => "config.json must be a JSON object",
        error.InvalidConfigJsonValue => "config.json values must match the field type",
        error.UnknownKey => "configuration contains an unknown key",
        error.MissingHome => "set HOME or XDG_CONFIG_HOME/XDG_STATE_HOME so nllclw can find its user config directory",
        error.InvalidAppPathRoot => "HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, APPDATA, and LOCALAPPDATA must be absolute paths",
        error.ContextFileTooLarge => "assistant context file is larger than 16 KiB",
        error.InvalidContextFileUtf8 => "assistant context files must be valid UTF-8 markdown without binary control bytes",
        error.SkillFileTooLarge => "skill file is larger than 8 KiB",
        error.InvalidSkillFileUtf8 => "skill files must be valid UTF-8 markdown without binary control bytes",
        else => @errorName(err),
    };
}

pub fn printTopLevel(err: anyerror) void {
    std.debug.print("nllclw: {s}\n", .{topLevelErrorMessage(err)});
}

fn topLevelErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidMemoryLimit => "memory retention limit is out of range",
        error.InvalidMemoryLine => "memory file contains invalid JSONL",
        error.InvalidMemoryRole => "memory file roles must be user or assistant",
        error.StreamTooLong => "input is too large",
        else => @errorName(err),
    };
}

pub fn printAppErrorWriter(stderr: *Io.Writer, err: anyerror, diagnostic: agent.Diagnostic) !void {
    if (err == error.HttpStatus) {
        const status = diagnostic.status orelse {
            try stderr.writeAll("nllclw: provider returned an HTTP error\n");
            return;
        };

        try stderr.print("nllclw: provider returned HTTP {d}", .{status});
        if (diagnostic.message) |message| {
            try stderr.print(": {s}\n", .{message});
        } else if (diagnostic.body) |body| {
            try stderr.writeByte('\n');
            try writeDiagnosticBody(stderr, body);
        } else {
            try stderr.writeByte('\n');
        }
        return;
    }

    if (err == error.ToolRoundLimit) {
        try stderr.writeAll("nllclw: tool round limit reached\n");
        return;
    }

    if (err == error.InvalidRequestText) {
        try stderr.writeAll("nllclw: chat request text must be valid UTF-8 without binary control bytes\n");
        return;
    }

    if (err == error.InvalidHeaderValue) {
        try stderr.writeAll("nllclw: provider header values must not contain ASCII control bytes\n");
        return;
    }

    if (err == error.StreamWriteFailed) {
        try stderr.writeAll("nllclw: failed to write streaming response\n");
        return;
    }

    if (diagnostic.body) |body| {
        try stderr.print("nllclw: {s}\n", .{@errorName(err)});
        try writeDiagnosticBody(stderr, body);
    } else {
        try stderr.print("nllclw: {s}\n", .{@errorName(err)});
    }
}

pub fn writeDiagnosticBody(writer: *Io.Writer, body: []const u8) !void {
    if (!isPrintableDiagnosticBody(body)) {
        try writer.writeAll("[non-text response body omitted]\n");
        return;
    }

    if (body.len <= max_diagnostic_body_bytes) {
        try writer.writeAll(body);
        if (!std.mem.endsWith(u8, body, "\n")) try writer.writeByte('\n');
        return;
    }

    const prefix_len = utf8PrefixLen(body, max_diagnostic_body_bytes);
    try writer.writeAll(body[0..prefix_len]);
    if (prefix_len == 0 or !std.mem.endsWith(u8, body[0..prefix_len], "\n")) try writer.writeByte('\n');
    try writer.writeAll(truncated_message);
}

fn isPrintableDiagnosticBody(body: []const u8) bool {
    return text_policy.isMultilineText(body);
}

fn utf8PrefixLen(value: []const u8, max_bytes: usize) usize {
    var index: usize = 0;
    while (index < value.len and index < max_bytes) {
        const width = std.unicode.utf8ByteSequenceLength(value[index]) catch break;
        if (index + width > value.len or index + width > max_bytes) break;
        index += width;
    }
    return index;
}

test "config errors are user-facing" {
    try std.testing.expectEqualStrings("set NLLCLW_PROVIDER", configErrorMessage(error.MissingProvider));
    try std.testing.expectEqualStrings(
        "NLLCLW_PROVIDER must be openai, openrouter, or compatible",
        configErrorMessage(error.UnknownProvider),
    );
    try std.testing.expectEqualStrings(
        "configuration contains an unknown key",
        configErrorMessage(error.UnknownKey),
    );
    try std.testing.expectEqualStrings(".env is larger than 16 KiB", configErrorMessage(error.DotenvFileTooLarge));
    try std.testing.expectEqualStrings("config.json must contain valid JSON", configErrorMessage(error.InvalidConfigJson));
    try std.testing.expectEqualStrings(
        "set HOME or XDG_CONFIG_HOME/XDG_STATE_HOME so nllclw can find its user config directory",
        configErrorMessage(error.MissingHome),
    );
    try std.testing.expectEqualStrings(
        "HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, APPDATA, and LOCALAPPDATA must be absolute paths",
        configErrorMessage(error.InvalidAppPathRoot),
    );
    if (comptime build_options.shell_tool) {
        try std.testing.expectEqualStrings("NLLCLW_SHELL must be on or off", configErrorMessage(error.InvalidShell));
    } else {
        try std.testing.expectEqualStrings(
            "optional shell configuration requires a binary built with -Dshell-tool=true",
            configErrorMessage(error.InvalidShell),
        );
    }
    try std.testing.expectEqualStrings(
        "assistant context file is larger than 16 KiB",
        configErrorMessage(error.ContextFileTooLarge),
    );
    try std.testing.expectEqualStrings(
        "assistant context files must be valid UTF-8 markdown without binary control bytes",
        configErrorMessage(error.InvalidContextFileUtf8),
    );
    try std.testing.expectEqualStrings(
        "skill files must be valid UTF-8 markdown without binary control bytes",
        configErrorMessage(error.InvalidSkillFileUtf8),
    );
    try std.testing.expectEqualStrings(
        "provider header values must not contain ASCII control bytes",
        configErrorMessage(error.InvalidHeaderValue),
    );
}

test "top-level memory errors are user-facing" {
    try std.testing.expectEqualStrings("memory file contains invalid JSONL", topLevelErrorMessage(error.InvalidMemoryLine));
    try std.testing.expectEqualStrings("memory file roles must be user or assistant", topLevelErrorMessage(error.InvalidMemoryRole));
}

test "diagnostic body printer omits binary payloads" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try writeDiagnosticBody(&out.writer, "line one\nline two");
    try std.testing.expectEqualStrings("line one\nline two\n", out.written());

    out.clearRetainingCapacity();
    try writeDiagnosticBody(&out.writer, "bad\x00body");
    try std.testing.expectEqualStrings("[non-text response body omitted]\n", out.written());
}

test "diagnostic body printer caps long text at a utf-8 boundary" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const body = try std.testing.allocator.alloc(u8, max_diagnostic_body_bytes + 32);
    defer std.testing.allocator.free(body);
    @memset(body, 'a');

    try writeDiagnosticBody(&out.writer, body);
    try std.testing.expectEqual(@as(usize, max_diagnostic_body_bytes), std.mem.indexOfScalar(u8, out.written(), '\n').?);
    try std.testing.expect(std.mem.endsWith(u8, out.written(), truncated_message));

    out.clearRetainingCapacity();
    const unicode_body = "é" ** ((max_diagnostic_body_bytes / 2) + 1);
    try writeDiagnosticBody(&out.writer, unicode_body);
    try std.testing.expect(std.unicode.utf8ValidateSlice(out.written()));
    try std.testing.expect(std.mem.endsWith(u8, out.written(), truncated_message));
}
