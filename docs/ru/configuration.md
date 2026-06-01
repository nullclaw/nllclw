# Конфигурация

`nllclw` настраивается сначала через OS environment variables, затем через
`config.json`, затем через `.env`. OS env всегда побеждает. Default provider,
API key или model отсутствуют.

Для обычной постоянной настройки предпочитайте `config.json`, обычно созданный
`nllclw init`. OS env стоит первым, чтобы shell, service manager или CI могли
переопределить file config без редактирования. `.env` — lower-priority
альтернатива для тех, кому удобен этот формат.

## Порядок источников

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

Если одна и та же настройка есть в нескольких источниках, побеждает первый
источник в этом порядке: OS env, затем `config.json`, затем `.env`.

`nllclw uninstall` удаляет пользовательские config и state directories
`nllclw`.

## Формат `config.json`

Запустите `nllclw init`, чтобы создать `config.json`. Файл находится в user
config directory, а не рядом с binary и не в текущем проекте:

- `$XDG_CONFIG_HOME/nllclw/config.json`, когда `XDG_CONFIG_HOME` задан
- иначе `$HOME/.config/nllclw/config.json`
- на Windows, `%APPDATA%\nllclw\config.json`, когда `APPDATA` задан

`config.json` — плоский JSON object. Используйте те же settings, что и
environment keys `NLLCLW_*`, но удалите `NLLCLW_` и запишите имя в lowercase
snake_case. Например, `NLLCLW_API_KEY` становится `api_key`.

Rules:

- top-level JSON value должен быть object
- unknown keys отклоняются
- string values принимаются для всех settings
- integer values принимаются только для integer settings
- boolean values принимаются только для boolean settings и map to `on`/`off`
- arrays, nested objects, floats и `null` отклоняются
- `config.json` ограничен 16 KiB

Example:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## Формат `.env`

Запустите `nllclw init --env`, чтобы создать global `.env` в том же user config
directory. Если `config.json` уже существует, `init --env` stops, потому что
`config.json` имеет более высокий приоритет и shadow `.env`. Parser принимает:

- `KEY=VALUE`
- leading and trailing whitespace trimmed
- blank lines ignored
- lines starting with `#` ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys rejected
- `.env` capped at 16 KiB
- quoting and interpolation are not supported

Example:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Обязательные Completion Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter` или `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token, отправляемый как `Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL, например `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap, передаваемый как Chat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Разрешает `http://localhost`, `http://127.0.0.1` или `http://[::1]` для compatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical` или `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode не streaming. |

`NLLCLW_MODEL` должен быть single-line valid UTF-8 text. Provider header values
не должны содержать ASCII control bytes.

## Разрешение провайдера

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

Все провайдеры используют один и тот же minimal request shape:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Когда tools включены, добавляются `tools` и `tool_choice: "auto"`. Когда direct
streaming включен, добавляется `stream: true`.

## Правила Compatible Provider URL

`NLLCLW_BASE_URL`:

- должен parse as a URL;
- должен иметь host;
- не должен включать userinfo, query string или fragment;
- по умолчанию должен использовать `https://`;
- может использовать `http://` только для exact loopback hosts, когда
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- имеет trailing slashes removed перед добавлением `/chat/completions`.

Допустимые local HTTP examples:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Отклоняемые examples:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Включает transcript memory и durable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Максимум recent transcript entries, отправляемых модели. Должно быть не меньше 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Максимум retained fact entries. |

Configured state file paths являются JSONL subpaths под user state directory.
Они должны быть relative, valid UTF-8, control-free, не больше 512 bytes, не
должны содержать `.` или `..` path components, должны использовать `/`
separators без empty path components, не должны содержать Windows-reserved
filename characters, и должны заканчиваться на `.jsonl`. Components,
заканчивающиеся пробелом или точкой, также отклоняются для portable behavior.
Windows device names, такие как `CON`, `NUL`, `CONIN$`, `CONOUT$`, `COM1` и
`LPT1`, отклоняются даже если содержат extension. Parent directories создаются
при первой записи.

Default state files находятся в user state directory:

- `$XDG_STATE_HOME/nllclw`, когда `XDG_STATE_HOME` задан
- иначе `$HOME/.local/state/nllclw`
- на Windows, `%LOCALAPPDATA%\nllclw`, когда `LOCALAPPDATA` задан

User config and state roots должны быть absolute paths. Relative `HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA` и `LOCALAPPDATA` values
отклоняются, чтобы runtime files никогда не создавались относительно current
directory.

См. [memory.md](memory.md) для file formats и lifecycle.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Включает tool loop и local tools. Установите `off`, чтобы выключить все tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, от 256 bytes до 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | Включает `list_dir` и `read_file`. Установите `off`, чтобы выключить file reads. |
| `NLLCLW_FILE_WRITE` | `on` | Включает `write_file` и `edit_file`. Установите `off`, чтобы выключить file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | Включает `cron_set`, `cron_list` и `cron_delete`. Установите `off`, чтобы выключить scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

User-defined macro tools включены, когда `NLLCLW_TOOLS=on`. Они хранятся в
`NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` выключен, пока не настроен один search provider. `auto` mode
выбирает первый настроенный provider в этом порядке: Tavily, Brave Search, Exa,
Firecrawl, затем DuckDuckGo только при явном включении.
Если `NLLCLW_SEARCH_PROVIDER` установлен в key-based provider, соответствующий
`NLLCLW_SEARCH_*_KEY` тоже должен быть задан.
Search keys не должны содержать ASCII control bytes, потому что отправляются
как HTTP header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl` или `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | Включает no-key DuckDuckGo Instant Answer fallback в `auto` mode. |

Только optional shell build:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | Включает `shell_exec`, но только в binary, собранном с `-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout для optional shell build. |

Default binary отклоняет эти shell keys. Соберите с `-Dshell-tool=true` перед
их настройкой.

См. [tools.md](tools.md) для деталей.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token в форме `<bot-id>:<secret>`; bot id должен быть digits, secret может использовать letters, digits, `-` и `_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username` или тот же username без `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout в секундах. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages allowed per minute. Default `20`; `0` disables. |

Telegram отказывается запускаться без chat allowlist. После настройки этих keys
запустите `nllclw telegram`, чтобы начать Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal для bind `nllclw websocket`. Loopback является safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port для WebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. Должен начинаться с `/`, быть single-line valid UTF-8 и не может включать spaces, `?` или `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. Loopback clients могут использовать `?token=...`; remote clients должны использовать `Authorization: Bearer ...`. Должен быть 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | Разрешает non-loopback bind addresses только при `on`. |
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

Query-token authentication только loopback и принимает ровно один параметр
`token`. Remote clients должны отправлять ровно один
`Authorization: Bearer change-me` header; browser-based remote UIs должны быть
за trusted local или reverse proxy, который injects that header.
Встроенный server handles one active WebSocket client at a time.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep между daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep между daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset, используемый time/scheduler formatting. |

`NLLCLW_SCHEDULE_PATH` следует тем же local JSONL state-path rules, что memory
и user-defined macro tools.

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

Atlas Cloud через compatible provider:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Локальная модель Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Общий compatible HTTPS provider:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

Используйте env для разовых override с теми же setting names, преобразованными
в `NLLCLW_*`: например, `model` становится `NLLCLW_MODEL`.
