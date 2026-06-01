const std = @import("std");
const agent = @import("../agent.zig");
const channel_error = @import("./errors.zig");
const config = @import("../config.zig");
const ratelimit = @import("../ratelimit.zig");
const runtime = @import("../runtime.zig");
const websocket = @import("../websocket.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Net = std.Io.net;
const HttpServer = std.http.Server;

pub fn isCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "websocket");
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

    const ws_cfg = app_runtime.cfg.value.websocket;
    _ = ws_cfg.token orelse {
        try stderr.writeAll("nllclw: config error: set NLLCLW_WS_TOKEN for nllclw websocket\n");
        try stderr.flush();
        return 2;
    };
    if (!isLoopbackHost(ws_cfg.host) and !ws_cfg.allow_remote) {
        try stderr.writeAll("nllclw: websocket refuses non-loopback bind; set NLLCLW_WS_ALLOW_REMOTE=on and NLLCLW_WS_TOKEN\n");
        try stderr.flush();
        return 2;
    }

    var address = Net.IpAddress.parse(ws_cfg.host, ws_cfg.port) catch {
        try stderr.writeAll("nllclw: NLLCLW_WS_HOST must be an IP literal\n");
        try stderr.flush();
        return 2;
    };
    var server = address.listen(io, .{ .reuse_address = true }) catch |err| {
        try stderr.print("nllclw: websocket listen failed: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return 1;
    };
    defer server.deinit(io);

    try printListenMessage(stderr, ws_cfg);
    try stderr.flush();

    var limiter: ratelimit.FixedWindow = .{
        .limit = ws_cfg.rate_limit_per_minute,
    };
    while (true) {
        const stream = server.accept(io) catch |err| {
            try stderr.print("nllclw: websocket accept warning: {s}\n", .{@errorName(err)});
            try stderr.flush();
            continue;
        };
        handleConnection(allocator, io, stream, &app_runtime, &limiter, stderr) catch |err| {
            try stderr.print("nllclw: websocket connection warning: {s}\n", .{@errorName(err)});
            try stderr.flush();
        };
    }
}

fn handleConnection(
    allocator: Allocator,
    io: Io,
    stream: Net.Stream,
    app_runtime: *runtime.Runtime,
    limiter: *ratelimit.FixedWindow,
    stderr: *Io.Writer,
) !void {
    defer stream.close(io);

    var read_buffer: [websocket.max_prompt_bytes]u8 = undefined;
    var write_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);
    var stream_writer = stream.writer(io, &write_buffer);
    var server = HttpServer.init(&stream_reader.interface, &stream_writer.interface);

    var request = server.receiveHead() catch return;
    const ws_cfg = app_runtime.cfg.value.websocket;
    if (!websocket.targetMatchesPath(request.head.target, ws_cfg.path)) {
        try request.respond("not found\n", .{ .status = .not_found, .keep_alive = false });
        return;
    }
    if (!authorized(&request, ws_cfg)) {
        const headers = [_]std.http.Header{.{ .name = "www-authenticate", .value = "Bearer" }};
        try request.respond("unauthorized\n", .{
            .status = .unauthorized,
            .keep_alive = false,
            .extra_headers = &headers,
        });
        return;
    }

    const key = switch (request.upgradeRequested()) {
        .websocket => |maybe_key| maybe_key orelse {
            try request.respond("missing sec-websocket-key\n", .{ .status = .bad_request, .keep_alive = false });
            return;
        },
        else => {
            try request.respond("upgrade required\n", .{ .status = .upgrade_required, .keep_alive = false });
            return;
        },
    };

    var ws = try request.respondWebSocket(.{ .key = key });
    try ws.flush();
    try sendReady(allocator, &ws);
    try serveWebSocket(allocator, &ws, app_runtime, limiter, stderr);
}

fn serveWebSocket(
    allocator: Allocator,
    ws: *HttpServer.WebSocket,
    app_runtime: *runtime.Runtime,
    limiter: *ratelimit.FixedWindow,
    stderr: *Io.Writer,
) !void {
    while (true) {
        const message = ws.readSmallMessage() catch |err| switch (err) {
            error.ConnectionClose => {
                ws.writeMessage("", .connection_close) catch {};
                return;
            },
            error.EndOfStream => return,
            error.MessageOversize => {
                try sendError(allocator, ws, "message too large");
                try sendClose(ws);
                return;
            },
            else => {
                try sendError(allocator, ws, "invalid websocket frame");
                try sendClose(ws);
                return;
            },
        };

        switch (message.opcode) {
            .ping => {
                try ws.writeMessage(message.data, .pong);
                continue;
            },
            .text => {},
            else => {
                try sendError(allocator, ws, "text messages only");
                continue;
            },
        }

        var command = websocket.parseCommand(allocator, message.data) catch |err| {
            try sendError(allocator, ws, parseErrorMessage(err));
            continue;
        };
        defer command.deinit(allocator);

        switch (command) {
            .ping => try sendContent(allocator, ws, "pong", "pong"),
            .status => {
                const status = try app_runtime.statusText(.quick);
                defer allocator.free(status);
                try sendContent(allocator, ws, "status", status);
            },
            .close => {
                try sendClose(ws);
                return;
            },
            .chat => |prompt| {
                if (!limiter.allow(app_runtime.now())) {
                    try sendError(allocator, ws, "rate limit exceeded");
                    continue;
                }
                try runPrompt(allocator, ws, app_runtime, prompt, stderr);
            },
        }
    }
}

