const std = @import("std");
const path_policy = @import("../path_policy.zig");
const persona = @import("../persona.zig");
const providers = @import("../providers.zig");
const source_mod = @import("./source.zig");
const telegram_identity = @import("../telegram/identity.zig");
const text_policy = @import("../text_policy.zig");
const telegram_token = @import("../telegram/token.zig");
const types = @import("./types.zig");
const websocket_config = @import("./websocket.zig");

const Allocator = std.mem.Allocator;
const Source = source_mod.Source;

pub const LoadError = error{
    MissingProvider,
    MissingApiKey,
    MissingModel,
    InvalidModel,
    MissingBaseUrl,
    EmptyBaseUrl,
    InvalidBaseUrl,
    InsecureBaseUrl,
    InvalidHeaderValue,
    UnknownProvider,
    InvalidMaxTokens,
    InvalidAllowHttpBaseUrl,
    InvalidPersona,
    InvalidMemory,
    InvalidMemoryPath,
    InvalidMemoryFactsPath,
    InvalidMemoryMaxFacts,
    InvalidMemoryMaxMessages,
    InvalidTools,
    InvalidFileRead,
    InvalidFileWrite,
    InvalidScheduleTools,
    InvalidUserToolsPath,
    InvalidShell,
    InvalidToolMaxRounds,
    InvalidToolOutputMaxBytes,
    InvalidToolTimeoutMs,
    InvalidStream,
    InvalidTelegramToken,
    InvalidTelegramChatId,
    InvalidTelegramPollTimeout,
    InvalidTelegramRateLimit,
    InvalidSearchProvider,
    MissingSearchKey,
    InvalidSearchKey,
    InvalidSearchDuckDuckGo,
    InvalidSchedulePath,
    InvalidDaemonIntervalSeconds,
    InvalidHeartbeatIntervalSeconds,
    InvalidTimezoneOffsetMinutes,
} || websocket_config.ParseError;

