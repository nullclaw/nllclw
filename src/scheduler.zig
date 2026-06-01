const std = @import("std");
const builtin = @import("builtin");
const state_file = @import("./adapters/state_file.zig");
const text_policy = @import("./text_policy.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const max_file_bytes = 128 * 1024;
pub const max_entries: usize = 64;
pub const max_action_bytes: usize = 2048;
pub const default_lease_seconds: u32 = 15 * 60;

const seconds_per_day: i64 = 24 * 60 * 60;
const max_periodic_interval_seconds: u32 = 7 * 86_400;
const max_once_delay_seconds: u32 = 365 * 86_400;

pub const Error = Allocator.Error || error{
    InvalidScheduleLine,
    InvalidScheduleKind,
    InvalidScheduleAction,
    ScheduleFull,
    StorageFailed,
    StreamTooLong,
    ToolOutputTooLarge,
};

pub const Kind = enum {
    periodic,
    once,
    daily,
};

pub const Destination = union(enum) {
    local,
    telegram: i64,
};

pub const Entry = struct {
    id: u32,
    kind: Kind,
    interval_seconds: u32 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    action: []const u8,
    destination: Destination = .local,
    next_run: i64,
    claimed_until: i64 = 0,
};

pub const NewEntry = struct {
    kind: Kind,
    interval_seconds: u32 = 0,
    delay_seconds: u32 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    action: []const u8,
    destination: Destination = .local,
};

pub const Created = struct {
    id: u32,
    next_run: i64,
};

pub const Entries = struct {
    items: []Entry = &.{},

    pub fn deinit(self: *Entries, allocator: Allocator) void {
        for (self.items) |entry| allocator.free(entry.action);
        allocator.free(self.items);
        self.* = .{};
    }
};

pub const DueTask = struct {
    id: u32,
    action: []u8,
    destination: Destination = .local,
    lease_until: i64 = 0,
};

pub const DueTasks = struct {
    items: []DueTask = &.{},

    pub fn deinit(self: *DueTasks, allocator: Allocator) void {
        freeDueTaskSlice(allocator, self.items);
        self.* = .{};
    }
};

const ParsedEntry = struct {
    id: u32 = 0,
    kind: []const u8 = "",
    interval_seconds: u32 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    action: []const u8 = "",
    channel: []const u8 = "local",
    chat_id: ?i64 = null,
    next_run: i64 = 0,
    claimed_until: i64 = 0,
};

pub fn load(allocator: Allocator, io: Io, path: []const u8) Error!Entries {
    const bytes = (state_file.readAlloc(allocator, io, path, max_file_bytes) catch |err| return mapReadError(err)) orelse return .{};
    defer allocator.free(bytes);
    return parseJsonl(allocator, bytes);
}

pub fn create(
    allocator: Allocator,
    io: Io,
    path: []const u8,
    new_entry: NewEntry,
    now: i64,
    timezone_offset_minutes: i32,
) Error!Created {
    const action_text = try validateNewEntry(new_entry);

    var lock_file = try lockSchedule(allocator, io, path);
    defer lock_file.close(io);

    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);
    if (entries.items.len >= max_entries) return error.ScheduleFull;

    var list: std.ArrayList(Entry) = .empty;
    defer list.deinit(allocator);
    try list.appendSlice(allocator, entries.items);

    const id = nextId(entries.items) orelse return error.ScheduleFull;
    const next_run = try computeNextRun(new_entry, now, timezone_offset_minutes);
    if (next_run <= 0) return error.InvalidScheduleLine;
    var action: ?[]u8 = try allocator.dupe(u8, action_text);
    errdefer if (action) |bytes| allocator.free(bytes);

    try list.append(allocator, .{
        .id = id,
        .kind = new_entry.kind,
        .interval_seconds = new_entry.interval_seconds,
        .hour = new_entry.hour,
        .minute = new_entry.minute,
        .action = action.?,
        .destination = new_entry.destination,
        .next_run = next_run,
        .claimed_until = 0,
    });
    action = null;
    errdefer {
        if (list.pop()) |removed| allocator.free(removed.action);
    }

    try saveEntries(allocator, io, path, list.items);
    if (list.pop()) |removed| allocator.free(removed.action);
    return .{ .id = id, .next_run = next_run };
}

