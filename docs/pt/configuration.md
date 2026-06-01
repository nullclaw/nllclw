# Configuração

`nllclw` é configurado primeiro por OS environment variables, depois por
`config.json` e depois por `.env`. OS env sempre vence. Não há provedor, API key
ou modelo padrão.

Para uma configuração persistente normal, prefira `config.json`, normalmente
criado por `nllclw init`. OS env vem primeiro para que uma shell, um service
manager ou um job de CI possa sobrescrever file config sem editá-la. `.env` é uma
alternativa de menor prioridade para usuários que preferem esse formato.

## Ordem das fontes

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

Se a mesma configuração existe em várias fontes, a primeira fonte nesta ordem
vence: OS env, depois `config.json`, depois `.env`.

`nllclw uninstall` remove os diretórios de configuração e estado de usuário do
`nllclw`.

## Formato de `config.json`

Execute `nllclw init` para criar `config.json`. O arquivo vive no user config
directory, não ao lado do binário nem no projeto atual:

- `$XDG_CONFIG_HOME/nllclw/config.json` quando `XDG_CONFIG_HOME` está definido
- caso contrário `$HOME/.config/nllclw/config.json`
- no Windows, `%APPDATA%\nllclw\config.json` quando `APPDATA` está definido

`config.json` é um objeto JSON plano. Use as mesmas settings das chaves de
ambiente `NLLCLW_*`, mas remova `NLLCLW_` e escreva o nome em lowercase
snake_case. Por exemplo, `NLLCLW_API_KEY` vira `api_key`.

Regras:

- top-level JSON value deve ser um objeto
- unknown keys são rejeitadas
- string values são aceitos para toda setting
- integer values são aceitos apenas para integer settings
- boolean values são aceitos apenas para boolean settings e mapeiam para
  `on`/`off`
- arrays, nested objects, floats e `null` são rejeitados
- `config.json` é limitado a 16 KiB

Exemplo:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## Formato de `.env`

Execute `nllclw init --env` para criar um `.env` global no mesmo user config
directory. Se `config.json` já existir, `init --env` para porque `config.json`
tem prioridade maior e faria shadow de `.env`. O parser aceita:

- `KEY=VALUE`
- leading and trailing whitespace is trimmed
- blank lines are ignored
- lines starting with `#` are ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys are rejected
- `.env` is capped at 16 KiB
- quoting and interpolation are not supported

Exemplo:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Chaves obrigatórias de Completion

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter` ou `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token enviado como `Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL como `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap passado como Chat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Permite `http://localhost`, `http://127.0.0.1` ou `http://[::1]` para compatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical` ou `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode é non-streaming. |

`NLLCLW_MODEL` deve ser texto UTF-8 válido single-line. Provider header values
não devem conter ASCII control bytes.

## Resolução do provedor

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

Todos os provedores usam a mesma forma mínima de requisição:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Quando tools são habilitadas, `tools` e `tool_choice: "auto"` são adicionados.
Quando direct streaming é habilitado, `stream: true` é adicionado.

## Regras de URL para Compatible Provider

`NLLCLW_BASE_URL`:

- deve parsear como URL;
- deve ter host;
- não deve incluir userinfo, query string ou fragment;
- deve usar `https://` por padrão;
- pode usar `http://` apenas para hosts loopback exatos quando
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- tem trailing slashes removidos antes de `/chat/completions` ser anexado.

Exemplos HTTP locais aceitos:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Exemplos rejeitados:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Habilita transcript memory e durable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Máximo de recent transcript entries enviadas ao modelo. Deve ser pelo menos 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Máximo de retained fact entries. |

