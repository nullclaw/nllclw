const std = @import("std");
const chat = @import("../chat.zig");
const state_file = @import("../adapters/state_file.zig");
const text_policy = @import("../text_policy.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_file_bytes = 128 * 1024;
pub const max_tools: usize = 16;
pub const max_name_bytes: usize = 48;
pub const max_description_bytes: usize = 256;
pub const max_action_bytes: usize = 2048;

const macro_action_prefix = "Execute this user-defined tool action now using available tools:\n";
const macro_action_suffix = "\n";

pub const StoreError = Allocator.Error || error{
    UserToolLimit,
    UserToolExists,
    InvalidUserToolLine,
    InvalidUserToolName,
    InvalidUserToolDescription,
    InvalidUserToolAction,
    StorageFailed,
    StreamTooLong,
    ToolOutputTooLarge,
};

const name_parameter = chat.ToolParameter{
    .name = "name",
    .kind = .string,
    .description = "Tool name using letters, digits, and underscores.",
};
const description_parameter = chat.ToolParameter{
    .name = "description",
    .kind = .string,
    .description = "Short model-facing description.",
};
const action_parameter = chat.ToolParameter{
    .name = "action",
    .kind = .string,
    .description = "Natural-language steps to execute using available built-in tools.",
};

const create_parameters = [_]chat.ToolParameter{
    name_parameter,
    description_parameter,
    action_parameter,
};
const delete_parameters = [_]chat.ToolParameter{name_parameter};

pub const create_definition: chat.ToolDefinition = .{
    .name = "create_tool",
    .description = "Create a persistent user-defined macro tool composed from natural-language steps.",
    .parameters = .{
        .properties = &create_parameters,
        .required = &.{ "name", "description", "action" },
    },
};

pub const list_definition: chat.ToolDefinition = .{
    .name = "list_user_tools",
    .description = "List persistent user-defined macro tools.",
    .parameters = .{ .properties = &.{} },
};

pub const delete_definition: chat.ToolDefinition = .{
    .name = "delete_user_tool",
    .description = "Delete a persistent user-defined macro tool by name.",
    .parameters = .{
        .properties = &delete_parameters,
        .required = &.{"name"},
    },
};

pub const Entry = struct {
    name: []u8,
    description: []u8,
    action: []u8,

    fn deinit(self: *Entry, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.action);
        self.* = undefined;
    }
};

pub const Entries = struct {
    items: []Entry = &.{},

    pub fn deinit(self: *Entries, allocator: Allocator) void {
        for (self.items) |*entry| entry.deinit(allocator);
        allocator.free(self.items);
        self.* = .{};
    }
};