pub fn delete(allocator: Allocator, io: Io, path: []const u8, id: u32) Error!bool {
    var lock_file = try lockSchedule(allocator, io, path);
    defer lock_file.close(io);

    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var kept: std.ArrayList(Entry) = .empty;
    defer kept.deinit(allocator);
    var deleted = false;
    for (entries.items) |entry| {
        if (entry.id == id) {
            deleted = true;
        } else {
            try kept.append(allocator, entry);
        }
    }
    if (!deleted) return false;

    try saveEntries(allocator, io, path, kept.items);
    return true;
}

pub fn listText(allocator: Allocator, io: Io, path: []const u8, limit: usize) Error![]u8 {
    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try appendLimited(&out, "schedules:\n", limit);
    for (entries.items) |entry| {
        const line = try formatEntry(allocator, entry);
        defer allocator.free(line);
        try appendLimited(&out, line, limit);
    }
    return out.toOwnedSlice();
}

pub fn peekDue(allocator: Allocator, io: Io, path: []const u8, now: i64) Error!DueTasks {
    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var due: std.ArrayList(DueTask) = .empty;
    errdefer {
        for (due.items) |task| allocator.free(task.action);
        due.deinit(allocator);
    }

    for (entries.items) |entry| {
        if (!isDue(entry, now)) continue;
        try appendDueTask(allocator, &due, entry, 0);
    }

    return .{ .items = try due.toOwnedSlice(allocator) };
}

pub fn claimDue(allocator: Allocator, io: Io, path: []const u8, now: i64, lease_seconds: u32) Error!DueTasks {
    if (lease_seconds == 0) return error.InvalidScheduleLine;

    var lock_file = try lockSchedule(allocator, io, path);
    defer lock_file.close(io);

    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var due: std.ArrayList(DueTask) = .empty;
    errdefer {
        for (due.items) |task| allocator.free(task.action);
        due.deinit(allocator);
    }

    var changed = false;
    const lease_until = addSeconds(now, @intCast(lease_seconds)) catch return error.InvalidScheduleLine;
    for (entries.items) |*entry| {
        if (!isDue(entry.*, now)) continue;
        entry.claimed_until = lease_until;
        changed = true;
        try appendDueTask(allocator, &due, entry.*, lease_until);
    }

    const items = try due.toOwnedSlice(allocator);
    errdefer freeDueTaskSlice(allocator, items);
    if (changed) try saveEntries(allocator, io, path, entries.items);
    return .{ .items = items };
}

pub fn commitDue(allocator: Allocator, io: Io, path: []const u8, id: u32, lease_until: i64, now: i64) Error!bool {
    var lock_file = try lockSchedule(allocator, io, path);
    defer lock_file.close(io);

    var entries = try load(allocator, io, path);
    defer entries.deinit(allocator);

    var kept: std.ArrayList(Entry) = .empty;
    defer kept.deinit(allocator);
    var committed = false;

    for (entries.items) |*entry| {
        if (entry.id == id and entry.claimed_until == lease_until) {
            committed = true;
            switch (entry.kind) {
                .once => continue,
                .periodic, .daily => {
                    try advanceEntry(entry, now);
                    try kept.append(allocator, entry.*);
                },
            }
        } else {
            try kept.append(allocator, entry.*);
        }
    }

    if (!committed) return false;
    try saveEntries(allocator, io, path, kept.items);
    return true;
}

pub fn parseJsonl(allocator: Allocator, bytes: []const u8) Error!Entries {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |entry| allocator.free(entry.action);
        entries.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (entries.items.len >= max_entries) return error.ScheduleFull;

        const parsed = std.json.parseFromSlice(ParsedEntry, allocator, line, .{
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidScheduleLine,
        };
        defer parsed.deinit();

        const kind = parseKind(parsed.value.kind) orelse return error.InvalidScheduleKind;
        if (parsed.value.id == 0) return error.InvalidScheduleLine;
        if (containsId(entries.items, parsed.value.id)) return error.InvalidScheduleLine;
        const action_text = normalizeAction(parsed.value.action) orelse return error.InvalidScheduleAction;
        const destination = parseDestination(parsed.value.channel, parsed.value.chat_id) orelse return error.InvalidScheduleLine;
        try validateDestination(destination);
        try validatePersistedTiming(kind, parsed.value.interval_seconds, parsed.value.hour, parsed.value.minute);
        if (parsed.value.next_run <= 0) return error.InvalidScheduleLine;
        if (parsed.value.claimed_until < 0) return error.InvalidScheduleLine;

        const action = try allocator.dupe(u8, action_text);
        errdefer allocator.free(action);
        try entries.append(allocator, .{
            .id = parsed.value.id,
            .kind = kind,
            .interval_seconds = parsed.value.interval_seconds,
            .hour = parsed.value.hour,
            .minute = parsed.value.minute,
            .action = action,
            .destination = destination,
            .next_run = parsed.value.next_run,
            .claimed_until = parsed.value.claimed_until,
        });
    }

    return .{ .items = try entries.toOwnedSlice(allocator) };
}

