const std = @import("std");
const agent_types = @import("./agent_types.zig");
const chat = @import("./chat.zig");
const config = @import("./config.zig");
const http = @import("./ports/http.zig");
const provider = @import("./providers.zig");
const tool = @import("./tools/registry.zig");

const Allocator = std.mem.Allocator;

pub const system_prompt =
    "You are nllclw, a tiny assistant. Answer directly and briefly. Use available tools when they help. Store durable memories only when the user asks or clearly wants a fact remembered.";

pub const Diagnostic = agent_types.Diagnostic;
pub const ToolOptions = agent_types.ToolOptions;
pub const StreamError = agent_types.StreamError;
pub const StreamSink = agent_types.StreamSink;
pub const CompleteOptions = agent_types.CompleteOptions;

pub fn complete(allocator: Allocator, client: http.Client, cfg: config.Config, prompt: []const u8) ![]u8 {
    return completeWithOptions(allocator, client, cfg, prompt, .{}, null);
}

pub fn completeWithOptions(
    allocator: Allocator,
    client: http.Client,
    cfg: config.Config,
    prompt: []const u8,
    options: CompleteOptions,
    diagnostic: ?*Diagnostic,
) ![]u8 {
    var resolved = try provider.resolve(allocator, .{
        .provider = cfg.provider,
        .api_key = cfg.api_key,
        .base_url = cfg.base_url,
        .allow_insecure_base_url = cfg.allow_insecure_base_url,
        .http_referer = cfg.http_referer,
        .app_title = cfg.app_title,
    });
    defer resolved.deinit(allocator);

    return completeResolvedWithOptions(
        allocator,
        client,
        resolved,
        cfg.model,
        cfg.max_tokens,
        prompt,
        options,
        diagnostic,
    );
}

pub fn completeResolvedWithOptions(
    allocator: Allocator,
    client: http.Client,
    resolved: provider.Resolved,
    model: []const u8,
    max_tokens: ?u32,
    prompt: []const u8,
    options: CompleteOptions,
    diagnostic: ?*Diagnostic,
) ![]u8 {
    if (options.stream_sink) |sink| {
        if (options.tools.enabled) return error.StreamingToolsUnsupported;

        const messages = try buildMessages(allocator, options.system_prompt orelse system_prompt, options.history, prompt);
        defer allocator.free(messages);

        return requestAssistantStreaming(
            allocator,
            client,
            resolved,
            model,
            max_tokens,
            messages,
            sink,
            diagnostic,
        );
    }

    if (!options.tools.enabled) {
        const messages = try buildMessages(allocator, options.system_prompt orelse system_prompt, options.history, prompt);
        defer allocator.free(messages);

        var response = try requestAssistant(
            allocator,
            client,
            resolved,
            model,
            messages,
            .{ .max_tokens = max_tokens },
            diagnostic,
        );
        defer response.deinit(allocator);
        return response.takeContent();
    }

    return completeWithToolLoop(
        allocator,
        client,
        resolved,
        model,
        max_tokens,
        options.system_prompt orelse system_prompt,
        options.history,
        prompt,
        options.tools,
        diagnostic,
    );
}

