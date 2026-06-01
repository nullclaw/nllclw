# nllclw 日本語ドキュメント

リポジトリ直下の README はクイックエントリーポイントです。これらの文書では、
セットアップ、運用、セキュリティ、開発をより詳しく説明します。

| 文書 | 目的 |
|---|---|
| [installation.md](installation.md) | まず release binary をインストールし、source から build する場合だけ Zig `0.16.0` をインストールします。 |
| [getting-started.md](getting-started.md) | Provider を設定し、release binary または source build から assistant を実行します。 |
| [architecture.md](architecture.md) | System boundaries、request flows、module map、public API shape。 |
| [configuration.md](configuration.md) | すべての configuration keys、`config.json` と `.env` の behavior、provider presets、validation rules。 |
| [context.md](context.md) | `SOUL.md`、`AGENTS.md`、`MEMORY.md` などの Assistant context files。 |
| [memory.md](memory.md) | Transcript memory、durable fact memory、JSONL formats、memory tools。 |
| [tools.md](tools.md) | Tool registry、tool-call flow、capability gates、filesystem safety model。 |
| [channels.md](channels.md) | CLI、interactive REPL、Telegram polling、WebSocket UI channel、heartbeat、daemon behavior。 |
| [security.md](security.md) | Capability boundaries、local file safety、provider-key handling、threat model。 |
| [benchmarks.md](benchmarks.md) | Binary size、startup、RAM、tests、source counts、reproduction commands。 |
| [localization.md](localization.md) | 翻訳しやすい書き方の rules と、想定される multilingual docs layout。 |
| [development.md](development.md) | Build/test commands、project conventions、extension recipes。 |

## 読む順序

1. Project overview はリポジトリの [README](../../README.md) から始めます。
2. Release binary のインストール、または source build 用の Zig セットアップには [installation.md](installation.md) を使います。
3. 設定して実行するには [getting-started.md](getting-started.md) に従います。
4. 実際の provider key を使う前に [configuration.md](configuration.md) を読みます。
5. Local capabilities を有効にする前に [context.md](context.md)、[memory.md](memory.md)、[tools.md](tools.md) を読みます。
6. Sensitive directory で実行する前に [security.md](security.md) を読みます。
7. Code を変更するときは [architecture.md](architecture.md) と [development.md](development.md) を読みます。
8. Documentation を翻訳する前に [localization.md](localization.md) を読みます。

## Design Summary

`nllclw` は user-facing channels、runtime composition、agent logic、provider
resolution、memory、tools、stdlib adapters を別々の modules に分けています。
Default build は runtime で Zig と Zig standard library だけを使います。