pub const Owned = struct {
    value: types.RuntimeConfig,

    pub fn deinit(self: *Owned, allocator: Allocator) void {
        allocator.free(self.value.completion.api_key);
        allocator.free(self.value.completion.model);
        if (self.value.completion.base_url) |value| allocator.free(value);
        if (self.value.completion.http_referer) |value| allocator.free(value);
        if (self.value.completion.app_title) |value| allocator.free(value);
        if (self.value.memory.path) |value| allocator.free(value);
        if (self.value.memory.facts_path) |value| allocator.free(value);
        if (self.value.tools.user_tools_path) |value| allocator.free(value);
        if (self.value.telegram.token) |value| allocator.free(value);
        if (self.value.telegram.chat_id) |chat| switch (chat) {
            .id => {},
            .username => |value| allocator.free(value),
        };
        allocator.free(self.value.websocket.host);
        allocator.free(self.value.websocket.path);
        if (self.value.websocket.token) |value| allocator.free(value);
        if (self.value.search.tavily_key) |value| allocator.free(value);
        if (self.value.search.brave_key) |value| allocator.free(value);
        if (self.value.search.exa_key) |value| allocator.free(value);
        if (self.value.search.firecrawl_key) |value| allocator.free(value);
        if (self.value.schedule.path) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub fn fromSources(env: Source, dotenv: Source) LoadError!types.RuntimeConfig {
    return fromSourcesWithFeatures(env, dotenv, .{});
}

pub fn fromSourcesWithFeatures(
    env: Source,
    dotenv: Source,
    comptime features: types.Features,
) LoadError!types.RuntimeConfig {
    return .{
        .completion = try resolveCompletion(env, dotenv),
        .persona = try parsePersona(pick(env.persona, dotenv.persona)),
        .memory = try resolveMemory(env, dotenv),
        .tools = try resolveTools(env, dotenv, features),
        .telegram = try resolveTelegram(env, dotenv),
        .websocket = try resolveWebSocket(env, dotenv),
        .search = try resolveSearch(env, dotenv),
        .schedule = try resolveSchedule(env, dotenv),
        .timezone_offset_minutes = try parseTimezoneOffsetMinutes(pick(
            env.timezone_offset_minutes,
            dotenv.timezone_offset_minutes,
        )),
        .stream = try parseStreamEnabled(pick(env.stream, dotenv.stream)),
    };
}

fn resolveCompletion(env: Source, dotenv: Source) LoadError!types.Config {
    const provider_name = pick(env.provider, dotenv.provider) orelse return error.MissingProvider;
    const kind = parseProvider(provider_name) orelse return error.UnknownProvider;
    const api_key = pick(env.api_key, dotenv.api_key) orelse return error.MissingApiKey;
    const model = try parseModel(pick(env.model, dotenv.model));
    const base_url = pick(env.base_url, dotenv.base_url);
    const http_referer = pick(env.http_referer, dotenv.http_referer);
    const app_title = pick(env.app_title, dotenv.app_title);
    const allow_insecure_base_url = try parseAllowHttpBaseUrl(pick(
        env.allow_http_base_url,
        dotenv.allow_http_base_url,
    ));

    try providers.validateHeaderValue(api_key);
    if (http_referer) |value| try providers.validateHeaderValue(value);
    if (app_title) |value| try providers.validateHeaderValue(value);

    if (kind == .compatible) {
        const value = base_url orelse return error.MissingBaseUrl;
        _ = try providers.validateCompatibleBaseUrl(value, allow_insecure_base_url);
    }

    return .{
        .provider = kind,
        .api_key = api_key,
        .model = model,
        .max_tokens = try parseMaxTokens(pick(env.max_tokens, dotenv.max_tokens)),
        .base_url = base_url,
        .allow_insecure_base_url = allow_insecure_base_url,
        .http_referer = http_referer,
        .app_title = app_title,
    };
}

fn resolveMemory(env: Source, dotenv: Source) LoadError!types.MemoryConfig {
    return .{
        .enabled = try parseMemoryEnabled(pick(env.memory, dotenv.memory)),
        .path = try parseStatePath(pick(env.memory_path, dotenv.memory_path), error.InvalidMemoryPath),
        .max_messages = try parseMemoryMaxMessages(pick(env.memory_max_messages, dotenv.memory_max_messages)),
        .facts_path = try parseStatePath(pick(env.memory_facts_path, dotenv.memory_facts_path), error.InvalidMemoryFactsPath),
        .max_facts = try parseMemoryMaxFacts(pick(env.memory_max_facts, dotenv.memory_max_facts)),
    };
}

fn resolveTools(
    env: Source,
    dotenv: Source,
    comptime features: types.Features,
) LoadError!types.ToolsConfig {
    if (comptime !features.shell_tool) {
        if (pick(env.shell, dotenv.shell) != null) return error.InvalidShell;
        if (pick(env.tool_timeout_ms, dotenv.tool_timeout_ms) != null) return error.InvalidToolTimeoutMs;
    }

    return .{
        .enabled = try parseToolsEnabled(pick(env.tools, dotenv.tools)),
        .shell_enabled = if (comptime features.shell_tool) try parseShellEnabled(pick(env.shell, dotenv.shell)) else false,
        .file_read_enabled = try parseFileReadEnabled(pick(env.file_read, dotenv.file_read)),
        .file_write_enabled = try parseFileWriteEnabled(pick(env.file_write, dotenv.file_write)),
        .schedule_enabled = try parseScheduleToolsEnabled(pick(env.schedule_tools, dotenv.schedule_tools)),
        .user_tools_path = try parseStatePath(pick(env.user_tools_path, dotenv.user_tools_path), error.InvalidUserToolsPath),
        .max_rounds = try parseToolMaxRounds(pick(env.tool_max_rounds, dotenv.tool_max_rounds)),
        .output_max_bytes = try parseToolOutputMaxBytes(pick(
            env.tool_output_max_bytes,
            dotenv.tool_output_max_bytes,
        )),
        .timeout_ms = if (comptime features.shell_tool)
            try parseToolTimeoutMs(pick(env.tool_timeout_ms, dotenv.tool_timeout_ms))
        else
            types.default_shell_timeout_ms,
    };
}

fn resolveTelegram(env: Source, dotenv: Source) LoadError!types.TelegramConfig {
    return .{
        .token = try parseTelegramToken(pick(env.telegram_token, dotenv.telegram_token)),
        .chat_id = try parseTelegramChatId(pick(env.telegram_chat_id, dotenv.telegram_chat_id)),
        .poll_timeout_seconds = try parseTelegramPollTimeout(pick(
            env.telegram_poll_timeout,
            dotenv.telegram_poll_timeout,
        )),
        .rate_limit_per_minute = try parseTelegramRateLimit(pick(
            env.telegram_rate_limit_per_minute,
            dotenv.telegram_rate_limit_per_minute,
        )),
    };
}

fn resolveWebSocket(env: Source, dotenv: Source) LoadError!types.WebSocketConfig {
    return websocket_config.fromRaw(.{
        .host = pick(env.websocket_host, dotenv.websocket_host),
        .port = pick(env.websocket_port, dotenv.websocket_port),
        .path = pick(env.websocket_path, dotenv.websocket_path),
        .token = pick(env.websocket_token, dotenv.websocket_token),
        .allow_remote = pick(env.websocket_allow_remote, dotenv.websocket_allow_remote),
        .rate_limit_per_minute = pick(
            env.websocket_rate_limit_per_minute,
            dotenv.websocket_rate_limit_per_minute,
        ),
    });
}

fn resolveSearch(env: Source, dotenv: Source) LoadError!types.SearchConfig {
    const cfg = types.SearchConfig{
        .provider = try parseSearchProvider(pick(env.search_provider, dotenv.search_provider)),
        .tavily_key = pick(env.search_tavily_key, dotenv.search_tavily_key),
        .brave_key = pick(env.search_brave_key, dotenv.search_brave_key),
        .exa_key = pick(env.search_exa_key, dotenv.search_exa_key),
        .firecrawl_key = pick(env.search_firecrawl_key, dotenv.search_firecrawl_key),
        .duckduckgo_enabled = try parseSearchDuckDuckGoEnabled(pick(
            env.search_duckduckgo,
            dotenv.search_duckduckgo,
        )),
    };

    try validateSearchKey(cfg.tavily_key);
    try validateSearchKey(cfg.brave_key);
    try validateSearchKey(cfg.exa_key);
    try validateSearchKey(cfg.firecrawl_key);
    try validateExplicitSearchProvider(cfg);
    return cfg;
}

fn resolveSchedule(env: Source, dotenv: Source) LoadError!types.ScheduleConfig {
    return .{
        .path = try parseStatePath(pick(env.schedule_path, dotenv.schedule_path), error.InvalidSchedulePath),
        .daemon_interval_seconds = try parseDaemonIntervalSeconds(pick(
            env.daemon_interval_seconds,
            dotenv.daemon_interval_seconds,
        )),
        .heartbeat_interval_seconds = try parseHeartbeatIntervalSeconds(pick(
            env.heartbeat_interval_seconds,
            dotenv.heartbeat_interval_seconds,
        )),
    };
}

pub fn fromSourcesOwned(allocator: Allocator, env: Source, dotenv: Source) (LoadError || Allocator.Error)!Owned {
    return fromSourcesOwnedWithFeatures(allocator, env, dotenv, .{});
}

pub fn fromSourcesOwnedWithFeatures(
    allocator: Allocator,
    env: Source,
    dotenv: Source,
    comptime features: types.Features,
) (LoadError || Allocator.Error)!Owned {
    const borrowed = try fromSourcesWithFeatures(env, dotenv, features);

    var owned: Owned = blk: {
        const api_key = try allocator.dupe(u8, borrowed.completion.api_key);
        errdefer allocator.free(api_key);
        const model = try allocator.dupe(u8, borrowed.completion.model);
        errdefer allocator.free(model);
        const websocket_host = try allocator.dupe(u8, borrowed.websocket.host);
        errdefer allocator.free(websocket_host);
        const websocket_path = try allocator.dupe(u8, borrowed.websocket.path);
        errdefer allocator.free(websocket_path);

        break :blk .{
            .value = .{
                .completion = .{
                    .provider = borrowed.completion.provider,
                    .api_key = api_key,
                    .model = model,
                    .max_tokens = borrowed.completion.max_tokens,
                    .allow_insecure_base_url = borrowed.completion.allow_insecure_base_url,
                },
                .persona = borrowed.persona,
                .memory = .{
                    .enabled = borrowed.memory.enabled,
                    .max_messages = borrowed.memory.max_messages,
                    .max_facts = borrowed.memory.max_facts,
                },
                .tools = .{
                    .enabled = borrowed.tools.enabled,
                    .shell_enabled = borrowed.tools.shell_enabled,
                    .file_read_enabled = borrowed.tools.file_read_enabled,
                    .file_write_enabled = borrowed.tools.file_write_enabled,
                    .schedule_enabled = borrowed.tools.schedule_enabled,
                    .max_rounds = borrowed.tools.max_rounds,
                    .output_max_bytes = borrowed.tools.output_max_bytes,
                    .timeout_ms = borrowed.tools.timeout_ms,
                },
                .telegram = .{
                    .poll_timeout_seconds = borrowed.telegram.poll_timeout_seconds,
                    .rate_limit_per_minute = borrowed.telegram.rate_limit_per_minute,
                },
                .websocket = .{
                    .host = websocket_host,
                    .port = borrowed.websocket.port,
                    .path = websocket_path,
                    .allow_remote = borrowed.websocket.allow_remote,
                    .rate_limit_per_minute = borrowed.websocket.rate_limit_per_minute,
                },
                .search = .{
                    .provider = borrowed.search.provider,
                    .duckduckgo_enabled = borrowed.search.duckduckgo_enabled,
                },
                .schedule = .{
                    .daemon_interval_seconds = borrowed.schedule.daemon_interval_seconds,
                    .heartbeat_interval_seconds = borrowed.schedule.heartbeat_interval_seconds,
                },
                .timezone_offset_minutes = borrowed.timezone_offset_minutes,
                .stream = borrowed.stream,
            },
        };
    };
    errdefer owned.deinit(allocator);

    if (borrowed.completion.base_url) |value| owned.value.completion.base_url = try allocator.dupe(u8, value);
    if (borrowed.completion.http_referer) |value| owned.value.completion.http_referer = try allocator.dupe(u8, value);
    if (borrowed.completion.app_title) |value| owned.value.completion.app_title = try allocator.dupe(u8, value);
    if (borrowed.memory.path) |value| owned.value.memory.path = try allocator.dupe(u8, value);
    if (borrowed.memory.facts_path) |value| owned.value.memory.facts_path = try allocator.dupe(u8, value);
    if (borrowed.tools.user_tools_path) |value| owned.value.tools.user_tools_path = try allocator.dupe(u8, value);
    if (borrowed.telegram.token) |value| owned.value.telegram.token = try allocator.dupe(u8, value);
    if (borrowed.telegram.chat_id) |chat| {
        owned.value.telegram.chat_id = switch (chat) {
            .id => |id| .{ .id = id },
            .username => |value| .{ .username = try allocator.dupe(u8, value) },
        };
    }
    if (borrowed.websocket.token) |value| owned.value.websocket.token = try allocator.dupe(u8, value);
    if (borrowed.search.tavily_key) |value| owned.value.search.tavily_key = try allocator.dupe(u8, value);
    if (borrowed.search.brave_key) |value| owned.value.search.brave_key = try allocator.dupe(u8, value);
    if (borrowed.search.exa_key) |value| owned.value.search.exa_key = try allocator.dupe(u8, value);
    if (borrowed.search.firecrawl_key) |value| owned.value.search.firecrawl_key = try allocator.dupe(u8, value);
    if (borrowed.schedule.path) |value| owned.value.schedule.path = try allocator.dupe(u8, value);

    return owned;
}

fn pick(primary: ?[]const u8, fallback: ?[]const u8) ?[]const u8 {
    return clean(primary) orelse clean(fallback);
}

fn clean(value: ?[]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    return if (trimmed.len == 0) null else trimmed;
}

fn parseProvider(value: []const u8) ?types.ProviderKind {
    if (std.mem.eql(u8, value, "openai")) return .openai;
    if (std.mem.eql(u8, value, "openrouter")) return .openrouter;
    if (std.mem.eql(u8, value, "compatible")) return .compatible;
    return null;
}

fn parseSearchProvider(value: ?[]const u8) LoadError!types.SearchProvider {
    const raw = clean(value) orelse return .auto;
    if (std.mem.eql(u8, raw, "auto")) return .auto;
    if (std.mem.eql(u8, raw, "tavily")) return .tavily;
    if (std.mem.eql(u8, raw, "brave")) return .brave;
    if (std.mem.eql(u8, raw, "exa")) return .exa;
    if (std.mem.eql(u8, raw, "firecrawl")) return .firecrawl;
    if (std.mem.eql(u8, raw, "duckduckgo")) return .duckduckgo;
    return error.InvalidSearchProvider;
}

fn parseSearchDuckDuckGoEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, false, error.InvalidSearchDuckDuckGo);
}

