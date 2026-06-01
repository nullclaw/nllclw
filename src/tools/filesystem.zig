const std = @import("std");
const builtin = @import("builtin");
const io_file = @import("../adapters/io_file.zig");
const chat = @import("../chat.zig");
const path_policy = @import("../path_policy.zig");
const text_policy = @import("../text_policy.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_path_bytes: usize = 512;

const path_parameter = [_]chat.ToolParameter{
    .{
        .name = "path",
        .kind = .string,
        .description = "CWD-relative path. Absolute paths and .. are rejected.",
    },
};
const write_parameters = [_]chat.ToolParameter{
    .{
        .name = "path",
        .kind = .string,
        .description = "CWD-relative path. Absolute paths and .. are rejected.",
    },
    .{
        .name = "content",
        .kind = .string,
        .description = "Text content to write.",
    },
};
const edit_parameters = [_]chat.ToolParameter{
    .{
        .name = "path",
        .kind = .string,
        .description = "CWD-relative path. Absolute paths and .. are rejected.",
    },
    .{
        .name = "old_string",
        .kind = .string,
        .description = "Exact text to replace.",
    },
    .{
        .name = "new_string",
        .kind = .string,
        .description = "Replacement text.",
    },
};

pub const list_dir_definition: chat.ToolDefinition = .{
    .name = "list_dir",
    .description = "List entries in a CWD-relative directory.",
    .parameters = .{
        .properties = &path_parameter,
        .required = &.{"path"},
    },
};

pub const read_file_definition: chat.ToolDefinition = .{
    .name = "read_file",
    .description = "Read a UTF-8/text file from a CWD-relative non-symlink path, capped by the configured tool output limit.",
    .parameters = .{
        .properties = &path_parameter,
        .required = &.{"path"},
    },
};

pub const write_file_definition: chat.ToolDefinition = .{
    .name = "write_file",
    .description = "Write a UTF-8/text file to a CWD-relative non-symlink path.",
    .parameters = .{
        .properties = &write_parameters,
        .required = &.{ "path", "content" },
    },
};

pub const edit_file_definition: chat.ToolDefinition = .{
    .name = "edit_file",
    .description = "Replace the first exact occurrence of old_string in a CWD-relative non-symlink text file.",
    .parameters = .{
        .properties = &edit_parameters,
        .required = &.{ "path", "old_string", "new_string" },
    },
};

pub const Client = struct {
    io: Io,
    output_max_bytes: usize,

    pub fn init(io: Io, output_max_bytes: usize) Client {
        return .{ .io = io, .output_max_bytes = output_max_bytes };
    }

    pub fn listDirHandler(self: *Client) tool.Handler {
        return .{
            .definition = list_dir_definition,
            .ptr = self,
            .run_fn = runListDir,
        };
    }

    pub fn readFileHandler(self: *Client) tool.Handler {
        return .{
            .definition = read_file_definition,
            .ptr = self,
            .run_fn = runReadFile,
        };
    }

    pub fn writeFileHandler(self: *Client) tool.Handler {
        return .{
            .definition = write_file_definition,
            .ptr = self,
            .run_fn = runWriteFile,
            .mutates_state = true,
        };
    }

    pub fn editFileHandler(self: *Client) tool.Handler {
        return .{
            .definition = edit_file_definition,
            .ptr = self,
            .run_fn = runEditFile,
            .mutates_state = true,
        };
    }

    fn runListDir(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const path = try parsePath(allocator, call.arguments);
        defer allocator.free(path);
        return listDir(allocator, self.io, path, self.output_max_bytes);
    }

    fn runReadFile(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const path = try parseFilePath(allocator, call.arguments);
        defer allocator.free(path);

        return readFile(allocator, self.io, path, self.output_max_bytes);
    }

    fn runWriteFile(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        var args = try parseWriteArgs(allocator, call.arguments, self.output_max_bytes);
        defer args.deinit(allocator);

        try ensurePathResultFits("wrote: ", args.path, self.output_max_bytes);
        try writeFileTool(self.io, args.path, args.content, self.output_max_bytes);
        return pathResult(allocator, "wrote: ", args.path, self.output_max_bytes);
    }

    fn runEditFile(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        var args = try parseEditArgs(allocator, call.arguments, self.output_max_bytes);
        defer args.deinit(allocator);
        try ensurePathResultFits("edited: ", args.path, self.output_max_bytes);

        const original = try readFile(allocator, self.io, args.path, self.output_max_bytes);
        defer allocator.free(original);
        const index = std.mem.indexOf(u8, original, args.old_string) orelse return error.InvalidToolArguments;
        const next_len = std.math.add(usize, original.len - args.old_string.len, args.new_string.len) catch {
            return error.ToolOutputTooLarge;
        };
        if (next_len > self.output_max_bytes) return error.ToolOutputTooLarge;

        var out = std.Io.Writer.Allocating.init(allocator);
        defer out.deinit();
        out.writer.writeAll(original[0..index]) catch return error.OutOfMemory;
        out.writer.writeAll(args.new_string) catch return error.OutOfMemory;
        out.writer.writeAll(original[index + args.old_string.len ..]) catch return error.OutOfMemory;
        try writeFileTool(self.io, args.path, out.written(), self.output_max_bytes);
        return pathResult(allocator, "edited: ", args.path, self.output_max_bytes);
    }
};

const PathArgs = struct {
    path: []const u8 = "",
};

const WriteArgs = struct {
    path: []const u8 = "",
    content: []const u8 = "",
};

const EditArgs = struct {
    path: []const u8 = "",
    old_string: []const u8 = "",
    new_string: []const u8 = "",
};

const WriteArgsOwned = struct {
    path: []u8,
    content: []u8,

    fn deinit(self: *WriteArgsOwned, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.content);
        self.* = undefined;
    }
};

