const std = @import("std");
const agent_types = @import("./agent_types.zig");
const chat = @import("./chat.zig");
const http = @import("./ports/http.zig");
const tool = @import("./tools/registry.zig");

const Allocator = std.mem.Allocator;

pub const FakeHttp = struct {
    status: http.StatusCode = 200,
    body: []const u8,
    seen_url: ?[]u8 = null,
    seen_body: ?[]u8 = null,
    seen_auth: ?[]u8 = null,

    pub fn deinit(self: *FakeHttp, allocator: Allocator) void {
        if (self.seen_url) |value| allocator.free(value);
        if (self.seen_body) |value| allocator.free(value);
        if (self.seen_auth) |value| allocator.free(value);
        self.* = undefined;
    }

    pub fn client(self: *FakeHttp) http.Client {
        return .{
            .ptr = self,
            .post_json = postJson,
        };
    }

    fn postJson(ptr: *anyopaque, allocator: Allocator, request: http.Request) http.Error!http.Response {
        const self: *FakeHttp = @ptrCast(@alignCast(ptr));
        self.seen_url = try allocator.dupe(u8, request.url);
        self.seen_body = try allocator.dupe(u8, request.body);
        if (headerValue(request.headers, "authorization")) |value| {
            self.seen_auth = try allocator.dupe(u8, value);
        }

        return .{
            .status = self.status,
            .body = try allocator.dupe(u8, self.body),
        };
    }
};

pub const StreamHttp = struct {
    status: http.StatusCode = 200,
    body: []const u8,
    seen_body: ?[]u8 = null,
    stream_calls: usize = 0,

    pub fn deinit(self: *StreamHttp, allocator: Allocator) void {
        if (self.seen_body) |value| allocator.free(value);
        self.* = undefined;
    }

    pub fn client(self: *StreamHttp) http.Client {
        return .{
            .ptr = self,
            .post_json = postJson,
            .post_json_stream = postJsonStream,
        };
    }

    fn postJson(_: *anyopaque, _: Allocator, _: http.Request) http.Error!http.Response {
        return error.RequestFailed;
    }

    fn postJsonStream(
        ptr: *anyopaque,
        allocator: Allocator,
        request: http.Request,
        callback: http.StreamCallback,
    ) http.Error!http.Response {
        const self: *StreamHttp = @ptrCast(@alignCast(ptr));
        self.stream_calls += 1;
        self.seen_body = try allocator.dupe(u8, request.body);
        if (self.status == 200) try callback.write(self.body);
        return .{
            .status = self.status,
            .body = try allocator.dupe(u8, self.body),
        };
    }
};

pub const CollectSink = struct {
    allocator: Allocator,
    chunks: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *CollectSink, allocator: Allocator) void {
        self.chunks.deinit(allocator);
    }

    pub fn sink(self: *CollectSink) agent_types.StreamSink {
        return .{
            .ptr = self,
            .write_fn = write,
        };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) agent_types.StreamError!void {
        const self: *CollectSink = @ptrCast(@alignCast(ptr));
        try self.chunks.appendSlice(self.allocator, bytes);
    }
};

pub const FailingSink = struct {
    writes: usize = 0,

    pub fn sink(self: *FailingSink) agent_types.StreamSink {
        return .{
            .ptr = self,
            .write_fn = write,
        };
    }

    fn write(ptr: *anyopaque, _: []const u8) agent_types.StreamError!void {
        const self: *FailingSink = @ptrCast(@alignCast(ptr));
        self.writes += 1;
        return error.WriteFailed;
    }
};

pub const ToolHttp = struct {
    calls: usize = 0,
    seen_first_body: ?[]u8 = null,
    seen_second_body: ?[]u8 = null,

    pub fn deinit(self: *ToolHttp, allocator: Allocator) void {
        if (self.seen_first_body) |value| allocator.free(value);
        if (self.seen_second_body) |value| allocator.free(value);
        self.* = undefined;
    }

    pub fn client(self: *ToolHttp) http.Client {
        return .{
            .ptr = self,
            .post_json = postJson,
        };
    }

    fn postJson(ptr: *anyopaque, allocator: Allocator, request: http.Request) http.Error!http.Response {
        const self: *ToolHttp = @ptrCast(@alignCast(ptr));
        self.calls += 1;
        if (self.calls == 1) {
            self.seen_first_body = try allocator.dupe(u8, request.body);
            return .{
                .status = 200,
                .body = try allocator.dupe(u8,
                    \\{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"inspect_cwd","arguments":"{\"path\":\".\"}"}}]}}]}
                ),
            };
        }

        self.seen_second_body = try allocator.dupe(u8, request.body);
        return .{
            .status = 200,
            .body = try allocator.dupe(u8, "{\"choices\":[{\"message\":{\"content\":\"tool done\"}}]}"),
        };
    }
};