pub const Client = struct {
    io: Io,
    path: []const u8,
    output_max_bytes: usize,
    entries: Entries,

    pub fn init(allocator: Allocator, io: Io, path: []const u8, output_max_bytes: usize) StoreError!Client {
        return .{
            .io = io,
            .path = path,
            .output_max_bytes = output_max_bytes,
            .entries = try load(allocator, io, path),
        };
    }

    pub fn deinit(self: *Client, allocator: Allocator) void {
        self.entries.deinit(allocator);
        self.* = undefined;
    }

    pub fn createHandler(self: *Client) tool.Handler {
        return .{ .definition = create_definition, .ptr = self, .run_fn = runCreate, .mutates_state = true };
    }

    pub fn listHandler(self: *Client) tool.Handler {
        return .{ .definition = list_definition, .ptr = self, .run_fn = runList };
    }

    pub fn deleteHandler(self: *Client) tool.Handler {
        return .{ .definition = delete_definition, .ptr = self, .run_fn = runDelete, .mutates_state = true };
    }

    pub fn dynamicHandler(self: *Client, index: usize) tool.Handler {
        const entry = self.entries.items[index];
        return .{
            .definition = .{
                .name = entry.name,
                .description = entry.description,
                .parameters = .{ .properties = &.{} },
            },
            .ptr = self,
            .run_fn = runMacro,
            .mutates_state = true,
        };
    }

    fn runCreate(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        var args = try parseCreateArgs(allocator, call.arguments);
        defer args.deinit(allocator);

        try ensureNameResultFits("created user tool: ", args.name, self.output_max_bytes);
        try ensureMacroOutputFits(args.action, self.output_max_bytes);
        create(self.io, self.path, allocator, args.entry()) catch |err| return mapCreateError(err);
        return nameResult(allocator, "created user tool: ", args.name, self.output_max_bytes);
    }

    fn runList(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        try parseEmptyObject(allocator, call.arguments);
        return listText(allocator, self.io, self.path, self.output_max_bytes) catch |err| return mapStateError(err);
    }

    fn runDelete(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        var args = try parseNameArgs(allocator, call.arguments);
        defer args.deinit(allocator);

        try ensureNameResultFits("not found user tool: ", args.name, self.output_max_bytes);
        const deleted = delete(self.io, self.path, allocator, args.name) catch |err| return mapStateError(err);
        if (deleted) return nameResult(allocator, "deleted user tool: ", args.name, self.output_max_bytes);
        return nameResult(allocator, "not found user tool: ", args.name, self.output_max_bytes);
    }

    fn runMacro(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        try parseEmptyObject(allocator, call.arguments);

        var entries = load(allocator, self.io, self.path) catch |err| return mapStateError(err);
        defer entries.deinit(allocator);

        for (entries.items) |entry| {
            if (std.mem.eql(u8, entry.name, call.name)) {
                return macroText(allocator, entry.action, self.output_max_bytes);
            }
        }
        return error.UnknownTool;
    }
};

const ParsedEntry = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    action: []const u8 = "",
};

const NameArgs = struct {
    name: []const u8 = "",
};

const EmptyArgs = struct {};

const OwnedEntry = struct {
    name: []u8,
    description: []u8,
    action: []u8,

    fn entry(self: OwnedEntry) NewEntry {
        return .{
            .name = self.name,
            .description = self.description,
            .action = self.action,
        };
    }

    fn deinit(self: *OwnedEntry, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.action);
        self.* = undefined;
    }
};

const OwnedName = struct {
    name: []u8,

    fn deinit(self: *OwnedName, allocator: Allocator) void {
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const NewEntry = struct {
    name: []const u8,
    description: []const u8,
    action: []const u8,
};

pub fn load(allocator: Allocator, io: Io, path: []const u8) StoreError!Entries {
    const bytes = (state_file.readAlloc(allocator, io, path, max_file_bytes) catch |err| return mapReadError(err)) orelse return .{};
    defer allocator.free(bytes);
    return parseJsonl(allocator, bytes);
}

pub fn create(io: Io, path: []const u8, allocator: Allocator, entry: NewEntry) StoreError!void {
    const normalized = try normalizeNewEntry(entry);

    var lock_file = try lockPath(allocator, io, path);
    defer lock_file.close(io);

    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);
    if (entries.items.len >= max_tools) return error.UserToolLimit;
    for (entries.items) |existing| {
        if (std.mem.eql(u8, existing.name, normalized.name)) return error.UserToolExists;
    }

    var list: std.ArrayList(Entry) = .empty;
    defer list.deinit(allocator);
    try list.appendSlice(allocator, entries.items);

    var name: ?[]u8 = try allocator.dupe(u8, normalized.name);
    errdefer if (name) |bytes| allocator.free(bytes);
    var description: ?[]u8 = try allocator.dupe(u8, normalized.description);
    errdefer if (description) |bytes| allocator.free(bytes);
    var action: ?[]u8 = try allocator.dupe(u8, normalized.action);
    errdefer if (action) |bytes| allocator.free(bytes);

    try list.append(allocator, .{ .name = name.?, .description = description.?, .action = action.? });
    name = null;
    description = null;
    action = null;
    errdefer {
        if (list.pop()) |removed| {
            allocator.free(removed.name);
            allocator.free(removed.description);
            allocator.free(removed.action);
        }
    }

    try saveEntries(allocator, io, path, list.items);
    if (list.pop()) |removed| {
        allocator.free(removed.name);
        allocator.free(removed.description);
        allocator.free(removed.action);
    }
}

pub fn delete(io: Io, path: []const u8, allocator: Allocator, name: []const u8) StoreError!bool {
    var lock_file = try lockPath(allocator, io, path);
    defer lock_file.close(io);

    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var kept: std.ArrayList(Entry) = .empty;
    defer kept.deinit(allocator);
    var deleted = false;
    for (entries.items) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            deleted = true;
        } else {
            try kept.append(allocator, entry);
        }
    }
    if (!deleted) return false;

    try saveEntries(allocator, io, path, kept.items);
    return true;
}

