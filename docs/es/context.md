# Archivos de contexto del asistente

`nllclw` puede cargar archivos markdown locales de instrucciones desde el
directorio de trabajo actual y anexarlos al system prompt. Esto da a un
repositorio o proyecto una forma ligera de definir identidad, reglas de
operación, preferencias de usuario, política de herramientas y tareas heartbeat.

También indexa archivos `skills/*.md`. Las skills se anuncian como un resumen
compacto; el archivo completo se carga después mediante `read_file` solo cuando
una tarea coincide con él. Cada línea de resumen limita el título inline y la
descripción para que un archivo skill grande no pueda dominar el índice del
system prompt.

## Orden de carga

Los archivos se cargan en este orden cuando están presentes:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. resumen `skills/*.md`, ordenado por filename

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

Los archivos se tratan como trusted local instructions. No se obtienen desde un
servicio remoto.

Cada context file debe ser markdown UTF-8 válido sin binary control bytes y no
mayor de 16 KiB. Bytes inválidos hacen fallar el startup en vez de incrustarse
en provider JSON. Los skill files también deben ser markdown UTF-8 válido sin
binary control bytes y no mayores de 8 KiB.

## Runtime Persona

`NLLCLW_PERSONA` y `/persona` añaden una pequeña instrucción final de estilo al
system prompt. Los modos soportados son:

- `neutral`: directo y equilibrado;
- `friendly`: cálido pero conciso;
- `technical`: tono de ingeniería preciso y atento a supuestos;
- `witty`: ingenio ligero sin sacrificar utilidad.

Persona controla solo la presentación. No sobreescribe `SOUL.md`, `TOOLS.md`,
memory policy, safety boundaries ni provider configuration.

## Roles de archivos

| Archivo | Rol |
|---|---|
| `IDENTITY.md` | Identidad estable del asistente y high-level project role. |
| `SOUL.md` | Constitución de comportamiento: tono, prioridades y reglas no negociables. |
| `USER.md` | Preferencias locales privadas del usuario. Ignorado por git. |
| `AGENTS.md` | Instrucciones canónicas de nivel repositorio compartidas con coding agents. |
| `MEMORY.md` | Notas long-term mantenidas por humanos. Separadas de JSONL runtime memory. |
| `TOOLS.md` | Política de herramientas legible por humanos y notas de capacidades disponibles. |
| `HEARTBEAT.md` | Fuente local de trabajo/tareas recurrentes para `nllclw heartbeat` y daemon mode. |
| `BOOTSTRAP.md` | Notas privadas locales de startup/bootstrap. Ignoradas por git. |
| `skills/*.md` | Instrucciones opcionales task-specific anunciadas como compact skill index. |

Usa `AGENTS.md` para shared agent guidance en vez de mantener archivos de
instrucción separados por herramienta.

## Runtime Memory frente a Markdown Memory

Hay dos conceptos distintos:

| Mecanismo | Archivo | Escrito por | Propósito |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humanos o ediciones normales de archivo | Notas curated de proyecto/usuario incluidas en el system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Turnos recientes user/assistant enviados como chat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts que el modelo puede guardar o recordar. |

Consulta [memory.md](memory.md) para los sistemas de memoria JSONL.

## Trust Model

Los context files pueden dirigir al asistente. No ejecutes `nllclw` en un
directorio no confiable salvo que estés dispuesto a dejar que esos archivos
influyan en el prompt.

Práctica recomendada:

- commit shared project instructions como `IDENTITY.md`, `SOUL.md`,
  `AGENTS.md`, `MEMORY.md` y `TOOLS.md`;
- mantén private local preference files como `USER.md` y `BOOTSTRAP.md`;
- evita secretos en todos los context files.

## Heartbeat Tasks

`HEARTBEAT.md` es tanto un context file como una fuente local de tareas. El
heartbeat parser es conservador: solo las unchecked markdown tasks y las líneas
`TODO:` se convierten en prompts.

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

Crea archivos markdown bajo `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

En startup, `nllclw` añade un resumen como:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

La skill completa permanece local y se lee solo cuando el modelo decide que es
relevante y las file-read tools están habilitadas.

Los skill filenames y contents deben ser markdown UTF-8 válido sin binary
control bytes. Los skill summaries colapsan whitespace de título y descripción
en una sola línea compacta. Hidden files, non-`.md` files, nested paths y más de
32 skill files se ignoran.
