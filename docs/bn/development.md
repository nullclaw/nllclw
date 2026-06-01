# Development

`nllclw` পরিবর্তনের জন্য commands এবং conventions।

## Requirements

- Zig `0.16.0`
- Zig stdlib ছাড়া কোনো package dependency নেই

Package metadata check করুন:

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

Project যে cross-target release checks ব্যবহার করে:

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

Default test step cover করে:

- public package module;
- executable module;
- `src/all_tests.zig`, যা compile এবং behavior coverage-এর জন্য internal modules import করে।

Changes ফেরত দেওয়ার আগে full local gate চালান:

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

Binary size, startup, RAM, test counts, source counts এবং reproduction commands
[benchmarks.md](benchmarks.md)-এ documented।

## Adding a Provider Preset

Provider presets `src/providers.zig`-এ থাকে।

Checklist:

1. `ProviderKind` enum tag যোগ করুন।
2. `src/config/resolve.zig`-এ config parsing যোগ করুন।
3. `src/providers.zig`-এ endpoint এবং headers resolve করুন।
4. Endpoint, headers, invalid config এবং header injection-এর tests যোগ করুন।
5. Provider [configuration.md](configuration.md)-এ document করুন।

Provider minimal Chat Completions contract-এর সঙ্গে compatible থাকলে request body
provider-neutral রাখুন।

## Adding a Channel

যখন channels user-facing orchestration হয়, সেগুলো `src/channels/`-এ থাকে।

Checklist:

1. Parsing এবং I/O channel module-এ রাখুন।
2. Config, HTTP, memory, tools এবং completions-এর জন্য `runtime.Runtime` ব্যবহার করুন।
3. Telegram offsets-এর মতো channel-specific state ছাড়া channel-এ direct provider
   বা filesystem logic এড়িয়ে চলুন।
4. Channel main executable থেকে launched হলে `src/channels/cli.zig`-এ command/help text যোগ করুন।
5. Channel-এর protocol surface থাকলে reusable wire parsing/formatting sibling
   protocol module-এ রাখুন, যেমন WebSocket-এর জন্য `src/websocket.zig`।
6. Command recognition, protocol parsing এবং error mapping-এর tests যোগ করুন।
7. Channel [channels.md](channels.md)-এ document করুন।

## Adding a Tool

Tools `src/tools/`-এ থাকে এবং `src/tools/catalog.zig`-এ registered হয়।
Full tool checklist-এর জন্য [tools.md](tools.md) দেখুন।

Short version:

- `chat.ToolDefinition` define করুন;
- `std.json` দিয়ে arguments parse করুন;
- owned UTF-8 text return করুন;
- output cap করুন;
- local-state capabilities explicit config flags-এর পেছনে রাখুন;
- positive এবং negative behavior test করুন।

## Adding Memory Storage

Memory domain `src/memory.zig`-এ থাকে; concrete storage `src/adapters/`-এ থাকে।

আরেকটি storage backend যোগ করতে:

1. `memory.TranscriptStore` এবং/অথবা `memory.FactStore` implement করুন।
2. Backend-specific file/database/network details `memory.zig`-এর বাইরে রাখুন।
3. Backend `runtime.zig`-এ wire করুন।
4. Malformed data, bounds, duplicate keys এবং deletion-এর adapter tests যোগ করুন।

## Documentation Rules

- `README.md` structured, practical এবং learning-এর জন্য useful রাখুন।
- Long-form English docs `docs/en/`-এ রাখুন।
- `docs/README.md` language index রাখুন এবং শুধু real entry point থাকা languages list করুন।
- README translations `README.ru.md`-এর মতো separate files-এ রাখুন।
- Translated README files-এ English README section order preserve করুন।
- Mermaid diagrams ব্যবহার করুন যাতে GitHub natively render করে।
- প্রতিটি new runtime capability-এর configuration docs এবং safety notes দরকার।
- প্রতিটি new command README বা [channels.md](channels.md)-এ থাকতে হবে।
- প্রতিটি new docs page [English docs hub](README.md) থেকে link হতে হবে এবং
  user-facing হলে root [README](../../README.md) থেকেও।
- Translation-ready writing-এর জন্য [localization.md](localization.md) follow করুন।
