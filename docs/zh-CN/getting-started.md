# Getting Started

安装、配置并运行 `nllclw`。对大多数用户来说，第一步是下载最新 release
binary，而不是从 source 构建。

## 要求

- 来自 [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest) 的
  `nllclw` release binary；如果从 source 构建，则需要 Zig `0.16.0` 和 Git。
- Provider access：cloud API key，或像 Ollama 这样的 local OpenAI-compatible
  server。

Repository 保持 private 时，release downloads 需要 `nullclaw/nllclw` access。

Official references：

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## 安装 nllclw

下载适合你的 OS 和 CPU 的最新 release asset，解压，然后检查 binary：

```sh
./nllclw --help
```

在 macOS/Linux 上，如果需要，先将其设为 executable：

```sh
chmod +x nllclw
```

## 从 source 构建

使用 release binary 时跳过本节。Source builds 需要 Zig `0.16.0`：

```sh
zig version
```

macOS、Linux、Windows、containers、CI 和 ESP-IDF host shells 的详细安装路径在
[installation.md](installation.md) 中。

Clone 并 build：

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Build 小型 release binary：

```sh
zig build --release=small
```

检查 binary：

```sh
./zig-out/bin/nllclw --help
```

如果需要，可以全局安装：

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

在没有 `/usr/local/bin` 或 BSD/GNU `install` 的 platforms 上，把
`zig-out/bin/nllclw` copy 到 `PATH` 中任意 directory。

## Configure a Provider

运行一次 wizard：

```sh
nllclw init
```

Wizard 使用 numbered menus 配置 provider、optional `max_tokens`、assistant
style、local capability profile、Telegram、WebSocket 和 web search。按 Enter
接受菜单默认值。

`nllclw` 先读取 OS env，其次读取 user config directory 中的 `config.json`，最后读取
同一 directory 中的 `.env`。OS env 会 override file config，`config.json` 会 override
`.env`。常规使用时，优先使用 `nllclw init` 创建的 `config.json`；one-off overrides
或 CI 再使用 OS env。只有在偏好 `.env` format 时才使用 `nllclw init --env`。

手动 `config.json` 示例：

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

通过 compatible provider 使用 Atlas Cloud：

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama 本地模型：

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

对于 local HTTP providers，只允许 exact loopback hosts。`api_key` 是 `nllclw`
必需的；Ollama 接受任何 non-empty value。

完整配置参考：[configuration.md](configuration.md)。

删除 wizard 创建的文件和 runtime state：

```sh
nllclw uninstall
```

## Run

Direct prompt：

```sh
nllclw "summarize what this project does"
```

如果没有全局安装 binary：

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

从 stdin 提供 prompt：

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat：

```sh
nllclw
```

使用以下命令退出 chat loop：

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` 是默认值，但默认 tool loop 是 non-streaming，因为 tool
calls 必须先被解析，local functions 才能运行。纯 streaming chat 可禁用 tools：

```sh
NLLCLW_TOOLS=off
```

显式禁用 streaming：

```sh
NLLCLW_STREAM=off
```

## Persona

Default persona 是 neutral。通过以下设置选择 startup style：

```sh
NLLCLW_PERSONA=technical
```

在 direct CLI、REPL 或 Telegram 中切换 persona：

```sh
nllclw /persona friendly
```

Supported modes 是 `neutral`、`friendly`、`technical` 和 `witty`。

## Enable Memory

Transcript memory 默认开启：

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory 可通过默认 local tool loop 使用：

```sh
NLLCLW_MEMORY=on
```

Inspect local facts：

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Memory details：[memory.md](memory.md)。

## Tools

不需要 external services 的 local tools 默认启用：

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

将其中任意项设置为 `off` 可禁用对应 capability。

Web search：

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo 可作为 no-key Instant Answer fallback 使用，但它不是完整的 web
results API：

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Tool details 和 safety notes：[tools.md](tools.md) 与
[security.md](security.md)。

通过 assistant 创建 reusable macro tools：

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

添加 optional local skills：

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files 会摘要进 system prompt，并按需通过 `read_file` 加载。

## Telegram

用 BotFather 创建 bot。如果在 `nllclw init` 中启用了 Telegram，wizard 写入
config 后即可立即开始 polling：

```sh
nllclw telegram
```

手动 env 配置时，设置 bot token 和一个 allowlisted chat。Allowlist 接受 numeric
chat id、private-chat username，或带不带 `@` 的 public chat username：

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Username allowlist example：

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

缺少 `NLLCLW_TELEGRAM_CHAT_ID` 时 Telegram 会拒绝启动。
启动后，在 Telegram 中发送 `/chatid` 可查看 numeric chat id 和可用的 username
fields。

Channel details：[channels.md](channels.md)。

## WebSocket UI Channel

为 custom UI 启动 loopback WebSocket server：

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint：

```text
ws://127.0.0.1:8765/ws?token=change-me
```

发送 JSON text frame：

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds 要求 explicit token：

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Remote binds 使用 `Authorization: Bearer change-me` 认证。Query tokens 只在
loopback binds 上接受。

WebSocket protocol details：[channels.md](channels.md)。

## Heartbeat and Daemon

从 `HEARTBEAT.md` 运行一次 heartbeat pass：

```sh
nllclw heartbeat
```

重复运行 due schedules 和 heartbeat tasks：

```sh
nllclw daemon
```

Useful settings：

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Verify the Repository

运行 standard checks：

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
