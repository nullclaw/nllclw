const std = @import("std");
const text_policy = @import("./text_policy.zig");

const Allocator = std.mem.Allocator;

pub const RequestMessage = struct {
    role: []const u8,
    content: ?[]const u8,
    tool_calls: []const ToolCall = &.{},
    tool_call_id: ?[]const u8 = null,
};

pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8,
};

pub const ToolDefinition = struct {
    name: []const u8,
    description: []const u8,
    parameters: ToolParameters,
};

pub const ToolParameters = struct {
    properties: []const ToolParameter,
    required: []const []const u8 = &.{},
    additional_properties: bool = false,
};

pub const ToolParameter = struct {
    name: []const u8,
    kind: ToolParameterKind,
    description: ?[]const u8 = null,
};

pub const ToolParameterKind = enum {
    boolean,
    integer,
    string,
};

pub const RequestOptions = struct {
    tools: []const ToolDefinition = &.{},
    stream: bool = false,
    max_tokens: ?u32 = null,
};

pub const max_tool_name_bytes: usize = 64;
pub const max_tool_call_id_bytes: usize = 256;
pub const max_diagnostic_message_bytes: usize = 1024;

const CompletionResponse = struct {
    choices: []const Choice = &.{},
};

const Choice = struct {
    message: Message = .{},
};

const Message = struct {
    role: ?[]const u8 = null,
    content: ?[]const u8 = null,
    tool_calls: []const ResponseToolCall = &.{},
};

const ResponseToolCall = struct {
    id: []const u8 = "",
    type: []const u8 = "",
    function: ?ResponseToolFunction = null,
};

const ResponseToolFunction = struct {
    name: []const u8 = "",
    arguments: ?[]const u8 = null,
};

const ApiErrorResponse = struct {
    @"error": ?ApiError = null,
};

const ApiError = struct {
    message: []const u8,
};

const StreamResponse = struct {
    choices: []const StreamChoice = &.{},
};

const StreamChoice = struct {
    delta: StreamDelta = .{},
};

const StreamDelta = struct {
    content: ?[]const u8 = null,
};

pub const DecodeError = error{
    InvalidResponse,
    MissingChoice,
    MissingMessageContent,
    MissingToolCall,
} || Allocator.Error;

pub const BuildError = error{
    InvalidRequestText,
} || Allocator.Error;

pub fn buildRequest(allocator: Allocator, model: []const u8, messages: []const RequestMessage) BuildError![]u8 {
    return buildRequestWithOptions(allocator, model, messages, .{});
}

pub fn buildRequestWithOptions(
    allocator: Allocator,
    model: []const u8,
    messages: []const RequestMessage,
    options: RequestOptions,
) BuildError![]u8 {
    try validateRequestEnvelope(model, messages);

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    var json: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{},
    };

    try jsonBeginObject(&json);
    try jsonObjectField(&json, "model");
    try jsonWriteSingleLineString(&json, model);
    if (options.max_tokens) |max_tokens| {
        try jsonObjectField(&json, "max_tokens");
        try jsonWrite(&json, max_tokens);
    }
    try jsonObjectField(&json, "messages");
    try jsonBeginArray(&json);
    for (messages) |message| {
        try writeMessage(&json, message);
    }
    try jsonEndArray(&json);

    if (options.tools.len > 0) {
        try validateToolDefinitions(options.tools);
        try jsonObjectField(&json, "tools");
        try jsonBeginArray(&json);
        for (options.tools) |tool| try writeToolDefinition(&json, tool);
        try jsonEndArray(&json);
        try jsonObjectField(&json, "tool_choice");
        try jsonWriteString(&json, "auto");
    }

    if (options.stream) {
        try jsonObjectField(&json, "stream");
        try jsonWrite(&json, true);
    }

    try jsonEndObject(&json);

    return out.toOwnedSlice();
}

fn validateRequestEnvelope(model: []const u8, messages: []const RequestMessage) BuildError!void {
    try validateJsonSingleLineString(model);
    if (messages.len == 0) return error.InvalidRequestText;
}

