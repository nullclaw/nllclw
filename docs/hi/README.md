# nllclw हिंदी दस्तावेज़

Repository README तेज़ प्रवेश बिंदु है। ये दस्तावेज़ setup, संचालन, सुरक्षा और
development को अधिक विस्तार से बताते हैं।

| दस्तावेज़ | उद्देश्य |
|---|---|
| [installation.md](installation.md) | पहले release binary install करें, या source से build करते समय Zig `0.16.0` install करें। |
| [getting-started.md](getting-started.md) | Provider configure करें और assistant को release binary या source build से चलाएँ। |
| [architecture.md](architecture.md) | System boundaries, request flows, module map और public API shape। |
| [configuration.md](configuration.md) | सभी configuration keys, `config.json` और `.env` behavior, provider presets और validation rules। |
| [context.md](context.md) | Assistant context files जैसे `SOUL.md`, `AGENTS.md`, और `MEMORY.md`। |
| [memory.md](memory.md) | Transcript memory, durable fact memory, JSONL formats और memory tools। |
| [tools.md](tools.md) | Tool registry, tool-call flow, capability gates और filesystem safety model। |
| [channels.md](channels.md) | CLI, interactive REPL, Telegram polling, WebSocket UI channel, heartbeat और daemon behavior। |
| [security.md](security.md) | Capability boundaries, local file safety, provider-key handling और threat model। |
| [benchmarks.md](benchmarks.md) | Binary size, startup, RAM, tests, source counts और reproduction commands। |
| [localization.md](localization.md) | Translation-ready writing rules और अपेक्षित multilingual docs layout। |
| [development.md](development.md) | Build/test commands, project conventions और extension recipes। |

## पढ़ने का क्रम

1. Project overview के लिए repository [README](../../README.md) से शुरू करें।
2. Release binary install करने या source builds के लिए Zig setup करने के लिए [installation.md](installation.md) का उपयोग करें।
3. Configure और run करने के लिए [getting-started.md](getting-started.md) का पालन करें।
4. असली provider key इस्तेमाल करने से पहले [configuration.md](configuration.md) पढ़ें।
5. Local capabilities enable करने से पहले [context.md](context.md), [memory.md](memory.md), और [tools.md](tools.md) पढ़ें।
6. Sensitive directory में चलाने से पहले [security.md](security.md) पढ़ें।
7. Code बदलते समय [architecture.md](architecture.md) और [development.md](development.md) पढ़ें।
8. Documentation translate करने से पहले [localization.md](localization.md) पढ़ें।

## Design Summary

`nllclw` user-facing channels, runtime composition, agent logic, provider
resolution, memory, tools और stdlib adapters को अलग-अलग modules में रखता है।
Default build runtime पर केवल Zig और Zig standard library का उपयोग करता है।
