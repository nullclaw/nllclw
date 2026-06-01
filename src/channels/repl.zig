const std = @import("std");
const agent = @import("../agent.zig");
const runtime = @import("../runtime.zig");
const channel_error = @import("./errors.zig");
const slash = @import("./slash.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_prompt_bytes = 64 * 1024;

pub const Command = union(enum) {
    empty,
    quit,
    prompt: []const u8,
};

pub fn run(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    stdout: *Io.Writer,
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

    try stderr.writeAll("nllclw interactive (:q to quit)\n");
    try stderr.flush();

    var stdin_buffer: [max_prompt_bytes + 1]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
    while (true) {
        try stderr.writeAll("nllclw> ");
        try stderr.flush();

        const line = try readLineAlloc(allocator, &stdin_reader.interface) orelse break;
        const command = parse(line);
        switch (command) {
            .empty => {
                allocator.free(line);
                continue;
            },
            .quit => {
                allocator.free(line);
                break;
            },
            .prompt => |prompt| {
                if (try slash.run(allocator, &app_runtime, prompt, stdout)) |_| {
                    allocator.free(line);
                    continue;
                }

                try stderr.writeAll("assistant> ");
                try stderr.flush();

                var diagnostic: agent.Diagnostic = .{};
                const text = app_runtime.complete(prompt, stdout, &diagnostic) catch |err| {
                    defer diagnostic.deinit(allocator);
                    try channel_error.printAppErrorWriter(stderr, err, diagnostic);
                    try stderr.flush();
                    allocator.free(line);
                    continue;
                };
                defer diagnostic.deinit(allocator);
                defer allocator.free(text);

                app_runtime.rememberTurn(prompt, text) catch |err| {
                    try stderr.print("nllclw: warning: failed to update memory: {s}\n", .{@errorName(err)});
                    try stderr.flush();
                };

                allocator.free(line);
            },
        }
    }

    return 0;
}

pub fn parse(line: []const u8) Command {
    const text = std.mem.trim(u8, line, &std.ascii.whitespace);
    if (text.len == 0) return .empty;
    if (std.mem.eql(u8, text, ":q") or
        std.mem.eql(u8, text, ":quit") or
        std.ascii.eqlIgnoreCase(text, "exit"))
    {
        return .quit;
    }
    return .{ .prompt = text };
}

fn readLineAlloc(allocator: Allocator, reader: *Io.Reader) !?[]u8 {
    const line = try reader.takeDelimiter('\n') orelse return null;
    const normalized = if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
    return try allocator.dupe(u8, normalized);
}

test "repl parser classifies empty input" {
    try std.testing.expectEqual(Command.empty, parse(" \r\n\t "));
}

test "repl parser classifies quit commands" {
    try std.testing.expectEqual(Command.quit, parse(":q"));
    try std.testing.expectEqual(Command.quit, parse(" :quit "));
    try std.testing.expectEqual(Command.quit, parse("EXIT"));
}

test "repl parser returns trimmed prompts" {
    const command = parse("  hello assistant  \n");
    try std.testing.expectEqualStrings("hello assistant", command.prompt);
}
