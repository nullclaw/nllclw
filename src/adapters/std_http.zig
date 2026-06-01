const std = @import("std");
const http = @import("../ports/http.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_response_bytes = 2 * 1024 * 1024;

pub const Client = struct {
    inner: std.http.Client,

    pub fn init(allocator: Allocator, io: Io) Client {
        return .{
            .inner = .{
                .allocator = allocator,
                .io = io,
            },
        };
    }

    pub fn deinit(self: *Client) void {
        self.inner.deinit();
        self.* = undefined;
    }

    pub fn httpClient(self: *Client) http.Client {
        return .{
            .ptr = self,
            .post_json = postJson,
            .post_json_stream = postJsonStream,
        };
    }

    fn postJson(ptr: *anyopaque, allocator: Allocator, request: http.Request) http.Error!http.Response {
        const self: *Client = @ptrCast(@alignCast(ptr));

        validateHeaders(request.headers) catch return error.RequestFailed;
        var body_writer = CappedBodyWriter.init(allocator, max_response_bytes);
        defer body_writer.deinit();

        const authorization = headerValue(request.headers, "authorization");
        const content_type = headerValue(request.headers, "content-type");
        const user_agent = headerValue(request.headers, "user-agent");
        const extra_headers = try collectExtraHeaders(allocator, request.headers);
        defer if (extra_headers.len != 0) allocator.free(extra_headers);

        const result = self.inner.fetch(.{
            .location = .{ .url = request.url },
            .method = fetchMethod(request.method),
            .payload = fetchPayload(request),
            .headers = .{
                .authorization = if (authorization) |value| .{ .override = value } else .omit,
                .content_type = if (content_type) |value| .{ .override = value } else .omit,
                .user_agent = if (user_agent) |value| .{ .override = value } else .omit,
            },
            .extra_headers = extra_headers,
            .response_writer = &body_writer.writer,
        }) catch |err| {
            if (body_writer.err) |stored| return stored;
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.RequestFailed,
            };
        };

        return .{
            .status = @intFromEnum(result.status),
            .body = try body_writer.takeBody(),
        };
    }

    fn postJsonStream(
        ptr: *anyopaque,
        allocator: Allocator,
        request: http.Request,
        callback: http.StreamCallback,
    ) http.Error!http.Response {
        const self: *Client = @ptrCast(@alignCast(ptr));

        validateHeaders(request.headers) catch return error.RequestFailed;
        const authorization = headerValue(request.headers, "authorization");
        const content_type = headerValue(request.headers, "content-type");
        const user_agent = headerValue(request.headers, "user-agent");
        const extra_headers = try collectExtraHeaders(allocator, request.headers);
        defer if (extra_headers.len != 0) allocator.free(extra_headers);

        const uri = std.Uri.parse(request.url) catch return error.RequestFailed;
        const payload = fetchPayload(request);
        const redirect_behavior: std.http.Client.Request.RedirectBehavior = if (payload == null)
            std.http.Client.Request.RedirectBehavior.init(3)
        else
            .unhandled;

        var std_request = self.inner.request(fetchMethod(request.method), uri, .{
            .redirect_behavior = redirect_behavior,
            .headers = .{
                .authorization = if (authorization) |value| .{ .override = value } else .omit,
                .content_type = if (content_type) |value| .{ .override = value } else .omit,
                .user_agent = if (user_agent) |value| .{ .override = value } else .omit,
            },
            .extra_headers = extra_headers,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.RequestFailed,
        };
        defer std_request.deinit();

        if (payload) |body| {
            std_request.transfer_encoding = .{ .content_length = body.len };
            var body_writer = std_request.sendBodyUnflushed(&.{}) catch return error.RequestFailed;
            body_writer.writer.writeAll(body) catch return error.RequestFailed;
            body_writer.end() catch return error.RequestFailed;
            const connection = std_request.connection orelse return error.RequestFailed;
            connection.flush() catch return error.RequestFailed;
        } else {
            std_request.sendBodiless() catch return error.RequestFailed;
        }

        const redirect_buffer: []u8 = if (redirect_behavior == .unhandled) &.{} else try allocator.alloc(u8, 8 * 1024);
        defer if (redirect_behavior != .unhandled) allocator.free(redirect_buffer);

        var response = std_request.receiveHead(redirect_buffer) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.RequestFailed,
        };
        const status_code: u16 = @intFromEnum(response.head.status);

        var stream_writer = StreamingResponseWriter.init(allocator, callback, status_code == 200);
        errdefer stream_writer.deinit();

        const decompress_buffer = try allocDecompressBuffer(allocator, response.head.content_encoding);
        defer freeDecompressBuffer(allocator, response.head.content_encoding, decompress_buffer);

        var transfer_buffer: [64]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

        _ = reader.streamRemaining(&stream_writer.writer) catch |err| switch (err) {
            error.WriteFailed => return stream_writer.err orelse error.RequestFailed,
            else => return error.RequestFailed,
        };

        return .{
            .status = status_code,
            .body = try stream_writer.takeBody(),
        };
    }
};

