# Contributing

Thanks for improving `nllclw`. This project is intentionally small, stdlib-only
by default, and conservative about local capabilities.

## Development Setup

Use Zig `0.16.0`.

```sh
zig version
zig build test --summary all
```

The default binary must not require package dependencies, `curl`, Node, Python,
an external runtime process, or a shell. Shell execution belongs only behind the
explicit `-Dshell-tool=true` build option.

## Before Submitting

Run the repository gate:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

For portability-sensitive changes, also run the cross-builds listed in
`AGENTS.md`.

## Code Guidelines

- Prefer Zig stdlib APIs before adding abstractions.
- Keep product tools in `src/tools/`, adapters in `src/adapters/`, channel loops
  in `src/channels/`, and runtime composition in `src/runtime.zig`.
- Keep `src/main.zig` as the process entrypoint only.
- Do not expose channel or runtime internals from `src/root.zig`.
- Add focused tests near the code for new behavior.
- Keep shell execution behind `-Dshell-tool=true`.
- Preserve safe defaults for local files, memory, tools, Telegram, WebSocket,
  and compatible-provider HTTP URLs.

## Documentation

- Prefer `config.json` examples for normal setup. Use environment variables for
  one-off overrides, CI, or `.env` documentation.
- Installation docs should recommend the latest release binary first, then
  source builds with Zig `0.16.0`.
- When changing English documentation under `docs/en/`, apply the equivalent
  update to every translated language directory under `docs/`.

## Secrets And Local State

Do not commit:

- `.env`
- `config.json`
- `USER.md`
- `BOOTSTRAP.md`
- generated memory files
- provider keys, Telegram tokens, WebSocket tokens, or private logs

If a contribution touches secret handling, local file access, shell execution,
network endpoints, or provider configuration, call that out clearly in the pull
request.
