# Getting Started

`nllclw` をインストール、設定、実行します。ほとんどのユーザーは、source から
build するのではなく、最新の release binary をダウンロードするところから始めます。

## 要件

- [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest) の
  `nllclw` release binary、または source から build する場合は Zig `0.16.0` と Git。
- Provider access: cloud API key、または Ollama のような local OpenAI-compatible
  server。

Repository が private の間、release downloads には `nullclaw/nllclw` への
access が必要です。

Official references:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## nllclw をインストールする

OS と CPU に合う最新の release asset をダウンロードして展開し、binary を確認します:

```sh
./nllclw --help
```

macOS/Linux では、必要なら先に executable にします:

```sh
chmod +x nllclw
```

## Source から build する

Release binary を使う場合、この section はスキップします。Source builds には Zig
`0.16.0` が必要です:

```sh
zig version
```

macOS、Linux、Windows、containers、CI、ESP-IDF host shells の詳細な install paths は
[installation.md](installation.md) にあります。

Clone して build します:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

小さい release binary を build します:

```sh
zig build --release=small
```

Binary を確認します:

```sh
./zig-out/bin/nllclw --help
```

必要なら globally install します:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

`/usr/local/bin` または BSD/GNU `install` がない platforms では、
`zig-out/bin/nllclw` を `PATH` 上の任意の directory に copy します。

## Configure a Provider

Wizard を一度実行します:

```sh
nllclw init
```

Wizard は provider、optional `max_tokens`、assistant style、local capability profile、
Telegram、WebSocket、web search setup に numbered menus を使います。Menu default を
accept するには Enter を押します。

`nllclw` はまず OS env、次に user config directory の `config.json`、最後に同じ
directory の `.env` を読みます。OS env は file config を override し、`config.json`
は `.env` を override します。通常の使用では `nllclw init` が作る `config.json` を
優先し、one-off overrides や CI には OS env を使います。`.env` format を好む場合だけ
`nllclw init --env` を使います。

手動の `config.json` 例:

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

Compatible provider 経由の Atlas Cloud:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama の local model:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Local HTTP providers では exact loopback hosts だけが allowed です。`api_key` は
`nllclw` で required です。Ollama は任意の non-empty value を accept します。

完全な configuration reference: [configuration.md](configuration.md)。

Wizard と runtime state が作成した files を remove するには:

```sh
nllclw uninstall
```

## Run

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Binary を globally installed していない場合:

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

stdin から prompt:

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat:

```sh
nllclw
```

Chat loop を exit:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` が default ですが、default tool loop は non-streaming です。
Tool calls は local functions が run する前に parsed される必要があるためです。
Pure streaming chat では tools を disable します:

```sh
NLLCLW_TOOLS=off
```

Streaming を explicitly disable:

```sh
NLLCLW_STREAM=off
```

## Persona

Default persona は neutral です。Startup style を選びます:

```sh
NLLCLW_PERSONA=technical
```

Direct CLI、REPL、Telegram で persona を switch:

```sh
nllclw /persona friendly
```

Supported modes は `neutral`、`friendly`、`technical`、`witty` です。

## Enable Memory

Transcript memory は default で on です:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory は default local tool loop で available です:

```sh
NLLCLW_MEMORY=on
```

Local facts を inspect:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Memory details: [memory.md](memory.md)。

## Tools

External services を必要としない local tools は default で enabled です:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Capability を disable するには、それを `off` に set します。

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo は no-key Instant Answer fallback として使えますが、full web results API ではありません:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Tool details と safety notes: [tools.md](tools.md) と [security.md](security.md)。

Assistant を通じて reusable macro tools を作成します:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Optional local skills を追加します:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files は system prompt に summarized され、必要に応じて `read_file` で loaded されます。

## Telegram

BotFather で bot を作成します。`nllclw init` で Telegram を enable した場合、
wizard が config を書いた直後に polling を start します:

```sh
nllclw telegram
```

Manual env configuration では、bot token と one allowlisted chat を set します。
Allowlist は numeric chat id、private-chat username、または `@` 付き/なしの public
chat username を accept します:

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

Telegram は `NLLCLW_TELEGRAM_CHAT_ID` なしでは start を拒否します。
Startup 後、numeric chat id と available username fields を見るには Telegram で
`/chatid` を送ります。

Channel details: [channels.md](channels.md)。

## WebSocket UI Channel

Custom UI のために loopback WebSocket server を start します:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

JSON text frame を送ります:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds は explicit token を require します:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Remote binds では `Authorization: Bearer change-me` で authenticate します。
Query tokens は loopback binds でだけ accepted です。

WebSocket protocol details: [channels.md](channels.md)。

## Heartbeat and Daemon

`HEARTBEAT.md` から 1 回の heartbeat pass を run:

```sh
nllclw heartbeat
```

Due schedules と heartbeat tasks を繰り返し run:

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

Standard checks を run:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
