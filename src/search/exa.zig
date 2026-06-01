const std = @import("std");
const common = @import("./common.zig");
const http = @import("../ports/http.zig");

const Allocator = std.mem.Allocator;

pub const endpoint = "https://api.exa.ai/search";

const Response = struct {
    results: []const Result = &.{},
};

const Result = struct {
    title: ?[]const u8 = null,
    url: ?[]const u8 = null,
    text: ?[]const u8 = null,
    highlights: []const []const u8 = &.{},
};

const Request = struct {
    query: []const u8,
    numResults: usize = common.default_result_count,
    contents: Contents = .{},
};

const Contents = struct {
    highlights: bool = true,
};

pub fn call(client: http.Client, allocator: Allocator, key: []const u8, query: []const u8) http.Error!http.Response {
    const body = buildRequest(allocator, query) catch return error.OutOfMemory;
    defer allocator.free(body);

    const headers = [_]http.Header{
        .{ .name = "x-api-key", .value = key },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "User-Agent", .value = "nllclw/0.1" },
    };
    return client.postJson(allocator, .{
        .url = endpoint,
        .headers = &headers,
        .body = body,
    });
}

pub fn buildRequest(allocator: Allocator, query: []const u8) common.BuildError![]u8 {
    return common.formatJson(allocator, Request{ .query = query });
}

pub fn format(allocator: Allocator, body: []const u8, limit: usize) common.FormatError![]u8 {
    const parsed = try common.parseResponse(Response, allocator, body);
    defer parsed.deinit();

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try common.appendHeader(&out, .exa, limit);
    var emitted = false;
    var count: usize = 0;
    for (parsed.value.results) |result| {
        if (count >= common.default_result_count) break;
        const snippet = if (result.highlights.len > 0) result.highlights[0] else result.text;
        if (try common.appendResult(&out, result.title, result.url, snippet, limit)) {
            count += 1;
            emitted = true;
        }
    }
    if (!emitted) try common.appendNoResults(&out, limit);
    return out.toOwnedSlice();
}

test "build request and format response" {
    const body = try buildRequest(std.testing.allocator, "zig lang");
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"numResults\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"highlights\":true") != null);

    const text = try format(
        std.testing.allocator,
        "{\"results\":[{\"title\":\"E\",\"url\":\"https://e.test\",\"highlights\":[\"echo\"]}]}",
        4096,
    );
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "provider: exa") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "echo") != null);

    const empty = try format(std.testing.allocator, "{\"results\":[{}]}", 4096);
    defer std.testing.allocator.free(empty);
    try std.testing.expect(std.mem.indexOf(u8, empty, "no results") != null);
}
