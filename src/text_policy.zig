const std = @import("std");

pub fn isSingleLineText(value: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(value)) return false;
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

pub fn isMultilineText(value: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(value)) return false;
    for (value) |byte| {
        switch (byte) {
            '\n', '\r', '\t' => {},
            else => if (byte < 0x20 or byte == 0x7f) return false,
        }
    }
    return true;
}

test "single-line text rejects all ASCII controls" {
    try std.testing.expect(isSingleLineText("plain utf-8 é"));
    try std.testing.expect(!isSingleLineText("line\nbreak"));
    try std.testing.expect(!isSingleLineText("tab\tvalue"));
    try std.testing.expect(!isSingleLineText("bad\x00value"));
    try std.testing.expect(!isSingleLineText("bad\x1bvalue"));
    try std.testing.expect(!isSingleLineText("bad\x7fvalue"));
    try std.testing.expect(!isSingleLineText("bad\xff"));
}

test "multiline text permits normal whitespace but rejects binary controls" {
    try std.testing.expect(isMultilineText("line one\nline two\tok\r\n"));
    try std.testing.expect(!isMultilineText("bad\x00value"));
    try std.testing.expect(!isMultilineText("bad\x1bvalue"));
    try std.testing.expect(!isMultilineText("bad\x7fvalue"));
    try std.testing.expect(!isMultilineText("bad\xff"));
}
