const std = @import("std");
const state_file = @import("../adapters/state_file.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_file_bytes = 128;

pub const Store = struct {
    io: Io,
    path: []const u8,

    pub fn load(self: Store, allocator: Allocator) !?i64 {
        return loadFile(allocator, self.io, self.path);
    }

    pub fn save(self: Store, allocator: Allocator, offset: i64) !void {
        return saveFile(allocator, self.io, self.path, offset);
    }
};

pub fn loadFile(allocator: Allocator, io: Io, path: []const u8) !?i64 {
    const contents = (try state_file.readAlloc(allocator, io, path, max_file_bytes)) orelse return null;
    defer allocator.free(contents);

    const trimmed = std.mem.trim(u8, contents, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    const offset = std.fmt.parseInt(i64, trimmed, 10) catch return error.InvalidTelegramOffset;
    if (offset < 0) return error.InvalidTelegramOffset;
    return offset;
}

pub fn saveFile(allocator: Allocator, io: Io, path: []const u8, offset: i64) !void {
    if (offset < 0) return error.InvalidTelegramOffset;
    const bytes = try std.fmt.allocPrint(allocator, "{d}\n", .{offset});
    defer allocator.free(bytes);

    var lock_file = try state_file.lockPath(allocator, io, path);
    defer lock_file.close(io);

    try state_file.writeAtomic(io, path, bytes);
}

test "telegram offset store persists integer offsets" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/offset", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try std.testing.expect((try loadFile(std.testing.allocator, io, path)) == null);
    try saveFile(std.testing.allocator, io, path, 42);
    try std.testing.expectEqual(@as(?i64, 42), try loadFile(std.testing.allocator, io, path));
    try std.testing.expectError(error.InvalidTelegramOffset, saveFile(std.testing.allocator, io, path, -1));
}

test "telegram offset store creates parent directories" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/offset", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try saveFile(std.testing.allocator, io, path, 7);
    try std.testing.expectEqual(@as(?i64, 7), try loadFile(std.testing.allocator, io, path));
}

test "telegram offset store serializes writes with a lock file" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/offset", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const lock_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.lock", .{path});
    defer std.testing.allocator.free(lock_path);

    try saveFile(std.testing.allocator, io, path, 11);
    var lock = try Io.Dir.cwd().openFile(io, lock_path, .{});
    lock.close(io);
}

test "telegram offset store rejects invalid persisted offsets" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/offset", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "-1\n" });
    try std.testing.expectError(error.InvalidTelegramOffset, loadFile(std.testing.allocator, io, path));
}
