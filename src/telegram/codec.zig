const std = @import("std");
const text_policy = @import("../text_policy.zig");
const token_policy = @import("./token.zig");

const Allocator = std.mem.Allocator;

pub const default_api_base = "https://api.telegram.org";
pub const max_message_bytes = 3900;
pub const max_update_text_bytes = 64 * 1024;
pub const max_diagnostic_description_bytes = 1024;

pub const BuildError = error{
    InvalidTelegramChatId,
    InvalidTelegramMethod,
    InvalidTelegramOffset,
    InvalidTelegramText,
    InvalidTelegramToken,
} || Allocator.Error;

pub const ParseError = Allocator.Error || error{
    InvalidTelegramResponse,
    InvalidTelegramUpdate,
    TelegramApiError,
};

pub const Update = struct {
    update_id: i64,
    chat_id: i64,
    chat_username: ?[]u8 = null,
    from_username: ?[]u8 = null,
    text: []u8,

    pub fn deinit(self: *Update, allocator: Allocator) void {
        if (self.chat_username) |value| allocator.free(value);
        if (self.from_username) |value| allocator.free(value);
        allocator.free(self.text);
        self.* = undefined;
    }
};

pub const Updates = struct {
    items: []Update = &.{},
    next_offset: ?i64 = null,

    pub fn deinit(self: *Updates, allocator: Allocator) void {
        for (self.items) |*update| update.deinit(allocator);
        allocator.free(self.items);
        self.* = .{};
    }
};

const GetUpdatesResponse = struct {
    ok: bool = false,
    description: ?[]const u8 = null,
    result: []const RawUpdate = &.{},
};

const BasicResponse = struct {
    ok: bool = false,
    description: ?[]const u8 = null,
};

const RawUpdate = struct {
    update_id: i64,
    message: ?RawMessage = null,
};

const RawMessage = struct {
    chat: RawChat,
    text: ?[]const u8 = null,
    from: ?RawUser = null,
};

const RawChat = struct {
    id: i64,
    username: ?[]const u8 = null,
};

const RawUser = struct {
    is_bot: bool = false,
    username: ?[]const u8 = null,
};

const GetUpdatesRequest = struct {
    offset: ?i64 = null,
    timeout: u32,
    allowed_updates: []const []const u8,
};

const SendMessageRequest = struct {
    chat_id: i64,
    text: []const u8,
    disable_web_page_preview: bool = true,
};

pub fn endpoint(allocator: Allocator, token: []const u8, method: []const u8) BuildError![]u8 {
    if (!token_policy.isValid(token)) return error.InvalidTelegramToken;
    if (!isValidMethod(method)) return error.InvalidTelegramMethod;
    return std.fmt.allocPrint(allocator, "{s}/bot{s}/{s}", .{ default_api_base, token, method });
}

pub fn buildGetUpdatesRequest(
    allocator: Allocator,
    offset: ?i64,
    timeout_seconds: u32,
) BuildError![]u8 {
    if (offset) |value| {
        if (value < 0) return error.InvalidTelegramOffset;
    }
    const allowed_updates = [_][]const u8{"message"};
    return formatJson(allocator, GetUpdatesRequest{
        .offset = offset,
        .timeout = timeout_seconds,
        .allowed_updates = &allowed_updates,
    });
}

pub fn buildSendMessageRequest(allocator: Allocator, chat_id: i64, text: []const u8) BuildError![]u8 {
    if (chat_id == 0) return error.InvalidTelegramChatId;
    if (text.len == 0 or text.len > max_message_bytes) return error.InvalidTelegramText;
    if (!isValidMessageText(text)) return error.InvalidTelegramText;
    return formatJson(allocator, SendMessageRequest{
        .chat_id = chat_id,
        .text = text,
    });
}

fn formatJson(allocator: Allocator, value: anytype) BuildError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    out.writer.print("{f}", .{std.json.fmt(value, .{ .emit_null_optional_fields = false })}) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

