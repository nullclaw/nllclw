const std = @import("std");
const app_paths = @import("./app_paths.zig");
const build_options = @import("build_options");
const channel_error = @import("./channels/errors.zig");
const config = @import("./config.zig");
const state_file = @import("./adapters/state_file.zig");
const telegram_identity = @import("./telegram/identity.zig");
const telegram_token = @import("./telegram/token.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const max_setup_line_bytes: usize = 4096;

const init_usage =
    \\usage:
    \\  nllclw init [--env] [--force]
    \\
    \\Creates user config with numbered setup menus. Defaults do not set max_tokens.
    \\
;

const uninstall_usage =
    \\usage:
    \\  nllclw uninstall [--force]
    \\
;

const ConfigFormat = enum {
    json,
    env,
};

const InitOptions = struct {
    format: ConfigFormat = .json,
    force: bool = false,
};

const InitTargets = struct {
    config_path: []u8,
    state_dir: []u8,
    shadowing_json_path: ?[]u8 = null,

    fn deinit(self: *InitTargets, allocator: Allocator) void {
        allocator.free(self.config_path);
        allocator.free(self.state_dir);
        if (self.shadowing_json_path) |path| allocator.free(path);
        self.* = undefined;
    }
};

const Settings = struct {
    provider: []u8,
    api_key: []u8,
    model: []u8,
    max_tokens: ?[]u8 = null,
    base_url: ?[]u8 = null,
    allow_http_base_url: bool = false,
    persona: ?[]u8 = null,
    tools: ?[]u8 = null,
    file_write: ?[]u8 = null,
    telegram_token: ?[]u8 = null,
    telegram_chat_id: ?[]u8 = null,
    websocket_host: ?[]u8 = null,
    websocket_port: ?[]u8 = null,
    websocket_path: ?[]u8 = null,
    websocket_token: ?[]u8 = null,
    websocket_allow_remote: bool = false,
    search_provider: ?[]u8 = null,
    search_tavily_key: ?[]u8 = null,
    search_brave_key: ?[]u8 = null,
    search_exa_key: ?[]u8 = null,
    search_firecrawl_key: ?[]u8 = null,

    fn deinit(self: *Settings, allocator: Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.api_key);
        allocator.free(self.model);
        freeOptional(allocator, self.max_tokens);
        if (self.base_url) |value| allocator.free(value);
        freeOptional(allocator, self.persona);
        freeOptional(allocator, self.tools);
        freeOptional(allocator, self.file_write);
        freeOptional(allocator, self.telegram_token);
        freeOptional(allocator, self.telegram_chat_id);
        freeOptional(allocator, self.websocket_host);
        freeOptional(allocator, self.websocket_port);
        freeOptional(allocator, self.websocket_path);
        freeOptional(allocator, self.websocket_token);
        freeOptional(allocator, self.search_provider);
        freeOptional(allocator, self.search_tavily_key);
        freeOptional(allocator, self.search_brave_key);
        freeOptional(allocator, self.search_exa_key);
        freeOptional(allocator, self.search_firecrawl_key);
        self.* = undefined;
    }
};

const MenuChoice = struct {
    value: []const u8,
    label: []const u8,
};

const ToolsChoice = struct {
    tools: ?[]u8 = null,
    file_write: ?[]u8 = null,

    fn deinit(self: ToolsChoice, allocator: Allocator) void {
        freeOptional(allocator, self.tools);
        freeOptional(allocator, self.file_write);
    }
};

const TelegramChoice = struct {
    token: ?[]u8 = null,
    chat_id: ?[]u8 = null,

    fn deinit(self: TelegramChoice, allocator: Allocator) void {
        freeOptional(allocator, self.token);
        freeOptional(allocator, self.chat_id);
    }
};

const WebSocketChoice = struct {
    host: ?[]u8 = null,
    port: ?[]u8 = null,
    path: ?[]u8 = null,
    token: ?[]u8 = null,
    allow_remote: bool = false,

    fn deinit(self: WebSocketChoice, allocator: Allocator) void {
        freeOptional(allocator, self.host);
        freeOptional(allocator, self.port);
        freeOptional(allocator, self.path);
        freeOptional(allocator, self.token);
    }
};

const SearchChoice = struct {
    provider: ?[]u8 = null,
    tavily_key: ?[]u8 = null,
    brave_key: ?[]u8 = null,
    exa_key: ?[]u8 = null,
    firecrawl_key: ?[]u8 = null,

    fn deinit(self: SearchChoice, allocator: Allocator) void {
        freeOptional(allocator, self.provider);
        freeOptional(allocator, self.tavily_key);
        freeOptional(allocator, self.brave_key);
        freeOptional(allocator, self.exa_key);
        freeOptional(allocator, self.firecrawl_key);
    }
};

pub fn isCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "init") or std.mem.eql(u8, arg, "uninstall");
}

pub fn run(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    if (std.mem.eql(u8, args[1], "init")) {
        return runInit(allocator, io, env_map, args, stdout, stderr);
    }
    if (std.mem.eql(u8, args[1], "uninstall")) {
        return runUninstall(allocator, io, env_map, args, stdout, stderr);
    }
    return 2;
}