fn appendDueTask(
    allocator: Allocator,
    due: *std.ArrayList(DueTask),
    entry: Entry,
    lease_until: i64,
) Allocator.Error!void {
    const action = try allocator.dupe(u8, entry.action);
    errdefer allocator.free(action);
    try due.append(allocator, .{
        .id = entry.id,
        .action = action,
        .destination = entry.destination,
        .lease_until = lease_until,
    });
}

fn freeDueTaskSlice(allocator: Allocator, tasks: []DueTask) void {
    for (tasks) |task| allocator.free(task.action);
    allocator.free(tasks);
}

pub fn saveEntries(allocator: Allocator, io: Io, path: []const u8, entries: []const Entry) Error!void {
    const bytes = try buildJsonl(allocator, entries);
    defer allocator.free(bytes);
    try writeAtomic(io, path, bytes);
}

pub fn buildJsonl(allocator: Allocator, entries: []const Entry) Error![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    for (entries) |entry| {
        try writeEntry(&out.writer, entry);
        try ensureJsonlFits(&out);
    }
    return out.toOwnedSlice();
}

pub fn currentUnixSeconds(io: Io) i64 {
    return Io.Timestamp.now(io, .real).toSeconds();
}

pub fn parseKind(value: []const u8) ?Kind {
    if (std.mem.eql(u8, value, "periodic")) return .periodic;
    if (std.mem.eql(u8, value, "once")) return .once;
    if (std.mem.eql(u8, value, "daily")) return .daily;
    return null;
}

pub fn formatKind(kind: Kind) []const u8 {
    return @tagName(kind);
}

fn validateNewEntry(entry: NewEntry) error{ InvalidScheduleAction, InvalidScheduleLine }![]const u8 {
    const action = normalizeAction(entry.action) orelse return error.InvalidScheduleAction;
    try validateDestination(entry.destination);
    try validateNewEntryTiming(entry);
    return action;
}

fn validatePersistedTiming(kind: Kind, interval_seconds: u32, hour: u8, minute: u8) error{InvalidScheduleLine}!void {
    switch (kind) {
        .periodic => {
            if (hour != 0 or minute != 0) return error.InvalidScheduleLine;
            try validatePeriodicInterval(interval_seconds);
        },
        .once => {
            if (interval_seconds != 0 or hour != 0 or minute != 0) return error.InvalidScheduleLine;
        },
        .daily => {
            if (interval_seconds != 0) return error.InvalidScheduleLine;
            try validateDailyTime(hour, minute);
        },
    }
}

fn validateNewEntryTiming(entry: NewEntry) error{InvalidScheduleLine}!void {
    switch (entry.kind) {
        .periodic => {
            if (entry.delay_seconds != 0 or entry.hour != 0 or entry.minute != 0) return error.InvalidScheduleLine;
            try validatePeriodicInterval(entry.interval_seconds);
        },
        .once => {
            if (entry.interval_seconds != 0 or entry.hour != 0 or entry.minute != 0) return error.InvalidScheduleLine;
            try validateOnceDelay(entry.delay_seconds);
        },
        .daily => {
            if (entry.interval_seconds != 0 or entry.delay_seconds != 0) return error.InvalidScheduleLine;
            try validateDailyTime(entry.hour, entry.minute);
        },
    }
}

fn validatePeriodicInterval(seconds: u32) error{InvalidScheduleLine}!void {
    if (seconds == 0 or seconds > max_periodic_interval_seconds) return error.InvalidScheduleLine;
}

fn validateOnceDelay(seconds: u32) error{InvalidScheduleLine}!void {
    if (seconds == 0 or seconds > max_once_delay_seconds) return error.InvalidScheduleLine;
}

fn validateDailyTime(hour: u8, minute: u8) error{InvalidScheduleLine}!void {
    if (hour > 23 or minute > 59) return error.InvalidScheduleLine;
}

fn validateDestination(destination: Destination) error{InvalidScheduleLine}!void {
    switch (destination) {
        .local => {},
        .telegram => |chat_id| if (chat_id == 0) return error.InvalidScheduleLine,
    }
}

