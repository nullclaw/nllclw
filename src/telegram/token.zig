const std = @import("std");

pub const max_bytes: usize = 256;

pub fn isValid(value: []const u8) bool {
    if (value.len == 0 or value.len > max_bytes) return false;
    const colon = std.mem.indexOfScalar(u8, value, ':') orelse return false;
    if (colon == 0 or colon + 1 == value.len) return false;
    if (std.mem.indexOfScalar(u8, value[colon + 1 ..], ':') != null) return false;

    for (value[0..colon]) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
    }
    for (value[colon + 1 ..]) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        if (byte == '-' or byte == '_') continue;
        return false;
    }
    return true;
}

test "telegram token policy accepts bot api token shape" {
    try std.testing.expect(isValid("123:abc_DEF-456"));

    try std.testing.expect(!isValid("token"));
    try std.testing.expect(!isValid("abc:secret"));
    try std.testing.expect(!isValid("123:"));
    try std.testing.expect(!isValid(":secret"));
    try std.testing.expect(!isValid("123:secret:extra"));
    try std.testing.expect(!isValid("123:bad/value"));
    try std.testing.expect(!isValid("123:bad\nvalue"));

    var long: [max_bytes + 1]u8 = undefined;
    @memset(&long, 'a');
    long[3] = ':';
    try std.testing.expect(!isValid(&long));
}