fn runInit(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const options = parseInitArgs(args) orelse {
        try stderr.writeAll(init_usage);
        try stderr.flush();
        return 2;
    };
    if (args.len == 3 and std.mem.eql(u8, args[2], "--help")) {
        try stdout.writeAll(init_usage);
        try stdout.flush();
        return 0;
    }

    var targets = resolveInitTargets(allocator, env_map, options.format) catch |err| return failConfig(stderr, err);
    defer targets.deinit(allocator);

    if (envConfigShadowedByJson(io, targets)) |shadowed| {
        if (shadowed) {
            try stderr.writeAll("nllclw: config.json already exists and overrides .env; remove it or run nllclw uninstall first\n");
            try stderr.flush();
            return 2;
        }
    } else |err| return failSetupStorage(stderr, err);

    var stdin_buffer: [max_setup_line_bytes]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
    const target_exists = fileExists(io, targets.config_path) catch |err| return failSetupStorage(stderr, err);
    if (!options.force and target_exists) {
        if (!try confirm(&stdin_reader.interface, stdout, "config already exists; replace it? [y/N] ")) {
            try stdout.writeAll("init cancelled\n");
            try stdout.flush();
            return 1;
        }
    }

    var settings = try promptSettings(allocator, &stdin_reader.interface, stdout);
    defer settings.deinit(allocator);

    var validation = config.fromSourcesOwnedWithFeatures(
        allocator,
        sourceFromSettings(settings),
        .{},
        .{ .shell_tool = build_options.shell_tool },
    ) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.flush();
        return 2;
    };
    validation.deinit(allocator);

    const contents = switch (options.format) {
        .json => try buildJsonConfig(allocator, settings),
        .env => try buildEnvConfig(allocator, settings),
    };
    defer allocator.free(contents);

    writeConfigWithPreparedState(io, targets.state_dir, targets.config_path, contents) catch |err| return failSetupStorage(stderr, err);

    try stdout.print("created config: {s}\n", .{targets.config_path});
    try stdout.print("created state dir: {s}\n", .{targets.state_dir});
    try stdout.flush();
    return 0;
}

fn runUninstall(
    allocator: Allocator,
    io: Io,
    env_map: *const std.process.Environ.Map,
    args: []const [:0]const u8,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) !u8 {
    const force = parseUninstallArgs(args) orelse {
        try stderr.writeAll(uninstall_usage);
        try stderr.flush();
        return 2;
    };
    if (args.len == 3 and std.mem.eql(u8, args[2], "--help")) {
        try stdout.writeAll(uninstall_usage);
        try stdout.flush();
        return 0;
    }

    const config_dir = app_paths.configDir(allocator, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.flush();
        return 2;
    };
    defer allocator.free(config_dir);
    const state_dir = app_paths.stateDir(allocator, env_map) catch |err| {
        try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
        try stderr.flush();
        return 2;
    };
    defer allocator.free(state_dir);

    if (!force) {
        try stdout.print("delete nllclw config dir: {s}\n", .{config_dir});
        try stdout.print("delete nllclw state dir: {s}\n", .{state_dir});
        var stdin_buffer: [max_setup_line_bytes]u8 = undefined;
        var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
        if (!try confirm(&stdin_reader.interface, stdout, "continue? [y/N] ")) {
            try stdout.writeAll("uninstall cancelled\n");
            try stdout.flush();
            return 1;
        }
    }

    try deleteTreeIfPresent(io, state_dir);
    if (!std.mem.eql(u8, config_dir, state_dir)) try deleteTreeIfPresent(io, config_dir);
    try stdout.writeAll("nllclw user files removed\n");
    try stdout.flush();
    return 0;
}

fn parseInitArgs(args: []const [:0]const u8) ?InitOptions {
    var options: InitOptions = .{};
    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            return if (args.len == 3) options else null;
        } else if (std.mem.eql(u8, arg, "--env")) {
            options.format = .env;
        } else if (std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else {
            return null;
        }
    }
    return options;
}

