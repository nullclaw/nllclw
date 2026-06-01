const std = @import("std");
const state_file = @import("../adapters/state_file.zig");
const agent = @import("../agent.zig");
const app_paths = @import("../app_paths.zig");
const commands = @import("./commands.zig");
const runtime = @import("../runtime.zig");
const channel_error = @import("./errors.zig");
const telegram = @import("../telegram/codec.zig");
const telegram_client = @import("../telegram/client.zig");
const telegram_identity = @import("../telegram/identity.zig");
const telegram_offset = @import("../telegram/offset.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const ratelimit = @import("../ratelimit.zig");

pub fn isCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "telegram");
}

pub fn run(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    usage: []const u8,
) !u8 {
    var app_runtime = runtime.Runtime.init(allocator, io, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.writeAll(usage);
        try stderr.flush();
        return 2;
    };
    defer app_runtime.deinit();

    const token = app_runtime.cfg.value.telegram.token orelse {
        try stderr.writeAll("nllclw: config error: set NLLCLW_TELEGRAM_TOKEN\n");
        try stderr.writeAll(usage);
        try stderr.flush();
        return 2;
    };

    const allowed_chat = app_runtime.cfg.value.telegram.chat_id orelse {
        try stderr.writeAll("nllclw: config error: set NLLCLW_TELEGRAM_CHAT_ID\n");
        try stderr.flush();
        return 2;
    };

    const poller_path = try app_paths.telegramPollerPath(allocator, env_map);
    defer allocator.free(poller_path);
    var poller_lock = state_file.tryLockPath(allocator, io, poller_path) catch |err| {
        try stderr.print("nllclw: telegram lock error: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return 2;
    } orelse {
        try stderr.writeAll("nllclw: telegram already running on this machine\n");
        try stderr.flush();
        return 2;
    };
    defer poller_lock.close(io);

    try stderr.writeAll("nllclw telegram polling (: stop with Ctrl-C)\n");
    try stderr.flush();

    const offset_path = try app_paths.telegramOffsetPath(allocator, env_map);
    defer allocator.free(offset_path);
    const offset_store: telegram_offset.Store = .{ .io = io, .path = offset_path };
    var offset: ?i64 = offset_store.load(allocator) catch |err| load_offset: {
        try stderr.print("nllclw: telegram offset warning: {s}; starting from latest unconfirmed update\n", .{@errorName(err)});
        try stderr.flush();
        break :load_offset null;
    };
    var paused = false;
    var limiter: ratelimit.FixedWindow = .{
        .limit = app_runtime.cfg.value.telegram.rate_limit_per_minute,
    };
    while (true) {
        var diagnostic: agent.Diagnostic = .{};
        var updates = telegram_client.fetchUpdates(
            allocator,
            app_runtime.http_client.httpClient(),
            token,
            offset,
            app_runtime.cfg.value.telegram.poll_timeout_seconds,
            &diagnostic,
        ) catch |err| {
            defer diagnostic.deinit(allocator);
            try printTelegramError(stderr, err, diagnostic);
            try stderr.flush();
            return 1;
        };
        defer updates.deinit(allocator);
        const batch_next_offset = updates.next_offset;

        for (updates.items) |update| {
            const update_next_offset = try telegram.nextOffset(update.update_id);
            if (!telegram_identity.matches(allowed_chat, update.chat_id, update.chat_username, update.from_username)) {
                offset = try advanceOffset(allocator, offset_store, stderr, update_next_offset);
                continue;
            }

            var command_diagnostic: agent.Diagnostic = .{};
            const handled = handleBuiltInCommand(
                allocator,
                app_runtime.http_client.httpClient(),
                token,
                update,
                &app_runtime,
                &paused,
                &command_diagnostic,
            ) catch |err| handled: {
                try printTelegramError(stderr, err, command_diagnostic);
                try stderr.flush();
                break :handled true;
            };
            command_diagnostic.deinit(allocator);
            if (handled) {
                offset = try advanceOffset(allocator, offset_store, stderr, update_next_offset);
                continue;
            }
            if (paused) {
                offset = try advanceOffset(allocator, offset_store, stderr, update_next_offset);
                continue;
            }

            if (!limiter.allow(app_runtime.now())) {
                var send_diagnostic: agent.Diagnostic = .{};
                defer send_diagnostic.deinit(allocator);
                telegram_client.sendTextChunks(
                    allocator,
                    app_runtime.http_client.httpClient(),
                    token,
                    update.chat_id,
                    "nllclw: rate limit exceeded, try again later",
                    &send_diagnostic,
                ) catch |err| try printTelegramError(stderr, err, send_diagnostic);
                offset = try advanceOffset(allocator, offset_store, stderr, update_next_offset);
                continue;
            }

            var app_diagnostic: agent.Diagnostic = .{};
            const text = app_runtime.completeWithTurn(update.text, null, &app_diagnostic, .{
                .schedule_destination = .{ .telegram = update.chat_id },
            }) catch |err| {
                defer app_diagnostic.deinit(allocator);
                try channel_error.printAppErrorWriter(stderr, err, app_diagnostic);
                var send_error_diagnostic: agent.Diagnostic = .{};
                defer send_error_diagnostic.deinit(allocator);
                telegram_client.sendTextChunks(
                    allocator,
                    app_runtime.http_client.httpClient(),
                    token,
                    update.chat_id,
                    "nllclw: request failed",
                    &send_error_diagnostic,
                ) catch |send_err| {
                    try printTelegramError(stderr, send_err, send_error_diagnostic);
                };
                try stderr.flush();
                offset = try advanceOffset(allocator, offset_store, stderr, update_next_offset);
                continue;
            };
            defer app_diagnostic.deinit(allocator);
            defer allocator.free(text);

            offset = try advanceOffset(allocator, offset_store, stderr, update_next_offset);

            var send_diagnostic: agent.Diagnostic = .{};
            telegram_client.sendTextChunks(
                allocator,
                app_runtime.http_client.httpClient(),
                token,
                update.chat_id,
                text,
                &send_diagnostic,
            ) catch |err| {
                defer send_diagnostic.deinit(allocator);
                try printTelegramError(stderr, err, send_diagnostic);
                try stderr.flush();
                continue;
            };
            send_diagnostic.deinit(allocator);

            app_runtime.rememberTurn(update.text, text) catch |err| {
                try stderr.print("nllclw: warning: failed to update memory: {s}\n", .{@errorName(err)});
                try stderr.flush();
            };
        }

        if (batch_next_offset) |next| {
            const should_advance = updates.items.len == 0 or if (offset) |current| next > current else true;
            if (should_advance) {
                offset = try advanceOffset(allocator, offset_store, stderr, next);
            }
        }
    }
}

fn advanceOffset(
    allocator: Allocator,
    store: telegram_offset.Store,
    stderr: *Io.Writer,
    next: i64,
) !i64 {
    store.save(allocator, next) catch |err| {
        try stderr.print("nllclw: telegram offset warning: failed to save offset: {s}\n", .{@errorName(err)});
        try stderr.flush();
    };
    return next;
}

fn handleBuiltInCommand(
    allocator: Allocator,
    client: @import("../ports/http.zig").Client,
    token: []const u8,
    update: telegram.Update,
    app_runtime: *runtime.Runtime,
    paused: *bool,
    diagnostic: ?*agent.Diagnostic,
) !bool {
    const text = std.mem.trim(u8, update.text, &std.ascii.whitespace);
    const command = commands.parse(text);
    return switch (command) {
        .none => false,
        .chat_id => blk: {
            const message = try formatChatIdMessage(allocator, update);
            defer allocator.free(message);
            try telegram_client.sendTextChunks(allocator, client, token, update.chat_id, message, diagnostic);
            break :blk true;
        },
        .help => blk: {
            try telegram_client.sendTextChunks(
                allocator,
                client,
                token,
                update.chat_id,
                commands.help_text,
                diagnostic,
            );
            break :blk true;
        },
        .settings => blk: {
            const status = try app_runtime.statusText(.quick);
            defer allocator.free(status);
            try telegram_client.sendTextChunks(allocator, client, token, update.chat_id, status, diagnostic);
            break :blk true;
        },
        .diag => |scope| blk: {
            const status = try app_runtime.statusText(scope);
            defer allocator.free(status);
            try telegram_client.sendTextChunks(allocator, client, token, update.chat_id, status, diagnostic);
            break :blk true;
        },
        .invalid_diag => blk: {
            try telegram_client.sendTextChunks(
                allocator,
                client,
                token,
                update.chat_id,
                "usage: /diag [quick|runtime|memory|rates|time|all]",
                diagnostic,
            );
            break :blk true;
        },
        .persona => |persona_command| blk: {
            const message = try handlePersonaCommand(allocator, app_runtime, persona_command);
            defer allocator.free(message);
            try telegram_client.sendTextChunks(allocator, client, token, update.chat_id, message, diagnostic);
            break :blk true;
        },
        .pause => blk: {
            paused.* = true;
            try telegram_client.sendTextChunks(allocator, client, token, update.chat_id, "nllclw intake paused. Send /resume to continue.", diagnostic);
            break :blk true;
        },
        .resume_intake => blk: {
            paused.* = false;
            try telegram_client.sendTextChunks(allocator, client, token, update.chat_id, "nllclw intake resumed.", diagnostic);
            break :blk true;
        },
    };
}

fn formatChatIdMessage(allocator: Allocator, update: telegram.Update) ![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    try out.writer.print("chat_id: {d}", .{update.chat_id});
    if (update.chat_username) |username| {
        try out.writer.print("\nchat_username: @{s}", .{username});
    }
    if (update.from_username) |username| {
        try out.writer.print("\nfrom_username: @{s}", .{username});
    }
    return out.toOwnedSlice();
}

fn handlePersonaCommand(
    allocator: Allocator,
    app_runtime: *runtime.Runtime,
    command: commands.PersonaCommand,
) ![]u8 {
    return switch (command) {
        .show => std.fmt.allocPrint(allocator, "persona: {s}\n", .{app_runtime.personaName()}),
        .set => |kind| blk: {
            try app_runtime.setPersona(kind);
            break :blk try std.fmt.allocPrint(allocator, "persona: {s}\n", .{app_runtime.personaName()});
        },
        .invalid => allocator.dupe(u8, "usage: /persona neutral|friendly|technical|witty\n"),
    };
}

fn printTelegramError(stderr: *Io.Writer, err: anyerror, diagnostic: agent.Diagnostic) !void {
    if (diagnostic.status) |status| {
        try stderr.print("nllclw: telegram returned HTTP {d}", .{status});
        if (diagnostic.message) |message| {
            try stderr.print(": {s}\n", .{message});
            try printTelegramConflictHint(stderr, status);
        } else if (diagnostic.body) |body| {
            try stderr.writeByte('\n');
            try channel_error.writeDiagnosticBody(stderr, body);
            try printTelegramConflictHint(stderr, status);
        } else {
            try stderr.writeByte('\n');
            try printTelegramConflictHint(stderr, status);
        }
        return;
    }

    if (diagnostic.message) |message| {
        try stderr.print("nllclw: telegram error: {s}\n", .{message});
    } else if (diagnostic.body) |body| {
        try stderr.print("nllclw: telegram {s}\n", .{@errorName(err)});
        try channel_error.writeDiagnosticBody(stderr, body);
    } else {
        try stderr.print("nllclw: telegram {s}\n", .{@errorName(err)});
    }
}

fn printTelegramConflictHint(stderr: *Io.Writer, status: u16) !void {
    if (status != 409) return;
    try stderr.writeAll("nllclw: another Telegram getUpdates poller is already using this bot token\n");
}

test "telegram command predicate accepts subcommands" {
    try std.testing.expect(isCommand("telegram"));
    try std.testing.expect(!isCommand("hello"));
}

test "telegram chat id command includes username fields" {
    const chat_username = try std.testing.allocator.dupe(u8, "private_user");
    defer std.testing.allocator.free(chat_username);
    const from_username = try std.testing.allocator.dupe(u8, "sender_user");
    defer std.testing.allocator.free(from_username);
    const text = try std.testing.allocator.dupe(u8, "/chatid");
    defer std.testing.allocator.free(text);

    const message = try formatChatIdMessage(std.testing.allocator, .{
        .update_id = 1,
        .chat_id = 42,
        .chat_username = chat_username,
        .from_username = from_username,
        .text = text,
    });
    defer std.testing.allocator.free(message);

    try std.testing.expectEqualStrings(
        "chat_id: 42\nchat_username: @private_user\nfrom_username: @sender_user",
        message,
    );
}
