const std = @import("std");
const agent = @import("./agent.zig");
const channel_error = @import("./channels/errors.zig");
const runtime = @import("./runtime.zig");
const scheduler = @import("./scheduler.zig");
const telegram_client = @import("./telegram/client.zig");
const telegram_identity = @import("./telegram/identity.zig");

const Io = std.Io;

pub fn run(app_runtime: *runtime.Runtime, stdout: *Io.Writer, stderr: *Io.Writer) !u8 {
    try stderr.writeAll("nllclw daemon running (Ctrl-C to stop)\n");
    try stderr.flush();

    var next_heartbeat = app_runtime.now();
    while (true) {
        const due_count = runDueSchedules(app_runtime, stdout, stderr) catch |err| warn: {
            try stderr.print("nllclw: schedule warning: {s}\n", .{@errorName(err)});
            try stderr.flush();
            break :warn 0;
        };
        if (due_count > 0) try stdout.flush();

        const now = app_runtime.now();
        if (now >= next_heartbeat) {
            if (try app_runtime.heartbeatPrompt()) |prompt| {
                defer app_runtime.allocator.free(prompt);
                var diagnostic: agent.Diagnostic = .{};
                defer diagnostic.deinit(app_runtime.allocator);
                const text = app_runtime.complete(prompt, stdout, &diagnostic) catch |err| fail: {
                    try channel_error.printAppErrorWriter(stderr, err, diagnostic);
                    try stderr.flush();
                    break :fail null;
                };
                if (text) |bytes| {
                    defer app_runtime.allocator.free(bytes);
                    warnMemory(app_runtime, stderr, prompt, bytes);
                }
            }
            next_heartbeat = nextHeartbeatAfter(now, app_runtime.cfg.value.schedule.heartbeat_interval_seconds);
        }

        try std.Io.sleep(
            app_runtime.io,
            .fromSeconds(app_runtime.cfg.value.schedule.daemon_interval_seconds),
            .real,
        );
    }
}

pub fn runDueSchedules(app_runtime: *runtime.Runtime, stdout: *Io.Writer, stderr: *Io.Writer) !usize {
    var due = try app_runtime.claimDueSchedules();
    defer due.deinit(app_runtime.allocator);

    var completed: usize = 0;
    for (due.items) |task| {
        if (!try destinationReady(app_runtime, task, stderr)) continue;

        const prompt = try std.fmt.allocPrint(
            app_runtime.allocator,
            "[SCHEDULE #{d}]\n{s}",
            .{ task.id, task.action },
        );
        defer app_runtime.allocator.free(prompt);

        var diagnostic: agent.Diagnostic = .{};
        defer diagnostic.deinit(app_runtime.allocator);

        const text = switch (task.destination) {
            .local => app_runtime.complete(prompt, stdout, &diagnostic),
            .telegram => app_runtime.completeWithTurn(prompt, null, &diagnostic, .{
                .schedule_destination = task.destination,
            }),
        } catch |err| {
            try stderr.print("nllclw: schedule #{d} failed\n", .{task.id});
            try channel_error.printAppErrorWriter(stderr, err, diagnostic);
            try stderr.flush();
            continue;
        };
        defer app_runtime.allocator.free(text);

        switch (task.destination) {
            .local => {},
            .telegram => |chat_id| {
                const token = app_runtime.cfg.value.telegram.token orelse {
                    try stderr.print("nllclw: schedule #{d} telegram delivery skipped: missing NLLCLW_TELEGRAM_TOKEN\n", .{task.id});
                    try stderr.flush();
                    continue;
                };
                var send_diagnostic: agent.Diagnostic = .{};
                defer send_diagnostic.deinit(app_runtime.allocator);
                telegram_client.sendTextChunks(
                    app_runtime.allocator,
                    app_runtime.http_client.httpClient(),
                    token,
                    chat_id,
                    text,
                    &send_diagnostic,
                ) catch |err| {
                    try printScheduleTelegramDeliveryError(stderr, task.id, err, send_diagnostic);
                    try stderr.flush();
                    continue;
                };
            },
        }

        warnMemory(app_runtime, stderr, prompt, text);
        if (try app_runtime.commitDueSchedule(task)) completed += 1;
    }
    return completed;
}

fn printScheduleTelegramDeliveryError(
    stderr: *Io.Writer,
    task_id: u32,
    err: anyerror,
    diagnostic: agent.Diagnostic,
) !void {
    try stderr.print("nllclw: schedule #{d} telegram delivery failed", .{task_id});
    if (diagnostic.status) |status| {
        try stderr.print(": HTTP {d}", .{status});
        if (diagnostic.message) |message| {
            try stderr.print(": {s}\n", .{message});
        } else if (diagnostic.body) |body| {
            try stderr.writeByte('\n');
            try channel_error.writeDiagnosticBody(stderr, body);
        } else {
            try stderr.writeByte('\n');
        }
        return;
    }

    if (diagnostic.message) |message| {
        try stderr.print(": {s}\n", .{message});
    } else if (diagnostic.body) |body| {
        try stderr.print(": {s}\n", .{@errorName(err)});
        try channel_error.writeDiagnosticBody(stderr, body);
    } else {
        try stderr.print(": {s}\n", .{@errorName(err)});
    }
}