fn parseModel(value: ?[]const u8) LoadError![]const u8 {
    const raw = clean(value) orelse return error.MissingModel;
    if (!text_policy.isSingleLineText(raw)) return error.InvalidModel;
    return raw;
}

fn validateSearchKey(value: ?[]const u8) LoadError!void {
    const raw = value orelse return;
    for (raw) |byte| {
        if (byte < ' ' or byte == 0x7f) return error.InvalidSearchKey;
    }
}

fn validateExplicitSearchProvider(cfg: types.SearchConfig) LoadError!void {
    switch (cfg.provider) {
        .auto, .duckduckgo => {},
        .tavily => if (clean(cfg.tavily_key) == null) return error.MissingSearchKey,
        .brave => if (clean(cfg.brave_key) == null) return error.MissingSearchKey,
        .exa => if (clean(cfg.exa_key) == null) return error.MissingSearchKey,
        .firecrawl => if (clean(cfg.firecrawl_key) == null) return error.MissingSearchKey,
    }
}

fn parseAllowHttpBaseUrl(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, false, error.InvalidAllowHttpBaseUrl);
}

fn parsePersona(value: ?[]const u8) LoadError!types.PersonaKind {
    const raw = clean(value) orelse return persona.default_kind;
    return persona.parse(raw) orelse error.InvalidPersona;
}

