const std = @import("std");
const config = @import("../config.zig");
const http = @import("../ports/http.zig");
const text_policy = @import("../text_policy.zig");

const Allocator = std.mem.Allocator;

pub const default_result_count: usize = 3;

pub const FormatError = Allocator.Error || error{
    InvalidSearchResponse,
    ToolOutputTooLarge,
};

pub const BuildError = Allocator.Error;

pub const not_configured_message =
    "web_search is not configured; set NLLCLW_SEARCH_TAVILY_KEY, NLLCLW_SEARCH_BRAVE_KEY, " ++
    "NLLCLW_SEARCH_EXA_KEY, NLLCLW_SEARCH_FIRECRAWL_KEY, or NLLCLW_SEARCH_DUCKDUCKGO=on\n";

pub const Provider = enum {
    tavily,
    brave,
    exa,
    firecrawl,
    duckduckgo,
};

pub const SelectedProvider = union(Provider) {
    tavily: []const u8,
    brave: []const u8,
    exa: []const u8,
    firecrawl: []const u8,
    duckduckgo,
};

pub fn selectProvider(search: config.SearchConfig) ?SelectedProvider {
    return switch (search.provider) {
        .auto => selectAutoProvider(search),
        .tavily => if (nonEmpty(search.tavily_key)) |key| .{ .tavily = key } else null,
        .brave => if (nonEmpty(search.brave_key)) |key| .{ .brave = key } else null,
        .exa => if (nonEmpty(search.exa_key)) |key| .{ .exa = key } else null,
        .firecrawl => if (nonEmpty(search.firecrawl_key)) |key| .{ .firecrawl = key } else null,
        .duckduckgo => .duckduckgo,
    };
}

pub fn nonEmpty(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    return if (trimmed.len == 0) null else trimmed;
}

pub fn providerName(provider: Provider) []const u8 {
    return switch (provider) {
        .tavily => "tavily",
        .brave => "brave",
        .exa => "exa",
        .firecrawl => "firecrawl",
        .duckduckgo => "duckduckgo",
    };
}

pub fn selectedProvider(selected: SelectedProvider) Provider {
    return switch (selected) {
        .tavily => .tavily,
        .brave => .brave,
        .exa => .exa,
        .firecrawl => .firecrawl,
        .duckduckgo => .duckduckgo,
    };
}

pub fn selectedName(selected: SelectedProvider) []const u8 {
    return providerName(selectedProvider(selected));
}

pub fn bearerAuth(allocator: Allocator, key: []const u8) BuildError![]u8 {
    return std.fmt.allocPrint(allocator, "Bearer {s}", .{key});
}

pub fn buildSearchUrl(allocator: Allocator, endpoint: []const u8, query: []const u8, suffix: []const u8) BuildError![]u8 {
    const escaped = try queryEscape(allocator, query);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "{s}?q={s}{s}", .{ endpoint, escaped, suffix });
}

pub fn formatJson(allocator: Allocator, value: anytype) BuildError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    out.writer.print("{f}", .{std.json.fmt(value, .{ .emit_null_optional_fields = false })}) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

pub fn parseResponse(comptime T: type, allocator: Allocator, body: []const u8) FormatError!std.json.Parsed(T) {
    return std.json.parseFromSlice(T, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidSearchResponse,
    };
}

pub fn queryEscape(allocator: Allocator, value: []const u8) BuildError![]u8 {
    const hex = "0123456789ABCDEF";
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    for (value) |byte| {
        if (isUrlUnreserved(byte)) {
            out.writer.writeByte(byte) catch return error.OutOfMemory;
        } else {
            const encoded = [_]u8{ '%', hex[byte >> 4], hex[byte & 0x0f] };
            out.writer.writeAll(&encoded) catch return error.OutOfMemory;
        }
    }
    return out.toOwnedSlice() catch error.OutOfMemory;
}

pub fn appendHeader(out: *std.Io.Writer.Allocating, provider: Provider, limit: usize) FormatError!void {
    try appendLimited(out, "web_search results:\n", limit);
    try appendLimited(out, "provider: ", limit);
    try appendLimited(out, providerName(provider), limit);
    try appendLimited(out, "\n", limit);
}