pub fn listText(allocator: Allocator, io: Io, path: []const u8, limit: usize) StoreError![]u8 {
    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try appendLimited(&out, "user tools:\n", limit);
    for (entries.items) |entry| {
        const line = try std.fmt.allocPrint(allocator, "- {s}: {s}\n", .{ entry.name, entry.description });
        defer allocator.free(line);
        try appendLimited(&out, line, limit);
    }
    return out.toOwnedSlice();
}

pub fn parseJsonl(allocator: Allocator, bytes: []const u8) StoreError!Entries {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (entries.items.len >= max_tools) return error.UserToolLimit;

        const parsed = std.json.parseFromSlice(ParsedEntry, allocator, line, .{
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidUserToolLine,
        };
        defer parsed.deinit();
        const normalized = try normalizeNewEntry(.{
            .name = parsed.value.name,
            .description = parsed.value.description,
            .action = parsed.value.action,
        });
        if (containsName(entries.items, normalized.name)) return error.InvalidUserToolLine;

        const name = try allocator.dupe(u8, normalized.name);
        errdefer allocator.free(name);
        const description = try allocator.dupe(u8, normalized.description);
        errdefer allocator.free(description);
        const action = try allocator.dupe(u8, normalized.action);
        errdefer allocator.free(action);
        try entries.append(allocator, .{
            .name = name,
            .description = description,
            .action = action,
        });
    }

    return .{ .items = try entries.toOwnedSlice(allocator) };
}

pub fn saveEntries(allocator: Allocator, io: Io, path: []const u8, entries: []const Entry) StoreError!void {
    const bytes = try buildJsonl(allocator, entries);
    defer allocator.free(bytes);
    try writeAtomic(io, path, bytes);
}

pub fn buildJsonl(allocator: Allocator, entries: []const Entry) StoreError![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    for (entries) |entry| {
        try writeEntry(&out.writer, entry);
        try ensureJsonlFits(&out);
    }
    return out.toOwnedSlice();
}

fn writeEntry(writer: *Io.Writer, entry: Entry) StoreError!void {
    const normalized = try normalizeNewEntry(.{
        .name = entry.name,
        .description = entry.description,
        .action = entry.action,
    });

    var json: std.json.Stringify = .{ .writer = writer, .options = .{} };
    json.beginObject() catch return error.OutOfMemory;
    json.objectField("name") catch return error.OutOfMemory;
    json.write(normalized.name) catch return error.OutOfMemory;
    json.objectField("description") catch return error.OutOfMemory;
    json.write(normalized.description) catch return error.OutOfMemory;
    json.objectField("action") catch return error.OutOfMemory;
    json.write(normalized.action) catch return error.OutOfMemory;
    json.endObject() catch return error.OutOfMemory;
    writer.writeByte('\n') catch return error.OutOfMemory;
}

fn parseCreateArgs(allocator: Allocator, arguments: []const u8) tool.RunError!OwnedEntry {
    const parsed = try tool.parseArgs(ParsedEntry, allocator, arguments, .{});
    defer parsed.deinit();

    const normalized = normalizeNewEntry(.{
        .name = parsed.value.name,
        .description = parsed.value.description,
        .action = parsed.value.action,
    }) catch return error.InvalidToolArguments;

    const name = try allocator.dupe(u8, normalized.name);
    errdefer allocator.free(name);
    const description = try allocator.dupe(u8, normalized.description);
    errdefer allocator.free(description);
    const action = try allocator.dupe(u8, normalized.action);
    return .{ .name = name, .description = description, .action = action };
}

