# Development

أوامر واتفاقيات تغيير `nllclw`.

## Requirements

- Zig `0.16.0`
- لا توجد package dependencies خارج Zig stdlib

افحص package metadata:

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

Cross-target release checks المستخدمة في المشروع:

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

تغطي خطوة الاختبار الافتراضية:

- public package module;
- executable module;
- `src/all_tests.zig`، الذي يستورد internal modules لتغطية compile وbehavior.

قبل إعادة التغييرات، شغّل full local gate:

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

Binary size وstartup وRAM وtest counts وsource counts وأوامر reproduction موثقة في
[benchmarks.md](benchmarks.md).

## Adding a Provider Preset

توجد provider presets في `src/providers.zig`.

Checklist:

1. أضف `ProviderKind` enum tag.
2. أضف config parsing في `src/config/resolve.zig`.
3. Resolve endpoint وheaders في `src/providers.zig`.
4. أضف tests للendpoint والheaders وinvalid config وheader injection.
5. وثّق provider في [configuration.md](configuration.md).

أبق request body provider-neutral ما لم يكن provider لا يزال compatible مع عقد
Chat Completions الأدنى.

## Adding a Channel

توضع channels في `src/channels/` عندما تكون user-facing orchestration.

Checklist:

1. أبق parsing وI/O داخل channel module.
2. استخدم `runtime.Runtime` للconfig وHTTP وmemory وtools وcompletions.
3. تجنب direct provider أو filesystem logic داخل channel إلا إذا كان channel-specific
   state، مثل Telegram offsets.
4. أضف command/help text في `src/channels/cli.zig` إذا كان channel يطلق من main executable.
5. ضع reusable wire parsing/formatting في sibling protocol module عندما يكون لدى
   channel protocol surface، كما يفعل WebSocket في `src/websocket.zig`.
6. أضف tests للتعرف على commands وprotocol parsing وerror mapping.
7. وثّق channel في [channels.md](channels.md).

## Adding a Tool

Tools توضع في `src/tools/` وتُسجّل في `src/tools/catalog.zig`.
راجع [tools.md](tools.md) للاطلاع على full tool checklist.

النسخة المختصرة:

- عرّف `chat.ToolDefinition`;
- parse arguments باستخدام `std.json`;
- أعد owned UTF-8 text;
- cap output;
- ضع local-state capabilities خلف explicit config flags;
- اختبر positive وnegative behavior.

## Adding Memory Storage

يقع memory domain في `src/memory.zig`؛ concrete storage في `src/adapters/`.

لإضافة storage backend آخر:

1. نفّذ `memory.TranscriptStore` و/أو `memory.FactStore`.
2. أبق تفاصيل file/database/network الخاصة بالbackend خارج `memory.zig`.
3. Wire backend في `runtime.zig`.
4. أضف adapter tests للmalformed data وbounds وduplicate keys وdeletion.

## Documentation Rules

- أبق `README.md` منظماً وعملياً ومفيداً للتعلم.
- أبق long-form English docs في `docs/en/`.
- أبق `docs/README.md` كlanguage index ولا تعرض إلا اللغات ذات real entry point.
- ضع README translations في ملفات منفصلة مثل `README.ru.md`.
- حافظ على ترتيب أقسام English README في translated README files.
- استخدم Mermaid diagrams كي يعرضها GitHub natively.
- كل runtime capability جديدة تحتاج configuration docs وsafety notes.
- كل command جديد يجب أن يظهر في README أو [channels.md](channels.md).
- كل docs page جديدة يجب أن ترتبط من [English docs hub](README.md)، ومن root
  [README](../../README.md) عندما تكون user-facing.
- اتبع [localization.md](localization.md) للكتابة المناسبة للترجمة.