fn writeMessage(json: *std.json.Stringify, message: RequestMessage) BuildError!void {
    try validateMessageShape(message);

    try jsonBeginObject(json);
    try jsonObjectField(json, "role");
    try jsonWriteRole(json, message.role);
    try jsonObjectField(json, "content");
    if (message.content) |content| {
        try jsonWriteString(json, content);
    } else if (std.mem.eql(u8, message.role, "assistant") and message.tool_calls.len > 0) {
        try jsonWriteString(json, "");
    } else {
        try jsonWrite(json, null);
    }

    if (message.tool_calls.len > 0) {
        try validateToolCalls(message.tool_calls);
        try jsonObjectField(json, "tool_calls");
        try jsonBeginArray(json);
        for (message.tool_calls) |call| try writeToolCall(json, call);
        try jsonEndArray(json);
    }

    if (message.tool_call_id) |id| {
        try jsonObjectField(json, "tool_call_id");
        try jsonWriteToolCallId(json, id);
    }

    try jsonEndObject(json);
}

fn validateMessageShape(message: RequestMessage) BuildError!void {
    const has_content = message.content != null;
    const has_tool_calls = message.tool_calls.len != 0;
    const has_tool_call_id = message.tool_call_id != null;

    if (std.mem.eql(u8, message.role, "system") or std.mem.eql(u8, message.role, "user")) {
        if (!has_content or has_tool_calls or has_tool_call_id) return error.InvalidRequestText;
        return;
    }

    if (std.mem.eql(u8, message.role, "assistant")) {
        if (!has_content and !has_tool_calls) return error.InvalidRequestText;
        if (has_tool_call_id) return error.InvalidRequestText;
        return;
    }

    if (std.mem.eql(u8, message.role, "tool")) {
        if (!has_content or has_tool_calls or !has_tool_call_id) return error.InvalidRequestText;
        return;
    }

    return error.InvalidRequestText;
}

fn writeToolCall(json: *std.json.Stringify, call: ToolCall) BuildError!void {
    try jsonBeginObject(json);
    try jsonObjectField(json, "id");
    try jsonWriteToolCallId(json, call.id);
    try jsonObjectField(json, "type");
    try jsonWriteSingleLineString(json, "function");
    try jsonObjectField(json, "function");
    try jsonBeginObject(json);
    try jsonObjectField(json, "name");
    try jsonWriteToolName(json, call.name);
    try jsonObjectField(json, "arguments");
    try jsonWriteString(json, call.arguments);
    try jsonEndObject(json);
    try jsonEndObject(json);
}

fn validateToolCalls(calls: []const ToolCall) BuildError!void {
    for (calls, 0..) |call, index| {
        try validateToolCallId(call.id);
        try validateToolName(call.name);
        try validateJsonString(call.arguments);
        for (calls[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, call.id)) return error.InvalidRequestText;
        }
    }
}

fn writeToolDefinition(json: *std.json.Stringify, tool: ToolDefinition) BuildError!void {
    try jsonBeginObject(json);
    try jsonObjectField(json, "type");
    try jsonWriteSingleLineString(json, "function");
    try jsonObjectField(json, "function");
    try jsonBeginObject(json);
    try jsonObjectField(json, "name");
    try jsonWriteToolName(json, tool.name);
    try jsonObjectField(json, "description");
    try jsonWriteString(json, tool.description);
    try jsonObjectField(json, "parameters");
    try writeToolParameters(json, tool.parameters);
    try jsonEndObject(json);
    try jsonEndObject(json);
}

fn writeToolParameters(json: *std.json.Stringify, parameters: ToolParameters) BuildError!void {
    try validateToolParameters(parameters);

    try jsonBeginObject(json);
    try jsonObjectField(json, "type");
    try jsonWriteString(json, "object");
    try jsonObjectField(json, "properties");
    try jsonBeginObject(json);
    for (parameters.properties) |property| {
        try jsonObjectFieldIdentifier(json, property.name);
        try jsonBeginObject(json);
        try jsonObjectField(json, "type");
        try jsonWriteString(json, @tagName(property.kind));
        if (property.description) |description| {
            try jsonObjectField(json, "description");
            try jsonWriteString(json, description);
        }
        try jsonEndObject(json);
    }
    try jsonEndObject(json);
    try jsonObjectField(json, "required");
    try jsonBeginArray(json);
    for (parameters.required) |name| try jsonWriteObjectIdentifier(json, name);
    try jsonEndArray(json);
    try jsonObjectField(json, "additionalProperties");
    try jsonWrite(json, parameters.additional_properties);
    try jsonEndObject(json);
}

fn validateToolDefinitions(tools: []const ToolDefinition) BuildError!void {
    for (tools, 0..) |tool, index| {
        try validateToolName(tool.name);
        for (tools[0..index]) |previous| {
            if (std.mem.eql(u8, previous.name, tool.name)) return error.InvalidRequestText;
        }
    }
}

