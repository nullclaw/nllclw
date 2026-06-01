# nllclw English Documentation

The repository README is the quick entry point. These documents cover setup,
operation, security, and development in more detail.

| Document | Purpose |
|---|---|
| [installation.md](installation.md) | Install a release binary first, or install Zig `0.16.0` when building from source. |
| [getting-started.md](getting-started.md) | Configure a provider and run the assistant from a release binary or source build. |
| [architecture.md](architecture.md) | System boundaries, request flows, module map, and public API shape. |
| [configuration.md](configuration.md) | All configuration keys, `config.json` and `.env` behavior, provider presets, and validation rules. |
| [context.md](context.md) | Assistant context files such as `SOUL.md`, `AGENTS.md`, and `MEMORY.md`. |
| [memory.md](memory.md) | Transcript memory, durable fact memory, JSONL formats, and memory tools. |
| [tools.md](tools.md) | Tool registry, tool-call flow, capability gates, and filesystem safety model. |
| [channels.md](channels.md) | CLI, interactive REPL, Telegram polling, WebSocket UI channel, heartbeat, and daemon behavior. |
| [security.md](security.md) | Capability boundaries, local file safety, provider-key handling, and threat model. |
| [benchmarks.md](benchmarks.md) | Binary size, startup, RAM, tests, source counts, and reproduction commands. |
| [localization.md](localization.md) | Translation-ready writing rules and the expected multilingual docs layout. |
| [development.md](development.md) | Build/test commands, project conventions, and extension recipes. |

## Reading Order

1. Start with the repository [README](../../README.md) for the project overview.
2. Use [installation.md](installation.md) to install the release binary or set up Zig for source builds.
3. Follow [getting-started.md](getting-started.md) to configure and run.
4. Read [configuration.md](configuration.md) before using a real provider key.
5. Read [context.md](context.md), [memory.md](memory.md), and [tools.md](tools.md) before enabling local capabilities.
6. Read [security.md](security.md) before running in a sensitive directory.
7. Read [architecture.md](architecture.md) and [development.md](development.md) when modifying the code.
8. Read [localization.md](localization.md) before translating documentation.

## Design Summary

`nllclw` keeps user-facing channels, runtime composition, agent logic, provider
resolution, memory, tools, and stdlib adapters in separate modules. The default
build uses only Zig and the Zig standard library at runtime.