pub fn parseUpdates(allocator: Allocator, body: []const u8) ParseError!Updates {
    const parsed = try parseTelegramJson(GetUpdatesResponse, allocator, body);
    defer parsed.deinit();

    if (!parsed.value.ok) return error.TelegramApiError;

    var updates: std.ArrayList(Update) = .empty;
    errdefer {
        for (updates.items) |*update| update.deinit(allocator);
        updates.deinit(allocator);
    }

    var next_offset: ?i64 = null;
    for (parsed.value.result) |raw| {
        const candidate = try nextOffset(raw.update_id);
        if (next_offset) |current| {
            if (candidate > current) next_offset = candidate;
        } else {
            next_offset = candidate;
        }

        const message = raw.message orelse continue;
        if (message.from) |from| {
            if (from.is_bot) continue;
        }
        const text = message.text orelse continue;
        if (!isValidText(text)) continue;
        if (text.len > max_update_text_bytes) continue;
        if (std.mem.trim(u8, text, &std.ascii.whitespace).len == 0) continue;
        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);
        const chat_username = try dupeOptional(allocator, message.chat.username);
        errdefer if (chat_username) |value| allocator.free(value);
        const from_username = try dupeOptional(allocator, if (message.from) |from| from.username else null);
        errdefer if (from_username) |value| allocator.free(value);
        try updates.append(allocator, .{
            .update_id = raw.update_id,
            .chat_id = message.chat.id,
            .chat_username = chat_username,
            .from_username = from_username,
            .text = owned_text,
        });
    }

    return .{
        .items = try updates.toOwnedSlice(allocator),
        .next_offset = next_offset,
    };
}

fn dupeOptional(allocator: Allocator, value: ?[]const u8) Allocator.Error!?[]u8 {
    const raw = value orelse return null;
    return try allocator.dupe(u8, raw);
}

pub fn isValidMessageText(text: []const u8) bool {
    return isValidText(text);
}

pub fn nextOffset(update_id: i64) error{InvalidTelegramUpdate}!i64 {
    if (update_id < 0) return error.InvalidTelegramUpdate;
    return std.math.add(i64, update_id, 1) catch error.InvalidTelegramUpdate;
}

pub fn ensureOk(allocator: Allocator, body: []const u8) ParseError!void {
    const parsed = try parseTelegramJson(BasicResponse, allocator, body);
    defer parsed.deinit();
    if (!parsed.value.ok) return error.TelegramApiError;
}

pub fn apiErrorDescription(allocator: Allocator, body: []const u8) Allocator.Error!?[]u8 {
    const parsed = std.json.parseFromSlice(BasicResponse, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer parsed.deinit();

    if (parsed.value.ok) return null;
    const description = parsed.value.description orelse return try allocator.dupe(u8, "telegram api error");
    if (!isDiagnosticDescriptionText(description)) return try allocator.dupe(u8, "telegram api error");
    return try allocator.dupe(u8, description);
}

fn parseTelegramJson(comptime T: type, allocator: Allocator, body: []const u8) ParseError!std.json.Parsed(T) {
    return std.json.parseFromSlice(T, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidTelegramResponse,
    };
}

fn isValidText(text: []const u8) bool {
    return text_policy.isMultilineText(text);
}

fn isDiagnosticDescriptionText(text: []const u8) bool {
    return text.len != 0 and
        text.len <= max_diagnostic_description_bytes and
        text_policy.isSingleLineText(text);
}

fn isValidMethod(method: []const u8) bool {
    if (method.len == 0 or method.len > 64) return false;
    for (method) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_') continue;
        return false;
    }
    return true;
}

pub fn utf8ChunkEnd(text: []const u8, max_bytes: usize) usize {
    if (max_bytes == 0) return 0;
    if (text.len <= max_bytes) return text.len;
    var end = max_bytes;
    while (end > 0 and (text[end] & 0xc0) == 0x80) : (end -= 1) {}
    return end;
}

test "builds getUpdates JSON body" {
    const body = try buildGetUpdatesRequest(std.testing.allocator, 42, 20);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"offset\":42,\"timeout\":20,\"allowed_updates\":[\"message\"]}", body);

    try std.testing.expectError(
        error.InvalidTelegramOffset,
        buildGetUpdatesRequest(std.testing.allocator, -1, 20),
    );
}

