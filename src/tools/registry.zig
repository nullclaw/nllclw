const std = @import("std");
const chat = @import("../chat.zig");
const defaults = @import("../defaults.zig");
const text_policy = @import("../text_policy.zig");

const Allocator = std.mem.Allocator;

pub const default_max_rounds: usize = defaults.tool_max_rounds;
pub const default_output_max_bytes: usize = defaults.tool_output_max_bytes;

pub const RunError = Allocator.Error || error{
    InvalidToolArguments,
    ToolFailed,
    ToolOutputTooLarge,
    ToolTimedOut,
    UnknownTool,
};

pub const Handler = struct {
    definition: chat.ToolDefinition,
    ptr: *anyopaque,
    run_fn: *const fn (*anyopaque, Allocator, chat.ToolCall) RunError![]u8,
    mutates_state: bool = false,
    untrusted_output: bool = false,

    pub fn run(self: Handler, allocator: Allocator, call: chat.ToolCall) RunError![]u8 {
        return self.run_fn(self.ptr, allocator, call);
    }
};

pub const Executor = struct {
    ptr: *anyopaque,
    run_fn: *const fn (*anyopaque, Allocator, chat.ToolCall) RunError![]u8,

    pub fn run(self: Executor, allocator: Allocator, call: chat.ToolCall) RunError![]u8 {
        return self.run_fn(self.ptr, allocator, call);
    }
};

pub const Registry = struct {
    handlers: []const Handler,

    pub fn executor(self: *Registry) Executor {
        return .{
            .ptr = self,
            .run_fn = run,
        };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) RunError![]u8 {
        const self: *Registry = @ptrCast(@alignCast(ptr));
        for (self.handlers) |handler| {
            if (std.mem.eql(u8, handler.definition.name, call.name)) {
                return handler.run(allocator, call);
            }
        }
        return error.UnknownTool;
    }
};

pub fn definitions(allocator: Allocator, handlers: []const Handler) Allocator.Error![]chat.ToolDefinition {
    const out = try allocator.alloc(chat.ToolDefinition, handlers.len);
    for (handlers, out) |handler, *definition| definition.* = handler.definition;
    return out;
}

pub fn readOnlyHandlers(allocator: Allocator, handlers: []const Handler) Allocator.Error![]Handler {
    var count: usize = 0;
    for (handlers) |handler| {
        if (!handler.mutates_state) count += 1;
    }

    const out = try allocator.alloc(Handler, count);
    var index: usize = 0;
    for (handlers) |handler| {
        if (handler.mutates_state) continue;
        out[index] = handler;
        index += 1;
    }
    return out;
}

pub fn callProducesUntrusted(handlers: []const Handler, name: []const u8) bool {
    for (handlers) |handler| {
        if (std.mem.eql(u8, handler.definition.name, name)) return handler.untrusted_output;
    }
    return false;
}

pub fn runCall(allocator: Allocator, executor: Executor, call: chat.ToolCall) Allocator.Error![]u8 {
    const output = executor.run(allocator, call) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return std.fmt.allocPrint(allocator, "tool error: {s}", .{@errorName(err)});
    };
    errdefer allocator.free(output);
    if (!isValidToolOutput(output)) {
        allocator.free(output);
        return allocator.dupe(u8, "tool error: ToolFailed");
    }
    return output;
}

pub fn parseArgs(
    comptime T: type,
    allocator: Allocator,
    arguments: []const u8,
    options: std.json.ParseOptions,
) RunError!std.json.Parsed(T) {
    return std.json.parseFromSlice(T, allocator, arguments, options) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidToolArguments,
    };
}

fn isValidToolOutput(output: []const u8) bool {
    return text_policy.isMultilineText(output);
}

const FakeTool = struct {
    definition: chat.ToolDefinition,
    seen_name: ?[]u8 = null,

    fn deinit(self: *FakeTool, allocator: Allocator) void {
        if (self.seen_name) |name| allocator.free(name);
        self.* = undefined;
    }

    fn handler(self: *FakeTool) Handler {
        return .{
            .definition = self.definition,
            .ptr = self,
            .run_fn = run,
        };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) RunError![]u8 {
        const self: *FakeTool = @ptrCast(@alignCast(ptr));
        self.seen_name = try allocator.dupe(u8, call.name);
        return try allocator.dupe(u8, "done\n");
    }
};

const OomTool = struct {
    fn handler(self: *OomTool) Handler {
        return .{
            .definition = .{
                .name = "oom",
                .description = "return OutOfMemory",
                .parameters = .{ .properties = &.{} },
            },
            .ptr = self,
            .run_fn = run,
        };
    }

    fn run(_: *anyopaque, _: Allocator, _: chat.ToolCall) RunError![]u8 {
        return error.OutOfMemory;
    }
};

