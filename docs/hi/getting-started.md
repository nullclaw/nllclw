# Getting Started

`nllclw` install, configure और run करें। अधिकांश users के लिए पहला कदम source
से build करने के बजाय latest release binary download करना है।

## आवश्यकताएँ

- [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest) से
  `nllclw` release binary, या source से build करने पर Zig `0.16.0` और Git।
- Provider access: cloud API key, या Ollama जैसा local OpenAI-compatible server।

Repository private रहने तक release downloads के लिए `nullclaw/nllclw` access
चाहिए।

Official references:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## nllclw install करें

अपने OS और CPU के लिए latest release asset download करके extract करें, फिर binary
check करें:

```sh
./nllclw --help
```

macOS/Linux पर जरूरत हो तो पहले executable करें:

```sh
chmod +x nllclw
```

## Source से build करें

Release binary इस्तेमाल करते समय यह section skip करें। Source builds के लिए Zig
`0.16.0` चाहिए:

```sh
zig version
```

macOS, Linux, Windows, containers, CI और ESP-IDF host shells के detailed install
paths [installation.md](installation.md) में हैं।

Clone और build करें:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Small release binary build करें:

```sh
zig build --release=small
```

Binary check करें:

```sh
./zig-out/bin/nllclw --help
```

चाहें तो globally install करें:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

`/usr/local/bin` या BSD/GNU `install` न होने वाले platforms पर
`zig-out/bin/nllclw` को अपने `PATH` की किसी directory में copy करें।

## Configure a Provider

Wizard एक बार चलाएँ:

```sh
nllclw init
```

Wizard provider, optional `max_tokens`, assistant style, local capability profile,
Telegram, WebSocket और web search setup के लिए numbered menus इस्तेमाल करता है।
Menu default accept करने के लिए Enter दबाएँ।

`nllclw` पहले OS env, फिर user config directory में `config.json`, और फिर उसी
directory में `.env` पढ़ता है। OS env file config override करता है, और
`config.json` `.env` override करता है। सामान्य उपयोग के लिए `nllclw init` से बना
`config.json` prefer करें; one-off overrides या CI के लिए OS env इस्तेमाल करें।
`nllclw init --env` केवल तब इस्तेमाल करें जब आप `.env` format prefer करते हैं।

Manual `config.json` उदाहरण:

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

Compatible provider के जरिए Atlas Cloud:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Ollama local मॉडल:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Local HTTP providers के लिए केवल exact loopback hosts allowed हैं। `api_key`
`nllclw` के लिए required है; Ollama कोई भी non-empty value accept करता है।

पूर्ण configuration reference: [configuration.md](configuration.md)।

Wizard द्वारा बनाए गए files और runtime state हटाने के लिए:

```sh
nllclw uninstall
```

## Run

Direct prompt:

```sh
nllclw "summarize what this project does"
```

अगर binary globally installed नहीं है:

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

stdin से prompt:

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat:

```sh
nllclw
```

Chat loop से exit:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` default है, लेकिन default tool loop non-streaming है क्योंकि
local functions चलने से पहले tool calls parse होने चाहिए। Pure streaming chat के
लिए tools disable करें:

```sh
NLLCLW_TOOLS=off
```

Streaming explicitly disable करें:

```sh
NLLCLW_STREAM=off
```

## Persona

Default persona neutral है। Startup style चुनें:

```sh
NLLCLW_PERSONA=technical
```

Direct CLI, REPL, या Telegram में persona switch करें:

```sh
nllclw /persona friendly
```

Supported modes `neutral`, `friendly`, `technical`, और `witty` हैं।

## Enable Memory

Transcript memory default रूप से on है:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory default local tool loop के माध्यम से available है:

```sh
NLLCLW_MEMORY=on
```

Local facts inspect करें:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Memory details: [memory.md](memory.md)।

## Tools

External services की जरूरत न रखने वाले local tools default रूप से enabled हैं:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

किसी भी capability को disable करने के लिए उसे `off` set करें।

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo no-key Instant Answer fallback के रूप में इस्तेमाल हो सकता है, लेकिन
यह full web results API नहीं है:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Tool details और safety notes: [tools.md](tools.md) और [security.md](security.md)।

Assistant के माध्यम से reusable macro tools बनाएँ:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Optional local skills जोड़ें:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files system prompt में summarized होते हैं और demand पर `read_file` से loaded होते हैं।

## Telegram

BotFather से bot बनाएँ। अगर आपने `nllclw init` में Telegram enable किया, wizard
config लिखने के तुरंत बाद polling start करें:

```sh
nllclw telegram
```

Manual env configuration के लिए bot token और एक allowlisted chat set करें।
Allowlist numeric chat id, private-chat username, या `@` के साथ या बिना public
chat username accept करता है:

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

Telegram `NLLCLW_TELEGRAM_CHAT_ID` के बिना start करने से मना करता है।
Startup के बाद, numeric chat id और available username fields देखने के लिए Telegram
में `/chatid` भेजें।

Channel details: [channels.md](channels.md)।

## WebSocket UI Channel

Custom UI के लिए loopback WebSocket server start करें:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

JSON text frame भेजें:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds explicit token require करते हैं:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Remote binds के लिए `Authorization: Bearer change-me` से authenticate करें। Query
tokens केवल loopback binds पर accepted हैं।

WebSocket protocol details: [channels.md](channels.md)।

## Heartbeat and Daemon

`HEARTBEAT.md` से एक heartbeat pass चलाएँ:

```sh
nllclw heartbeat
```

Due schedules और heartbeat tasks repeatedly चलाएँ:

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

Standard checks चलाएँ:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