fn validateToolParameters(parameters: ToolParameters) BuildError!void {
    for (parameters.properties, 0..) |property, index| {
        try validateObjectIdentifier(property.name);
        for (parameters.properties[0..index]) |previous| {
            if (std.mem.eql(u8, previous.name, property.name)) return error.InvalidRequestText;
        }
    }

    for (parameters.required, 0..) |required_name, index| {
        try validateObjectIdentifier(required_name);
        for (parameters.required[0..index]) |previous| {
            if (std.mem.eql(u8, previous, required_name)) return error.InvalidRequestText;
        }
        if (!hasProperty(parameters.properties, required_name)) return error.InvalidRequestText;
    }
}

fn hasProperty(properties: []const ToolParameter, name: []const u8) bool {
    for (properties) |property| {
        if (std.mem.eql(u8, property.name, name)) return true;
    }
    return false;
}

fn jsonBeginObject(json: *std.json.Stringify) BuildError!void {
    json.beginObject() catch return error.OutOfMemory;
}

fn jsonEndObject(json: *std.json.Stringify) BuildError!void {
    json.endObject() catch return error.OutOfMemory;
}

fn jsonObjectField(json: *std.json.Stringify, name: []const u8) BuildError!void {
    json.objectField(name) catch return error.OutOfMemory;
}

fn jsonObjectFieldIdentifier(json: *std.json.Stringify, name: []const u8) BuildError!void {
    try validateObjectIdentifier(name);
    return jsonObjectField(json, name);
}

fn jsonBeginArray(json: *std.json.Stringify) BuildError!void {
    json.beginArray() catch return error.OutOfMemory;
}

fn jsonEndArray(json: *std.json.Stringify) BuildError!void {
    json.endArray() catch return error.OutOfMemory;
}

fn jsonWrite(json: *std.json.Stringify, value: anytype) BuildError!void {
    json.write(value) catch return error.OutOfMemory;
}

fn jsonWriteString(json: *std.json.Stringify, value: []const u8) BuildError!void {
    try validateJsonString(value);
    return jsonWrite(json, value);
}

fn jsonWriteSingleLineString(json: *std.json.Stringify, value: []const u8) BuildError!void {
    try validateJsonSingleLineString(value);
    return jsonWrite(json, value);
}

fn jsonWriteRole(json: *std.json.Stringify, value: []const u8) BuildError!void {
    if (!isRequestRole(value)) return error.InvalidRequestText;
    return jsonWrite(json, value);
}

fn jsonWriteToolName(json: *std.json.Stringify, value: []const u8) BuildError!void {
    try validateToolName(value);
    return jsonWrite(json, value);
}

fn jsonWriteToolCallId(json: *std.json.Stringify, value: []const u8) BuildError!void {
    try validateToolCallId(value);
    return jsonWrite(json, value);
}

fn jsonWriteObjectIdentifier(json: *std.json.Stringify, value: []const u8) BuildError!void {
    try validateObjectIdentifier(value);
    return jsonWrite(json, value);
}

fn validateJsonString(value: []const u8) BuildError!void {
    if (!isValidText(value)) return error.InvalidRequestText;
}

fn validateJsonSingleLineString(value: []const u8) BuildError!void {
    if (value.len == 0) return error.InvalidRequestText;
    if (!isValidSingleLineText(value)) return error.InvalidRequestText;
}

fn validateToolName(value: []const u8) BuildError!void {
    if (!isToolName(value)) return error.InvalidRequestText;
}

fn validateToolCallId(value: []const u8) BuildError!void {
    if (!isToolCallId(value)) return error.InvalidRequestText;
}

fn validateObjectIdentifier(value: []const u8) BuildError!void {
    if (!isToolName(value)) return error.InvalidRequestText;
}

fn isValidText(value: []const u8) bool {
    return text_policy.isMultilineText(value);
}

fn isValidSingleLineText(value: []const u8) bool {
    return text_policy.isSingleLineText(value);
}

pub fn isRequestRole(value: []const u8) bool {
    return std.mem.eql(u8, value, "system") or
        std.mem.eql(u8, value, "user") or
        std.mem.eql(u8, value, "assistant") or
        std.mem.eql(u8, value, "tool");
}

pub fn isToolName(value: []const u8) bool {
    if (value.len == 0 or value.len > max_tool_name_bytes) return false;
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        if (byte == '_' or byte == '-') continue;
        return false;
    }
    return true;
}