const CappedBodyWriter = struct {
    body: Io.Writer.Allocating,
    writer: Io.Writer,
    max_bytes: usize,
    err: ?http.Error = null,
    body_taken: bool = false,

    fn init(allocator: Allocator, max_bytes: usize) CappedBodyWriter {
        return .{
            .body = Io.Writer.Allocating.init(allocator),
            .writer = .{
                .buffer = &.{},
                .vtable = &.{ .drain = drain },
            },
            .max_bytes = max_bytes,
        };
    }

    fn deinit(self: *CappedBodyWriter) void {
        if (!self.body_taken) self.body.deinit();
        self.* = undefined;
    }

    fn takeBody(self: *CappedBodyWriter) Allocator.Error![]u8 {
        const body = try self.body.toOwnedSlice();
        self.body_taken = true;
        return body;
    }

    fn drain(writer: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *CappedBodyWriter = @alignCast(@fieldParentPtr("writer", writer));

        if (writer.end != 0) {
            self.append(writer.buffered()) catch |err| {
                self.err = err;
                return error.WriteFailed;
            };
            writer.end = 0;
        }

        if (data.len == 0) return 0;

        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            self.append(bytes) catch |err| {
                self.err = err;
                return error.WriteFailed;
            };
            consumed += bytes.len;
        }

        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            self.append(pattern) catch |err| {
                self.err = err;
                return error.WriteFailed;
            };
            consumed += pattern.len;
        }
        return consumed;
    }

    fn append(self: *CappedBodyWriter, bytes: []const u8) http.Error!void {
        if (bytes.len == 0) return;

        const next_len = std.math.add(usize, self.body.written().len, bytes.len) catch return error.RequestFailed;
        if (next_len > self.max_bytes) return error.RequestFailed;

        self.body.writer.writeAll(bytes) catch return error.OutOfMemory;
    }
};

fn fetchMethod(method: http.Method) std.http.Method {
    return switch (method) {
        .get => .GET,
        .post => .POST,
    };
}

fn fetchPayload(request: http.Request) ?[]const u8 {
    return switch (request.method) {
        .get => null,
        .post => request.body,
    };
}

const StreamingResponseWriter = struct {
    callback: http.StreamCallback,
    body: Io.Writer.Allocating,
    writer: Io.Writer,
    forward_to_callback: bool,
    err: ?http.Error = null,
    body_taken: bool = false,

    fn init(allocator: Allocator, callback: http.StreamCallback, forward_to_callback: bool) StreamingResponseWriter {
        return .{
            .callback = callback,
            .body = Io.Writer.Allocating.init(allocator),
            .writer = .{
                .buffer = &.{},
                .vtable = &.{ .drain = drain },
            },
            .forward_to_callback = forward_to_callback,
        };
    }

    fn deinit(self: *StreamingResponseWriter) void {
        if (!self.body_taken) self.body.deinit();
        self.* = undefined;
    }

    fn takeBody(self: *StreamingResponseWriter) Allocator.Error![]u8 {
        const body = try self.body.toOwnedSlice();
        self.body_taken = true;
        return body;
    }

    fn drain(writer: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *StreamingResponseWriter = @alignCast(@fieldParentPtr("writer", writer));

        if (writer.end != 0) {
            self.writeBytes(writer.buffered()) catch |err| {
                self.err = err;
                return error.WriteFailed;
            };
            writer.end = 0;
        }

        if (data.len == 0) return 0;

        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            self.writeBytes(bytes) catch |err| {
                self.err = err;
                return error.WriteFailed;
            };
            consumed += bytes.len;
        }

        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            self.writeBytes(pattern) catch |err| {
                self.err = err;
                return error.WriteFailed;
            };
            consumed += pattern.len;
        }
        return consumed;
    }

    fn writeBytes(self: *StreamingResponseWriter, bytes: []const u8) http.Error!void {
        if (bytes.len == 0) return;

        const next_len = std.math.add(usize, self.body.written().len, bytes.len) catch return error.RequestFailed;
        if (next_len > max_response_bytes) return error.RequestFailed;

        self.body.writer.writeAll(bytes) catch return error.OutOfMemory;
        if (self.forward_to_callback) try self.callback.write(bytes);
    }
};

