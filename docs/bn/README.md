# nllclw বাংলা ডকুমেন্টেশন

Repository README হলো দ্রুত প্রবেশদ্বার। এই ডকুমেন্টগুলো setup, operation,
security এবং development আরও বিস্তারিতভাবে ব্যাখ্যা করে।

| ডকুমেন্ট | উদ্দেশ্য |
|---|---|
| [installation.md](installation.md) | প্রথমে release binary install করুন, অথবা source থেকে build করলে Zig `0.16.0` install করুন। |
| [getting-started.md](getting-started.md) | Provider configure করুন এবং release binary বা source build থেকে assistant চালান। |
| [architecture.md](architecture.md) | System boundaries, request flows, module map এবং public API shape। |
| [configuration.md](configuration.md) | সব configuration keys, `config.json` এবং `.env` behavior, provider presets এবং validation rules। |
| [context.md](context.md) | Assistant context files যেমন `SOUL.md`, `AGENTS.md`, এবং `MEMORY.md`। |
| [memory.md](memory.md) | Transcript memory, durable fact memory, JSONL formats এবং memory tools। |
| [tools.md](tools.md) | Tool registry, tool-call flow, capability gates এবং filesystem safety model। |
| [channels.md](channels.md) | CLI, interactive REPL, Telegram polling, WebSocket UI channel, heartbeat এবং daemon behavior। |
| [security.md](security.md) | Capability boundaries, local file safety, provider-key handling এবং threat model। |
| [benchmarks.md](benchmarks.md) | Binary size, startup, RAM, tests, source counts এবং reproduction commands। |
| [localization.md](localization.md) | Translation-ready writing rules এবং প্রত্যাশিত multilingual docs layout। |
| [development.md](development.md) | Build/test commands, project conventions এবং extension recipes। |

## পড়ার ক্রম

1. Project overview-এর জন্য repository [README](../../README.md) দিয়ে শুরু করুন।
2. Release binary install করতে বা source builds-এর জন্য Zig setup করতে [installation.md](installation.md) ব্যবহার করুন।
3. Configure এবং run করতে [getting-started.md](getting-started.md) অনুসরণ করুন।
4. Real provider key ব্যবহারের আগে [configuration.md](configuration.md) পড়ুন।
5. Local capabilities enable করার আগে [context.md](context.md), [memory.md](memory.md), এবং [tools.md](tools.md) পড়ুন।
6. Sensitive directory-তে চালানোর আগে [security.md](security.md) পড়ুন।
7. Code modify করার সময় [architecture.md](architecture.md) এবং [development.md](development.md) পড়ুন।
8. Documentation translate করার আগে [localization.md](localization.md) পড়ুন।

## Design Summary

`nllclw` user-facing channels, runtime composition, agent logic, provider
resolution, memory, tools এবং stdlib adapters আলাদা modules-এ রাখে। Default build
runtime-এ শুধু Zig এবং Zig standard library ব্যবহার করে।
