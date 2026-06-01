# Assistant Context Files

`nllclw` current working directory से local markdown instruction files load कर
सकता है और उन्हें system prompt में append कर सकता है। इससे repository या project
को identity, operating rules, user preferences, tool policy और heartbeat tasks
define करने का lightweight तरीका मिलता है।

यह `skills/*.md` files भी index करता है। Skills compact summary के रूप में
advertised होते हैं; full file बाद में `read_file` से केवल तब loaded होती है जब
task उससे match करता है। हर summary line inline title और description cap करती है
ताकि large skill file system prompt index पर dominate न कर सके।

## Load Order

Files present हों तो इस order में loaded होते हैं:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. `skills/*.md` summary, filename से sorted

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

Files trusted local instructions के रूप में treat होते हैं। वे remote service से
fetch नहीं होते।

हर context file valid UTF-8 markdown होना चाहिए, binary control bytes के बिना,
और 16 KiB से बड़ा नहीं होना चाहिए। Invalid bytes provider JSON में embed होने के
bajay startup fail कर देते हैं। Skill files भी valid UTF-8 markdown, binary control
bytes के बिना, और 8 KiB से अधिक नहीं होनी चाहिए।

## Runtime Persona

`NLLCLW_PERSONA` और `/persona` system prompt में छोटी final style instruction जोड़ते
हैं। Supported modes:

- `neutral`: direct और balanced;
- `friendly`: warm लेकिन concise;
- `technical`: precise, assumption-aware engineering tone;
- `witty`: usefulness छोड़े बिना light wit।

Persona केवल presentation control करता है। यह `SOUL.md`, `TOOLS.md`, memory
policy, safety boundaries या provider configuration override नहीं करता।

## File Roles

| File | Role |
|---|---|
| `IDENTITY.md` | Stable assistant identity और high-level project role। |
| `SOUL.md` | Behavioral constitution: tone, priorities और non-negotiable rules। |
| `USER.md` | Private local user preferences। Git द्वारा ignored। |
| `AGENTS.md` | Coding agents के साथ shared canonical repository-level instructions। |
| `MEMORY.md` | Human-maintained long-term notes। JSONL runtime memory से अलग। |
| `TOOLS.md` | Human-readable tool policy और available capability notes। |
| `HEARTBEAT.md` | `nllclw heartbeat` और daemon mode के लिए local recurring work/task source। |
| `BOOTSTRAP.md` | Private local startup/bootstrap notes। Git द्वारा ignored। |
| `skills/*.md` | Compact skill index के रूप में advertised optional task-specific instructions। |

Separate tool-specific instruction files maintain करने के बजाय shared agent
guidance के लिए `AGENTS.md` इस्तेमाल करें।

## Runtime Memory vs Markdown Memory

दो अलग concepts हैं:

| Mechanism | File | Written by | Purpose |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humans या normal file edits | Curated project/user notes जो system prompt में शामिल होते हैं। |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Recent user/assistant turns जो chat history के रूप में भेजे जाते हैं। |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts जिन्हें model store या recall कर सकता है। |

JSONL memory systems के लिए [memory.md](memory.md) देखें।

## Trust Model

Context files assistant को steer कर सकते हैं। Untrusted directory में `nllclw` न
चलाएँ जब तक आप उन files को prompt influence करने देने के लिए तैयार न हों।

Recommended practice:

- shared project instructions जैसे `IDENTITY.md`, `SOUL.md`, `AGENTS.md`,
  `MEMORY.md`, और `TOOLS.md` commit करें;
- private local preference files को `USER.md` और `BOOTSTRAP.md` रखें;
- सभी context files में secrets से बचें।

## Heartbeat Tasks

`HEARTBEAT.md` context file भी है और local task source भी। Heartbeat parser
conservative है: केवल unchecked markdown tasks और `TODO:` lines prompts बनते हैं।

Example:

```md
- [ ] Review pending schedule items.
TODO: Summarize new memory facts.
```

एक heartbeat pass चलाएँ:

```sh
nllclw heartbeat
```

Due schedules के साथ heartbeat repeatedly चलाएँ:

```sh
nllclw daemon
```

## Skills

`skills/` के अंदर markdown files बनाएँ:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

Startup पर, `nllclw` इस तरह का summary जोड़ता है:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

Full skill local रहता है और केवल तब read होता है जब model तय करता है कि वह relevant
है और file-read tools enabled हैं।

Skill filenames और contents valid UTF-8 markdown होने चाहिए, binary control bytes
के बिना। Skill summaries title और description whitespace को एक compact line में
collapse करते हैं। Hidden files, non-`.md` files, nested paths और 32 से अधिक skill
files ignored हैं।
