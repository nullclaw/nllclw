const std = @import("std");
const chat = @import("../chat.zig");
const scheduler = @import("../scheduler.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const type_parameter = chat.ToolParameter{
    .name = "type",
    .kind = .string,
    .description = "Schedule type: periodic, daily, or once.",
};
const interval_seconds_parameter = chat.ToolParameter{
    .name = "interval_seconds",
    .kind = .integer,
    .description = "Repeat interval for periodic schedules.",
};
const delay_seconds_parameter = chat.ToolParameter{
    .name = "delay_seconds",
    .kind = .integer,
    .description = "Delay before a one-shot schedule fires.",
};
const hour_parameter = chat.ToolParameter{
    .name = "hour",
    .kind = .integer,
    .description = "Daily schedule hour, 0-23, in configured local offset.",
};
const minute_parameter = chat.ToolParameter{
    .name = "minute",
    .kind = .integer,
    .description = "Daily schedule minute, 0-59.",
};
const action_parameter = chat.ToolParameter{
    .name = "action",
    .kind = .string,
    .description = "Prompt to inject into the agent when the schedule fires.",
};
const channel_parameter = chat.ToolParameter{
    .name = "channel",
    .kind = .string,
    .description = "Optional destination channel: local or telegram. Defaults to the current channel.",
};
const chat_id_parameter = chat.ToolParameter{
    .name = "chat_id",
    .kind = .integer,
    .description = "Telegram chat id when channel is telegram.",
};
const id_parameter = chat.ToolParameter{
    .name = "id",
    .kind = .integer,
    .description = "Schedule id.",
};

const set_parameters = [_]chat.ToolParameter{
    type_parameter,
    interval_seconds_parameter,
    delay_seconds_parameter,
    hour_parameter,
    minute_parameter,
    action_parameter,
    channel_parameter,
    chat_id_parameter,
};
const id_parameters = [_]chat.ToolParameter{id_parameter};

pub const set_definition: chat.ToolDefinition = .{
    .name = "cron_set",
    .description = "Create a periodic, daily, or one-shot scheduled agent task.",
    .parameters = .{
        .properties = &set_parameters,
        .required = &.{ "type", "action" },
    },
};

pub const list_definition: chat.ToolDefinition = .{
    .name = "cron_list",
    .description = "List scheduled agent tasks.",
    .parameters = .{ .properties = &.{} },
};

pub const delete_definition: chat.ToolDefinition = .{
    .name = "cron_delete",
    .description = "Delete a scheduled agent task by id.",
    .parameters = .{
        .properties = &id_parameters,
        .required = &.{"id"},
    },
};

pub const Client = struct {
    io: Io,
    path: []const u8,
    output_max_bytes: usize,
    timezone_offset_minutes: i32,
    default_destination: scheduler.Destination,

    pub fn init(
        io: Io,
        path: []const u8,
        output_max_bytes: usize,
        timezone_offset_minutes: i32,
        default_destination: scheduler.Destination,
    ) Client {
        return .{
            .io = io,
            .path = path,
            .output_max_bytes = output_max_bytes,
            .timezone_offset_minutes = timezone_offset_minutes,
            .default_destination = default_destination,
        };
    }

    pub fn setHandler(self: *Client) tool.Handler {
        return .{ .definition = set_definition, .ptr = self, .run_fn = runSet, .mutates_state = true };
    }

    pub fn listHandler(self: *Client) tool.Handler {
        return .{ .definition = list_definition, .ptr = self, .run_fn = runList };
    }

    pub fn deleteHandler(self: *Client) tool.Handler {
        return .{ .definition = delete_definition, .ptr = self, .run_fn = runDelete, .mutates_state = true };
    }

    fn runSet(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        var parsed_entry = try parseSetArgs(allocator, call.arguments, self.default_destination);
        defer parsed_entry.deinit(allocator);
        try ensureCreateResultFits(self.output_max_bytes);

        const created = scheduler.create(
            allocator,
            self.io,
            self.path,
            parsed_entry.entry,
            scheduler.currentUnixSeconds(self.io),
            self.timezone_offset_minutes,
        ) catch |err| return mapSchedulerError(err);
        return boundedPrint(allocator, self.output_max_bytes, "created schedule #{d}, next_run={d}\n", .{ created.id, created.next_run });
    }

    fn runList(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        try parseEmptyObject(allocator, call.arguments);
        return scheduler.listText(allocator, self.io, self.path, self.output_max_bytes) catch |err| return mapSchedulerError(err);
    }

    fn runDelete(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const id = try parseDeleteArgs(allocator, call.arguments);
        try ensureDeleteResultFits(id, self.output_max_bytes);

        const deleted = scheduler.delete(allocator, self.io, self.path, id) catch |err| return mapSchedulerError(err);
        if (deleted) return boundedPrint(allocator, self.output_max_bytes, "deleted schedule #{d}\n", .{id});
        return boundedPrint(allocator, self.output_max_bytes, "not found schedule #{d}\n", .{id});
    }
};

