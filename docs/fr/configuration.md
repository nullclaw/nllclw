# Configuration

`nllclw` est configuré d'abord par les OS environment variables, puis
`config.json`, puis `.env`. OS env gagne toujours. Il n'y a pas de fournisseur,
API key ou modèle par défaut.

Pour une configuration durable normale, préférez `config.json`, généralement
créé par `nllclw init`. OS env passe en premier afin qu'un shell, un service
manager ou un job CI puisse override la file config sans la modifier. `.env` est
une alternative de priorité inférieure pour les utilisateurs qui préfèrent ce
format.

## Ordre des sources

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

Si le même réglage existe dans plusieurs sources, la première source de cet
ordre gagne: OS env, puis `config.json`, puis `.env`.

`nllclw uninstall` supprime les répertoires de configuration et d'état
utilisateur de `nllclw`.

## Format `config.json`

Exécutez `nllclw init` pour créer `config.json`. Le fichier vit dans le user
config directory, pas à côté du binaire ni dans le projet courant:

- `$XDG_CONFIG_HOME/nllclw/config.json` lorsque `XDG_CONFIG_HOME` est défini
- sinon `$HOME/.config/nllclw/config.json`
- sur Windows, `%APPDATA%\nllclw\config.json` lorsque `APPDATA` est défini

`config.json` est un objet JSON plat. Utilisez les mêmes settings que les clés
d'environnement `NLLCLW_*`, mais retirez `NLLCLW_` et écrivez le nom en
lowercase snake_case. Par exemple, `NLLCLW_API_KEY` devient `api_key`.

Règles:

- la valeur JSON top-level doit être un objet
- les unknown keys sont rejetées
- les string values sont acceptées pour chaque setting
- les integer values ne sont acceptées que pour les integer settings
- les boolean values ne sont acceptées que pour les boolean settings et mappent
  vers `on`/`off`
- arrays, nested objects, floats et `null` sont rejetés
- `config.json` est plafonné à 16 KiB

Exemple:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## Format `.env`

Exécutez `nllclw init --env` pour créer un `.env` global dans le même user
config directory. Si `config.json` existe déjà, `init --env` s'arrête parce que
`config.json` a une priorité plus haute et ferait shadow à `.env`. Le parser
accepte:

- `KEY=VALUE`
- leading and trailing whitespace is trimmed
- blank lines are ignored
- lines starting with `#` are ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys are rejected
- `.env` is capped at 16 KiB
- quoting and interpolation are not supported

Exemple:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Clés Completion obligatoires

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter` ou `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token envoyé comme `Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL comme `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap passé comme Chat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Autorise `http://localhost`, `http://127.0.0.1` ou `http://[::1]` pour compatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical` ou `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode est non-streaming. |

`NLLCLW_MODEL` doit être du texte UTF-8 valide single-line. Les provider header
values ne doivent pas contenir d'ASCII control bytes.

## Résolution du fournisseur

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

Tous les fournisseurs utilisent la même forme minimale de requête:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Lorsque tools est activé, `tools` et `tool_choice: "auto"` sont ajoutés.
Lorsque direct streaming est activé, `stream: true` est ajouté.

## Règles d'URL Compatible Provider

`NLLCLW_BASE_URL`:

- doit se parser comme URL;
- doit avoir un host;
- ne doit pas inclure userinfo, query string ou fragment;
- doit utiliser `https://` par défaut;
- peut utiliser `http://` seulement pour des hosts loopback exacts lorsque
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- a ses trailing slashes retirés avant l'ajout de `/chat/completions`.

Exemples HTTP locaux acceptés:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Exemples rejetés:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Active transcript memory et durable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Nombre maximum de recent transcript entries envoyées au modèle. Doit être au moins 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Nombre maximum de retained fact entries. |