fn isToolCallId(value: []const u8) bool {
    return value.len != 0 and value.len <= max_tool_call_id_bytes and isValidSingleLineText(value);
}

pub const AssistantResponse = struct {
    content: ?[]u8 = null,
    tool_calls: []ToolCall = &.{},

    pub fn deinit(self: *AssistantResponse, allocator: Allocator) void {
        if (self.content) |content| allocator.free(content);
        for (self.tool_calls) |call| {
            allocator.free(call.id);
            allocator.free(call.name);
            allocator.free(call.arguments);
        }
        allocator.free(self.tool_calls);
        self.* = .{};
    }

    pub fn takeContent(self: *AssistantResponse) DecodeError![]u8 {
        const content = self.content orelse return error.MissingMessageContent;
        if (content.len == 0) return error.MissingMessageContent;
        self.content = null;
        return content;
    }
};

pub fn extractAssistantResponse(allocator: Allocator, body: []const u8) DecodeError!AssistantResponse {
    const parsed = std.json.parseFromSlice(CompletionResponse, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidResponse,
    };
    defer parsed.deinit();

    if (parsed.value.choices.len == 0) return error.MissingChoice;
    const message = parsed.value.choices[0].message;
    if (message.role) |role| {
        if (!std.mem.eql(u8, role, "assistant")) return error.InvalidResponse;
    }

    var response: AssistantResponse = .{};
    errdefer response.deinit(allocator);

    if (message.content) |content| {
        if (!isValidText(content)) return error.InvalidResponse;
        response.content = try allocator.dupe(u8, content);
    }

    if (message.tool_calls.len > 0) {
        var calls: std.ArrayList(ToolCall) = .empty;
        errdefer {
            for (calls.items) |call| {
                allocator.free(call.id);
                allocator.free(call.name);
                allocator.free(call.arguments);
            }
            calls.deinit(allocator);
        }

        for (message.tool_calls) |raw| {
            const function = raw.function orelse return error.MissingToolCall;
            if (!std.mem.eql(u8, raw.type, "function")) return error.MissingToolCall;
            if (raw.id.len == 0 or function.name.len == 0) return error.MissingToolCall;
            const raw_arguments = function.arguments orelse return error.MissingToolCall;
            if (raw_arguments.len == 0) return error.MissingToolCall;
            if (!isToolCallId(raw.id) or !isToolName(function.name) or !isValidText(raw_arguments)) {
                return error.InvalidResponse;
            }
            for (calls.items) |previous| {
                if (std.mem.eql(u8, previous.id, raw.id)) return error.InvalidResponse;
            }
            const id = try allocator.dupe(u8, raw.id);
            errdefer allocator.free(id);
            const name = try allocator.dupe(u8, function.name);
            errdefer allocator.free(name);
            const arguments = try allocator.dupe(u8, raw_arguments);
            errdefer allocator.free(arguments);
            try calls.append(allocator, .{
                .id = id,
                .name = name,
                .arguments = arguments,
            });
        }
        response.tool_calls = try calls.toOwnedSlice(allocator);
    }

    if (response.content == null and response.tool_calls.len == 0) return error.MissingMessageContent;
    return response;
}

pub fn extractAssistantMessage(allocator: Allocator, body: []const u8) DecodeError![]u8 {
    var response = try extractAssistantResponse(allocator, body);
    defer response.deinit(allocator);
    return response.takeContent();
}

