# Memulai

Instal, konfigurasi, dan jalankan `nllclw`. Untuk sebagian besar pengguna,
langkah pertama adalah mengunduh release binary terbaru, bukan build dari source.

## Persyaratan

- Release binary `nllclw` dari
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest), atau Zig
  `0.16.0` dan Git jika Anda build dari source.
- Provider access: cloud API key, atau server lokal OpenAI-compatible seperti
  Ollama.

Selama repository private, release downloads memerlukan access ke
`nullclaw/nllclw`.

Referensi resmi:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## Instal nllclw

Unduh release asset terbaru untuk OS dan CPU Anda, extract, lalu cek binary:

```sh
./nllclw --help
```

Di macOS/Linux, buat executable terlebih dahulu jika perlu:

```sh
chmod +x nllclw
```

## Build dari source

Lewati section ini jika memakai release binary. Source build memerlukan Zig
`0.16.0`:

```sh
zig version
```

Path instalasi detail untuk macOS, Linux, Windows, containers, CI, dan shell host
ESP-IDF ada di [installation.md](installation.md).

Clone dan build:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Build release binary kecil:

```sh
zig build --release=small
```

Cek binary:

```sh
./zig-out/bin/nllclw --help
```

Instal secara global jika Anda mau:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

Di platform tanpa `/usr/local/bin` atau BSD/GNU `install`, copy
`zig-out/bin/nllclw` ke directory mana pun di `PATH` Anda.

## Konfigurasi provider

Jalankan wizard sekali:

```sh
nllclw init
```

Wizard memakai numbered menus untuk provider, optional `max_tokens`, assistant
style, local capability profile, Telegram, WebSocket, dan setup web search.
Tekan Enter untuk menerima menu default.

`nllclw` membaca OS env lebih dulu, `config.json` di user config directory
kedua, dan `.env` di directory yang sama ketiga. OS env override file config, dan
`config.json` override `.env`. Untuk penggunaan normal, prioritaskan
`config.json` yang dibuat oleh `nllclw init`; gunakan OS env untuk override
sekali pakai atau CI. Gunakan `nllclw init --env` hanya jika Anda memilih format
`.env`.

Contoh manual `config.json`:

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

Untuk provider HTTP lokal, hanya host loopback exact yang diizinkan. `api_key`
diperlukan oleh `nllclw`; Ollama menerima nilai non-empty apa pun.

Referensi konfigurasi lengkap: [configuration.md](configuration.md).

Untuk menghapus file yang dibuat wizard dan runtime state:

```sh
nllclw uninstall
```

## Run

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Jika binary belum diinstall global:

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

Prompt from stdin:

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat:

```sh
nllclw
```

Keluar dari chat loop dengan:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` adalah default, tetapi default tool loop bersifat
non-streaming karena tool calls harus di-parse sebelum local functions berjalan.
Untuk pure streaming chat, nonaktifkan tools:

```sh
NLLCLW_TOOLS=off
```

Nonaktifkan streaming secara eksplisit dengan:

```sh
NLLCLW_STREAM=off
```

## Persona

Persona default adalah neutral. Pilih startup style dengan:

```sh
NLLCLW_PERSONA=technical
```

Ganti persona di direct CLI, REPL, atau Telegram dengan:

```sh
nllclw /persona friendly
```

Mode yang didukung adalah `neutral`, `friendly`, `technical`, dan `witty`.

## Aktifkan memory

Transcript memory aktif secara default:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory tersedia melalui default local tool loop:

```sh
NLLCLW_MEMORY=on
```

Inspeksi local facts:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Detail memory: [memory.md](memory.md).

## Tools

Local tools yang tidak memerlukan external services aktif secara default:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Set salah satunya ke `off` untuk menonaktifkan capability.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo dapat digunakan sebagai no-key Instant Answer fallback, tetapi bukan
full web results API:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Detail tools dan catatan keamanan: [tools.md](tools.md) dan
[security.md](security.md).

Buat reusable macro tools melalui assistant:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Tambahkan optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files diringkas di system prompt dan dimuat on demand dengan `read_file`.

## Telegram

Buat bot dengan BotFather. Jika Anda mengaktifkan Telegram di `nllclw init`,
mulai polling segera setelah wizard menulis config:

```sh
nllclw telegram
```

Untuk konfigurasi env manual, set bot token dan satu chat allowlisted. Allowlist
menerima numeric chat id, private-chat username, atau public chat username
dengan atau tanpa `@`:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Contoh username allowlist:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

Telegram menolak start tanpa `NLLCLW_TELEGRAM_CHAT_ID`.
Setelah startup, kirim `/chatid` di Telegram untuk melihat numeric chat id dan
available username fields.

Detail channel: [channels.md](channels.md).

## WebSocket UI Channel

Mulai loopback WebSocket server untuk custom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

Kirim JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds memerlukan token eksplisit:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Untuk remote binds, autentikasi dengan `Authorization: Bearer change-me`. Query
tokens hanya diterima pada loopback binds.

Detail protocol WebSocket: [channels.md](channels.md).

## Heartbeat dan Daemon

Jalankan satu heartbeat pass dari `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

Jalankan due schedules dan heartbeat tasks berulang:

```sh
nllclw daemon
```

Settings berguna:

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Verifikasi repositori

Jalankan checks standar:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
