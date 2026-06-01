# File konteks asisten

`nllclw` dapat memuat file instruksi markdown lokal dari direktori kerja saat
ini dan menambahkannya ke system prompt. Ini memberi repositori atau proyek cara
ringan untuk mendefinisikan identity, operating rules, user preferences, tool
policy, dan heartbeat tasks.

Ia juga mengindeks file `skills/*.md`. Skills diiklankan sebagai ringkasan
ringkas; file lengkap dimuat nanti melalui `read_file` hanya saat suatu task
cocok dengannya. Setiap summary line membatasi inline title dan description agar
file skill besar tidak dapat mendominasi system prompt index.

## Urutan load

File dimuat dalam urutan ini jika ada:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. summary `skills/*.md`, diurutkan berdasarkan filename

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

File diperlakukan sebagai trusted local instructions. File tersebut tidak
diambil dari remote service.

Setiap context file harus berupa markdown UTF-8 valid tanpa binary control bytes
dan tidak lebih dari 16 KiB. Bytes invalid membuat startup gagal alih-alih
disematkan ke provider JSON. Skill files juga harus berupa markdown UTF-8 valid
tanpa binary control bytes dan tidak lebih dari 8 KiB.

## Runtime Persona

`NLLCLW_PERSONA` dan `/persona` menambahkan instruksi style final kecil ke
system prompt. Mode yang didukung:

- `neutral`: langsung dan seimbang;
- `friendly`: hangat tetapi ringkas;
- `technical`: nada engineering presisi dan sadar asumsi;
- `witty`: humor ringan tanpa mengorbankan kegunaan.

Persona hanya mengontrol presentasi. Ini tidak menggantikan `SOUL.md`,
`TOOLS.md`, memory policy, safety boundaries, atau provider configuration.

## Peran file

| File | Peran |
|---|---|
| `IDENTITY.md` | Stable assistant identity dan high-level project role. |
| `SOUL.md` | Behavioral constitution: tone, priorities, dan non-negotiable rules. |
| `USER.md` | Private local user preferences. Diabaikan oleh git. |
| `AGENTS.md` | Canonical repository-level instructions yang dibagikan dengan coding agents. |
| `MEMORY.md` | Human-maintained long-term notes. Terpisah dari JSONL runtime memory. |
| `TOOLS.md` | Human-readable tool policy dan catatan capability tersedia. |
| `HEARTBEAT.md` | Sumber local recurring work/task untuk `nllclw heartbeat` dan daemon mode. |
| `BOOTSTRAP.md` | Private local startup/bootstrap notes. Diabaikan oleh git. |
| `skills/*.md` | Optional task-specific instructions yang diiklankan sebagai compact skill index. |

Gunakan `AGENTS.md` untuk shared agent guidance alih-alih memelihara file
instruksi khusus tool yang terpisah.

## Runtime Memory versus Markdown Memory

Ada dua konsep berbeda:

| Mekanisme | File | Ditulis oleh | Tujuan |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Manusia atau edit file normal | Curated project/user notes yang disertakan dalam system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Turn user/assistant terbaru yang dikirim sebagai chat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts yang dapat disimpan atau diingat model. |

Lihat [memory.md](memory.md) untuk sistem memory JSONL.

## Trust Model

Context files dapat mengarahkan asisten. Jangan menjalankan `nllclw` di
direktori yang tidak dipercaya kecuali Anda bersedia membiarkan file tersebut
mempengaruhi prompt.

Praktik yang disarankan:

- commit shared project instructions seperti `IDENTITY.md`, `SOUL.md`,
  `AGENTS.md`, `MEMORY.md`, dan `TOOLS.md`;
- simpan private local preference files sebagai `USER.md` dan `BOOTSTRAP.md`;
- hindari secrets di semua context files.

## Heartbeat Tasks

`HEARTBEAT.md` adalah context file sekaligus sumber task lokal. Heartbeat parser
konservatif: hanya unchecked markdown tasks dan baris `TODO:` yang menjadi
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

Buat file markdown di bawah `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

Saat startup, `nllclw` menambahkan summary seperti:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

Skill lengkap tetap lokal dan hanya dibaca ketika model memutuskan skill
tersebut relevan dan file-read tools aktif.

Skill filenames and contents harus berupa markdown UTF-8 valid tanpa binary
control bytes. Skill summaries memadatkan whitespace title dan description
menjadi satu baris ringkas. Hidden files, non-`.md` files, nested paths, dan
lebih dari 32 skill files diabaikan.
