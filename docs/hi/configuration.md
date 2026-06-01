# Configuration

`nllclw` पहले OS environment variables से configured होता है, दूसरे `config.json`
से, और तीसरे `.env` से। OS env हमेशा जीतता है। कोई default provider, API key या
model नहीं है।

सामान्य long-lived setup के लिए `config.json` prefer करें, जो आम तौर पर
`nllclw init` बनाता है। OS env पहले आता है ताकि shell, service manager, या CI job
file config edit किए बिना override कर सके। `.env` उस format को prefer करने वाले
users के लिए lower-priority alternative है।

## Source Order

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

अगर वही setting कई sources में हो, तो इस order में पहला source जीतता है: OS env,
फिर `config.json`, फिर `.env`।

`nllclw uninstall` `nllclw` user config और state directories हटाता है।

## `config.json` Format

`config.json` बनाने के लिए `nllclw init` चलाएँ। File user config directory में रहती
है, binary के पास या current project में नहीं:

- `$XDG_CONFIG_HOME/nllclw/config.json` जब `XDG_CONFIG_HOME` set हो
- अन्यथा `$HOME/.config/nllclw/config.json`
- Windows पर, `%APPDATA%\nllclw\config.json` जब `APPDATA` set हो

`config.json` flat JSON object है। `NLLCLW_*` environment keys जैसी ही settings
इस्तेमाल करें, पर `NLLCLW_` हटाकर name को lowercase snake_case में लिखें। उदाहरण:
`NLLCLW_API_KEY` `api_key` बनता है।

Rules:

- top-level JSON value object होना चाहिए
- unknown keys rejected हैं
- string values हर setting के लिए accepted हैं
- integer values केवल integer settings के लिए accepted हैं
- boolean values केवल boolean settings के लिए accepted हैं और `on`/`off` में map होते हैं
- arrays, nested objects, floats और `null` rejected हैं
- `config.json` 16 KiB पर capped है

Example:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## `.env` Format

उसी user config directory में global `.env` बनाने के लिए `nllclw init --env`
चलाएँ। अगर `config.json` पहले से मौजूद है, `init --env` रुकता है क्योंकि
`config.json` higher priority रखता है और `.env` को shadow करेगा। Parser accept करता है:

- `KEY=VALUE`
- leading and trailing whitespace trimmed है
- blank lines ignored हैं
- `#` से शुरू होने वाली lines ignored हैं
- duplicate keys same `.env` के अंदर last value wins use करते हैं
- unknown `NLLCLW_*` keys rejected हैं
- `.env` 16 KiB पर capped है
- quoting और interpolation supported नहीं हैं

Example:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Required Completion Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter`, या `compatible`। |
| `NLLCLW_API_KEY` | yes | `Authorization: Bearer ...` के रूप में भेजा गया Bearer token। |
| `NLLCLW_MODEL` | yes | Provider model name। |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL जैसे `https://example.com/v1`। |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap जो Chat Completions `max_tokens` के रूप में passed है। |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header। |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header। |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Compatible local servers के लिए `http://localhost`, `http://127.0.0.1`, या `http://[::1]` allow करता है। |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical`, या `witty`। |
| `NLLCLW_STREAM` | `on` | Direct completions stream करता है। Tool mode non-streaming है। |

`NLLCLW_MODEL` single-line valid UTF-8 text होना चाहिए। Provider header values में
ASCII control bytes नहीं होने चाहिए।

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

सभी providers वही minimal request shape use करते हैं:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Tools enabled होने पर `tools` और `tool_choice: "auto"` जोड़े जाते हैं। Direct
streaming enabled होने पर `stream: true` जोड़ा जाता है।

## Compatible Provider URL Rules

`NLLCLW_BASE_URL`:

- URL के रूप में parse होना चाहिए;
- host होना चाहिए;
- userinfo, query string या fragment शामिल नहीं होना चाहिए;
- default रूप से `https://` use करना चाहिए;
- `http://` केवल exact loopback hosts के लिए use हो सकता है जब
  `NLLCLW_ALLOW_HTTP_BASE_URL=on` हो;
- `/chat/completions` append होने से पहले trailing slashes removed होते हैं।

Accepted local HTTP उदाहरण:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Rejected उदाहरण:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Transcript memory और durable fact tools enable करता है। |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path। |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Model को भेजी जाने वाली maximum recent transcript entries। कम से कम 2 होना चाहिए। |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path। |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Maximum retained fact entries। |

Configured state file paths user state directory के अंदर JSONL subpaths हैं।
वे relative, valid UTF-8, control-free, अधिकतम 512 bytes, `.` या `..` path
components के बिना होने चाहिए, empty path components के बिना `/` separators use
करने चाहिए, Windows-reserved filename characters नहीं होने चाहिए, और `.jsonl`
पर end होने चाहिए। Space या dot पर ending components भी portable behavior के लिए
rejected हैं। Windows device names जैसे `CON`, `NUL`, `CONIN$`, `CONOUT$`,
`COM1`, और `LPT1` extension सहित भी rejected हैं। Parent directories first write
पर created होते हैं।