fn parseMemoryEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, true, error.InvalidMemory);
}

fn parseToolsEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, types.default_tools_enabled, error.InvalidTools);
}

fn parseFileWriteEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, types.default_file_write_enabled, error.InvalidFileWrite);
}

fn parseFileReadEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, types.default_file_read_enabled, error.InvalidFileRead);
}

fn parseScheduleToolsEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, types.default_schedule_tools_enabled, error.InvalidScheduleTools);
}

fn parseShellEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, false, error.InvalidShell);
}

fn parseStreamEnabled(value: ?[]const u8) LoadError!bool {
    return parseBoolDefault(value, true, error.InvalidStream);
}

fn parseStatePath(value: ?[]const u8, invalid: LoadError) LoadError!?[]const u8 {
    const raw = clean(value) orelse return null;
    try validateStatePath(raw, invalid);
    return raw;
}

fn validateStatePath(path: []const u8, invalid: LoadError) LoadError!void {
    if (path.len == 0 or path.len > 512) return invalid;
    if (!text_policy.isSingleLineText(path)) return invalid;
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return invalid;
    if (!std.mem.endsWith(u8, path, ".jsonl")) return invalid;
    if (std.fs.path.parsePathPosix(path).kind != .relative) return invalid;
    if (std.fs.path.parsePathWindows(u8, path).kind != .relative) return invalid;

    var component_count: usize = 0;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0) return invalid;
        component_count += 1;
        if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return invalid;
        if (isDeniedStatePathComponent(component)) return invalid;
        if (path_policy.isWindowsReservedFilenameComponent(component)) return invalid;
    }
    if (component_count == 0) return invalid;
}

fn isDeniedStatePathComponent(component: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(component, ".env")) return true;
    if (std.ascii.startsWithIgnoreCase(component, ".env.")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".git")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".ssh")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".gnupg")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".aws")) return true;
    if (std.ascii.eqlIgnoreCase(component, ".npmrc")) return true;
    return false;
}

fn parseTelegramToken(value: ?[]const u8) LoadError!?[]const u8 {
    const raw = clean(value) orelse return null;
    if (!telegram_token.isValid(raw)) return error.InvalidTelegramToken;
    return raw;
}

fn parseTelegramChatId(value: ?[]const u8) LoadError!?types.TelegramChatAllowlist {
    const raw = clean(value) orelse return null;
    return telegram_identity.parseAllowlist(raw) orelse error.InvalidTelegramChatId;
}

fn parseTelegramPollTimeout(value: ?[]const u8) LoadError!u32 {
    return parseBoundedInt(
        u32,
        value,
        types.default_telegram_poll_timeout_seconds,
        0,
        60,
        error.InvalidTelegramPollTimeout,
    );
}

fn parseTelegramRateLimit(value: ?[]const u8) LoadError!u32 {
    return parseBoundedInt(
        u32,
        value,
        types.default_telegram_rate_limit_per_minute,
        0,
        10_000,
        error.InvalidTelegramRateLimit,
    );
}

fn parseDaemonIntervalSeconds(value: ?[]const u8) LoadError!u32 {
    return parseBoundedInt(
        u32,
        value,
        types.default_daemon_interval_seconds,
        1,
        86_400,
        error.InvalidDaemonIntervalSeconds,
    );
}

fn parseHeartbeatIntervalSeconds(value: ?[]const u8) LoadError!u32 {
    return parseBoundedInt(
        u32,
        value,
        types.default_heartbeat_interval_seconds,
        1,
        7 * 86_400,
        error.InvalidHeartbeatIntervalSeconds,
    );
}

fn parseTimezoneOffsetMinutes(value: ?[]const u8) LoadError!i32 {
    return parseBoundedInt(
        i32,
        value,
        types.default_timezone_offset_minutes,
        -14 * 60,
        14 * 60,
        error.InvalidTimezoneOffsetMinutes,
    );
}

fn parseBool(raw: []const u8) ?bool {
    if (std.mem.eql(u8, raw, "on")) return true;
    if (std.mem.eql(u8, raw, "off")) return false;
    return null;
}

fn parseBoolDefault(value: ?[]const u8, default: bool, invalid: LoadError) LoadError!bool {
    const raw = clean(value) orelse return default;
    return parseBool(raw) orelse invalid;
}

fn parseMaxTokens(value: ?[]const u8) LoadError!?u32 {
    return parseOptionalBoundedInt(
        u32,
        value,
        1,
        std.math.maxInt(u32),
        error.InvalidMaxTokens,
    );
}

fn parseMemoryMaxMessages(value: ?[]const u8) LoadError!usize {
    return parseBoundedInt(
        usize,
        value,
        types.default_memory_max_messages,
        types.min_memory_max_messages,
        std.math.maxInt(usize),
        error.InvalidMemoryMaxMessages,
    );
}

fn parseMemoryMaxFacts(value: ?[]const u8) LoadError!usize {
    return parseBoundedInt(
        usize,
        value,
        types.default_memory_max_facts,
        types.min_memory_max_facts,
        types.max_memory_max_facts,
        error.InvalidMemoryMaxFacts,
    );
}

