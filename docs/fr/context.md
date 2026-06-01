# Fichiers de contexte de l'assistant

`nllclw` peut charger des fichiers markdown d'instructions locaux depuis le
répertoire de travail courant et les ajouter au system prompt. Cela donne à un
dépôt ou projet une façon légère de définir l'identité, les règles
d'exploitation, les préférences utilisateur, la politique d'outils et les tâches
heartbeat.

Il indexe aussi les fichiers `skills/*.md`. Les skills sont annoncées comme un
résumé compact; le fichier complet est chargé plus tard via `read_file`
seulement lorsqu'une tâche lui correspond. Chaque summary line plafonne le titre
et la description inline afin qu'un grand skill file ne puisse pas dominer
l'index du system prompt.

## Ordre de chargement

Les fichiers sont chargés dans cet ordre lorsqu'ils sont présents:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. résumé `skills/*.md`, trié par filename

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

Les fichiers sont traités comme trusted local instructions. Ils ne sont pas
récupérés depuis un service distant.

Chaque context file doit être un markdown UTF-8 valide sans binary control bytes
et ne pas dépasser 16 KiB. Des bytes invalides font échouer le startup au lieu
d'être incorporés dans le provider JSON. Les skill files doivent aussi être du
markdown UTF-8 valide sans binary control bytes et ne pas dépasser 8 KiB.

## Runtime Persona

`NLLCLW_PERSONA` et `/persona` ajoutent une petite instruction finale de style
au system prompt. Les modes pris en charge sont:

- `neutral`: direct et équilibré;
- `friendly`: chaleureux mais concis;
- `technical`: ton d'ingénierie précis et attentif aux hypothèses;
- `witty`: esprit léger sans sacrifier l'utilité.

Persona contrôle uniquement la présentation. Elle ne remplace pas `SOUL.md`,
`TOOLS.md`, memory policy, safety boundaries ou provider configuration.

## Rôles des fichiers

| Fichier | Rôle |
|---|---|
| `IDENTITY.md` | Identité stable de l'assistant et high-level project role. |
| `SOUL.md` | Constitution comportementale: ton, priorités et règles non négociables. |
| `USER.md` | Préférences utilisateur locales privées. Ignoré par git. |
| `AGENTS.md` | Instructions canoniques de niveau dépôt partagées avec les coding agents. |
| `MEMORY.md` | Notes long-term maintenues par des humains. Séparées de JSONL runtime memory. |
| `TOOLS.md` | Politique d'outils lisible par les humains et notes sur les capacités disponibles. |
| `HEARTBEAT.md` | Source locale de travail/tâches récurrentes pour `nllclw heartbeat` et daemon mode. |
| `BOOTSTRAP.md` | Notes privées locales de startup/bootstrap. Ignoré par git. |
| `skills/*.md` | Instructions optionnelles task-specific annoncées comme compact skill index. |

Utilisez `AGENTS.md` pour le shared agent guidance au lieu de maintenir des
fichiers d'instructions séparés par outil.

## Runtime Memory et Markdown Memory

Il existe deux concepts distincts:

| Mécanisme | Fichier | Écrit par | Objectif |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humains ou edits de fichier normaux | Notes curated de projet/utilisateur incluses dans le system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Tours user/assistant récents envoyés comme chat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts que le modèle peut stocker ou rappeler. |

Voir [memory.md](memory.md) pour les systèmes de mémoire JSONL.

## Trust Model

Les context files peuvent orienter l'assistant. N'exécutez pas `nllclw` dans un
répertoire non fiable sauf si vous acceptez que ces fichiers influencent le
prompt.

Pratique recommandée:

- commit shared project instructions comme `IDENTITY.md`, `SOUL.md`,
  `AGENTS.md`, `MEMORY.md` et `TOOLS.md`;
- gardez les private local preference files comme `USER.md` et `BOOTSTRAP.md`;
- évitez les secrets dans tous les context files.

## Heartbeat Tasks

`HEARTBEAT.md` est à la fois un context file et une source de tâches locale. Le
heartbeat parser est conservateur: seules les unchecked markdown tasks et les
lignes `TODO:` deviennent des prompts.

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

Créez des fichiers markdown sous `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

Au startup, `nllclw` ajoute un résumé comme:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

La skill complète reste locale et n'est lue que lorsque le modèle décide qu'elle
est pertinente et que les file-read tools sont activés.

Les skill filenames et contents doivent être du markdown UTF-8 valide sans
binary control bytes. Les skill summaries réduisent les whitespaces du titre et
de la description en une seule ligne compacte. Les hidden files, non-`.md`
files, nested paths et plus de 32 skill files sont ignorés.
