# Configuration

`nllclw` 先由 OS environment variables 配置，其次是 `config.json`，第三是
`.env`。OS env 始终优先。没有 default provider、API key 或 model。

对于常规长期配置，优先使用通常由 `nllclw init` 创建的 `config.json`。OS env
排在第一位，这样 shell、service manager 或 CI job 可以在不编辑 file config 的情况下
override 它。`.env` 是给偏好该 format 的 users 使用的 lower-priority alternative。

## Source order

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

如果同一 setting 存在于多个来源，按以下顺序第一个来源获胜：OS env，
然后是 `config.json`，然后是 `.env`。

`nllclw uninstall` 会删除 `nllclw` 的 user config 和 state directories。

## `config.json` format

运行 `nllclw init` 创建 `config.json`。该文件位于 user config directory，
不在 binary 旁边，也不在当前 project 中：

- 当设置 `XDG_CONFIG_HOME` 时，`$XDG_CONFIG_HOME/nllclw/config.json`
- 否则 `$HOME/.config/nllclw/config.json`
- 在 Windows 上，当设置 `APPDATA` 时，`%APPDATA%\nllclw\config.json`

`config.json` 是 flat JSON object。使用与 `NLLCLW_*` environment keys 相同的
settings，但去掉 `NLLCLW_` 并以 lowercase snake_case 写名称。例如，
`NLLCLW_API_KEY` 变为 `api_key`。

Rules：

- top-level JSON value 必须是 object
- unknown keys 被拒绝
- string values 对每个 setting 都接受
- integer values 只对 integer settings 接受
- boolean values 只对 boolean settings 接受，并映射到 `on`/`off`
- arrays、nested objects、floats 和 `null` 被拒绝
- `config.json` 限制为 16 KiB

Example：

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## `.env` format

运行 `nllclw init --env`，在同一 user config directory 中创建 global `.env`。
如果 `config.json` 已存在，`init --env` 会停止，因为 `config.json` 优先级更高
并会 shadow `.env`。Parser 接受：

- `KEY=VALUE`
- leading and trailing whitespace is trimmed
- blank lines are ignored
- lines starting with `#` are ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys are rejected
- `.env` is capped at 16 KiB
- quoting and interpolation are not supported

Example：

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Required completion keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`、`openrouter` 或 `compatible`。 |
| `NLLCLW_API_KEY` | yes | 作为 `Authorization: Bearer ...` 发送的 Bearer token。 |
| `NLLCLW_MODEL` | yes | Provider model name。 |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL，例如 `https://example.com/v1`。 |

Optional completion keys：

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap，作为 Chat Completions `max_tokens` 传递。 |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header。 |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header。 |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | 允许 compatible local servers 使用 `http://localhost`、`http://127.0.0.1` 或 `http://[::1]`。 |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`、`friendly`、`technical` 或 `witty`。 |
| `NLLCLW_STREAM` | `on` | Streams direct completions。Tool mode 是 non-streaming。 |

`NLLCLW_MODEL` 必须是 single-line valid UTF-8 text。Provider header values
不得包含 ASCII control bytes。

## Provider resolution

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

所有 providers 使用相同的 minimal request shape：

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

启用 tools 时，会添加 `tools` 和 `tool_choice: "auto"`。启用 direct streaming
时，会添加 `stream: true`。

## Compatible provider URL rules

`NLLCLW_BASE_URL`：

- 必须 parse 为 URL；
- 必须有 host；
- 不得包含 userinfo、query string 或 fragment；
- 默认必须使用 `https://`；
- 只有在 `NLLCLW_ALLOW_HTTP_BASE_URL=on` 时，才可对 exact loopback hosts
  使用 `http://`；
- 在追加 `/chat/completions` 前会移除 trailing slashes。

可接受的 local HTTP examples：

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

会被拒绝的 examples：

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | 启用 transcript memory 和 durable fact tools。 |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path。 |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | 发送给 model 的 recent transcript entries 最大数量。必须至少为 2。 |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path。 |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Retained fact entries 最大数量。 |

Configured state file paths 是 user state directory 下的 JSONL subpaths。它们
必须是 relative、valid UTF-8、control-free，最多 512 bytes，不得包含 `.` 或
`..` path components，必须使用 `/` separators 且没有 empty path components，
不得包含 Windows-reserved filename characters，并且必须以 `.jsonl` 结尾。
以空格或点结尾的 components 也会因 portable behavior 而被拒绝。即使包含
extension，`CON`、`NUL`、`CONIN$`、`CONOUT$`、`COM1` 和 `LPT1` 等 Windows
device names 也会被拒绝。Parent directories 在第一次 write 时创建。

Default state files 位于 user state directory：