test "builds Telegram endpoint only for valid bot tokens" {
    const url = try endpoint(std.testing.allocator, "123:token", "getUpdates");
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("https://api.telegram.org/bot123:token/getUpdates", url);

    try std.testing.expectError(error.InvalidTelegramToken, endpoint(std.testing.allocator, "token", "getUpdates"));
    try std.testing.expectError(error.InvalidTelegramToken, endpoint(std.testing.allocator, "abc:token", "getUpdates"));
    try std.testing.expectError(error.InvalidTelegramToken, endpoint(std.testing.allocator, "123:bad/token", "getUpdates"));
    try std.testing.expectError(error.InvalidTelegramMethod, endpoint(std.testing.allocator, "123:token", ""));
    try std.testing.expectError(error.InvalidTelegramMethod, endpoint(std.testing.allocator, "123:token", "send/Message"));
    try std.testing.expectError(error.InvalidTelegramMethod, endpoint(std.testing.allocator, "123:token", "send\nMessage"));
}

test "builds sendMessage JSON body" {
    const body = try buildSendMessageRequest(std.testing.allocator, -100, "hello");
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"chat_id\":-100,\"text\":\"hello\",\"disable_web_page_preview\":true}", body);

    try std.testing.expectError(
        error.InvalidTelegramChatId,
        buildSendMessageRequest(std.testing.allocator, 0, "hello"),
    );
}

test "rejects invalid utf-8 sendMessage text" {
    try std.testing.expectError(
        error.InvalidTelegramText,
        buildSendMessageRequest(std.testing.allocator, -100, ""),
    );

    const long_text = try std.testing.allocator.alloc(u8, max_message_bytes + 1);
    defer std.testing.allocator.free(long_text);
    @memset(long_text, 'a');
    try std.testing.expectError(
        error.InvalidTelegramText,
        buildSendMessageRequest(std.testing.allocator, -100, long_text),
    );

    try std.testing.expectError(
        error.InvalidTelegramText,
        buildSendMessageRequest(std.testing.allocator, -100, "bad\xff"),
    );
    try std.testing.expectError(
        error.InvalidTelegramText,
        buildSendMessageRequest(std.testing.allocator, -100, "bad\x00value"),
    );
    try std.testing.expectError(
        error.InvalidTelegramText,
        buildSendMessageRequest(std.testing.allocator, -100, "bad\x1bvalue"),
    );
}

test "parses text updates and skips bot messages" {
    const body =
        \\{
        \\  "ok": true,
        \\  "result": [
        \\    {"update_id": 1, "message": {"chat": {"id": 10, "username": "groupname"}, "from": {"is_bot": false, "username": "donprus"}, "text": "hi"}},
        \\    {"update_id": 2, "message": {"chat": {"id": 10}, "from": {"is_bot": true}, "text": "bot"}},
        \\    {"update_id": 3, "message": {"chat": {"id": 10}}}
        \\  ]
        \\}
    ;

    var updates = try parseUpdates(std.testing.allocator, body);
    defer updates.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), updates.items.len);
    try std.testing.expectEqual(@as(i64, 1), updates.items[0].update_id);
    try std.testing.expectEqual(@as(i64, 10), updates.items[0].chat_id);
    try std.testing.expectEqualStrings("groupname", updates.items[0].chat_username.?);
    try std.testing.expectEqualStrings("donprus", updates.items[0].from_username.?);
    try std.testing.expectEqualStrings("hi", updates.items[0].text);
    try std.testing.expectEqual(@as(i64, 4), updates.next_offset.?);
}

test "rejects invalid telegram update ids" {
    try std.testing.expectError(error.InvalidTelegramUpdate, parseUpdates(
        std.testing.allocator,
        "{\"ok\":true,\"result\":[{\"update_id\":-1,\"message\":{\"chat\":{\"id\":10},\"text\":\"bad\"}}]}",
    ));
    try std.testing.expectError(error.InvalidTelegramUpdate, nextOffset(std.math.maxInt(i64)));
}

test "skips binary control bytes in telegram update text" {
    var nul_updates = try parseUpdates(
        std.testing.allocator,
        "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"chat\":{\"id\":10},\"text\":\"bad\\u0000value\"}}]}",
    );
    defer nul_updates.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), nul_updates.items.len);
    try std.testing.expectEqual(@as(i64, 2), nul_updates.next_offset.?);

    var esc_updates = try parseUpdates(
        std.testing.allocator,
        "{\"ok\":true,\"result\":[{\"update_id\":1,\"message\":{\"chat\":{\"id\":10},\"text\":\"bad\\u001bvalue\"}}]}",
    );
    defer esc_updates.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), esc_updates.items.len);
    try std.testing.expectEqual(@as(i64, 2), esc_updates.next_offset.?);
}

