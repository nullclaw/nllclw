const std = @import("std");
const builtin = @import("builtin");
const chat = @import("../chat.zig");
const text_policy = @import("../text_policy.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;

pub const name = "shell_exec";
pub const max_command_bytes: usize = 4096;

const parameters = [_]chat.ToolParameter{
    .{
        .name = "command",
        .kind = .string,
        .description = "Command to run with the platform shell.",
    },
};

pub const definition: chat.ToolDefinition = .{
    .name = name,
    .description = "Dangerous: run a platform shell command in the current working directory and return output plus exit status.",
    .parameters = .{
        .properties = &parameters,
        .required = &.{"command"},
    },
};

pub const Client = struct {
    io: std.Io,
    output_max_bytes: usize,
    timeout_ms: u64,

    pub fn init(io: std.Io, output_max_bytes: usize, timeout_ms: u64) Client {
        return .{
            .io = io,
            .output_max_bytes = output_max_bytes,
            .timeout_ms = timeout_ms,
        };
    }

    pub fn handler(self: *Client) tool.Handler {
        return .{
            .definition = definition,
            .ptr = self,
            .run_fn = run,
            .mutates_state = true,
        };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const command = try parseCommand(allocator, call);
        defer allocator.free(command);

        const result = std.process.run(allocator, self.io, .{
            .argv = shellArgv(command),
            .stdout_limit = .limited(self.output_max_bytes),
            .stderr_limit = .limited(self.output_max_bytes),
            .timeout = .{ .duration = .{
                .raw = .fromMilliseconds(@intCast(self.timeout_ms)),
                .clock = .awake,
            } },
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.StreamTooLong => return error.ToolOutputTooLarge,
            error.Timeout => return error.ToolTimedOut,
            else => return error.ToolFailed,
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const status = try formatTerm(allocator, result.term);
        defer allocator.free(status);
        return formatResultLimited(allocator, status, result.stdout, result.stderr, self.output_max_bytes);
    }
};

fn parseCommand(allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
    const ShellArgs = struct {
        command: []const u8 = "",
    };

    const parsed = try tool.parseArgs(ShellArgs, allocator, call.arguments, .{});
    defer parsed.deinit();

    const command = std.mem.trim(u8, parsed.value.command, &std.ascii.whitespace);
    if (command.len == 0) return error.InvalidToolArguments;
    if (command.len > max_command_bytes) return error.InvalidToolArguments;
    if (!text_policy.isMultilineText(command)) return error.InvalidToolArguments;
    return try allocator.dupe(u8, command);
}

fn formatResult(
    allocator: Allocator,
    status: []const u8,
    stdout: []const u8,
    stderr: []const u8,
) tool.RunError![]u8 {
    return formatResultLimited(allocator, status, stdout, stderr, std.math.maxInt(usize));
}

fn formatResultLimited(
    allocator: Allocator,
    status: []const u8,
    stdout: []const u8,
    stderr: []const u8,
    limit: usize,
) tool.RunError![]u8 {
    if (!isTextOutput(stdout) or !isTextOutput(stderr)) return error.ToolFailed;

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    try appendLimited(&out, "status: ", limit);
    try appendLimited(&out, status, limit);
    try appendLimited(&out, "\nstdout:\n", limit);
    try appendLimited(&out, stdout, limit);
    if (stdout.len == 0 or stdout[stdout.len - 1] != '\n') try appendLimited(&out, "\n", limit);
    try appendLimited(&out, "stderr:\n", limit);
    try appendLimited(&out, stderr, limit);
    if (stderr.len == 0 or stderr[stderr.len - 1] != '\n') try appendLimited(&out, "\n", limit);

    return out.toOwnedSlice() catch error.OutOfMemory;
}

fn isTextOutput(bytes: []const u8) bool {
    return text_policy.isMultilineText(bytes);
}

fn appendLimited(out: *std.Io.Writer.Allocating, bytes: []const u8, limit: usize) tool.RunError!void {
    const next_len = std.math.add(usize, out.written().len, bytes.len) catch return error.ToolOutputTooLarge;
    if (next_len > limit) return error.ToolOutputTooLarge;
    out.writer.writeAll(bytes) catch return error.OutOfMemory;
}

fn shellArgv(command: []const u8) []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/C", command },
        else => &.{ "sh", "-c", command },
    };
}

fn formatTerm(allocator: Allocator, term: std.process.Child.Term) Allocator.Error![]u8 {
    return switch (term) {
        .exited => |code| std.fmt.allocPrint(allocator, "exited {d}", .{code}),
        .signal => |signal| formatSignalTerm(allocator, "signal", signal),
        .stopped => |signal| formatSignalTerm(allocator, "stopped", signal),
        .unknown => |status| std.fmt.allocPrint(allocator, "unknown {d}", .{status}),
    };
}

fn formatSignalTerm(allocator: Allocator, prefix: []const u8, signal: anytype) Allocator.Error![]u8 {
    if (@TypeOf(signal) == void) return allocator.dupe(u8, prefix);
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ prefix, @tagName(signal) });
}