fn parseUninstallArgs(args: []const [:0]const u8) ?bool {
    var force = false;
    for (args[2..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            return if (args.len == 3) false else null;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else {
            return null;
        }
    }
    return force;
}

fn promptSettings(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !Settings {
    try stdout.writeAll(
        \\nllclw setup
        \\This writes user config outside the repository.
        \\Press Enter on a numbered menu to accept its default.
        \\
    );

    const provider = try promptProvider(allocator, reader, stdout);
    errdefer allocator.free(provider);
    const api_key = try promptRequired(allocator, reader, stdout, "API key: ");
    errdefer allocator.free(api_key);
    const model = try promptRequired(allocator, reader, stdout, "Model name: ");
    errdefer allocator.free(model);
    const max_tokens = try promptMaxTokens(allocator, reader, stdout);
    errdefer freeOptional(allocator, max_tokens);

    var base_url: ?[]u8 = null;
    errdefer if (base_url) |value| allocator.free(value);
    var allow_http_base_url = false;
    if (std.mem.eql(u8, provider, "compatible")) {
        base_url = try promptRequired(allocator, reader, stdout, "Compatible base URL: ");
        allow_http_base_url = try promptYesNo(reader, stdout, "Allow HTTP loopback base URL?", false);
    }

    const persona_choice = try promptPersona(allocator, reader, stdout);
    errdefer freeOptional(allocator, persona_choice);

    const tools_choice = try promptToolsProfile(allocator, reader, stdout);
    errdefer tools_choice.deinit(allocator);

    const telegram_choice = try promptTelegram(allocator, reader, stdout);
    errdefer telegram_choice.deinit(allocator);

    const websocket_choice = try promptWebSocket(allocator, reader, stdout);
    errdefer websocket_choice.deinit(allocator);

    const search_choice = try promptSearch(allocator, reader, stdout);
    errdefer search_choice.deinit(allocator);

    return .{
        .provider = provider,
        .api_key = api_key,
        .model = model,
        .max_tokens = max_tokens,
        .base_url = base_url,
        .allow_http_base_url = allow_http_base_url,
        .persona = persona_choice,
        .tools = tools_choice.tools,
        .file_write = tools_choice.file_write,
        .telegram_token = telegram_choice.token,
        .telegram_chat_id = telegram_choice.chat_id,
        .websocket_host = websocket_choice.host,
        .websocket_port = websocket_choice.port,
        .websocket_path = websocket_choice.path,
        .websocket_token = websocket_choice.token,
        .websocket_allow_remote = websocket_choice.allow_remote,
        .search_provider = search_choice.provider,
        .search_tavily_key = search_choice.tavily_key,
        .search_brave_key = search_choice.brave_key,
        .search_exa_key = search_choice.exa_key,
        .search_firecrawl_key = search_choice.firecrawl_key,
    };
}

fn promptProvider(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) ![]u8 {
    const choices = [_]MenuChoice{
        .{ .value = "openrouter", .label = "OpenRouter" },
        .{ .value = "openai", .label = "OpenAI" },
        .{ .value = "compatible", .label = "OpenAI-compatible endpoint" },
    };
    const index = try promptChoice(reader, stdout, "Provider", &choices, 0);
    return allocator.dupe(u8, choices[index].value);
}

fn promptMaxTokens(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !?[]u8 {
    const choices = [_]MenuChoice{
        .{ .value = "unset", .label = "Do not set max_tokens; let the provider choose" },
        .{ .value = "set", .label = "Set an explicit max_tokens cap" },
    };
    const index = try promptChoice(reader, stdout, "Output token cap", &choices, 0);
    if (index == 0) return null;
    return try promptPositiveU32(allocator, reader, stdout, "max_tokens: ");
}

fn promptPersona(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !?[]u8 {
    const choices = [_]MenuChoice{
        .{ .value = "neutral", .label = "Neutral (default)" },
        .{ .value = "technical", .label = "Technical" },
        .{ .value = "friendly", .label = "Friendly" },
        .{ .value = "witty", .label = "Witty" },
    };
    const index = try promptChoice(reader, stdout, "Assistant style", &choices, 0);
    if (index == 0) return null;
    return try allocator.dupe(u8, choices[index].value);
}

fn promptToolsProfile(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !ToolsChoice {
    const choices = [_]MenuChoice{
        .{ .value = "default", .label = "Default local tools: memory, file read/write, schedules, user tools" },
        .{ .value = "read-only", .label = "Read-only files: keep tools on but disable file writes" },
        .{ .value = "chat-only", .label = "Chat only: disable model-called tools" },
    };
    const index = try promptChoice(reader, stdout, "Local capability profile", &choices, 0);
    return switch (index) {
        0 => .{},
        1 => .{ .file_write = try allocator.dupe(u8, "off") },
        2 => .{ .tools = try allocator.dupe(u8, "off") },
        else => unreachable,
    };
}

fn promptTelegram(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !TelegramChoice {
    if (!try promptYesNo(reader, stdout, "Configure Telegram polling?", false)) return .{};
    const token = try promptTelegramToken(allocator, reader, stdout);
    errdefer allocator.free(token);
    const chat_id = try promptTelegramAllowlist(allocator, reader, stdout);
    errdefer allocator.free(chat_id);
    return .{ .token = token, .chat_id = chat_id };
}

fn promptWebSocket(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !WebSocketChoice {
    if (!try promptYesNo(reader, stdout, "Configure local WebSocket channel?", false)) return .{};

    var result: WebSocketChoice = .{
        .token = try promptRequired(allocator, reader, stdout, "WebSocket token (8-256 URL-safe chars): "),
    };
    errdefer result.deinit(allocator);

    const choices = [_]MenuChoice{
        .{ .value = "default", .label = "Use local defaults: 127.0.0.1:8765/ws" },
        .{ .value = "custom", .label = "Customize host, port, or path" },
    };
    const index = try promptChoice(reader, stdout, "WebSocket bind", &choices, 0);
    if (index == 1) {
        result.host = try promptWithDefault(allocator, reader, stdout, "WebSocket host: ", "127.0.0.1");
        result.port = try promptPort(allocator, reader, stdout, "WebSocket port: ", "8765");
        result.path = try promptWebSocketPath(allocator, reader, stdout, "WebSocket path: ", "/ws");
        result.allow_remote = try promptYesNo(reader, stdout, "Allow non-loopback WebSocket binds?", false);
    }
    return result;
}

fn promptSearch(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) !SearchChoice {
    if (!try promptYesNo(reader, stdout, "Configure web_search?", false)) return .{};

    const choices = [_]MenuChoice{
        .{ .value = "duckduckgo", .label = "DuckDuckGo Instant Answer (no key)" },
        .{ .value = "tavily", .label = "Tavily Search API key" },
        .{ .value = "brave", .label = "Brave Search API key" },
        .{ .value = "exa", .label = "Exa API key" },
        .{ .value = "firecrawl", .label = "Firecrawl API key" },
    };
    const index = try promptChoice(reader, stdout, "Search provider", &choices, 0);
    const provider = try allocator.dupe(u8, choices[index].value);
    errdefer allocator.free(provider);

    var result: SearchChoice = .{ .provider = provider };
    errdefer result.deinit(allocator);
    switch (index) {
        0 => {},
        1 => result.tavily_key = try promptRequired(allocator, reader, stdout, "Tavily API key: "),
        2 => result.brave_key = try promptRequired(allocator, reader, stdout, "Brave Search API key: "),
        3 => result.exa_key = try promptRequired(allocator, reader, stdout, "Exa API key: "),
        4 => result.firecrawl_key = try promptRequired(allocator, reader, stdout, "Firecrawl API key: "),
        else => unreachable,
    }
    return result;
}

fn promptRequired(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer, prompt: []const u8) ![]u8 {
    while (true) {
        const value = try promptWithDefault(allocator, reader, stdout, prompt, null);
        if (value.len != 0) return value;
        allocator.free(value);
        try stdout.writeAll("value is required\n");
        try stdout.flush();
    }
}

fn promptPositiveU32(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer, prompt: []const u8) ![]u8 {
    while (true) {
        const value = try promptRequired(allocator, reader, stdout, prompt);
        const parsed = std.fmt.parseInt(u32, value, 10) catch {
            allocator.free(value);
            try stdout.writeAll("enter a positive integer\n");
            try stdout.flush();
            continue;
        };
        if (parsed != 0) return value;
        allocator.free(value);
        try stdout.writeAll("enter a positive integer\n");
        try stdout.flush();
    }
}

fn promptTelegramAllowlist(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) ![]u8 {
    while (true) {
        const value = try promptRequired(allocator, reader, stdout, "Telegram allowlist chat (id or @username): ");
        if (telegram_identity.parseAllowlist(value) != null) return value;
        allocator.free(value);
        try stdout.writeAll("enter a non-zero chat id or a Telegram username like @donprus\n");
        try stdout.flush();
    }
}

fn promptPort(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer, prompt: []const u8, default: []const u8) ![]u8 {
    while (true) {
        const value = try promptWithDefault(allocator, reader, stdout, prompt, default);
        const parsed = std.fmt.parseInt(u16, value, 10) catch {
            allocator.free(value);
            try stdout.writeAll("enter a TCP port from 1 to 65535\n");
            try stdout.flush();
            continue;
        };
        if (parsed != 0) return value;
        allocator.free(value);
        try stdout.writeAll("enter a TCP port from 1 to 65535\n");
        try stdout.flush();
    }
}

fn promptWebSocketPath(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer, prompt: []const u8, default: []const u8) ![]u8 {
    while (true) {
        const value = try promptWithDefault(allocator, reader, stdout, prompt, default);
        if (value.len != 0 and value[0] == '/' and std.mem.indexOfAny(u8, value, " \t\r\n?#") == null) return value;
        allocator.free(value);
        try stdout.writeAll("path must start with / and cannot contain spaces, ? or #\n");
        try stdout.flush();
    }
}

fn promptTelegramToken(allocator: Allocator, reader: *Io.Reader, stdout: *Io.Writer) ![]u8 {
    while (true) {
        const value = try promptRequired(allocator, reader, stdout, "Telegram bot token: ");
        if (telegram_token.isValid(value)) return value;
        allocator.free(value);
        try stdout.writeAll("telegram token must look like <bot-id>:<secret>\n");
        try stdout.flush();
    }
}

fn promptWithDefault(
    allocator: Allocator,
    reader: *Io.Reader,
    stdout: *Io.Writer,
    prompt: []const u8,
    default: ?[]const u8,
) ![]u8 {
    try stdout.writeAll(prompt);
    try stdout.flush();
    const line = try readLine(reader);
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    if (trimmed.len == 0) return allocator.dupe(u8, default orelse "");
    return allocator.dupe(u8, trimmed);
}

fn promptYesNo(reader: *Io.Reader, stdout: *Io.Writer, title: []const u8, default: bool) !bool {
    const choices = [_]MenuChoice{
        .{ .value = "no", .label = "No" },
        .{ .value = "yes", .label = "Yes" },
    };
    const default_index: usize = if (default) 1 else 0;
    return (try promptChoice(reader, stdout, title, &choices, default_index)) == 1;
}

fn promptChoice(
    reader: *Io.Reader,
    stdout: *Io.Writer,
    title: []const u8,
    choices: []const MenuChoice,
    default_index: usize,
) !usize {
    std.debug.assert(choices.len > 0);
    std.debug.assert(default_index < choices.len);

    while (true) {
        try stdout.print("\n{s}\n", .{title});
        for (choices, 0..) |choice, index| {
            try stdout.print("  {d}) {s}\n", .{ index + 1, choice.label });
        }
        try stdout.print("Choose [{d}]: ", .{default_index + 1});
        try stdout.flush();
        const line = try readLine(reader);
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) return default_index;
        if (std.fmt.parseInt(usize, trimmed, 10)) |choice_number| {
            if (choice_number >= 1 and choice_number <= choices.len) return choice_number - 1;
        } else |_| {}
        for (choices, 0..) |choice, index| {
            if (std.mem.eql(u8, trimmed, choice.value)) return index;
        }
        try stdout.print("choose a number from 1 to {d}\n", .{choices.len});
        try stdout.flush();
    }
}

fn confirm(reader: *Io.Reader, stdout: *Io.Writer, prompt: []const u8) !bool {
    try stdout.writeAll(prompt);
    try stdout.flush();
    const line = try readLine(reader);
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    return std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "yes");
}

fn readLine(reader: *Io.Reader) ![]const u8 {
    return (reader.takeDelimiter('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.StreamTooLong,
        error.ReadFailed => return error.ReadFailed,
    }) orelse return error.EndOfStream;
}

fn freeOptional(allocator: Allocator, value: ?[]u8) void {
    if (value) |owned| allocator.free(owned);
}

fn sourceFromSettings(settings: Settings) config.Source {
    return .{
        .provider = settings.provider,
        .api_key = settings.api_key,
        .model = settings.model,
        .max_tokens = settings.max_tokens,
        .base_url = settings.base_url,
        .allow_http_base_url = if (settings.allow_http_base_url) "on" else null,
        .persona = settings.persona,
        .tools = settings.tools,
        .file_write = settings.file_write,
        .telegram_token = settings.telegram_token,
        .telegram_chat_id = settings.telegram_chat_id,
        .websocket_host = settings.websocket_host,
        .websocket_port = settings.websocket_port,
        .websocket_path = settings.websocket_path,
        .websocket_token = settings.websocket_token,
        .websocket_allow_remote = if (settings.websocket_allow_remote) "on" else null,
        .search_provider = settings.search_provider,
        .search_tavily_key = settings.search_tavily_key,
        .search_brave_key = settings.search_brave_key,
        .search_exa_key = settings.search_exa_key,
        .search_firecrawl_key = settings.search_firecrawl_key,
    };
}

fn buildJsonConfig(allocator: Allocator, settings: Settings) ![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    var json: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
    try json.beginObject();
    try json.objectField("provider");
    try json.write(settings.provider);
    try json.objectField("api_key");
    try json.write(settings.api_key);
    try json.objectField("model");
    try json.write(settings.model);
    if (settings.max_tokens) |value| {
        try json.objectField("max_tokens");
        try json.write(try std.fmt.parseInt(u32, value, 10));
    }
    if (settings.base_url) |value| {
        try json.objectField("base_url");
        try json.write(value);
    }
    if (settings.allow_http_base_url) {
        try json.objectField("allow_http_base_url");
        try json.write(true);
    }
    try writeJsonStringField(&json, "persona", settings.persona);
    try writeJsonStringField(&json, "tools", settings.tools);
    try writeJsonStringField(&json, "file_write", settings.file_write);
    try writeJsonStringField(&json, "telegram_token", settings.telegram_token);
    if (settings.telegram_chat_id) |value| {
        try json.objectField("telegram_chat_id");
        if (std.fmt.parseInt(i64, value, 10)) |id| {
            try json.write(id);
        } else |_| {
            try json.write(value);
        }
    }
    try writeJsonStringField(&json, "websocket_host", settings.websocket_host);
    if (settings.websocket_port) |value| {
        try json.objectField("websocket_port");
        try json.write(try std.fmt.parseInt(u16, value, 10));
    }
    try writeJsonStringField(&json, "websocket_path", settings.websocket_path);
    try writeJsonStringField(&json, "websocket_token", settings.websocket_token);
    if (settings.websocket_allow_remote) {
        try json.objectField("websocket_allow_remote");
        try json.write(true);
    }
    try writeJsonStringField(&json, "search_provider", settings.search_provider);
    try writeJsonStringField(&json, "search_tavily_key", settings.search_tavily_key);
    try writeJsonStringField(&json, "search_brave_key", settings.search_brave_key);
    try writeJsonStringField(&json, "search_exa_key", settings.search_exa_key);
    try writeJsonStringField(&json, "search_firecrawl_key", settings.search_firecrawl_key);
    try json.endObject();
    try out.writer.writeByte('\n');
    return out.toOwnedSlice();
}

fn writeJsonStringField(json: *std.json.Stringify, field: []const u8, value: ?[]const u8) !void {
    const raw = value orelse return;
    try json.objectField(field);
    try json.write(raw);
}

fn buildEnvConfig(allocator: Allocator, settings: Settings) ![]u8 {
    var out = Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.print("NLLCLW_PROVIDER={s}\n", .{settings.provider});
    try out.writer.print("NLLCLW_API_KEY={s}\n", .{settings.api_key});
    try out.writer.print("NLLCLW_MODEL={s}\n", .{settings.model});
    if (settings.max_tokens) |value| try out.writer.print("NLLCLW_MAX_TOKENS={s}\n", .{value});
    if (settings.base_url) |value| try out.writer.print("NLLCLW_BASE_URL={s}\n", .{value});
    if (settings.allow_http_base_url) try out.writer.writeAll("NLLCLW_ALLOW_HTTP_BASE_URL=on\n");
    try writeEnvField(&out.writer, "NLLCLW_PERSONA", settings.persona);
    try writeEnvField(&out.writer, "NLLCLW_TOOLS", settings.tools);
    try writeEnvField(&out.writer, "NLLCLW_FILE_WRITE", settings.file_write);
    try writeEnvField(&out.writer, "NLLCLW_TELEGRAM_TOKEN", settings.telegram_token);
    try writeEnvField(&out.writer, "NLLCLW_TELEGRAM_CHAT_ID", settings.telegram_chat_id);
    try writeEnvField(&out.writer, "NLLCLW_WS_HOST", settings.websocket_host);
    try writeEnvField(&out.writer, "NLLCLW_WS_PORT", settings.websocket_port);
    try writeEnvField(&out.writer, "NLLCLW_WS_PATH", settings.websocket_path);
    try writeEnvField(&out.writer, "NLLCLW_WS_TOKEN", settings.websocket_token);
    if (settings.websocket_allow_remote) try out.writer.writeAll("NLLCLW_WS_ALLOW_REMOTE=on\n");
    try writeEnvField(&out.writer, "NLLCLW_SEARCH_PROVIDER", settings.search_provider);
    try writeEnvField(&out.writer, "NLLCLW_SEARCH_TAVILY_KEY", settings.search_tavily_key);
    try writeEnvField(&out.writer, "NLLCLW_SEARCH_BRAVE_KEY", settings.search_brave_key);
    try writeEnvField(&out.writer, "NLLCLW_SEARCH_EXA_KEY", settings.search_exa_key);
    try writeEnvField(&out.writer, "NLLCLW_SEARCH_FIRECRAWL_KEY", settings.search_firecrawl_key);
    return out.toOwnedSlice();
}

fn writeEnvField(writer: *Io.Writer, key: []const u8, value: ?[]const u8) !void {
    const raw = value orelse return;
    try writer.print("{s}={s}\n", .{ key, raw });
}

fn resolveInitTargets(
    allocator: Allocator,
    env_map: *const std.process.Environ.Map,
    format: ConfigFormat,
) app_paths.Error!InitTargets {
    var targets: InitTargets = .{
        .config_path = switch (format) {
            .json => try app_paths.configJsonPath(allocator, env_map),
            .env => try app_paths.dotenvPath(allocator, env_map),
        },
        .state_dir = undefined,
    };
    errdefer allocator.free(targets.config_path);

    targets.state_dir = try app_paths.stateDir(allocator, env_map);
    errdefer allocator.free(targets.state_dir);

    if (format == .env) {
        targets.shadowing_json_path = try app_paths.configJsonPath(allocator, env_map);
    }
    return targets;
}

fn envConfigShadowedByJson(io: Io, targets: InitTargets) !bool {
    const path = targets.shadowing_json_path orelse return false;
    return fileExists(io, path);
}

fn writeConfigWithPreparedState(io: Io, state_dir: []const u8, config_path: []const u8, contents: []const u8) !void {
    const state_dir_existed = try dirExists(io, state_dir);
    try ensureDir(io, state_dir);
    errdefer if (!state_dir_existed) deleteTreeIfPresent(io, state_dir) catch {};
    try state_file.writeAtomic(io, config_path, contents);
}

fn fileExists(io: Io, path: []const u8) !bool {
    var file = Io.Dir.cwd().openFile(io, path, .{
        .allow_directory = false,
        .follow_symlinks = false,
    }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    file.close(io);
    return true;
}

fn dirExists(io: Io, path: []const u8) !bool {
    var dir = openDirPath(io, path) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    dir.close(io);
    return true;
}

fn ensureDir(io: Io, path: []const u8) !void {
    Io.Dir.cwd().createDirPath(io, path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dir = try openDirPath(io, path);
    dir.close(io);
}

fn openDirPath(io: Io, path: []const u8) !Io.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return Io.Dir.openDirAbsolute(io, path, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        });
    }
    return Io.Dir.cwd().openDir(io, path, .{
        .access_sub_paths = true,
        .follow_symlinks = false,
    });
}

fn deleteTreeIfPresent(io: Io, path: []const u8) !void {
    try Io.Dir.cwd().deleteTree(io, path);
}

fn failConfig(stderr: *Io.Writer, err: anyerror) !u8 {
    try stderr.print("nllclw: config error: {s}\n", .{channel_error.configErrorMessage(err)});
    try stderr.flush();
    return 2;
}

fn failSetupStorage(stderr: *Io.Writer, err: anyerror) !u8 {
    try stderr.print("nllclw: setup error: {s} ({s})\n", .{ setupStorageErrorMessage(err), @errorName(err) });
    try stderr.flush();
    return 1;
}

fn setupStorageErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.NotDir => "config/state path parent is not a directory",
        error.AccessDenied, error.PermissionDenied => "permission denied while creating config/state files",
        else => "failed to create config/state files",
    };
}

test "setup arg parsing is explicit" {
    const init_json: []const [:0]const u8 = &.{ "nllclw", "init" };
    try std.testing.expectEqual(ConfigFormat.json, parseInitArgs(init_json).?.format);

    const init_env_force: []const [:0]const u8 = &.{ "nllclw", "init", "--env", "--force" };
    const parsed = parseInitArgs(init_env_force).?;
    try std.testing.expectEqual(ConfigFormat.env, parsed.format);
    try std.testing.expect(parsed.force);

    const bad_init: []const [:0]const u8 = &.{ "nllclw", "init", "--toml" };
    try std.testing.expect(parseInitArgs(bad_init) == null);

    const uninstall_force: []const [:0]const u8 = &.{ "nllclw", "uninstall", "--force" };
    try std.testing.expect(parseUninstallArgs(uninstall_force).?);
}

test "setup config writers produce validated file formats" {
    var settings: Settings = .{
        .provider = try std.testing.allocator.dupe(u8, "compatible"),
        .api_key = try std.testing.allocator.dupe(u8, "key"),
        .model = try std.testing.allocator.dupe(u8, "model"),
        .base_url = try std.testing.allocator.dupe(u8, "http://127.0.0.1:11434/v1"),
        .allow_http_base_url = true,
        .telegram_chat_id = try std.testing.allocator.dupe(u8, "@donprus"),
    };
    defer settings.deinit(std.testing.allocator);

    const json_bytes = try buildJsonConfig(std.testing.allocator, settings);
    defer std.testing.allocator.free(json_bytes);
    var parsed_json = try @import("./config/json.zig").parseWithFeatures(std.testing.allocator, json_bytes, .{});
    defer parsed_json.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("compatible", parsed_json.source.provider.?);
    try std.testing.expectEqualStrings("on", parsed_json.source.allow_http_base_url.?);
    try std.testing.expectEqualStrings("@donprus", parsed_json.source.telegram_chat_id.?);
    try std.testing.expect(parsed_json.source.max_tokens == null);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "max_tokens") == null);

    const env_bytes = try buildEnvConfig(std.testing.allocator, settings);
    defer std.testing.allocator.free(env_bytes);
    const parsed_env = try @import("./dotenv.zig").parse(env_bytes);
    try std.testing.expectEqualStrings("compatible", parsed_env.provider.?);
    try std.testing.expectEqualStrings("on", parsed_env.allow_http_base_url.?);
    try std.testing.expectEqualStrings("@donprus", parsed_env.telegram_chat_id.?);
    try std.testing.expect(parsed_env.max_tokens == null);
    try std.testing.expect(std.mem.indexOf(u8, env_bytes, "NLLCLW_MAX_TOKENS") == null);
}

