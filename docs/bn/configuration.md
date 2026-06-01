# Configuration

`nllclw` প্রথমে OS environment variables, দ্বিতীয় `config.json`, এবং তৃতীয় `.env`
দিয়ে configured হয়। OS env সবসময় wins। কোনো default provider, API key, বা model নেই।

সাধারণ long-lived setup-এর জন্য `config.json` prefer করুন; সাধারণত এটি
`nllclw init` তৈরি করে। OS env আগে থাকে যাতে shell, service manager, বা CI job
file config edit না করেই override করতে পারে। `.env` এই format পছন্দ করা users-এর
জন্য lower-priority alternative।

## Source Order

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

একই setting একাধিক sources-এ থাকলে এই order-এ first source wins: OS env, তারপর
`config.json`, তারপর `.env`।

`nllclw uninstall` `nllclw` user config এবং state directories remove করে।

## `config.json` Format

`config.json` তৈরি করতে `nllclw init` চালান। File user config directory-তে থাকে,
binary-এর পাশে বা current project-এ নয়:

- `$XDG_CONFIG_HOME/nllclw/config.json` যখন `XDG_CONFIG_HOME` set থাকে
- অন্যথায় `$HOME/.config/nllclw/config.json`
- Windows-এ, `%APPDATA%\nllclw\config.json` যখন `APPDATA` set থাকে

`config.json` একটি flat JSON object। `NLLCLW_*` environment keys-এর মতো একই settings
ব্যবহার করুন, কিন্তু `NLLCLW_` সরিয়ে name lowercase snake_case-এ লিখুন। উদাহরণ:
`NLLCLW_API_KEY` হয় `api_key`।

Rules:

- top-level JSON value object হতে হবে
- unknown keys rejected
- string values প্রতিটি setting-এর জন্য accepted
- integer values শুধু integer settings-এর জন্য accepted
- boolean values শুধু boolean settings-এর জন্য accepted এবং `on`/`off`-এ map হয়
- arrays, nested objects, floats, এবং `null` rejected
- `config.json` 16 KiB-এ capped

Example:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## `.env` Format

একই user config directory-তে global `.env` তৈরি করতে `nllclw init --env` চালান।
`config.json` আগে থেকে থাকলে `init --env` stops, কারণ `config.json` higher priority
এবং `.env` shadow করবে। Parser accepts:

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
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter`, বা `compatible`। |
| `NLLCLW_API_KEY` | yes | `Authorization: Bearer ...` হিসেবে sent Bearer token। |
| `NLLCLW_MODEL` | yes | Provider model name। |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL যেমন `https://example.com/v1`। |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Chat Completions `max_tokens` হিসেবে passed optional positive integer output cap। |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header। |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header। |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Compatible local servers-এর জন্য `http://localhost`, `http://127.0.0.1`, বা `http://[::1]` allow করে। |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical`, বা `witty`। |
| `NLLCLW_STREAM` | `on` | Direct completions stream করে। Tool mode non-streaming। |

`NLLCLW_MODEL` single-line valid UTF-8 text হতে হবে। Provider header values-এ
ASCII control bytes থাকতে পারবে না।

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

সব providers একই minimal request shape ব্যবহার করে:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Tools enabled হলে `tools` এবং `tool_choice: "auto"` যোগ হয়। Direct streaming enabled
হলে `stream: true` যোগ হয়।

## Compatible Provider URL Rules

`NLLCLW_BASE_URL`:

- URL হিসেবে parse হতে হবে;
- host থাকতে হবে;
- userinfo, query string, বা fragment থাকতে পারবে না;
- defaultভাবে `https://` ব্যবহার করতে হবে;
- `http://` শুধু exact loopback hosts-এর জন্য ব্যবহার করা যায় যখন
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- `/chat/completions` append করার আগে trailing slashes removed হয়।

Accepted local HTTP উদাহরণ:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Rejected উদাহরণ:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Transcript memory এবং durable fact tools enable করে। |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path। |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Model-এ sent maximum recent transcript entries। অন্তত 2 হতে হবে। |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path। |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Maximum retained fact entries। |

Configured state file paths user state directory-এর অধীনে JSONL subpaths। এগুলো
relative, valid UTF-8, control-free, সর্বোচ্চ 512 bytes হতে হবে, `.` বা `..` path
components থাকতে পারবে না, empty path components ছাড়া `/` separators ব্যবহার করতে
হবে, Windows-reserved filename characters থাকতে পারবে না, এবং `.jsonl` দিয়ে end
হতে হবে। Space বা dot দিয়ে ending components portable behavior-এর জন্য rejected।
`CON`, `NUL`, `CONIN$`, `CONOUT$`, `COM1`, এবং `LPT1`-এর মতো Windows device names
extension থাকলেও rejected। Parent directories first write-এ created হয়।

Default state files user state directory-এর নিচে থাকে:

- `$XDG_STATE_HOME/nllclw` যখন `XDG_STATE_HOME` set থাকে
- অন্যথায় `$HOME/.local/state/nllclw`
- Windows-এ, `%LOCALAPPDATA%\nllclw` যখন `LOCALAPPDATA` set থাকে

User config এবং state roots absolute paths হতে হবে। Relative `HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA`, এবং `LOCALAPPDATA` values rejected,
যাতে runtime files কখনও current directory-এর relative তৈরি না হয়।

File formats এবং lifecycle-এর জন্য [memory.md](memory.md) দেখুন।

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Tool loop এবং local tools enable করে। সব tools disable করতে `off` set করুন। |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds। |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, 256 bytes থেকে 1 MiB। |
| `NLLCLW_FILE_READ` | `on` | `list_dir` এবং `read_file` enable করে। File reads disable করতে `off` set করুন। |
| `NLLCLW_FILE_WRITE` | `on` | `write_file` এবং `edit_file` enable করে। File writes disable করতে `off` set করুন। |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | `cron_set`, `cron_list`, এবং `cron_delete` enable করে। Scheduler tools disable করতে `off` set করুন। |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path। |

User-defined macro tools যখনই `NLLCLW_TOOLS=on` তখন enabled। এগুলো
`NLLCLW_USER_TOOLS_PATH`-এ stored হয়।

## Search Keys

`web_search` disabled থাকে যতক্ষণ না কোনো search provider configured হয়। `auto`
mode প্রথম configured provider এই order-এ নেয়: Tavily, Brave Search, Exa,
Firecrawl, তারপর DuckDuckGo শুধু explicitly enabled হলে।
`NLLCLW_SEARCH_PROVIDER` key-based provider-এ set থাকলে matching
`NLLCLW_SEARCH_*_KEY`-ও set থাকতে হবে।
Search keys-এ ASCII control bytes থাকতে পারবে না কারণ এগুলো HTTP header values
হিসেবে sent হয়।

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl`, বা `duckduckgo`। |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key। |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key। |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key। |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key। |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | `auto` mode-এ no-key DuckDuckGo Instant Answer fallback enable করে। |

Optional shell build only:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | `shell_exec` enable করে, কিন্তু শুধু `-Dshell-tool=true` দিয়ে built binary-তে। |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Optional shell build-এর shell command timeout। |

Default binary এই shell keys reject করে। এগুলো set করার আগে `-Dshell-tool=true`
দিয়ে build করুন।

Details-এর জন্য [tools.md](tools.md) দেখুন।

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token `<bot-id>:<secret>` form-এ; bot id digits হতে হবে এবং secret letters, digits, `-`, এবং `_` ব্যবহার করতে পারে। |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username`, বা `@` ছাড়া একই username। |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout seconds-এ। Default `20`। |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | প্রতি minute allowed model-backed Telegram messages। Default `20`; `0` disables। |

Chat allowlist ছাড়া Telegram start করে না। এই keys configure করার পরে Bot API
long polling start করতে `nllclw telegram` চালান।

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | `nllclw websocket`-এর bind IP literal। Loopback safe default। |
| `NLLCLW_WS_PORT` | `8765` | WebSocket server-এর TCP port। |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path। `/` দিয়ে শুরু হতে হবে, single-line valid UTF-8 হতে হবে, এবং spaces, `?`, বা `#` থাকতে পারবে না। |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token। Loopback clients `?token=...` use করতে পারে; remote clients `Authorization: Bearer ...` use করতে হবে। 8-256 URL-safe ASCII characters হতে হবে। |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | শুধু `on` set থাকলে non-loopback bind addresses allow করে। |
| `NLLCLW_WS_RATE_LIMIT_PER_MINUTE` | `20` | প্রতি minute allowed model-backed WebSocket chat messages। `0` disables। |

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

Query-token authentication loopback-only এবং exactly one `token` parameter accept
করে। Remote clients exactly one `Authorization: Bearer change-me` header পাঠাতে
হবে; browser-based remote UIs trusted local বা reverse proxy-এর পেছনে থাকা উচিত
যা সেই header inject করে। Built-in server এক সময়ে এক active WebSocket client handle করে।

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file। |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Daemon polling passes-এর মধ্যে sleep। |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Daemon heartbeat passes-এর মধ্যে sleep। |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Time/scheduler formatting-এ used offset। |

`NLLCLW_SCHEDULE_PATH` memory এবং user-defined macro tools-এর মতো একই local JSONL
state-path rules follow করে।

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

Compatible provider দিয়ে Atlas Cloud:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama local মডেল:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

সাধারণ compatible HTTPS provider উদাহরণ:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

একই setting names `NLLCLW_*`-এ convert করে one-off overrides-এর জন্য env ব্যবহার করুন;
যেমন `model` becomes `NLLCLW_MODEL`।