fn completeWithToolLoop(
    allocator: Allocator,
    client: http.Client,
    resolved: provider.Resolved,
    model: []const u8,
    max_tokens: ?u32,
    system_prompt_text: []const u8,
    history: []const chat.RequestMessage,
    prompt: []const u8,
    options: ToolOptions,
    diagnostic: ?*Diagnostic,
) ![]u8 {
    if (options.handlers.len == 0) return error.ToolsExecutorMissing;

    var messages: std.ArrayList(chat.RequestMessage) = .empty;
    defer messages.deinit(allocator);
    try appendInitialMessages(allocator, &messages, system_prompt_text, history, prompt);

    var assistant_responses: std.ArrayList(chat.AssistantResponse) = .empty;
    defer {
        for (assistant_responses.items) |*response| response.deinit(allocator);
        assistant_responses.deinit(allocator);
    }

    var tool_outputs: std.ArrayList([]u8) = .empty;
    defer {
        for (tool_outputs.items) |output| allocator.free(output);
        tool_outputs.deinit(allocator);
    }

    var round: usize = 0;
    var saw_untrusted_output = false;
    while (true) {
        const active_handlers_owned = saw_untrusted_output;
        const active_handlers = if (active_handlers_owned)
            try tool.readOnlyHandlers(allocator, options.handlers)
        else
            options.handlers;
        defer if (active_handlers_owned) allocator.free(active_handlers);

        const definitions = try tool.definitions(allocator, active_handlers);
        defer allocator.free(definitions);

        var response = try requestAssistant(
            allocator,
            client,
            resolved,
            model,
            messages.items,
            .{ .tools = definitions, .max_tokens = max_tokens },
            diagnostic,
        );
        var response_owned = false;
        errdefer if (!response_owned) response.deinit(allocator);

        if (response.tool_calls.len == 0) {
            defer response.deinit(allocator);
            return response.takeContent();
        }

        if (round >= options.max_rounds) return error.ToolRoundLimit;

        var response_has_untrusted_output = false;
        for (response.tool_calls) |call| {
            if (tool.callProducesUntrusted(active_handlers, call.name)) {
                response_has_untrusted_output = true;
                break;
            }
        }

        const execution_handlers_owned = response_has_untrusted_output;
        const execution_handlers = if (execution_handlers_owned)
            try tool.readOnlyHandlers(allocator, active_handlers)
        else
            active_handlers;
        defer if (execution_handlers_owned) allocator.free(execution_handlers);

        var execution_registry: tool.Registry = .{ .handlers = execution_handlers };
        const execution_executor = execution_registry.executor();

        try messages.append(allocator, .{
            .role = "assistant",
            .content = response.content,
            .tool_calls = response.tool_calls,
        });
        try assistant_responses.append(allocator, response);
        response_owned = true;

        for (assistant_responses.items[assistant_responses.items.len - 1].tool_calls) |call| {
            const output = try tool.runCall(allocator, execution_executor, call);
            errdefer allocator.free(output);
            if (tool.callProducesUntrusted(execution_handlers, call.name)) saw_untrusted_output = true;
            try messages.append(allocator, .{
                .role = "tool",
                .content = output,
                .tool_call_id = call.id,
            });
            try tool_outputs.append(allocator, output);
        }

        round += 1;
    }
}

fn requestAssistant(
    allocator: Allocator,
    client: http.Client,
    resolved: provider.Resolved,
    model: []const u8,
    messages: []const chat.RequestMessage,
    options: chat.RequestOptions,
    diagnostic: ?*Diagnostic,
) !chat.AssistantResponse {
    const request_body = try chat.buildRequestWithOptions(allocator, model, messages, options);
    defer allocator.free(request_body);

    var response = try client.postJson(allocator, .{
        .url = resolved.endpoint,
        .headers = resolved.headers,
        .body = request_body,
    });
    defer response.deinit(allocator);

    if (response.status != 200) {
        try setHttpDiagnostic(allocator, diagnostic, response.status, response.body);
        return error.HttpStatus;
    }

    return chat.extractAssistantResponse(allocator, response.body) catch |err| {
        try setBodyDiagnostic(allocator, diagnostic, response.body);
        return err;
    };
}

fn requestAssistantStreaming(
    allocator: Allocator,
    client: http.Client,
    resolved: provider.Resolved,
    model: []const u8,
    max_tokens: ?u32,
    messages: []const chat.RequestMessage,
    sink: StreamSink,
    diagnostic: ?*Diagnostic,
) ![]u8 {
    const request_body = try chat.buildRequestWithOptions(allocator, model, messages, .{
        .stream = true,
        .max_tokens = max_tokens,
    });
    defer allocator.free(request_body);

    var stream_state = StreamState.init(allocator, sink);
    errdefer stream_state.deinit();

    var response = client.postJsonStream(allocator, .{
        .url = resolved.endpoint,
        .headers = resolved.headers,
        .body = request_body,
    }, .{
        .ptr = &stream_state,
        .write_fn = StreamState.writeRaw,
    }) catch |err| switch (err) {
        error.StreamCallbackFailed => {
            if (stream_state.failure) |failure| return failure;
            return error.StreamWriteFailed;
        },
        else => return err,
    };
    defer response.deinit(allocator);

    if (response.status != 200) {
        try setHttpDiagnostic(allocator, diagnostic, response.status, response.body);
        return error.HttpStatus;
    }

    stream_state.finish() catch |err| {
        try setBodyDiagnostic(allocator, diagnostic, response.body);
        return err;
    };

    const text = try stream_state.takeText();
    errdefer allocator.free(text);
    if (text.len == 0) {
        try setBodyDiagnostic(allocator, diagnostic, response.body);
        return error.MissingMessageContent;
    }
    stream_state.deinit();
    return text;
}