fn parseToolMaxRounds(value: ?[]const u8) LoadError!usize {
    return parseBoundedInt(
        usize,
        value,
        types.default_tool_max_rounds,
        1,
        16,
        error.InvalidToolMaxRounds,
    );
}

fn parseToolOutputMaxBytes(value: ?[]const u8) LoadError!usize {
    return parseBoundedInt(
        usize,
        value,
        types.default_tool_output_max_bytes,
        256,
        1024 * 1024,
        error.InvalidToolOutputMaxBytes,
    );
}

fn parseToolTimeoutMs(value: ?[]const u8) LoadError!u64 {
    return parseBoundedInt(
        u64,
        value,
        types.default_shell_timeout_ms,
        1,
        600_000,
        error.InvalidToolTimeoutMs,
    );
}

fn parseOptionalBoundedInt(
    comptime T: type,
    value: ?[]const u8,
    min: T,
    max: T,
    invalid: LoadError,
) LoadError!?T {
    const raw = clean(value) orelse return null;
    return try parseBoundedIntRaw(T, raw, min, max, invalid);
}

fn parseBoundedInt(
    comptime T: type,
    value: ?[]const u8,
    default: T,
    min: T,
    max: T,
    invalid: LoadError,
) LoadError!T {
    const raw = clean(value) orelse return default;
    return parseBoundedIntRaw(T, raw, min, max, invalid);
}

fn parseBoundedIntRaw(
    comptime T: type,
    raw: []const u8,
    min: T,
    max: T,
    invalid: LoadError,
) LoadError!T {
    const parsed = std.fmt.parseInt(T, raw, 10) catch return invalid;
    if (parsed < min or parsed > max) return invalid;
    return parsed;
}

test "OS env source overrides dotenv source" {
    const cfg = try fromSources(
        .{ .provider = "openrouter", .api_key = "env-key", .model = "env-model" },
        .{ .provider = "openai", .api_key = "dot-key", .model = "dot-model" },
    );

    try std.testing.expectEqual(.openrouter, cfg.completion.provider);
    try std.testing.expectEqualStrings("env-key", cfg.completion.api_key);
    try std.testing.expectEqualStrings("env-model", cfg.completion.model);
}

test "missing required config is rejected" {
    try std.testing.expectError(error.MissingProvider, fromSources(.{}, .{}));
    try std.testing.expectError(error.MissingApiKey, fromSources(.{ .provider = "openai" }, .{}));
    try std.testing.expectError(error.MissingModel, fromSources(.{ .provider = "openai", .api_key = "key" }, .{}));
}

test "unknown provider is rejected" {
    try std.testing.expectError(
        error.UnknownProvider,
        fromSources(.{ .provider = "local", .api_key = "key", .model = "model" }, .{}),
    );
}

test "completion max_tokens is optional and validated" {
    const defaults = try fromSources(.{
        .provider = "openrouter",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expect(defaults.completion.max_tokens == null);

    const capped = try fromSources(.{
        .provider = "openrouter",
        .api_key = "key",
        .model = "model",
        .max_tokens = "64",
    }, .{});
    try std.testing.expectEqual(@as(u32, 64), capped.completion.max_tokens.?);

    try std.testing.expectError(error.InvalidMaxTokens, fromSources(.{
        .provider = "openrouter",
        .api_key = "key",
        .model = "model",
        .max_tokens = "0",
    }, .{}));
    try std.testing.expectError(error.InvalidMaxTokens, fromSources(.{
        .provider = "openrouter",
        .api_key = "key",
        .model = "model",
        .max_tokens = "nope",
    }, .{}));
}

test "compatible provider requires base URL" {
    try std.testing.expectError(
        error.MissingBaseUrl,
        fromSources(.{ .provider = "compatible", .api_key = "key", .model = "model" }, .{}),
    );

    const cfg = try fromSources(.{
        .provider = "compatible",
        .api_key = "key",
        .model = "model",
        .base_url = "https://example.test/v1",
    }, .{});
    try std.testing.expectEqual(.compatible, cfg.completion.provider);
    try std.testing.expectEqualStrings("https://example.test/v1", cfg.completion.base_url.?);
}

test "compatible provider rejects insecure remote base URL by default" {
    try std.testing.expectError(error.InsecureBaseUrl, fromSources(.{
        .provider = "compatible",
        .api_key = "key",
        .model = "model",
        .base_url = "http://example.test/v1",
    }, .{}));

    const local = try fromSources(.{
        .provider = "compatible",
        .api_key = "key",
        .model = "model",
        .base_url = "http://localhost:11434/v1",
        .allow_http_base_url = "on",
    }, .{});
    try std.testing.expect(local.completion.allow_insecure_base_url);
    try std.testing.expectEqualStrings("http://localhost:11434/v1", local.completion.base_url.?);
}

test "provider header config rejects ascii control bytes" {
    try std.testing.expectError(error.InvalidHeaderValue, fromSources(.{
        .provider = "openai",
        .api_key = "key\x1f",
        .model = "model",
    }, .{}));
    try std.testing.expectError(error.InvalidHeaderValue, fromSources(.{
        .provider = "openrouter",
        .api_key = "key",
        .model = "model",
        .http_referer = "https://example.test\x7f",
    }, .{}));
}

test "model config rejects non-text bytes" {
    try std.testing.expectError(error.InvalidModel, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "bad\xff",
    }, .{}));
    try std.testing.expectError(error.InvalidModel, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "bad\x00model",
    }, .{}));
    try std.testing.expectError(error.InvalidModel, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "bad\nmodel",
    }, .{}));
}

