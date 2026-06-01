const std = @import("std");
const http = @import("./ports/http.zig");

const Allocator = std.mem.Allocator;

pub const ProviderKind = enum {
    openai,
    openrouter,
    compatible,
};

pub const Config = struct {
    provider: ProviderKind,
    api_key: []const u8,
    base_url: ?[]const u8 = null,
    allow_insecure_base_url: bool = false,
    http_referer: ?[]const u8 = null,
    app_title: ?[]const u8 = null,
};

pub const Resolved = struct {
    endpoint: []u8,
    headers: []http.Header,
    authorization: []u8,

    pub fn deinit(self: *Resolved, allocator: Allocator) void {
        allocator.free(self.endpoint);
        allocator.free(self.headers);
        allocator.free(self.authorization);
        self.* = undefined;
    }
};

pub const ResolveError = error{
    MissingBaseUrl,
    EmptyBaseUrl,
    InvalidBaseUrl,
    InsecureBaseUrl,
    InvalidHeaderValue,
} || Allocator.Error;

pub fn resolve(allocator: Allocator, cfg: Config) ResolveError!Resolved {
    const endpoint = switch (cfg.provider) {
        .openai => try allocator.dupe(u8, "https://api.openai.com/v1/chat/completions"),
        .openrouter => try allocator.dupe(u8, "https://openrouter.ai/api/v1/chat/completions"),
        .compatible => try compatibleEndpoint(
            allocator,
            cfg.base_url orelse return error.MissingBaseUrl,
            cfg.allow_insecure_base_url,
        ),
    };
    errdefer allocator.free(endpoint);

    if (cfg.api_key.len == 0) return error.InvalidHeaderValue;
    try validateHeaderValue(cfg.api_key);
    if (cfg.http_referer) |value| try validateHeaderValue(value);
    if (cfg.app_title) |value| try validateHeaderValue(value);

    const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{cfg.api_key});
    errdefer allocator.free(authorization);

    var headers: std.ArrayList(http.Header) = .empty;
    errdefer headers.deinit(allocator);

    try headers.append(allocator, .{ .name = "Authorization", .value = authorization });
    try headers.append(allocator, .{ .name = "Content-Type", .value = "application/json" });
    try headers.append(allocator, .{ .name = "User-Agent", .value = "nllclw/0.1" });

    if (cfg.provider == .openrouter) {
        if (cfg.http_referer) |value| {
            try headers.append(allocator, .{ .name = "HTTP-Referer", .value = value });
        }
        if (cfg.app_title) |value| {
            try headers.append(allocator, .{ .name = "X-OpenRouter-Title", .value = value });
        }
    }

    return .{
        .endpoint = endpoint,
        .headers = try headers.toOwnedSlice(allocator),
        .authorization = authorization,
    };
}

pub fn validateCompatibleBaseUrl(base_url: []const u8, allow_insecure: bool) error{ EmptyBaseUrl, InvalidBaseUrl, InsecureBaseUrl }![]const u8 {
    const stripped = std.mem.trim(u8, base_url, &std.ascii.whitespace);
    var end = stripped.len;
    while (end != 0 and stripped[end - 1] == '/') end -= 1;
    const trimmed = stripped[0..end];
    if (trimmed.len == 0) return error.EmptyBaseUrl;
    if (containsInvalidUrlByte(trimmed)) return error.InvalidBaseUrl;
    const uri = std.Uri.parse(trimmed) catch return error.InvalidBaseUrl;
    if (uri.host == null or uri.user != null or uri.password != null or uri.query != null or uri.fragment != null) {
        return error.InvalidBaseUrl;
    }
    if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) return trimmed;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "http")) {
        if (allow_insecure and isLocalHttpHost(uri, trimmed)) return trimmed;
        return error.InsecureBaseUrl;
    }
    return error.InvalidBaseUrl;
}

fn compatibleEndpoint(allocator: Allocator, base_url: []const u8, allow_insecure: bool) ![]u8 {
    const trimmed = try validateCompatibleBaseUrl(base_url, allow_insecure);
    return std.fmt.allocPrint(allocator, "{s}/chat/completions", .{trimmed});
}

fn containsInvalidUrlByte(url: []const u8) bool {
    for (url) |byte| {
        if (byte <= ' ' or byte == 0x7f) return true;
    }
    return false;
}

fn isLocalHttpHost(uri: std.Uri, url: []const u8) bool {
    const host_component = uri.host orelse return false;
    const encoded_host = uriComponentBytes(host_component);
    const rest = url["http://".len..];
    if (!std.mem.startsWith(u8, rest, encoded_host)) return false;
    if (rest.len != encoded_host.len and rest[encoded_host.len] != ':' and rest[encoded_host.len] != '/') return false;

    var host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = uri.getHost(&host_buffer) catch return false;
    return std.ascii.eqlIgnoreCase(host.bytes, "localhost") or
        std.mem.eql(u8, host.bytes, "127.0.0.1") or
        std.mem.eql(u8, host.bytes, "[::1]");
}

