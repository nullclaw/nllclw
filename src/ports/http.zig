const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const StatusCode = u16;
pub const Method = enum {
    get,
    post,
};

pub const Error = Allocator.Error || error{
    RequestFailed,
    StreamCallbackFailed,
};

pub const Request = struct {
    url: []const u8,
    method: Method = .post,
    headers: []const Header = &.{},
    body: []const u8,
};

pub const Response = struct {
    status: StatusCode,
    body: []u8,

    pub fn deinit(self: *Response, allocator: Allocator) void {
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const StreamCallback = struct {
    ptr: *anyopaque,
    write_fn: *const fn (*anyopaque, []const u8) Error!void,

    pub fn write(self: StreamCallback, bytes: []const u8) Error!void {
        return self.write_fn(self.ptr, bytes);
    }
};

pub const Client = struct {
    ptr: *anyopaque,
    post_json: *const fn (*anyopaque, Allocator, Request) Error!Response,
    post_json_stream: ?*const fn (*anyopaque, Allocator, Request, StreamCallback) Error!Response = null,

    pub fn postJson(self: Client, allocator: Allocator, request: Request) Error!Response {
        return self.post_json(self.ptr, allocator, request);
    }

    pub fn postJsonStream(
        self: Client,
        allocator: Allocator,
        request: Request,
        callback: StreamCallback,
    ) Error!Response {
        if (self.post_json_stream) |stream_fn| {
            return stream_fn(self.ptr, allocator, request, callback);
        }

        var response = try self.postJson(allocator, request);
        errdefer response.deinit(allocator);
        if (response.status == 200) try callback.write(response.body);
        return response;
    }
};

const FakeClient = struct {
    status: StatusCode,
    body: []const u8,

    fn client(self: *FakeClient) Client {
        return .{
            .ptr = self,
            .post_json = postJson,
        };
    }

    fn postJson(ptr: *anyopaque, allocator: Allocator, _: Request) Error!Response {
        const self: *FakeClient = @ptrCast(@alignCast(ptr));
        return .{
            .status = self.status,
            .body = try allocator.dupe(u8, self.body),
        };
    }
};

const CaptureCallback = struct {
    bytes: std.Io.Writer.Allocating,

    fn init(allocator: Allocator) CaptureCallback {
        return .{ .bytes = std.Io.Writer.Allocating.init(allocator) };
    }

    fn deinit(self: *CaptureCallback) void {
        self.bytes.deinit();
    }

    fn callback(self: *CaptureCallback) StreamCallback {
        return .{
            .ptr = self,
            .write_fn = write,
        };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) Error!void {
        const self: *CaptureCallback = @ptrCast(@alignCast(ptr));
        self.bytes.writer.writeAll(bytes) catch return error.OutOfMemory;
    }
};

test "stream fallback writes successful non-streaming body to callback" {
    var fake = FakeClient{ .status = 200, .body = "hello" };
    var capture = CaptureCallback.init(std.testing.allocator);
    defer capture.deinit();

    var response = try fake.client().postJsonStream(std.testing.allocator, .{
        .url = "https://example.test",
        .body = "{}",
    }, capture.callback());
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(StatusCode, 200), response.status);
    try std.testing.expectEqualStrings("hello", response.body);
    try std.testing.expectEqualStrings("hello", capture.bytes.written());
}

test "stream fallback does not call callback for HTTP failures" {
    var fake = FakeClient{ .status = 500, .body = "bad" };
    var capture = CaptureCallback.init(std.testing.allocator);
    defer capture.deinit();

    var response = try fake.client().postJsonStream(std.testing.allocator, .{
        .url = "https://example.test",
        .body = "{}",
    }, capture.callback());
    defer response.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(StatusCode, 500), response.status);
    try std.testing.expectEqualStrings("bad", response.body);
    try std.testing.expectEqualStrings("", capture.bytes.written());
}

test "stream fallback preserves callback failures" {
    const FailingCallback = struct {
        fn callback(self: *@This()) StreamCallback {
            return .{
                .ptr = self,
                .write_fn = write,
            };
        }

        fn write(_: *anyopaque, _: []const u8) Error!void {
            return error.StreamCallbackFailed;
        }
    };

    var fake = FakeClient{ .status = 200, .body = "hello" };
    var failing: FailingCallback = .{};

    try std.testing.expectError(error.StreamCallbackFailed, fake.client().postJsonStream(std.testing.allocator, .{
        .url = "https://example.test",
        .body = "{}",
    }, failing.callback()));
}