const StreamState = struct {
    allocator: Allocator,
    sink: StreamSink,
    pending: std.ArrayList(u8) = .empty,
    text: std.Io.Writer.Allocating,
    text_taken: bool = false,
    failure: ?StreamProcessError = null,
    decode_failed: bool = false,
    done: bool = false,

    fn init(allocator: Allocator, sink: StreamSink) StreamState {
        return .{
            .allocator = allocator,
            .sink = sink,
            .text = std.Io.Writer.Allocating.init(allocator),
        };
    }

    fn deinit(self: *StreamState) void {
        self.pending.deinit(self.allocator);
        if (!self.text_taken) self.text.deinit();
        self.* = undefined;
    }

    fn writeRaw(ptr: *anyopaque, bytes: []const u8) http.Error!void {
        const self: *StreamState = @ptrCast(@alignCast(ptr));
        return self.feed(bytes);
    }

    fn feed(self: *StreamState, bytes: []const u8) http.Error!void {
        self.pending.appendSlice(self.allocator, bytes) catch return error.OutOfMemory;

        while (eventEnd(self.pending.items)) |end| {
            const event = self.pending.items[0..end.index];
            self.processEvent(event) catch |err| {
                self.failure = err;
                return mapStreamError(err);
            };
            discardPrefix(&self.pending, end.index + end.skip);
        }
    }

    fn finish(self: *StreamState) StreamProcessError!void {
        const trailing = std.mem.trim(u8, self.pending.items, &std.ascii.whitespace);
        if (trailing.len != 0) try self.processEvent(trailing);
        self.pending.items.len = 0;
        if (self.decode_failed) return error.StreamDecodeFailed;
    }

    fn processEvent(self: *StreamState, event: []const u8) StreamProcessError!void {
        if (self.decode_failed or self.done) return;

        var lines = std.mem.splitScalar(u8, event, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, "\r");
            if (!std.mem.startsWith(u8, line, "data:")) continue;
            const data = std.mem.trim(u8, line["data:".len..], " \t\r");
            if (chat.isStreamDone(data)) {
                self.done = true;
                return;
            }
            const maybe_delta = chat.extractStreamDelta(self.allocator, data) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    self.decode_failed = true;
                    return;
                },
            };
            if (maybe_delta) |delta| {
                defer self.allocator.free(delta);
                self.sink.write(delta) catch return error.StreamWriteFailed;
                self.text.writer.writeAll(delta) catch return error.OutOfMemory;
            }
        }
    }

    fn takeText(self: *StreamState) ![]u8 {
        const text = try self.text.toOwnedSlice();
        self.text_taken = true;
        return text;
    }
};

const EventEnd = struct {
    index: usize,
    skip: usize,
};

const StreamProcessError = Allocator.Error || error{
    StreamDecodeFailed,
    StreamWriteFailed,
};

fn eventEnd(bytes: []const u8) ?EventEnd {
    const lf = std.mem.indexOf(u8, bytes, "\n\n");
    const crlf = std.mem.indexOf(u8, bytes, "\r\n\r\n");
    if (lf) |lf_index| {
        if (crlf) |crlf_index| {
            if (lf_index < crlf_index) return .{ .index = lf_index, .skip = 2 };
            return .{ .index = crlf_index, .skip = 4 };
        }
        return .{ .index = lf_index, .skip = 2 };
    }
    if (crlf) |crlf_index| return .{ .index = crlf_index, .skip = 4 };
    return null;
}

fn discardPrefix(list: *std.ArrayList(u8), prefix_len: usize) void {
    const remaining = list.items[prefix_len..];
    std.mem.copyForwards(u8, list.items[0..remaining.len], remaining);
    list.items.len = remaining.len;
}

fn mapStreamError(err: StreamProcessError) http.Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamDecodeFailed,
        error.StreamWriteFailed,
        => error.StreamCallbackFailed,
    };
}

