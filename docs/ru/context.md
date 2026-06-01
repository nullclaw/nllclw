# Файлы контекста ассистента

`nllclw` может загружать локальные markdown instruction files из текущего
рабочего каталога и добавлять их в system prompt. Это дает репозиторию или
проекту легкий способ определить identity, operating rules, user preferences,
tool policy и heartbeat tasks.

Он также индексирует файлы `skills/*.md`. Skills рекламируются как компактное
summary; полный файл позже загружается через `read_file` только когда task ему
соответствует. Каждая summary line ограничивает inline title и description,
чтобы большой skill file не мог доминировать в system prompt index.

## Порядок загрузки

Файлы загружаются в таком порядке, если присутствуют:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. summary `skills/*.md`, отсортированное по filename

```mermaid
flowchart LR
    Base["built-in system prompt"] --> Identity["IDENTITY.md"]
    Identity --> Soul["SOUL.md"]
    Soul --> User["USER.md"]
    User --> Agents["AGENTS.md"]
    Agents --> Memory["MEMORY.md"]
    Memory --> Tools["TOOLS.md"]
    Tools --> Heartbeat["HEARTBEAT.md"]
    Heartbeat --> Bootstrap["BOOTSTRAP.md"]
    Bootstrap --> Skills["skills/*.md summary"]
    Skills --> Persona["runtime persona"]
    Persona --> Final["final system prompt"]
```

Файлы считаются trusted local instructions. Они не загружаются из remote
service.

Каждый context file должен быть valid UTF-8 markdown без binary control bytes и
не больше 16 KiB. Invalid bytes приводят к failure startup вместо встраивания в
provider JSON. Skill files также должны быть valid UTF-8 markdown без binary
control bytes и не больше 8 KiB.

## Runtime Persona

`NLLCLW_PERSONA` и `/persona` добавляют небольшую финальную style instruction в
system prompt. Поддерживаемые modes:

- `neutral`: прямой и сбалансированный;
- `friendly`: теплый, но concise;
- `technical`: точный engineering tone с учетом assumptions;
- `witty`: легкая ирония без ущерба usefulness.

Persona управляет только presentation. Она не переопределяет `SOUL.md`,
`TOOLS.md`, memory policy, safety boundaries или provider configuration.

## Роли файлов

| Файл | Роль |
|---|---|
| `IDENTITY.md` | Stable assistant identity и high-level project role. |
| `SOUL.md` | Behavioral constitution: tone, priorities и non-negotiable rules. |
| `USER.md` | Private local user preferences. Игнорируется git. |
| `AGENTS.md` | Canonical repository-level instructions, shared with coding agents. |
| `MEMORY.md` | Human-maintained long-term notes. Отдельно от JSONL runtime memory. |
| `TOOLS.md` | Human-readable tool policy и available capability notes. |
| `HEARTBEAT.md` | Local recurring work/task source для `nllclw heartbeat` и daemon mode. |
| `BOOTSTRAP.md` | Private local startup/bootstrap notes. Игнорируется git. |
| `skills/*.md` | Optional task-specific instructions, advertised as compact skill index. |

Используйте `AGENTS.md` для shared agent guidance вместо поддержки отдельных
tool-specific instruction files.

## Runtime Memory и Markdown Memory

Есть два разных понятия:

| Механизм | Файл | Кто пишет | Назначение |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Люди или обычные file edits | Curated project/user notes, включенные в system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Последние user/assistant turns, отправляемые как chat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts, которые модель может сохранить или вспомнить. |

См. [memory.md](memory.md) для JSONL memory systems.

## Trust Model

Context files могут направлять ассистента. Не запускайте `nllclw` в
недоверенном каталоге, если не готовы позволить этим файлам влиять на prompt.

Рекомендуемая практика:

- commit shared project instructions, такие как `IDENTITY.md`, `SOUL.md`,
  `AGENTS.md`, `MEMORY.md` и `TOOLS.md`;
- держите private local preference files как `USER.md` и `BOOTSTRAP.md`;
- избегайте secrets во всех context files.

## Heartbeat Tasks

`HEARTBEAT.md` одновременно является context file и local task source. Heartbeat
parser консервативен: только unchecked markdown tasks и `TODO:` lines
становятся prompts.

Example:

```md
- [ ] Review pending schedule items.
TODO: Summarize new memory facts.
```

Run one heartbeat pass:

```sh
nllclw heartbeat
```

Run heartbeat repeatedly with due schedules:

```sh
nllclw daemon
```

## Skills

Создайте markdown files в `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

При startup `nllclw` добавляет summary вида:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

Full skill остается локальным и читается только когда модель решает, что он
релевантен, и file-read tools включены.

Skill filenames and contents должны быть valid UTF-8 markdown без binary
control bytes. Skill summaries сворачивают whitespace title и description в
одну compact line. Hidden files, non-`.md` files, nested paths и больше 32
skill files игнорируются.
