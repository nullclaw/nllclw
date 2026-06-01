const std = @import("std");

pub fn hasWindowsReservedFilenameByte(component: []const u8) bool {
    return std.mem.indexOfAny(u8, component, "<>:\"|?*") != null;
}

pub fn hasWindowsReservedTrailingByte(component: []const u8) bool {
    if (component.len == 0) return false;
    const last = component[component.len - 1];
    return last == ' ' or last == '.';
}

pub fn isWindowsReservedFilenameComponent(component: []const u8) bool {
    return hasWindowsReservedFilenameByte(component) or
        hasWindowsReservedTrailingByte(component) or
        isWindowsReservedDeviceName(component);
}

pub fn isWindowsReservedDeviceName(component: []const u8) bool {
    var end = component.len;
    while (end != 0 and (component[end - 1] == ' ' or component[end - 1] == '.')) end -= 1;
    const trimmed = component[0..end];
    const stem_end = std.mem.indexOfScalar(u8, trimmed, '.') orelse trimmed.len;
    const stem = trimmed[0..stem_end];

    if (std.ascii.eqlIgnoreCase(stem, "CON")) return true;
    if (std.ascii.eqlIgnoreCase(stem, "PRN")) return true;
    if (std.ascii.eqlIgnoreCase(stem, "AUX")) return true;
    if (std.ascii.eqlIgnoreCase(stem, "NUL")) return true;
    if (std.ascii.eqlIgnoreCase(stem, "CONIN$")) return true;
    if (std.ascii.eqlIgnoreCase(stem, "CONOUT$")) return true;

    if (stem.len == 4) {
        const suffix = stem[3];
        if (suffix >= '1' and suffix <= '9') {
            if (std.ascii.eqlIgnoreCase(stem[0..3], "COM")) return true;
            if (std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) return true;
        }
    }
    return false;
}

test "windows filename policy rejects reserved punctuation" {
    try std.testing.expect(hasWindowsReservedFilenameByte("bad:name"));
    try std.testing.expect(hasWindowsReservedFilenameByte("bad?.jsonl"));
    try std.testing.expect(!hasWindowsReservedFilenameByte("state.jsonl"));
}

test "windows filename policy rejects trailing spaces and dots" {
    try std.testing.expect(hasWindowsReservedTrailingByte("bad."));
    try std.testing.expect(hasWindowsReservedTrailingByte("bad "));
    try std.testing.expect(!hasWindowsReservedTrailingByte("state.jsonl"));
}

test "windows filename policy rejects device names with extensions" {
    try std.testing.expect(isWindowsReservedDeviceName("CON"));
    try std.testing.expect(isWindowsReservedDeviceName("nul.jsonl"));
    try std.testing.expect(isWindowsReservedDeviceName("COM1.txt"));
    try std.testing.expect(isWindowsReservedDeviceName("lpt9"));
    try std.testing.expect(isWindowsReservedDeviceName("CONIN$"));
    try std.testing.expect(isWindowsReservedDeviceName("conout$.jsonl"));
    try std.testing.expect(isWindowsReservedDeviceName("AUX."));

    try std.testing.expect(!isWindowsReservedDeviceName("COM0.txt"));
    try std.testing.expect(!isWindowsReservedDeviceName("COM10.txt"));
    try std.testing.expect(!isWindowsReservedDeviceName("company.jsonl"));
    try std.testing.expect(!isWindowsReservedDeviceName("notes.txt"));
}

test "windows filename component policy rejects all reserved forms" {
    try std.testing.expect(isWindowsReservedFilenameComponent("bad:name"));
    try std.testing.expect(isWindowsReservedFilenameComponent("bad."));
    try std.testing.expect(isWindowsReservedFilenameComponent("NUL.jsonl"));
    try std.testing.expect(!isWindowsReservedFilenameComponent(".hidden-memory.jsonl"));
    try std.testing.expect(!isWindowsReservedFilenameComponent("state.jsonl"));
}
