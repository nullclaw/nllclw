const std = @import("std");
const text_policy = @import("./text_policy.zig");

const Allocator = std.mem.Allocator;

pub const protocol_version: u32 = 1;
pub const max_prompt_bytes: usize = 64 * 1024;

pub const ParseError = error{
    EmptyMessage,
    InvalidJson,
    InvalidUtf8,
    MissingPrompt,
    PromptTooLarge,
    UnexpectedPrompt,
    UnknownMessageType,
} || Allocator.Error;

pub const FormatError = error{
    InvalidEventText,
} || Allocator.Error;

pub const Command = union(enum) {
    chat: []u8,
    ping,
    status,
    close,

    pub fn deinit(self: *Command, allocator: Allocator) void {
        switch (self.*) {
            .chat => |prompt| allocator.free(prompt),
            else => {},
        }
        self.* = undefined;
    }
};

const ClientMessage = struct {
    type: []const u8 = "chat",
    prompt: ?[]const u8 = null,
};

pub fn parseCommand(allocator: Allocator, frame: []const u8) ParseError!Command {
    const trimmed = std.mem.trim(u8, frame, &std.ascii.whitespace);
    if (trimmed.len == 0) return error.EmptyMessage;
    if (trimmed.len > max_prompt_bytes) return error.PromptTooLarge;
    if (!isValidText(trimmed)) return error.InvalidUtf8;

    if (trimmed[0] != '{') {
        return .{ .chat = try allocator.dupe(u8, trimmed) };
    }

    const parsed = std.json.parseFromSlice(ClientMessage, allocator, trimmed, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
    defer parsed.deinit();

    const message_type = parsed.value.type;
    if (std.mem.eql(u8, message_type, "chat") or std.mem.eql(u8, message_type, "message")) {
        const prompt_raw = parsed.value.prompt orelse return error.MissingPrompt;
        const prompt = std.mem.trim(u8, prompt_raw, &std.ascii.whitespace);
        if (prompt.len == 0) return error.MissingPrompt;
        if (prompt.len > max_prompt_bytes) return error.PromptTooLarge;
        if (!isValidText(prompt)) return error.InvalidUtf8;
        return .{ .chat = try allocator.dupe(u8, prompt) };
    }
    if (std.mem.eql(u8, message_type, "ping")) {
        if (parsed.value.prompt != null) return error.UnexpectedPrompt;
        return .ping;
    }
    if (std.mem.eql(u8, message_type, "status")) {
        if (parsed.value.prompt != null) return error.UnexpectedPrompt;
        return .status;
    }
    if (std.mem.eql(u8, message_type, "close")) {
        if (parsed.value.prompt != null) return error.UnexpectedPrompt;
        return .close;
    }
    return error.UnknownMessageType;
}

pub const Event = struct {
    type: []const u8,
    version: ?u32 = null,
    channel: ?[]const u8 = null,
    content: ?[]const u8 = null,
    message: ?[]const u8 = null,
};

pub fn formatEvent(allocator: Allocator, event: Event) FormatError![]u8 {
    try validateEventName(event.type);
    if (event.channel) |channel| try validateEventName(channel);
    if (event.content) |content| try validateEventText(content);
    if (event.message) |message| try validateEventText(message);

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    out.writer.print("{f}", .{std.json.fmt(event, .{ .emit_null_optional_fields = false })}) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

pub fn readyEvent(allocator: Allocator) FormatError![]u8 {
    return formatEvent(allocator, .{
        .type = "ready",
        .version = protocol_version,
        .channel = "websocket",
    });
}

pub fn contentEvent(allocator: Allocator, event_type: []const u8, content: []const u8) FormatError![]u8 {
    return formatEvent(allocator, .{
        .type = event_type,
        .content = content,
    });
}

pub fn errorEvent(allocator: Allocator, message: []const u8) FormatError![]u8 {
    return formatEvent(allocator, .{
        .type = "error",
        .message = message,
    });
}

pub fn targetMatchesPath(target: []const u8, path: []const u8) bool {
    const end = std.mem.indexOfScalar(u8, target, '?') orelse target.len;
    return std.mem.eql(u8, target[0..end], path);
}

pub fn targetHasToken(target: []const u8, expected: []const u8) bool {
    const query_start = std.mem.indexOfScalar(u8, target, '?') orelse return false;
    var matched = false;
    var parts = std.mem.splitScalar(u8, target[query_start + 1 ..], '&');
    while (parts.next()) |part| {
        var kv = std.mem.splitScalar(u8, part, '=');
        const key = kv.next() orelse continue;
        const value = kv.rest();
        if (!std.mem.eql(u8, key, "token")) continue;
        if (matched) return false;
        if (!tokenEquals(value, expected)) return false;
        matched = true;
    }
    return matched;
}

pub fn authorizationBearerMatches(value: []const u8, expected: []const u8) bool {
    const prefix = "Bearer ";
    if (!std.ascii.startsWithIgnoreCase(value, prefix)) return false;
    const token = std.mem.trim(u8, value[prefix.len..], " \t");
    return tokenEquals(token, expected);
}

fn validateEventText(value: []const u8) FormatError!void {
    if (!isValidText(value)) return error.InvalidEventText;
}

fn validateEventName(value: []const u8) FormatError!void {
    if (value.len == 0 or value.len > 64) return error.InvalidEventText;
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_') continue;
        return error.InvalidEventText;
    }
}

fn isValidText(value: []const u8) bool {
    return text_policy.isMultilineText(value);
}

fn tokenEquals(actual: []const u8, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    var diff: u8 = 0;
    for (actual, expected) |a, b| diff |= a ^ b;
    return diff == 0;
}

test "websocket parses plain text as chat prompt" {
    var command = try parseCommand(std.testing.allocator, "  hello  ");
    defer command.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("hello", command.chat);
}

test "websocket parses json commands and rejects invalid messages" {
    var chat_command = try parseCommand(std.testing.allocator, "{\"type\":\"chat\",\"prompt\":\" hello \"}");
    defer chat_command.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("hello", chat_command.chat);

    var status_command = try parseCommand(std.testing.allocator, "{\"type\":\"status\"}");
    defer status_command.deinit(std.testing.allocator);
    switch (status_command) {
        .status => {},
        else => return error.TestExpectedEqual,
    }

    try std.testing.expectError(error.MissingPrompt, parseCommand(std.testing.allocator, "{\"type\":\"chat\"}"));
    try std.testing.expectError(error.UnexpectedPrompt, parseCommand(std.testing.allocator, "{\"type\":\"status\",\"prompt\":\"hello\"}"));
    try std.testing.expectError(error.InvalidJson, parseCommand(std.testing.allocator, "{\"type\":\"status\",\"unknown\":true}"));
    try std.testing.expectError(error.UnknownMessageType, parseCommand(std.testing.allocator, "{\"type\":\"unknown\"}"));
    try std.testing.expectError(error.InvalidJson, parseCommand(std.testing.allocator, "{broken"));
    try std.testing.expectError(error.InvalidUtf8, parseCommand(std.testing.allocator, "\xff"));
    try std.testing.expectError(error.InvalidUtf8, parseCommand(std.testing.allocator, "bad\x00value"));
    try std.testing.expectError(error.InvalidUtf8, parseCommand(std.testing.allocator, "bad\x1bvalue"));
    try std.testing.expectError(error.InvalidUtf8, parseCommand(std.testing.allocator, "{\"type\":\"chat\",\"prompt\":\"bad\\u0000value\"}"));
    try std.testing.expectError(error.InvalidUtf8, parseCommand(std.testing.allocator, "{\"type\":\"chat\",\"prompt\":\"bad\\u001bvalue\"}"));
}

test "websocket parser preserves allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var command = try parseCommand(allocator, "{\"type\":\"chat\",\"prompt\":\"hello\"}");
            defer command.deinit(allocator);
            try std.testing.expectEqualStrings("hello", command.chat);
        }
    }.run, .{});
}