pub fn apiErrorMessage(allocator: Allocator, body: []const u8) Allocator.Error!?[]u8 {
    const parsed = std.json.parseFromSlice(ApiErrorResponse, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer parsed.deinit();

    const api_error = parsed.value.@"error" orelse return null;
    if (!isDiagnosticMessageText(api_error.message)) return null;
    return try allocator.dupe(u8, api_error.message);
}

fn isDiagnosticMessageText(value: []const u8) bool {
    return value.len != 0 and
        value.len <= max_diagnostic_message_bytes and
        text_policy.isSingleLineText(value);
}

pub fn extractStreamDelta(allocator: Allocator, data: []const u8) DecodeError!?[]u8 {
    const trimmed = std.mem.trim(u8, data, &std.ascii.whitespace);
    if (trimmed.len == 0 or isStreamDone(data)) return null;

    const parsed = std.json.parseFromSlice(StreamResponse, allocator, trimmed, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidResponse,
    };
    defer parsed.deinit();

    if (parsed.value.choices.len == 0) return null;
    const content = parsed.value.choices[0].delta.content orelse return null;
    if (content.len == 0) return null;
    if (!isValidText(content)) return error.InvalidResponse;
    return try allocator.dupe(u8, content);
}

pub fn isStreamDone(data: []const u8) bool {
    const trimmed = std.mem.trim(u8, data, &std.ascii.whitespace);
    return std.mem.eql(u8, trimmed, "[DONE]");
}

pub fn extractStreamMessage(allocator: Allocator, sse_body: []const u8) DecodeError![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    var lines = std.mem.splitScalar(u8, sse_body, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (!std.mem.startsWith(u8, line, "data:")) continue;
        const data = std.mem.trim(u8, line["data:".len..], " \t\r");
        if (isStreamDone(data)) break;
        if (try extractStreamDelta(allocator, data)) |delta| {
            defer allocator.free(delta);
            out.writer.writeAll(delta) catch return error.OutOfMemory;
        }
    }

    return out.toOwnedSlice() catch error.OutOfMemory;
}

test "request JSON escapes user input and uses exact chat message shape" {
    const messages = [_]RequestMessage{
        .{ .role = "system", .content = "system prompt" },
        .{ .role = "user", .content = "say \"hi\"\nnow" },
    };
    const body = try buildRequest(std.testing.allocator, "model", &messages);
    defer std.testing.allocator.free(body);

    const expected =
        "{\"model\":\"model\",\"messages\":[{\"role\":\"system\",\"content\":\"system prompt\"},{\"role\":\"user\",\"content\":\"say \\\"hi\\\"\\nnow\"}]}";
    try std.testing.expectEqualStrings(expected, body);
}

test "request JSON can opt into streaming" {
    const messages = [_]RequestMessage{
        .{ .role = "user", .content = "hello" },
    };
    const body = try buildRequestWithOptions(std.testing.allocator, "model", &messages, .{ .stream = true });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.indexOf(u8, body, "\"stream\":true") != null);
}

test "request JSON includes optional max token cap" {
    const body = try buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .max_tokens = 64 },
    );
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.indexOf(u8, body, "\"max_tokens\":64") != null);
}

test "request JSON rejects invalid utf-8 strings" {
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "",
        &.{.{ .role = "user", .content = "hello" }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "bad\xff" }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "bad\xff",
        &.{.{ .role = "user", .content = "hello" }},
    ));
}

test "request JSON rejects binary control bytes in text strings" {
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "bad\x00value" }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "bad\x1bvalue" }},
    ));
}

test "request JSON rejects multiline metadata strings" {
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "bad\nmodel",
        &.{.{ .role = "user", .content = "hello" }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user\nrole", .content = "hello" }},
    ));

    const calls = [_]ToolCall{
        .{ .id = "call\n1", .name = "lookup_memory", .arguments = "{}" },
    };
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = null, .tool_calls = &calls }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "tool", .content = "ok", .tool_call_id = "call\t1" }},
    ));
}

test "request JSON rejects invalid protocol identifiers" {
    try std.testing.expect(isRequestRole("system"));
    try std.testing.expect(isRequestRole("user"));
    try std.testing.expect(isRequestRole("assistant"));
    try std.testing.expect(isRequestRole("tool"));
    try std.testing.expect(!isRequestRole("developer"));

    try std.testing.expect(isToolName("lookup_memory"));
    try std.testing.expect(isToolName("lookup-memory"));
    try std.testing.expect(!isToolName(""));
    try std.testing.expect(!isToolName("lookup memory"));
    try std.testing.expect(!isToolName("lookup.memory"));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "developer", .content = "hello" }},
    ));

    const empty_id = [_]ToolCall{
        .{ .id = "", .name = "lookup_memory", .arguments = "{}" },
    };
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = null, .tool_calls = &empty_id }},
    ));

    const duplicate_id = [_]ToolCall{
        .{ .id = "call_1", .name = "lookup_memory", .arguments = "{}" },
        .{ .id = "call_1", .name = "lookup_memory", .arguments = "{}" },
    };
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = null, .tool_calls = &duplicate_id }},
    ));

    var long_id_bytes: [max_tool_call_id_bytes + 1]u8 = undefined;
    @memset(&long_id_bytes, 'a');
    const long_id = [_]ToolCall{
        .{ .id = long_id_bytes[0..], .name = "lookup_memory", .arguments = "{}" },
    };
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = null, .tool_calls = &long_id }},
    ));

    const bad_name = [_]ToolCall{
        .{ .id = "call_1", .name = "lookup memory", .arguments = "{}" },
    };
    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = null, .tool_calls = &bad_name }},
    ));

    const empty_required = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Empty required name.",
        .parameters = .{
            .properties = &.{.{ .name = "key", .kind = .string }},
            .required = &.{""},
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &empty_required },
    ));

    const bad_required = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Bad required name.",
        .parameters = .{
            .properties = &.{.{ .name = "key", .kind = .string }},
            .required = &.{"bad key"},
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &bad_required },
    ));

    const unknown_required = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Unknown required name.",
        .parameters = .{
            .properties = &.{.{ .name = "key", .kind = .string }},
            .required = &.{"missing"},
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &unknown_required },
    ));

    const duplicate_required = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Duplicate required name.",
        .parameters = .{
            .properties = &.{.{ .name = "key", .kind = .string }},
            .required = &.{ "key", "key" },
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &duplicate_required },
    ));

    const duplicate_properties = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Duplicate property name.",
        .parameters = .{
            .properties = &.{
                .{ .name = "key", .kind = .string },
                .{ .name = "key", .kind = .integer },
            },
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &duplicate_properties },
    ));

    const duplicate_tools = [_]ToolDefinition{
        .{
            .name = "lookup_memory",
            .description = "First.",
            .parameters = .{ .properties = &.{} },
        },
        .{
            .name = "lookup_memory",
            .description = "Second.",
            .parameters = .{ .properties = &.{} },
        },
    };
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &duplicate_tools },
    ));
}

