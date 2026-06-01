# Development

`nllclw` बदलने के लिए commands और conventions।

## Requirements

- Zig `0.16.0`
- Zig stdlib के अलावा कोई package dependency नहीं

Package metadata check करें:

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

Project द्वारा इस्तेमाल किए जाने वाले cross-target release checks:

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

Default test step cover करता है:

- public package module;
- executable module;
- `src/all_tests.zig`, जो compile और behavior coverage के लिए internal modules
  import करता है।

Changes वापस देने से पहले full local gate चलाएँ:

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

Binary size, startup, RAM, test counts, source counts और reproduction commands
[benchmarks.md](benchmarks.md) में documented हैं।

## Adding a Provider Preset

Provider presets `src/providers.zig` में रहते हैं।

Checklist:

1. `ProviderKind` enum tag जोड़ें।
2. `src/config/resolve.zig` में config parsing जोड़ें।
3. `src/providers.zig` में endpoint और headers resolve करें।
4. Endpoint, headers, invalid config और header injection के tests जोड़ें।
5. Provider को [configuration.md](configuration.md) में document करें।

Request body को provider-neutral रखें, जब तक provider minimal Chat Completions
contract से compatible हो।

## Adding a Channel

Channels `src/channels/` में होते हैं जब वे user-facing orchestration हों।

Checklist:

1. Parsing और I/O channel module में रखें।
2. Config, HTTP, memory, tools और completions के लिए `runtime.Runtime` इस्तेमाल करें।
3. Channel-specific state, जैसे Telegram offsets, को छोड़कर direct provider या
   filesystem logic channel में न रखें।
4. अगर channel main executable से launch होता है, तो command/help text
   `src/channels/cli.zig` में जोड़ें।
5. Channel के पास protocol surface हो तो reusable wire parsing/formatting को
   sibling protocol module में रखें, जैसे WebSocket के लिए `src/websocket.zig`।
6. Command recognition, protocol parsing और error mapping के tests जोड़ें।
7. Channel को [channels.md](channels.md) में document करें।

## Adding a Tool

Tools `src/tools/` में होते हैं और `src/tools/catalog.zig` में registered होते हैं।
Full tool checklist के लिए [tools.md](tools.md) देखें।

Short version:

- `chat.ToolDefinition` define करें;
- `std.json` से arguments parse करें;
- owned UTF-8 text return करें;
- output cap करें;
- local-state capabilities को explicit config flags के पीछे रखें;
- positive और negative behavior test करें।

## Adding Memory Storage

Memory domain `src/memory.zig` में रहता है; concrete storage `src/adapters/` में।

दूसरा storage backend जोड़ने के लिए:

1. `memory.TranscriptStore` और/या `memory.FactStore` implement करें।
2. Backend-specific file/database/network details को `memory.zig` से बाहर रखें।
3. Backend को `runtime.zig` में wire करें।
4. Malformed data, bounds, duplicate keys और deletion के adapter tests जोड़ें।

## Documentation Rules

- `README.md` को structured, practical और learning के लिए useful रखें।
- Long-form English docs `docs/en/` में रखें।
- `docs/README.md` को language index रखें और केवल real entry point वाली languages list करें।
- README translations को `README.ru.md` जैसी separate files में रखें।
- Translated README files में English README section order preserve करें।
- Mermaid diagrams इस्तेमाल करें ताकि GitHub उन्हें natively render करे।
- हर नई runtime capability को configuration docs और safety notes चाहिए।
- हर new command README या [channels.md](channels.md) में आनी चाहिए।
- हर new docs page [English docs hub](README.md) से link होनी चाहिए और, user-facing हो तो,
  root [README](../../README.md) से भी।
- Translation-ready writing के लिए [localization.md](localization.md) follow करें।