fn validateSerializableEntry(entry: Entry) error{ InvalidScheduleLine, InvalidScheduleAction }![]const u8 {
    if (entry.id == 0) return error.InvalidScheduleLine;
    const action = normalizeAction(entry.action) orelse return error.InvalidScheduleAction;
    try validateDestination(entry.destination);
    try validatePersistedTiming(entry.kind, entry.interval_seconds, entry.hour, entry.minute);
    if (entry.next_run <= 0) return error.InvalidScheduleLine;
    if (entry.claimed_until < 0) return error.InvalidScheduleLine;
    return action;
}

fn computeNextRun(entry: NewEntry, now: i64, timezone_offset_minutes: i32) error{InvalidScheduleLine}!i64 {
    return switch (entry.kind) {
        .periodic => addSeconds(now, @intCast(entry.interval_seconds)) catch error.InvalidScheduleLine,
        .once => addSeconds(now, @intCast(entry.delay_seconds)) catch error.InvalidScheduleLine,
        .daily => try nextDailyRun(now, timezone_offset_minutes, entry.hour, entry.minute),
    };
}

fn nextDailyRun(now: i64, timezone_offset_minutes: i32, hour: u8, minute: u8) error{InvalidScheduleLine}!i64 {
    const offset_seconds = @as(i64, timezone_offset_minutes) * 60;
    const local_now = addSeconds(now, offset_seconds) catch return error.InvalidScheduleLine;
    const local_day = @divFloor(local_now, seconds_per_day);
    const target_seconds = @as(i64, hour) * 60 * 60 + @as(i64, minute) * 60;
    const local_day_start = std.math.mul(i64, local_day, seconds_per_day) catch return error.InvalidScheduleLine;
    var target_local = addSeconds(local_day_start, target_seconds) catch return error.InvalidScheduleLine;
    if (target_local <= local_now) target_local = addSeconds(target_local, seconds_per_day) catch return error.InvalidScheduleLine;
    return std.math.sub(i64, target_local, offset_seconds) catch error.InvalidScheduleLine;
}

fn nextId(entries: []const Entry) ?u32 {
    var id: u32 = 1;
    while (id <= max_entries) : (id += 1) {
        if (!containsId(entries, id)) return id;
    }
    return null;
}

fn containsId(entries: []const Entry, id: u32) bool {
    for (entries) |entry| {
        if (entry.id == id) return true;
    }
    return false;
}

fn advanceEntry(entry: *Entry, now: i64) error{InvalidScheduleLine}!void {
    switch (entry.kind) {
        .once => {},
        .periodic => try advanceByInterval(entry, now, @intCast(entry.interval_seconds)),
        .daily => try advanceByInterval(entry, now, seconds_per_day),
    }
    entry.claimed_until = 0;
}

fn advanceByInterval(entry: *Entry, now: i64, interval: i64) error{InvalidScheduleLine}!void {
    if (interval <= 0) return error.InvalidScheduleLine;
    if (entry.next_run > now) return;

    const elapsed = std.math.sub(i64, now, entry.next_run) catch return error.InvalidScheduleLine;
    const missed = @divFloor(elapsed, interval) + 1;
    const delta = std.math.mul(i64, missed, interval) catch return error.InvalidScheduleLine;
    entry.next_run = addSeconds(entry.next_run, delta) catch return error.InvalidScheduleLine;
}

fn addSeconds(base: i64, delta: i64) error{Overflow}!i64 {
    return std.math.add(i64, base, delta) catch error.Overflow;
}

fn isDue(entry: Entry, now: i64) bool {
    return entry.next_run <= now and entry.claimed_until <= now;
}

pub fn normalizeAction(action: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, action, &std.ascii.whitespace);
    if (trimmed.len == 0 or trimmed.len > max_action_bytes) return null;
    if (!text_policy.isSingleLineText(trimmed)) return null;
    return trimmed;
}

fn formatEntry(allocator: Allocator, entry: Entry) Allocator.Error![]u8 {
    const destination = formatDestination(entry.destination);
    return switch (entry.kind) {
        .periodic => std.fmt.allocPrint(
            allocator,
            "- #{d} periodic every {d}s next {d} [{s}]: {s}\n",
            .{ entry.id, entry.interval_seconds, entry.next_run, destination, entry.action },
        ),
        .once => std.fmt.allocPrint(
            allocator,
            "- #{d} once next {d} [{s}]: {s}\n",
            .{ entry.id, entry.next_run, destination, entry.action },
        ),
        .daily => std.fmt.allocPrint(
            allocator,
            "- #{d} daily {d:0>2}:{d:0>2} next {d} [{s}]: {s}\n",
            .{ entry.id, entry.hour, entry.minute, entry.next_run, destination, entry.action },
        ),
    };
}

