# Development

Commands and conventions for changing `nllclw`.

## Requirements

- Zig `0.16.0`
- No package dependencies beyond Zig stdlib

Check the package metadata:

```sh
cat build.zig.zon
```

## Build Commands

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

Cross-target release checks used by the project:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Test Commands

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

The default test step covers:

- the public package module;
- the executable module;
- `src/all_tests.zig`, which imports internal modules for compile and behavior
  coverage.

Before handing changes back, run the full local gate:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

## Metrics

Binary size, startup, RAM, test counts, source counts, and reproduction commands
are documented in [benchmarks.md](benchmarks.md).

## Adding a Provider Preset

Provider presets live in `src/providers.zig`.

Checklist:

1. Add a `ProviderKind` enum tag.
2. Add config parsing in `src/config/resolve.zig`.
3. Resolve endpoint and headers in `src/providers.zig`.
4. Add tests for endpoint, headers, invalid config, and header injection.
5. Document the provider in [configuration.md](configuration.md).

Keep the request body provider-neutral unless the provider is still compatible
with the minimal Chat Completions contract.

## Adding a Channel

Channels belong in `src/channels/` when they are user-facing orchestration.

Checklist:

1. Keep parsing and I/O in the channel module.
2. Use `runtime.Runtime` for config, HTTP, memory, tools, and completions.
3. Avoid direct provider or filesystem logic in the channel unless it is
   channel-specific state, such as Telegram offsets.
4. Add command/help text in `src/channels/cli.zig` if the channel is launched
   from the main executable.
5. Put reusable wire parsing/formatting in a sibling protocol module when the
   channel has a protocol surface, as WebSocket does in `src/websocket.zig`.
6. Add tests for command recognition, protocol parsing, and error mapping.
7. Document the channel in [channels.md](channels.md).

## Adding a Tool

Tools belong in `src/tools/` and are registered in `src/tools/catalog.zig`.
See [tools.md](tools.md) for the full tool checklist.

The short version:

- define a `chat.ToolDefinition`;
- parse arguments with `std.json`;
- return owned UTF-8 text;
- cap output;
- put local-state capabilities behind explicit config flags;
- test positive and negative behavior.

## Adding Memory Storage

The memory domain lives in `src/memory.zig`; concrete storage lives in
`src/adapters/`.

To add another storage backend:

1. Implement `memory.TranscriptStore` and/or `memory.FactStore`.
2. Keep backend-specific file/database/network details out of `memory.zig`.
3. Wire the backend in `runtime.zig`.
4. Add adapter tests for malformed data, bounds, duplicate keys, and deletion.

## Documentation Rules

- Keep `README.md` structured, practical, and useful for learning.
- Keep long-form English docs in `docs/en/`.
- Keep `docs/README.md` as the language index and list only languages with a
  real entry point.
- Put README translations in separate files such as `README.ru.md`.
- Preserve the English README section order in translated README files.
- Use Mermaid diagrams so GitHub renders them natively.
- Every new runtime capability needs configuration docs and safety notes.
- Every new command should appear in README or [channels.md](channels.md).
- Every new docs page should be linked from the [English docs hub](README.md)
  and, when user-facing, the root [README](../../README.md).
- Follow [localization.md](localization.md) for translation-ready writing.
