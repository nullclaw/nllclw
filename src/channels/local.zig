const std = @import("std");
const agent = @import("../agent.zig");
const channel_error = @import("./errors.zig");
const daemon = @import("../daemon.zig");
const memory = @import("../memory.zig");
const runtime = @import("../runtime.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const memory_usage =
    \\usage:
    \\  nllclw memory list
    \\  nllclw memory get <key>
    \\  nllclw memory forget <key>
    \\  nllclw memory reset
    \\
;

const schedule_usage =
    \\usage:
    \\  nllclw schedule list
    \\  nllclw schedule delete <id>
    \\
;

const MemoryCommand = union(enum) {
    list,
    get: []const u8,
    forget: []const u8,
    reset,
};

const MemoryCommandParse = union(enum) {
    command: MemoryCommand,
    usage: []const u8,
    unknown,
};

const ScheduleCommand = union(enum) {
    list,
    delete: u32,
};

const ScheduleCommandParse = union(enum) {
    command: ScheduleCommand,
    usage: []const u8,
    invalid_id,
    unknown,
};

pub fn isCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "status") or
        std.mem.eql(u8, arg, "doctor") or
        std.mem.eql(u8, arg, "memory") or
        std.mem.eql(u8, arg, "schedule") or
        std.mem.eql(u8, arg, "heartbeat") or
        std.mem.eql(u8, arg, "daemon");
}

pub fn run(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    if (std.mem.eql(u8, args[1], "memory")) {
        return runMemoryCommand(allocator, io, env_map, args, stdout, stderr);
    }
    if (std.mem.eql(u8, args[1], "schedule")) {
        return runScheduleCommand(allocator, io, env_map, args, stdout, stderr);
    }

    if (simpleCommandHelp(args)) |command| {
        try stdout.print("usage: nllclw {s}\n", .{command});
        try stdout.flush();
        return 0;
    }

    if (simpleCommandWithExtraArgs(args)) |command| {
        try stderr.print("nllclw: usage: nllclw {s}\n", .{command});
        try stderr.flush();
        return 2;
    }

    var app_runtime = runtime.Runtime.init(allocator, io, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.flush();
        return 2;
    };
    defer app_runtime.deinit();

    if (std.mem.eql(u8, args[1], "status")) {
        const text = try app_runtime.statusText(.quick);
        defer allocator.free(text);
        try stdout.writeAll(text);
        try stdout.flush();
        return 0;
    }
    if (std.mem.eql(u8, args[1], "doctor")) {
        const text = try app_runtime.statusText(.all);
        defer allocator.free(text);
        try stdout.writeAll(text);
        try stdout.flush();
        return 0;
    }
    if (std.mem.eql(u8, args[1], "heartbeat")) {
        var diagnostic: agent.Diagnostic = .{};
        defer diagnostic.deinit(allocator);
        _ = app_runtime.runHeartbeat(stdout, &diagnostic) catch |err| {
            try channel_error.printAppErrorWriter(stderr, err, diagnostic);
            try stderr.flush();
            return 1;
        };
        return 0;
    }
    if (std.mem.eql(u8, args[1], "daemon")) {
        return daemon.run(&app_runtime, stdout, stderr);
    }
    return 2;
}

fn runMemoryCommand(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    if (args.len < 3 or (args.len == 3 and isHelp(args[2]))) {
        try stdout.writeAll(memory_usage);
        try stdout.flush();
        return 0;
    }

    const parsed = parseMemoryCommand(args);
    const command = switch (parsed) {
        .command => |command| command,
        .usage => |text| {
            try stderr.writeAll(text);
            try stderr.flush();
            return 2;
        },
        .unknown => {
            try stderr.writeAll("nllclw: unknown memory command\n");
            try stderr.flush();
            return 2;
        },
    };

    var app_runtime = runtime.Runtime.init(allocator, io, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.flush();
        return 2;
    };
    defer app_runtime.deinit();

    switch (command) {
        .list => {
            var listed = app_runtime.listMemoryFacts() catch |err| {
                try stderr.print("nllclw: memory error: {s}\n", .{@errorName(err)});
                try stderr.flush();
                return 1;
            };
            defer listed.deinit(allocator);
            try stdout.writeAll("memories:\n");
            for (listed.entries) |fact| try stdout.print("- {s}: {s}\n", .{ fact.key, fact.value });
            try stdout.flush();
            return 0;
        },
        .get => |key| {
            const value = app_runtime.getMemoryFact(key) catch |err| {
                try stderr.print("nllclw: memory error: {s}\n", .{@errorName(err)});
                try stderr.flush();
                return 1;
            };
            defer if (value) |bytes| allocator.free(bytes);
            if (value) |bytes| {
                try stdout.print("{s}: {s}\n", .{ key, bytes });
            } else {
                try stdout.print("not found: {s}\n", .{key});
            }
            try stdout.flush();
            return 0;
        },
        .forget => |key| {
            const deleted = app_runtime.forgetMemoryFact(key) catch |err| {
                try stderr.print("nllclw: memory error: {s}\n", .{@errorName(err)});
                try stderr.flush();
                return 1;
            };
            try stdout.print("{s}: {s}\n", .{ if (deleted) "deleted" else "not found", key });
            try stdout.flush();
            return 0;
        },
        .reset => {
            app_runtime.resetMemory() catch |err| {
                try stderr.print("nllclw: memory error: {s}\n", .{@errorName(err)});
                try stderr.flush();
                return 1;
            };
            try stdout.writeAll("memory reset\n");
            try stdout.flush();
            return 0;
        },
    }
}

