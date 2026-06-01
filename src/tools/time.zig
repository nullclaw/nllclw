const std = @import("std");
const chat = @import("../chat.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const definition: chat.ToolDefinition = .{
    .name = "get_time",
    .description = "Get current Unix time and configured local wall-clock time.",
    .parameters = .{ .properties = &.{} },
};

pub const Client = struct {
    io: Io,
    timezone_offset_minutes: i32,
    output_max_bytes: usize,

    pub fn init(io: Io, timezone_offset_minutes: i32, output_max_bytes: usize) Client {
        return .{
            .io = io,
            .timezone_offset_minutes = timezone_offset_minutes,
            .output_max_bytes = output_max_bytes,
        };
    }

    pub fn handler(self: *Client) tool.Handler {
        return .{ .definition = definition, .ptr = self, .run_fn = run };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        try parseEmptyObject(allocator, call.arguments);
        const now = Io.Timestamp.now(self.io, .real).toSeconds();
        const local = try formatLocalTime(allocator, now, self.timezone_offset_minutes);
        defer allocator.free(local);
        const text = try std.fmt.allocPrint(
            allocator,
            "unix_seconds: {d}\ntimezone_offset_minutes: {d}\nlocal_time: {s}\n",
            .{ now, self.timezone_offset_minutes, local },
        );
        errdefer allocator.free(text);
        if (text.len > self.output_max_bytes) return error.ToolOutputTooLarge;
        return text;
    }
};

const EmptyArgs = struct {};

fn parseEmptyObject(allocator: Allocator, arguments: []const u8) tool.RunError!void {
    const parsed = try tool.parseArgs(EmptyArgs, allocator, arguments, .{});
    parsed.deinit();
}

fn formatLocalTime(allocator: Allocator, unix_seconds: i64, offset_minutes: i32) tool.RunError![]u8 {
    const offset_seconds = @as(i64, offset_minutes) * 60;
    const local_seconds = std.math.add(i64, unix_seconds, offset_seconds) catch return error.ToolFailed;
    if (local_seconds < 0) return std.fmt.allocPrint(allocator, "{d}", .{local_seconds});

    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(local_seconds) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    return std.fmt.allocPrint(
        allocator,
        "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
}

test "time tool reports configured offset and rejects non-object input" {
    var client = Client.init(std.testing.io, 180, 256);
    const output = try client.handler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "get_time",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "unix_seconds: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "timezone_offset_minutes: 180\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "local_time: ") != null);

    try std.testing.expectError(error.InvalidToolArguments, client.handler().run(std.testing.allocator, .{
        .id = "call_2",
        .name = "get_time",
        .arguments = "null",
    }));
}

test "time tool enforces output cap" {
    var client = Client.init(std.testing.io, 0, 32);
    try std.testing.expectError(error.ToolOutputTooLarge, client.handler().run(std.testing.allocator, .{
        .id = "call_1",
        .name = "get_time",
        .arguments = "{}",
    }));
}

test "time formatter uses numeric local wall-clock format" {
    const epoch = try formatLocalTime(std.testing.allocator, 0, 0);
    defer std.testing.allocator.free(epoch);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00", epoch);

    const offset = try formatLocalTime(std.testing.allocator, 0, 90);
    defer std.testing.allocator.free(offset);
    try std.testing.expectEqualStrings("1970-01-01T01:30:00", offset);

    try std.testing.expectError(error.ToolFailed, formatLocalTime(std.testing.allocator, std.math.maxInt(i64), 1));
}