- 当设置 `XDG_STATE_HOME` 时，`$XDG_STATE_HOME/nllclw`
- 否则 `$HOME/.local/state/nllclw`
- 在 Windows 上，当设置 `LOCALAPPDATA` 时，`%LOCALAPPDATA%\nllclw`

User config and state roots 必须是 absolute paths。Relative `HOME`、
`XDG_CONFIG_HOME`、`XDG_STATE_HOME`、`APPDATA` 和 `LOCALAPPDATA` values 会被
拒绝，使 runtime files 永远不会相对于 current directory 创建。

File formats 和 lifecycle 见 [memory.md](memory.md)。

## Tool keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | 启用 tool loop 和 local tools。设置为 `off` 可禁用所有 tools。 |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds。 |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap，范围 256 bytes 到 1 MiB。 |
| `NLLCLW_FILE_READ` | `on` | 启用 `list_dir` 和 `read_file`。设置 `off` 可禁用 file reads。 |
| `NLLCLW_FILE_WRITE` | `on` | 启用 `write_file` 和 `edit_file`。设置 `off` 可禁用 file writes。 |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | 启用 `cron_set`、`cron_list` 和 `cron_delete`。设置 `off` 可禁用 scheduler tools。 |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path。 |

只要 `NLLCLW_TOOLS=on`，user-defined macro tools 就会启用。它们存储在
`NLLCLW_USER_TOOLS_PATH`。

## Search keys

`web_search` 在配置一个 search provider 前禁用。`auto` mode 按以下顺序选择
第一个已配置 provider：Tavily、Brave Search、Exa、Firecrawl，然后只有在显式
启用时才选择 DuckDuckGo。
如果 `NLLCLW_SEARCH_PROVIDER` 设置为 key-based provider，也必须设置匹配的
`NLLCLW_SEARCH_*_KEY`。
Search keys 不得包含 ASCII control bytes，因为它们作为 HTTP header values
发送。

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`、`tavily`、`brave`、`exa`、`firecrawl` 或 `duckduckgo`。 |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key。 |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key。 |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key。 |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key。 |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | 在 `auto` mode 中启用 no-key DuckDuckGo Instant Answer fallback。 |

仅 optional shell build：

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | 启用 `shell_exec`，但只在用 `-Dshell-tool=true` 构建的 binary 中有效。 |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Optional shell build 的 shell command timeout。 |

Default binary 会拒绝这些 shell keys。设置它们前，请先用 `-Dshell-tool=true`
构建。

详见 [tools.md](tools.md)。

## Telegram keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | 形如 `<bot-id>:<secret>` 的 Telegram Bot API token；bot id 必须是 digits，secret 可使用 letters、digits、`-` 和 `_`。 |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist：non-zero numeric chat id、private-chat `@username`、public-chat `@username`，或不带 `@` 的同一 username。 |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout，单位秒。Default `20`。 |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | 每分钟允许的 model-backed Telegram messages。Default `20`；`0` disables。 |

没有 chat allowlist 时，Telegram 会拒绝启动。配置这些 keys 后，运行
`nllclw telegram` 开始 Bot API long polling。

## WebSocket keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | `nllclw websocket` 要 bind 的 IP literal。Loopback 是 safe default。 |
| `NLLCLW_WS_PORT` | `8765` | WebSocket server 的 TCP port。 |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path。必须以 `/` 开头，是 single-line valid UTF-8，且不能包含 spaces、`?` 或 `#`。 |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token。Loopback clients 可使用 `?token=...`；remote clients 必须使用 `Authorization: Bearer ...`。必须是 8-256 URL-safe ASCII characters。 |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | 仅在设置为 `on` 时允许 non-loopback bind addresses。 |
| `NLLCLW_WS_RATE_LIMIT_PER_MINUTE` | `20` | 每分钟允许的 model-backed WebSocket chat messages。`0` disables。 |

Local UI default：

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Remote bind with token：

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Query-token authentication 仅限 loopback，且只接受一个 `token` parameter。
Remote clients 必须发送恰好一个 `Authorization: Bearer change-me` header；
browser-based remote UIs 应位于 trusted local 或 reverse proxy 后，由其注入
该 header。内置 server 一次只处理一个 active WebSocket client。

## Scheduler and heartbeat keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file。 |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Daemon polling passes 之间的 sleep。 |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Daemon heartbeat passes 之间的 sleep。 |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Time/scheduler formatting 使用的 offset。 |

`NLLCLW_SCHEDULE_PATH` 遵循与 memory 和 user-defined macro tools 相同的
local JSONL state-path rules。

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

通过 compatible provider 使用 Atlas Cloud：

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama local model：

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

通用 compatible HTTPS provider：

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

如需 one-off overrides，可使用 env，并把相同 setting names 转成
`NLLCLW_*`；例如 `model` becomes `NLLCLW_MODEL`。