fn formatDestination(destination: Destination) []const u8 {
    return switch (destination) {
        .local => "local",
        .telegram => "telegram",
    };
}

fn parseDestination(channel: []const u8, chat_id: ?i64) ?Destination {
    const trimmed_channel = std.mem.trim(u8, channel, &std.ascii.whitespace);
    if (trimmed_channel.len == 0 or std.mem.eql(u8, trimmed_channel, "local")) {
        if (chat_id != null) return null;
        return .local;
    }
    if (std.mem.eql(u8, trimmed_channel, "telegram")) {
        return .{ .telegram = chat_id orelse return null };
    }
    return null;
}

fn writeEntry(writer: *Io.Writer, entry: Entry) Error!void {
    const action = try validateSerializableEntry(entry);
    var json: std.json.Stringify = .{
        .writer = writer,
        .options = .{},
    };
    json.beginObject() catch return error.OutOfMemory;
    json.objectField("id") catch return error.OutOfMemory;
    json.write(entry.id) catch return error.OutOfMemory;
    json.objectField("kind") catch return error.OutOfMemory;
    json.write(formatKind(entry.kind)) catch return error.OutOfMemory;
    json.objectField("interval_seconds") catch return error.OutOfMemory;
    json.write(entry.interval_seconds) catch return error.OutOfMemory;
    json.objectField("hour") catch return error.OutOfMemory;
    json.write(entry.hour) catch return error.OutOfMemory;
    json.objectField("minute") catch return error.OutOfMemory;
    json.write(entry.minute) catch return error.OutOfMemory;
    json.objectField("action") catch return error.OutOfMemory;
    json.write(action) catch return error.OutOfMemory;
    json.objectField("channel") catch return error.OutOfMemory;
    switch (entry.destination) {
        .local => json.write("local") catch return error.OutOfMemory,
        .telegram => |chat_id| {
            json.write("telegram") catch return error.OutOfMemory;
            json.objectField("chat_id") catch return error.OutOfMemory;
            json.write(chat_id) catch return error.OutOfMemory;
        },
    }
    json.objectField("next_run") catch return error.OutOfMemory;
    json.write(entry.next_run) catch return error.OutOfMemory;
    json.objectField("claimed_until") catch return error.OutOfMemory;
    json.write(entry.claimed_until) catch return error.OutOfMemory;
    json.endObject() catch return error.OutOfMemory;
    writer.writeByte('\n') catch return error.OutOfMemory;
}

fn appendLimited(out: *Io.Writer.Allocating, bytes: []const u8, limit: usize) (Allocator.Error || error{ToolOutputTooLarge})!void {
    const next_len = std.math.add(usize, out.written().len, bytes.len) catch return error.ToolOutputTooLarge;
    if (next_len > limit) return error.ToolOutputTooLarge;
    out.writer.writeAll(bytes) catch return error.OutOfMemory;
}

fn ensureJsonlFits(out: *Io.Writer.Allocating) error{StreamTooLong}!void {
    if (out.written().len > max_file_bytes) return error.StreamTooLong;
}

fn lockSchedule(allocator: Allocator, io: Io, path: []const u8) Error!Io.File {
    return state_file.lockPath(allocator, io, path) catch |err| return mapStorageError(err);
}

fn writeAtomic(io: Io, path: []const u8, snapshot: []const u8) Error!void {
    state_file.writeAtomic(io, path, snapshot) catch |err| return mapStorageError(err);
}

fn mapReadError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
        else => error.StorageFailed,
    };
}

fn mapStorageError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.StorageFailed,
    };
}