const SetArgs = struct {
    type: []const u8 = "",
    interval_seconds: ?u32 = null,
    delay_seconds: ?u32 = null,
    hour: ?u8 = null,
    minute: ?u8 = null,
    action: []const u8 = "",
    channel: ?[]const u8 = null,
    chat_id: ?i64 = null,
};

const DeleteArgs = struct {
    id: u32 = 0,
};

const EmptyArgs = struct {};

const NewEntryOwned = struct {
    entry: scheduler.NewEntry,
    action: []u8,

    fn deinit(self: *NewEntryOwned, allocator: Allocator) void {
        allocator.free(self.action);
        self.* = undefined;
    }
};

fn parseSetArgs(
    allocator: Allocator,
    arguments: []const u8,
    default_destination: scheduler.Destination,
) tool.RunError!NewEntryOwned {
    const parsed = try tool.parseArgs(SetArgs, allocator, arguments, .{});
    defer parsed.deinit();

    const kind = scheduler.parseKind(parsed.value.type) orelse return error.InvalidToolArguments;
    const action = scheduler.normalizeAction(parsed.value.action) orelse return error.InvalidToolArguments;
    const destination = parseDestination(parsed.value.channel, parsed.value.chat_id, default_destination) orelse return error.InvalidToolArguments;
    if (!timingFieldsMatchKind(parsed.value, kind)) return error.InvalidToolArguments;
    const owned_action = try allocator.dupe(u8, action);
    errdefer allocator.free(owned_action);

    const entry: scheduler.NewEntry = switch (kind) {
        .periodic => .{
            .kind = .periodic,
            .interval_seconds = parsed.value.interval_seconds orelse return error.InvalidToolArguments,
            .action = owned_action,
            .destination = destination,
        },
        .once => .{
            .kind = .once,
            .delay_seconds = parsed.value.delay_seconds orelse return error.InvalidToolArguments,
            .action = owned_action,
            .destination = destination,
        },
        .daily => .{
            .kind = .daily,
            .hour = parsed.value.hour orelse return error.InvalidToolArguments,
            .minute = parsed.value.minute orelse return error.InvalidToolArguments,
            .action = owned_action,
            .destination = destination,
        },
    };
    return .{ .entry = entry, .action = owned_action };
}

fn timingFieldsMatchKind(args: SetArgs, kind: scheduler.Kind) bool {
    return switch (kind) {
        .periodic => args.delay_seconds == null and
            args.hour == null and
            args.minute == null,
        .once => args.interval_seconds == null and
            args.hour == null and
            args.minute == null,
        .daily => args.interval_seconds == null and
            args.delay_seconds == null,
    };
}

fn parseDestination(
    channel: ?[]const u8,
    chat_id: ?i64,
    default_destination: scheduler.Destination,
) ?scheduler.Destination {
    const raw = channel orelse {
        if (chat_id) |requested_id| {
            return switch (default_destination) {
                .telegram => |id| if (requested_id == id) .{ .telegram = id } else null,
                .local => null,
            };
        }
        return default_destination;
    };
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        if (chat_id) |requested_id| {
            return switch (default_destination) {
                .telegram => |id| if (requested_id == id) .{ .telegram = id } else null,
                .local => null,
            };
        }
        return default_destination;
    }
    if (std.mem.eql(u8, trimmed, "local")) return if (chat_id == null) .local else null;
    if (std.mem.eql(u8, trimmed, "telegram")) {
        return switch (default_destination) {
            .telegram => |id| if (chat_id) |requested_id|
                if (requested_id == id) .{ .telegram = id } else null
            else
                .{ .telegram = id },
            .local => null,
        };
    }
    return null;
}

fn parseDeleteArgs(allocator: Allocator, arguments: []const u8) tool.RunError!u32 {
    const parsed = try tool.parseArgs(DeleteArgs, allocator, arguments, .{});
    defer parsed.deinit();
    if (parsed.value.id == 0) return error.InvalidToolArguments;
    return parsed.value.id;
}