test "skips oversized telegram update text" {
    const oversized_text = try std.testing.allocator.alloc(u8, max_update_text_bytes + 1);
    defer std.testing.allocator.free(oversized_text);
    @memset(oversized_text, 'a');
    const body = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"ok\":true,\"result\":[{{\"update_id\":1,\"message\":{{\"chat\":{{\"id\":10}},\"text\":\"{s}\"}}}}]}}",
        .{oversized_text},
    );
    defer std.testing.allocator.free(body);

    var updates = try parseUpdates(std.testing.allocator, body);
    defer updates.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), updates.items.len);
    try std.testing.expectEqual(@as(i64, 2), updates.next_offset.?);
}

test "extracts telegram api error description" {
    const description = (try apiErrorDescription(std.testing.allocator, "{\"ok\":false,\"description\":\"bad token\"}")).?;
    defer std.testing.allocator.free(description);
    try std.testing.expectEqualStrings("bad token", description);

    const fallback = (try apiErrorDescription(std.testing.allocator, "{\"ok\":false}")).?;
    defer std.testing.allocator.free(fallback);
    try std.testing.expectEqualStrings("telegram api error", fallback);

    const invalid = (try apiErrorDescription(std.testing.allocator, "{\"ok\":false,\"description\":\"bad\\u0000token\"}")).?;
    defer std.testing.allocator.free(invalid);
    try std.testing.expectEqualStrings("telegram api error", invalid);

    const control = (try apiErrorDescription(std.testing.allocator, "{\"ok\":false,\"description\":\"bad\\u001b[31mtoken\"}")).?;
    defer std.testing.allocator.free(control);
    try std.testing.expectEqualStrings("telegram api error", control);

    const empty = (try apiErrorDescription(std.testing.allocator, "{\"ok\":false,\"description\":\"\"}")).?;
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqualStrings("telegram api error", empty);

    const long_description = try std.testing.allocator.alloc(u8, max_diagnostic_description_bytes + 1);
    defer std.testing.allocator.free(long_description);
    @memset(long_description, 'x');
    const long_body = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"ok\":false,\"description\":\"{s}\"}}",
        .{long_description},
    );
    defer std.testing.allocator.free(long_body);
    const long = (try apiErrorDescription(std.testing.allocator, long_body)).?;
    defer std.testing.allocator.free(long);
    try std.testing.expectEqualStrings("telegram api error", long);

    try std.testing.expect((try apiErrorDescription(std.testing.allocator, "{\"ok\":true}")) == null);
    try std.testing.expectError(error.TelegramApiError, ensureOk(std.testing.allocator, "{\"ok\":false}"));
}

test "telegram API error parser preserves allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            const description = (try apiErrorDescription(allocator, "{\"ok\":false,\"description\":\"bad token\"}")).?;
            defer allocator.free(description);
            try std.testing.expectEqualStrings("bad token", description);
        }
    }.run, .{});
}

test "telegram updates parser preserves allocation failures" {
    const body =
        \\{
        \\  "ok": true,
        \\  "result": [
        \\    {"update_id": 1, "message": {"chat": {"id": 10}, "text": "hi"}}
        \\  ]
        \\}
    ;

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator, updates_body: []const u8) !void {
            var updates = try parseUpdates(allocator, updates_body);
            defer updates.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 1), updates.items.len);
            try std.testing.expectEqualStrings("hi", updates.items[0].text);
        }
    }.run, .{body});
}

test "utf8 chunk end does not split continuation bytes" {
    const text = "ab€cd";
    try std.testing.expectEqual(@as(usize, 2), utf8ChunkEnd(text, 4));
    try std.testing.expectEqual(text.len, utf8ChunkEnd(text, 32));

    try std.testing.expectEqual(@as(usize, 0), utf8ChunkEnd("€", 1));
    try std.testing.expectEqual(@as(usize, 0), utf8ChunkEnd("€", 0));
}