fn parseNameArgs(allocator: Allocator, arguments: []const u8) tool.RunError!OwnedName {
    const parsed = try tool.parseArgs(NameArgs, allocator, arguments, .{});
    defer parsed.deinit();
    const name = std.mem.trim(u8, parsed.value.name, &std.ascii.whitespace);
    if (!isValidName(name)) return error.InvalidToolArguments;
    return .{ .name = try allocator.dupe(u8, name) };
}

fn parseEmptyObject(allocator: Allocator, arguments: []const u8) tool.RunError!void {
    const parsed = try tool.parseArgs(EmptyArgs, allocator, arguments, .{});
    parsed.deinit();
}

fn normalizeNewEntry(entry: NewEntry) error{
    InvalidUserToolName,
    InvalidUserToolDescription,
    InvalidUserToolAction,
}!NewEntry {
    const name = std.mem.trim(u8, entry.name, &std.ascii.whitespace);
    const description = normalizeText(entry.description, max_description_bytes) orelse return error.InvalidUserToolDescription;
    const action = normalizeText(entry.action, max_action_bytes) orelse return error.InvalidUserToolAction;
    if (!isValidName(name) or isReservedName(name)) return error.InvalidUserToolName;
    return .{
        .name = name,
        .description = description,
        .action = action,
    };
}

fn isValidName(name: []const u8) bool {
    if (name.len == 0 or name.len > max_name_bytes) return false;
    for (name) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    }
    return true;
}

fn normalizeText(text: []const u8, max_len: usize) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
    if (trimmed.len == 0 or trimmed.len > max_len) return null;
    if (!text_policy.isSingleLineText(trimmed)) return null;
    return trimmed;
}

fn isReservedName(name: []const u8) bool {
    if (isShellExecName(name)) return true;

    const reserved = [_][]const u8{
        "get_time",
        "get_diagnostics",
        "web_search",
        "memory_store",
        "memory_recall",
        "memory_list",
        "memory_forget",
        "list_dir",
        "read_file",
        "write_file",
        "edit_file",
        "cron_set",
        "cron_list",
        "cron_delete",
        "create_tool",
        "list_user_tools",
        "delete_user_tool",
    };
    for (reserved) |reserved_name| {
        if (std.mem.eql(u8, reserved_name, name)) return true;
    }
    return false;
}

fn isShellExecName(name: []const u8) bool {
    return name.len == "shell".len + 1 + "exec".len and
        std.mem.eql(u8, name[0.."shell".len], "shell") and
        name["shell".len] == '_' and
        std.mem.eql(u8, name["shell".len + 1 ..], "exec");
}

fn containsName(entries: []const Entry, name: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return true;
    }
    return false;
}

fn mapCreateError(err: StoreError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UserToolLimit,
        error.UserToolExists,
        error.InvalidUserToolName,
        error.InvalidUserToolDescription,
        error.InvalidUserToolAction,
        => error.InvalidToolArguments,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
        error.StreamTooLong => error.ToolOutputTooLarge,
        error.InvalidUserToolLine,
        error.StorageFailed,
        => error.ToolFailed,
    };
}

fn mapStateError(err: StoreError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
        error.StreamTooLong => error.ToolOutputTooLarge,
        error.UserToolLimit,
        error.UserToolExists,
        error.InvalidUserToolLine,
        error.InvalidUserToolName,
        error.InvalidUserToolDescription,
        error.InvalidUserToolAction,
        error.StorageFailed,
        => error.ToolFailed,
    };
}