test "memory config defaults and overrides" {
    const defaults = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expect(defaults.memory.enabled);
    try std.testing.expect(defaults.memory.path == null);
    try std.testing.expectEqual(@as(usize, 20), defaults.memory.max_messages);
    try std.testing.expect(defaults.memory.facts_path == null);
    try std.testing.expectEqual(@as(usize, types.default_memory_max_facts), defaults.memory.max_facts);

    const cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory = "off",
        .memory_path = ".custom-memory.jsonl",
        .memory_max_messages = "8",
        .memory_facts_path = ".custom-facts.jsonl",
        .memory_max_facts = "12",
    }, .{});
    try std.testing.expect(!cfg.memory.enabled);
    try std.testing.expectEqualStrings(".custom-memory.jsonl", cfg.memory.path.?);
    try std.testing.expectEqual(@as(usize, 8), cfg.memory.max_messages);
    try std.testing.expectEqualStrings(".custom-facts.jsonl", cfg.memory.facts_path.?);
    try std.testing.expectEqual(@as(usize, 12), cfg.memory.max_facts);
}

test "state file config paths are local JSONL paths" {
    const cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_path = "state/memory.jsonl",
        .memory_facts_path = "state/facts.jsonl",
        .user_tools_path = "state/tools.jsonl",
        .schedule_path = "state/schedule.jsonl",
    }, .{});
    try std.testing.expectEqualStrings("state/memory.jsonl", cfg.memory.path.?);
    try std.testing.expectEqualStrings("state/facts.jsonl", cfg.memory.facts_path.?);
    try std.testing.expectEqualStrings("state/tools.jsonl", cfg.tools.user_tools_path.?);
    try std.testing.expectEqualStrings("state/schedule.jsonl", cfg.schedule.path.?);
}

test "tools config defaults and overrides" {
    const defaults = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expect(defaults.tools.enabled);
    try std.testing.expect(!defaults.tools.shell_enabled);
    try std.testing.expect(defaults.tools.file_read_enabled);
    try std.testing.expect(defaults.tools.file_write_enabled);
    try std.testing.expect(defaults.tools.schedule_enabled);
    try std.testing.expectEqual(@as(usize, types.default_tool_max_rounds), defaults.tools.max_rounds);
    try std.testing.expectEqual(@as(usize, types.default_tool_output_max_bytes), defaults.tools.output_max_bytes);
    try std.testing.expectEqual(@as(u64, types.default_shell_timeout_ms), defaults.tools.timeout_ms);

    const cfg = try fromSourcesWithFeatures(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tools = "on",
        .file_read = "on",
        .file_write = "on",
        .schedule_tools = "on",
        .shell = "on",
        .tool_max_rounds = "3",
        .tool_output_max_bytes = "4096",
        .tool_timeout_ms = "2500",
    }, .{}, .{ .shell_tool = true });
    try std.testing.expect(cfg.tools.enabled);
    try std.testing.expect(cfg.tools.shell_enabled);
    try std.testing.expect(cfg.tools.file_read_enabled);
    try std.testing.expect(cfg.tools.file_write_enabled);
    try std.testing.expect(cfg.tools.schedule_enabled);
    try std.testing.expectEqual(@as(usize, 3), cfg.tools.max_rounds);
    try std.testing.expectEqual(@as(usize, 4096), cfg.tools.output_max_bytes);
    try std.testing.expectEqual(@as(u64, 2500), cfg.tools.timeout_ms);
}

test "numeric config boundaries are inclusive where intended" {
    const cfg = try fromSourcesWithFeatures(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .max_tokens = "1",
        .memory_max_messages = "2",
        .memory_max_facts = "1024",
        .tool_max_rounds = "16",
        .tool_output_max_bytes = "1048576",
        .tool_timeout_ms = "600000",
        .telegram_poll_timeout = "0",
        .telegram_rate_limit_per_minute = "0",
        .daemon_interval_seconds = "86400",
        .heartbeat_interval_seconds = "604800",
        .timezone_offset_minutes = "-840",
    }, .{}, .{ .shell_tool = true });

    try std.testing.expectEqual(@as(u32, 1), cfg.completion.max_tokens.?);
    try std.testing.expectEqual(@as(usize, 2), cfg.memory.max_messages);
    try std.testing.expectEqual(@as(usize, 1024), cfg.memory.max_facts);
    try std.testing.expectEqual(@as(usize, 16), cfg.tools.max_rounds);
    try std.testing.expectEqual(@as(usize, 1024 * 1024), cfg.tools.output_max_bytes);
    try std.testing.expectEqual(@as(u64, 600_000), cfg.tools.timeout_ms);
    try std.testing.expectEqual(@as(u32, 0), cfg.telegram.poll_timeout_seconds);
    try std.testing.expectEqual(@as(u32, 0), cfg.telegram.rate_limit_per_minute);
    try std.testing.expectEqual(@as(u32, 86_400), cfg.schedule.daemon_interval_seconds);
    try std.testing.expectEqual(@as(u32, 7 * 86_400), cfg.schedule.heartbeat_interval_seconds);
    try std.testing.expectEqual(@as(i32, -14 * 60), cfg.timezone_offset_minutes);
}

test "boolean config accepts only on and off" {
    const truthy = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory = "on",
        .tools = "on",
        .file_read = "on",
        .file_write = "on",
        .schedule_tools = "on",
        .stream = "on",
    }, .{});
    try std.testing.expect(truthy.memory.enabled);
    try std.testing.expect(truthy.tools.enabled);
    try std.testing.expect(truthy.tools.file_read_enabled);
    try std.testing.expect(truthy.tools.file_write_enabled);
    try std.testing.expect(truthy.tools.schedule_enabled);
    try std.testing.expect(truthy.stream);

    const falsy = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory = "off",
        .tools = "off",
        .file_read = "off",
        .file_write = "off",
        .schedule_tools = "off",
        .stream = "off",
    }, .{});
    try std.testing.expect(!falsy.memory.enabled);
    try std.testing.expect(!falsy.tools.enabled);
    try std.testing.expect(!falsy.tools.file_read_enabled);
    try std.testing.expect(!falsy.tools.file_write_enabled);
    try std.testing.expect(!falsy.tools.schedule_enabled);
    try std.testing.expect(!falsy.stream);

    try std.testing.expectError(error.InvalidMemory, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory = "true",
    }, .{}));
    try std.testing.expectError(error.InvalidTools, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tools = "1",
    }, .{}));
    try std.testing.expectError(error.InvalidTools, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tools = "ON",
    }, .{}));
}