test "websocket formats events as compact json" {
    const ready = try readyEvent(std.testing.allocator);
    defer std.testing.allocator.free(ready);
    try std.testing.expectEqualStrings("{\"type\":\"ready\",\"version\":1,\"channel\":\"websocket\"}", ready);

    const message = try contentEvent(std.testing.allocator, "message", "hello \"zig\"");
    defer std.testing.allocator.free(message);
    try std.testing.expectEqualStrings("{\"type\":\"message\",\"content\":\"hello \\\"zig\\\"\"}", message);

    const multiline = try contentEvent(std.testing.allocator, "message", "line one\nline two");
    defer std.testing.allocator.free(multiline);
    try std.testing.expectEqualStrings("{\"type\":\"message\",\"content\":\"line one\\nline two\"}", multiline);

    try std.testing.expectError(error.InvalidEventText, contentEvent(std.testing.allocator, "bad\ntype", "ok"));
    try std.testing.expectError(error.InvalidEventText, contentEvent(std.testing.allocator, "bad type", "ok"));
    try std.testing.expectError(error.InvalidEventText, contentEvent(std.testing.allocator, "", "ok"));
    try std.testing.expectError(error.InvalidEventText, formatEvent(std.testing.allocator, .{ .type = "ready", .channel = "bad\nchannel" }));
    try std.testing.expectError(error.InvalidEventText, contentEvent(std.testing.allocator, "message", "bad\xff"));
    try std.testing.expectError(error.InvalidEventText, contentEvent(std.testing.allocator, "message", "bad\x00value"));
    try std.testing.expectError(error.InvalidEventText, contentEvent(std.testing.allocator, "message", "bad\x1bvalue"));
}

test "websocket target path and token helpers" {
    try std.testing.expect(targetMatchesPath("/ws?token=abc", "/ws"));
    try std.testing.expect(!targetMatchesPath("/other?token=abc", "/ws"));
    try std.testing.expect(targetHasToken("/ws?token=abc&x=1", "abc"));
    try std.testing.expect(!targetHasToken("/ws?token=abc", "def"));
    try std.testing.expect(!targetHasToken("/ws?token=abc&token=abc", "abc"));
    try std.testing.expect(!targetHasToken("/ws?token=abc&token=def", "abc"));
    try std.testing.expect(!targetHasToken("/ws?x=1&token=abc&y=2&token=abc", "abc"));
    try std.testing.expect(!targetHasToken("/ws?token=a%20b", "a b"));
    try std.testing.expect(authorizationBearerMatches("Bearer abc", "abc"));
    try std.testing.expect(authorizationBearerMatches("bearer abc", "abc"));
    try std.testing.expect(!authorizationBearerMatches("Basic abc", "abc"));
}
