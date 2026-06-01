# Разработка

Команды и соглашения для изменения `nllclw`.

## Требования

- Zig `0.16.0`
- Нет пакетных зависимостей помимо Zig stdlib

Проверьте metadata пакета:

```sh
cat build.zig.zon
```

## Команды сборки

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

Кросс-таргетные release-проверки, используемые проектом:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Команды тестов

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

Шаг тестов по умолчанию покрывает:

- публичный package module;
- executable module;
- `src/all_tests.zig`, который импортирует внутренние модули для покрытия
  компиляции и поведения.

Перед передачей изменений запустите полный локальный gate:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

## Метрики

Размер бинарника, время запуска, RAM, количество тестов, количество исходников
и команды воспроизведения описаны в [benchmarks.md](benchmarks.md).

## Добавление пресета провайдера

Пресеты провайдеров находятся в `src/providers.zig`.

Checklist:

1. Добавьте enum tag в `ProviderKind`.
2. Добавьте parsing конфигурации в `src/config/resolve.zig`.
3. Разрешите endpoint и headers в `src/providers.zig`.
4. Добавьте тесты для endpoint, headers, некорректной конфигурации и header
   injection.
5. Задокументируйте провайдера в [configuration.md](configuration.md).

Держите request body provider-neutral, если провайдер все еще совместим с
минимальным контрактом Chat Completions.

## Добавление канала

Каналы принадлежат `src/channels/`, когда они являются пользовательской
оркестрацией.

Checklist:

1. Держите parsing и I/O в модуле канала.
2. Используйте `runtime.Runtime` для конфигурации, HTTP, памяти, инструментов и
   completions.
3. Избегайте прямой логики провайдера или файловой системы в канале, если это
   не channel-specific state, например Telegram offsets.
4. Добавьте текст command/help в `src/channels/cli.zig`, если канал запускается
   из основного executable.
5. Вынесите переиспользуемый wire parsing/formatting в соседний protocol
   module, когда канал имеет protocol surface, как WebSocket в
   `src/websocket.zig`.
6. Добавьте тесты для распознавания команд, parsing протокола и error mapping.
7. Задокументируйте канал в [channels.md](channels.md).

## Добавление инструмента

Инструменты принадлежат `src/tools/` и регистрируются в
`src/tools/catalog.zig`. Полный checklist для инструментов см.
в [tools.md](tools.md).

Короткая версия:

- определите `chat.ToolDefinition`;
- разбирайте аргументы через `std.json`;
- возвращайте owned UTF-8 text;
- ограничивайте вывод;
- помещайте возможности локального состояния за явные флаги конфигурации;
- тестируйте положительное и отрицательное поведение.

## Добавление хранилища памяти

Домен памяти находится в `src/memory.zig`; конкретное хранилище находится в
`src/adapters/`.

Чтобы добавить другой storage backend:

1. Реализуйте `memory.TranscriptStore` и/или `memory.FactStore`.
2. Держите backend-specific детали файлов/базы данных/сети вне `memory.zig`.
3. Подключите backend в `runtime.zig`.
4. Добавьте adapter tests для malformed data, bounds, duplicate keys и deletion.

## Правила документации

- Держите `README.md` структурированным, практичным и полезным для обучения.
- Держите подробную английскую документацию в `docs/en/`.
- Держите `docs/README.md` как индекс языков и перечисляйте только языки с
  реальной точкой входа.
- Помещайте переводы README в отдельные файлы, например `README.ru.md`.
- Сохраняйте порядок секций английского README в переведенных README-файлах.
- Используйте Mermaid diagrams, чтобы GitHub отображал их нативно.
- Каждая новая runtime-возможность требует документации конфигурации и заметок
  безопасности.
- Каждая новая команда должна появляться в README или [channels.md](channels.md).
- Каждая новая docs page должна быть связана из [English docs hub](README.md)
  и, если она пользовательская, из корневого [README](../../README.md).
- Следуйте [localization.md](localization.md) для письма, готового к переводу.