const EditArgsOwned = struct {
    path: []u8,
    old_string: []u8,
    new_string: []u8,

    fn deinit(self: *EditArgsOwned, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.old_string);
        allocator.free(self.new_string);
        self.* = undefined;
    }
};

fn parsePath(allocator: Allocator, arguments: []const u8) tool.RunError![]u8 {
    const parsed = try tool.parseArgs(PathArgs, allocator, arguments, .{});
    defer parsed.deinit();

    return parsePathValue(allocator, parsed.value.path, true);
}

fn parseFilePath(allocator: Allocator, arguments: []const u8) tool.RunError![]u8 {
    const parsed = try tool.parseArgs(PathArgs, allocator, arguments, .{});
    defer parsed.deinit();

    return parsePathValue(allocator, parsed.value.path, false);
}

fn parsePathValue(allocator: Allocator, value: []const u8, allow_current_dir: bool) tool.RunError![]u8 {
    const raw = std.mem.trim(u8, value, &std.ascii.whitespace);
    if (!isValidPathText(raw)) return error.InvalidToolArguments;
    if (std.fs.path.parsePathPosix(raw).kind != .relative) return error.InvalidToolArguments;
    if (std.fs.path.parsePathWindows(u8, raw).kind != .relative) return error.InvalidToolArguments;

    if (std.mem.eql(u8, raw, ".")) {
        if (!allow_current_dir) return error.InvalidToolArguments;
        return try allocator.dupe(u8, raw);
    }

    var components = std.mem.splitAny(u8, raw, "/\\");
    while (components.next()) |component| {
        if (component.len == 0) return error.InvalidToolArguments;
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.InvalidToolArguments;
        if (isDeniedPathComponent(component)) return error.InvalidToolArguments;
    }

    return try allocator.dupe(u8, raw);
}

fn parseWriteArgs(allocator: Allocator, arguments: []const u8, limit: usize) tool.RunError!WriteArgsOwned {
    const parsed = try tool.parseArgs(WriteArgs, allocator, arguments, .{});
    defer parsed.deinit();

    const path = try parsePathValue(allocator, parsed.value.path, false);
    errdefer allocator.free(path);
    if (parsed.value.content.len > limit) return error.ToolOutputTooLarge;
    if (!isValidTextContent(parsed.value.content)) return error.InvalidToolArguments;
    const content = try allocator.dupe(u8, parsed.value.content);
    return .{ .path = path, .content = content };
}

fn parseEditArgs(allocator: Allocator, arguments: []const u8, limit: usize) tool.RunError!EditArgsOwned {
    const parsed = try tool.parseArgs(EditArgs, allocator, arguments, .{});
    defer parsed.deinit();

    const path = try parsePathValue(allocator, parsed.value.path, false);
    errdefer allocator.free(path);
    if (parsed.value.old_string.len == 0) return error.InvalidToolArguments;
    if (parsed.value.old_string.len > limit) return error.InvalidToolArguments;
    if (parsed.value.new_string.len > limit) return error.ToolOutputTooLarge;
    if (!isValidTextContent(parsed.value.old_string)) return error.InvalidToolArguments;
    if (!isValidTextContent(parsed.value.new_string)) return error.InvalidToolArguments;
    const old_string = try allocator.dupe(u8, parsed.value.old_string);
    errdefer allocator.free(old_string);
    const new_string = try allocator.dupe(u8, parsed.value.new_string);
    return .{ .path = path, .old_string = old_string, .new_string = new_string };
}

