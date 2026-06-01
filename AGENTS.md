# AGENTS.md

This is the canonical workspace instruction file for nllclw and for coding
agents working on this repository. nllclw loads this file into runtime context
when it is present in the current directory. Tool-specific files in this repo
point here.

## Project

nllclw is a tiny Zig 0.16 AI assistant. It is intentionally stdlib-only by
default: no package dependencies, no `curl`, no external runtime process, and no
shell tool unless the binary is built with `-Dshell-tool=true`.

## Architecture

- `src/main.zig`: process entrypoint only.
- `src/root.zig`: small public Zig package API.
- `src/runtime.zig`: composition root for channels, config, adapters, memory, and tools.
- `src/agent.zig`: channel-neutral Chat Completions engine.
- `src/chat.zig`: OpenAI-compatible Chat Completions JSON/SSE codec.
- `src/providers.zig`: OpenAI/OpenRouter/compatible endpoint and header presets.
- `src/config/`: runtime config types, source mapping, and validation.
- `src/channels/`: CLI, terminal REPL, local commands, Telegram, and WebSocket orchestration.
- `src/tools/`: product tools: time, diagnostics, filesystem, memory, web search, scheduler, macro tools, and optional shell.
- `src/ports/`: dependency ports.
- `src/adapters/`: stdlib implementations of ports.

Keep product capabilities in `src/tools/`, technical implementations in
`src/adapters/`, and channel loops in `src/channels/`.

## Build And Test

Run these before handing work back:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

For portability-sensitive changes, also run:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Rules

- Use Zig stdlib APIs first.
- Preserve zero external runtime dependencies in the default binary.
- Keep shell execution behind `-Dshell-tool=true`.
- Do not expose channel/runtime internals from `src/root.zig`.
- Add tests near the code for new behavior.
- Update README metrics when release binary size, test counts, source file
  counts, or LOC change.
- When changing English documentation under `docs/en/`, apply the equivalent
  documentation update to every translated language directory under `docs/`.
- Do not commit `.env`, `config.json`, `USER.md`, `BOOTSTRAP.md`, or generated memory files.
