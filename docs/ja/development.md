# Development

`nllclw` を変更するための commands と conventions。

## Requirements

- Zig `0.16.0`
- Zig stdlib 以外の package dependencies はなし

Package metadata を check します:

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

Project が使う cross-target release checks:

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

Default test step は次を cover します:

- public package module;
- executable module;
- compile と behavior coverage のために internal modules を import する `src/all_tests.zig`。

Changes を返す前に full local gate を実行します:

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

Binary size、startup、RAM、test counts、source counts、reproduction commands は
[benchmarks.md](benchmarks.md) に documented されています。

## Adding a Provider Preset

Provider presets は `src/providers.zig` にあります。

Checklist:

1. `ProviderKind` enum tag を追加します。
2. `src/config/resolve.zig` に config parsing を追加します。
3. `src/providers.zig` で endpoint と headers を resolve します。
4. Endpoint、headers、invalid config、header injection の tests を追加します。
5. Provider を [configuration.md](configuration.md) に document します。

Provider が minimal Chat Completions contract と compatible なままである限り、
request body は provider-neutral に保ちます。

## Adding a Channel

Channels は user-facing orchestration の場合 `src/channels/` に置きます。

Checklist:

1. Parsing と I/O は channel module に置きます。
2. Config、HTTP、memory、tools、completions には `runtime.Runtime` を使います。
3. Telegram offsets のような channel-specific state を除き、channel 内の direct
   provider logic や filesystem logic は避けます。
4. Channel が main executable から launched される場合、`src/channels/cli.zig` に command/help text を追加します。
5. Channel に protocol surface がある場合、WebSocket の `src/websocket.zig` のように reusable wire parsing/formatting を sibling protocol module に置きます。
6. Command recognition、protocol parsing、error mapping の tests を追加します。
7. Channel を [channels.md](channels.md) に document します。

## Adding a Tool

Tools は `src/tools/` に置き、`src/tools/catalog.zig` で registered します。
Full tool checklist は [tools.md](tools.md) を参照してください。

Short version:

- `chat.ToolDefinition` を define します;
- `std.json` で arguments を parse します;
- owned UTF-8 text を return します;
- output を cap します;
- local-state capabilities は explicit config flags の後ろに置きます;
- positive と negative behavior を test します。

## Adding Memory Storage

Memory domain は `src/memory.zig` にあり、concrete storage は `src/adapters/` にあります。

別の storage backend を追加するには:

1. `memory.TranscriptStore` と/または `memory.FactStore` を implement します。
2. Backend-specific file/database/network details を `memory.zig` の外に置きます。
3. Backend を `runtime.zig` で wire します。
4. Malformed data、bounds、duplicate keys、deletion の adapter tests を追加します。

## Documentation Rules

- `README.md` は structured、practical、learning に useful に保ちます。
- Long-form English docs は `docs/en/` に保ちます。
- `docs/README.md` は language index とし、real entry point を持つ languages だけを list します。
- README translations は `README.ru.md` のような separate files に置きます。
- Translated README files では English README section order を preserve します。
- GitHub が natively render できるように Mermaid diagrams を使います。
- すべての new runtime capability には configuration docs と safety notes が必要です。
- すべての new command は README または [channels.md](channels.md) に載せます。
- すべての new docs page は [English docs hub](README.md) から link し、user-facing の場合は root [README](../../README.md) からも link します。
- Translation-ready writing は [localization.md](localization.md) に従います。
