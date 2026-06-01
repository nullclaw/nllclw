# Assistant Context Files

`nllclw` can load local markdown instruction files from the current working
directory and append them to the system prompt. This gives a repository or
project a lightweight way to define identity, operating rules, user preferences,
tool policy, and heartbeat tasks.

It also indexes `skills/*.md` files. Skills are advertised as a compact summary;
the full file is loaded later through `read_file` only when a task matches it.
Each summary line caps the inline title and description so a large skill file
cannot dominate the system prompt index.

## Load Order

Files are loaded in this order when present:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. `skills/*.md` summary, sorted by filename

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

The files are treated as trusted local instructions. They are not fetched from a
remote service.

Each context file must be valid UTF-8 markdown without binary control bytes and
no larger than 16 KiB. Invalid bytes fail startup instead of being embedded into
provider JSON. Skill files must also be valid UTF-8 markdown without binary
control bytes and no larger than 8 KiB.

## Runtime Persona

`NLLCLW_PERSONA` and `/persona` add a small final style instruction to the system
prompt. Supported modes are:

- `neutral`: direct and balanced;
- `friendly`: warm but concise;
- `technical`: precise, assumption-aware engineering tone;
- `witty`: light wit without sacrificing usefulness.

Persona controls presentation only. It does not override `SOUL.md`, `TOOLS.md`,
memory policy, safety boundaries, or provider configuration.

## File Roles

| File | Role |
|---|---|
| `IDENTITY.md` | Stable assistant identity and high-level project role. |
| `SOUL.md` | Behavioral constitution: tone, priorities, and non-negotiable rules. |
| `USER.md` | Private local user preferences. Ignored by git. |
| `AGENTS.md` | Canonical repository-level instructions shared with coding agents. |
| `MEMORY.md` | Human-maintained long-term notes. Separate from JSONL runtime memory. |
| `TOOLS.md` | Human-readable tool policy and available capability notes. |
| `HEARTBEAT.md` | Local recurring work/task source for `nllclw heartbeat` and daemon mode. |
| `BOOTSTRAP.md` | Private local startup/bootstrap notes. Ignored by git. |
| `skills/*.md` | Optional task-specific instructions advertised as a compact skill index. |

Use `AGENTS.md` for shared agent guidance instead of maintaining separate
tool-specific instruction files.

## Runtime Memory vs Markdown Memory

There are two distinct concepts:

| Mechanism | File | Written by | Purpose |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humans or normal file edits | Curated project/user notes included in the system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Recent user/assistant turns sent as chat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts that the model can store or recall. |

See [memory.md](memory.md) for the JSONL memory systems.

## Trust Model

Context files can steer the assistant. Do not run `nllclw` in an untrusted
directory unless you are willing to let those files influence the prompt.

Recommended practice:

- commit shared project instructions such as `IDENTITY.md`, `SOUL.md`,
  `AGENTS.md`, `MEMORY.md`, and `TOOLS.md`;
- keep private local preference files as `USER.md` and `BOOTSTRAP.md`;
- avoid secrets in all context files.

## Heartbeat Tasks

`HEARTBEAT.md` is both a context file and a local task source. The heartbeat
parser is conservative: only unchecked markdown tasks and `TODO:` lines become
prompts.

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

Create markdown files under `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

At startup, `nllclw` adds a summary like:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

The full skill stays local and is read only when the model decides it is
relevant and file-read tools are enabled.

Skill filenames and contents must be valid UTF-8 markdown without binary control
bytes. Skill summaries collapse title and description whitespace into a single
compact line. Hidden files, non-`.md` files, nested paths, and more than 32 skill
files are ignored.
