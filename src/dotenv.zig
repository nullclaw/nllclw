const std = @import("std");
const config = @import("./config.zig");

pub const ParseError = error{ InvalidLine, UnknownKey, InvalidShell, InvalidToolTimeoutMs };

pub fn parse(contents: []const u8) ParseError!config.Source {
    return parseWithFeatures(contents, .{});
}

pub fn parseWithFeatures(contents: []const u8, comptime features: config.Features) ParseError!config.Source {
    var source: config.Source = .{};
    var rest = contents;

    while (std.mem.indexOfScalar(u8, rest, '\n')) |line_end| {
        try parseLine(&source, rest[0..line_end], features);
        rest = rest[line_end + 1 ..];
    }

    if (rest.len != 0) try parseLine(&source, rest, features);
    return source;
}

fn parseLine(source: *config.Source, line: []const u8, comptime features: config.Features) ParseError!void {
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    if (trimmed.len == 0 or trimmed[0] == '#') return;

    const equals = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.InvalidLine;
    const key = std.mem.trim(u8, trimmed[0..equals], &std.ascii.whitespace);
    const value = std.mem.trim(u8, trimmed[equals + 1 ..], &std.ascii.whitespace);
    if (key.len == 0) return error.InvalidLine;

    if (!source.setWithFeatures(key, value, features) and std.mem.startsWith(u8, key, "NLLCLW_")) {
        if (config.shellOnlyKey(key)) |shell_key| {
            return switch (shell_key) {
                .shell => error.InvalidShell,
                .tool_timeout_ms => error.InvalidToolTimeoutMs,
            };
        }
        return error.UnknownKey;
    }
}

test "parses comments blanks whitespace and CRLF" {
    const source = try parse(
        \\# comment
        \\
        \\ NLLCLW_PROVIDER = openrouter 
        \\NLLCLW_API_KEY= key 
        \\NLLCLW_MODEL=model
        \\
    );

    try std.testing.expectEqualStrings("openrouter", source.provider.?);
    try std.testing.expectEqualStrings("key", source.api_key.?);
    try std.testing.expectEqualStrings("model", source.model.?);

    const crlf = try parse("NLLCLW_PROVIDER=openai\r\nNLLCLW_MODEL=gpt\r\n");
    try std.testing.expectEqualStrings("openai", crlf.provider.?);
    try std.testing.expectEqualStrings("gpt", crlf.model.?);
}

test "invalid non-comment line is rejected" {
    try std.testing.expectError(error.InvalidLine, parse("NLLCLW_PROVIDER\n"));
    try std.testing.expectError(error.InvalidLine, parse("=value\n"));
}

test "duplicate keys use the last value" {
    const source = try parse(
        \\NLLCLW_MODEL=first
        \\NLLCLW_MODEL=second
    );
    try std.testing.expectEqualStrings("second", source.model.?);
}

test "shell keys are parsed only for shell feature builds" {
    try std.testing.expectError(error.InvalidShell, parse("NLLCLW_SHELL=on\n"));
    try std.testing.expectError(error.InvalidToolTimeoutMs, parse("NLLCLW_TOOL_TIMEOUT_MS=2500\n"));

    const shell_source = try parseWithFeatures(
        \\NLLCLW_SHELL=on
        \\NLLCLW_TOOL_TIMEOUT_MS=2500
    ,
        .{ .shell_tool = true },
    );
    try std.testing.expectEqualStrings("on", shell_source.shell.?);
    try std.testing.expectEqualStrings("2500", shell_source.tool_timeout_ms.?);
}

test "unknown nllclw dotenv keys are rejected" {
    try std.testing.expectError(error.UnknownKey, parse("NLLCLW_MDOEL=gpt\n"));
    _ = try parse("OTHER_TOOL_FLAG=ok\n");
}