const BinaryTool = struct {
    fn handler(self: *BinaryTool) Handler {
        return .{
            .definition = .{
                .name = "binary",
                .description = "return invalid text",
                .parameters = .{ .properties = &.{} },
            },
            .ptr = self,
            .run_fn = run,
        };
    }

    fn run(_: *anyopaque, allocator: Allocator, _: chat.ToolCall) RunError![]u8 {
        return try allocator.dupe(u8, "bad\x00output");
    }
};

const ControlTool = struct {
    fn handler(self: *ControlTool) Handler {
        return .{
            .definition = .{
                .name = "control",
                .description = "return control bytes",
                .parameters = .{ .properties = &.{} },
            },
            .ptr = self,
            .run_fn = run,
        };
    }

    fn run(_: *anyopaque, allocator: Allocator, _: chat.ToolCall) RunError![]u8 {
        return try allocator.dupe(u8, "bad\x1boutput");
    }
};

test "registry dispatches by tool definition name" {
    var fake = FakeTool{
        .definition = .{
            .name = "fake",
            .description = "fake",
            .parameters = .{ .properties = &.{} },
        },
    };
    defer fake.deinit(std.testing.allocator);

    const handlers = [_]Handler{fake.handler()};
    var registry: Registry = .{ .handlers = &handlers };
    const output = try runCall(std.testing.allocator, registry.executor(), .{
        .id = "call_1",
        .name = "fake",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("fake", fake.seen_name.?);
    try std.testing.expectEqualStrings("done\n", output);
}

test "registry reports unknown tools as tool output" {
    var registry: Registry = .{ .handlers = &.{} };
    const output = try runCall(std.testing.allocator, registry.executor(), .{
        .id = "call_1",
        .name = "missing",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("tool error: UnknownTool", output);
}

test "registry propagates OutOfMemory instead of turning it into tool text" {
    var oom: OomTool = .{};
    const handlers = [_]Handler{oom.handler()};
    var registry: Registry = .{ .handlers = &handlers };

    try std.testing.expectError(error.OutOfMemory, runCall(std.testing.allocator, registry.executor(), .{
        .id = "call_1",
        .name = "oom",
        .arguments = "{}",
    }));
}

test "registry prevents invalid tool output from reaching the model" {
    var binary: BinaryTool = .{};
    const handlers = [_]Handler{binary.handler()};
    var registry: Registry = .{ .handlers = &handlers };

    const output = try runCall(std.testing.allocator, registry.executor(), .{
        .id = "call_1",
        .name = "binary",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("tool error: ToolFailed", output);

    var control: ControlTool = .{};
    const control_handlers = [_]Handler{control.handler()};
    var control_registry: Registry = .{ .handlers = &control_handlers };
    const control_output = try runCall(std.testing.allocator, control_registry.executor(), .{
        .id = "call_2",
        .name = "control",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(control_output);

    try std.testing.expectEqualStrings("tool error: ToolFailed", control_output);
}

test "argument parser preserves allocation failures" {
    const Args = struct {
        value: []const u8,
    };

    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            const parsed = try parseArgs(Args, allocator, "{\"value\":\"ok\"}", .{});
            defer parsed.deinit();
            try std.testing.expectEqualStrings("ok", parsed.value.value);
        }
    }.run, .{});
}

test "registry can filter mutating handlers after untrusted output" {
    var read: FakeTool = .{
        .definition = .{
            .name = "read",
            .description = "read",
            .parameters = .{ .properties = &.{} },
        },
    };
    defer read.deinit(std.testing.allocator);
    var write: FakeTool = .{
        .definition = .{
            .name = "write",
            .description = "write",
            .parameters = .{ .properties = &.{} },
        },
    };
    defer write.deinit(std.testing.allocator);

    const handlers = [_]Handler{
        read.handler(),
        .{
            .definition = write.definition,
            .ptr = &write,
            .run_fn = FakeTool.run,
            .mutates_state = true,
        },
    };
    const filtered = try readOnlyHandlers(std.testing.allocator, &handlers);
    defer std.testing.allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("read", filtered[0].definition.name);
}

test "registry reports whether a call produced untrusted output" {
    var web: FakeTool = .{
        .definition = .{
            .name = "web_search",
            .description = "web",
            .parameters = .{ .properties = &.{} },
        },
    };
    defer web.deinit(std.testing.allocator);
    const handlers = [_]Handler{.{
        .definition = web.definition,
        .ptr = &web,
        .run_fn = FakeTool.run,
        .untrusted_output = true,
    }};

    try std.testing.expect(callProducesUntrusted(&handlers, "web_search"));
    try std.testing.expect(!callProducesUntrusted(&handlers, "missing"));
}
