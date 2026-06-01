const std = @import("std");
const chat = @import("../chat.zig");
const config = @import("../config.zig");
const http = @import("../ports/http.zig");
const search = @import("../search.zig");
const text_policy = @import("../text_policy.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;

const query_parameter = [_]chat.ToolParameter{
    .{
        .name = "query",
        .kind = .string,
        .description = "Search query.",
    },
};

pub const definition: chat.ToolDefinition = .{
    .name = "web_search",
    .description = "Search the web for current information through the configured search provider.",
    .parameters = .{
        .properties = &query_parameter,
        .required = &.{"query"},
    },
};

pub const Client = struct {
    client: http.Client,
    search_config: config.SearchConfig,
    output_max_bytes: usize,

    pub fn init(client: http.Client, search_config: config.SearchConfig, output_max_bytes: usize) Client {
        return .{
            .client = client,
            .search_config = search_config,
            .output_max_bytes = output_max_bytes,
        };
    }

    pub fn handler(self: *Client) tool.Handler {
        return .{ .definition = definition, .ptr = self, .run_fn = run, .untrusted_output = true };
    }

    pub fn configured(self: Client) bool {
        return search.selectProvider(self.search_config) != null;
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const selected = search.selectProvider(self.search_config) orelse {
            if (search.not_configured_message.len > self.output_max_bytes) return error.ToolOutputTooLarge;
            return try allocator.dupe(u8, search.not_configured_message);
        };
        const query = try parseQuery(allocator, call.arguments);
        defer allocator.free(query);

        var response = callProvider(self.client, allocator, selected, query) catch |err| return mapHttpError(err);
        defer response.deinit(allocator);

        if (response.status != 200) {
            return search.formatHttpFailure(allocator, response.status, response.body, self.output_max_bytes) catch |err| {
                return mapFormatError(err);
            };
        }
        return formatProviderResponse(allocator, selected, response.body, self.output_max_bytes) catch |err| {
            return mapFormatError(err);
        };
    }
};

const SearchArgs = struct {
    query: []const u8 = "",
};

fn callProvider(
    client: http.Client,
    allocator: Allocator,
    selected: search.SelectedProvider,
    query: []const u8,
) http.Error!http.Response {
    return switch (selected) {
        .tavily => |key| search.tavily.call(client, allocator, key, query),
        .brave => |key| search.brave.call(client, allocator, key, query),
        .exa => |key| search.exa.call(client, allocator, key, query),
        .firecrawl => |key| search.firecrawl.call(client, allocator, key, query),
        .duckduckgo => search.duckduckgo.call(client, allocator, query),
    };
}

fn formatProviderResponse(
    allocator: Allocator,
    selected: search.SelectedProvider,
    body: []const u8,
    limit: usize,
) search.common.FormatError![]u8 {
    return switch (selected) {
        .tavily => search.tavily.format(allocator, body, limit),
        .brave => search.brave.format(allocator, body, limit),
        .exa => search.exa.format(allocator, body, limit),
        .firecrawl => search.firecrawl.format(allocator, body, limit),
        .duckduckgo => search.duckduckgo.format(allocator, body, limit),
    };
}

fn parseQuery(allocator: Allocator, arguments: []const u8) tool.RunError![]u8 {
    const parsed = try tool.parseArgs(SearchArgs, allocator, arguments, .{});
    defer parsed.deinit();

    const query = std.mem.trim(u8, parsed.value.query, &std.ascii.whitespace);
    if (!isValidQuery(query)) return error.InvalidToolArguments;
    return try allocator.dupe(u8, query);
}

fn isValidQuery(query: []const u8) bool {
    if (query.len == 0 or query.len > 512) return false;
    return text_policy.isSingleLineText(query);
}

fn mapHttpError(err: http.Error) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.ToolFailed,
    };
}

fn mapFormatError(err: search.common.FormatError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
        error.InvalidSearchResponse => error.ToolFailed,
    };
}

