const std = @import("std");
const builtin = @import("builtin");
const io_file = @import("./io_file.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn lockPath(allocator: Allocator, io: Io, path: []const u8) !Io.File {
    return lockPathBlockingMode(allocator, io, path, false);
}

pub fn tryLockPath(allocator: Allocator, io: Io, path: []const u8) !?Io.File {
    return lockPathBlockingMode(allocator, io, path, true) catch |err| switch (err) {
        error.WouldBlock => null,
        else => return err,
    };
}

fn lockPathBlockingMode(allocator: Allocator, io: Io, path: []const u8, nonblocking: bool) !Io.File {
    var parent = try openParentDir(io, path, true);
    defer parent.deinit(io);

    const lock_basename = try std.fmt.allocPrint(allocator, "{s}.lock", .{parent.basename});
    defer allocator.free(lock_basename);

    var lock_file = parent.dir.openFile(io, lock_basename, .{
        .mode = .read_write,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
        .lock = .exclusive,
        .lock_nonblocking = nonblocking,
    }) catch |err| switch (err) {
        error.FileNotFound => try createOrOpenLockFile(io, parent.dir, lock_basename, nonblocking),
        else => return err,
    };
    errdefer lock_file.close(io);
    try lock_file.setPermissions(io, privateFilePermissions());
    return lock_file;
}

fn createOrOpenLockFile(io: Io, dir: Io.Dir, basename: []const u8, nonblocking: bool) !Io.File {
    return dir.createFile(io, basename, .{
        .read = true,
        .truncate = false,
        .exclusive = true,
        .permissions = privateFilePermissions(),
        .lock = .exclusive,
        .lock_nonblocking = nonblocking,
        .resolve_beneath = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => dir.openFile(io, basename, .{
            .mode = .read_write,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
            .lock = .exclusive,
            .lock_nonblocking = nonblocking,
        }),
        else => return err,
    };
}

pub fn readAlloc(allocator: Allocator, io: Io, path: []const u8, max_bytes: usize) !?[]u8 {
    var parent = openParentDir(io, path, false) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer parent.deinit(io);

    var file = parent.dir.openFile(io, parent.basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    io_file.fixWindowsNoFollowFile(&file);
    defer file.close(io);

    var reader = file.reader(io, &.{});
    return reader.interface.allocRemaining(allocator, .limited(max_bytes)) catch |err| switch (err) {
        error.ReadFailed => {
            if (reader.err) |read_err| return read_err;
            return error.ReadFailed;
        },
        error.OutOfMemory,
        error.StreamTooLong,
        => |e| return e,
    };
}

pub fn writeAtomic(io: Io, path: []const u8, snapshot: []const u8) !void {
    var parent = try openParentDir(io, path, true);
    defer parent.deinit(io);

    if (parent.dir.openFile(io, parent.basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    })) |existing| {
        var existing_file = existing;
        existing_file.close(io);
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    var file = try parent.dir.createFileAtomic(io, parent.basename, .{
        .permissions = privateFilePermissions(),
        .replace = true,
    });
    defer file.deinit(io);

    try file.file.writeStreamingAll(io, snapshot);
    try file.file.setPermissions(io, privateFilePermissions());
    try file.file.sync(io);
    try file.replace(io);
}

const ParentDir = struct {
    dir: Io.Dir,
    owns_dir: bool,
    basename: []const u8,

    fn deinit(self: *ParentDir, io: Io) void {
        if (self.owns_dir) self.dir.close(io);
        self.* = undefined;
    }
};

fn openParentDir(io: Io, path: []const u8, create_parent_dirs: bool) !ParentDir {
    if (std.fs.path.isAbsolute(path)) return openAbsoluteParentDir(io, path, create_parent_dirs);

    const basename_start = std.mem.lastIndexOfScalar(u8, path, '/') orelse {
        if (!isValidComponent(path)) return error.BadPathName;
        return .{ .dir = Io.Dir.cwd(), .owns_dir = false, .basename = path };
    };
    const dirname = path[0..basename_start];
    const basename = path[basename_start + 1 ..];
    if (dirname.len == 0 or !isValidComponent(basename)) return error.BadPathName;

    var dir = Io.Dir.cwd();
    var owns_dir = false;
    errdefer if (owns_dir) dir.close(io);

    var components = std.mem.splitScalar(u8, dirname, '/');
    while (components.next()) |component| {
        if (!isValidComponent(component)) return error.BadPathName;

        const child = dir.openDir(io, component, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                if (!create_parent_dirs) return error.FileNotFound;
                dir.createDir(io, component, .default_dir) catch |create_err| switch (create_err) {
                    error.PathAlreadyExists => {},
                    else => return create_err,
                };
                break :blk try dir.openDir(io, component, .{
                    .access_sub_paths = true,
                    .follow_symlinks = false,
                });
            },
            else => return err,
        };
        if (owns_dir) dir.close(io);
        dir = child;
        owns_dir = true;
    }

    return .{ .dir = dir, .owns_dir = owns_dir, .basename = basename };
}

fn openAbsoluteParentDir(io: Io, path: []const u8, create_parent_dirs: bool) !ParentDir {
    const dirname = std.fs.path.dirname(path) orelse return error.BadPathName;
    const basename = std.fs.path.basename(path);
    if (!isValidComponent(basename)) return error.BadPathName;

    if (create_parent_dirs) {
        Io.Dir.cwd().createDirPath(io, dirname) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const dir = Io.Dir.openDirAbsolute(io, dirname, .{
        .access_sub_paths = true,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => return err,
    };
    return .{ .dir = dir, .owns_dir = true, .basename = basename };
}

fn isValidComponent(component: []const u8) bool {
    if (component.len == 0) return false;
    if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
    return true;
}

fn privateFilePermissions() Io.File.Permissions {
    return switch (builtin.os.tag) {
        .windows, .wasi => .default_file,
        else => @enumFromInt(0o600),
    };
}

test "state file atomic writes create parent directories" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/value.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try writeAtomic(io, path, "value");
    const contents = try Io.Dir.cwd().readFileAlloc(io, path, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("value", contents);
}

test "state file atomic writes support absolute app paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const relative = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/app/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(relative);
    const cwd = try std.process.currentPathAlloc(io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    const absolute = try std.fs.path.join(std.testing.allocator, &.{ cwd, ".zig-cache", "tmp" });
    defer std.testing.allocator.free(absolute);
    const path = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}/app/state.jsonl", .{ absolute, tmp.sub_path });
    defer std.testing.allocator.free(path);

    try writeAtomic(io, path, "value");
    const contents = try Io.Dir.cwd().readFileAlloc(io, relative, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("value", contents);
}

test "state file reads regular files without following symlinks" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "value" });
    const contents = (try readAlloc(std.testing.allocator, io, path, 64)).?;
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("value", contents);

    const missing = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/missing.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(missing);
    try std.testing.expect((try readAlloc(std.testing.allocator, io, missing, 64)) == null);
}

