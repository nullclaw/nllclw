const std = @import("std");
const chat = @import("../chat.zig");
const config = @import("../config.zig");
const diagnostics = @import("../diagnostics.zig");
const memory = @import("../memory.zig");
const scheduler = @import("../scheduler.zig");
const tool = @import("./registry.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
pub const Scope = diagnostics.Scope;

const scope_parameter = [_]chat.ToolParameter{
    .{
        .name = "scope",
        .kind = .string,
        .description = "Diagnostic scope: quick, runtime, memory, rates, time, or all.",
    },
};

pub const definition: chat.ToolDefinition = .{
    .name = "get_diagnostics",
    .description = "Get local nllclw runtime diagnostics.",
    .parameters = .{ .properties = &scope_parameter },
};

pub const Client = struct {
    io: Io,
    cfg: config.RuntimeConfig,
    history_count: usize,
    output_max_bytes: usize,

    pub fn init(io: Io, cfg: config.RuntimeConfig, state: memory.State) Client {
        return initCount(io, cfg, state.transcript.entries.len);
    }

    pub fn initCount(io: Io, cfg: config.RuntimeConfig, history_count: usize) Client {
        return .{
            .io = io,
            .cfg = cfg,
            .history_count = history_count,
            .output_max_bytes = cfg.tools.output_max_bytes,
        };
    }

    pub fn handler(self: *Client) tool.Handler {
        return .{ .definition = definition, .ptr = self, .run_fn = run };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const self: *Client = @ptrCast(@alignCast(ptr));
        const scope = try parseScope(allocator, call.arguments);
        const text = diagnostics.format(allocator, self.cfg, self.history_count, scope, scheduler.currentUnixSeconds(self.io)) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.ToolFailed,
            };
        };
        errdefer allocator.free(text);
        if (text.len > self.output_max_bytes) return error.ToolOutputTooLarge;
        return text;
    }
};

const Args = struct {
    scope: []const u8 = "quick",
};

fn parseScope(allocator: Allocator, arguments: []const u8) tool.RunError!Scope {
    const parsed = try tool.parseArgs(Args, allocator, arguments, .{});
    defer parsed.deinit();
    return diagnostics.parseScopeName(parsed.value.scope) orelse error.InvalidToolArguments;
}

test "diagnostics tool enforces the configured output cap" {
    var client = Client.initCount(std.testing.io, .{
        .completion = .{
            .provider = .openai,
            .api_key = "secret",
            .model = "model-name-that-makes-the-quick-report-long",
        },
        .tools = .{ .output_max_bytes = 32 },
    }, 0);

    try std.testing.expectError(error.ToolOutputTooLarge, client.handler().run(std.testing.allocator, .{
        .id = "call_diag",
        .name = "get_diagnostics",
        .arguments = "{}",
    }));
    try std.testing.expectError(error.InvalidToolArguments, parseScope(
        std.testing.allocator,
        "{\"scope\":\"quick\",\"unknown\":true}",
    ));
}