const FakeHttp = struct {
    status: http.StatusCode = 200,
    body: []const u8 = "{\"answer\":\"ok\",\"results\":[]}",
    fail_request: bool = false,
    seen_url: ?[]u8 = null,
    seen_body: ?[]u8 = null,
    seen_auth: ?[]u8 = null,
    seen_api_key: ?[]u8 = null,
    seen_subscription: ?[]u8 = null,
    seen_method: ?http.Method = null,

    fn deinit(self: *FakeHttp, allocator: Allocator) void {
        if (self.seen_url) |value| allocator.free(value);
        if (self.seen_body) |value| allocator.free(value);
        if (self.seen_auth) |value| allocator.free(value);
        if (self.seen_api_key) |value| allocator.free(value);
        if (self.seen_subscription) |value| allocator.free(value);
        self.* = undefined;
    }

    fn client(self: *FakeHttp) http.Client {
        return .{
            .ptr = self,
            .post_json = postJson,
        };
    }

    fn postJson(ptr: *anyopaque, allocator: Allocator, request: http.Request) http.Error!http.Response {
        const self: *FakeHttp = @ptrCast(@alignCast(ptr));
        if (self.fail_request) return error.RequestFailed;
        self.seen_method = request.method;
        self.seen_url = try allocator.dupe(u8, request.url);
        self.seen_body = try allocator.dupe(u8, request.body);
        for (request.headers) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
                self.seen_auth = try allocator.dupe(u8, header.value);
            } else if (std.ascii.eqlIgnoreCase(header.name, "x-api-key")) {
                self.seen_api_key = try allocator.dupe(u8, header.value);
            } else if (std.ascii.eqlIgnoreCase(header.name, "x-subscription-token")) {
                self.seen_subscription = try allocator.dupe(u8, header.value);
            }
        }
        return .{
            .status = self.status,
            .body = try allocator.dupe(u8, self.body),
        };
    }
};

test "handler sends Tavily request and formats output" {
    var fake: FakeHttp = .{};
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.client(), .{ .tavily_key = "tvly-key" }, 4096);

    const output = try client.handler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "web_search",
        .arguments = "{\"query\":\" zig news \"}",
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqual(http.Method.post, fake.seen_method.?);
    try std.testing.expectEqualStrings(search.tavily.endpoint, fake.seen_url.?);
    try std.testing.expectEqualStrings("Bearer tvly-key", fake.seen_auth.?);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"query\":\"zig news\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "provider: tavily") != null);
}

test "handler sends Brave request with search token" {
    var fake: FakeHttp = .{ .body = "{\"web\":{\"results\":[{\"title\":\"B\",\"url\":\"https://b.test\",\"description\":\"beta\"}]}}" };
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.client(), .{ .provider = .brave, .brave_key = "brave-key" }, 4096);

    const output = try client.handler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "web_search",
        .arguments = "{\"query\":\"zig lang\"}",
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqual(http.Method.get, fake.seen_method.?);
    try std.testing.expect(std.mem.startsWith(u8, fake.seen_url.?, search.brave.endpoint));
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_url.?, "q=zig%20lang") != null);
    try std.testing.expectEqualStrings("brave-key", fake.seen_subscription.?);
    try std.testing.expect(std.mem.indexOf(u8, output, "provider: brave") != null);
}