fn warnMemory(app_runtime: *runtime.Runtime, stderr: *Io.Writer, prompt: []const u8, text: []const u8) void {
    app_runtime.rememberTurn(prompt, text) catch |err| {
        stderr.print("nllclw: warning: failed to update memory: {s}\n", .{@errorName(err)}) catch return;
        stderr.flush() catch return;
    };
}

const DestinationStatus = enum {
    ready,
    missing_telegram_chat_id,
    telegram_chat_not_allowlisted,
    missing_telegram_token,
};

fn destinationReady(app_runtime: *runtime.Runtime, task: scheduler.DueTask, stderr: *Io.Writer) !bool {
    switch (destinationStatus(task, app_runtime.cfg.value.telegram.chat_id, app_runtime.cfg.value.telegram.token)) {
        .ready => return true,
        .missing_telegram_chat_id => try stderr.print(
            "nllclw: schedule #{d} blocked: telegram delivery requires NLLCLW_TELEGRAM_CHAT_ID\n",
            .{task.id},
        ),
        .telegram_chat_not_allowlisted => try stderr.print(
            "nllclw: schedule #{d} blocked: telegram chat {d} is not allowlisted\n",
            .{ task.id, telegramDestinationId(task.destination) orelse 0 },
        ),
        .missing_telegram_token => try stderr.print(
            "nllclw: schedule #{d} blocked: telegram delivery requires NLLCLW_TELEGRAM_TOKEN\n",
            .{task.id},
        ),
    }
    try stderr.flush();
    return false;
}

fn destinationStatus(task: scheduler.DueTask, allowed_chat_id: ?telegram_identity.ChatAllowlist, token: ?[]const u8) DestinationStatus {
    switch (task.destination) {
        .local => return .ready,
        .telegram => |chat_id| {
            const allowed = allowed_chat_id orelse return .missing_telegram_chat_id;
            switch (allowed) {
                .id => |id| if (chat_id != id) return .telegram_chat_not_allowlisted,
                // Telegram schedules persist numeric chat ids. Username allowlists
                // are enforced when Telegram creates the local schedule.
                .username => {},
            }
            if (token == null) return .missing_telegram_token;
            return .ready;
        },
    }
}

fn telegramDestinationId(destination: scheduler.Destination) ?i64 {
    return switch (destination) {
        .local => null,
        .telegram => |chat_id| chat_id,
    };
}

fn nextHeartbeatAfter(now: i64, interval_seconds: u32) i64 {
    return std.math.add(i64, now, @intCast(interval_seconds)) catch std.math.maxInt(i64);
}

test "daemon heartbeat scheduling caps on integer overflow" {
    try std.testing.expectEqual(
        @as(i64, 1060),
        nextHeartbeatAfter(1000, 60),
    );
    try std.testing.expectEqual(
        std.math.maxInt(i64),
        nextHeartbeatAfter(std.math.maxInt(i64), 60),
    );
}

test "daemon telegram schedule delivery errors include diagnostics" {
    var out = Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    var diagnostic: agent.Diagnostic = .{
        .status = 401,
        .message = try std.testing.allocator.dupe(u8, "bad token"),
    };
    defer diagnostic.deinit(std.testing.allocator);

    try printScheduleTelegramDeliveryError(&out.writer, 7, error.TelegramHttpStatus, diagnostic);
    try std.testing.expectEqualStrings(
        "nllclw: schedule #7 telegram delivery failed: HTTP 401: bad token\n",
        out.written(),
    );
}

test "daemon keeps telegram schedules leased when destination is not deliverable" {
    const task = scheduler.DueTask{
        .id = 1,
        .action = try std.testing.allocator.dupe(u8, "ping"),
        .destination = .{ .telegram = 42 },
        .lease_until = 100,
    };
    defer std.testing.allocator.free(task.action);

    try std.testing.expectEqual(.missing_telegram_chat_id, destinationStatus(task, null, "123:token"));
    try std.testing.expectEqual(.telegram_chat_not_allowlisted, destinationStatus(task, .{ .id = 99 }, "123:token"));
    try std.testing.expectEqual(.missing_telegram_token, destinationStatus(task, .{ .id = 42 }, null));
    try std.testing.expectEqual(.ready, destinationStatus(task, .{ .id = 42 }, "123:token"));
    try std.testing.expectEqual(.ready, destinationStatus(task, .{ .username = "donprus" }, "123:token"));

    const local_task = scheduler.DueTask{
        .id = 2,
        .action = try std.testing.allocator.dupe(u8, "local"),
        .destination = .local,
        .lease_until = 100,
    };
    defer std.testing.allocator.free(local_task.action);
    try std.testing.expectEqual(.ready, destinationStatus(local_task, null, null));
}
