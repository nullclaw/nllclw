const std = @import("std");
const commands = @import("./commands.zig");
const runtime = @import("../runtime.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn runStateless(prompt: []const u8, stdout: *Io.Writer) !?u8 {
    switch (commands.parse(prompt)) {
        .none => return null,
        .help => {
            try stdout.writeAll(commands.help_text);
            try stdout.flush();
            return 0;
        },
        .chat_id => {
            try stdout.writeAll("chat_id is only available in Telegram\n");
            try stdout.flush();
            return 0;
        },
        .pause => {
            try stdout.writeAll("intake pause is only available in Telegram\n");
            try stdout.flush();
            return 0;
        },
        .resume_intake => {
            try stdout.writeAll("intake resume is only available in Telegram\n");
            try stdout.flush();
            return 0;
        },
        .invalid_diag => {
            try stdout.writeAll("usage: /diag [quick|runtime|memory|rates|time|all]\n");
            try stdout.flush();
            return 2;
        },
        .persona => |persona_command| switch (persona_command) {
            .invalid => {
                try stdout.writeAll("usage: /persona neutral|friendly|technical|witty\n");
                try stdout.flush();
                return 2;
            },
            else => return null,
        },
        else => return null,
    }
}

pub fn run(
    allocator: Allocator,
    app_runtime: *runtime.Runtime,
    prompt: []const u8,
    stdout: *Io.Writer,
) !?u8 {
    switch (commands.parse(prompt)) {
        .none => return null,
        .help => {
            try stdout.writeAll(commands.help_text);
            try stdout.flush();
            return 0;
        },
        .chat_id => {
            try stdout.writeAll("chat_id is only available in Telegram\n");
            try stdout.flush();
            return 0;
        },
        .settings => {
            const text = try app_runtime.statusText(.quick);
            defer allocator.free(text);
            try stdout.writeAll(text);
            try stdout.flush();
            return 0;
        },
        .diag => |scope| {
            const text = try app_runtime.statusText(scope);
            defer allocator.free(text);
            try stdout.writeAll(text);
            try stdout.flush();
            return 0;
        },
        .invalid_diag => {
            try stdout.writeAll("usage: /diag [quick|runtime|memory|rates|time|all]\n");
            try stdout.flush();
            return 2;
        },
        .persona => |persona_command| {
            const code = try writePersonaCommand(app_runtime, persona_command, stdout);
            try stdout.flush();
            return code;
        },
        .pause => {
            try stdout.writeAll("intake pause is only available in Telegram\n");
            try stdout.flush();
            return 0;
        },
        .resume_intake => {
            try stdout.writeAll("intake resume is only available in Telegram\n");
            try stdout.flush();
            return 0;
        },
    }
}

fn writePersonaCommand(
    app_runtime: *runtime.Runtime,
    command: commands.PersonaCommand,
    stdout: *Io.Writer,
) !u8 {
    switch (command) {
        .show => {
            try stdout.print("persona: {s}\n", .{app_runtime.personaName()});
            return 0;
        },
        .set => |kind| {
            try app_runtime.setPersona(kind);
            try stdout.print("persona: {s}\n", .{app_runtime.personaName()});
            return 0;
        },
        .invalid => {
            try stdout.writeAll("usage: /persona neutral|friendly|technical|witty\n");
            return 2;
        },
    }
}
