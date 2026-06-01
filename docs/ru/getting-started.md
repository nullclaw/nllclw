# Быстрый старт

Установите, настройте и запустите `nllclw`. Для большинства пользователей
первый шаг — скачать последний release binary, а не собирать из source.

## Требования

- Release binary `nllclw` из
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest), либо
  Zig `0.16.0` и Git, если вы собираете из source.
- Provider access: cloud API key или локальный OpenAI-compatible server вроде
  Ollama.

Пока repository private, downloads требуют доступ к `nullclaw/nllclw`.

Официальные ссылки:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## Установка nllclw

Скачайте последний release asset для вашей OS и CPU, распакуйте его и проверьте
binary:

```sh
./nllclw --help
```

На macOS/Linux сначала сделайте его executable, если нужно:

```sh
chmod +x nllclw
```

## Сборка из source

Пропустите этот раздел, если используете release binary. Source builds требуют
Zig `0.16.0`:

```sh
zig version
```

Подробные варианты установки для macOS, Linux, Windows, containers, CI и
ESP-IDF host shells описаны в [installation.md](installation.md).

Клонируйте и соберите:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Соберите маленький release binary:

```sh
zig build --release=small
```

Проверьте binary:

```sh
./zig-out/bin/nllclw --help
```

Установите глобально, если нужно:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

На платформах без `/usr/local/bin` или BSD/GNU `install` скопируйте
`zig-out/bin/nllclw` в любой directory из `PATH`.

## Настройка провайдера

Запустите wizard один раз. Используйте `./nllclw`, если binary не находится в
`PATH`:

```sh
nllclw init
```

Wizard использует numbered menus для provider, optional `max_tokens`,
assistant style, local capability profile, Telegram, WebSocket и настройки web
search. Нажмите Enter, чтобы принять default menu.

`nllclw` читает OS env первым, `config.json` в user config directory вторым и
`.env` в том же каталоге третьим. OS env переопределяет file config, а
`config.json` переопределяет `.env`. Для обычного использования предпочитайте
`config.json`, созданный `nllclw init`; OS env используйте для разовых override
или CI. Используйте `nllclw init --env` только если предпочитаете формат `.env`.

Примеры ручного `config.json`:

OpenRouter:

```json
{
  "provider": "openrouter",
  "api_key": "sk-or-...",
  "model": "openai/gpt-chat-latest"
}
```

OpenAI:

```json
{
  "provider": "openai",
  "api_key": "sk-...",
  "model": "gpt-4o"
}
```

Atlas Cloud через compatible provider:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Локальная модель Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Для локальных HTTP providers разрешены только точные loopback hosts. `api_key`
требуется `nllclw`; Ollama принимает любое непустое значение.

Полный справочник конфигурации: [configuration.md](configuration.md).

Чтобы удалить файлы, созданные wizard, и runtime state:

```sh
nllclw uninstall
```

## Запуск

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Если binary не установлен globally:

```sh
./zig-out/bin/nllclw "summarize what this project does"
```

Prompt from stdin:

```sh
printf 'what is nllclw?\n' | nllclw
```

Interactive terminal chat:

```sh
nllclw
```

Выйти из chat loop:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` является default, но default tool loop не streaming, потому
что tool calls нужно разобрать до запуска local functions. Для pure streaming
chat выключите tools:

```sh
NLLCLW_TOOLS=off
```

Выключить streaming явно:

```sh
NLLCLW_STREAM=off
```

## Persona

Default persona — neutral. Выберите startup style:

```sh
NLLCLW_PERSONA=technical
```

Переключить persona в direct CLI, REPL или Telegram:

```sh
nllclw /persona friendly
```

Поддерживаемые modes: `neutral`, `friendly`, `technical` и `witty`.

## Включение памяти

Transcript memory включена по умолчанию:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory доступна через default local tool loop:

```sh
NLLCLW_MEMORY=on
```

Просмотреть local facts:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Подробности о памяти: [memory.md](memory.md).

## Инструменты

Local tools, которым не нужны external services, включены по умолчанию:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Установите любой из этих флагов в `off`, чтобы выключить capability.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo можно использовать как no-key Instant Answer fallback, но это не
полный web results API:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Подробности об инструментах и заметки безопасности:
[tools.md](tools.md) и [security.md](security.md).

Создайте reusable macro tools через ассистента:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Добавьте optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files summarised in the system prompt and loaded on demand with
`read_file`.

## Telegram

Создайте bot через BotFather. Если вы включили Telegram в `nllclw init`,
запустите polling сразу после записи config wizard:

```sh
nllclw telegram
```

Для ручной env configuration задайте bot token и один allowlisted chat.
Allowlist принимает numeric chat id, private-chat username или public chat
username с `@` или без:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Пример username allowlist:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

Telegram отказывается запускаться без `NLLCLW_TELEGRAM_CHAT_ID`. После startup
отправьте `/chatid` в Telegram, чтобы увидеть numeric chat id и available
username fields.

Подробности о каналах: [channels.md](channels.md).

## WebSocket UI Channel

Запустите loopback WebSocket server для custom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

Отправьте JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds требуют явный token:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Для remote binds используйте authentication
`Authorization: Bearer change-me`. Query tokens принимаются только на loopback
binds.

Подробности протокола WebSocket: [channels.md](channels.md).

## Heartbeat и Daemon

Запустить один heartbeat pass из `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

Запускать due schedules и heartbeat tasks повторно:

```sh
nllclw daemon
```

Полезные settings:

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Проверка репозитория

Запустите стандартные checks:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