fn allocDecompressBuffer(allocator: Allocator, content_encoding: std.http.ContentEncoding) Allocator.Error![]u8 {
    return switch (content_encoding) {
        .identity => &.{},
        .zstd => try allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => &.{},
    };
}

fn freeDecompressBuffer(allocator: Allocator, content_encoding: std.http.ContentEncoding, buffer: []u8) void {
    switch (content_encoding) {
        .identity, .compress => {},
        .zstd, .deflate, .gzip => allocator.free(buffer),
    }
}

fn headerValue(headers: []const http.Header, name: []const u8) ?[]const u8 {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}

fn collectExtraHeaders(allocator: Allocator, headers: []const http.Header) Allocator.Error![]std.http.Header {
    var out: std.ArrayList(std.http.Header) = .empty;
    errdefer out.deinit(allocator);

    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization")) continue;
        if (std.ascii.eqlIgnoreCase(header.name, "content-type")) continue;
        if (std.ascii.eqlIgnoreCase(header.name, "user-agent")) continue;
        try out.append(allocator, .{ .name = header.name, .value = header.value });
    }

    return out.toOwnedSlice(allocator);
}

fn validateHeaders(headers: []const http.Header) error{InvalidHeader}!void {
    for (headers) |header| {
        if (header.name.len == 0) return error.InvalidHeader;
        for (header.name) |byte| {
            if (!isHeaderNameByte(byte)) return error.InvalidHeader;
        }
        for (header.value) |byte| {
            if (!isHeaderValueByte(byte)) return error.InvalidHeader;
        }
    }
}

fn isHeaderNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or switch (byte) {
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
        else => false,
    };
}

fn isHeaderValueByte(byte: u8) bool {
    return byte >= ' ' and byte != 0x7f;
}

test "collects only non-standard headers as extras" {
    const extras = try collectExtraHeaders(std.testing.allocator, &.{
        .{ .name = "Authorization", .value = "Bearer key" },
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "HTTP-Referer", .value = "https://example.test" },
    });
    defer std.testing.allocator.free(extras);

    try std.testing.expectEqual(@as(usize, 1), extras.len);
    try std.testing.expectEqualStrings("HTTP-Referer", extras[0].name);
}

test "validates headers before handing them to std.http" {
    try validateHeaders(&.{
        .{ .name = "Authorization", .value = "Bearer key" },
        .{ .name = "X-Test", .value = "ok" },
    });

    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "", .value = "ok" }}));
    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "Bad:Name", .value = "ok" }}));
    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "Bad Name", .value = "ok" }}));
    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "X-Test", .value = "bad\r\nX-Injected: 1" }}));
    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "X-Test", .value = "bad\x00" }}));
    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "X-Test", .value = "bad\x1f" }}));
    try std.testing.expectError(error.InvalidHeader, validateHeaders(&.{.{ .name = "X-Test", .value = "bad\x7f" }}));
}

test "capped body writer owns exact response bytes" {
    var body_writer = CappedBodyWriter.init(std.testing.allocator, 8);
    defer body_writer.deinit();

    try body_writer.writer.writeAll("abc");
    try body_writer.writer.writeAll("def");
    try body_writer.writer.writeAll("!!");

    const body = try body_writer.takeBody();
    defer std.testing.allocator.free(body);

    try std.testing.expectEqualStrings("abcdef!!", body);
}

test "capped body writer records response overflow" {
    var body_writer = CappedBodyWriter.init(std.testing.allocator, 5);
    defer body_writer.deinit();

    try body_writer.writer.writeAll("abc");
    try std.testing.expectError(error.WriteFailed, body_writer.writer.writeAll("def"));
    try std.testing.expectEqual(error.RequestFailed, body_writer.err.?);
}

