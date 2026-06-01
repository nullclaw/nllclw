const std = @import("std");
const agent = @import("../agent.zig");
const http = @import("../ports/http.zig");
const telegram = @import("./codec.zig");

const Allocator = std.mem.Allocator;

pub fn fetchUpdates(
    allocator: Allocator,
    client: http.Client,
    token: []const u8,
    offset: ?i64,
    timeout_seconds: u32,
    diagnostic: ?*agent.Diagnostic,
) !telegram.Updates {
    const body = try telegram.buildGetUpdatesRequest(allocator, offset, timeout_seconds);
    defer allocator.free(body);

    var response = try postJson(allocator, client, token, "getUpdates", body);
    defer response.deinit(allocator);

    if (response.status != 200) {
        try setHttpDiagnostic(allocator, diagnostic, response.status, response.body);
        return error.TelegramHttpStatus;
    }

    return telegram.parseUpdates(allocator, response.body) catch |err| {
        try setBodyDiagnostic(allocator, diagnostic, response.body);
        return err;
    };
}

pub fn sendTextChunks(
    allocator: Allocator,
    client: http.Client,
    token: []const u8,
    chat_id: i64,
    text: []const u8,
    diagnostic: ?*agent.Diagnostic,
) !void {
    const fallback = if (text.len == 0) "(empty)" else text;
    if (!telegram.isValidMessageText(fallback)) return error.InvalidTelegramText;
    var remaining = fallback;
    while (remaining.len > 0) {
        const end = telegram.utf8ChunkEnd(remaining, telegram.max_message_bytes);
        if (end == 0) return error.InvalidTelegramText;
        const chunk = remaining[0..end];
        try sendText(allocator, client, token, chat_id, chunk, diagnostic);
        remaining = remaining[end..];
    }
}

pub fn sendText(
    allocator: Allocator,
    client: http.Client,
    token: []const u8,
    chat_id: i64,
    text: []const u8,
    diagnostic: ?*agent.Diagnostic,
) !void {
    const body = try telegram.buildSendMessageRequest(allocator, chat_id, text);
    defer allocator.free(body);

    var response = try postJson(allocator, client, token, "sendMessage", body);
    defer response.deinit(allocator);

    if (response.status != 200) {
        try setHttpDiagnostic(allocator, diagnostic, response.status, response.body);
        return error.TelegramHttpStatus;
    }

    telegram.ensureOk(allocator, response.body) catch |err| {
        try setBodyDiagnostic(allocator, diagnostic, response.body);
        return err;
    };
}

fn postJson(
    allocator: Allocator,
    client: http.Client,
    token: []const u8,
    method: []const u8,
    body: []const u8,
) !http.Response {
    const endpoint = try telegram.endpoint(allocator, token, method);
    defer allocator.free(endpoint);
    const headers = [_]http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "User-Agent", .value = "nllclw/0.1" },
    };
    return client.postJson(allocator, .{
        .url = endpoint,
        .headers = &headers,
        .body = body,
    });
}

fn setHttpDiagnostic(
    allocator: Allocator,
    diagnostic: ?*agent.Diagnostic,
    status: http.StatusCode,
    body: []const u8,
) !void {
    const diag = diagnostic orelse return;
    diag.deinit(allocator);
    diag.status = status;
    try setDiagnosticBodyOrMessage(allocator, diag, body);
}

fn setBodyDiagnostic(
    allocator: Allocator,
    diagnostic: ?*agent.Diagnostic,
    body: []const u8,
) !void {
    const diag = diagnostic orelse return;
    diag.deinit(allocator);
    try setDiagnosticBodyOrMessage(allocator, diag, body);
}

fn setDiagnosticBodyOrMessage(allocator: Allocator, diag: *agent.Diagnostic, body: []const u8) !void {
    if (try telegram.apiErrorDescription(allocator, body)) |description| {
        diag.message = description;
    } else {
        diag.body = try allocator.dupe(u8, body);
    }
}

const FakeHttp = struct {
    status: http.StatusCode = 200,
    body: []const u8,
    seen_url: ?[]u8 = null,
    seen_body: ?[]u8 = null,
    sent_text: std.ArrayList(u8) = .empty,
    max_chunk_text_bytes: usize = 0,
    calls: usize = 0,

    fn deinit(self: *FakeHttp, allocator: Allocator) void {
        if (self.seen_url) |value| allocator.free(value);
        if (self.seen_body) |value| allocator.free(value);
        self.sent_text.deinit(allocator);
        self.* = undefined;
    }

    fn client(self: *FakeHttp) http.Client {
        return .{
            .ptr = self,
            .post_json = postJsonFake,
        };
    }

    fn postJsonFake(ptr: *anyopaque, allocator: Allocator, request: http.Request) http.Error!http.Response {
        const self: *FakeHttp = @ptrCast(@alignCast(ptr));
        self.calls += 1;
        if (self.seen_url) |value| allocator.free(value);
        if (self.seen_body) |value| allocator.free(value);
        self.seen_url = try allocator.dupe(u8, request.url);
        self.seen_body = try allocator.dupe(u8, request.body);

        const SendBody = struct {
            text: ?[]const u8 = null,
        };
        if (std.json.parseFromSlice(SendBody, allocator, request.body, .{
            .ignore_unknown_fields = true,
        })) |parsed| {
            defer parsed.deinit();
            if (parsed.value.text) |text| {
                try self.sent_text.appendSlice(allocator, text);
                self.max_chunk_text_bytes = @max(self.max_chunk_text_bytes, text.len);
            }
        } else |_| {}

        return .{
            .status = self.status,
            .body = try allocator.dupe(u8, self.body),
        };
    }
};