Configured state file paths são JSONL subpaths sob o user state directory. Eles
devem ser relativos, UTF-8 válidos, control-free, ter no máximo 512 bytes, não
devem conter path components `.` ou `..`, devem usar separadores `/` sem empty
path components, não devem conter Windows-reserved filename characters e devem
terminar em `.jsonl`. Components terminados em espaço ou ponto também são
rejeitados por portable behavior. Windows device names como `CON`, `NUL`,
`CONIN$`, `CONOUT$`, `COM1` e `LPT1` são rejeitados mesmo quando incluem uma
extension. Parent directories são criados na primeira escrita.

Default state files vivem sob o user state directory:

- `$XDG_STATE_HOME/nllclw` quando `XDG_STATE_HOME` está definido
- caso contrário `$HOME/.local/state/nllclw`
- no Windows, `%LOCALAPPDATA%\nllclw` quando `LOCALAPPDATA` está definido

User config and state roots devem ser absolute paths. Valores relativos de
`HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA` e `LOCALAPPDATA` são
rejeitados para que runtime files nunca sejam criados relativos ao current
directory.

Veja [memory.md](memory.md) para file formats e lifecycle.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Habilita o tool loop e local tools. Defina `off` para desabilitar todas as tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, de 256 bytes a 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | Habilita `list_dir` e `read_file`. Defina `off` para desabilitar file reads. |
| `NLLCLW_FILE_WRITE` | `on` | Habilita `write_file` e `edit_file`. Defina `off` para desabilitar file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | Habilita `cron_set`, `cron_list` e `cron_delete`. Defina `off` para desabilitar scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

User-defined macro tools são habilitadas sempre que `NLLCLW_TOOLS=on`. Elas são
armazenadas em `NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` fica desabilitado até que um search provider seja configurado. O
modo `auto` escolhe o primeiro provedor configurado nesta ordem: Tavily, Brave
Search, Exa, Firecrawl, depois DuckDuckGo apenas quando explicitamente
habilitado.
Se `NLLCLW_SEARCH_PROVIDER` for definido como um key-based provider, a
`NLLCLW_SEARCH_*_KEY` correspondente também deve ser definida.
Search keys não devem conter ASCII control bytes porque são enviadas como HTTP
header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl` ou `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | Habilita o no-key DuckDuckGo Instant Answer fallback no modo `auto`. |

Apenas optional shell build:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | Habilita `shell_exec`, mas apenas em um binary compilado com `-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout para o optional shell build. |

O default binary rejeita essas shell keys. Compile com `-Dshell-tool=true` antes
de defini-las.

Veja [tools.md](tools.md) para detalhes.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token na forma `<bot-id>:<secret>`; bot id deve ser digits e o secret pode usar letters, digits, `-` e `_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username` ou o mesmo username sem `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout em segundos. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages allowed per minute. Default `20`; `0` disables. |

Telegram se recusa a iniciar sem chat allowlist. Depois de configurar essas
chaves, execute `nllclw telegram` para iniciar Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal para bind de `nllclw websocket`. Loopback é o safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port para o WebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. Deve começar com `/`, ser UTF-8 válido single-line e não pode incluir spaces, `?` ou `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. Loopback clients podem usar `?token=...`; remote clients devem usar `Authorization: Bearer ...`. Deve ter 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | Permite non-loopback bind addresses apenas quando definido como `on`. |
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

Query-token authentication é loopback-only e aceita exatamente um parâmetro
`token`. Remote clients devem enviar exatamente um header
`Authorization: Bearer change-me`; browser-based remote UIs devem ficar atrás
de um trusted local ou reverse proxy que injete esse header.
O servidor embutido lida com um active WebSocket client por vez.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep entre daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep entre daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset usado por time/scheduler formatting. |

`NLLCLW_SCHEDULE_PATH` segue as mesmas local JSONL state-path rules que memory e
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

Atlas Cloud pelo provedor compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Modelo local Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Provedor HTTPS compatible genérico:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

Use env para overrides pontuais com os mesmos nomes de settings convertidos para
`NLLCLW_*`; por exemplo, `model` vira `NLLCLW_MODEL`.
