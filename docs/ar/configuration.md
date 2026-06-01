# Configuration

يُكوّن `nllclw` أولاً عبر OS environment variables، ثم `config.json`، ثم `.env`.
يفوز OS env دائماً. لا يوجد default provider أو API key أو model.

للإعدادات الدائمة العادية، فضّل `config.json` الذي ينشئه عادةً
`nllclw init`. يأتي OS env أولاً حتى تتمكن shell أو service manager أو CI job من
override file config دون تعديلها. `.env` بديل lower-priority لمن يفضّل هذا
format.

## Source Order

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

إذا كانت setting نفسها موجودة في عدة sources، يفوز أول source بهذا الترتيب:
OS env، ثم `config.json`، ثم `.env`.

يزيل `nllclw uninstall` user config وstate directories الخاصة ب`nllclw`.

## `config.json` Format

شغّل `nllclw init` لإنشاء `config.json`. يوجد الملف في user config directory،
وليس بجانب الbinary أو في المشروع الحالي:

- `$XDG_CONFIG_HOME/nllclw/config.json` عندما يكون `XDG_CONFIG_HOME` مضبوطاً
- وإلا `$HOME/.config/nllclw/config.json`
- على Windows، `%APPDATA%\nllclw\config.json` عندما يكون `APPDATA` مضبوطاً

`config.json` هو flat JSON object. استخدم settings نفسها مثل `NLLCLW_*`
environment keys، لكن احذف `NLLCLW_` واكتب الاسم بlowercase snake_case. على سبيل
المثال، يصبح `NLLCLW_API_KEY` هو `api_key`.

Rules:

- top-level JSON value يجب أن يكون object
- unknown keys مرفوضة
- string values مقبولة لكل setting
- integer values مقبولة فقط لinteger settings
- boolean values مقبولة فقط لboolean settings وتُحوّل إلى `on`/`off`
- arrays وnested objects وfloats و`null` مرفوضة
- `config.json` capped عند 16 KiB

Example:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## `.env` Format

شغّل `nllclw init --env` لإنشاء global `.env` في user config directory نفسه. إذا
كان `config.json` موجوداً، يتوقف `init --env` لأن `config.json` له أولوية أعلى
وسيحجب `.env`. يقبل parser:

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
| `NLLCLW_PROVIDER` | yes | `openai` أو `openrouter` أو `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token يُرسل ك`Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL مثل `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap يُمرر كChat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | يسمح ب`http://localhost` أو `http://127.0.0.1` أو `http://[::1]` للcompatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral` أو `friendly` أو `technical` أو `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode non-streaming. |

يجب أن يكون `NLLCLW_MODEL` single-line valid UTF-8 text. يجب ألا تحتوي provider
header values ASCII control bytes.

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

كل providers تستخدم minimal request shape نفسها:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

عندما تكون tools enabled، تضاف `tools` و`tool_choice: "auto"`. عندما تكون direct
streaming enabled، يضاف `stream: true`.

## Compatible Provider URL Rules

`NLLCLW_BASE_URL`:

- يجب أن parse كURL;
- يجب أن يحتوي host;
- يجب ألا يتضمن userinfo أو query string أو fragment;
- يجب أن يستخدم `https://` افتراضياً;
- قد يستخدم `http://` فقط لexact loopback hosts عندما يكون
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- تُزال trailing slashes قبل إضافة `/chat/completions`.

أمثلة local HTTP المقبولة:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

أمثلة مرفوضة:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | يفعّل transcript memory وdurable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Maximum recent transcript entries المرسلة إلى model. يجب أن تكون at least 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Maximum retained fact entries. |

Configured state file paths هي JSONL subpaths تحت user state directory. يجب أن تكون
relative وvalid UTF-8 وcontrol-free وبحد أقصى 512 bytes، وألا تحتوي `.` أو `..`
path components، وأن تستخدم `/` separators بلا empty path components، وألا تحتوي
Windows-reserved filename characters، وأن تنتهي ب`.jsonl`. كما تُرفض components
المنتهية بمسافة أو نقطة من أجل portable behavior. تُرفض Windows device names مثل
`CON` و`NUL` و`CONIN$` و`CONOUT$` و`COM1` و`LPT1` حتى عندما تتضمن extension. تُنشأ
Parent directories عند first write.