fn runScheduleCommand(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    if (args.len < 3 or (args.len == 3 and isHelp(args[2]))) {
        try stdout.writeAll(schedule_usage);
        try stdout.flush();
        return 0;
    }

    const parsed = parseScheduleCommand(args);
    const command = switch (parsed) {
        .command => |command| command,
        .usage => |text| {
            try stderr.writeAll(text);
            try stderr.flush();
            return 2;
        },
        .invalid_id => {
            try stderr.writeAll("nllclw: schedule id must be an integer\n");
            try stderr.flush();
            return 2;
        },
        .unknown => {
            try stderr.writeAll("nllclw: unknown schedule command\n");
            try stderr.flush();
            return 2;
        },
    };

    var app_runtime = runtime.Runtime.init(allocator, io, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.flush();
        return 2;
    };
    defer app_runtime.deinit();

    switch (command) {
        .list => {
            const text = app_runtime.listSchedules() catch |err| {
                try stderr.print("nllclw: schedule error: {s}\n", .{@errorName(err)});
                try stderr.flush();
                return 1;
            };
            defer allocator.free(text);
            try stdout.writeAll(text);
            try stdout.flush();
            return 0;
        },
        .delete => |id| {
            const deleted = app_runtime.deleteSchedule(id) catch |err| {
                try stderr.print("nllclw: schedule error: {s}\n", .{@errorName(err)});
                try stderr.flush();
                return 1;
            };
            try stdout.print("{s} schedule #{d}\n", .{ if (deleted) "deleted" else "not found", id });
            try stdout.flush();
            return 0;
        },
    }
}

fn parseMemoryCommand(args: []const [:0]const u8) MemoryCommandParse {
    const command = args[2];
    if (std.mem.eql(u8, command, "list")) {
        return if (args.len == 3)
            .{ .command = .list }
        else
            .{ .usage = "nllclw: usage: nllclw memory list\n" };
    }
    if (std.mem.eql(u8, command, "get")) {
        if (args.len != 4 or !memory.isValidFactKey(args[3])) {
            return .{ .usage = "nllclw: usage: nllclw memory get <key>\n" };
        }
        return .{ .command = .{ .get = args[3] } };
    }
    if (std.mem.eql(u8, command, "forget")) {
        if (args.len != 4 or !memory.isValidFactKey(args[3])) {
            return .{ .usage = "nllclw: usage: nllclw memory forget <key>\n" };
        }
        return .{ .command = .{ .forget = args[3] } };
    }
    if (std.mem.eql(u8, command, "reset")) {
        return if (args.len == 3)
            .{ .command = .reset }
        else
            .{ .usage = "nllclw: usage: nllclw memory reset\n" };
    }
    return .unknown;
}

fn parseScheduleCommand(args: []const [:0]const u8) ScheduleCommandParse {
    const command = args[2];
    if (std.mem.eql(u8, command, "list")) {
        return if (args.len == 3)
            .{ .command = .list }
        else
            .{ .usage = "nllclw: usage: nllclw schedule list\n" };
    }
    if (std.mem.eql(u8, command, "delete")) {
        if (args.len != 4) return .{ .usage = "nllclw: usage: nllclw schedule delete <id>\n" };
        return .{ .command = .{ .delete = parseScheduleId(args[3]) catch return .invalid_id } };
    }
    return .unknown;
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help");
}

