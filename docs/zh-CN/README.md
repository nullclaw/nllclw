# nllclw 中文文档

仓库根目录的 README 是快速入口。这些文档更详细地介绍安装、运行、
安全和开发。

| 文档 | 用途 |
|---|---|
| [installation.md](installation.md) | 先安装 release binary；从 source 构建时再安装 Zig `0.16.0`。 |
| [getting-started.md](getting-started.md) | 配置 provider，并从 release binary 或 source build 运行 assistant。 |
| [architecture.md](architecture.md) | 系统边界、请求流、模块图和公共 API 形态。 |
| [configuration.md](configuration.md) | 所有配置 key、`config.json` 与 `.env` 行为、provider presets 和验证规则。 |
| [context.md](context.md) | Assistant context files，例如 `SOUL.md`、`AGENTS.md` 和 `MEMORY.md`。 |
| [memory.md](memory.md) | Transcript memory、durable fact memory、JSONL 格式和 memory tools。 |
| [tools.md](tools.md) | Tool registry、tool-call flow、capability gates 和 filesystem safety model。 |
| [channels.md](channels.md) | CLI、交互式 REPL、Telegram polling、WebSocket UI channel、heartbeat 和 daemon 行为。 |
| [security.md](security.md) | Capability boundaries、local file safety、provider-key handling 和 threat model。 |
| [benchmarks.md](benchmarks.md) | Binary size、startup、RAM、tests、source counts 和 reproduction commands。 |
| [localization.md](localization.md) | 面向翻译的写作规则和预期的多语言文档布局。 |
| [development.md](development.md) | Build/test commands、项目约定和扩展配方。 |

## 阅读顺序

1. 先阅读仓库根目录的 [README](../../README.md)，了解项目概览。
2. 使用 [installation.md](installation.md) 安装 release binary，或为 source build 设置 Zig。
3. 按照 [getting-started.md](getting-started.md) 完成配置并运行。
4. 使用真实 provider key 前，阅读 [configuration.md](configuration.md)。
5. 启用本地 capability 前，阅读 [context.md](context.md)、[memory.md](memory.md) 和 [tools.md](tools.md)。
6. 在敏感目录中运行前，阅读 [security.md](security.md)。
7. 修改代码时，阅读 [architecture.md](architecture.md) 和 [development.md](development.md)。
8. 翻译文档前，阅读 [localization.md](localization.md)。

## 设计概要

`nllclw` 将用户可见 channel、runtime composition、agent logic、provider
resolution、memory、tools 和 stdlib adapters 分隔到不同模块。默认 build
在运行时只使用 Zig 和 Zig standard library。
