# Configuración

`nllclw` se configura primero con OS environment variables, luego con
`config.json` y después con `.env`. OS env siempre gana. No hay proveedor, API
key ni modelo por defecto.

Para una configuración persistente normal, prefiere `config.json`, normalmente
creado por `nllclw init`. OS env va primero para que una shell, un service
manager o un job de CI puedan sobrescribir file config sin editarlo. `.env` es
una alternativa de menor prioridad para usuarios que prefieren ese formato.

## Orden de fuentes

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

Si la misma opción existe en varias fuentes, gana la primera fuente en este
orden: OS env, luego `config.json`, luego `.env`.

`nllclw uninstall` elimina los directorios de configuración y estado de usuario
de `nllclw`.

## Formato de `config.json`

Ejecuta `nllclw init` para crear `config.json`. El archivo vive en el user
config directory, no junto al binario ni en el proyecto actual:

- `$XDG_CONFIG_HOME/nllclw/config.json` cuando `XDG_CONFIG_HOME` está definido
- de lo contrario `$HOME/.config/nllclw/config.json`
- en Windows, `%APPDATA%\nllclw\config.json` cuando `APPDATA` está definido

`config.json` es un objeto JSON plano. Usa las mismas opciones que las claves de
entorno `NLLCLW_*`, pero elimina `NLLCLW_` y escribe el nombre en lowercase
snake_case. Por ejemplo, `NLLCLW_API_KEY` se vuelve `api_key`.

Reglas:

- el top-level JSON value debe ser un objeto
- unknown keys se rechazan
- string values se aceptan para todas las opciones
- integer values se aceptan solo para opciones enteras
- boolean values se aceptan solo para opciones booleanas y se mapean a `on`/`off`
- arrays, nested objects, floats y `null` se rechazan
- `config.json` está limitado a 16 KiB

Ejemplo:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## Formato de `.env`

Ejecuta `nllclw init --env` para crear un `.env` global en el mismo user config
directory. Si `config.json` ya existe, `init --env` se detiene porque
`config.json` tiene mayor prioridad y haría shadow a `.env`. El parser acepta:

- `KEY=VALUE`
- leading and trailing whitespace is trimmed
- blank lines are ignored
- lines starting with `#` are ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys are rejected
- `.env` is capped at 16 KiB
- quoting and interpolation are not supported

Ejemplo:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Claves obligatorias de Completion

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter` o `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token enviado como `Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL como `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap pasado como Chat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Permite `http://localhost`, `http://127.0.0.1` o `http://[::1]` para compatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical` o `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode es non-streaming. |

`NLLCLW_MODEL` debe ser texto UTF-8 válido single-line. Provider header values
no deben contener ASCII control bytes.

## Resolución de proveedor

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

Todos los proveedores usan la misma forma mínima de solicitud:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Cuando tools están habilitadas, se añaden `tools` y `tool_choice: "auto"`.
Cuando direct streaming está habilitado, se añade `stream: true`.

## Reglas de URL para Compatible Provider

`NLLCLW_BASE_URL`:

- debe parsearse como URL;
- debe tener host;
- no debe incluir userinfo, query string ni fragment;
- debe usar `https://` por defecto;
- puede usar `http://` solo para hosts loopback exactos cuando
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- se le eliminan trailing slashes antes de anexar `/chat/completions`.

Ejemplos HTTP locales aceptados:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Ejemplos rechazados:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Habilita transcript memory y durable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Máximo de recent transcript entries enviadas al modelo. Debe ser al menos 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Máximo de retained fact entries. |

Configured state file paths son JSONL subpaths bajo el user state directory.
Deben ser relativas, UTF-8 válidas, sin controles, de máximo 512 bytes, no
deben contener path components `.` o `..`, deben usar `/` separators sin empty
path components, no deben contener Windows-reserved filename characters y deben
terminar en `.jsonl`. Components que terminan en espacio o punto también se
rechazan por portable behavior. Windows device names como `CON`, `NUL`,
`CONIN$`, `CONOUT$`, `COM1` y `LPT1` se rechazan incluso si incluyen una
extension. Parent directories se crean en la primera escritura.

Default state files viven bajo el user state directory:

- `$XDG_STATE_HOME/nllclw` cuando `XDG_STATE_HOME` está definido
- de lo contrario `$HOME/.local/state/nllclw`
- en Windows, `%LOCALAPPDATA%\nllclw` cuando `LOCALAPPDATA` está definido

User config and state roots deben ser absolute paths. Valores relativos de
`HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA` y `LOCALAPPDATA` se
rechazan para que runtime files nunca se creen relativos al current directory.

Consulta [memory.md](memory.md) para los file formats y lifecycle.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Habilita el tool loop y local tools. Pon `off` para deshabilitar todas las tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, de 256 bytes a 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | Habilita `list_dir` y `read_file`. Pon `off` para deshabilitar file reads. |
| `NLLCLW_FILE_WRITE` | `on` | Habilita `write_file` y `edit_file`. Pon `off` para deshabilitar file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | Habilita `cron_set`, `cron_list` y `cron_delete`. Pon `off` para deshabilitar scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

User-defined macro tools están habilitadas siempre que `NLLCLW_TOOLS=on`. Se
almacenan en `NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` está deshabilitado hasta que se configure un search provider. El
modo `auto` elige el primer proveedor configurado en este orden: Tavily, Brave
Search, Exa, Firecrawl, luego DuckDuckGo solo cuando se habilita explícitamente.
Si `NLLCLW_SEARCH_PROVIDER` se establece en un key-based provider, la
`NLLCLW_SEARCH_*_KEY` correspondiente también debe estar definida.
Search keys no deben contener ASCII control bytes porque se envían como HTTP
header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl` o `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | Habilita el no-key DuckDuckGo Instant Answer fallback en modo `auto`. |

Solo optional shell build:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | Habilita `shell_exec`, pero solo en un binary compilado con `-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout para la optional shell build. |

El default binary rechaza estas shell keys. Compila con `-Dshell-tool=true`
antes de configurarlas.

Consulta [tools.md](tools.md) para más detalles.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token en forma `<bot-id>:<secret>`; bot id debe ser digits y el secret puede usar letters, digits, `-` y `_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username` o el mismo username sin `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout en segundos. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages allowed per minute. Default `20`; `0` disables. |

Telegram se niega a arrancar sin una chat allowlist. Después de configurar estas
claves, ejecuta `nllclw telegram` para empezar Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal a la que hacer bind para `nllclw websocket`. Loopback es el safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port del WebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. Debe empezar con `/`, ser UTF-8 válido single-line y no puede incluir spaces, `?` o `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. Loopback clients pueden usar `?token=...`; remote clients deben usar `Authorization: Bearer ...`. Debe tener 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | Permite non-loopback bind addresses solo cuando se establece en `on`. |
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

Query-token authentication es solo loopback y acepta exactamente un parámetro
`token`. Remote clients deben enviar exactamente un header
`Authorization: Bearer change-me`; browser-based remote UIs deben estar detrás
de un trusted local o reverse proxy que inyecte ese header.
El servidor integrado maneja un active WebSocket client a la vez.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep entre daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep entre daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset usado por time/scheduler formatting. |

`NLLCLW_SCHEDULE_PATH` sigue las mismas local JSONL state-path rules que memory
y user-defined macro tools.

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

Atlas Cloud mediante el proveedor compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Modelo local con Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Proveedor HTTPS compatible genérico:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

Usa env para overrides puntuales con los mismos nombres de settings convertidos a
`NLLCLW_*`; por ejemplo, `model` se convierte en `NLLCLW_MODEL`.