fn listDir(allocator: Allocator, io: Io, path: []const u8, limit: usize) tool.RunError![]u8 {
    var parent = try openParentDir(io, path);
    defer parent.deinit(io);

    var dir = parent.dir.openDir(io, parent.basename, .{
        .iterate = true,
        .access_sub_paths = false,
        .follow_symlinks = false,
    }) catch return error.ToolFailed;
    defer dir.close(io);
    var iter = dir.iterate();

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    var output_len: usize = "entries:\n".len;
    if (output_len > limit) return error.ToolOutputTooLarge;

    while (iter.next(io) catch return error.ToolFailed) |entry| {
        const name = entry.name;
        if (!isListableEntryName(name)) continue;
        output_len = std.math.add(usize, output_len, name.len) catch return error.ToolOutputTooLarge;
        output_len = std.math.add(usize, output_len, 1) catch return error.ToolOutputTooLarge;
        if (output_len > limit) return error.ToolOutputTooLarge;

        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        try names.append(allocator, owned_name);
    }

    std.mem.sort([]u8, names.items, {}, stringLessThan);

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    appendLimited(&out, "entries:\n", limit) catch |err| return mapWriteError(err);
    for (names.items) |name| {
        appendLimited(&out, name, limit) catch |err| return mapWriteError(err);
        appendLimited(&out, "\n", limit) catch |err| return mapWriteError(err);
    }

    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn readFile(allocator: Allocator, io: Io, path: []const u8, limit: usize) tool.RunError![]u8 {
    var parent = try openParentDir(io, path);
    defer parent.deinit(io);

    var file = parent.dir.openFile(io, parent.basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch return error.ToolFailed;
    io_file.fixWindowsNoFollowFile(&file);
    defer file.close(io);

    var reader = file.reader(io, &.{});
    const contents = reader.interface.allocRemaining(allocator, .limited(limit)) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.ToolOutputTooLarge,
        else => error.ToolFailed,
    };
    errdefer allocator.free(contents);
    if (!isValidTextContent(contents)) return error.ToolFailed;
    return contents;
}

fn writeFileTool(io: Io, path: []const u8, content: []const u8, limit: usize) tool.RunError!void {
    if (content.len > limit) return error.ToolOutputTooLarge;
    if (!isValidTextContent(content)) return error.InvalidToolArguments;

    var parent = try openParentDir(io, path);
    defer parent.deinit(io);

    if (parent.dir.openFile(io, parent.basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    })) |existing| {
        var file = existing;
        file.close(io);
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return error.ToolFailed,
    }

    var file = parent.dir.createFileAtomic(io, parent.basename, .{
        .permissions = privateFilePermissions(),
        .replace = true,
    }) catch return error.ToolFailed;
    defer file.deinit(io);

    file.file.writeStreamingAll(io, content) catch return error.ToolFailed;
    file.file.sync(io) catch return error.ToolFailed;
    file.replace(io) catch return error.ToolFailed;
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

fn openParentDir(io: Io, path: []const u8) tool.RunError!ParentDir {
    var components = std.mem.tokenizeAny(u8, path, "/\\");
    var basename = components.next() orelse return error.InvalidToolArguments;

    var dir = Io.Dir.cwd();
    var owns_dir = false;
    errdefer if (owns_dir) dir.close(io);

    while (components.next()) |next| {
        const child = dir.openDir(io, basename, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch return error.ToolFailed;
        if (owns_dir) dir.close(io);
        dir = child;
        owns_dir = true;
        basename = next;
    }

    return .{
        .dir = dir,
        .owns_dir = owns_dir,
        .basename = basename,
    };
}

fn appendLimited(out: *std.Io.Writer.Allocating, bytes: []const u8, limit: usize) (Allocator.Error || error{ToolOutputTooLarge})!void {
    const next_len = std.math.add(usize, out.written().len, bytes.len) catch return error.ToolOutputTooLarge;
    if (next_len > limit) return error.ToolOutputTooLarge;
    out.writer.writeAll(bytes) catch return error.OutOfMemory;
}

const LimitedWriteError = Allocator.Error || error{ToolOutputTooLarge};

fn pathResult(allocator: Allocator, prefix: []const u8, path: []const u8, limit: usize) tool.RunError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    appendLimited(&out, prefix, limit) catch |err| return mapWriteError(err);
    appendLimited(&out, path, limit) catch |err| return mapWriteError(err);
    appendLimited(&out, "\n", limit) catch |err| return mapWriteError(err);
    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn ensurePathResultFits(prefix: []const u8, path: []const u8, limit: usize) error{ToolOutputTooLarge}!void {
    var len = std.math.add(usize, prefix.len, path.len) catch return error.ToolOutputTooLarge;
    len = std.math.add(usize, len, 1) catch return error.ToolOutputTooLarge;
    if (len > limit) return error.ToolOutputTooLarge;
}

fn privateFilePermissions() Io.File.Permissions {
    return switch (builtin.os.tag) {
        .windows, .wasi => .default_file,
        else => @enumFromInt(0o600),
    };
}

fn isDeniedPathComponent(component: []const u8) bool {
    if (path_policy.isWindowsReservedFilenameComponent(component)) return true;
    if (std.ascii.eqlIgnoreCase(component, ".env")) return true;
    if (std.ascii.startsWithIgnoreCase(component, ".env.")) return true;
    if (std.ascii.eqlIgnoreCase(component, "config.json")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".git")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".ssh")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".gnupg")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".aws")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".npmrc")) return true;
    if (std.ascii.eqlIgnoreCase(component, "id_rsa")) return true;
    if (std.ascii.eqlIgnoreCase(component, "id_ed25519")) return true;
    if (std.ascii.endsWithIgnoreCase(component, ".pem")) return true;
    if (std.ascii.endsWithIgnoreCase(component, ".key")) return true;
    if (std.ascii.endsWithIgnoreCase(component, ".p12")) return true;
    if (std.ascii.endsWithIgnoreCase(component, ".pfx")) return true;
    return false;
}