test "parseCommand trims and rejects invalid arguments" {
    const command = try parseCommand(std.testing.allocator, .{
        .id = "call_1",
        .name = name,
        .arguments = "{\"command\":\" pwd \"}",
    });
    defer std.testing.allocator.free(command);
    try std.testing.expectEqualStrings("pwd", command);

    try std.testing.expectError(error.InvalidToolArguments, parseCommand(std.testing.allocator, .{
        .id = "call_2",
        .name = name,
        .arguments = "{}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, parseCommand(std.testing.allocator, .{
        .id = "call_3",
        .name = name,
        .arguments = "{\"command\":\"bad\\u0000command\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, parseCommand(std.testing.allocator, .{
        .id = "call_4",
        .name = name,
        .arguments = "{\"command\":\"bad\\u001bcommand\"}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, parseCommand(std.testing.allocator, .{
        .id = "call_unknown",
        .name = name,
        .arguments = "{\"command\":\"pwd\",\"unknown\":true}",
    }));

    const long_command = try std.testing.allocator.alloc(u8, max_command_bytes + 1);
    defer std.testing.allocator.free(long_command);
    @memset(long_command, 'a');
    const long_args = try std.fmt.allocPrint(std.testing.allocator, "{{\"command\":\"{s}\"}}", .{long_command});
    defer std.testing.allocator.free(long_args);
    try std.testing.expectError(error.InvalidToolArguments, parseCommand(std.testing.allocator, .{
        .id = "call_5",
        .name = name,
        .arguments = long_args,
    }));
}

test "formatResult includes status stdout and stderr sections" {
    const text = try formatResult(std.testing.allocator, "exited 0", "ok", "");
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(
        "status: exited 0\nstdout:\nok\nstderr:\n\n",
        text,
    );
}

test "formatResult enforces combined output cap" {
    try std.testing.expectError(
        error.ToolOutputTooLarge,
        formatResultLimited(std.testing.allocator, "exited 0", "1234567890", "abcdefghij", 32),
    );
}

test "formatResult rejects non-text process output" {
    try std.testing.expectError(
        error.ToolFailed,
        formatResultLimited(std.testing.allocator, "exited 0", "bad\xff", "", 4096),
    );
    try std.testing.expectError(
        error.ToolFailed,
        formatResultLimited(std.testing.allocator, "exited 0", "bad\x00", "", 4096),
    );
    try std.testing.expectError(
        error.ToolFailed,
        formatResultLimited(std.testing.allocator, "exited 0", "bad\x1boutput", "", 4096),
    );
}

test "formats process termination" {
    const text = try formatTerm(std.testing.allocator, .{ .exited = 7 });
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("exited 7", text);
}