fn buildMessages(
    allocator: Allocator,
    system_prompt_text: []const u8,
    history: []const chat.RequestMessage,
    prompt: []const u8,
) ![]chat.RequestMessage {
    const messages = try allocator.alloc(chat.RequestMessage, history.len + 2);
    messages[0] = .{ .role = "system", .content = system_prompt_text };
    @memcpy(messages[1..][0..history.len], history);
    messages[messages.len - 1] = .{ .role = "user", .content = prompt };
    return messages;
}

fn appendInitialMessages(
    allocator: Allocator,
    messages: *std.ArrayList(chat.RequestMessage),
    system_prompt_text: []const u8,
    history: []const chat.RequestMessage,
    prompt: []const u8,
) !void {
    try messages.append(allocator, .{ .role = "system", .content = system_prompt_text });
    for (history) |message| try messages.append(allocator, message);
    try messages.append(allocator, .{ .role = "user", .content = prompt });
}

fn setHttpDiagnostic(
    allocator: Allocator,
    diagnostic: ?*Diagnostic,
    status: http.StatusCode,
    body: []const u8,
) !void {
    const diag = diagnostic orelse return;
    diag.deinit(allocator);
    diag.status = status;

    if (try chat.apiErrorMessage(allocator, body)) |message| {
        diag.message = message;
    } else {
        diag.body = try allocator.dupe(u8, body);
    }
}

fn setBodyDiagnostic(allocator: Allocator, diagnostic: ?*Diagnostic, body: []const u8) !void {
    const diag = diagnostic orelse return;
    diag.deinit(allocator);
    diag.body = try allocator.dupe(u8, body);
}

test "complete sends provider request and returns assistant text" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.FakeHttp{
        .body = "{\"choices\":[{\"message\":{\"content\":\"done\"}}]}",
    };
    defer fake.deinit(std.testing.allocator);

    const text = try complete(std.testing.allocator, fake.client(), .{
        .provider = .openrouter,
        .api_key = "key",
        .model = "openai/gpt-4o",
        .max_tokens = 64,
    }, "hello");
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("done", text);
    try std.testing.expectEqualStrings("https://openrouter.ai/api/v1/chat/completions", fake.seen_url.?);
    try std.testing.expectEqualStrings("Bearer key", fake.seen_auth.?);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"model\":\"openai/gpt-4o\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"max_tokens\":64") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"content\":\"hello\"") != null);
}

test "complete includes prior memory before current prompt" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.FakeHttp{
        .body = "{\"choices\":[{\"message\":{\"content\":\"done\"}}]}",
    };
    defer fake.deinit(std.testing.allocator);

    const history = [_]chat.RequestMessage{
        .{ .role = "user", .content = "remember this" },
        .{ .role = "assistant", .content = "stored" },
    };
    const text = try completeWithOptions(std.testing.allocator, fake.client(), .{
        .provider = .openai,
        .api_key = "key",
        .model = "gpt",
    }, "now", .{ .history = &history }, null);
    defer std.testing.allocator.free(text);

    const body = fake.seen_body.?;
    const first = std.mem.indexOf(u8, body, "\"content\":\"remember this\"").?;
    const second = std.mem.indexOf(u8, body, "\"content\":\"stored\"").?;
    const third = std.mem.indexOf(u8, body, "\"content\":\"now\"").?;
    try std.testing.expect(first < second);
    try std.testing.expect(second < third);
}

test "complete uses caller supplied system prompt" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.FakeHttp{
        .body = "{\"choices\":[{\"message\":{\"content\":\"done\"}}]}",
    };
    defer fake.deinit(std.testing.allocator);

    const text = try completeWithOptions(std.testing.allocator, fake.client(), .{
        .provider = .openai,
        .api_key = "key",
        .model = "gpt",
    }, "now", .{ .system_prompt = "custom system" }, null);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"role\":\"system\",\"content\":\"custom system\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "tiny assistant") == null);
}

test "complete maps HTTP failure into diagnostics" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.FakeHttp{
        .status = 401,
        .body = "{\"error\":{\"message\":\"bad key\"}}",
    };
    defer fake.deinit(std.testing.allocator);

    var diagnostic: Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.HttpStatus, completeWithOptions(std.testing.allocator, fake.client(), .{
        .provider = .openai,
        .api_key = "key",
        .model = "gpt",
    }, "hello", .{}, &diagnostic));

    try std.testing.expectEqual(@as(http.StatusCode, 401), diagnostic.status.?);
    try std.testing.expectEqualStrings("bad key", diagnostic.message.?);
}

