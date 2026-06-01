# Getting Started

قم بتثبيت `nllclw` وضبطه وتشغيله. بالنسبة لمعظم المستخدمين، ابدأ بتنزيل
أحدث release binary بدلاً من البناء من source.

## المتطلبات

- Release binary لـ `nllclw` من
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest)، أو Zig
  `0.16.0` وGit إذا كنت تبني من source.
- Provider access: مفتاح cloud API، أو local OpenAI-compatible server مثل
  Ollama.

ما دام repository خاصاً، تتطلب downloads من releases صلاحية وصول إلى
`nullclaw/nllclw`.

المراجع الرسمية:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## تثبيت nllclw

نزّل أحدث release asset المناسب للـ OS والـ CPU لديك، واستخرجه، ثم تحقق من
binary:

```sh
./nllclw --help
```

على macOS/Linux، اجعله executable أولاً إذا لزم الأمر:

```sh
chmod +x nllclw
```

## البناء من source

تجاوز هذا القسم عند استخدام release binary. تتطلب source builds Zig `0.16.0`:

```sh
zig version
```

مسارات التثبيت التفصيلية لـ macOS وLinux وWindows وcontainers وCI وESP-IDF host
shells موجودة في [installation.md](installation.md).

Clone وbuild:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Build release binary صغير:

```sh
zig build --release=small
```

تحقق من binary:

```sh
./zig-out/bin/nllclw --help
```

ثبّته globally إذا أردت:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

على platforms بلا `/usr/local/bin` أو BSD/GNU `install`، انسخ
`zig-out/bin/nllclw` إلى أي directory ضمن `PATH`.

## Configure a Provider

شغّل wizard مرة واحدة:

```sh
nllclw init
```

يستخدم wizard numbered menus للprovider وoptional `max_tokens` وassistant style وlocal
capability profile وTelegram وWebSocket وweb search setup. اضغط Enter لقبول menu default.

`nllclw` يقرأ OS env أولاً، ثم `config.json` في user config directory، ثم
`.env` في نفس directory. يتجاوز OS env file config، ويتجاوز `config.json` ملف
`.env`. للاستخدام العادي، فضّل `config.json` الذي ينشئه `nllclw init`؛ استخدم
OS env للـ one-off overrides أو CI. استخدم `nllclw init --env` فقط إذا كنت تفضّل
format `.env`.

أمثلة `config.json` يدوية:

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

لـ local HTTP providers، لا يُسمح إلا بloopback hosts المطابقة تماماً. `api_key`
مطلوب من `nllclw`؛ يقبل Ollama أي قيمة غير فارغة.

مرجع configuration الكامل: [configuration.md](configuration.md).

لإزالة الملفات التي أنشأها wizard وruntime state:

```sh
nllclw uninstall
```

## Run

Direct prompt:

```sh
nllclw "summarize what this project does"
```

إذا لم تكن قد ثبتت binary globally:

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

Prompt من stdin:

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat:

```sh
nllclw
```

اخرج من chat loop عبر:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` هو default، لكن default tool loop non-streaming لأن tool calls
يجب أن تُparse قبل تشغيل local functions. لpure streaming chat، عطّل tools:

```sh
NLLCLW_TOOLS=off
```

عطّل streaming صراحة:

```sh
NLLCLW_STREAM=off
```

## Persona

Default persona هي neutral. اختر startup style عبر:

```sh
NLLCLW_PERSONA=technical
```

بدّل persona في direct CLI أو REPL أو Telegram عبر:

```sh
nllclw /persona friendly
```

Supported modes هي `neutral` و`friendly` و`technical` و`witty`.

## Enable Memory

Transcript memory on افتراضياً:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory available عبر default local tool loop:

```sh
NLLCLW_MEMORY=on
```

Inspect local facts:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Memory details: [memory.md](memory.md).

## Tools

Local tools التي لا تحتاج external services مفعّلة افتراضياً:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

اضبط أي منها إلى `off` لتعطيل capability.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

يمكن استخدام DuckDuckGo كno-key Instant Answer fallback، لكنه ليس full web results API:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Tool details وsafety notes: [tools.md](tools.md) و[security.md](security.md).

أنشئ reusable macro tools عبر assistant:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

أضف optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

تُلخص skill files في system prompt وتُحمّل عند الطلب ب`read_file`.

## Telegram

أنشئ bot عبر BotFather. إذا فعّلت Telegram في `nllclw init`، ابدأ polling فوراً
بعد أن يكتب wizard config:

```sh
nllclw telegram
```

لmanual env configuration، اضبط bot token وone allowlisted chat. تقبل allowlist
numeric chat id أو private-chat username أو public chat username مع `@` أو بدونه:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Username allowlist example:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

يرفض Telegram البدء بلا `NLLCLW_TELEGRAM_CHAT_ID`.
بعد startup، أرسل `/chatid` في Telegram لرؤية numeric chat id وavailable username fields.

Channel details: [channels.md](channels.md).

## WebSocket UI Channel

ابدأ loopback WebSocket server لcustom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

أرسل JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds تتطلب explicit token:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

بالنسبة لremote binds، authenticate باستخدام `Authorization: Bearer change-me`.
Query tokens مقبولة فقط على loopback binds.

WebSocket protocol details: [channels.md](channels.md).

## Heartbeat and Daemon

شغّل heartbeat pass واحداً من `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

شغّل due schedules وheartbeat tasks مراراً:

```sh
nllclw daemon
```

Useful settings:

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Verify the Repository

شغّل standard checks:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
