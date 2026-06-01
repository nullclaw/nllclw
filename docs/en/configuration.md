# Configuration

`nllclw` is configured by OS environment variables first, `config.json` second,
and `.env` third. OS env always wins. There is no default provider, API key, or
model.

For normal long-lived setup, prefer `config.json`, usually created by
`nllclw init`. OS env is first so a shell, service manager, or CI job can
override file config without editing it. `.env` is a lower-priority alternative
for users who prefer that format.

## Source Order

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

If the same setting exists in multiple sources, the first source in this order
wins: OS env, then `config.json`, then `.env`.

`nllclw uninstall` removes the `nllclw` user config and state directories.

## `config.json` Format

Run `nllclw init` to create `config.json`. The file lives in the user config
directory, not beside the binary or in the current project:

- `$XDG_CONFIG_HOME/nllclw/config.json` when `XDG_CONFIG_HOME` is set
- otherwise `$HOME/.config/nllclw/config.json`
- on Windows, `%APPDATA%\nllclw\config.json` when `APPDATA` is set

`config.json` is a flat JSON object. Use the same settings as the `NLLCLW_*`
environment keys, but remove `NLLCLW_` and write the name in lowercase
snake_case. For example, `NLLCLW_API_KEY` becomes `api_key`.

Rules:

- top-level JSON value must be an object
- unknown keys are rejected
- string values are accepted for every setting
- integer values are accepted only for integer settings
- boolean values are accepted only for boolean settings and map to `on`/`off`
- arrays, nested objects, floats, and `null` are rejected
- `config.json` is capped at 16 KiB

Example:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## `.env` Format

Run `nllclw init --env` to create a global `.env` in the same user config
directory. If `config.json` already exists, `init --env` stops because
`config.json` has higher priority and would shadow `.env`. The parser accepts:

- `KEY=VALUE`
- leading and trailing whitespace is trimmed
- blank lines are ignored
- lines starting with `#` are ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys are rejected
- `.env` is capped at 16 KiB
- quoting and interpolation are not supported

Example:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Required Completion Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter`, or `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token sent as `Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL such as `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap passed as Chat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Allows `http://localhost`, `http://127.0.0.1`, or `http://[::1]` for compatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical`, or `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode is non-streaming. |

`NLLCLW_MODEL` must be single-line valid UTF-8 text. Provider header values
must not contain ASCII control bytes.

## Provider Resolution

```mermaid
flowchart TD
    Kind["NLLCLW_PROVIDER"] --> OpenAI{"openai?"}
    Kind --> OpenRouter{"openrouter?"}
    Kind --> Compat{"compatible?"}
    OpenAI -->|yes| OpenAIURL["https://api.openai.com/v1/chat/completions"]
    OpenRouter -->|yes| ORURL["https://openrouter.ai/api/v1/chat/completions"]
    Compat -->|yes| Validate["validate NLLCLW_BASE_URL"]
    Validate --> Append["trim trailing slash + /chat/completions"]
```

All providers use the same minimal request shape:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

When tools are enabled, `tools` and `tool_choice: "auto"` are added. When direct
streaming is enabled, `stream: true` is added.

## Compatible Provider URL Rules

`NLLCLW_BASE_URL`:

- must parse as a URL;
- must have a host;
- must not include userinfo, query string, or fragment;
- must use `https://` by default;
- may use `http://` only for exact loopback hosts when
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- has trailing slashes removed before `/chat/completions` is appended.

Accepted local HTTP examples:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Rejected examples:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Enables transcript memory and durable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Maximum recent transcript entries sent to the model. Must be at least 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Maximum retained fact entries. |

Configured state file paths are JSONL subpaths under the user state directory.
They must be relative, valid UTF-8, control-free, at most 512 bytes, must not
contain `.` or `..` path components, must use `/` separators without empty path
components, must not contain Windows-reserved filename characters, and must end
in `.jsonl`. Components ending in a space or dot are also rejected for portable
behavior. Windows device names such as `CON`, `NUL`, `CONIN$`, `CONOUT$`,
`COM1`, and `LPT1` are rejected even when they include an extension. Parent
directories are created on first write.

Default state files live under the user state directory:

- `$XDG_STATE_HOME/nllclw` when `XDG_STATE_HOME` is set
- otherwise `$HOME/.local/state/nllclw`
- on Windows, `%LOCALAPPDATA%\nllclw` when `LOCALAPPDATA` is set

User config and state roots must be absolute paths. Relative `HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA`, and `LOCALAPPDATA` values are
rejected so runtime files are never created relative to the current directory.

See [memory.md](memory.md) for the file formats and lifecycle.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Enables the tool loop and local tools. Set `off` to disable all tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, 256 bytes to 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | Enables `list_dir` and `read_file`. Set `off` to disable file reads. |
| `NLLCLW_FILE_WRITE` | `on` | Enables `write_file` and `edit_file`. Set `off` to disable file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | Enables `cron_set`, `cron_list`, and `cron_delete`. Set `off` to disable scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

User-defined macro tools are enabled whenever `NLLCLW_TOOLS=on`. They are stored
in `NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` is disabled until one search provider is configured. `auto` mode
picks the first configured provider in this order: Tavily, Brave Search, Exa,
Firecrawl, then DuckDuckGo only when explicitly enabled.
If `NLLCLW_SEARCH_PROVIDER` is set to a key-based provider, the matching
`NLLCLW_SEARCH_*_KEY` must also be set.
Search keys must not contain ASCII control bytes because they are sent as HTTP
header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl`, or `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | Enables the no-key DuckDuckGo Instant Answer fallback in `auto` mode. |

Optional shell build only:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | Enables `shell_exec`, but only in a binary built with `-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout for the optional shell build. |

The default binary rejects these shell keys. Build with `-Dshell-tool=true`
before setting them.

See [tools.md](tools.md) for details.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token in `<bot-id>:<secret>` form; bot id must be digits and the secret may use letters, digits, `-`, and `_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: a non-zero numeric chat id, private-chat `@username`, public-chat `@username`, or the same username without `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout in seconds. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages allowed per minute. Default `20`; `0` disables. |

Telegram refuses to start without a chat allowlist. After configuring these
keys, run `nllclw telegram` to start Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal to bind for `nllclw websocket`. Loopback is the safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port for the WebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. Must start with `/`, be single-line valid UTF-8, and cannot include spaces, `?`, or `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. Loopback clients may use `?token=...`; remote clients must use `Authorization: Bearer ...`. Must be 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | Allows non-loopback bind addresses only when set to `on`. |
| `NLLCLW_WS_RATE_LIMIT_PER_MINUTE` | `20` | Model-backed WebSocket chat messages allowed per minute. `0` disables. |

Local UI default:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Remote bind with token:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Query-token authentication is loopback-only and accepts exactly one `token`
parameter. Remote clients must send exactly one
`Authorization: Bearer change-me` header; browser-based remote UIs should sit
behind a trusted local or reverse proxy that injects that header.
The built-in server handles one active WebSocket client at a time.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep between daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep between daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset used by time/scheduler formatting. |

`NLLCLW_SCHEDULE_PATH` follows the same local JSONL state-path rules as memory
and user-defined macro tools.

## Minimal Configs

OpenRouter:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

OpenAI:

```json
{
  "provider": "openai",
  "api_key": "sk-...",
  "model": "gpt-4o"
}
```

Atlas Cloud through the compatible provider:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama local model:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Generic compatible HTTPS provider:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

Use env for one-off overrides with the same setting names converted to
`NLLCLW_*`, for example `model` becomes `NLLCLW_MODEL`.