test "capped body writer cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var body_writer = CappedBodyWriter.init(allocator, 32);
            defer body_writer.deinit();

            body_writer.writer.writeAll("response") catch |err| {
                if (body_writer.err) |stored| return stored;
                return err;
            };
            const body = try body_writer.takeBody();
            defer allocator.free(body);
            try std.testing.expectEqualStrings("response", body);
        }
    }.run, .{});
}

test "streaming response writer forwards chunks and captures body" {
    const Fake = struct {
        out: Io.Writer.Allocating,

        fn init(allocator: Allocator) @This() {
            return .{ .out = Io.Writer.Allocating.init(allocator) };
        }

        fn deinit(self: *@This()) void {
            self.out.deinit();
        }

        fn callback(self: *@This()) http.StreamCallback {
            return .{
                .ptr = self,
                .write_fn = write,
            };
        }

        fn write(ptr: *anyopaque, bytes: []const u8) http.Error!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.out.writer.writeAll(bytes) catch return error.OutOfMemory;
        }
    };

    var fake = Fake.init(std.testing.allocator);
    defer fake.deinit();

    var stream_writer = StreamingResponseWriter.init(std.testing.allocator, fake.callback(), true);
    defer stream_writer.deinit();

    try stream_writer.writer.writeAll("data: one\n\n");
    try stream_writer.writer.writeAll("data: two\n\n");

    const body = try stream_writer.takeBody();
    defer std.testing.allocator.free(body);

    try std.testing.expectEqualStrings("data: one\n\ndata: two\n\n", fake.out.written());
    try std.testing.expectEqualStrings("data: one\n\ndata: two\n\n", body);
}

test "streaming response writer captures non-success body without forwarding" {
    const Fake = struct {
        out: Io.Writer.Allocating,

        fn init(allocator: Allocator) @This() {
            return .{ .out = Io.Writer.Allocating.init(allocator) };
        }

        fn deinit(self: *@This()) void {
            self.out.deinit();
        }

        fn callback(self: *@This()) http.StreamCallback {
            return .{
                .ptr = self,
                .write_fn = write,
            };
        }

        fn write(ptr: *anyopaque, bytes: []const u8) http.Error!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.out.writer.writeAll(bytes) catch return error.OutOfMemory;
        }
    };

    var fake = Fake.init(std.testing.allocator);
    defer fake.deinit();

    var stream_writer = StreamingResponseWriter.init(std.testing.allocator, fake.callback(), false);
    defer stream_writer.deinit();

    try stream_writer.writer.writeAll("provider error");

    const body = try stream_writer.takeBody();
    defer std.testing.allocator.free(body);

    try std.testing.expectEqualStrings("", fake.out.written());
    try std.testing.expectEqualStrings("provider error", body);
}

test "streaming response writer cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        const Sink = struct {
            fn callback(self: *@This()) http.StreamCallback {
                return .{
                    .ptr = self,
                    .write_fn = write,
                };
            }

            fn write(_: *anyopaque, _: []const u8) http.Error!void {}
        };

        fn run(allocator: Allocator) !void {
            var sink: Sink = .{};
            var stream_writer = StreamingResponseWriter.init(allocator, sink.callback(), true);
            defer stream_writer.deinit();

            try stream_writer.writeBytes("data: one\n\n");
            const body = try stream_writer.takeBody();
            defer allocator.free(body);
            try std.testing.expectEqualStrings("data: one\n\n", body);
        }
    }.run, .{});
}

test "streaming response writer records callback failures" {
    const Failing = struct {
        fn callback(self: *@This()) http.StreamCallback {
            return .{
                .ptr = self,
                .write_fn = write,
            };
        }

        fn write(_: *anyopaque, _: []const u8) http.Error!void {
            return error.RequestFailed;
        }
    };

    var failing: Failing = .{};
    var stream_writer = StreamingResponseWriter.init(std.testing.allocator, failing.callback(), true);
    defer stream_writer.deinit();

    try std.testing.expectError(error.WriteFailed, stream_writer.writer.writeAll("data: fail\n\n"));
    try std.testing.expectEqual(error.RequestFailed, stream_writer.err.?);
}
