# Getting Started

`nllclw` install, configure এবং run করুন। বেশিরভাগ users-এর জন্য source থেকে
build না করে latest release binary download করাই প্রথম ধাপ।

## প্রয়োজনীয়তা

- [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest) থেকে
  `nllclw` release binary, অথবা source থেকে build করলে Zig `0.16.0` এবং Git।
- Provider access: cloud API key, অথবা Ollama-এর মতো local OpenAI-compatible
  server।

Repository private থাকা অবস্থায় release downloads-এর জন্য `nullclaw/nllclw`
access দরকার।

Official references:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## nllclw install

আপনার OS এবং CPU-এর latest release asset download করে extract করুন, তারপর binary
check করুন:

```sh
./nllclw --help
```

macOS/Linux-এ দরকার হলে আগে executable করুন:

```sh
chmod +x nllclw
```

## Source থেকে build

Release binary ব্যবহার করলে এই section skip করুন। Source builds-এর জন্য Zig
`0.16.0` দরকার:

```sh
zig version
```

macOS, Linux, Windows, containers, CI এবং ESP-IDF host shells-এর বিস্তারিত install
paths [installation.md](installation.md)-এ আছে।

Clone এবং build:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Small release binary build করুন:

```sh
zig build --release=small
```

Binary check করুন:

```sh
./zig-out/bin/nllclw --help
```

চাইলে globally install করুন:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

`/usr/local/bin` বা BSD/GNU `install` না থাকা platforms-এ `zig-out/bin/nllclw`
আপনার `PATH`-এর যেকোনো directory-তে copy করুন।

## Configure a Provider

Wizard একবার চালান:

```sh
nllclw init
```

Wizard provider, optional `max_tokens`, assistant style, local capability profile,
Telegram, WebSocket, এবং web search setup-এর জন্য numbered menus ব্যবহার করে।
Menu default accept করতে Enter চাপুন।

`nllclw` প্রথমে OS env, তারপর user config directory-র `config.json`, তারপর একই
directory-র `.env` পড়ে। OS env file config override করে, আর `config.json` `.env`
override করে। সাধারণ ব্যবহারে `nllclw init` তৈরি করা `config.json` prefer করুন;
one-off overrides বা CI-র জন্য OS env ব্যবহার করুন। `.env` format prefer করলেই
শুধু `nllclw init --env` ব্যবহার করুন।

Manual `config.json` উদাহরণ:

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

Local HTTP providers-এর জন্য শুধু exact loopback hosts allowed। `api_key`
`nllclw`-এর required; Ollama যেকোনো non-empty value accept করে।

সম্পূর্ণ configuration reference: [configuration.md](configuration.md)।

Wizard-created files এবং runtime state remove করতে:

```sh
nllclw uninstall
```

## Run

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Binary globally installed না থাকলে:

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

stdin থেকে prompt:

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat:

```sh
nllclw
```

Chat loop থেকে exit:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` default, কিন্তু default tool loop non-streaming কারণ local
functions run করার আগে tool calls parse হতে হবে। Pure streaming chat-এর জন্য tools disable করুন:

```sh
NLLCLW_TOOLS=off
```

Streaming explicitly disable:

```sh
NLLCLW_STREAM=off
```

## Persona

Default persona neutral। Startup style বেছে নিন:

```sh
NLLCLW_PERSONA=technical
```

Direct CLI, REPL, বা Telegram-এ persona switch:

```sh
nllclw /persona friendly
```

Supported modes `neutral`, `friendly`, `technical`, এবং `witty`।

## Enable Memory

Transcript memory defaultভাবে on:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory default local tool loop দিয়ে available:

```sh
NLLCLW_MEMORY=on
```

Local facts inspect:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Memory details: [memory.md](memory.md)।

## Tools

External services দরকার নেই এমন local tools defaultভাবে enabled:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

কোনো capability disable করতে সেটি `off` set করুন।

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo no-key Instant Answer fallback হিসেবে ব্যবহার করা যায়, কিন্তু এটি full
web results API নয়:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Tool details এবং safety notes: [tools.md](tools.md) এবং [security.md](security.md)।

Assistant দিয়ে reusable macro tools তৈরি করুন:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Optional local skills যোগ করুন:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files system prompt-এ summarized হয় এবং demand অনুযায়ী `read_file` দিয়ে loaded হয়।

## Telegram

BotFather দিয়ে bot তৈরি করুন। `nllclw init`-এ Telegram enable করলে wizard config
লেখার সঙ্গে সঙ্গে polling start করুন:

```sh
nllclw telegram
```

Manual env configuration-এর জন্য bot token এবং one allowlisted chat set করুন।
Allowlist numeric chat id, private-chat username, বা `@` সহ বা ছাড়া public chat
username accept করে:

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

`NLLCLW_TELEGRAM_CHAT_ID` ছাড়া Telegram start করতে অস্বীকার করে।
Startup-এর পরে numeric chat id এবং available username fields দেখতে Telegram-এ
`/chatid` পাঠান।

Channel details: [channels.md](channels.md)।

## WebSocket UI Channel

Custom UI-এর জন্য loopback WebSocket server start করুন:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

JSON text frame পাঠান:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds explicit token require করে:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Remote binds-এর জন্য `Authorization: Bearer change-me` দিয়ে authenticate করুন।
Query tokens শুধু loopback binds-এ accepted।

WebSocket protocol details: [channels.md](channels.md)।

## Heartbeat and Daemon

`HEARTBEAT.md` থেকে একটি heartbeat pass চালান:

```sh
nllclw heartbeat
```

Due schedules এবং heartbeat tasks repeatedly চালান:

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

Standard checks চালান:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