Default state files تحت user state directory:

- `$XDG_STATE_HOME/nllclw` عندما يكون `XDG_STATE_HOME` مضبوطاً
- وإلا `$HOME/.local/state/nllclw`
- على Windows، `%LOCALAPPDATA%\nllclw` عندما يكون `LOCALAPPDATA` مضبوطاً

يجب أن تكون user config وstate roots absolute paths. تُرفض relative `HOME` و
`XDG_CONFIG_HOME` و`XDG_STATE_HOME` و`APPDATA` و`LOCALAPPDATA` حتى لا تُنشأ runtime
files أبداً relative to current directory.

راجع [memory.md](memory.md) لتنسيقات الملفات ودورة الحياة.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | يفعّل tool loop وlocal tools. اضبط `off` لتعطيل كل tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap، من 256 bytes إلى 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | يفعّل `list_dir` و`read_file`. اضبط `off` لتعطيل file reads. |
| `NLLCLW_FILE_WRITE` | `on` | يفعّل `write_file` و`edit_file`. اضبط `off` لتعطيل file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | يفعّل `cron_set` و`cron_list` و`cron_delete`. اضبط `off` لتعطيل scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

User-defined macro tools مفعّلة عندما يكون `NLLCLW_TOOLS=on`. تُخزن في
`NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` معطلة حتى يُكوّن search provider واحد. يختار `auto` mode أول configured
provider بهذا الترتيب: Tavily، Brave Search، Exa، Firecrawl، ثم DuckDuckGo فقط عند
explicit enable.
إذا ضُبط `NLLCLW_SEARCH_PROVIDER` على key-based provider، فيجب أيضاً ضبط
`NLLCLW_SEARCH_*_KEY` المطابق.
يجب ألا تحتوي search keys ASCII control bytes لأنها تُرسل كHTTP header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl`, أو `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | يفعّل no-key DuckDuckGo Instant Answer fallback في `auto` mode. |

Optional shell build only:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | يفعّل `shell_exec`، لكن فقط في binary مبني ب`-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout لoptional shell build. |

يرفض default binary هذه shell keys. ابنِ باستخدام `-Dshell-tool=true` قبل ضبطها.

راجع [tools.md](tools.md) للتفاصيل.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token بصيغة `<bot-id>:<secret>`؛ يجب أن يكون bot id digits وقد يستخدم secret letters وdigits و`-` و`_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id أو private-chat `@username` أو public-chat `@username` أو username نفسه بلا `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout بالثواني. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages المسموحة في الدقيقة. Default `20`; `0` disables. |

يرفض Telegram البدء بلا chat allowlist. بعد تكوين هذه keys، شغّل `nllclw telegram`
لبدء Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal للbind عند `nllclw websocket`. Loopback هو safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port لWebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. يجب أن يبدأ ب`/`، ويكون single-line valid UTF-8، ولا يتضمن spaces أو `?` أو `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. يمكن لloopback clients استخدام `?token=...`; يجب أن تستخدم remote clients `Authorization: Bearer ...`. يجب أن يكون 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | يسمح بnon-loopback bind addresses فقط عند ضبطه إلى `on`. |
| `NLLCLW_WS_RATE_LIMIT_PER_MINUTE` | `20` | Model-backed WebSocket chat messages المسموحة في الدقيقة. `0` disables. |

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

Query-token authentication هو loopback-only ويقبل exactly one `token` parameter.
يجب أن ترسل remote clients exactly one `Authorization: Bearer change-me` header؛
يجب أن تكون browser-based remote UIs خلف trusted local أو reverse proxy يحقن ذلك
header. يتعامل built-in server مع active WebSocket client واحد في كل مرة.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep بين daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep بين daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset المستخدم في time/scheduler formatting. |

يتبع `NLLCLW_SCHEDULE_PATH` قواعد local JSONL state-path نفسها مثل memory و
user-defined macro tools.

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

Atlas Cloud عبر compatible provider:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Local model عبر Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Compatible HTTPS provider عام:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

استخدم env للـ one-off overrides مع تحويل أسماء settings نفسها إلى
`NLLCLW_*`، مثلاً `model` تصبح `NLLCLW_MODEL`.