fn isValidPathText(path: []const u8) bool {
    if (path.len == 0 or path.len > max_path_bytes) return false;
    return text_policy.isSingleLineText(path);
}

fn isListableEntryName(name: []const u8) bool {
    if (isDeniedPathComponent(name)) return false;
    return text_policy.isSingleLineText(name);
}

fn isValidTextContent(content: []const u8) bool {
    return text_policy.isMultilineText(content);
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn mapWriteError(err: LimitedWriteError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
    };
}

test "parsePath accepts cwd-relative paths and rejects escapes" {
    const path = try parsePath(std.testing.allocator, "{\"path\":\"src/main.zig\"}");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("src/main.zig", path);

    const cwd_path = try parsePath(std.testing.allocator, "{\"path\":\".\"}");
    defer std.testing.allocator.free(cwd_path);
    try std.testing.expectEqualStrings(".", cwd_path);
    try std.testing.expectError(error.InvalidToolArguments, parseFilePath(std.testing.allocator, "{\"path\":\".\"}"));

    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"/etc/passwd\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"C:\\\\Windows\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"C:Windows\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"\\\\\\\\server\\\\share\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"src//main.zig\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"src/./main.zig\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"src/\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"../secret\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe\\\\..\\\\secret\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\".env\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\".ENV\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\".env.local\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"config.json\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"CONFIG.JSON\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\".AWS/config\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"keys/private.pem\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"keys/private.KEY\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"keys/ID_RSA\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"bad?.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/bad:name.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/*.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/trailing./file.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/trailing /file.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"NUL.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/COM1.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/lpt9\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"safe/CONOUT$.txt\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"line\\nbreak\"}"));
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, "{\"path\":\"src/main.zig\",\"unknown\":true}"));

    var long_path: [max_path_bytes + 1]u8 = undefined;
    @memset(&long_path, 'a');
    const long_args = try std.fmt.allocPrint(std.testing.allocator, "{{\"path\":\"{s}\"}}", .{&long_path});
    defer std.testing.allocator.free(long_args);
    try std.testing.expectError(error.InvalidToolArguments, parsePath(std.testing.allocator, long_args));
}

test "safe local tools can read and list cwd-relative paths" {
    var threaded: Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    var client = Client.init(threaded.io(), 4096);

    const read = try client.readFileHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "read_file",
        .arguments = "{\"path\":\"build.zig\"}",
    });
    defer std.testing.allocator.free(read);
    try std.testing.expect(std.mem.indexOf(u8, read, "pub fn build") != null);

    const listing = try client.listDirHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "list_dir",
        .arguments = "{\"path\":\"src\"}",
    });
    defer std.testing.allocator.free(listing);
    try std.testing.expect(std.mem.indexOf(u8, listing, "main.zig") != null);
}