fn parseEmptyObject(allocator: Allocator, arguments: []const u8) tool.RunError!void {
    const parsed = try tool.parseArgs(EmptyArgs, allocator, arguments, .{});
    parsed.deinit();
}

fn mapSchedulerError(err: scheduler.Error) tool.RunError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidScheduleLine,
        error.InvalidScheduleKind,
        error.InvalidScheduleAction,
        error.ScheduleFull,
        => error.InvalidToolArguments,
        error.ToolOutputTooLarge => error.ToolOutputTooLarge,
        error.StreamTooLong => error.ToolOutputTooLarge,
        error.StorageFailed => error.ToolFailed,
    };
}

fn boundedPrint(allocator: Allocator, limit: usize, comptime fmt: []const u8, args: anytype) tool.RunError![]u8 {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(text);
    if (text.len > limit) return error.ToolOutputTooLarge;
    return text;
}

fn ensureCreateResultFits(limit: usize) error{ToolOutputTooLarge}!void {
    const max_id: u32 = @intCast(scheduler.max_entries);
    const max_len = std.fmt.count("created schedule #{d}, next_run={d}\n", .{ max_id, std.math.maxInt(i64) });
    if (max_len > limit) return error.ToolOutputTooLarge;
}

fn ensureDeleteResultFits(id: u32, limit: usize) error{ToolOutputTooLarge}!void {
    const deleted_len = std.fmt.count("deleted schedule #{d}\n", .{id});
    const missing_len = std.fmt.count("not found schedule #{d}\n", .{id});
    const max_len = if (deleted_len > missing_len) deleted_len else missing_len;
    if (max_len > limit) return error.ToolOutputTooLarge;
}

test "scheduler tool parses periodic schedule arguments" {
    var entry = try parseSetArgs(std.testing.allocator, "{\"type\":\"periodic\",\"interval_seconds\":300,\"action\":\"check status\"}", .local);
    defer entry.deinit(std.testing.allocator);
    try std.testing.expectEqual(.periodic, entry.entry.kind);
    try std.testing.expectEqual(@as(u32, 300), entry.entry.interval_seconds);
    try std.testing.expectEqualStrings("check status", entry.entry.action);
}

test "scheduler tool defaults and validates schedule destination" {
    var inherited = try parseSetArgs(
        std.testing.allocator,
        "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\"}",
        .{ .telegram = 42 },
    );
    defer inherited.deinit(std.testing.allocator);
    switch (inherited.entry.destination) {
        .telegram => |chat_id| try std.testing.expectEqual(@as(i64, 42), chat_id),
        .local => return error.TestExpectedEqual,
    }

    var explicit = try parseSetArgs(
        std.testing.allocator,
        "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"channel\":\"telegram\",\"chat_id\":42}",
        .{ .telegram = 42 },
    );
    defer explicit.deinit(std.testing.allocator);
    switch (explicit.entry.destination) {
        .telegram => |chat_id| try std.testing.expectEqual(@as(i64, 42), chat_id),
        .local => return error.TestExpectedEqual,
    }

    var explicit_id_without_channel = try parseSetArgs(
        std.testing.allocator,
        "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"chat_id\":42}",
        .{ .telegram = 42 },
    );
    defer explicit_id_without_channel.deinit(std.testing.allocator);
    switch (explicit_id_without_channel.entry.destination) {
        .telegram => |chat_id| try std.testing.expectEqual(@as(i64, 42), chat_id),
        .local => return error.TestExpectedEqual,
    }

    try std.testing.expectError(
        error.InvalidToolArguments,
        parseSetArgs(
            std.testing.allocator,
            "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"channel\":\"telegram\",\"chat_id\":99}",
            .{ .telegram = 42 },
        ),
    );
    try std.testing.expectError(
        error.InvalidToolArguments,
        parseSetArgs(
            std.testing.allocator,
            "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"channel\":\"telegram\",\"chat_id\":99}",
            .local,
        ),
    );
    try std.testing.expectError(
        error.InvalidToolArguments,
        parseSetArgs(
            std.testing.allocator,
            "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"chat_id\":99}",
            .{ .telegram = 42 },
        ),
    );
    try std.testing.expectError(
        error.InvalidToolArguments,
        parseSetArgs(
            std.testing.allocator,
            "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"chat_id\":42}",
            .local,
        ),
    );
    try std.testing.expectError(
        error.InvalidToolArguments,
        parseSetArgs(
            std.testing.allocator,
            "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"ping\",\"channel\":\"local\",\"chat_id\":42}",
            .{ .telegram = 42 },
        ),
    );
}