test "request JSON rejects invalid message shapes" {
    const calls = [_]ToolCall{
        .{ .id = "call_1", .name = "lookup_memory", .arguments = "{}" },
    };

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "system", .content = null }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello", .tool_calls = &calls }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = null }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "assistant", .content = "hello", .tool_call_id = "call_1" }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "tool", .content = "ok" }},
    ));

    try std.testing.expectError(error.InvalidRequestText, buildRequest(
        std.testing.allocator,
        "model",
        &.{.{ .role = "tool", .content = "ok", .tool_call_id = "call_1", .tool_calls = &calls }},
    ));
}

test "request JSON includes tools and tool result messages" {
    const calls = [_]ToolCall{
        .{ .id = "call_1", .name = "lookup_memory", .arguments = "{\"key\":\"cwd\"}" },
    };
    const messages = [_]RequestMessage{
        .{ .role = "user", .content = "inspect" },
        .{ .role = "assistant", .content = null, .tool_calls = &calls },
        .{ .role = "tool", .content = "ok", .tool_call_id = "call_1" },
    };
    const tools = [_]ToolDefinition{
        .{
            .name = "lookup_memory",
            .description = "Look up a memory key.",
            .parameters = .{
                .properties = &.{.{ .name = "key", .kind = .string }},
                .required = &.{"key"},
            },
        },
    };
    const body = try buildRequestWithOptions(std.testing.allocator, "model", &messages, .{ .tools = &tools });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.indexOf(u8, body, "\"tools\":[{\"type\":\"function\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tool_choice\":\"auto\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"assistant\",\"content\":\"\",\"tool_calls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tool_calls\":[{\"id\":\"call_1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"tool\",\"content\":\"ok\",\"tool_call_id\":\"call_1\"") != null);
}

test "request JSON rejects invalid utf-8 tool metadata" {
    const tools = [_]ToolDefinition{
        .{
            .name = "bad\xff",
            .description = "Bad tool.",
            .parameters = .{ .properties = &.{} },
        },
    };

    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &tools },
    ));

    const multiline_name = [_]ToolDefinition{.{
        .name = "lookup\nmemory",
        .description = "Bad tool.",
        .parameters = .{ .properties = &.{} },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &multiline_name },
    ));

    const multiline_property = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Bad property.",
        .parameters = .{
            .properties = &.{.{ .name = "bad\nkey", .kind = .string }},
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &multiline_property },
    ));

    const bad_property = [_]ToolDefinition{.{
        .name = "lookup_memory",
        .description = "Bad property.",
        .parameters = .{
            .properties = &.{.{ .name = "bad key", .kind = .string }},
        },
    }};
    try std.testing.expectError(error.InvalidRequestText, buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "hello" }},
        .{ .tools = &bad_property },
    ));
}

