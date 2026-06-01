# Документация nllclw на русском

README в корне репозитория является краткой точкой входа. Эти документы
подробнее описывают установку, эксплуатацию, безопасность и разработку.

| Документ | Назначение |
|---|---|
| [installation.md](installation.md) | Установка release binary в первую очередь или Zig `0.16.0` для сборки из source. |
| [getting-started.md](getting-started.md) | Настройка провайдера и запуск ассистента из release binary или source build. |
| [architecture.md](architecture.md) | Границы системы, потоки запросов, карта модулей и форма публичного API. |
| [configuration.md](configuration.md) | Все ключи конфигурации, поведение `config.json` и `.env`, пресеты провайдеров и правила валидации. |
| [context.md](context.md) | Файлы контекста ассистента, такие как `SOUL.md`, `AGENTS.md` и `MEMORY.md`. |
| [memory.md](memory.md) | Память transcript, долговременная память фактов, форматы JSONL и инструменты памяти. |
| [tools.md](tools.md) | Реестр инструментов, поток tool-call, capability gates и модель безопасности файловой системы. |
| [channels.md](channels.md) | CLI, интерактивный REPL, Telegram polling, WebSocket-канал UI, heartbeat и поведение daemon. |
| [security.md](security.md) | Границы возможностей, безопасность локальных файлов, обработка ключей провайдера и threat model. |
| [benchmarks.md](benchmarks.md) | Размер бинарника, запуск, RAM, тесты, количество исходников и команды воспроизведения. |
| [localization.md](localization.md) | Правила письма для перевода и ожидаемая структура многоязычной документации. |
| [development.md](development.md) | Команды сборки и тестов, проектные соглашения и рецепты расширения. |

## Порядок чтения

1. Начните с [README](../../README.md) в корне репозитория для общего обзора.
2. Используйте [installation.md](installation.md), чтобы установить release binary или подготовить Zig для source build.
3. Следуйте [getting-started.md](getting-started.md), чтобы настроить и запустить проект.
4. Прочитайте [configuration.md](configuration.md) перед использованием реального ключа провайдера.
5. Прочитайте [context.md](context.md), [memory.md](memory.md) и [tools.md](tools.md) перед включением локальных возможностей.
6. Прочитайте [security.md](security.md) перед запуском в чувствительном каталоге.
7. Прочитайте [architecture.md](architecture.md) и [development.md](development.md), когда меняете код.
8. Прочитайте [localization.md](localization.md) перед переводом документации.

## Краткое описание дизайна

`nllclw` держит пользовательские каналы, композицию runtime, логику агента,
разрешение провайдера, память, инструменты и stdlib-адаптеры в отдельных
модулях. Сборка по умолчанию использует во время выполнения только Zig и
стандартную библиотеку Zig.
