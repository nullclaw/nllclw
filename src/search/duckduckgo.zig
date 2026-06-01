const std = @import("std");
const common = @import("./common.zig");
const http = @import("../ports/http.zig");

const Allocator = std.mem.Allocator;

pub const endpoint = "https://api.duckduckgo.com/";

const Response = struct {
    Heading: ?[]const u8 = null,
    AbstractText: ?[]const u8 = null,
    AbstractURL: ?[]const u8 = null,
    Answer: ?[]const u8 = null,
    RelatedTopics: []const Topic = &.{},
};

const Topic = struct {
    Text: ?[]const u8 = null,
    FirstURL: ?[]const u8 = null,
    Topics: []const Topic = &.{},
};

const max_topic_depth: usize = 4;

pub fn call(client: http.Client, allocator: Allocator, query: []const u8) http.Error!http.Response {
    const url = common.buildSearchUrl(
        allocator,
        endpoint,
        query,
        "&format=json&no_redirect=1&no_html=1&skip_disambig=1",
    ) catch return error.OutOfMemory;
    defer allocator.free(url);

    const headers = [_]http.Header{
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
    try common.appendHeader(&out, .duckduckgo, limit);
    var emitted = false;
    if (parsed.value.Answer) |answer| emitted = try common.appendAnswer(&out, answer, limit) or emitted;
    emitted = try common.appendResult(&out, parsed.value.Heading, parsed.value.AbstractURL, parsed.value.AbstractText, limit) or emitted;
    var count: usize = 0;
    try appendTopics(&out, parsed.value.RelatedTopics, limit, &count, &emitted, 0);
    if (!emitted) try common.appendNoResults(&out, limit);
    return out.toOwnedSlice();
}

fn appendTopics(
    out: *std.Io.Writer.Allocating,
    topics: []const Topic,
    limit: usize,
    count: *usize,
    emitted: *bool,
    depth: usize,
) common.FormatError!void {
    if (depth >= max_topic_depth) return;
    for (topics) |topic| {
        if (count.* >= common.default_result_count) return;
        if (try common.appendResult(out, topic.Text, topic.FirstURL, null, limit)) {
            count.* += 1;
            emitted.* = true;
        }
        try appendTopics(out, topic.Topics, limit, count, emitted, depth + 1);
    }
}

test "format response" {
    const text = try format(
        std.testing.allocator,
        "{\"Heading\":\"D\",\"AbstractText\":\"delta\",\"AbstractURL\":\"https://d.test\",\"RelatedTopics\":[{\"Text\":\"topic\",\"FirstURL\":\"https://topic.test\"}]}",
        4096,
    );
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "provider: duckduckgo") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "delta") != null);

    const nested = try format(
        std.testing.allocator,
        "{\"RelatedTopics\":[{\"Name\":\"Zig\",\"Topics\":[{\"Text\":\"nested topic\",\"FirstURL\":\"https://nested.test\"}]}]}",
        4096,
    );
    defer std.testing.allocator.free(nested);
    try std.testing.expect(std.mem.indexOf(u8, nested, "nested topic") != null);

    const empty = try format(std.testing.allocator, "{\"RelatedTopics\":[{}]}", 4096);
    defer std.testing.allocator.free(empty);
    try std.testing.expect(std.mem.indexOf(u8, empty, "no results") != null);
}
