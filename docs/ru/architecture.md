# Архитектура

`nllclw` — компактный AI assistant, собранный как Zig package плюс один
executable. Главная цель дизайна — сохранить agent engine тестируемым и при
этом поставлять небольшой standalone binary.

## Цели

- Держать provider wire contract простым: OpenAI-compatible Chat Completions.
- Держать runtime dependencies явными: default build использует только Zig
  stdlib.
- Держать локальные capabilities за capability gates и простыми для аудита.
- Держать каналы тонкими: CLI, REPL, Telegram, WebSocket, heartbeat и daemon
  вызывают один и тот же runtime и agent engine.
- Держать public package API достаточно маленьким, чтобы по нему было удобно
  учиться.

## Карта слоев

```mermaid
flowchart TB
    Main["src/main.zig\nprocess entrypoint"]
    Root["src/root.zig\npublic package API"]
    Channels["src/channels/*\nCLI, REPL, Telegram, WebSocket"]
    Runtime["src/runtime.zig\ncomposition root"]
    Config["src/config/* + env.zig + dotenv.zig\nconfiguration sources and validation"]
    Context["src/context.zig + skills.zig + persona.zig\nassistant context, skills, persona"]
    Agent["src/agent.zig\ncompletion, streaming, tool loop"]
    Chat["src/chat.zig\nChat Completions JSON codec"]
    Providers["src/providers.zig\nendpoint and headers"]
    Policy["src/path_policy.zig + text_policy.zig\nshared boundary validation"]
    Tools["src/tools/*\nregistered product capabilities"]
    Memory["src/memory.zig\nmemory model and ports"]
    Scheduler["src/scheduler.zig + heartbeat.zig\nlocal future work"]
    Ports["src/ports/*\ninterfaces"]
    Adapters["src/adapters/*\nstdlib HTTP, file state"]
    Telegram["src/telegram/*\nBot API codec/client/offset"]
    WebSocket["src/websocket.zig\nWebSocket JSON protocol helpers"]

    Main --> Channels
    Root --> Agent
    Root --> Chat
    Root --> Providers
    Root --> Ports
    Channels --> Runtime
    Runtime --> Config
    Runtime --> Context
    Runtime --> Agent
    Runtime --> Tools
    Runtime --> Memory
    Runtime --> Scheduler
    Runtime --> Adapters
    Config --> Policy
    Chat --> Policy
    Tools --> Policy
    Telegram --> Policy
    WebSocket --> Policy
    Channels --> Telegram
    Channels --> WebSocket
    Agent --> Chat
    Agent --> Providers
    Agent --> Ports
    Tools --> Memory
    Tools --> Scheduler
    Adapters --> Ports
    Adapters --> Memory
```

## Поток запроса

Один и тот же engine обрабатывает argv prompts, stdin prompts, REPL turns,
Telegram messages, WebSocket prompts, heartbeat tasks и due schedules.

```mermaid
sequenceDiagram
    participant Channel
    participant Runtime
    participant Config
    participant Context
    participant Memory
    participant Agent
    participant HTTP
    participant Provider

    Channel->>Runtime: init(io, env)
    Runtime->>Config: merge OS env, config.json, and .env
    Runtime->>Context: load IDENTITY/SOUL/AGENTS/etc. + persona
    Runtime->>Memory: load transcript JSONL
    Channel->>Runtime: prompt
    Runtime->>Agent: config, system prompt, history, prompt
    Agent->>HTTP: POST /chat/completions
    HTTP->>Provider: HTTPS request
    Provider-->>HTTP: JSON or SSE response
    HTTP-->>Agent: response body
    Agent-->>Runtime: assistant text
    Runtime->>Memory: append user and assistant messages
    Runtime-->>Channel: assistant text
```

## Поток Tool Loop

Tools являются product capabilities, а не infrastructure adapters. Они живут в
`src/tools/` и предоставляются модели только через `src/tools/catalog.zig`.

```mermaid
flowchart TD
    Config["RuntimeConfig.tools"] --> Catalog["Tool catalog"]
    Catalog --> Definitions["Chat tool definitions"]
    Catalog --> Handlers["Function-pointer handlers"]
    Definitions --> Agent["Agent request"]
    Agent --> LLM["Provider model"]
    LLM --> Calls["tool_calls"]
    Calls --> Registry["Tool registry dispatch"]
    Registry --> FS["filesystem tools"]
    Registry --> Mem["memory tools"]
    Registry --> Sched["scheduler tools"]
    Registry --> Time["time/diagnostics/web tools"]
    Registry --> Macros["user-defined macro tools"]
    Registry --> Shell["optional shell_exec\ncompiled with -Dshell-tool=true"]
    Registry --> Results["bounded tool outputs"]
    Results --> Agent
```

Агент повторяет этот loop, пока не произойдет одно из трех событий:

- модель вернет assistant content без tool calls;
- достигнут `NLLCLW_TOOL_MAX_ROUNDS`;
- произойдет provider error, malformed provider response, allocation failure
  или другая fatal dispatch error.

Non-fatal tool failures возвращаются модели как tool messages вида
`tool error: ...`, чтобы модель могла восстановиться, выбрать другие аргументы
или объяснить ошибку. Allocation failures все равно прерывают turn.

Streaming намеренно выключается, когда tools включены. Ассистенту нужен полный
ответ модели, чтобы знать, какие tool calls запускать.

`src/chat.zig` валидирует каждую request string как UTF-8 text без binary
control bytes до JSON encoding. Это держит поля Chat Completions как JSON
strings вместо того, чтобы arbitrary byte slices деградировали в arrays. Для
SSE `[DONE]` является terminal; последующие chunks игнорируются.

## Ответственность модулей

| Путь | Ответственность |
|---|---|
| `src/main.zig` | Минимальный executable entrypoint и process exit. |
| `src/root.zig` | Stable public API: config, chat types, HTTP port, streaming sink, `complete`. |
| `src/runtime.zig` | Composition root для CLI-like operation: config, HTTP adapter, memory adapter, context, tools. |
| `src/agent.zig` | Channel-neutral one-turn assistant engine, streaming и tool loop. |
| `src/chat.zig` | JSON request/response codec для Chat Completions, включая tools и SSE chunks. |
| `src/providers.zig` | Provider presets и compatible-provider endpoint validation. |
| `src/config/*` | Typed runtime config, source collection, validation и owned copies. |
| `src/channels/*` | User I/O orchestration для CLI, REPL, Telegram, WebSocket и daemon commands. |
| `src/tools/*` | Tool definitions, local capabilities и user-defined macro tools. |
| `src/skills.zig` | Компактный index `skills/*.md` для on-demand local skill loading. |
| `src/persona.zig` | Runtime presentation modes, добавляемые в system prompt. |
| `src/memory.zig` | Transcript/fact models, JSONL parsers и memory store ports. |
| `src/adapters/*` | Конкретные stdlib adapters для ports. |
| `src/ports/*` | Function-pointer interfaces для testable boundaries. |
| `src/telegram/*` | Telegram Bot API wire helpers. |
| `src/websocket.zig` | Testable WebSocket JSON message/event helpers. |

## Public Package API

Consumers импортируют package module как `nllclw`. Exported surface маленький:

```zig
const nllclw = @import("nllclw");

const cfg: nllclw.Config = .{
    .provider = .openrouter,
    .api_key = "...",
    .model = "openai/gpt-chat-latest",
};

const text = try nllclw.complete(allocator, http_client, cfg, "hello");
```

Public API предоставляет:

- `ProviderKind`
- `PersonaKind`
- `Config`
- chat request/tool types
- `HttpClient`, `HttpResponse`, `HttpHeader`, `HttpStatusCode`
- `Diagnostic`
- `ToolOptions`, `ToolHandler`, `ToolRunError`, `CompleteOptions`
- `StreamError`, `StreamSink`
- `complete` и `completeWithOptions`

Runtime-only details, такие как загрузка `config.json`/`.env`, file memory,
Telegram polling и stdlib HTTP adapter, остаются вне public root. Public tool
handler является только function-pointer abstraction, нужной `ToolOptions`;
built-in product tools и их file-backed stores остаются internal.

## Направление зависимостей

Направление зависимостей явное:

```mermaid
flowchart LR
    Channels --> Runtime
    Runtime --> Core["Agent, chat, providers, config"]
    Runtime --> Adapters
    Runtime --> Tools
    Tools --> Ports["Memory/scheduler/http ports"]
    Adapters --> Ports
    Core --> Ports
```

Core code не знает о process env, `config.json`, `.env`, filesystem paths,
Telegram polling или `std.http.Client`. Эти детали собираются в `runtime.zig` и
каналах.

## Владение памятью

Код следует Zig-стилю явного ownership:

- Functions, которые выделяют память, возвращают owned slices и документируют
  ownership через `defer`/`deinit` patterns рядом с call sites.
- Long-lived runtime state принадлежит `Runtime` и освобождается в
  `Runtime.deinit`.
- Parsed config может быть borrowed из source buffers или copied в
  `config.Owned` для runtime storage.
- Tool outputs принадлежат агенту, пока не будут отправлены обратно модели, а
  затем освобождаются после loop.

## Cross-Platform Runtime Model

Default binary предназначен для запуска везде, где Zig и Zig standard library
могут поддерживать target:

- нет `curl`;
- нет provider SDK;
- нет package dependencies в `build.zig.zon`;
- нет shell process в default build;
- `std.http.Client` для HTTPS;
- `std.Io` для files, stdin/stdout/stderr и timers.

Optional shell tool является отдельным build flavor:

```sh
zig build -Dshell-tool=true
```

Этот flavor не является default, потому что может запускать `sh` или `cmd.exe`
при включении во время выполнения.
