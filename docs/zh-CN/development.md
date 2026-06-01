# 开发

用于修改 `nllclw` 的命令和约定。

## 要求

- Zig `0.16.0`
- 除 Zig stdlib 外没有 package dependencies

检查 package metadata：

```sh
cat build.zig.zon
```

## Build commands

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

项目使用的 cross-target release checks：

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Test commands

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

默认 test step 覆盖：

- public package module；
- executable module；
- `src/all_tests.zig`，它导入 internal modules 以覆盖 compile 和 behavior。

交回修改前，运行完整本地 gate：

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

Binary size、startup、RAM、test counts、source counts 和 reproduction commands
记录在 [benchmarks.md](benchmarks.md) 中。

## 添加 provider preset

Provider presets 位于 `src/providers.zig`。

Checklist：

1. 添加一个 `ProviderKind` enum tag。
2. 在 `src/config/resolve.zig` 中添加 config parsing。
3. 在 `src/providers.zig` 中 resolve endpoint 和 headers。
4. 为 endpoint、headers、invalid config 和 header injection 添加 tests。
5. 在 [configuration.md](configuration.md) 中记录 provider。

保持 request body provider-neutral，除非 provider 仍兼容最小 Chat Completions
contract。

## 添加 channel

当 channel 是面向用户的 orchestration 时，它属于 `src/channels/`。

Checklist：

1. 将 parsing 和 I/O 保持在 channel module 中。
2. 使用 `runtime.Runtime` 处理 config、HTTP、memory、tools 和 completions。
3. 避免在 channel 中直接放 provider 或 filesystem logic，除非它是
   channel-specific state，例如 Telegram offsets。
4. 如果 channel 从主 executable 启动，在 `src/channels/cli.zig` 中添加
   command/help text。
5. 当 channel 有 protocol surface 时，将可复用的 wire parsing/formatting
   放在相邻 protocol module 中，例如 WebSocket 在 `src/websocket.zig` 中。
6. 为 command recognition、protocol parsing 和 error mapping 添加 tests。
7. 在 [channels.md](channels.md) 中记录 channel。

## 添加 tool

Tools 属于 `src/tools/`，并在 `src/tools/catalog.zig` 中注册。完整 tool
checklist 见 [tools.md](tools.md)。

简版：

- 定义 `chat.ToolDefinition`；
- 用 `std.json` 解析 arguments；
- 返回 owned UTF-8 text；
- 限制 output；
- 将 local-state capabilities 放在显式 config flags 后面；
- 测试 positive 和 negative behavior。

## 添加 memory storage

Memory domain 位于 `src/memory.zig`；concrete storage 位于 `src/adapters/`。

要添加另一个 storage backend：

1. 实现 `memory.TranscriptStore` 和/或 `memory.FactStore`。
2. 将 backend-specific file/database/network details 放在 `memory.zig` 外。
3. 在 `runtime.zig` 中接入 backend。
4. 为 malformed data、bounds、duplicate keys 和 deletion 添加 adapter tests。

## 文档规则

- 保持 `README.md` 结构化、实用且便于学习。
- 将长篇英文文档保存在 `docs/en/`。
- 将 `docs/README.md` 作为语言索引，只列出有真实 entry point 的语言。
- 将 README 翻译放入单独文件，例如 `README.ru.md`。
- 在翻译 README 中保留英文 README 的 section 顺序。
- 使用 Mermaid diagrams，让 GitHub 原生渲染。
- 每个新的 runtime capability 都需要 configuration docs 和 safety notes。
- 每个新 command 都应出现在 README 或 [channels.md](channels.md) 中。
- 每个新的 docs page 都应从 [English docs hub](README.md) 链接；如果面向用户，
  还应从根 [README](../../README.md) 链接。
- 遵循 [localization.md](localization.md) 编写适合翻译的内容。