const DueSliceFailAllocator = if (builtin.is_test) struct {
    backing: Allocator,

    fn init(backing: Allocator) DueSliceFailAllocator {
        return .{ .backing = backing };
    }

    fn allocator(self: *DueSliceFailAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn shouldFail(len: usize, alignment: std.mem.Alignment) bool {
        return len == @sizeOf(DueTask) and alignment.toByteUnits() == @alignOf(DueTask);
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        if (shouldFail(len, alignment)) return null;
        const self: *DueSliceFailAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawAlloc(len, alignment, return_address);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
        const self: *DueSliceFailAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawResize(memory, alignment, new_len, return_address);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        if (shouldFail(new_len, alignment)) return null;
        const self: *DueSliceFailAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawRemap(memory, alignment, new_len, return_address);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const self: *DueSliceFailAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(memory, alignment, return_address);
    }
} else void;

test "scheduler parses and serializes entries" {
    var entries = try parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"periodic\",\"interval_seconds\":60,\"action\":\" ping \",\"next_run\":100}\n",
    );
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expectEqual(.periodic, entries.items[0].kind);
    try std.testing.expectEqualStrings("ping", entries.items[0].action);

    const bytes = try buildJsonl(std.testing.allocator, entries.items);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"periodic\"") != null);
}

test "scheduler preserves telegram destinations" {
    var entries = try parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"ping\",\"channel\":\"telegram\",\"chat_id\":42,\"next_run\":100}\n",
    );
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(.once, entries.items[0].kind);
    switch (entries.items[0].destination) {
        .telegram => |chat_id| try std.testing.expectEqual(@as(i64, 42), chat_id),
        .local => return error.TestExpectedEqual,
    }

    const bytes = try buildJsonl(std.testing.allocator, entries.items);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"channel\":\"telegram\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"chat_id\":42") != null);
}

test "scheduler advances due periodic and removes one-shot entries" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    _ = try create(std.testing.allocator, io, path, .{
        .kind = .periodic,
        .interval_seconds = 10,
        .action = " tick ",
    }, 100, 0);
    _ = try create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 5,
        .action = "once",
    }, 100, 0);

    var due = try claimDue(std.testing.allocator, io, path, 110, 30);
    defer due.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), due.items.len);
    try std.testing.expectEqualStrings("tick", due.items[0].action);
    for (due.items) |task| {
        try std.testing.expect(try commitDue(std.testing.allocator, io, path, task.id, task.lease_until, 110));
    }

    var entries = try load(std.testing.allocator, io, path);
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expectEqual(.periodic, entries.items[0].kind);
    try std.testing.expectEqualStrings("tick", entries.items[0].action);
    try std.testing.expect(entries.items[0].next_run > 110);
}

test "scheduler creates parent directories for configured state paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/state/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    _ = try create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 5,
        .action = "once",
    }, 100, 0);

    var entries = try load(std.testing.allocator, io, path);
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
}

test "scheduler peek requires explicit successful commit" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    _ = try create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 5,
        .action = "once",
    }, 100, 0);

    var due = try peekDue(std.testing.allocator, io, path, 110);
    defer due.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), due.items.len);

    var before_commit = try load(std.testing.allocator, io, path);
    defer before_commit.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), before_commit.items.len);

    var claimed = try claimDue(std.testing.allocator, io, path, 110, default_lease_seconds);
    defer claimed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), claimed.items.len);

    var after_claim = try load(std.testing.allocator, io, path);
    defer after_claim.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), after_claim.items.len);
    try std.testing.expect(after_claim.items[0].claimed_until > 110);

    var during_lease = try peekDue(std.testing.allocator, io, path, 111);
    defer during_lease.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), during_lease.items.len);

    try std.testing.expect(try commitDue(
        std.testing.allocator,
        io,
        path,
        claimed.items[0].id,
        claimed.items[0].lease_until,
        110,
    ));

    var after_commit = try load(std.testing.allocator, io, path);
    defer after_commit.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), after_commit.items.len);
}

test "scheduler rejects invalid persisted and new entries" {
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":0,\"kind\":\"once\",\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleKind, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"weird\",\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleAction, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"periodic\",\"interval_seconds\":0,\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"periodic\",\"interval_seconds\":60,\"minute\":1,\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"periodic\",\"interval_seconds\":604801,\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"daily\",\"hour\":24,\"minute\":0,\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"daily\",\"interval_seconds\":60,\"hour\":9,\"minute\":0,\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"next_run\":0}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"interval_seconds\":60,\"action\":\"x\",\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"next_run\":1}\n{\"id\":1,\"kind\":\"once\",\"action\":\"y\",\"next_run\":2}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"next_run\":1,\"claimed_until\":-1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"channel\":\"telegram\",\"chat_id\":0,\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"channel\":\"local\",\"chat_id\":42,\"next_run\":1}\n",
    ));
    try std.testing.expectError(error.InvalidScheduleLine, parseJsonl(
        std.testing.allocator,
        "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"chat_id\":42,\"next_run\":1}\n",
    ));

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .periodic,
        .interval_seconds = 0,
        .action = "tick",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .periodic,
        .interval_seconds = 60,
        .delay_seconds = 1,
        .action = "tick",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 0,
        .action = "once",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .interval_seconds = 60,
        .delay_seconds = 1,
        .action = "once",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .daily,
        .hour = 24,
        .minute = 0,
        .action = "daily",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .daily,
        .delay_seconds = 1,
        .hour = 9,
        .minute = 0,
        .action = "daily",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleAction, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 1,
        .action = "\x00",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleAction, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 1,
        .action = "bad\nvalue",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleAction, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 1,
        .action = "bad\xff",
    }, 100, 0));
    try std.testing.expectError(error.InvalidScheduleLine, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 1,
        .action = "once",
    }, -2, 0));
}