pub const FakeTool = struct {
    seen_path: ?[]u8 = null,

    pub fn deinit(self: *FakeTool, allocator: Allocator) void {
        if (self.seen_path) |value| allocator.free(value);
        self.* = undefined;
    }

    pub fn handler(self: *FakeTool) tool.Handler {
        return .{
            .definition = .{
                .name = "inspect_cwd",
                .description = "Return the current workspace path for tests.",
                .parameters = .{
                    .properties = &.{.{ .name = "path", .kind = .string }},
                    .required = &.{"path"},
                },
            },
            .ptr = self,
            .run_fn = run,
        };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, call: chat.ToolCall) tool.RunError![]u8 {
        const Args = struct {
            path: []const u8 = "",
        };

        const self: *FakeTool = @ptrCast(@alignCast(ptr));
        const parsed = std.json.parseFromSlice(Args, allocator, call.arguments, .{
            .ignore_unknown_fields = true,
        }) catch return error.InvalidToolArguments;
        defer parsed.deinit();

        if (parsed.value.path.len == 0) return error.InvalidToolArguments;
        self.seen_path = try allocator.dupe(u8, parsed.value.path);
        return try allocator.dupe(u8, "cwd: /repo\n");
    }
};

pub const UntrustedToolHttp = struct {
    calls: usize = 0,
    same_batch: bool = false,
    seen_second_body: ?[]u8 = null,

    pub fn deinit(self: *UntrustedToolHttp, allocator: Allocator) void {
        if (self.seen_second_body) |value| allocator.free(value);
        self.* = undefined;
    }

    pub fn client(self: *UntrustedToolHttp) http.Client {
        return .{
            .ptr = self,
            .post_json = postJson,
        };
    }

    fn postJson(ptr: *anyopaque, allocator: Allocator, request: http.Request) http.Error!http.Response {
        const self: *UntrustedToolHttp = @ptrCast(@alignCast(ptr));
        self.calls += 1;
        switch (self.calls) {
            1 => {
                const body =
                    if (self.same_batch)
                        \\{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_web","type":"function","function":{"name":"web_search","arguments":"{}"}},{"id":"call_write","type":"function","function":{"name":"write_file","arguments":"{}"}}]}}]}
                    else
                        \\{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_web","type":"function","function":{"name":"web_search","arguments":"{}"}}]}}]}
                    ;
                return .{ .status = 200, .body = try allocator.dupe(u8, body) };
            },
            2 => {
                self.seen_second_body = try allocator.dupe(u8, request.body);
                if (self.same_batch) {
                    return .{
                        .status = 200,
                        .body = try allocator.dupe(u8, "{\"choices\":[{\"message\":{\"content\":\"safe final\"}}]}"),
                    };
                }
                return .{
                    .status = 200,
                    .body = try allocator.dupe(u8,
                        \\{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_write","type":"function","function":{"name":"write_file","arguments":"{}"}}]}}]}
                    ),
                };
            },
            else => return .{
                .status = 200,
                .body = try allocator.dupe(u8, "{\"choices\":[{\"message\":{\"content\":\"safe final\"}}]}"),
            },
        }
    }
};

pub const CountingTool = struct {
    name: []const u8,
    output: []const u8,
    calls: usize = 0,

    pub fn handler(self: *CountingTool, mutates_state: bool, untrusted_output: bool) tool.Handler {
        return .{
            .definition = .{
                .name = self.name,
                .description = "count calls",
                .parameters = .{ .properties = &.{} },
            },
            .ptr = self,
            .run_fn = run,
            .mutates_state = mutates_state,
            .untrusted_output = untrusted_output,
        };
    }

    fn run(ptr: *anyopaque, allocator: Allocator, _: chat.ToolCall) tool.RunError![]u8 {
        const self: *CountingTool = @ptrCast(@alignCast(ptr));
        self.calls += 1;
        return try allocator.dupe(u8, self.output);
    }
};

fn headerValue(headers: []const http.Header, name: []const u8) ?[]const u8 {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}