test "request JSON writes tool parameter metadata exactly" {
    const tools = [_]ToolDefinition{
        .{
            .name = "configure",
            .description = "Configure a value.",
            .parameters = .{
                .properties = &.{
                    .{ .name = "enabled", .kind = .boolean, .description = "Feature flag." },
                    .{ .name = "count", .kind = .integer },
                },
                .required = &.{ "enabled", "count" },
                .additional_properties = true,
            },
        },
    };
    const body = try buildRequestWithOptions(
        std.testing.allocator,
        "model",
        &.{.{ .role = "user", .content = "configure" }},
        .{ .tools = &tools },
    );
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.indexOf(u8, body, "\"enabled\":{\"type\":\"boolean\",\"description\":\"Feature flag.\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"count\":{\"type\":\"integer\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"required\":[\"enabled\",\"count\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"additionalProperties\":true") != null);
}

test "extracts assistant message content" {
    const body =
        \\{
        \\  "choices": [
        \\    {
        \\      "message": {
        \\        "role": "assistant",
        \\        "content": "hello"
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const text = try extractAssistantMessage(std.testing.allocator, body);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("hello", text);
}

test "rejects non-assistant provider message role when present" {
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"role\":\"user\",\"content\":\"hello\"}}]}"),
    );

    const text = try extractAssistantMessage(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"content\":\"hello\"}}]}",
    );
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("hello", text);
}

test "extracts assistant tool calls" {
    const body =
        \\{
        \\  "choices": [
        \\    {
        \\      "message": {
        \\        "role": "assistant",
        \\        "content": null,
        \\        "tool_calls": [
        \\          {
        \\            "id": "call_abc",
        \\            "type": "function",
        \\            "function": {
        \\              "name": "lookup_memory",
        \\              "arguments": "{\"key\":\"cwd\"}"
        \\            }
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    var response = try extractAssistantResponse(std.testing.allocator, body);
    defer response.deinit(std.testing.allocator);
    try std.testing.expect(response.content == null);
    try std.testing.expectEqual(@as(usize, 1), response.tool_calls.len);
    try std.testing.expectEqualStrings("call_abc", response.tool_calls[0].id);
    try std.testing.expectEqualStrings("lookup_memory", response.tool_calls[0].name);
    try std.testing.expectEqualStrings("{\"key\":\"cwd\"}", response.tool_calls[0].arguments);
}

test "rejects malformed assistant tool calls" {
    try std.testing.expectError(error.MissingToolCall, extractAssistantResponse(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"custom\",\"function\":{\"name\":\"x\",\"arguments\":\"{}\"}}]}}]}",
    ));
    try std.testing.expectError(error.MissingToolCall, extractAssistantResponse(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\"}]}}]}",
    ));
    try std.testing.expectError(error.MissingToolCall, extractAssistantResponse(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"\",\"type\":\"function\",\"function\":{\"name\":\"x\",\"arguments\":\"{}\"}}]}}]}",
    ));
    try std.testing.expectError(error.MissingToolCall, extractAssistantResponse(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"x\"}}]}}]}",
    ));
    try std.testing.expectError(error.MissingToolCall, extractAssistantResponse(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"x\",\"arguments\":\"\"}}]}}]}",
    ));

    var long_id_bytes: [max_tool_call_id_bytes + 1]u8 = undefined;
    @memset(&long_id_bytes, 'a');
    const long_id_body = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"choices\":[{{\"message\":{{\"tool_calls\":[{{\"id\":\"{s}\",\"type\":\"function\",\"function\":{{\"name\":\"x\",\"arguments\":\"{{}}\"}}}}]}}}}]}}",
        .{long_id_bytes[0..]},
    );
    defer std.testing.allocator.free(long_id_body);
    try std.testing.expectError(error.InvalidResponse, extractAssistantResponse(
        std.testing.allocator,
        long_id_body,
    ));

    try std.testing.expectError(error.InvalidResponse, extractAssistantResponse(
        std.testing.allocator,
        "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"x\",\"arguments\":\"{}\"}},{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"x\",\"arguments\":\"{}\"}}]}}]}",
    ));
}

test "detects missing choices and null content" {
    try std.testing.expectError(error.MissingChoice, extractAssistantMessage(std.testing.allocator, "{\"choices\":[]}"));
    try std.testing.expectError(
        error.MissingMessageContent,
        extractAssistantMessage(std.testing.allocator, "{\"choices\":[{\"message\":{\"content\":null}}]}"),
    );
    try std.testing.expectError(
        error.MissingMessageContent,
        extractAssistantMessage(std.testing.allocator, "{\"choices\":[{\"message\":{\"content\":\"\"}}]}"),
    );
}

test "maps malformed provider JSON to invalid response" {
    try std.testing.expectError(error.InvalidResponse, extractAssistantResponse(std.testing.allocator, "not-json"));
    try std.testing.expectError(error.InvalidResponse, extractStreamDelta(std.testing.allocator, "not-json"));
}

test "rejects binary control bytes decoded from provider text" {
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"content\":\"bad\\u0000value\"}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"content\":\"bad\\u001bvalue\"}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup_memory\",\"arguments\":\"bad\\u0000value\"}}]}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup_memory\",\"arguments\":\"bad\\u001bvalue\"}}]}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call\\n1\",\"type\":\"function\",\"function\":{\"name\":\"lookup_memory\",\"arguments\":\"{}\"}}]}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup\\tmemory\",\"arguments\":\"{}\"}}]}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractAssistantResponse(std.testing.allocator, "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup memory\",\"arguments\":\"{}\"}}]}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractStreamDelta(std.testing.allocator, "{\"choices\":[{\"delta\":{\"content\":\"bad\\u0000value\"}}]}"),
    );
    try std.testing.expectError(
        error.InvalidResponse,
        extractStreamDelta(std.testing.allocator, "{\"choices\":[{\"delta\":{\"content\":\"bad\\u001bvalue\"}}]}"),
    );
}

test "extracts API error message" {
    const message = (try apiErrorMessage(
        std.testing.allocator,
        "{\"error\":{\"message\":\"bad key\",\"type\":\"invalid_request_error\"}}",
    )).?;
    defer std.testing.allocator.free(message);
    try std.testing.expectEqualStrings("bad key", message);
}

test "API error parser ignores unsafe diagnostic messages" {
    try std.testing.expect((try apiErrorMessage(
        std.testing.allocator,
        "{\"error\":{\"message\":\"\",\"type\":\"invalid_request_error\"}}",
    )) == null);
    try std.testing.expect((try apiErrorMessage(
        std.testing.allocator,
        "{\"error\":{\"message\":\"bad\\u001b[31m\",\"type\":\"invalid_request_error\"}}",
    )) == null);
    try std.testing.expect((try apiErrorMessage(
        std.testing.allocator,
        "{\"error\":{\"message\":\"bad\\nkey\",\"type\":\"invalid_request_error\"}}",
    )) == null);
    try std.testing.expect((try apiErrorMessage(
        std.testing.allocator,
        "{\"error\":{\"message\":\"bad\\u0000key\",\"type\":\"invalid_request_error\"}}",
    )) == null);

    const long_message = try std.testing.allocator.alloc(u8, max_diagnostic_message_bytes + 1);
    defer std.testing.allocator.free(long_message);
    @memset(long_message, 'x');

    const body = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"error\":{{\"message\":\"{s}\",\"type\":\"invalid_request_error\"}}}}",
        .{long_message},
    );
    defer std.testing.allocator.free(body);
    try std.testing.expect((try apiErrorMessage(std.testing.allocator, body)) == null);
}

test "API error parser preserves allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            const maybe_message = try apiErrorMessage(
                allocator,
                "{\"error\":{\"message\":\"bad key\",\"type\":\"invalid_request_error\"}}",
            );
            const message = maybe_message orelse return error.TestUnexpectedResult;
            defer allocator.free(message);
            try std.testing.expectEqualStrings("bad key", message);
        }
    }.run, .{});
}

test "extracts streaming delta content and done sentinel" {
    const delta = (try extractStreamDelta(
        std.testing.allocator,
        "{\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}",
    )).?;
    defer std.testing.allocator.free(delta);
    try std.testing.expectEqualStrings("Hel", delta);

    try std.testing.expect((try extractStreamDelta(std.testing.allocator, "[DONE]")) == null);
    try std.testing.expect((try extractStreamDelta(std.testing.allocator, "{\"choices\":[]}")) == null);
    try std.testing.expect((try extractStreamDelta(std.testing.allocator, "{\"choices\":[{\"delta\":{\"content\":\"\"}}]}")) == null);
}

test "extracts full assistant message from SSE body" {
    const body =
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\n" ++
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\r\n\r\n" ++
        "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\n" ++
        "data: [DONE]\n\n";

    const text = try extractStreamMessage(std.testing.allocator, body);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Hello", text);
}

test "stream message stops at done sentinel" {
    const body =
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n" ++
        "data: [DONE]\n\n" ++
        "data: {\"choices\":[{\"delta\":{\"content\":\"late\"}}]}\n\n";

    const text = try extractStreamMessage(std.testing.allocator, body);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("Hel", text);
}