test "handler supports Exa Firecrawl and DuckDuckGo" {
    var exa_fake: FakeHttp = .{ .body = "{\"results\":[{\"title\":\"E\",\"url\":\"https://e.test\",\"highlights\":[\"echo\"]}]}" };
    defer exa_fake.deinit(std.testing.allocator);
    var exa_client = Client.init(exa_fake.client(), .{ .provider = .exa, .exa_key = "exa-key" }, 4096);
    const exa_output = try exa_client.handler().run(std.testing.allocator, .{
        .id = "call_exa",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    });
    defer std.testing.allocator.free(exa_output);
    try std.testing.expectEqualStrings(search.exa.endpoint, exa_fake.seen_url.?);
    try std.testing.expectEqualStrings("exa-key", exa_fake.seen_api_key.?);
    try std.testing.expect(std.mem.indexOf(u8, exa_output, "provider: exa") != null);

    var firecrawl_fake: FakeHttp = .{ .body = "{\"data\":{\"web\":[{\"title\":\"F\",\"url\":\"https://f.test\",\"description\":\"foxtrot\"}]}}" };
    defer firecrawl_fake.deinit(std.testing.allocator);
    var firecrawl_client = Client.init(firecrawl_fake.client(), .{ .provider = .firecrawl, .firecrawl_key = "fc-key" }, 4096);
    const firecrawl_output = try firecrawl_client.handler().run(std.testing.allocator, .{
        .id = "call_fc",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    });
    defer std.testing.allocator.free(firecrawl_output);
    try std.testing.expectEqualStrings(search.firecrawl.endpoint, firecrawl_fake.seen_url.?);
    try std.testing.expectEqualStrings("Bearer fc-key", firecrawl_fake.seen_auth.?);
    try std.testing.expect(std.mem.indexOf(u8, firecrawl_output, "provider: firecrawl") != null);

    var duck_fake: FakeHttp = .{
        .body = "{\"Heading\":\"D\",\"AbstractText\":\"delta\",\"AbstractURL\":\"https://d.test\",\"RelatedTopics\":[]}",
    };
    defer duck_fake.deinit(std.testing.allocator);
    var duck_client = Client.init(duck_fake.client(), .{ .provider = .duckduckgo }, 4096);
    const duck_output = try duck_client.handler().run(std.testing.allocator, .{
        .id = "call_duck",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    });
    defer std.testing.allocator.free(duck_output);
    try std.testing.expectEqual(http.Method.get, duck_fake.seen_method.?);
    try std.testing.expect(std.mem.startsWith(u8, duck_fake.seen_url.?, search.duckduckgo.endpoint));
    try std.testing.expect(std.mem.indexOf(u8, duck_output, "provider: duckduckgo") != null);
}

test "handler validates configuration query and HTTP failures" {
    var fake: FakeHttp = .{};
    defer fake.deinit(std.testing.allocator);

    var missing_key = Client.init(fake.client(), .{}, 4096);
    const unconfigured = try missing_key.handler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    });
    defer std.testing.allocator.free(unconfigured);
    try std.testing.expect(std.mem.indexOf(u8, unconfigured, "not configured") != null);

    var missing_key_capped = Client.init(fake.client(), .{}, "web_search is not configured".len);
    try std.testing.expectError(error.ToolOutputTooLarge, missing_key_capped.handler().run(std.testing.allocator, .{
        .id = "call_1_capped",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    }));

    var configured = Client.init(fake.client(), .{ .tavily_key = "tvly-key" }, 4096);
    try std.testing.expect(configured.configured());
    try std.testing.expectError(error.InvalidToolArguments, configured.handler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "web_search",
        .arguments = "{\"query\":\"   \"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, configured.handler().run(std.testing.allocator, .{
        .id = "call_control",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\\nlang\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, configured.handler().run(std.testing.allocator, .{
        .id = "call_unknown",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\",\"unknown\":true}",
    }));

    fake.status = 429;
    fake.body = "rate limited";
    const failed = try configured.handler().run(std.testing.allocator, .{
        .id = "call_3",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    });
    defer std.testing.allocator.free(failed);
    try std.testing.expect(std.mem.indexOf(u8, failed, "HTTP 429") != null);
    try std.testing.expect(std.mem.indexOf(u8, failed, "rate limited") != null);

    fake.fail_request = true;
    try std.testing.expectError(error.ToolFailed, configured.handler().run(std.testing.allocator, .{
        .id = "call_4",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    }));
}

test "handler treats malformed provider JSON as tool failure" {
    var fake: FakeHttp = .{ .body = "not-json" };
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.client(), .{ .tavily_key = "tvly-key" }, 4096);

    try std.testing.expectError(error.ToolFailed, client.handler().run(std.testing.allocator, .{
        .id = "call_bad_json",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    }));
}

test "handler treats binary provider text as tool failure" {
    var fake: FakeHttp = .{ .body = "{\"answer\":\"bad\\u0000value\",\"results\":[]}" };
    defer fake.deinit(std.testing.allocator);
    var client = Client.init(fake.client(), .{ .tavily_key = "tvly-key" }, 4096);

    try std.testing.expectError(error.ToolFailed, client.handler().run(std.testing.allocator, .{
        .id = "call_bad_text",
        .name = "web_search",
        .arguments = "{\"query\":\"zig\"}",
    }));
}