test "scheduler serializer rejects invalid domain text" {
    const bad_action = [_]Entry{.{
        .id = 1,
        .kind = .once,
        .action = "bad\xff",
        .next_run = 1,
    }};
    try std.testing.expectError(error.InvalidScheduleAction, buildJsonl(std.testing.allocator, &bad_action));

    const bad_destination = [_]Entry{.{
        .id = 1,
        .kind = .once,
        .action = "ok",
        .destination = .{ .telegram = 0 },
        .next_run = 1,
    }};
    try std.testing.expectError(error.InvalidScheduleLine, buildJsonl(std.testing.allocator, &bad_destination));

    const bad_control = [_]Entry{.{
        .id = 1,
        .kind = .once,
        .action = "bad\x1bvalue",
        .next_run = 1,
    }};
    try std.testing.expectError(error.InvalidScheduleAction, buildJsonl(std.testing.allocator, &bad_control));

    const bad_kind_fields = [_]Entry{.{
        .id = 1,
        .kind = .once,
        .interval_seconds = 60,
        .action = "ok",
        .next_run = 1,
    }};
    try std.testing.expectError(error.InvalidScheduleLine, buildJsonl(std.testing.allocator, &bad_kind_fields));
}

test "scheduler serializer rejects snapshots larger than the readable schedule file limit" {
    const allocator = std.testing.allocator;

    const action = try allocator.alloc(u8, max_action_bytes);
    defer allocator.free(action);
    @memset(action, 'x');

    const entries = try allocator.alloc(Entry, max_entries);
    defer allocator.free(entries);
    for (entries, 0..) |*entry, index| {
        entry.* = .{
            .id = @intCast(index + 1),
            .kind = .once,
            .action = action,
            .next_run = 1,
        };
    }

    try std.testing.expectError(error.StreamTooLong, buildJsonl(allocator, entries));
}

test "scheduler create cleans up transferred action when save fails" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    const existing_action = try std.testing.allocator.alloc(u8, 1950);
    defer std.testing.allocator.free(existing_action);
    @memset(existing_action, 'x');

    const entries = try std.testing.allocator.alloc(Entry, max_entries - 1);
    defer std.testing.allocator.free(entries);
    for (entries, 0..) |*entry, index| {
        entry.* = .{
            .id = @intCast(index + 1),
            .kind = .once,
            .action = existing_action,
            .next_run = 1,
        };
    }

    const snapshot = try buildJsonl(std.testing.allocator, entries);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(snapshot.len < max_file_bytes);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = snapshot });

    const new_action = try std.testing.allocator.alloc(u8, max_action_bytes);
    defer std.testing.allocator.free(new_action);
    @memset(new_action, 'y');

    try std.testing.expectError(error.StreamTooLong, create(std.testing.allocator, io, path, .{
        .kind = .once,
        .delay_seconds = 1,
        .action = new_action,
    }, 1, 0));

    var loaded = try load(std.testing.allocator, io, path);
    defer loaded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, max_entries - 1), loaded.items.len);
}

test "scheduler parser preserves allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var entries = try parseJsonl(allocator, "{\"id\":1,\"kind\":\"once\",\"action\":\"x\",\"next_run\":1}\n");
            defer entries.deinit(allocator);
            try std.testing.expectEqual(@as(u32, 1), entries.items[0].id);
        }
    }.run, .{});
}