fn runPrompt(
    allocator: Allocator,
    ws: *HttpServer.WebSocket,
    app_runtime: *runtime.Runtime,
    prompt: []const u8,
    stderr: *Io.Writer,
) !void {
    var diagnostic: agent.Diagnostic = .{};
    defer diagnostic.deinit(allocator);

    var stream_sink_state: WebSocketStreamSink = .{ .allocator = allocator, .ws = ws };
    const stream_sink: ?agent.StreamSink = if (app_runtime.cfg.value.stream and !app_runtime.cfg.value.tools.enabled)
        stream_sink_state.sink()
    else
        null;

    const text = app_runtime.completeWithSink(prompt, stream_sink, &diagnostic, .{}) catch |err| {
        try channel_error.printAppErrorWriter(stderr, err, diagnostic);
        try stderr.flush();
        try sendError(allocator, ws, "request failed");
        return;
    };
    defer allocator.free(text);

    try sendContent(allocator, ws, "message", text);
    app_runtime.rememberTurn(prompt, text) catch |err| {
        try stderr.print("nllclw: warning: failed to update memory: {s}\n", .{@errorName(err)});
        try stderr.flush();
    };
}

const WebSocketStreamSink = struct {
    allocator: Allocator,
    ws: *HttpServer.WebSocket,

    fn sink(self: *WebSocketStreamSink) agent.StreamSink {
        return .{
            .ptr = self,
            .write_fn = write,
        };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) agent.StreamError!void {
        const self: *WebSocketStreamSink = @ptrCast(@alignCast(ptr));
        sendContent(self.allocator, self.ws, "delta", bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.WriteFailed,
        };
    }
};

fn sendReady(allocator: Allocator, ws: *HttpServer.WebSocket) !void {
    const json = try websocket.readyEvent(allocator);
    defer allocator.free(json);
    try ws.writeMessage(json, .text);
}

fn sendContent(allocator: Allocator, ws: *HttpServer.WebSocket, event_type: []const u8, content: []const u8) !void {
    const json = try websocket.contentEvent(allocator, event_type, content);
    defer allocator.free(json);
    try ws.writeMessage(json, .text);
}

fn sendError(allocator: Allocator, ws: *HttpServer.WebSocket, message: []const u8) !void {
    const json = try websocket.errorEvent(allocator, message);
    defer allocator.free(json);
    try ws.writeMessage(json, .text);
}

fn sendClose(ws: *HttpServer.WebSocket) !void {
    const normal_close = [_]u8{ 0x03, 0xe8 };
    try ws.writeMessage(&normal_close, .connection_close);
}

fn authorized(request: *const HttpServer.Request, ws_cfg: config.WebSocketConfig) bool {
    const token = ws_cfg.token orelse return false;
    if (isLoopbackHost(ws_cfg.host) and websocket.targetHasToken(request.head.target, token)) return true;

    var seen_authorization = false;
    var bearer_matched = false;
    var it = request.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
            if (seen_authorization) return false;
            seen_authorization = true;
            bearer_matched = websocket.authorizationBearerMatches(header.value, token);
        }
    }
    return bearer_matched;
}

fn isLoopbackHost(host: []const u8) bool {
    const address = Net.IpAddress.parse(host, 1) catch return false;
    return switch (address) {
        .ip4 => |ip4| ip4.bytes[0] == 127,
        .ip6 => |ip6| std.mem.eql(u8, &ip6.bytes, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }),
    };
}

fn parseErrorMessage(err: websocket.ParseError) []const u8 {
    return switch (err) {
        error.OutOfMemory => "out of memory",
        error.EmptyMessage => "empty message",
        error.InvalidJson => "invalid json message",
        error.InvalidUtf8 => "text messages must be valid utf-8 without binary control bytes",
        error.MissingPrompt => "chat message requires a non-empty prompt",
        error.PromptTooLarge => "prompt too large",
        error.UnexpectedPrompt => "command message must not include a prompt",
        error.UnknownMessageType => "unknown message type",
    };
}