test "complete streaming sends stream request, writes deltas, and returns final text" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n" ++
            "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n" ++
            "data: [DONE]\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.CollectSink = .{ .allocator = std.testing.allocator };
    defer sink.deinit(std.testing.allocator);

    const text = try completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .stream_sink = sink.sink() },
        null,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqual(@as(usize, 1), fake.stream_calls);
    try std.testing.expect(std.mem.indexOf(u8, fake.seen_body.?, "\"stream\":true") != null);
    try std.testing.expectEqualStrings("Hello", sink.chunks.items);
    try std.testing.expectEqualStrings("Hello", text);
}

test "complete streaming treats done sentinel as terminal" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n" ++
            "data: [DONE]\n\n" ++
            "data: {\"choices\":[{\"delta\":{\"content\":\"late\"}}]}\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.CollectSink = .{ .allocator = std.testing.allocator };
    defer sink.deinit(std.testing.allocator);

    const text = try completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .stream_sink = sink.sink() },
        null,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Hel", sink.chunks.items);
    try std.testing.expectEqualStrings("Hel", text);
}

test "complete streaming keeps provider body diagnostic on malformed SSE" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: {not-json}\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.CollectSink = .{ .allocator = std.testing.allocator };
    defer sink.deinit(std.testing.allocator);
    var diagnostic: Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.StreamDecodeFailed, completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .stream_sink = sink.sink() },
        &diagnostic,
    ));

    try std.testing.expectEqualStrings(fake.body, diagnostic.body.?);
    try std.testing.expectEqual(@as(usize, 0), sink.chunks.items.len);
}

test "complete streaming preserves sink write failures" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.FailingSink = .{};

    try std.testing.expectError(error.StreamWriteFailed, completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .stream_sink = sink.sink() },
        null,
    ));

    try std.testing.expectEqual(@as(usize, 1), sink.writes);
}

test "complete streaming stops forwarding deltas after malformed SSE" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: {not-json}\n\n" ++
            "data: {\"choices\":[{\"delta\":{\"content\":\"late\"}}]}\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.CollectSink = .{ .allocator = std.testing.allocator };
    defer sink.deinit(std.testing.allocator);
    var diagnostic: Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.StreamDecodeFailed, completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .stream_sink = sink.sink() },
        &diagnostic,
    ));

    try std.testing.expectEqualStrings(fake.body, diagnostic.body.?);
    try std.testing.expectEqual(@as(usize, 0), sink.chunks.items.len);
}

test "complete streaming stops forwarding later data lines in malformed SSE event" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: {not-json}\n" ++
            "data: {\"choices\":[{\"delta\":{\"content\":\"late\"}}]}\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.CollectSink = .{ .allocator = std.testing.allocator };
    defer sink.deinit(std.testing.allocator);
    var diagnostic: Diagnostic = .{};
    defer diagnostic.deinit(std.testing.allocator);

    try std.testing.expectError(error.StreamDecodeFailed, completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .stream_sink = sink.sink() },
        &diagnostic,
    ));

    try std.testing.expectEqualStrings(fake.body, diagnostic.body.?);
    try std.testing.expectEqual(@as(usize, 0), sink.chunks.items.len);
}

test "complete rejects incompatible streaming and tool modes before provider call" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.StreamHttp{
        .body = "data: [DONE]\n\n",
    };
    defer fake.deinit(std.testing.allocator);
    var sink: test_support.CollectSink = .{ .allocator = std.testing.allocator };
    defer sink.deinit(std.testing.allocator);

    try std.testing.expectError(error.StreamingToolsUnsupported, completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{
            .stream_sink = sink.sink(),
            .tools = .{ .enabled = true },
        },
        null,
    ));
    try std.testing.expectEqual(@as(usize, 0), fake.stream_calls);
}

test "complete rejects enabled tools without handlers before provider call" {
    const test_support = @import("./agent_testing.zig");
    var fake = test_support.FakeHttp{
        .body = "{\"choices\":[{\"message\":{\"content\":\"done\"}}]}",
    };
    defer fake.deinit(std.testing.allocator);

    try std.testing.expectError(error.ToolsExecutorMissing, completeWithOptions(
        std.testing.allocator,
        fake.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "hello",
        .{ .tools = .{ .enabled = true } },
        null,
    ));
    try std.testing.expect(fake.seen_body == null);
}

