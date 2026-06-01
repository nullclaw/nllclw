const std = @import("std");
const common = @import("./common.zig");
const http = @import("../ports/http.zig");

const Allocator = std.mem.Allocator;

pub const endpoint = "https://api.search.brave.com/res/v1/web/search";

const Response = struct {
    web: ?Web = null,
};

const Web = struct {
    results: []const Result = &.{},
};

const Result = struct {
    title: ?[]const u8 = null,
    url: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub fn call(client: http.Client, allocator: Allocator, key: []const u8, query: []const u8) http.Error!http.Response {
    const url = common.buildSearchUrl(allocator, endpoint, query, "&count=3") catch return error.OutOfMemory;
    defer allocator.free(url);

    const headers = [_]http.Header{
        .{ .name = "X-Subscription-Token", .value = key },
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "User-Agent", .value = "nllclw/0.1" },
    };
    return client.postJson(allocator, .{
        .url = url,
        .method = .get,
        .headers = &headers,
        .body = "",
    });
}

pub fn format(allocator: Allocator, body: []const u8, limit: usize) common.FormatError![]u8 {
    const parsed = try common.parseResponse(Response, allocator, body);
    defer parsed.deinit();

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try common.appendHeader(&out, .brave, limit);
    var emitted = false;
    if (parsed.value.web) |web| {
        var count: usize = 0;
        for (web.results) |result| {
            if (count >= common.default_result_count) break;
            if (try common.appendResult(&out, result.title, result.url, result.description, limit)) {
                count += 1;
                emitted = true;
            }
        }
    }
    if (!emitted) try common.appendNoResults(&out, limit);
    return out.toOwnedSlice();
}

test "format response" {
    const text = try format(
        std.testing.allocator,
        "{\"web\":{\"results\":[{\"title\":\"B\",\"url\":\"https://b.test\",\"description\":\"beta\"}]}}",
        4096,
    );
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "provider: brave") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "https://b.test") != null);

    const empty = try format(std.testing.allocator, "{\"web\":{\"results\":[{}]}}", 4096);
    defer std.testing.allocator.free(empty);
    try std.testing.expect(std.mem.indexOf(u8, empty, "no results") != null);
}
