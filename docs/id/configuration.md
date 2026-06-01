# Konfigurasi

`nllclw` dikonfigurasi oleh OS environment variables terlebih dahulu,
`config.json` kedua, dan `.env` ketiga. OS env selalu menang. Tidak ada
provider, API key, atau model default.

Untuk setup jangka panjang biasa, prioritaskan `config.json`, biasanya dibuat
oleh `nllclw init`. OS env berada pertama agar shell, service manager, atau job
CI dapat override file config tanpa mengeditnya. `.env` adalah alternatif dengan
prioritas lebih rendah untuk pengguna yang memilih format itu.

## Urutan sumber

```mermaid
flowchart LR
    Env["OS environment"] --> Merge
    ConfigJson["user config dir/config.json"] --> Merge["merge"]
    Dotenv["user config dir/.env"] --> Merge
    Merge --> Validate["typed validation"]
    Validate --> RuntimeConfig["RuntimeConfig"]
```

Jika setting yang sama ada di beberapa sumber, sumber pertama dalam urutan ini
menang: OS env, lalu `config.json`, lalu `.env`.

`nllclw uninstall` menghapus direktori konfigurasi dan state pengguna `nllclw`.

## Format `config.json`

Jalankan `nllclw init` untuk membuat `config.json`. File berada di user config
directory, bukan di sebelah binary atau di project saat ini:

- `$XDG_CONFIG_HOME/nllclw/config.json` saat `XDG_CONFIG_HOME` diset
- jika tidak, `$HOME/.config/nllclw/config.json`
- di Windows, `%APPDATA%\nllclw\config.json` saat `APPDATA` diset

`config.json` adalah JSON object datar. Gunakan settings yang sama seperti key
environment `NLLCLW_*`, tetapi hapus `NLLCLW_` dan tulis nama dalam lowercase
snake_case. Contoh, `NLLCLW_API_KEY` menjadi `api_key`.

Aturan:

- top-level JSON value harus object
- unknown keys ditolak
- string values diterima untuk setiap setting
- integer values hanya diterima untuk integer settings
- boolean values hanya diterima untuk boolean settings dan dipetakan ke
  `on`/`off`
- arrays, nested objects, floats, dan `null` ditolak
- `config.json` dibatasi 16 KiB

Contoh:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

## Format `.env`

Jalankan `nllclw init --env` untuk membuat `.env` global di user config
directory yang sama. Jika `config.json` sudah ada, `init --env` berhenti karena
`config.json` memiliki prioritas lebih tinggi dan akan shadow `.env`. Parser
menerima:

- `KEY=VALUE`
- leading and trailing whitespace is trimmed
- blank lines are ignored
- lines starting with `#` are ignored
- duplicate keys use last value wins inside the same `.env`
- unknown `NLLCLW_*` keys are rejected
- `.env` is capped at 16 KiB
- quoting and interpolation are not supported

Contoh:

```sh
NLLCLW_PROVIDER=openrouter
NLLCLW_API_KEY=sk-or-...
NLLCLW_MODEL=openai/gpt-chat-latest
```

## Completion keys wajib

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_PROVIDER` | yes | `openai`, `openrouter`, atau `compatible`. |
| `NLLCLW_API_KEY` | yes | Bearer token yang dikirim sebagai `Authorization: Bearer ...`. |
| `NLLCLW_MODEL` | yes | Provider model name. |
| `NLLCLW_BASE_URL` | only for `compatible` | Base URL seperti `https://example.com/v1`. |

Optional completion keys:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MAX_TOKENS` | unset | Optional positive integer output cap yang diteruskan sebagai Chat Completions `max_tokens`. |
| `NLLCLW_HTTP_REFERER` | unset | Optional OpenRouter `HTTP-Referer` header. |
| `NLLCLW_APP_TITLE` | unset | Optional OpenRouter `X-OpenRouter-Title` header. |
| `NLLCLW_ALLOW_HTTP_BASE_URL` | `off` | Mengizinkan `http://localhost`, `http://127.0.0.1`, atau `http://[::1]` untuk compatible local servers. |
| `NLLCLW_PERSONA` | `neutral` | Runtime presentation mode: `neutral`, `friendly`, `technical`, atau `witty`. |
| `NLLCLW_STREAM` | `on` | Streams direct completions. Tool mode bersifat non-streaming. |

`NLLCLW_MODEL` harus single-line valid UTF-8 text. Provider header values tidak
boleh mengandung ASCII control bytes.

## Resolusi provider

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

Semua provider memakai request shape minimal yang sama:

```json
{
  "model": "provider/model",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

Saat tools aktif, `tools` dan `tool_choice: "auto"` ditambahkan. Saat direct
streaming aktif, `stream: true` ditambahkan.

## Aturan URL Compatible Provider

`NLLCLW_BASE_URL`:

- harus parse sebagai URL;
- harus memiliki host;
- tidak boleh menyertakan userinfo, query string, atau fragment;
- harus memakai `https://` secara default;
- boleh memakai `http://` hanya untuk exact loopback hosts saat
  `NLLCLW_ALLOW_HTTP_BASE_URL=on`;
- trailing slashes dihapus sebelum `/chat/completions` ditambahkan.

Contoh HTTP lokal yang diterima:

```json
{
  "provider": "compatible",
  "base_url": "http://localhost:11434/v1",
  "allow_http_base_url": true,
  "api_key": "local",
  "model": "local-model"
}
```

Contoh yang ditolak:

- `http://example.com/v1`
- `https://user:pass@example.com/v1`
- `https://example.com/v1?debug=true`

## Memory Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_MEMORY` | `on` | Mengaktifkan transcript memory dan durable fact tools. |
| `NLLCLW_MEMORY_PATH` | user state dir `memory.jsonl` | Transcript JSONL path. |
| `NLLCLW_MEMORY_MAX_MESSAGES` | `20` | Maksimum recent transcript entries yang dikirim ke model. Harus minimal 2. |
| `NLLCLW_MEMORY_FACTS_PATH` | user state dir `facts.jsonl` | Durable keyed fact JSONL path. |
| `NLLCLW_MEMORY_MAX_FACTS` | `64` | Maksimum retained fact entries. |

Configured state file paths adalah JSONL subpaths di bawah user state directory.
Path harus relative, valid UTF-8, control-free, maksimal 512 bytes, tidak boleh
berisi path components `.` atau `..`, harus memakai separator `/` tanpa empty
path components, tidak boleh mengandung Windows-reserved filename characters,
dan harus berakhir dengan `.jsonl`. Components yang berakhir dengan space atau
dot juga ditolak untuk portable behavior. Windows device names seperti `CON`,
`NUL`, `CONIN$`, `CONOUT$`, `COM1`, dan `LPT1` ditolak walau memiliki
extension. Parent directories dibuat saat write pertama.

Default state files berada di bawah user state directory:

- `$XDG_STATE_HOME/nllclw` saat `XDG_STATE_HOME` diset
- jika tidak, `$HOME/.local/state/nllclw`
- di Windows, `%LOCALAPPDATA%\nllclw` saat `LOCALAPPDATA` diset

User config and state roots harus absolute paths. Nilai relative `HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `APPDATA`, dan `LOCALAPPDATA` ditolak agar
runtime files tidak pernah dibuat relatif terhadap current directory.

Lihat [memory.md](memory.md) untuk file formats dan lifecycle.

## Tool Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_TOOLS` | `on` | Mengaktifkan tool loop dan local tools. Set `off` untuk menonaktifkan semua tools. |
| `NLLCLW_TOOL_MAX_ROUNDS` | `4` | Maximum assistant/tool exchange rounds. |
| `NLLCLW_TOOL_OUTPUT_MAX_BYTES` | `8192` | Per-tool output cap, 256 bytes hingga 1 MiB. |
| `NLLCLW_FILE_READ` | `on` | Mengaktifkan `list_dir` dan `read_file`. Set `off` untuk menonaktifkan file reads. |
| `NLLCLW_FILE_WRITE` | `on` | Mengaktifkan `write_file` dan `edit_file`. Set `off` untuk menonaktifkan file writes. |
| `NLLCLW_SCHEDULE_TOOLS` | `on` | Mengaktifkan `cron_set`, `cron_list`, dan `cron_delete`. Set `off` untuk menonaktifkan scheduler tools. |
| `NLLCLW_USER_TOOLS_PATH` | user state dir `user-tools.jsonl` | Persistent user-defined macro tool JSONL path. |

User-defined macro tools aktif kapan pun `NLLCLW_TOOLS=on`. Tools ini disimpan
di `NLLCLW_USER_TOOLS_PATH`.

## Search Keys