test "setup prompt defaults do not set hidden optional config" {
    var reader: Io.Reader = .fixed(
        "\n" ++
            "key\n" ++
            "model\n" ++
            "\n" ++
            "\n" ++
            "\n" ++
            "\n" ++
            "\n" ++
            "\n",
    );
    var stdout = Io.Writer.Allocating.init(std.testing.allocator);
    defer stdout.deinit();

    var settings = try promptSettings(std.testing.allocator, &reader, &stdout.writer);
    defer settings.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("openrouter", settings.provider);
    try std.testing.expect(settings.max_tokens == null);
    try std.testing.expect(settings.persona == null);
    try std.testing.expect(settings.tools == null);
    try std.testing.expect(settings.file_write == null);
    try std.testing.expect(settings.telegram_token == null);
    try std.testing.expect(settings.websocket_token == null);
    try std.testing.expect(settings.search_provider == null);

    const json_bytes = try buildJsonConfig(std.testing.allocator, settings);
    defer std.testing.allocator.free(json_bytes);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "max_tokens") == null);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "telegram") == null);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "websocket") == null);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "search") == null);

    var validation = try config.fromSourcesOwnedWithFeatures(
        std.testing.allocator,
        sourceFromSettings(settings),
        .{},
        .{ .shell_tool = build_options.shell_tool },
    );
    defer validation.deinit(std.testing.allocator);
    try std.testing.expect(validation.value.completion.max_tokens == null);
}

