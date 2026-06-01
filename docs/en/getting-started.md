# Getting Started

Install, configure, and run `nllclw`. For most users, start by downloading the
latest release binary instead of building from source.

## Requirements

- A `nllclw` release binary from
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest), or Zig
  `0.16.0` and Git if you are building from source.
- Provider access: a cloud API key, or a local OpenAI-compatible server such as
  Ollama.

While the repository is private, release downloads require access to
`nullclaw/nllclw`.

Official references:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## Install nllclw

Download the latest release asset for your OS and CPU, extract it, then check
the binary:

```sh
./nllclw --help
```

On macOS/Linux, make it executable first if needed:

```sh
chmod +x nllclw
```

## Build From Source

Skip this section when using a release binary. Source builds require Zig
`0.16.0`:

```sh
zig version
```

Detailed install paths for macOS, Linux, Windows, containers, CI, and ESP-IDF
host shells are in [installation.md](installation.md).

Clone and build:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Build the small release binary:

```sh
zig build --release=small
```

Check the binary:

```sh
./zig-out/bin/nllclw --help
```

Install it globally if you want:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

On platforms without `/usr/local/bin` or BSD/GNU `install`, copy
`zig-out/bin/nllclw` to any directory on your `PATH`.

## Configure a Provider

Run the wizard once. Use `./nllclw` instead if the binary is not on `PATH`:

```sh
nllclw init
```

The wizard uses numbered menus for provider, optional `max_tokens`, assistant
style, local capability profile, Telegram, WebSocket, and web search setup.
Press Enter to accept a menu default.

`nllclw` reads OS env first, `config.json` in the user config directory second,
and `.env` in the same directory third. OS env overrides file config, and
`config.json` overrides `.env`. For normal use, prefer the `config.json` created
by `nllclw init`; use OS env for one-off overrides or CI. Use
`nllclw init --env` only if you prefer the `.env` format.

Manual `config.json` examples:

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

Atlas Cloud through the compatible provider:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama local model:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

For local HTTP providers, only exact loopback hosts are allowed. `api_key` is
required by `nllclw`; Ollama accepts any non-empty value.

Full configuration reference: [configuration.md](configuration.md).

To remove files created by the wizard and runtime state:

```sh
nllclw uninstall
```

## Run

Direct prompt:

```sh
nllclw "summarize what this project does"
```

If you have not installed the binary globally:

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

Exit the chat loop with:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` is the default, but the default tool loop is non-streaming
because tool calls must be parsed before local functions run. For pure streaming
chat, disable tools:

```sh
NLLCLW_TOOLS=off
```

Disable streaming explicitly with:

```sh
NLLCLW_STREAM=off
```

## Persona

The default persona is neutral. Choose a startup style with:

```sh
NLLCLW_PERSONA=technical
```

Switch persona in direct CLI, REPL, or Telegram with:

```sh
nllclw /persona friendly
```

Supported modes are `neutral`, `friendly`, `technical`, and `witty`.

## Enable Memory

Transcript memory is on by default:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory is available through the default local tool loop:

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

Local tools that do not require external services are enabled by default:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Set any of those to `off` to disable a capability.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo can be used as a no-key Instant Answer fallback, but it is not a full
web results API:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Tool details and safety notes: [tools.md](tools.md) and [security.md](security.md).

Create reusable macro tools through the assistant:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Add optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files are summarized in the system prompt and loaded on demand with
`read_file`.

## Telegram

Create a bot with BotFather. If you enabled Telegram in `nllclw init`, start
polling immediately after the wizard writes the config:

```sh
nllclw telegram
```

For manual env configuration, set the bot token and one allowlisted chat. The
allowlist accepts either a numeric chat id, a private-chat username, or a public
chat username with or without `@`:

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

Telegram refuses to start without `NLLCLW_TELEGRAM_CHAT_ID`.
After startup, send `/chatid` in Telegram to see the numeric chat id and
available username fields.

Channel details: [channels.md](channels.md).

## WebSocket UI Channel

Start a loopback WebSocket server for a custom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

Send a JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds require an explicit token:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

For remote binds, authenticate with `Authorization: Bearer change-me`. Query
tokens are accepted only on loopback binds.

WebSocket protocol details: [channels.md](channels.md).

## Heartbeat and Daemon

Run one heartbeat pass from `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

Run due schedules and heartbeat tasks repeatedly:

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

Run the standard checks:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