pub fn appendAnswer(out: *std.Io.Writer.Allocating, answer: []const u8, limit: usize) FormatError!bool {
    const text = nonEmptyText(answer) orelse return false;
    try appendLimited(out, "answer: ", limit);
    try appendProviderText(out, text, limit);
    try appendLimited(out, "\n", limit);
    return true;
}

pub fn appendResult(
    out: *std.Io.Writer.Allocating,
    title: ?[]const u8,
    url: ?[]const u8,
    snippet: ?[]const u8,
    limit: usize,
) FormatError!bool {
    const maybe_title = nonEmptyOptionalText(title);
    const maybe_url = nonEmptyOptionalText(url);
    const maybe_snippet = nonEmptyOptionalText(snippet);
    if (maybe_title == null and maybe_url == null and maybe_snippet == null) return false;

    const display_title = maybe_title orelse "untitled";
    try appendLimited(out, "- ", limit);
    try appendProviderText(out, display_title, limit);
    if (maybe_url) |value| {
        try appendLimited(out, " (", limit);
        try appendProviderText(out, value, limit);
        try appendLimited(out, ")", limit);
    }
    if (maybe_snippet) |value| {
        try appendLimited(out, ": ", limit);
        try appendProviderText(out, value, limit);
    }
    try appendLimited(out, "\n", limit);
    return true;
}

pub fn appendNoResults(out: *std.Io.Writer.Allocating, limit: usize) FormatError!void {
    try appendLimited(out, "no results\n", limit);
}

pub fn formatHttpFailure(allocator: Allocator, status: http.StatusCode, body: []const u8, limit: usize) FormatError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try appendLimited(&out, "web_search failed: HTTP ", limit);
    const status_text = try std.fmt.allocPrint(allocator, "{d}\n", .{status});
    defer allocator.free(status_text);
    try appendLimited(&out, status_text, limit);
    if (isProviderText(body)) {
        const remaining = limit -| out.written().len;
        const body_limit = if (body.len != 0 and !std.mem.endsWith(u8, body, "\n")) remaining -| 1 else remaining;
        const capped_len = utf8PrefixLen(body, body_limit);
        try appendProviderText(&out, body[0..capped_len], limit);
    } else {
        try appendLimited(&out, "[non-text response body omitted]\n", limit);
    }
    if (!std.mem.endsWith(u8, out.written(), "\n")) try appendLimited(&out, "\n", limit);
    return out.toOwnedSlice();
}

pub fn appendLimited(out: *std.Io.Writer.Allocating, bytes: []const u8, limit: usize) FormatError!void {
    const next_len = std.math.add(usize, out.written().len, bytes.len) catch return error.ToolOutputTooLarge;
    if (next_len > limit) return error.ToolOutputTooLarge;
    out.writer.writeAll(bytes) catch return error.OutOfMemory;
}

fn appendProviderText(out: *std.Io.Writer.Allocating, bytes: []const u8, limit: usize) FormatError!void {
    if (!isProviderText(bytes)) return error.InvalidSearchResponse;
    var start: usize = 0;
    for (bytes, 0..) |byte, index| {
        switch (byte) {
            '\n', '\r', '\t' => {
                if (start < index) try appendLimited(out, bytes[start..index], limit);
                try appendLimited(out, " ", limit);
                start = index + 1;
            },
            else => {},
        }
    }
    if (start < bytes.len) try appendLimited(out, bytes[start..], limit);
}

fn isProviderText(bytes: []const u8) bool {
    return text_policy.isMultilineText(bytes);
}

fn nonEmptyOptionalText(value: ?[]const u8) ?[]const u8 {
    return nonEmptyText(value orelse return null);
}

fn nonEmptyText(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, &std.ascii.whitespace);
    return if (trimmed.len == 0) null else trimmed;
}

fn selectAutoProvider(search: config.SearchConfig) ?SelectedProvider {
    if (nonEmpty(search.tavily_key)) |key| return .{ .tavily = key };
    if (nonEmpty(search.brave_key)) |key| return .{ .brave = key };
    if (nonEmpty(search.exa_key)) |key| return .{ .exa = key };
    if (nonEmpty(search.firecrawl_key)) |key| return .{ .firecrawl = key };
    if (search.duckduckgo_enabled) return .duckduckgo;
    return null;
}

fn isUrlUnreserved(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '.' or byte == '_' or byte == '~';
}

