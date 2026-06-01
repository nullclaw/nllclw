const std = @import("std");
const source_mod = @import("./source.zig");
const types = @import("./types.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = error{
    InvalidConfigJson,
    InvalidConfigJsonTopLevel,
    UnknownKey,
    InvalidConfigJsonValue,
    InvalidShell,
    InvalidToolTimeoutMs,
} || Allocator.Error;

pub const ParsedSource = struct {
    source: source_mod.Source = .{},
    parsed: std.json.Parsed(std.json.Value),
    owned_values: std.ArrayList([]u8) = .empty,

    pub fn deinit(self: *ParsedSource, allocator: Allocator) void {
        for (self.owned_values.items) |value| allocator.free(value);
        self.owned_values.deinit(allocator);
        self.parsed.deinit();
        self.* = undefined;
    }
};

pub fn parseWithFeatures(
    allocator: Allocator,
    contents: []const u8,
    comptime features: types.Features,
) ParseError!ParsedSource {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidConfigJson,
    };

    var result: ParsedSource = .{ .parsed = parsed };
    errdefer result.deinit(allocator);

    switch (result.parsed.value) {
        .object => |*object| {
            var it = object.iterator();
            while (it.next()) |entry| {
                const field = entry.key_ptr.*;
                const kind = source_mod.anyFieldKind(field) orelse return error.UnknownKey;
                if (!source_mod.Source.isKnownField(field, features)) {
                    if (source_mod.shellOnlyField(field)) |shell_key| {
                        return switch (shell_key) {
                            .shell => error.InvalidShell,
                            .tool_timeout_ms => error.InvalidToolTimeoutMs,
                        };
                    }
                    return error.UnknownKey;
                }

                const value = try sourceText(&result, allocator, kind, entry.value_ptr.*);
                if (!result.source.setFieldWithFeatures(field, value, features)) return error.UnknownKey;
            }
        },
        else => return error.InvalidConfigJsonTopLevel,
    }

    return result;
}

fn sourceText(
    result: *ParsedSource,
    allocator: Allocator,
    kind: source_mod.ValueKind,
    value: std.json.Value,
) ParseError![]const u8 {
    return switch (value) {
        .string => |raw| raw,
        .bool => |raw| switch (kind) {
            .boolean => if (raw) "on" else "off",
            else => error.InvalidConfigJsonValue,
        },
        .integer => |raw| switch (kind) {
            .integer, .text_or_integer => try ownedPrint(result, allocator, "{d}", .{raw}),
            else => error.InvalidConfigJsonValue,
        },
        .number_string => |raw| switch (kind) {
            .integer, .text_or_integer => raw,
            else => error.InvalidConfigJsonValue,
        },
        else => error.InvalidConfigJsonValue,
    };
}

fn ownedPrint(result: *ParsedSource, allocator: Allocator, comptime fmt: []const u8, args: anytype) Allocator.Error![]const u8 {
    const value = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(value);
    try result.owned_values.append(allocator, value);
    return value;
}

test "config json parses canonical fields and native scalar values" {
    var parsed = try parseWithFeatures(
        std.testing.allocator,
        \\{
        \\  "provider": "openrouter",
        \\  "api_key": "key",
        \\  "model": "openai/gpt-chat-latest",
        \\  "max_tokens": 128,
        \\  "stream": false,
        \\  "telegram_chat_id": -42
        \\}
    ,
        .{},
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("openrouter", parsed.source.provider.?);
    try std.testing.expectEqualStrings("key", parsed.source.api_key.?);
    try std.testing.expectEqualStrings("openai/gpt-chat-latest", parsed.source.model.?);
    try std.testing.expectEqualStrings("128", parsed.source.max_tokens.?);
    try std.testing.expectEqualStrings("off", parsed.source.stream.?);
    try std.testing.expectEqualStrings("-42", parsed.source.telegram_chat_id.?);
}

test "config json accepts telegram username allowlist" {
    var parsed = try parseWithFeatures(
        std.testing.allocator,
        \\{
        \\  "provider": "openrouter",
        \\  "api_key": "key",
        \\  "model": "openai/gpt-chat-latest",
        \\  "telegram_chat_id": "@donprus"
        \\}
    ,
        .{},
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("@donprus", parsed.source.telegram_chat_id.?);
}

test "config json rejects unknown and mistyped fields" {
    try std.testing.expectError(
        error.UnknownKey,
        parseWithFeatures(std.testing.allocator, "{\"NLLCLW_PROVIDER\":\"openai\"}", .{}),
    );
    try std.testing.expectError(
        error.InvalidConfigJsonValue,
        parseWithFeatures(std.testing.allocator, "{\"provider\":42}", .{}),
    );
    try std.testing.expectError(
        error.InvalidConfigJsonValue,
        parseWithFeatures(std.testing.allocator, "{\"stream\":{\"enabled\":true}}", .{}),
    );
}

test "config json shell fields require shell feature build" {
    try std.testing.expectError(
        error.InvalidShell,
        parseWithFeatures(std.testing.allocator, "{\"shell\":true}", .{}),
    );
    try std.testing.expectError(
        error.InvalidToolTimeoutMs,
        parseWithFeatures(std.testing.allocator, "{\"tool_timeout_ms\":2500}", .{}),
    );

    var parsed = try parseWithFeatures(
        std.testing.allocator,
        "{\"shell\":true,\"tool_timeout_ms\":2500}",
        .{ .shell_tool = true },
    );
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("on", parsed.source.shell.?);
    try std.testing.expectEqualStrings("2500", parsed.source.tool_timeout_ms.?);
}