test "write and edit tools update cwd-relative files" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/note.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var client = Client.init(io, 4096);
    const write_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"content\":\"hello world\"}}",
        .{path},
    );
    defer std.testing.allocator.free(write_args);
    const wrote = try client.writeFileHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "write_file",
        .arguments = write_args,
    });
    defer std.testing.allocator.free(wrote);
    try std.testing.expect(std.mem.indexOf(u8, wrote, "wrote:") != null);

    const edit_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"old_string\":\"world\",\"new_string\":\"zig\"}}",
        .{path},
    );
    defer std.testing.allocator.free(edit_args);
    const edited = try client.editFileHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "edit_file",
        .arguments = edit_args,
    });
    defer std.testing.allocator.free(edited);
    try std.testing.expect(std.mem.indexOf(u8, edited, "edited:") != null);

    const contents = try readFile(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("hello zig", contents);

    const missing_old_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"old_string\":\"missing\",\"new_string\":\"nope\"}}",
        .{path},
    );
    defer std.testing.allocator.free(missing_old_args);
    try std.testing.expectError(error.InvalidToolArguments, client.editFileHandler().run(std.testing.allocator, .{
        .id = "call_3",
        .name = "edit_file",
        .arguments = missing_old_args,
    }));
}

test "file tools reject non-utf8 text" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "binary.dat", .data = "\xff" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/binary.dat", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try std.testing.expectError(error.ToolFailed, readFile(std.testing.allocator, io, path, 4096));

    const out_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/out.txt",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(out_path);
    try std.testing.expectError(error.InvalidToolArguments, writeFileTool(io, out_path, "\xff", 4096));
}

test "file tools reject NUL in text content" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "nul.txt", .data = "ok\x00bad" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/nul.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try std.testing.expectError(error.ToolFailed, readFile(std.testing.allocator, io, path, 4096));

    const out_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/out.txt",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(out_path);
    try std.testing.expectError(error.InvalidToolArguments, writeFileTool(io, out_path, "ok\x00bad", 4096));

    const write_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"content\":\"ok\\u0000bad\"}}",
        .{out_path},
    );
    defer std.testing.allocator.free(write_args);
    try std.testing.expectError(error.InvalidToolArguments, parseWriteArgs(std.testing.allocator, write_args, 4096));
    const write_unknown_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"content\":\"ok\",\"unknown\":true}}",
        .{out_path},
    );
    defer std.testing.allocator.free(write_unknown_args);
    try std.testing.expectError(error.InvalidToolArguments, parseWriteArgs(std.testing.allocator, write_unknown_args, 4096));

    const edit_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"old_string\":\"ok\",\"new_string\":\"bad\\u0000value\"}}",
        .{out_path},
    );
    defer std.testing.allocator.free(edit_args);
    try std.testing.expectError(error.InvalidToolArguments, parseEditArgs(std.testing.allocator, edit_args, 4096));
    const edit_unknown_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"old_string\":\"ok\",\"new_string\":\"bad\",\"unknown\":true}}",
        .{out_path},
    );
    defer std.testing.allocator.free(edit_unknown_args);
    try std.testing.expectError(error.InvalidToolArguments, parseEditArgs(std.testing.allocator, edit_unknown_args, 4096));
}

test "file tools reject binary control bytes in text content" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "ansi.txt", .data = "ok\x1bbad" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/ansi.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    try std.testing.expectError(error.ToolFailed, readFile(std.testing.allocator, io, path, 4096));

    const out_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/out.txt",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(out_path);
    try std.testing.expectError(error.InvalidToolArguments, writeFileTool(io, out_path, "ok\x1bbad", 4096));

    const write_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"content\":\"ok\\u001bbad\"}}",
        .{out_path},
    );
    defer std.testing.allocator.free(write_args);
    try std.testing.expectError(error.InvalidToolArguments, parseWriteArgs(std.testing.allocator, write_args, 4096));

    const edit_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"old_string\":\"ok\",\"new_string\":\"bad\\u001bvalue\"}}",
        .{out_path},
    );
    defer std.testing.allocator.free(edit_args);
    try std.testing.expectError(error.InvalidToolArguments, parseEditArgs(std.testing.allocator, edit_args, 4096));
}