fn utf8PrefixLen(value: []const u8, max_bytes: usize) usize {
    var index: usize = 0;
    while (index < value.len and index < max_bytes) {
        const width = std.unicode.utf8ByteSequenceLength(value[index]) catch break;
        if (index + width > value.len or index + width > max_bytes) break;
        index += width;
    }
    return index;
}

test "select provider deterministically" {
    try std.testing.expect(selectProvider(.{}) == null);
    try std.testing.expectEqualStrings("tavily", selectedName(selectProvider(.{ .tavily_key = "tvly" }).?));
    try std.testing.expectEqualStrings("brave", selectedName(selectProvider(.{ .brave_key = "brave" }).?));
    try std.testing.expectEqualStrings("exa", selectedName(selectProvider(.{ .exa_key = "exa" }).?));
    try std.testing.expectEqualStrings("firecrawl", selectedName(selectProvider(.{ .firecrawl_key = "fc" }).?));
    try std.testing.expectEqualStrings("duckduckgo", selectedName(selectProvider(.{ .duckduckgo_enabled = true }).?));
    try std.testing.expect(selectProvider(.{ .provider = .brave, .tavily_key = "tvly" }) == null);
    try std.testing.expectEqualStrings("duckduckgo", selectedName(selectProvider(.{ .provider = .duckduckgo }).?));
    try std.testing.expect(selectProvider(.{ .brave_key = "   " }) == null);
    try std.testing.expectEqualStrings("brave", selectedName(selectProvider(.{ .brave_key = " brave " }).?));
}

test "query escaping and HTTP failure formatting" {
    const escaped = try queryEscape(std.testing.allocator, "zig lang/+");
    defer std.testing.allocator.free(escaped);
    try std.testing.expectEqualStrings("zig%20lang%2F%2B", escaped);

    const failed = try formatHttpFailure(std.testing.allocator, 429, "rate limited", 4096);
    defer std.testing.allocator.free(failed);
    try std.testing.expect(std.mem.indexOf(u8, failed, "HTTP 429") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed, "rate limited") != null);

    const invalid_body = try formatHttpFailure(std.testing.allocator, 500, "bad\xff", 4096);
    defer std.testing.allocator.free(invalid_body);
    try std.testing.expect(std.unicode.utf8ValidateSlice(invalid_body));
    try std.testing.expect(std.mem.indexOf(u8, invalid_body, "non-text") != null);

    const binary_body = try formatHttpFailure(std.testing.allocator, 500, "bad\x00body", 4096);
    defer std.testing.allocator.free(binary_body);
    try std.testing.expect(std.mem.indexOfScalar(u8, binary_body, 0) == null);
    try std.testing.expect(std.mem.indexOf(u8, binary_body, "non-text") != null);

    const multiline_body = try formatHttpFailure(std.testing.allocator, 500, "line one\nline two", 4096);
    defer std.testing.allocator.free(multiline_body);
    try std.testing.expect(std.mem.indexOf(u8, multiline_body, "line one line two") != null);

    const capped = try formatHttpFailure(std.testing.allocator, 500, "éclair", 31);
    defer std.testing.allocator.free(capped);
    try std.testing.expect(std.unicode.utf8ValidateSlice(capped));
}

test "provider text formatting rejects binary control bytes and normalizes whitespace" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try std.testing.expect(try appendAnswer(&out, "line one\nline two\tend", 4096));
    try std.testing.expect(try appendResult(&out, " title ", "https://example.test/a\nb", "snippet\rtext", 4096));
    try std.testing.expect(!try appendAnswer(&out, "   ", 4096));
    try std.testing.expect(!try appendResult(&out, null, null, null, 4096));
    try std.testing.expectEqualStrings(
        "answer: line one line two end\n- title (https://example.test/a b): snippet text\n",
        out.written(),
    );

    try std.testing.expectError(error.InvalidSearchResponse, appendAnswer(&out, "bad\x00value", 4096));
    try std.testing.expectError(error.InvalidSearchResponse, appendResult(&out, "bad\x1fvalue", null, null, 4096));
}

test "parse response preserves allocation failures" {
    const TinyResponse = struct {
        value: []const u8,
    };

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            const parsed = try parseResponse(TinyResponse, allocator, "{\"value\":\"ok\"}");
            defer parsed.deinit();
            try std.testing.expectEqualStrings("ok", parsed.value.value);
        }
    }.run, .{});
}