test "scheduler due task append cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var due: std.ArrayList(DueTask) = .empty;
            defer {
                for (due.items) |task| allocator.free(task.action);
                due.deinit(allocator);
            }

            try appendDueTask(allocator, &due, .{
                .id = 1,
                .kind = .once,
                .action = "tick",
                .next_run = 1,
            }, 99);
            try std.testing.expectEqual(@as(usize, 1), due.items.len);
            try std.testing.expectEqualStrings("tick", due.items[0].action);
            try std.testing.expectEqual(@as(i64, 99), due.items[0].lease_until);
        }
    }.run, .{});
}

test "scheduler claim lease blocks duplicate work until expiry" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    _ = try create(std.testing.allocator, io, path, .{
        .kind = .periodic,
        .interval_seconds = 10,
        .action = "tick",
    }, 100, 0);

    var first = try claimDue(std.testing.allocator, io, path, 110, 30);
    defer first.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), first.items.len);
    try std.testing.expectEqual(@as(i64, 140), first.items[0].lease_until);

    var during_lease = try claimDue(std.testing.allocator, io, path, 120, 30);
    defer during_lease.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), during_lease.items.len);

    try std.testing.expect(!try commitDue(std.testing.allocator, io, path, first.items[0].id, first.items[0].lease_until + 1, 120));

    var after_expiry = try claimDue(std.testing.allocator, io, path, 141, 30);
    defer after_expiry.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), after_expiry.items.len);
    try std.testing.expectEqual(@as(i64, 171), after_expiry.items[0].lease_until);

    try std.testing.expectError(error.InvalidScheduleLine, claimDue(std.testing.allocator, io, path, 141, 0));
}

test "scheduler claimDue does not persist lease when returning due tasks runs out of memory" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/schedule.jsonl", .{tmp.sub_path});
    defer std.testing.allocator.free(path);

    _ = try create(std.testing.allocator, io, path, .{
        .kind = .periodic,
        .interval_seconds = 10,
        .action = "tick",
    }, 100, 0);

    var fail_alloc = DueSliceFailAllocator.init(std.testing.allocator);
    try std.testing.expectError(error.OutOfMemory, claimDue(fail_alloc.allocator(), io, path, 110, 30));

    var entries = try load(std.testing.allocator, io, path);
    defer entries.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), entries.items.len);
    try std.testing.expectEqual(@as(i64, 0), entries.items[0].claimed_until);
    try std.testing.expectEqual(@as(i64, 110), entries.items[0].next_run);
}

test "scheduler computes next daily run with timezone offset" {
    const now: i64 = 86_400 + 10 * 60 * 60;
    const next = try nextDailyRun(now, 180, 9, 30);
    try std.testing.expectEqual(@as(i64, 2 * 86_400 + 6 * 60 * 60 + 30 * 60), next);

    const later_same_day = try nextDailyRun(now, -120, 9, 30);
    try std.testing.expectEqual(@as(i64, 86_400 + 11 * 60 * 60 + 30 * 60), later_same_day);
}

test "scheduler advances overdue repeating entries without iterative catch-up" {
    var periodic: Entry = .{
        .id = 1,
        .kind = .periodic,
        .interval_seconds = 10,
        .action = "tick",
        .next_run = 100,
    };
    try advanceEntry(&periodic, 1_000_000_005);
    try std.testing.expectEqual(@as(i64, 1_000_000_010), periodic.next_run);

    var daily: Entry = .{
        .id = 2,
        .kind = .daily,
        .action = "daily",
        .next_run = 100,
    };
    try advanceEntry(&daily, 100 + 365 * seconds_per_day);
    try std.testing.expectEqual(@as(i64, 100 + 366 * seconds_per_day), daily.next_run);
}

test "scheduler rejects timestamp arithmetic overflow" {
    try std.testing.expectError(error.InvalidScheduleLine, computeNextRun(.{
        .kind = .once,
        .delay_seconds = 1,
        .action = "once",
    }, std.math.maxInt(i64), 0));

    try std.testing.expectError(error.InvalidScheduleLine, computeNextRun(.{
        .kind = .daily,
        .hour = 0,
        .minute = 0,
        .action = "daily",
    }, std.math.maxInt(i64), 0));

    var entry: Entry = .{
        .id = 1,
        .kind = .periodic,
        .interval_seconds = 1,
        .action = "tick",
        .next_run = std.math.maxInt(i64),
    };
    try std.testing.expectError(error.InvalidScheduleLine, advanceEntry(&entry, std.math.maxInt(i64)));
    try std.testing.expectError(error.Overflow, addSeconds(std.math.maxInt(i64), 1));
}
