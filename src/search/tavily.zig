const std = @import("std");
const common = @import("./common.zig");
const http = @import("../ports/http.zig");

const Allocator = std.mem.Allocator;

pub const endpoint = "https://api.tavily.com/search";

const Response = struct {
    answer: ?[]const u8 = null,
    results: []const Result = &.{},
};

const Result = struct {
    title: ?[]const u8 = null,
    url: ?[]const u8 = null,
    content: ?[]const u8 = null,
};

const Request = struct {
    query: []const u8,
    search_depth: []const u8 = "basic",
    max_results: usize = common.default_result_count,
};

pub fn call(client: http.Client, allocator: Allocator, key: []const u8, query: []const u8) http.Error!http.Response {
    const body = buildRequest(allocator, query) catch return error.OutOfMemory;
    defer allocator.free(body);
    const auth = common.bearerAuth(allocator, key) catch return error.OutOfMemory;
    defer allocator.free(auth);

    const headers = [_]http.Header{
        .{ .name = "Authorization", .value = auth },
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
    try common.appendHeader(&out, .tavily, limit);
    var emitted = false;
    if (parsed.value.answer) |answer| emitted = try common.appendAnswer(&out, answer, limit) or emitted;
    var count: usize = 0;
    for (parsed.value.results) |result| {
        if (count >= common.default_result_count) break;
        if (try common.appendResult(&out, result.title, result.url, result.content, limit)) {
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
    try std.testing.expect(std.mem.indexOf(u8, body, "\"query\":\"zig lang\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"max_results\":3") != null);

    const text = try format(
        std.testing.allocator,
        "{\"answer\":\"short\",\"results\":[{\"title\":\"A\",\"url\":\"https://a.test\",\"content\":\"alpha\"}]}",
        4096,
    );
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "provider: tavily") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "answer: short") != null);

    const empty = try format(std.testing.allocator, "{\"results\":[{}]}", 4096);
    defer std.testing.allocator.free(empty);
    try std.testing.expect(std.mem.indexOf(u8, empty, "no results") != null);
}
