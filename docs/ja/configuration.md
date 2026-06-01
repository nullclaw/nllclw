# Configuration

`nllclw` はまず OS environment variables、次に `config.json`、3 番目に `.env` で
configured されます。OS env は常に wins します。Default provider、API key、model はありません。

通常の long-lived setup では、`nllclw init` が作る `config.json` を優先します。
OS env は先頭にあり、shell、service manager、CI job が file config を編集せずに
override できるようにします。`.env` はその format を好む users 向けの
lower-priority alternative です。

## Source Order

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

同じ setting が複数の sources にある場合、この順序で最初の source が wins します:
OS env、次に `config.json`、次に `.env`。

`nllclw uninstall` は `nllclw` user config と state directories を remove します。

## `config.json` Format

`config.json` を作るには `nllclw init` を実行します。File は user config directory
にあり、binary の隣や current project の中にはありません:

- `XDG_CONFIG_HOME` が set されている場合、`$XDG_CONFIG_HOME/nllclw/config.json`
- それ以外は `$HOME/.config/nllclw/config.json`
- Windows では、`APPDATA` が set されている場合 `%APPDATA%\nllclw\config.json`

`config.json` は flat JSON object です。`NLLCLW_*` environment keys と同じ settings
を使いますが、`NLLCLW_` を取り除き、name を lowercase snake_case で書きます。
たとえば `NLLCLW_API_KEY` は `api_key` になります。

Rules:

- top-level JSON value は object である必要があります
- unknown keys are rejected
- string values はすべての setting に accepted
- integer values は integer settings にだけ accepted
- boolean values は boolean settings にだけ accepted され、`on`/`off` に map されます
- arrays、nested objects、floats、`null` are rejected
- `config.json` は 16 KiB で capped

Example:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## `.env` Format

同じ user config directory に global `.env` を作るには `nllclw init --env` を実行します。
`config.json` がすでに存在する場合、`init --env` は停止します。`config.json` は
higher priority で `.env` を shadow するためです。Parser は次を accept します:

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
| `NLLCLW_PROVIDER` | yes | `openai`、`openrouter`、または `compatible`。 |
| `NLLCLW_API_KEY` | yes | `Authorization: Bearer ...` として sent される Bearer token。 |
| `NLLCLW_MODEL` | yes | Provider model name。 |
| `NLLCLW_BASE_URL` | only for `compatible` | `https://example.com/v1` のような Base URL。 |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Chat Completions `max_tokens` として passed される optional positive integer output cap。 |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header。 |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header。 |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Compatible local servers に `http://localhost`、`http://127.0.0.1`、`http://[::1]` を allow します。 |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`、`friendly`、`technical`、`witty`。 |
| `NLLCLW_STREAM` | `on` | Direct completions を stream します。Tool mode は non-streaming。 |

`NLLCLW_MODEL` は single-line valid UTF-8 text である必要があります。Provider
header values は ASCII control bytes を含んではいけません。

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

すべての providers は同じ minimal request shape を使います:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Tools が enabled の場合、`tools` と `tool_choice: "auto"` が追加されます。
Direct streaming が enabled の場合、`stream: true` が追加されます。

## Compatible Provider URL Rules

`NLLCLW_BASE_URL`:

- URL として parse できる必要があります;
- host が必要です;
- userinfo、query string、fragment を含んではいけません;
- default では `https://` を使う必要があります;
- `NLLCLW_ALLOW_HTTP_BASE_URL=on` の場合だけ、exact loopback hosts に `http://` を使えます;
- `/chat/completions` が appended される前に trailing slashes が removed されます。

Accepted local HTTP の例:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

拒否される examples:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Transcript memory と durable fact tools を enable します。 |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path。 |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Model に送られる maximum recent transcript entries。少なくとも 2 である必要があります。 |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path。 |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Maximum retained fact entries。 |

Configured state file paths は user state directory の下の JSONL subpaths です。
Relative、valid UTF-8、control-free、最大 512 bytes であり、`.` または `..` path
components を含まず、empty path components のない `/` separators を使い、
Windows-reserved filename characters を含まず、`.jsonl` で終わる必要があります。
Space または dot で終わる components も portable behavior のため rejected されます。
`CON`、`NUL`、`CONIN$`、`CONOUT$`、`COM1`、`LPT1` などの Windows device names は
extension を含んでも rejected されます。Parent directories は first write で created されます。

Default state files は user state directory の下にあります:

- `XDG_STATE_HOME` が set されている場合、`$XDG_STATE_HOME/nllclw`
- それ以外は `$HOME/.local/state/nllclw`
- Windows では、`LOCALAPPDATA` が set されている場合 `%LOCALAPPDATA%\nllclw`

User config と state roots は absolute paths である必要があります。Relative な
`HOME`、`XDG_CONFIG_HOME`、`XDG_STATE_HOME`、`APPDATA`、`LOCALAPPDATA` values は
rejected されるため、runtime files が current directory 相対に作られることはありません。

File formats と lifecycle は [memory.md](memory.md) を参照してください。

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Tool loop と local tools を enable します。すべての tools を disable するには `off` を set します。 |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds。 |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap。256 bytes から 1 MiB。 |
| `NLLCLW_FILE_READ` | `on` | `list_dir` と `read_file` を enable します。File reads を disable するには `off` を set します。 |
| `NLLCLW_FILE_WRITE` | `on` | `write_file` と `edit_file` を enable します。File writes を disable するには `off` を set します。 |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | `cron_set`、`cron_list`、`cron_delete` を enable します。Scheduler tools を disable するには `off` を set します。 |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path。 |

User-defined macro tools は `NLLCLW_TOOLS=on` のとき enabled です。それらは
`NLLCLW_USER_TOOLS_PATH` に stored されます。

## Search Keys

`web_search` は search provider が 1 つ configured されるまで disabled です。
`auto` mode は次の order で最初の configured provider を選びます: Tavily、Brave
Search、Exa、Firecrawl、そして DuckDuckGo は explicitly enabled の場合だけ。
`NLLCLW_SEARCH_PROVIDER` が key-based provider に set されている場合、対応する
`NLLCLW_SEARCH_*_KEY` も set されている必要があります。
Search keys は HTTP header values として sent されるため、ASCII control bytes を含んではいけません。

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`、`tavily`、`brave`、`exa`、`firecrawl`、`duckduckgo`。 |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key。 |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key。 |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key。 |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key。 |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | `auto` mode の no-key DuckDuckGo Instant Answer fallback を enable します。 |

Optional shell build only:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | `shell_exec` を enable します。ただし `-Dshell-tool=true` で built された binary だけです。 |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Optional shell build の shell command timeout。 |

Default binary はこれらの shell keys を reject します。Set する前に
`-Dshell-tool=true` で build してください。

Details は [tools.md](tools.md) を参照してください。

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | `<bot-id>:<secret>` 形式の Telegram Bot API token。bot id は digits、secret は letters、digits、`-`、`_` を使えます。 |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id、private-chat `@username`、public-chat `@username`、または `@` なしの同じ username。 |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout in seconds。Default `20`。 |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | 1 分あたり allowed model-backed Telegram messages。Default `20`; `0` disables。 |

Telegram は chat allowlist なしでは start しません。これらの keys を configure
した後、Bot API long polling を start するには `nllclw telegram` を実行します。

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | `nllclw websocket` が bind する IP literal。Loopback は safe default。 |
| `NLLCLW_WS_PORT` | `8765` | WebSocket server の TCP port。 |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path。`/` で始まり、single-line valid UTF-8 で、spaces、`?`、`#` を含められません。 |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token。Loopback clients は `?token=...` を使えます。Remote clients は `Authorization: Bearer ...` を使う必要があります。8-256 URL-safe ASCII characters。 |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | `on` に set された場合だけ non-loopback bind addresses を allow します。 |
| `NLLCLW_WS_RATE_LIMIT_PER_MINUTE` | `20` | 1 分あたり allowed model-backed WebSocket chat messages。`0` disables。 |

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

Query-token authentication は loopback-only で、exactly one `token` parameter を
accept します。Remote clients は exactly one `Authorization: Bearer change-me`
header を送る必要があります。Browser-based remote UIs は、その header を inject
する trusted local または reverse proxy の背後に置くべきです。
Built-in server は一度に 1 つの active WebSocket client を handle します。

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file。 |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Daemon polling passes の間の sleep。 |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Daemon heartbeat passes の間の sleep。 |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Time/scheduler formatting で使われる offset。 |

`NLLCLW_SCHEDULE_PATH` は memory と user-defined macro tools と同じ local JSONL
state-path rules に従います。

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

Compatible provider 経由の Atlas Cloud:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama の local model:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

汎用 compatible HTTPS provider:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

One-off overrides には、同じ setting names を `NLLCLW_*` に変換した env を使います。
たとえば `model` は `NLLCLW_MODEL` になります。
