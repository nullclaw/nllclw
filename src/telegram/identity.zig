const std = @import("std");

pub const ChatAllowlist = union(enum) {
    id: i64,
    username: []const u8,
};

pub fn parseAllowlist(value: []const u8) ?ChatAllowlist {
    const trimmed = std.mem.trim(u8, value, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (std.fmt.parseInt(i64, trimmed, 10)) |id| {
        return if (id != 0) .{ .id = id } else null;
    } else |_| {}

    const username = normalizeUsername(trimmed) orelse return null;
    return .{ .username = username };
}

pub fn normalizeUsername(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, &std.ascii.whitespace);
    const username = if (std.mem.startsWith(u8, trimmed, "@")) trimmed[1..] else trimmed;
    return if (isValidUsername(username)) username else null;
}

pub fn isValidUsername(username: []const u8) bool {
    if (username.len < 5 or username.len > 32) return false;
    var has_alpha = false;
    for (username) |byte| {
        if (std.ascii.isAlphabetic(byte)) has_alpha = true;
        if (std.ascii.isAlphanumeric(byte) or byte == '_') continue;
        return false;
    }
    return has_alpha;
}

pub fn matches(
    allowlist: ChatAllowlist,
    chat_id: i64,
    chat_username: ?[]const u8,
    from_username: ?[]const u8,
) bool {
    return switch (allowlist) {
        .id => |allowed| chat_id == allowed,
        .username => |allowed| usernameMatches(allowed, chat_username) or
            (chat_id > 0 and usernameMatches(allowed, from_username)),
    };
}

pub fn usernameMatches(allowed: []const u8, candidate: ?[]const u8) bool {
    const raw = candidate orelse return false;
    const normalized = normalizeUsername(raw) orelse return false;
    return std.ascii.eqlIgnoreCase(allowed, normalized);
}

test "telegram allowlist parses ids and usernames" {
    try std.testing.expectEqual(@as(i64, 315078959), parseAllowlist("315078959").?.id);
    try std.testing.expectEqual(@as(i64, -10042), parseAllowlist("-10042").?.id);
    try std.testing.expectEqualStrings("donprus", parseAllowlist("@donprus").?.username);
    try std.testing.expectEqualStrings("donprus", parseAllowlist("donprus").?.username);
    try std.testing.expectEqualStrings("12abc", parseAllowlist("@12abc").?.username);

    try std.testing.expect(parseAllowlist("0") == null);
    try std.testing.expect(parseAllowlist("@bad-name") == null);
    try std.testing.expect(parseAllowlist("@12345") == null);
    try std.testing.expect(parseAllowlist("abcd") == null);
}

test "telegram allowlist matches chat id or usernames" {
    try std.testing.expect(matches(.{ .id = 315078959 }, 315078959, null, null));
    try std.testing.expect(!matches(.{ .id = 315078959 }, 42, "donprus", null));

    try std.testing.expect(matches(.{ .username = "donprus" }, 42, null, "donprus"));
    try std.testing.expect(matches(.{ .username = "donprus" }, 42, "@DonPrus", null));
    try std.testing.expect(!matches(.{ .username = "donprus" }, -10042, null, "donprus"));
    try std.testing.expect(!matches(.{ .username = "donprus" }, 42, "someone_else", null));
}