fn macroText(allocator: Allocator, action: []const u8, limit: usize) (Allocator.Error || error{ToolOutputTooLarge})![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try appendLimited(&out, macro_action_prefix, limit);
    try appendLimited(&out, action, limit);
    try appendLimited(&out, macro_action_suffix, limit);
    return out.toOwnedSlice();
}

fn nameResult(allocator: Allocator, prefix: []const u8, name: []const u8, limit: usize) tool.RunError![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    appendLimited(&out, prefix, limit) catch |err| return mapLimitedWriteError(err);
    appendLimited(&out, name, limit) catch |err| return mapLimitedWriteError(err);
    appendLimited(&out, "\n", limit) catch |err| return mapLimitedWriteError(err);
    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn ensureNameResultFits(prefix: []const u8, name: []const u8, limit: usize) error{ToolOutputTooLarge}!void {
    var len = std.math.add(usize, prefix.len, name.len) catch return error.ToolOutputTooLarge;
    len = std.math.add(usize, len, 1) catch return error.ToolOutputTooLarge;
    if (len > limit) return error.ToolOutputTooLarge;
}

fn ensureMacroOutputFits(action: []const u8, limit: usize) error{ToolOutputTooLarge}!void {
    var len = std.math.add(usize, macro_action_prefix.len, action.len) catch return error.ToolOutputTooLarge;
    len = std.math.add(usize, len, macro_action_suffix.len) catch return error.ToolOutputTooLarge;
    if (len > limit) return error.ToolOutputTooLarge;
}

fn appendLimited(out: *Io.Writer.Allocating, bytes: []const u8, limit: usize) (Allocator.Error || error{ToolOutputTooLarge})!void {
    const next_len = std.math.add(usize, out.written().len, bytes.len) catch return error.ToolOutputTooLarge;
    if (next_len > limit) return error.ToolOutputTooLarge;
    out.writer.writeAll(bytes) catch return error.OutOfMemory;
}

fn ensureJsonlFits(out: *Io.Writer.Allocating) error{StreamTooLong}!void {
    if (out.written().len > max_file_bytes) return error.StreamTooLong;
}

const LimitedWriteError = Allocator.Error || error{ToolOutputTooLarge};

fn mapLimitedWriteError(err: LimitedWriteError) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
    };
}

fn lockPath(allocator: Allocator, io: Io, path: []const u8) StoreError!Io.File {
    return state_file.lockPath(allocator, io, path) catch |err| return mapStorageError(err);
}

fn writeAtomic(io: Io, path: []const u8, snapshot: []const u8) StoreError!void {
    state_file.writeAtomic(io, path, snapshot) catch |err| return mapStorageError(err);
}

fn mapReadError(err: anyerror) StoreError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
        else => error.StorageFailed,
    };
}

fn mapStorageError(err: anyerror) StoreError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.StorageFailed,
    };
}

test "macro tools parse serialize and validate entries" {
    var entries = try parseJsonl(
        std.testing.allocator,
        "{\"name\":\" water_plants \",\"description\":\" Water plants \",\"action\":\" Turn relay on, wait, turn off \"}\n",
    );
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expectEqualStrings("water_plants", entries.items[0].name);
    try std.testing.expectEqualStrings("Water plants", entries.items[0].description);
    try std.testing.expectEqualStrings("Turn relay on, wait, turn off", entries.items[0].action);

    const bytes = try buildJsonl(std.testing.allocator, entries.items);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"name\":\"water_plants\"") != null);

    try std.testing.expectError(error.InvalidUserToolLine, parseJsonl(
        std.testing.allocator,
        "{\"name\":\"one\",\"description\":\"One\",\"action\":\"Do one\"}\n{\"name\":\"one\",\"description\":\"Duplicate\",\"action\":\"Do duplicate\"}\n",
    ));
}

test "macro parser preserves allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var entries = try parseJsonl(
                allocator,
                "{\"name\":\"water_plants\",\"description\":\"Water plants\",\"action\":\"Turn relay on\"}\n",
            );
            defer entries.deinit(allocator);
            try std.testing.expectEqualStrings("water_plants", entries.items[0].name);
        }
    }.run, .{});
}