`web_search` nonaktif hingga satu search provider dikonfigurasi. Mode `auto`
memilih provider terkonfigurasi pertama dalam urutan ini: Tavily, Brave Search,
Exa, Firecrawl, lalu DuckDuckGo hanya saat diaktifkan eksplisit.
Jika `NLLCLW_SEARCH_PROVIDER` diset ke key-based provider, maka
`NLLCLW_SEARCH_*_KEY` yang cocok juga harus diset.
Search keys tidak boleh mengandung ASCII control bytes karena dikirim sebagai
HTTP header values.

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SEARCH_PROVIDER` | `auto` | `auto`, `tavily`, `brave`, `exa`, `firecrawl`, atau `duckduckgo`. |
| `NLLCLW_SEARCH_TAVILY_KEY` | unset | Tavily Search API key. |
| `NLLCLW_SEARCH_BRAVE_KEY` | unset | Brave Search API key. |
| `NLLCLW_SEARCH_EXA_KEY` | unset | Exa API key. |
| `NLLCLW_SEARCH_FIRECRAWL_KEY` | unset | Firecrawl API key. |
| `NLLCLW_SEARCH_DUCKDUCKGO` | `off` | Mengaktifkan no-key DuckDuckGo Instant Answer fallback dalam mode `auto`. |

Hanya optional shell build:

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SHELL` | `off` | Mengaktifkan `shell_exec`, tetapi hanya di binary yang dibangun dengan `-Dshell-tool=true`. |
| `NLLCLW_TOOL_TIMEOUT_MS` | `5000` | Shell command timeout untuk optional shell build. |

Default binary menolak shell keys ini. Build dengan `-Dshell-tool=true` sebelum
menyetelnya.

Lihat [tools.md](tools.md) untuk detail.

## Telegram Keys

| Key | Required | Description |
|---|---:|---|
| `NLLCLW_TELEGRAM_TOKEN` | yes for `nllclw telegram` | Telegram Bot API token dalam bentuk `<bot-id>:<secret>`; bot id harus digits dan secret dapat memakai letters, digits, `-`, dan `_`. |
| `NLLCLW_TELEGRAM_CHAT_ID` | yes for `nllclw telegram` | Required allowlist: non-zero numeric chat id, private-chat `@username`, public-chat `@username`, atau username yang sama tanpa `@`. |
| `NLLCLW_TELEGRAM_POLL_TIMEOUT` | no | Long-poll timeout dalam detik. Default `20`. |
| `NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE` | no | Model-backed Telegram messages allowed per minute. Default `20`; `0` disables. |

Telegram menolak start tanpa chat allowlist. Setelah key ini dikonfigurasi,
jalankan `nllclw telegram` untuk memulai Bot API long polling.

## WebSocket Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_WS_HOST` | `127.0.0.1` | IP literal untuk bind `nllclw websocket`. Loopback adalah safe default. |
| `NLLCLW_WS_PORT` | `8765` | TCP port untuk WebSocket server. |
| `NLLCLW_WS_PATH` | `/ws` | HTTP upgrade path. Harus mulai dengan `/`, single-line valid UTF-8, dan tidak boleh menyertakan spaces, `?`, atau `#`. |
| `NLLCLW_WS_TOKEN` | yes for `nllclw websocket` | Required WebSocket token. Loopback clients dapat memakai `?token=...`; remote clients harus memakai `Authorization: Bearer ...`. Harus 8-256 URL-safe ASCII characters. |
| `NLLCLW_WS_ALLOW_REMOTE` | `off` | Mengizinkan non-loopback bind addresses hanya saat diset `on`. |
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

Query-token authentication hanya loopback dan menerima tepat satu parameter
`token`. Remote clients harus mengirim tepat satu header
`Authorization: Bearer change-me`; browser-based remote UIs harus berada di
belakang trusted local atau reverse proxy yang menginjeksikan header tersebut.
Server bawaan menangani satu active WebSocket client pada satu waktu.

## Scheduler and Heartbeat Keys

| Key | Default | Description |
|---|---:|---|
| `NLLCLW_SCHEDULE_PATH` | user state dir `schedule.jsonl` | Durable schedule file. |
| `NLLCLW_DAEMON_INTERVAL_SECONDS` | `60` | Sleep antara daemon polling passes. |
| `NLLCLW_HEARTBEAT_INTERVAL_SECONDS` | `1800` | Sleep antara daemon heartbeat passes. |
| `NLLCLW_TIMEZONE_OFFSET_MINUTES` | `0` | Offset yang digunakan oleh time/scheduler formatting. |

`NLLCLW_SCHEDULE_PATH` mengikuti local JSONL state-path rules yang sama seperti
memory dan user-defined macro tools.

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

Atlas Cloud melalui provider compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Model lokal Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Provider HTTPS compatible generik:

```json
{
  "provider": "compatible",
  "base_url": "https://example.com/v1",
  "api_key": "...",
  "model": "..."
}
```

Gunakan env untuk override sekali pakai dengan nama setting yang sama dikonversi ke
`NLLCLW_*`; misalnya `model` menjadi `NLLCLW_MODEL`.