test "stream config defaults on and can be disabled" {
    const defaults = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expect(defaults.stream);

    const cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .stream = "off",
    }, .{});
    try std.testing.expect(!cfg.stream);
}

test "persona config defaults neutral and accepts supported modes" {
    const defaults = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expectEqual(types.PersonaKind.neutral, defaults.persona);

    const cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .persona = "technical",
    }, .{});
    try std.testing.expectEqual(types.PersonaKind.technical, cfg.persona);
}

test "telegram config is optional and supports chat allowlist" {
    const defaults = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expect(defaults.telegram.token == null);
    try std.testing.expect(defaults.telegram.chat_id == null);
    try std.testing.expectEqual(@as(u32, 20), defaults.telegram.poll_timeout_seconds);

    const cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "123:abc",
        .telegram_chat_id = "-10042",
        .telegram_poll_timeout = "30",
    }, .{});
    try std.testing.expectEqualStrings("123:abc", cfg.telegram.token.?);
    try std.testing.expectEqual(@as(i64, -10042), cfg.telegram.chat_id.?.id);
    try std.testing.expectEqual(@as(u32, 30), cfg.telegram.poll_timeout_seconds);

    const username_cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_chat_id = "@donprus",
    }, .{});
    try std.testing.expectEqualStrings("donprus", username_cfg.telegram.chat_id.?.username);
}

test "invalid tools config is rejected" {
    try std.testing.expectError(error.InvalidTools, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tools = "maybe",
    }, .{}));
    try std.testing.expectError(error.InvalidToolMaxRounds, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tool_max_rounds = "0",
    }, .{}));
    try std.testing.expectError(error.InvalidToolOutputMaxBytes, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tool_output_max_bytes = "32",
    }, .{}));
    try std.testing.expectError(error.InvalidFileWrite, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .file_write = "maybe",
    }, .{}));
    try std.testing.expectError(error.InvalidFileRead, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .file_read = "maybe",
    }, .{}));
    try std.testing.expectError(error.InvalidScheduleTools, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .schedule_tools = "maybe",
    }, .{}));
    try std.testing.expectError(error.InvalidShell, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .shell = "on",
    }, .{}));
    try std.testing.expectError(error.InvalidToolTimeoutMs, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tool_timeout_ms = "2500",
    }, .{}));

    try std.testing.expectError(error.InvalidShell, fromSourcesWithFeatures(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .shell = "maybe",
    }, .{}, .{ .shell_tool = true }));
    try std.testing.expectError(error.InvalidToolTimeoutMs, fromSourcesWithFeatures(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .tool_timeout_ms = "0",
    }, .{}, .{ .shell_tool = true }));
}

test "invalid stream config is rejected" {
    try std.testing.expectError(error.InvalidStream, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .stream = "maybe",
    }, .{}));
}

test "invalid persona config is rejected" {
    try std.testing.expectError(error.InvalidPersona, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .persona = "sarcastic",
    }, .{}));
    try std.testing.expectError(error.InvalidPersona, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .persona = "Technical",
    }, .{}));
}

test "invalid telegram config is rejected" {
    try std.testing.expectError(error.InvalidTelegramToken, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "token",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramToken, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "abc:secret",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramToken, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "123:",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramToken, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "123:secret:extra",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramToken, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "bad/token",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramToken, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_token = "bad\nkey",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramChatId, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_chat_id = "abc",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramChatId, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_chat_id = "0",
    }, .{}));
    try std.testing.expectError(error.InvalidTelegramPollTimeout, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .telegram_poll_timeout = "61",
    }, .{}));
}

test "schedule search and timezone config defaults and overrides" {
    const defaults = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
    }, .{});
    try std.testing.expectEqual(types.SearchProvider.auto, defaults.search.provider);
    try std.testing.expect(defaults.search.tavily_key == null);
    try std.testing.expect(defaults.search.brave_key == null);
    try std.testing.expect(defaults.search.exa_key == null);
    try std.testing.expect(defaults.search.firecrawl_key == null);
    try std.testing.expect(!defaults.search.duckduckgo_enabled);
    try std.testing.expect(defaults.schedule.path == null);
    try std.testing.expectEqual(@as(u32, 60), defaults.schedule.daemon_interval_seconds);
    try std.testing.expectEqual(@as(u32, 1800), defaults.schedule.heartbeat_interval_seconds);
    try std.testing.expectEqual(@as(i32, 0), defaults.timezone_offset_minutes);

    const cfg = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_provider = "exa",
        .search_tavily_key = "tvly",
        .search_brave_key = "brave",
        .search_exa_key = "exa",
        .search_firecrawl_key = "fc",
        .search_duckduckgo = "on",
        .schedule_path = ".custom-schedule.jsonl",
        .daemon_interval_seconds = "5",
        .heartbeat_interval_seconds = "30",
        .timezone_offset_minutes = "180",
    }, .{});
    try std.testing.expectEqual(types.SearchProvider.exa, cfg.search.provider);
    try std.testing.expectEqualStrings("tvly", cfg.search.tavily_key.?);
    try std.testing.expectEqualStrings("brave", cfg.search.brave_key.?);
    try std.testing.expectEqualStrings("exa", cfg.search.exa_key.?);
    try std.testing.expectEqualStrings("fc", cfg.search.firecrawl_key.?);
    try std.testing.expect(cfg.search.duckduckgo_enabled);
    try std.testing.expectEqualStrings(".custom-schedule.jsonl", cfg.schedule.path.?);
    try std.testing.expectEqual(@as(u32, 5), cfg.schedule.daemon_interval_seconds);
    try std.testing.expectEqual(@as(u32, 30), cfg.schedule.heartbeat_interval_seconds);
    try std.testing.expectEqual(@as(i32, 180), cfg.timezone_offset_minutes);

    const env_value_wins = try fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_tavily_key = "env-tvly",
    }, .{
        .search_tavily_key = "dotenv-tvly",
    });
    try std.testing.expectEqualStrings("env-tvly", env_value_wins.search.tavily_key.?);
}