test "macro tools reject invalid and reserved names" {
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"read_file\",\"description\":\"bad\",\"action\":\"bad\"}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"shell_exec\",\"description\":\"bad\",\"action\":\"bad\"}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"bad-name\",\"description\":\"bad\",\"action\":\"bad\"}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"ok\",\"description\":\"\",\"action\":\"bad\"}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"bad_description\",\"description\":\"bad\\u001bdescription\",\"action\":\"bad\"}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"bad_action\",\"description\":\"Bad action\",\"action\":\"line one\\nline two\"}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseCreateArgs(
        std.testing.allocator,
        "{\"name\":\"ok\",\"description\":\"Ok\",\"action\":\"Do it\",\"unknown\":true}",
    ));
    try std.testing.expectError(error.InvalidToolArguments, parseNameArgs(
        std.testing.allocator,
        "{\"name\":\"ok\",\"description\":\"extra\"}",
    ));
}

test "macro serializer rejects invalid domain text" {
    const allocator = std.testing.allocator;
    const name = try allocator.dupe(u8, "bad_action");
    defer allocator.free(name);
    const description = try allocator.dupe(u8, "Bad action");
    defer allocator.free(description);
    var invalid_action = [_]u8{0xff};

    const entries = [_]Entry{.{
        .name = name,
        .description = description,
        .action = invalid_action[0..],
    }};
    try std.testing.expectError(error.InvalidUserToolAction, buildJsonl(allocator, &entries));
}

test "macro serializer rejects snapshots larger than the readable user-tool file limit" {
    const allocator = std.testing.allocator;

    const name = try allocator.alloc(u8, max_name_bytes);
    defer allocator.free(name);
    @memset(name, 'a');

    const description = try allocator.alloc(u8, max_description_bytes);
    defer allocator.free(description);
    @memset(description, 'd');

    const action = try allocator.alloc(u8, max_action_bytes);
    defer allocator.free(action);
    @memset(action, '\\');

    const entries = try allocator.alloc(Entry, 32);
    defer allocator.free(entries);
    for (entries) |*entry| {
        entry.* = .{
            .name = name,
            .description = description,
            .action = action,
        };
    }

    try std.testing.expectError(error.StreamTooLong, buildJsonl(allocator, entries));
}

test "macro tools create list and delete persisted tools" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try create(io, path, std.testing.allocator, .{
        .name = "water_plants",
        .description = "Water plants",
        .action = "Turn relay on, wait, turn off",
    });
    try std.testing.expectError(error.UserToolExists, create(io, path, std.testing.allocator, .{
        .name = "water_plants",
        .description = "Duplicate",
        .action = "Duplicate",
    }));
    try std.testing.expectError(error.InvalidUserToolDescription, create(io, path, std.testing.allocator, .{
        .name = "bad_description",
        .description = "bad\xff",
        .action = "Duplicate",
    }));
    try std.testing.expectError(error.InvalidUserToolAction, create(io, path, std.testing.allocator, .{
        .name = "bad_action",
        .description = "Bad action",
        .action = "bad\xff",
    }));

    const listed = try listText(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "water_plants") != null);

    try std.testing.expect(try delete(io, path, std.testing.allocator, "water_plants"));
    try std.testing.expect(!try delete(io, path, std.testing.allocator, "water_plants"));
}

test "macro create preserves transferred entry ownership on allocation failures" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator, io_arg: Io, tools_path: []const u8) !void {
            Io.Dir.cwd().deleteFile(io_arg, tools_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };

            try create(io_arg, tools_path, allocator, .{
                .name = "water_plants",
                .description = "Water plants",
                .action = "Turn relay on, wait, turn off",
            });

            var entries = try load(allocator, io_arg, tools_path);
            defer entries.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 1), entries.items.len);
            try std.testing.expectEqualStrings("water_plants", entries.items[0].name);
        }
    }.run, .{ io, path });
}

