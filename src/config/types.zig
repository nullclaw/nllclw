const defaults = @import("../defaults.zig");
const persona = @import("../persona.zig");
const provider = @import("../providers.zig");
const telegram_identity = @import("../telegram/identity.zig");

pub const ProviderKind = provider.ProviderKind;
pub const PersonaKind = persona.Kind;
pub const TelegramChatAllowlist = telegram_identity.ChatAllowlist;

pub const Config = struct {
    provider: ProviderKind,
    api_key: []const u8,
    model: []const u8,
    max_tokens: ?u32 = null,
    base_url: ?[]const u8 = null,
    allow_insecure_base_url: bool = false,
    http_referer: ?[]const u8 = null,
    app_title: ?[]const u8 = null,
};

pub const default_memory_max_messages = defaults.memory_max_messages;
pub const default_memory_max_facts = defaults.memory_max_facts;
pub const min_memory_max_messages: usize = 2;
pub const min_memory_max_facts: usize = 1;
pub const max_memory_max_facts: usize = 1024;
pub const default_tools_enabled = defaults.tools_enabled;
pub const default_file_read_enabled = defaults.file_read_enabled;
pub const default_file_write_enabled = defaults.file_write_enabled;
pub const default_schedule_tools_enabled = defaults.schedule_tools_enabled;
pub const default_tool_max_rounds = defaults.tool_max_rounds;
pub const default_tool_output_max_bytes = defaults.tool_output_max_bytes;
pub const default_shell_timeout_ms = defaults.shell_timeout_ms;
pub const default_telegram_poll_timeout_seconds = defaults.telegram_poll_timeout_seconds;
pub const default_telegram_rate_limit_per_minute = defaults.telegram_rate_limit_per_minute;
pub const default_websocket_host = defaults.websocket_host;
pub const default_websocket_port = defaults.websocket_port;
pub const default_websocket_path = defaults.websocket_path;
pub const default_websocket_rate_limit_per_minute = defaults.websocket_rate_limit_per_minute;
pub const default_daemon_interval_seconds = defaults.daemon_interval_seconds;
pub const default_heartbeat_interval_seconds = defaults.heartbeat_interval_seconds;
pub const default_timezone_offset_minutes = defaults.timezone_offset_minutes;

pub const MemoryConfig = struct {
    enabled: bool = true,
    path: ?[]const u8 = null,
    max_messages: usize = default_memory_max_messages,
    facts_path: ?[]const u8 = null,
    max_facts: usize = default_memory_max_facts,
};

pub const ToolsConfig = struct {
    enabled: bool = default_tools_enabled,
    shell_enabled: bool = false,
    file_read_enabled: bool = default_file_read_enabled,
    file_write_enabled: bool = default_file_write_enabled,
    schedule_enabled: bool = default_schedule_tools_enabled,
    user_tools_path: ?[]const u8 = null,
    max_rounds: usize = default_tool_max_rounds,
    output_max_bytes: usize = default_tool_output_max_bytes,
    timeout_ms: u64 = default_shell_timeout_ms,
};

pub const Features = struct {
    shell_tool: bool = false,
};

pub const TelegramConfig = struct {
    token: ?[]const u8 = null,
    chat_id: ?TelegramChatAllowlist = null,
    poll_timeout_seconds: u32 = default_telegram_poll_timeout_seconds,
    rate_limit_per_minute: u32 = default_telegram_rate_limit_per_minute,
};

pub const WebSocketConfig = struct {
    host: []const u8 = default_websocket_host,
    port: u16 = default_websocket_port,
    path: []const u8 = default_websocket_path,
    token: ?[]const u8 = null,
    allow_remote: bool = false,
    rate_limit_per_minute: u32 = default_websocket_rate_limit_per_minute,
};

pub const SearchProvider = enum {
    auto,
    tavily,
    brave,
    exa,
    firecrawl,
    duckduckgo,
};

pub const SearchConfig = struct {
    provider: SearchProvider = .auto,
    tavily_key: ?[]const u8 = null,
    brave_key: ?[]const u8 = null,
    exa_key: ?[]const u8 = null,
    firecrawl_key: ?[]const u8 = null,
    duckduckgo_enabled: bool = false,
};

pub const ScheduleConfig = struct {
    path: ?[]const u8 = null,
    daemon_interval_seconds: u32 = default_daemon_interval_seconds,
    heartbeat_interval_seconds: u32 = default_heartbeat_interval_seconds,
};

pub const RuntimeConfig = struct {
    completion: Config,
    persona: PersonaKind = persona.default_kind,
    memory: MemoryConfig = .{},
    tools: ToolsConfig = .{},
    telegram: TelegramConfig = .{},
    websocket: WebSocketConfig = .{},
    search: SearchConfig = .{},
    schedule: ScheduleConfig = .{},
    timezone_offset_minutes: i32 = default_timezone_offset_minutes,
    stream: bool = true,
};
