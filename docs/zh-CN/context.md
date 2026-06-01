# Assistant context files

`nllclw` 可以从当前工作目录加载本地 markdown instruction files，并将它们
追加到 system prompt。这为 repository 或 project 提供了一种轻量方式，用于
定义 identity、operating rules、user preferences、tool policy 和 heartbeat
tasks。

它还会索引 `skills/*.md` files。Skills 会以紧凑 summary 的形式公布；只有当
某个 task 匹配时，完整文件才会稍后通过 `read_file` 加载。每个 summary line
都会限制 inline title 和 description，避免大型 skill file 主导 system prompt
index。

## Load order

存在时，文件按以下顺序加载：

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. `skills/*.md` summary，按 filename 排序

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

这些文件被视为 trusted local instructions。它们不会从 remote service 获取。

每个 context file 都必须是 valid UTF-8 markdown，不含 binary control bytes，
且不大于 16 KiB。Invalid bytes 会导致 startup 失败，而不是嵌入 provider
JSON。Skill files 也必须是 valid UTF-8 markdown，不含 binary control bytes，
且不大于 8 KiB。

## Runtime persona

`NLLCLW_PERSONA` 和 `/persona` 会向 system prompt 添加一条小的最终 style
instruction。支持的 modes：

- `neutral`：直接且平衡；
- `friendly`：温暖但简洁；
- `technical`：精确、关注假设的 engineering tone；
- `witty`：轻微机智但不牺牲实用性。

Persona 只控制 presentation。它不会覆盖 `SOUL.md`、`TOOLS.md`、memory
policy、safety boundaries 或 provider configuration。

## File roles

| File | Role |
|---|---|
| `IDENTITY.md` | Stable assistant identity 和 high-level project role。 |
| `SOUL.md` | Behavioral constitution: tone、priorities 和 non-negotiable rules。 |
| `USER.md` | Private local user preferences。被 git 忽略。 |
| `AGENTS.md` | 与 coding agents 共享的 canonical repository-level instructions。 |
| `MEMORY.md` | Human-maintained long-term notes。与 JSONL runtime memory 分离。 |
| `TOOLS.md` | Human-readable tool policy 和 available capability notes。 |
| `HEARTBEAT.md` | `nllclw heartbeat` 和 daemon mode 的 local recurring work/task source。 |
| `BOOTSTRAP.md` | Private local startup/bootstrap notes。被 git 忽略。 |
| `skills/*.md` | Optional task-specific instructions，以 compact skill index 形式公布。 |

使用 `AGENTS.md` 保存 shared agent guidance，而不是维护单独的
tool-specific instruction files。

## Runtime memory vs Markdown memory

这里有两个不同概念：

| Mechanism | File | Written by | Purpose |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humans 或普通 file edits | 包含在 system prompt 中的 curated project/user notes。 |
| Transcript memory | user state dir `memory.jsonl` | Runtime | 作为 chat history 发送的最近 user/assistant turns。 |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Model 可以存储或 recall 的 durable key/value facts。 |

JSONL memory systems 见 [memory.md](memory.md)。

## Trust model

Context files 可以引导 assistant。除非你愿意让这些文件影响 prompt，否则不要
在不可信目录中运行 `nllclw`。

推荐做法：

- commit shared project instructions，例如 `IDENTITY.md`、`SOUL.md`、
  `AGENTS.md`、`MEMORY.md` 和 `TOOLS.md`；
- 将 private local preference files 保持为 `USER.md` 和 `BOOTSTRAP.md`；
- 避免在所有 context files 中放 secrets。

## Heartbeat tasks

`HEARTBEAT.md` 既是 context file，也是 local task source。Heartbeat parser
很保守：只有 unchecked markdown tasks 和 `TODO:` lines 会变成 prompts。

Example：

```md
- [ ] Review pending schedule items.
TODO: Summarize new memory facts.
```

Run one heartbeat pass：

```sh
nllclw heartbeat
```

Run heartbeat repeatedly with due schedules：

```sh
nllclw daemon
```

## Skills

在 `skills/` 下创建 markdown files：

```md
# Deploy
Use this skill for deployment checks and release verification.
```

Startup 时，`nllclw` 会添加类似这样的 summary：

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

完整 skill 保持本地，只在 model 认为相关且 file-read tools 已启用时读取。

Skill filenames and contents 必须是 valid UTF-8 markdown，不含 binary control
bytes。Skill summaries 会将 title 和 description whitespace 折叠成一条紧凑
line。Hidden files、non-`.md` files、nested paths 和超过 32 个 skill files 会被忽略。