fn uriComponentBytes(component: std.Uri.Component) []const u8 {
    return switch (component) {
        .raw, .percent_encoded => |bytes| bytes,
    };
}

pub fn validateHeaderValue(value: []const u8) error{InvalidHeaderValue}!void {
    for (value) |byte| {
        if (byte < ' ' or byte == 0x7f) return error.InvalidHeaderValue;
    }
}

fn headerValue(headers: []const http.Header, name: []const u8) ?[]const u8 {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}

test "resolves OpenAI endpoint" {
    var resolved = try resolve(std.testing.allocator, .{
        .provider = .openai,
        .api_key = "key",
    });
    defer resolved.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("https://api.openai.com/v1/chat/completions", resolved.endpoint);
    try std.testing.expectEqualStrings("Bearer key", headerValue(resolved.headers, "authorization").?);
}

test "resolves OpenRouter endpoint and optional headers" {
    var resolved = try resolve(std.testing.allocator, .{
        .provider = .openrouter,
        .api_key = "key",
        .http_referer = "https://example.test",
        .app_title = "nllclw",
    });
    defer resolved.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("https://openrouter.ai/api/v1/chat/completions", resolved.endpoint);
    try std.testing.expectEqualStrings("https://example.test", headerValue(resolved.headers, "HTTP-Referer").?);
    try std.testing.expectEqualStrings("nllclw", headerValue(resolved.headers, "X-OpenRouter-Title").?);
}

test "compatible endpoint trims trailing slashes" {
    var resolved = try resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = " https://example.test/v1/// ",
    });
    defer resolved.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("https://example.test/v1/chat/completions", resolved.endpoint);
}

test "compatible endpoint rejects insecure remote urls" {
    try std.testing.expectError(error.InsecureBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "http://example.test/v1",
    }));

    var resolved = try resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "http://127.0.0.1:11434/v1",
        .allow_insecure_base_url = true,
    });
    defer resolved.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("http://127.0.0.1:11434/v1/chat/completions", resolved.endpoint);
}

test "compatible endpoint allows only exact loopback HTTP hosts" {
    for ([_][]const u8{
        "http://localhost.evil.test/v1",
        "http://127.0.0.1.evil.test/v1",
        "http://[::1].evil.test/v1",
    }) |url| {
        try std.testing.expectError(error.InsecureBaseUrl, resolve(std.testing.allocator, .{
            .provider = .compatible,
            .api_key = "key",
            .base_url = url,
            .allow_insecure_base_url = true,
        }));
    }

    inline for ([_][]const u8{
        "http://localhost/v1",
        "http://localhost:11434/v1",
        "http://local%68ost:11434/v1",
        "http://127.0.0.1/v1",
        "http://[::1]:11434/v1",
    }) |url| {
        var resolved = try resolve(std.testing.allocator, .{
            .provider = .compatible,
            .api_key = "key",
            .base_url = url,
            .allow_insecure_base_url = true,
        });
        defer resolved.deinit(std.testing.allocator);
        try std.testing.expect(std.mem.endsWith(u8, resolved.endpoint, "/chat/completions"));
    }
}

test "compatible endpoint rejects malformed or credentialed urls" {
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "example.test/v1",
    }));
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "https://user:pass@example.test/v1",
    }));
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "https:///v1",
    }));
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "https://example.test/v1?x=1",
    }));
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "https://example.test/v1#fragment",
    }));
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "https://example.test/v1 bad",
    }));
    try std.testing.expectError(error.InvalidBaseUrl, resolve(std.testing.allocator, .{
        .provider = .compatible,
        .api_key = "key",
        .base_url = "https://example.test/v1\r\nX-Bad: value",
    }));
}

test "provider headers reject injection bytes" {
    try std.testing.expectError(error.InvalidHeaderValue, resolve(std.testing.allocator, .{
        .provider = .openai,
        .api_key = "",
    }));

    try std.testing.expectError(error.InvalidHeaderValue, resolve(std.testing.allocator, .{
        .provider = .openai,
        .api_key = "key\r\nX-Bad: value",
    }));

    try std.testing.expectError(error.InvalidHeaderValue, resolve(std.testing.allocator, .{
        .provider = .openrouter,
        .api_key = "key",
        .http_referer = "https://example.test\nx",
    }));
    try std.testing.expectError(error.InvalidHeaderValue, resolve(std.testing.allocator, .{
        .provider = .openrouter,
        .api_key = "key\x1f",
    }));
}