fn simpleCommandWithExtraArgs(args: []const [:0]const u8) ?[]const u8 {
    if (args.len <= 2) return null;
    if (simpleCommandHelp(args) != null) return null;
    const command = args[1];
    return if (isSimpleCommand(command)) command else null;
}

fn simpleCommandHelp(args: []const [:0]const u8) ?[]const u8 {
    if (args.len != 3 or !isHelp(args[2])) return null;
    const command = args[1];
    return if (isSimpleCommand(command)) command else null;
}

fn isSimpleCommand(command: []const u8) bool {
    return std.mem.eql(u8, command, "status") or
        std.mem.eql(u8, command, "doctor") or
        std.mem.eql(u8, command, "heartbeat") or
        std.mem.eql(u8, command, "daemon");
}

fn parseScheduleId(raw: []const u8) error{InvalidScheduleId}!u32 {
    const id = std.fmt.parseInt(u32, raw, 10) catch return error.InvalidScheduleId;
    if (id == 0) return error.InvalidScheduleId;
    return id;
}

test "local commands are canonical only" {
    try std.testing.expect(isCommand("status"));
    try std.testing.expect(isCommand("doctor"));
    try std.testing.expect(isCommand("schedule"));
    try std.testing.expect(!isCommand("cron"));
}

test "local schedule id parser rejects impossible ids" {
    try std.testing.expectEqual(@as(u32, 42), try parseScheduleId("42"));
    try std.testing.expectError(error.InvalidScheduleId, parseScheduleId("0"));
    try std.testing.expectError(error.InvalidScheduleId, parseScheduleId("nope"));
}

test "simple local commands reject extra argv before runtime init" {
    const status_extra: []const [:0]const u8 = &.{ "nllclw", "status", "extra" };
    try std.testing.expectEqualStrings("status", simpleCommandWithExtraArgs(status_extra).?);

    const status_help: []const [:0]const u8 = &.{ "nllclw", "status", "--help" };
    try std.testing.expectEqualStrings("status", simpleCommandHelp(status_help).?);
    try std.testing.expect(simpleCommandWithExtraArgs(status_help) == null);

    const heartbeat_ok: []const [:0]const u8 = &.{ "nllclw", "heartbeat" };
    try std.testing.expect(simpleCommandWithExtraArgs(heartbeat_ok) == null);

    const memory_extra: []const [:0]const u8 = &.{ "nllclw", "memory", "list" };
    try std.testing.expect(simpleCommandWithExtraArgs(memory_extra) == null);
}

test "memory commands validate argv before runtime init" {
    const list_extra: []const [:0]const u8 = &.{ "nllclw", "memory", "list", "extra" };
    try std.testing.expectEqualStrings(
        "nllclw: usage: nllclw memory list\n",
        parseMemoryCommand(list_extra).usage,
    );

    const get_invalid: []const [:0]const u8 = &.{ "nllclw", "memory", "get", "bad/key" };
    try std.testing.expectEqualStrings(
        "nllclw: usage: nllclw memory get <key>\n",
        parseMemoryCommand(get_invalid).usage,
    );

    const forget_ok: []const [:0]const u8 = &.{ "nllclw", "memory", "forget", "topic" };
    try std.testing.expectEqualStrings("topic", parseMemoryCommand(forget_ok).command.forget);

    const unknown: []const [:0]const u8 = &.{ "nllclw", "memory", "drop" };
    try std.testing.expectEqual(MemoryCommandParse.unknown, parseMemoryCommand(unknown));
}

test "schedule commands validate argv before runtime init" {
    const list_extra: []const [:0]const u8 = &.{ "nllclw", "schedule", "list", "extra" };
    try std.testing.expectEqualStrings(
        "nllclw: usage: nllclw schedule list\n",
        parseScheduleCommand(list_extra).usage,
    );

    const delete_bad_id: []const [:0]const u8 = &.{ "nllclw", "schedule", "delete", "0" };
    try std.testing.expectEqual(ScheduleCommandParse.invalid_id, parseScheduleCommand(delete_bad_id));

    const delete_ok: []const [:0]const u8 = &.{ "nllclw", "schedule", "delete", "12" };
    try std.testing.expectEqual(@as(u32, 12), parseScheduleCommand(delete_ok).command.delete);

    const unknown: []const [:0]const u8 = &.{ "nllclw", "schedule", "drop" };
    try std.testing.expectEqual(ScheduleCommandParse.unknown, parseScheduleCommand(unknown));
}
