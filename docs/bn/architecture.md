# Architecture

`nllclw` একটি compact AI assistant, যা Zig package এবং একটি executable হিসেবে
নির্মিত। প্রধান design goal হলো agent engine testable রাখা, তবু ছোট standalone
binary ship করা।

## Goals

- Provider wire contract simple রাখুন: OpenAI-compatible Chat Completions।
- Runtime dependencies explicit রাখুন: default build শুধু Zig stdlib ব্যবহার করে।
- Local capabilities capability-gated এবং audit করা সহজ রাখুন।
- Channels thin রাখুন: CLI, REPL, Telegram, WebSocket, heartbeat এবং daemon একই
  runtime এবং agent engine call করে।
- Public package API শেখানোর মতো ছোট রাখুন।

## Layer Map

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

## Request Flow

একই engine argv prompts, stdin prompts, REPL turns, Telegram messages, WebSocket
prompts, heartbeat tasks এবং due schedules handle করে।

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

## Tool Loop Flow

Tools হলো product capabilities, infrastructure adapters নয়। এগুলো `src/tools/`-এ
থাকে এবং model-এর কাছে শুধু `src/tools/catalog.zig` দিয়ে exposed হয়।

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

Agent এই loop repeat করে যতক্ষণ না তিনটির একটি ঘটে:

- model tool calls ছাড়া assistant content return করে;
- `NLLCLW_TOOL_MAX_ROUNDS` পৌঁছায়;
- provider error, malformed provider response, allocation failure, বা অন্য fatal
  dispatch error ঘটে।

Non-fatal tool failures model-এ `tool error: ...` tool messages হিসেবে ফেরত যায়,
যাতে model recover করতে পারে, ভিন্ন arguments নিতে পারে, বা failure ব্যাখ্যা করতে
পারে। Allocation failures এখনও turn abort করে।

Tools enabled থাকলে streaming ইচ্ছাকৃতভাবে disabled। কোন tool calls চালাতে হবে তা
জানতে assistant-এর complete model response দরকার।

`src/chat.zig` JSON encoding-এর আগে প্রতিটি request string UTF-8 text হিসেবে
validate করে, binary control bytes ছাড়া। এতে Chat Completions fields JSON strings
থাকে, arbitrary byte slices arrays-এ degrade হয় না। SSE-তে `[DONE]` terminal; পরের
chunks ignored হয়।

## Module Responsibilities

| Path | Responsibility |
|---|---|
| `src/main.zig` | Minimal executable entrypoint এবং process exit। |
| `src/root.zig` | Stable public API: config, chat types, HTTP port, streaming sink, `complete`। |
| `src/runtime.zig` | CLI-like operation-এর composition root: config, HTTP adapter, memory adapter, context, tools। |
| `src/agent.zig` | Channel-neutral one-turn assistant engine, streaming এবং tool loop। |
| `src/chat.zig` | Chat Completions-এর JSON request/response codec, tools এবং SSE chunks সহ। |
| `src/providers.zig` | Provider presets এবং compatible-provider endpoint validation। |
| `src/config/*` | Typed runtime config, source collection, validation এবং owned copies। |
| `src/channels/*` | CLI, REPL, Telegram, WebSocket এবং daemon commands-এর user I/O orchestration। |
| `src/tools/*` | Tool definitions, local capabilities এবং user-defined macro tools। |
| `src/skills.zig` | On-demand local skill loading-এর compact `skills/*.md` index। |
| `src/persona.zig` | System prompt-এ appended runtime presentation modes। |
| `src/memory.zig` | Transcript/fact models, JSONL parsers এবং memory store ports। |
| `src/adapters/*` | Ports-এর concrete stdlib adapters। |
| `src/ports/*` | Testable boundaries-এর function-pointer interfaces। |
| `src/telegram/*` | Telegram Bot API wire helpers। |
| `src/websocket.zig` | Testable WebSocket JSON message/event helpers। |

## Public Package API

Consumers package module `nllclw` নামে import করে। Exported surface ছোট:

```zig
const nllclw = @import("nllclw");

const cfg: nllclw.Config = .{
    .provider = .openrouter,
    .api_key = "...",
    .model = "openai/gpt-chat-latest",
};

const text = try nllclw.complete(allocator, http_client, cfg, "hello");
```

Public API expose করে:

- `ProviderKind`
- `PersonaKind`
- `Config`
- chat request/tool types
- `HttpClient`, `HttpResponse`, `HttpHeader`, `HttpStatusCode`
- `Diagnostic`
- `ToolOptions`, `ToolHandler`, `ToolRunError`, `CompleteOptions`
- `StreamError`, `StreamSink`
- `complete` এবং `completeWithOptions`

Runtime-only details যেমন `config.json`/`.env` loading, file memory, Telegram
polling এবং stdlib HTTP adapter public root-এর বাইরে থাকে। Public tool handler
শুধু `ToolOptions`-এর প্রয়োজনীয় function-pointer abstraction; built-in product
tools এবং তাদের file-backed stores internal থাকে।

## Dependency Direction

Dependency direction explicit:

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

Core code process env, `config.json`, `.env`, filesystem paths, Telegram polling,
বা `std.http.Client` সম্পর্কে জানে না। এই details `runtime.zig` এবং channels assemble করে।

## Memory Ownership

Code Zig-এর explicit ownership style অনুসরণ করে:

- Allocate করা functions owned slices return করে এবং call sites-এর কাছে
  `defer`/`deinit` patterns দিয়ে ownership document করে।
- Long-lived runtime state `Runtime` own করে এবং `Runtime.deinit`-এ release হয়।
- Parsed config source buffers থেকে borrowed হতে পারে বা runtime storage-এর জন্য
  `config.Owned`-এ copied হতে পারে।
- Tool outputs model-এ ফেরত পাঠানো পর্যন্ত agent-এর owned থাকে এবং loop-এর পরে freed হয়।

## Cross-Platform Runtime Model

Default binary এমন সব target-এ run করার জন্য যেখানে Zig এবং Zig standard library
support করতে পারে:

- no `curl`;
- no provider SDK;
- no package dependencies in `build.zig.zon`;
- no shell process in the default build;
- `std.http.Client` for HTTPS;
- `std.Io` for files, stdin/stdout/stderr, and timers.

Optional shell tool একটি separate build flavor:

```sh
zig build -Dshell-tool=true
```

ওই flavor default নয় কারণ runtime-এ enabled হলে এটি `sh` বা `cmd.exe` launch করতে পারে।
