const std = @import("std");
const agent = @import("../agent.zig");
const chat = @import("../chat.zig");
const config = @import("../config.zig");
const file_memory = @import("../adapters/file_memory.zig");
const http = @import("../ports/http.zig");
const providers = @import("../providers.zig");
const scheduler = @import("../scheduler.zig");
const tool_catalog = @import("../tools/catalog.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn withoutStream(
    allocator: Allocator,
    client: http.Client,
    target: providers.Resolved,
    cfg: config.RuntimeConfig,
    history: []const chat.RequestMessage,
    prompt: []const u8,
    system_prompt: []const u8,
    diagnostic: *agent.Diagnostic,
) ![]u8 {
    return agent.completeResolvedWithOptions(
        allocator,
        client,
        target,
        cfg.completion.model,
        cfg.completion.max_tokens,
        prompt,
        .{
            .history = history,
            .system_prompt = system_prompt,
        },
        diagnostic,
    );
}

pub fn withTools(
    allocator: Allocator,
    io: Io,
    client: http.Client,
    target: providers.Resolved,
    cfg: config.RuntimeConfig,
    history: []const chat.RequestMessage,
    prompt: []const u8,
    system_prompt: []const u8,
    schedule_destination: scheduler.Destination,
    diagnostic: *agent.Diagnostic,
) ![]u8 {
    var facts_store: ?file_memory.FactStore = if (cfg.memory.enabled) .{
        .io = io,
        .path = cfg.memory.facts_path orelse return error.MissingHome,
    } else null;
    var catalog = try tool_catalog.Catalog.init(
        allocator,
        io,
        client,
        cfg,
        if (facts_store) |*store| store.port() else null,
        cfg.schedule.path,
        schedule_destination,
        history.len,
    );
    defer catalog.deinit(allocator);

    return withToolOptions(
        allocator,
        client,
        target,
        cfg,
        history,
        prompt,
        system_prompt,
        try catalog.options(),
        diagnostic,
    );
}

fn withToolOptions(
    allocator: Allocator,
    client: http.Client,
    target: providers.Resolved,
    cfg: config.RuntimeConfig,
    history: []const chat.RequestMessage,
    prompt: []const u8,
    system_prompt: []const u8,
    tool_options: agent.ToolOptions,
    diagnostic: *agent.Diagnostic,
) ![]u8 {
    return agent.completeResolvedWithOptions(
        allocator,
        client,
        target,
        cfg.completion.model,
        cfg.completion.max_tokens,
        prompt,
        .{
            .history = history,
            .system_prompt = system_prompt,
            .tools = tool_options,
        },
        diagnostic,
    );
}