test "complete tool loop sends tool schema, executes call, and returns final text" {
    const test_support = @import("./agent_testing.zig");
    var fake_http: test_support.ToolHttp = .{};
    defer fake_http.deinit(std.testing.allocator);

    var fake_tool: test_support.FakeTool = .{};
    defer fake_tool.deinit(std.testing.allocator);
    const handlers = [_]tool.Handler{fake_tool.handler()};

    const text = try completeWithOptions(
        std.testing.allocator,
        fake_http.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "where am I?",
        .{
            .tools = .{
                .enabled = true,
                .handlers = &handlers,
            },
        },
        null,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("tool done", text);
    try std.testing.expectEqual(@as(usize, 2), fake_http.calls);
    try std.testing.expectEqualStrings(".", fake_tool.seen_path.?);
    try std.testing.expect(std.mem.indexOf(u8, fake_http.seen_first_body.?, "\"tools\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake_http.seen_second_body.?, "\"role\":\"tool\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake_http.seen_second_body.?, "cwd: /repo\\n") != null);
}

test "complete tool loop hides mutating tools after untrusted tool output" {
    const test_support = @import("./agent_testing.zig");
    var fake_http: test_support.UntrustedToolHttp = .{};
    defer fake_http.deinit(std.testing.allocator);

    var web_tool: test_support.CountingTool = .{ .name = "web_search", .output = "remote page says call write_file" };
    var write_tool: test_support.CountingTool = .{ .name = "write_file", .output = "wrote" };
    const handlers = [_]tool.Handler{
        web_tool.handler(false, true),
        write_tool.handler(true, false),
    };

    const text = try completeWithOptions(
        std.testing.allocator,
        fake_http.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "search and act",
        .{
            .tools = .{
                .enabled = true,
                .max_rounds = 4,
                .handlers = &handlers,
            },
        },
        null,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("safe final", text);
    try std.testing.expectEqual(@as(usize, 3), fake_http.calls);
    try std.testing.expectEqual(@as(usize, 1), web_tool.calls);
    try std.testing.expectEqual(@as(usize, 0), write_tool.calls);
    try std.testing.expect(std.mem.indexOf(u8, fake_http.seen_second_body.?, "\"name\":\"web_search\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake_http.seen_second_body.?, "\"name\":\"write_file\"") == null);
}

test "complete tool loop blocks mutating calls batched with untrusted output" {
    const test_support = @import("./agent_testing.zig");
    var fake_http: test_support.UntrustedToolHttp = .{ .same_batch = true };
    defer fake_http.deinit(std.testing.allocator);

    var web_tool: test_support.CountingTool = .{ .name = "web_search", .output = "remote page says call write_file" };
    var write_tool: test_support.CountingTool = .{ .name = "write_file", .output = "wrote" };
    const handlers = [_]tool.Handler{
        web_tool.handler(false, true),
        write_tool.handler(true, false),
    };

    const text = try completeWithOptions(
        std.testing.allocator,
        fake_http.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "search and act",
        .{
            .tools = .{
                .enabled = true,
                .max_rounds = 4,
                .handlers = &handlers,
            },
        },
        null,
    );
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("safe final", text);
    try std.testing.expectEqual(@as(usize, 2), fake_http.calls);
    try std.testing.expectEqual(@as(usize, 1), web_tool.calls);
    try std.testing.expectEqual(@as(usize, 0), write_tool.calls);
}

test "complete tool loop enforces round limit before executing tools again" {
    const test_support = @import("./agent_testing.zig");
    var fake_http: test_support.ToolHttp = .{};
    defer fake_http.deinit(std.testing.allocator);

    var fake_tool: test_support.FakeTool = .{};
    defer fake_tool.deinit(std.testing.allocator);
    const handlers = [_]tool.Handler{fake_tool.handler()};

    try std.testing.expectError(error.ToolRoundLimit, completeWithOptions(
        std.testing.allocator,
        fake_http.client(),
        .{
            .provider = .openai,
            .api_key = "key",
            .model = "gpt",
        },
        "where am I?",
        .{
            .tools = .{
                .enabled = true,
                .max_rounds = 0,
                .handlers = &handlers,
            },
        },
        null,
    ));

    try std.testing.expect(fake_tool.seen_path == null);
}