test "setup prompt numbered menus configure selected optional integrations" {
    var reader: Io.Reader = .fixed(
        "3\n" ++
            "key\n" ++
            "model\n" ++
            "2\n" ++
            "1024\n" ++
            "http://127.0.0.1:11434/v1\n" ++
            "2\n" ++
            "2\n" ++
            "2\n" ++
            "2\n" ++
            "123:abc_DEF-456\n" ++
            "-42\n" ++
            "2\n" ++
            "ws-token\n" ++
            "2\n" ++
            "0.0.0.0\n" ++
            "9001\n" ++
            "/agent\n" ++
            "2\n" ++
            "2\n" ++
            "2\n" ++
            "tvly-key\n",
    );
    var stdout = Io.Writer.Allocating.init(std.testing.allocator);
    defer stdout.deinit();

    var settings = try promptSettings(std.testing.allocator, &reader, &stdout.writer);
    defer settings.deinit(std.testing.allocator);

    var validation = try config.fromSourcesOwnedWithFeatures(
        std.testing.allocator,
        sourceFromSettings(settings),
        .{},
        .{ .shell_tool = build_options.shell_tool },
    );
    defer validation.deinit(std.testing.allocator);

    try std.testing.expectEqual(.compatible, validation.value.completion.provider);
    try std.testing.expectEqual(@as(u32, 1024), validation.value.completion.max_tokens.?);
    try std.testing.expect(validation.value.completion.allow_insecure_base_url);
    try std.testing.expectEqual(.technical, validation.value.persona);
    try std.testing.expect(validation.value.tools.enabled);
    try std.testing.expect(!validation.value.tools.file_write_enabled);
    try std.testing.expectEqualStrings("123:abc_DEF-456", validation.value.telegram.token.?);
    try std.testing.expectEqual(@as(i64, -42), validation.value.telegram.chat_id.?.id);
    try std.testing.expectEqualStrings("0.0.0.0", validation.value.websocket.host);
    try std.testing.expectEqual(@as(u16, 9001), validation.value.websocket.port);
    try std.testing.expectEqualStrings("/agent", validation.value.websocket.path);
    try std.testing.expectEqualStrings("ws-token", validation.value.websocket.token.?);
    try std.testing.expect(validation.value.websocket.allow_remote);
    try std.testing.expectEqual(.tavily, validation.value.search.provider);
    try std.testing.expectEqualStrings("tvly-key", validation.value.search.tavily_key.?);

    const env_bytes = try buildEnvConfig(std.testing.allocator, settings);
    defer std.testing.allocator.free(env_bytes);
    try std.testing.expect(std.mem.indexOf(u8, env_bytes, "NLLCLW_MAX_TOKENS=1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, env_bytes, "NLLCLW_TELEGRAM_TOKEN=123:abc_DEF-456") != null);
    try std.testing.expect(std.mem.indexOf(u8, env_bytes, "NLLCLW_WS_ALLOW_REMOTE=on") != null);
    try std.testing.expect(std.mem.indexOf(u8, env_bytes, "NLLCLW_SEARCH_TAVILY_KEY=tvly-key") != null);
}

test "setup env init refuses shadowing config json" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "config", .default_dir);
    try tmp.dir.createDir(io, "config/nllclw", .default_dir);
    try tmp.dir.writeFile(io, .{
        .sub_path = "config/nllclw/config.json",
        .data = "{\"provider\":\"openai\",\"api_key\":\"key\",\"model\":\"model\"}\n",
    });

    const config_root = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/config", .{tmp.sub_path});
    defer std.testing.allocator.free(config_root);
    const cwd = try std.process.currentPathAlloc(io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    const absolute_config_root = try std.fs.path.join(std.testing.allocator, &.{ cwd, config_root });
    defer std.testing.allocator.free(absolute_config_root);

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_CONFIG_HOME", absolute_config_root);
    try map.put("XDG_STATE_HOME", "/tmp/nllclw-test-state");

    const args: []const [:0]const u8 = &.{ "nllclw", "init", "--env", "--force" };
    var stdout = Io.Writer.Allocating.init(std.testing.allocator);
    defer stdout.deinit();
    var stderr = Io.Writer.Allocating.init(std.testing.allocator);
    defer stderr.deinit();

    const code = try run(std.testing.allocator, io, &map, args, &stdout.writer, &stderr.writer);
    try std.testing.expectEqual(@as(u8, 2), code);
    try std.testing.expect(std.mem.indexOf(u8, stderr.written(), "config.json already exists") != null);
}

test "uninstall is idempotent when app dirs are nested" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(io, "nllclw", .default_dir);
    try tmp.dir.createDir(io, "nllclw/nllclw", .default_dir);
    try tmp.dir.writeFile(io, .{
        .sub_path = "nllclw/memory.jsonl",
        .data = "",
    });
    try tmp.dir.writeFile(io, .{
        .sub_path = "nllclw/nllclw/config.json",
        .data = "{\"provider\":\"openai\",\"api_key\":\"key\",\"model\":\"model\"}\n",
    });

    const cwd = try std.process.currentPathAlloc(io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    const relative_state_root = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(relative_state_root);
    const state_root = try std.fs.path.join(std.testing.allocator, &.{ cwd, relative_state_root });
    defer std.testing.allocator.free(state_root);
    const config_root = try std.fs.path.join(std.testing.allocator, &.{ state_root, "nllclw" });
    defer std.testing.allocator.free(config_root);

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("XDG_STATE_HOME", state_root);
    try map.put("XDG_CONFIG_HOME", config_root);

    const args: []const [:0]const u8 = &.{ "nllclw", "uninstall", "--force" };
    var stdout = Io.Writer.Allocating.init(std.testing.allocator);
    defer stdout.deinit();
    var stderr = Io.Writer.Allocating.init(std.testing.allocator);
    defer stderr.deinit();

    const code = try run(std.testing.allocator, io, &map, args, &stdout.writer, &stderr.writer);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqualStrings("", stderr.written());
    try std.testing.expect(std.mem.indexOf(u8, stdout.written(), "nllclw user files removed") != null);

    try std.testing.expectError(error.FileNotFound, tmp.dir.openDir(io, "nllclw", .{}));
}