test "scheduler tool parses once and daily arguments and rejects bad inputs" {
    var once = try parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":120,\"action\":\" run \"}", .local);
    defer once.deinit(std.testing.allocator);
    try std.testing.expectEqual(.once, once.entry.kind);
    try std.testing.expectEqual(@as(u32, 120), once.entry.delay_seconds);
    try std.testing.expectEqualStrings("run", once.entry.action);

    var daily = try parseSetArgs(std.testing.allocator, "{\"type\":\"daily\",\"hour\":9,\"minute\":30,\"action\":\"daily\"}", .local);
    defer daily.deinit(std.testing.allocator);
    try std.testing.expectEqual(.daily, daily.entry.kind);
    try std.testing.expectEqual(@as(u8, 9), daily.entry.hour);
    try std.testing.expectEqual(@as(u8, 30), daily.entry.minute);

    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"periodic\",\"action\":\"missing interval\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"periodic\",\"interval_seconds\":60,\"delay_seconds\":1,\"action\":\"extra delay\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"   \"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"line one\\nline two\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"bad\\u001bvalue\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":1,\"interval_seconds\":60,\"action\":\"extra interval\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"daily\",\"hour\":9,\"action\":\"missing minute\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"daily\",\"hour\":9,\"minute\":30,\"delay_seconds\":1,\"action\":\"extra delay\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"x\",\"unknown\":true}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, "{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"x\",\"channel\":\"telegram\"}", .local));
    try std.testing.expectError(error.InvalidToolArguments, parseDeleteArgs(std.testing.allocator, "{\"id\":0}"));
    try std.testing.expectError(error.InvalidToolArguments, parseDeleteArgs(std.testing.allocator, "{\"id\":1,\"unknown\":true}"));
    try std.testing.expectError(error.InvalidToolArguments, parseEmptyObject(std.testing.allocator, "[]"));

    const long_action = try std.testing.allocator.alloc(u8, scheduler.max_action_bytes + 1);
    defer std.testing.allocator.free(long_action);
    @memset(long_action, 'x');
    const long_args = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"type\":\"once\",\"delay_seconds\":1,\"action\":\"{s}\"}}",
        .{long_action},
    );
    defer std.testing.allocator.free(long_args);
    try std.testing.expectError(error.InvalidToolArguments, parseSetArgs(std.testing.allocator, long_args, .local));
}

test "scheduler tool creates lists and deletes schedules" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var client = Client.init(io, path, 4096, 0, .local);
    const created = try client.setHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "cron_set",
        .arguments = "{\"type\":\"once\",\"delay_seconds\":10,\"action\":\"ping\"}",
    });
    defer std.testing.allocator.free(created);
    try std.testing.expect(std.mem.indexOf(u8, created, "created schedule #1") != null);

    const listed = try client.listHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "cron_list",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(listed);
    try std.testing.expect(std.mem.indexOf(u8, listed, "ping") != null);

    const deleted = try client.deleteHandler().run(std.testing.allocator, .{
        .id = "call_3",
        .name = "cron_delete",
        .arguments = "{\"id\":1}",
    });
    defer std.testing.allocator.free(deleted);
    try std.testing.expectEqualStrings("deleted schedule #1\n", deleted);
}

test "scheduler mutating tools check result cap before mutating state" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    var create_client = Client.init(io, path, 1, 0, .local);
    try std.testing.expectError(error.ToolOutputTooLarge, create_client.setHandler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "cron_set",
        .arguments = "{\"type\":\"once\",\"delay_seconds\":10,\"action\":\"ping\"}",
    }));
    var after_failed_create = try scheduler.load(std.testing.allocator, io, path);
    defer after_failed_create.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), after_failed_create.items.len);

    _ = try scheduler.create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 10,
        .action = "ping",
    }, 100, 0);

    var delete_client = Client.init(io, path, 1, 0, .local);
    try std.testing.expectError(error.ToolOutputTooLarge, delete_client.deleteHandler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "cron_delete",
        .arguments = "{\"id\":1}",
    }));
    var after_failed_delete = try scheduler.load(std.testing.allocator, io, path);
    defer after_failed_delete.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), after_failed_delete.items.len);
}
