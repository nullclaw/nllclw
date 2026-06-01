const std = @import("std");
const chat = @import("./chat.zig");
const defaults = @import("./defaults.zig");
const http = @import("./ports/http.zig");
const tool = @import("./tools/registry.zig");

const Allocator = std.mem.Allocator;

pub const Diagnostic = struct {
    status: ?http.StatusCode = null,
    message: ?[]u8 = null,
    body: ?[]u8 = null,

    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        if (self.message) |message| allocator.free(message);
        if (self.body) |body| allocator.free(body);
        self.* = .{};
    }
};

pub const ToolOptions = struct {
    enabled: bool = false,
    max_rounds: usize = defaults.tool_max_rounds,
    handlers: []const tool.Handler = &.{},
};

pub const StreamError = Allocator.Error || std.Io.Writer.Error;

pub const StreamSink = struct {
    ptr: *anyopaque,
    write_fn: *const fn (*anyopaque, []const u8) StreamError!void,

    pub fn write(self: StreamSink, bytes: []const u8) StreamError!void {
        return self.write_fn(self.ptr, bytes);
    }
};

pub const CompleteOptions = struct {
    history: []const chat.RequestMessage = &.{},
    tools: ToolOptions = .{},
    stream_sink: ?StreamSink = null,
    system_prompt: ?[]const u8 = null,
};