test "fetchUpdates posts to Telegram and parses updates" {
    var fake = FakeHttp{
        .body = "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"chat\":{\"id\":2},\"text\":\"hi\"}}]}",
    };
    defer fake.deinit(std.testing.allocator);

    var updates = try fetchUpdates(std.testing.allocator, fake.client(), "123:token", null, 0, null);
    defer updates.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("https://api.telegram.org/bot123:token/getUpdates", fake.seen_url.?);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"timeout\":0") != null);
    try std.testing.expectEqual(@as(usize, 1), updates.items.len);
    try std.testing.expectEqualStrings("hi", updates.items[0].text);
}

test "sendTextChunks splits long Telegram messages" {
    var fake = FakeHttp{
        .body = "{\"ok\":true,\"result\":{}}",
    };
    defer fake.deinit(std.testing.allocator);

    const long_text = try std.testing.allocator.alloc(u8, telegram.max_message_bytes + 17);
    defer std.testing.allocator.free(long_text);
    @memset(long_text, 'a');

    try sendTextChunks(std.testing.allocator, fake.client(), "123:token", 42, long_text, null);
    try std.testing.expectEqualStrings("https://api.telegram.org/bot123:token/sendMessage", fake.seen_url.?);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"chat_id\":42") != null);
    try std.testing.expectEqual(@as(usize, 2), fake.calls);
    try std.testing.expectEqual(telegram.max_message_bytes, fake.max_chunk_text_bytes);
    try std.testing.expectEqualStrings(long_text, fake.sent_text.items);
}

test "sendTextChunks sends explicit empty fallback" {
    var fake = FakeHttp{
        .body = "{\"ok\":true,\"result\":{}}",
    };
    defer fake.deinit(std.testing.allocator);

    try sendTextChunks(std.testing.allocator, fake.client(), "123:token", 42, "", null);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"text\":\"(empty)\"") != null);
}

test "sendTextChunks rejects invalid text before sending any chunk" {
    var fake = FakeHttp{
        .body = "{\"ok\":true,\"result\":{}}",
    };
    defer fake.deinit(std.testing.allocator);

    const invalid_text = try std.testing.allocator.alloc(u8, telegram.max_message_bytes + 8);
    defer std.testing.allocator.free(invalid_text);
    @memset(invalid_text, 'a');
    invalid_text[telegram.max_message_bytes + 1] = 0;

    try std.testing.expectError(error.InvalidTelegramText, sendTextChunks(
        std.testing.allocator,
        fake.client(),
        "123:token",
        42,
        invalid_text,
        null,
    ));
    try std.testing.expectEqual(@as(usize, 0), fake.calls);
    try std.testing.expect(fake.seen_body == null);
}

test "telegram HTTP error populates diagnostic" {
    var fake = FakeHttp{
        .status = 401,
        .body = "{\"ok\":false,\"description\":\"bad token\"}",
    };
    defer fake.deinit(std.testing.allocator);
    var diagnostic: agent.Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.TelegramHttpStatus, sendText(
        std.testing.allocator,
        fake.client(),
        "123:token",
        42,
        "hello",
        &diagnostic,
    ));
    try std.testing.expectEqual(@as(http.StatusCode, 401), diagnostic.status.?);
    try std.testing.expectEqualStrings("bad token", diagnostic.message.?);
}

test "telegram API error at HTTP 200 is not an HTTP diagnostic" {
    var fake = FakeHttp{
        .body = "{\"ok\":false,\"description\":\"bot blocked\"}",
    };
    defer fake.deinit(std.testing.allocator);
    var diagnostic: agent.Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.TelegramApiError, sendText(
        std.testing.allocator,
        fake.client(),
        "123:token",
        42,
        "hello",
        &diagnostic,
    ));
    try std.testing.expect(diagnostic.status == null);
    try std.testing.expectEqualStrings("bot blocked", diagnostic.message.?);
}

test "telegram parse error keeps raw body diagnostic" {
    var fake = FakeHttp{
        .body = "{\"ok\":true,\"result\":",
    };
    defer fake.deinit(std.testing.allocator);
    var diagnostic: agent.Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.InvalidTelegramResponse, fetchUpdates(
        std.testing.allocator,
        fake.client(),
        "123:token",
        7,
        20,
        &diagnostic,
    ));
    try std.testing.expect(diagnostic.status == null);
    try std.testing.expectEqualStrings("{\"ok\":true,\"result\":", diagnostic.body.?);
}