test "macro tools create parent directories for configured state paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try create(io, path, std.testing.allocator, .{
        .name = "water_plants",
        .description = "Water plants",
        .action = "Turn relay on",
    });

    const listed = try listText(std.testing.allocator, io, path, 4096);
    defer std.testing.allocator.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "water_plants") != null);
}

test "macro handlers enforce the configured output cap" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    const action = "Turn relay on, wait, turn off";
    try create(io, path, std.testing.allocator, .{
        .name = "water_plants",
        .description = "Water plants",
        .action = action,
    });

    var client = try Client.init(std.testing.allocator, io, path, macro_action_prefix.len + action.len);
    defer client.deinit(std.testing.allocator);
    const handler = client.dynamicHandler(0);

    try std.testing.expectError(error.ToolOutputTooLarge, handler.run(std.testing.allocator, .{
        .id = "call_1",
        .name = handler.definition.name,
        .arguments = "{}",
    }));
}

test "macro create rejects actions that cannot fit the output cap" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var client = try Client.init(std.testing.allocator, io, path, 80);
    defer client.deinit(std.testing.allocator);
    const args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"name\":\"water_plants\",\"description\":\"Water plants\",\"action\":\"{s}\"}}",
        .{"Turn relay on, wait, turn off"},
    );
    defer std.testing.allocator.free(args);

    try std.testing.expectError(error.ToolOutputTooLarge, client.createHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "create_tool",
        .arguments = args,
    }));

    var entries = try load(std.testing.allocator, io, path);
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), entries.items.len);
}

test "macro mutating handlers check result cap before mutating state" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    const long_name = "abcdefghijklmnopqrstuvwxyabcdefghijklmnopqrstuvw";
    const create_limit = macro_action_prefix.len + "x".len + macro_action_suffix.len;
    var create_client = try Client.init(std.testing.allocator, io, path, create_limit);
    defer create_client.deinit(std.testing.allocator);

    const create_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"name\":\"{s}\",\"description\":\"Tool\",\"action\":\"x\"}}",
        .{long_name},
    );
    defer std.testing.allocator.free(create_args);
    try std.testing.expectError(error.ToolOutputTooLarge, create_client.createHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "create_tool",
        .arguments = create_args,
    }));
    var after_failed_create = try load(std.testing.allocator, io, path);
    defer after_failed_create.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), after_failed_create.items.len);

    try create(io, path, std.testing.allocator, .{
        .name = "water_plants",
        .description = "Water plants",
        .action = "Turn relay on",
    });
    var delete_client = try Client.init(std.testing.allocator, io, path, 1);
    defer delete_client.deinit(std.testing.allocator);
    try std.testing.expectError(error.ToolOutputTooLarge, delete_client.deleteHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "delete_user_tool",
        .arguments = "{\"name\":\"water_plants\"}",
    }));
    var after_failed_delete = try load(std.testing.allocator, io, path);
    defer after_failed_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), after_failed_delete.items.len);
}

test "macro handlers report corrupt store state as tool failure" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var client = try Client.init(std.testing.allocator, io, path, 4096);
    defer client.deinit(std.testing.allocator);
    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = "{\"name\":\"bad-name\",\"description\":\"Bad\",\"action\":\"Bad\"}\n",
    });

    try std.testing.expectError(error.ToolFailed, client.listHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "list_user_tools",
        .arguments = "{}",
    }));
}

test "macro handler verifies persisted state before executing" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/user-tools.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try create(io, path, std.testing.allocator, .{
        .name = "water_plants",
        .description = "Water plants",
        .action = "Turn relay on, wait, turn off",
    });

    var client = try Client.init(std.testing.allocator, io, path, 4096);
    defer client.deinit(std.testing.allocator);
    const handler = client.dynamicHandler(0);

    try std.testing.expect(try delete(io, path, std.testing.allocator, "water_plants"));
    try std.testing.expectError(error.UnknownTool, handler.run(std.testing.allocator, .{
        .id = "call_1",
        .name = handler.definition.name,
        .arguments = "{}",
    }));
}
