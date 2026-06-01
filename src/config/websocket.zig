const std = @import("std");
const text_policy = @import("../text_policy.zig");
const types = @import("./types.zig");

pub const ParseError = error{
    InvalidWebSocketHost,
    InvalidWebSocketPort,
    InvalidWebSocketPath,
    InvalidWebSocketToken,
    InvalidWebSocketAllowRemote,
    InvalidWebSocketRateLimit,
};

pub const Raw = struct {
    host: ?[]const u8 = null,
    port: ?[]const u8 = null,
    path: ?[]const u8 = null,
    token: ?[]const u8 = null,
    allow_remote: ?[]const u8 = null,
    rate_limit_per_minute: ?[]const u8 = null,
};

pub fn fromRaw(raw: Raw) ParseError!types.WebSocketConfig {
    return .{
        .host = try parseHost(raw.host),
        .port = try parsePort(raw.port),
        .path = try parsePath(raw.path),
        .token = try parseToken(raw.token),
        .allow_remote = try parseAllowRemote(raw.allow_remote),
        .rate_limit_per_minute = try parseRateLimit(raw.rate_limit_per_minute),
    };
}

fn parseHost(value: ?[]const u8) ParseError![]const u8 {
    const raw = clean(value) orelse return types.default_websocket_host;
    if (raw.len > 255) return error.InvalidWebSocketHost;
    for (raw) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '/' or byte == '?' or byte == '#') {
            return error.InvalidWebSocketHost;
        }
    }
    _ = std.Io.net.IpAddress.parse(raw, 1) catch return error.InvalidWebSocketHost;
    return raw;
}

fn parsePort(value: ?[]const u8) ParseError!u16 {
    const raw = clean(value) orelse return types.default_websocket_port;
    const parsed = std.fmt.parseInt(u16, raw, 10) catch return error.InvalidWebSocketPort;
    if (parsed == 0) return error.InvalidWebSocketPort;
    return parsed;
}

fn parsePath(value: ?[]const u8) ParseError![]const u8 {
    const raw = clean(value) orelse return types.default_websocket_path;
    if (raw.len == 0 or raw.len > 128 or raw[0] != '/') return error.InvalidWebSocketPath;
    if (!text_policy.isSingleLineText(raw)) return error.InvalidWebSocketPath;
    for (raw) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '?' or byte == '#') return error.InvalidWebSocketPath;
    }
    return raw;
}

fn parseToken(value: ?[]const u8) ParseError!?[]const u8 {
    const raw = clean(value) orelse return null;
    if (raw.len < 8 or raw.len > 256) return error.InvalidWebSocketToken;
    for (raw) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        switch (byte) {
            '-', '_', '.', '~' => {},
            else => return error.InvalidWebSocketToken,
        }
    }
    return raw;
}

fn parseAllowRemote(value: ?[]const u8) ParseError!bool {
    const raw = clean(value) orelse return false;
    return parseBool(raw) orelse error.InvalidWebSocketAllowRemote;
}

fn parseRateLimit(value: ?[]const u8) ParseError!u32 {
    const raw = clean(value) orelse return types.default_websocket_rate_limit_per_minute;
    const parsed = std.fmt.parseInt(u32, raw, 10) catch return error.InvalidWebSocketRateLimit;
    if (parsed > 10_000) return error.InvalidWebSocketRateLimit;
    return parsed;
}

fn clean(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    return if (trimmed.len == 0) null else trimmed;
}

fn parseBool(raw: []const u8) ?bool {
    if (std.mem.eql(u8, raw, "on")) return true;
    if (std.mem.eql(u8, raw, "off")) return false;
    return null;
}

test "websocket config defaults and overrides" {
    const defaults = try fromRaw(.{});
    try std.testing.expectEqualStrings("127.0.0.1", defaults.host);
    try std.testing.expectEqual(@as(u16, 8765), defaults.port);
    try std.testing.expectEqualStrings("/ws", defaults.path);
    try std.testing.expect(defaults.token == null);
    try std.testing.expect(!defaults.allow_remote);
    try std.testing.expectEqual(@as(u32, 20), defaults.rate_limit_per_minute);

    const cfg = try fromRaw(.{
        .host = "0.0.0.0",
        .port = "9001",
        .path = "/agent",
        .token = "ws-token",
        .allow_remote = "on",
        .rate_limit_per_minute = "30",
    });
    try std.testing.expectEqualStrings("0.0.0.0", cfg.host);
    try std.testing.expectEqual(@as(u16, 9001), cfg.port);
    try std.testing.expectEqualStrings("/agent", cfg.path);
    try std.testing.expectEqualStrings("ws-token", cfg.token.?);
    try std.testing.expect(cfg.allow_remote);
    try std.testing.expectEqual(@as(u32, 30), cfg.rate_limit_per_minute);
}

test "invalid websocket config is rejected" {
    try std.testing.expectError(error.InvalidWebSocketHost, fromRaw(.{ .host = "127.0.0.1/ws" }));
    try std.testing.expectError(error.InvalidWebSocketHost, fromRaw(.{ .host = "127.0.0.1\x7f" }));
    try std.testing.expectError(error.InvalidWebSocketPort, fromRaw(.{ .port = "0" }));
    try std.testing.expectError(error.InvalidWebSocketPath, fromRaw(.{ .path = "ws" }));
    try std.testing.expectError(error.InvalidWebSocketPath, fromRaw(.{ .path = "/ws\x7f" }));
    try std.testing.expectError(error.InvalidWebSocketPath, fromRaw(.{ .path = "/ws\xff" }));
    try std.testing.expectError(error.InvalidWebSocketToken, fromRaw(.{ .token = "short" }));
    try std.testing.expectError(error.InvalidWebSocketToken, fromRaw(.{ .token = "not=query" }));
    try std.testing.expectError(error.InvalidWebSocketAllowRemote, fromRaw(.{ .allow_remote = "maybe" }));
    try std.testing.expectError(error.InvalidWebSocketAllowRemote, fromRaw(.{ .allow_remote = "true" }));
    try std.testing.expectError(error.InvalidWebSocketAllowRemote, fromRaw(.{ .allow_remote = "1" }));
    try std.testing.expectError(error.InvalidWebSocketRateLimit, fromRaw(.{ .rate_limit_per_minute = "10001" }));
}
