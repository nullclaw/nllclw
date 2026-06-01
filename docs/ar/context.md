# Assistant Context Files

يمكن ل`nllclw` تحميل ملفات تعليمات markdown محلية من current working directory
وإضافتها إلى system prompt. يمنح ذلك repository أو project طريقة خفيفة لتعريف
identity وoperating rules وuser preferences وtool policy وheartbeat tasks.

كما يفهرس ملفات `skills/*.md`. تُعلن skills كcompact summary؛ ولا يُحمّل full file
لاحقاً عبر `read_file` إلا عندما يطابقه task. تحد كل summary line من inline title
وdescription حتى لا يستطيع skill file كبير السيطرة على system prompt index.

## Load Order

تُحمّل الملفات بهذا الترتيب عندما تكون موجودة:

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

تُعامل الملفات كtrusted local instructions. لا تُجلب من remote service.

يجب أن يكون كل context file valid UTF-8 markdown بلا binary control bytes ولا يزيد
على 16 KiB. تؤدي invalid bytes إلى فشل startup بدلاً من embed داخل provider JSON.
يجب أن تكون skill files أيضاً valid UTF-8 markdown بلا binary control bytes ولا
تزيد على 8 KiB.

## Runtime Persona

يضيف `NLLCLW_PERSONA` و`/persona` final style instruction صغيرة إلى system prompt.
Supported modes:

- `neutral`: direct and balanced;
- `friendly`: warm but concise;
- `technical`: precise, assumption-aware engineering tone;
- `witty`: light wit without sacrificing usefulness.

يتحكم persona في presentation فقط. لا يoverride `SOUL.md` أو `TOOLS.md` أو memory
policy أو safety boundaries أو provider configuration.

## File Roles

| File | Role |
|---|---|
| `IDENTITY.md` | Stable assistant identity وhigh-level project role. |
| `SOUL.md` | Behavioral constitution: tone وpriorities وnon-negotiable rules. |
| `USER.md` | Private local user preferences. Ignored by git. |
| `AGENTS.md` | Canonical repository-level instructions shared with coding agents. |
| `MEMORY.md` | Human-maintained long-term notes. منفصل عن JSONL runtime memory. |
| `TOOLS.md` | Human-readable tool policy وavailable capability notes. |
| `HEARTBEAT.md` | Local recurring work/task source ل`nllclw heartbeat` وdaemon mode. |
| `BOOTSTRAP.md` | Private local startup/bootstrap notes. Ignored by git. |
| `skills/*.md` | Optional task-specific instructions advertised as a compact skill index. |

استخدم `AGENTS.md` لإرشادات agent المشتركة بدلاً من الحفاظ على ملفات تعليمات منفصلة
خاصة بكل tool.

## Runtime Memory vs Markdown Memory

هناك مفهومان منفصلان:

| Mechanism | File | Written by | Purpose |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humans أو normal file edits | Curated project/user notes مضافة إلى system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Recent user/assistant turns مرسلة كchat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts يستطيع model store أو recall لها. |

راجع [memory.md](memory.md) لأنظمة JSONL memory.

## Trust Model

يمكن لcontext files توجيه assistant. لا تشغل `nllclw` في untrusted directory إلا
إذا كنت مستعداً للسماح لتلك الملفات بالتأثير على prompt.

Recommended practice:

- commit shared project instructions مثل `IDENTITY.md` و`SOUL.md` و`AGENTS.md`
  و`MEMORY.md` و`TOOLS.md`;
- أبق private local preference files مثل `USER.md` و`BOOTSTRAP.md`;
- تجنب secrets في كل context files.

## Heartbeat Tasks

`HEARTBEAT.md` هو context file وlocal task source معاً. Heartbeat parser محافظ:
فقط unchecked markdown tasks و`TODO:` lines تتحول إلى prompts.

Example:

```md
- [ ] Review pending schedule items.
TODO: Summarize new memory facts.
```

شغّل heartbeat pass واحداً:

```sh
nllclw heartbeat
```

شغّل heartbeat مراراً مع due schedules:

```sh
nllclw daemon
```

## Skills

أنشئ markdown files داخل `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

عند startup، يضيف `nllclw` summary مثل:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

يبقى full skill محلياً ولا يُقرأ إلا عندما يقرر model أنه relevant وتكون file-read
tools enabled.

يجب أن تكون skill filenames وcontents valid UTF-8 markdown بلا binary control
bytes. تضغط skill summaries whitespace في title وdescription إلى compact line واحدة.
تُتجاهل hidden files وnon-`.md` files وnested paths وأكثر من 32 skill files.