test "state file reads reject terminal symlinks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "target.jsonl", .data = "secret" });
    tmp.dir.symLink(io, "target.jsonl", "state.jsonl", .{}) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    try std.testing.expectError(error.SymLinkLoop, readAlloc(std.testing.allocator, io, path, 64));
}

test "state file reads reject intermediate symlink directories" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "inside", .default_dir);
    try tmp.dir.createDir(io, "outside", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "outside/state.jsonl", .data = "secret" });
    tmp.dir.symLink(io, "../outside", "inside/link", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/inside/link/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    if (readAlloc(std.testing.allocator, io, path, 64)) |contents| {
        if (contents) |bytes| std.testing.allocator.free(bytes);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.SymLinkLoop,
        error.NotDir,
        => {},
        else => return err,
    }
}

test "state file atomic writes reject terminal symlinks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "target.jsonl", .data = "secret" });
    tmp.dir.symLink(io, "target.jsonl", "state.jsonl", .{}) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    if (writeAtomic(io, path, "replacement")) {
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.SymLinkLoop => {},
        else => return err,
    }

    const target_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/target.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(target_path);
    const target = try Io.Dir.cwd().readFileAlloc(io, target_path, std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(target);
    try std.testing.expectEqualStrings("secret", target);
}

test "state file atomic writes reject intermediate symlink directories" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "inside", .default_dir);
    try tmp.dir.createDir(io, "outside", .default_dir);
    tmp.dir.symLink(io, "../outside", "inside/link", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/inside/link/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    if (writeAtomic(io, path, "value")) {
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.SymLinkLoop,
        error.NotDir,
        => {},
        else => return err,
    }
}

test "state file locks create parent directories" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/value.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var lock = try lockPath(std.testing.allocator, io, path);
    lock.close(io);

    const lock_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.lock", .{path});
    defer std.testing.allocator.free(lock_path);
    var opened = try Io.Dir.cwd().openFile(io, lock_path, .{});
    opened.close(io);
}

test "state file try lock reports active lock without waiting" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/value.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var first = try lockPath(std.testing.allocator, io, path);
    defer first.close(io);

    const second = try tryLockPath(std.testing.allocator, io, path);
    try std.testing.expect(second == null);
}

test "state file lock creation retries when another writer creates the lock first" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "state.jsonl.lock", .data = "" });
    var lock = try createOrOpenLockFile(io, tmp.dir, "state.jsonl.lock", false);
    lock.close(io);
}

test "state file locks reject terminal symlinks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "target.lock", .data = "" });
    tmp.dir.symLink(io, "target.lock", "state.jsonl.lock", .{}) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    try std.testing.expectError(error.SymLinkLoop, lockPath(std.testing.allocator, io, path));
}

test "state file locks reject intermediate symlink directories" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "inside", .default_dir);
    try tmp.dir.createDir(io, "outside", .default_dir);
    tmp.dir.symLink(io, "../outside", "inside/link", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/inside/link/state.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    if (lockPath(std.testing.allocator, io, path)) |lock| {
        var lock_file = lock;
        lock_file.close(io);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.SymLinkLoop,
        error.NotDir,
        => {},
        else => return err,
    }
}
