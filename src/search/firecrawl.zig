const std = @import("std");
const common = @import("./common.zig");
const http = @import("../ports/http.zig");

const Allocator = std.mem.Allocator;

pub const endpoint = "https://api.firecrawl.dev/v2/search";

const Response = struct {
    data: Data = .{},
};

const Data = struct {
    web: []const Result = &.{},
};

const Result = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    markdown: ?[]const u8 = null,
};

const Request = struct {
    query: []const u8,
    limit: usize = common.default_result_count,
    sources: []const []const u8,
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
    const sources = [_][]const u8{"web"};
    return common.formatJson(allocator, Request{ .query = query, .sources = &sources });
}

pub fn format(allocator: Allocator, body: []const u8, limit: usize) common.FormatError![]u8 {
    const parsed = try common.parseResponse(Response, allocator, body);
    defer parsed.deinit();

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try common.appendHeader(&out, .firecrawl, limit);
    var emitted = false;
    var count: usize = 0;
    for (parsed.value.data.web) |result| {
        if (count >= common.default_result_count) break;
        const snippet = result.description orelse result.markdown;
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
    try std.testing.expect(std.mem.indexOf(u8, body, "\"limit\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"sources\":[\"web\"]") != null);

    const text = try format(
        std.testing.allocator,
        "{\"data\":{\"web\":[{\"title\":\"F\",\"url\":\"https://f.test\",\"description\":\"foxtrot\"}]}}",
        4096,
    );
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "provider: firecrawl") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "foxtrot") != null);

    const empty = try format(std.testing.allocator, "{\"data\":{\"web\":[{}]}}", 4096);
    defer std.testing.allocator.free(empty);
    try std.testing.expect(std.mem.indexOf(u8, empty, "no results") != null);
}