Les configured state file paths sont des JSONL subpaths sous le user state
directory. Ils doivent être relatifs, UTF-8 valides, control-free, d'au plus
512 bytes, ne pas contenir de path components `.` ou `..`, utiliser des
séparateurs `/` sans empty path components, ne pas contenir de Windows-reserved
filename characters, et finir en `.jsonl`. Les components finissant par un
espace ou un point sont aussi rejetés pour portable behavior. Les Windows device
names comme `CON`, `NUL`, `CONIN$`, `CONOUT$`, `COM1` et `LPT1` sont rejetés
même lorsqu'ils incluent une extension. Les parent directories sont créés à la
première écriture.

Les default state files vivent sous le user state directory:

- `$XDG_STATE_HOME/nllclw` lorsque `XDG_STATE_HOME` est défini
- sinon `$HOME/.local/state/nllclw`
- sur Windows, `%LOCALAPPDATA%\nllclw` lorsque `LOCALAPPDATA` est défini

Les user config and state roots doivent être des absolute paths. Les valeurs
relatives `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA` et
`LOCALAPPDATA` sont rejetées afin que les runtime files ne soient jamais créés
relativement au current directory.

Voir [memory.md](memory.md) pour les file formats et lifecycle.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Active le tool loop et les local tools. Définissez `off` pour désactiver tous les tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, de 256 bytes à 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | Active `list_dir` et `read_file`. Définissez `off` pour désactiver file reads. |
| `NLLCLW_FILE_WRITE` | `on` | Active `write_file` et `edit_file`. Définissez `off` pour désactiver file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | Active `cron_set`, `cron_list` et `cron_delete`. Définissez `off` pour désactiver scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

Les user-defined macro tools sont activés lorsque `NLLCLW_TOOLS=on`. Ils sont
stockés dans `NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` est désactivé tant qu'un search provider n'est pas configuré. Le
mode `auto` choisit le premier provider configuré dans cet ordre: Tavily, Brave
Search, Exa, Firecrawl, puis DuckDuckGo seulement lorsqu'il est explicitement
activé.
Si `NLLCLW_SEARCH_PROVIDER` est défini sur un key-based provider, la
`NLLCLW_SEARCH_*_KEY` correspondante doit aussi être définie.
Les search keys ne doivent pas contenir d'ASCII control bytes parce qu'elles
sont envoyées comme HTTP header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl` ou `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | Active le no-key DuckDuckGo Instant Answer fallback en mode `auto`. |

Optional shell build seulement:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | Active `shell_exec`, mais seulement dans un binary construit avec `-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout pour l'optional shell build. |

Le default binary rejette ces shell keys. Construisez avec `-Dshell-tool=true`
avant de les définir.

Voir [tools.md](tools.md) pour les détails.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token sous forme `<bot-id>:<secret>`; bot id doit être digits et le secret peut utiliser letters, digits, `-` et `_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username` ou le même username sans `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout en secondes. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages allowed per minute. Default `20`; `0` disables. |

Telegram refuse de démarrer sans chat allowlist. Après avoir configuré ces
clés, lancez `nllclw telegram` pour démarrer Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal à bind pour `nllclw websocket`. Loopback est le safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port pour le WebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. Doit commencer par `/`, être UTF-8 valide single-line et ne pas inclure spaces, `?` ou `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. Les loopback clients peuvent utiliser `?token=...`; les remote clients doivent utiliser `Authorization: Bearer ...`. Doit faire 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | Autorise les non-loopback bind addresses seulement lorsqu'il vaut `on`. |
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

Query-token authentication est loopback-only et accepte exactement un paramètre
`token`. Les remote clients doivent envoyer exactement un header
`Authorization: Bearer change-me`; les browser-based remote UIs doivent être
derrière un trusted local ou reverse proxy qui injecte ce header.
Le serveur intégré gère un active WebSocket client à la fois.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep entre les daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep entre les daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset utilisé par time/scheduler formatting. |

`NLLCLW_SCHEDULE_PATH` suit les mêmes local JSONL state-path rules que memory et
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

Atlas Cloud via le fournisseur compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Modèle local Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Fournisseur HTTPS compatible générique:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

Utilisez env pour des overrides ponctuels avec les mêmes noms de settings convertis en
`NLLCLW_*`; par exemple `model` devient `NLLCLW_MODEL`.