Default state files user state directory के अंतर्गत रहते हैं:

- `$XDG_STATE_HOME/nllclw` जब `XDG_STATE_HOME` set हो
- अन्यथा `$HOME/.local/state/nllclw`
- Windows पर, `%LOCALAPPDATA%\nllclw` जब `LOCALAPPDATA` set हो

User config और state roots absolute paths होने चाहिए। Relative `HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA`, और `LOCALAPPDATA` values rejected
हैं ताकि runtime files current directory के relative कभी न बनें।

File formats और lifecycle के लिए [memory.md](memory.md) देखें।

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Tool loop और local tools enable करता है। सभी tools disable करने के लिए `off` set करें। |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds। |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, 256 bytes से 1 MiB तक। |
| `NLLCLW_FILE_READ` | `on` | `list_dir` और `read_file` enable करता है। File reads disable करने के लिए `off` set करें। |
| `NLLCLW_FILE_WRITE` | `on` | `write_file` और `edit_file` enable करता है। File writes disable करने के लिए `off` set करें। |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | `cron_set`, `cron_list`, और `cron_delete` enable करता है। Scheduler tools disable करने के लिए `off` set करें। |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path। |

User-defined macro tools जब भी `NLLCLW_TOOLS=on` हो enabled हैं। वे
`NLLCLW_USER_TOOLS_PATH` में stored होते हैं।

## Search Keys

`web_search` तब तक disabled है जब तक कोई search provider configured न हो। `auto`
mode first configured provider को इस order में चुनता है: Tavily, Brave Search,
Exa, Firecrawl, फिर DuckDuckGo केवल explicit enable होने पर।
अगर `NLLCLW_SEARCH_PROVIDER` key-based provider पर set है, matching
`NLLCLW_SEARCH_*_KEY` भी set होना चाहिए।
Search keys में ASCII control bytes नहीं होने चाहिए क्योंकि वे HTTP header values
के रूप में भेजे जाते हैं।

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl`, या `duckduckgo`। |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key। |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key। |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key। |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key। |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | `auto` mode में no-key DuckDuckGo Instant Answer fallback enable करता है। |

Optional shell build only:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | `shell_exec` enable करता है, लेकिन केवल `-Dshell-tool=true` से built binary में। |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Optional shell build के लिए shell command timeout। |

Default binary इन shell keys को reject करता है। इन्हें set करने से पहले
`-Dshell-tool=true` से build करें।

Details के लिए [tools.md](tools.md) देखें।

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token `<bot-id>:<secret>` form में; bot id digits होना चाहिए और secret letters, digits, `-`, और `_` use कर सकता है। |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username`, या वही username बिना `@`। |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout seconds में। Default `20`। |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | प्रति minute allowed model-backed Telegram messages। Default `20`; `0` disables। |

Telegram chat allowlist के बिना start करने से मना करता है। ये keys configure करने
के बाद Bot API long polling start करने के लिए `nllclw telegram` चलाएँ।

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | `nllclw websocket` के लिए bind होने वाला IP literal। Loopback safe default है। |
| `NLLCLW_WS_PORT` | `8765` | WebSocket server का TCP port। |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path। `/` से शुरू होना चाहिए, single-line valid UTF-8 होना चाहिए, और spaces, `?`, या `#` शामिल नहीं कर सकता। |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token। Loopback clients `?token=...` use कर सकते हैं; remote clients `Authorization: Bearer ...` use करें। 8-256 URL-safe ASCII characters होना चाहिए। |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | केवल `on` set होने पर non-loopback bind addresses allow करता है। |
| `NLLCLW_WS_RATE_LIMIT_PER_MINUTE` | `20` | प्रति minute allowed model-backed WebSocket chat messages। `0` disables। |

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

Query-token authentication loopback-only है और exactly one `token` parameter
accept करता है। Remote clients exactly one `Authorization: Bearer change-me`
header भेजें; browser-based remote UIs trusted local या reverse proxy के पीछे
होनी चाहिए जो वह header inject करे।
Built-in server एक समय में एक active WebSocket client handle करता है।

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file। |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Daemon polling passes के बीच sleep। |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Daemon heartbeat passes के बीच sleep। |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Time/scheduler formatting के लिए used offset। |

`NLLCLW_SCHEDULE_PATH` memory और user-defined macro tools जैसी ही local JSONL
state-path rules follow करता है।

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

Compatible provider के जरिए Atlas Cloud:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama local मॉडल:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

सामान्य compatible HTTPS provider:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

One-off overrides के लिए env का उपयोग करें, उन्हीं setting names को `NLLCLW_*` में convert करके;
जैसे `model` becomes `NLLCLW_MODEL`।
