const std = @import("std");

const agent_mod = @import("./agent.zig");
const chat_mod = @import("./chat.zig");
const config_mod = @import("./config.zig");
const http_mod = @import("./ports/http.zig");
const persona_mod = @import("./persona.zig");
const provider_mod = @import("./providers.zig");
const tool_mod = @import("./tools/registry.zig");

pub const ProviderKind = provider_mod.ProviderKind;
pub const PersonaKind = persona_mod.Kind;
pub const Config = config_mod.Config;

pub const RequestMessage = chat_mod.RequestMessage;
pub const ToolCall = chat_mod.ToolCall;
pub const ToolDefinition = chat_mod.ToolDefinition;
pub const ToolParameters = chat_mod.ToolParameters;
pub const ToolParameter = chat_mod.ToolParameter;
pub const ToolParameterKind = chat_mod.ToolParameterKind;

pub const ToolOptions = agent_mod.ToolOptions;
pub const ToolHandler = tool_mod.Handler;
pub const ToolRunError = tool_mod.RunError;
pub const StreamError = agent_mod.StreamError;
pub const StreamSink = agent_mod.StreamSink;
pub const CompleteOptions = agent_mod.CompleteOptions;

pub const HttpClient = http_mod.Client;
pub const HttpResponse = http_mod.Response;
pub const HttpHeader = http_mod.Header;
pub const HttpStatusCode = http_mod.StatusCode;
pub const Diagnostic = agent_mod.Diagnostic;

pub const complete = agent_mod.complete;
pub const completeWithOptions = agent_mod.completeWithOptions;

test "public stream sink dispatches through root API" {
    const Sink = struct {
        bytes: [16]u8 = undefined,
        len: usize = 0,

        fn write(ptr: *anyopaque, bytes: []const u8) StreamError!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            if (bytes.len > self.bytes.len) return error.WriteFailed;
            @memcpy(self.bytes[0..bytes.len], bytes);
            self.len = bytes.len;
        }
    };

    var state: Sink = .{};
    const sink: StreamSink = .{
        .ptr = &state,
        .write_fn = Sink.write,
    };
    try sink.write("delta");
    try std.testing.expectEqualStrings("delta", state.bytes[0..state.len]);
}

test "public tool handler dispatches through root API" {
    const Tool = struct {
        fn run(_: *anyopaque, allocator: std.mem.Allocator, _: ToolCall) ToolRunError![]u8 {
            return allocator.dupe(u8, "ok");
        }
    };

    var state: u8 = 0;
    const handler: ToolHandler = .{
        .definition = .{
            .name = "test_tool",
            .description = "Test tool.",
            .parameters = .{ .properties = &.{} },
        },
        .ptr = &state,
        .run_fn = Tool.run,
    };
    const options: ToolOptions = .{
        .enabled = true,
        .handlers = &.{handler},
    };
    try std.testing.expect(options.handlers.len == 1);

    const output = try options.handlers[0].run(std.testing.allocator, .{
        .id = "call_1",
        .name = "test_tool",
        .arguments = "{}",
    });
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("ok", output);
}