fn printListenMessage(stderr: *Io.Writer, ws_cfg: config.WebSocketConfig) !void {
    if (std.mem.indexOfScalar(u8, ws_cfg.host, ':') != null) {
        try stderr.print("nllclw websocket listening on ws://[{s}]:{d}{s} (single active client)\n", .{ ws_cfg.host, ws_cfg.port, ws_cfg.path });
    } else {
        try stderr.print("nllclw websocket listening on ws://{s}:{d}{s} (single active client)\n", .{ ws_cfg.host, ws_cfg.port, ws_cfg.path });
    }
}

test "websocket command predicate accepts only canonical command" {
    try std.testing.expect(isCommand("websocket"));
    try std.testing.expect(!isCommand("telegram"));
}

test "websocket loopback detection is strict" {
    try std.testing.expect(isLoopbackHost("127.0.0.1"));
    try std.testing.expect(isLoopbackHost("127.10.20.30"));
    try std.testing.expect(isLoopbackHost("::1"));
    try std.testing.expect(!isLoopbackHost("0.0.0.0"));
    try std.testing.expect(!isLoopbackHost("::"));
}

test "websocket authorization accepts query or bearer token only" {
    var query_request = try testRequest(
        "GET /ws?token=ws-token HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "sec-websocket-key: test-key\r\n" ++
            "\r\n",
    );
    try std.testing.expect(websocket.targetMatchesPath(query_request.head.target, "/ws"));
    try std.testing.expect(authorized(&query_request, .{ .token = "ws-token" }));
    try std.testing.expect(!authorized(&query_request, .{
        .host = "0.0.0.0",
        .allow_remote = true,
        .token = "ws-token",
    }));
    switch (query_request.upgradeRequested()) {
        .websocket => |key| try std.testing.expectEqualStrings("test-key", key.?),
        else => return error.TestExpectedEqual,
    }

    var bearer_request = try testRequest(
        "GET /ws HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "sec-websocket-key: test-key\r\n" ++
            "authorization: Bearer ws-token\r\n" ++
            "\r\n",
    );
    try std.testing.expect(authorized(&bearer_request, .{ .token = "ws-token" }));
    try std.testing.expect(authorized(&bearer_request, .{
        .host = "0.0.0.0",
        .allow_remote = true,
        .token = "ws-token",
    }));

    var missing_request = try testRequest(
        "GET /ws HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "sec-websocket-key: test-key\r\n" ++
            "\r\n",
    );
    try std.testing.expect(!authorized(&missing_request, .{ .token = "ws-token" }));
}

test "websocket authorization rejects wrong path and missing upgrade key" {
    const wrong_path = try testRequest(
        "GET /other?token=ws-token HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "sec-websocket-key: test-key\r\n" ++
            "\r\n",
    );
    try std.testing.expect(!websocket.targetMatchesPath(wrong_path.head.target, "/ws"));

    var missing_key = try testRequest(
        "GET /ws?token=ws-token HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "\r\n",
    );
    switch (missing_key.upgradeRequested()) {
        .websocket => |key| try std.testing.expect(key == null),
        else => return error.TestExpectedEqual,
    }
}

test "websocket authorization rejects duplicate bearer headers" {
    var duplicate_bearer = try testRequest(
        "GET /ws HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "sec-websocket-key: test-key\r\n" ++
            "authorization: Bearer ws-token\r\n" ++
            "authorization: Bearer ws-token\r\n" ++
            "\r\n",
    );
    try std.testing.expect(!authorized(&duplicate_bearer, .{ .token = "ws-token" }));

    var duplicate_mixed = try testRequest(
        "GET /ws HTTP/1.1\r\n" ++
            "host: 127.0.0.1:8765\r\n" ++
            "upgrade: websocket\r\n" ++
            "sec-websocket-key: test-key\r\n" ++
            "authorization: Basic ws-token\r\n" ++
            "authorization: Bearer ws-token\r\n" ++
            "\r\n",
    );
    try std.testing.expect(!authorized(&duplicate_mixed, .{ .token = "ws-token" }));
}

fn testRequest(bytes: []const u8) !HttpServer.Request {
    return .{
        .server = &test_server,
        .head = try HttpServer.Request.Head.parse(bytes),
        .head_buffer = bytes,
    };
}

var test_server: HttpServer = .{
    .reader = .{
        .in = undefined,
        .state = .received_head,
        .interface = undefined,
        .max_head_len = 4096,
    },
    .out = undefined,
};