test "write and edit tools check result cap before mutating" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/note.txt", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var write_client = Client.init(io, "wrote: ".len + path.len);
    const write_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"content\":\"hello\"}}",
        .{path},
    );
    defer std.testing.allocator.free(write_args);
    try std.testing.expectError(error.ToolOutputTooLarge, write_client.writeFileHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "write_file",
        .arguments = write_args,
    }));

    if (Io.Dir.cwd().openFile(io, path, .{})) |opened| {
        var file = opened;
        file.close(io);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    try writeFileTool(io, path, "hello world", 4096);

    var edit_client = Client.init(io, "edited: ".len + path.len);
    const edit_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"path\":\"{s}\",\"old_string\":\"world\",\"new_string\":\"zig\"}}",
        .{path},
    );
    defer std.testing.allocator.free(edit_args);
    try std.testing.expectError(error.ToolOutputTooLarge, edit_client.editFileHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "edit_file",
        .arguments = edit_args,
    }));

    const contents = try readFile(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("hello world", contents);
}

test "list_dir filters denied secret-looking entries" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = ".env", .data = "secret" });
    try tmp.dir.writeFile(io, .{ .sub_path = "config.json", .data = "{\"api_key\":\"secret\"}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "visible.txt", .data = "ok" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const listing = try listDir(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(listing);

    try std.testing.expect(std.mem.indexOf(u8, listing, "visible.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, ".env") == null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "config.json") == null);
}

test "list_dir returns stable sorted entry names" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "b.txt", .data = "b" });
    try tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "a" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const listing = try listDir(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(listing);

    try std.testing.expectEqualStrings("entries:\na.txt\nb.txt\n", listing);
}

test "list_dir omits control-character entry names" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    tmp.dir.writeFile(io, .{ .sub_path = "line\nbreak.txt", .data = "hidden" }) catch |err| switch (err) {
        error.BadPathName => return error.SkipZigTest,
        else => return err,
    };
    try tmp.dir.writeFile(io, .{ .sub_path = "visible.txt", .data = "ok" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const listing = try listDir(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(listing);

    try std.testing.expectEqualStrings("entries:\nvisible.txt\n", listing);
}

test "list_dir omits Windows-reserved entry names" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    tmp.dir.writeFile(io, .{ .sub_path = "bad?.txt", .data = "hidden" }) catch |err| switch (err) {
        error.BadPathName => return error.SkipZigTest,
        else => return err,
    };
    tmp.dir.writeFile(io, .{ .sub_path = "bad.", .data = "hidden" }) catch |err| switch (err) {
        error.BadPathName => return error.SkipZigTest,
        else => return err,
    };
    tmp.dir.writeFile(io, .{ .sub_path = "bad ", .data = "hidden" }) catch |err| switch (err) {
        error.BadPathName => return error.SkipZigTest,
        else => return err,
    };
    try tmp.dir.writeFile(io, .{ .sub_path = "visible.txt", .data = "ok" });

    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(path);
    const listing = try listDir(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(listing);

    try std.testing.expectEqualStrings("entries:\nvisible.txt\n", listing);
}

test "list_dir entry name policy rejects non-utf8 names" {
    try std.testing.expect(!isListableEntryName("\xff"));
    try std.testing.expect(isListableEntryName("visible.txt"));
}

test "safe local tools reject intermediate symlink escapes" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "inside", .default_dir);
    try tmp.dir.createDir(io, "outside", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "outside/secret.txt", .data = "secret" });
    tmp.dir.symLink(io, "../outside", "inside/link", .{ .is_directory = true }) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const file_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/inside/link/secret.txt",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(file_path);

    const dir_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/inside/link",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(dir_path);

    try std.testing.expectError(error.ToolFailed, readFile(std.testing.allocator, io, file_path, 4096));
    try std.testing.expectError(error.ToolFailed, listDir(std.testing.allocator, io, dir_path, 4096));
}

test "safe local tools reject terminal symlink files" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "outside", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "outside/secret.txt", .data = "secret" });
    tmp.dir.symLink(io, "outside/secret.txt", "link.txt", .{}) catch |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileSystem,
        => return error.SkipZigTest,
        else => return err,
    };

    const path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/link.txt",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(path);

    try std.testing.expectError(error.ToolFailed, readFile(std.testing.allocator, io, path, 4096));
    try std.testing.expectError(error.ToolFailed, writeFileTool(io, path, "overwrite", 4096));
}