test "invalid schedule and timezone config is rejected" {
    try std.testing.expectError(error.InvalidSearchProvider, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_provider = "google",
    }, .{}));
    try std.testing.expectError(error.InvalidSearchProvider, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_provider = "TAVILY",
    }, .{}));
    try std.testing.expectError(error.InvalidSearchDuckDuckGo, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_duckduckgo = "maybe",
    }, .{}));
    try std.testing.expectError(error.MissingSearchKey, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_provider = "brave",
    }, .{}));
    try std.testing.expectError(error.MissingSearchKey, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_provider = "exa",
        .search_brave_key = "brave",
    }, .{}));
    try std.testing.expectError(error.MissingSearchKey, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_provider = "brave",
        .search_brave_key = "   ",
    }, .{}));
    try std.testing.expectError(error.InvalidSearchKey, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_brave_key = "bad\nkey",
    }, .{}));
    try std.testing.expectError(error.InvalidSearchKey, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .search_brave_key = "bad\x1fkey",
    }, .{}));
    try std.testing.expectError(error.InvalidDaemonIntervalSeconds, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .daemon_interval_seconds = "0",
    }, .{}));
    try std.testing.expectError(error.InvalidHeartbeatIntervalSeconds, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .heartbeat_interval_seconds = "0",
    }, .{}));
    try std.testing.expectError(error.InvalidTimezoneOffsetMinutes, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .timezone_offset_minutes = "900",
    }, .{}));
}

test "invalid memory config is rejected" {
    try std.testing.expectError(error.InvalidMemory, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory = "maybe",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryMaxMessages, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_max_messages = "1",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryMaxFacts, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_max_facts = "0",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_path = "/tmp/memory.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_path = "../memory.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_path = "state//memory.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_path = "memory.txt",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_path = "bad\x00path.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidMemoryFactsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .memory_facts_path = ".ssh/facts.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "C:\\tools.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "C:tools.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "state\\tools.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "state/tool?.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "state./tools.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "state /tools.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "NUL.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "state/COM1.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidUserToolsPath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .user_tools_path = "state/CONIN$.jsonl",
    }, .{}));
    try std.testing.expectError(error.InvalidSchedulePath, fromSources(.{
        .provider = "openai",
        .api_key = "key",
        .model = "model",
        .schedule_path = "schedule.JSONL",
    }, .{}));
}

test "owned config is independent from source buffers" {
    const allocator = std.testing.allocator;
    const api_key = try allocator.dupe(u8, "dot-key");
    defer allocator.free(api_key);
    const model = try allocator.dupe(u8, "dot-model");
    defer allocator.free(model);
    const websocket_host = try allocator.dupe(u8, "127.0.0.1");
    defer allocator.free(websocket_host);
    const websocket_path = try allocator.dupe(u8, "/agent");
    defer allocator.free(websocket_path);

    var owned = try fromSourcesOwned(allocator, .{}, .{
        .provider = "openai",
        .api_key = api_key,
        .model = model,
        .websocket_host = websocket_host,
        .websocket_path = websocket_path,
    });
    defer owned.deinit(allocator);

    @memset(api_key, 'x');
    @memset(model, 'x');
    @memset(websocket_host, 'x');
    @memset(websocket_path, 'x');

    try std.testing.expectEqualStrings("dot-key", owned.value.completion.api_key);
    try std.testing.expectEqualStrings("dot-model", owned.value.completion.model);
    try std.testing.expectEqualStrings("127.0.0.1", owned.value.websocket.host);
    try std.testing.expectEqualStrings("/agent", owned.value.websocket.path);
}

test "owned config cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var owned = try fromSourcesOwnedWithFeatures(allocator, .{}, .{
                .provider = "openai",
                .api_key = "key",
                .model = "model",
                .max_tokens = "64",
                .base_url = "https://example.test/v1",
                .http_referer = "https://example.test",
                .app_title = "nllclw test",
                .persona = "technical",
                .memory = "on",
                .memory_path = ".memory.jsonl",
                .memory_max_messages = "8",
                .memory_facts_path = ".facts.jsonl",
                .memory_max_facts = "12",
                .tools = "on",
                .file_read = "on",
                .file_write = "on",
                .schedule_tools = "on",
                .user_tools_path = ".tools.jsonl",
                .shell = "on",
                .tool_max_rounds = "3",
                .tool_output_max_bytes = "4096",
                .tool_timeout_ms = "2500",
                .stream = "on",
                .telegram_token = "123:abc",
                .telegram_chat_id = "-10042",
                .telegram_poll_timeout = "30",
                .telegram_rate_limit_per_minute = "10",
                .websocket_host = "127.0.0.1",
                .websocket_port = "9001",
                .websocket_path = "/agent",
                .websocket_token = "ws-token",
                .websocket_allow_remote = "off",
                .websocket_rate_limit_per_minute = "30",
                .search_provider = "exa",
                .search_tavily_key = "tvly",
                .search_brave_key = "brave",
                .search_exa_key = "exa",
                .search_firecrawl_key = "fc",
                .search_duckduckgo = "on",
                .schedule_path = ".schedule.jsonl",
                .daemon_interval_seconds = "5",
                .heartbeat_interval_seconds = "30",
                .timezone_offset_minutes = "180",
            }, .{ .shell_tool = true });
            defer owned.deinit(allocator);
        }
    }.run, .{});
}
