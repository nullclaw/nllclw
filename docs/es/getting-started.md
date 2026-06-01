# Primeros pasos

Instala, configura y ejecuta `nllclw`. Para la mayoría de usuarios, el primer
paso es descargar el último release binary en lugar de compilar desde source.

## Requisitos

- Un release binary de `nllclw` desde
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest), o Zig
  `0.16.0` y Git si vas a compilar desde source.
- Acceso al proveedor: una clave de API cloud, o un servidor local
  OpenAI-compatible como Ollama.

Mientras el repositorio sea privado, las descargas de releases requieren acceso
a `nullclaw/nllclw`.

Referencias oficiales:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## Instalar nllclw

Descarga el último release asset para tu OS y CPU, extráelo y comprueba el
binary:

```sh
./nllclw --help
```

En macOS/Linux, hazlo executable primero si hace falta:

```sh
chmod +x nllclw
```

## Compilar desde source

Omite esta sección cuando uses un release binary. Los source builds requieren
Zig `0.16.0`:

```sh
zig version
```

Las rutas de instalación detalladas para macOS, Linux, Windows, contenedores,
CI y shells host de ESP-IDF están en [installation.md](installation.md).

Clona y compila:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Compila el release binary pequeño:

```sh
zig build --release=small
```

Comprueba el binary:

```sh
./zig-out/bin/nllclw --help
```

Instálalo globalmente si quieres:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

En plataformas sin `/usr/local/bin` o BSD/GNU `install`, copia
`zig-out/bin/nllclw` a cualquier directorio en tu `PATH`.

## Configurar un proveedor

Ejecuta el wizard una vez:

```sh
nllclw init
```

El wizard usa numbered menus para provider, `max_tokens` opcional, estilo del
asistente, local capability profile, Telegram, WebSocket y configuración de web
search. Pulsa Enter para aceptar el default de un menú.

`nllclw` lee OS env primero, `config.json` en el user config directory segundo y
`.env` en el mismo directorio tercero. OS env sobrescribe file config, y
`config.json` sobrescribe `.env`. Para uso normal, prefiere el `config.json`
creado por `nllclw init`; usa OS env para overrides puntuales o CI. Usa
`nllclw init --env` solo si prefieres el formato `.env`.

Ejemplos manuales de `config.json`:

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

Atlas Cloud mediante el proveedor compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Modelo local con Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Para proveedores HTTP locales, solo se permiten hosts loopback exactos. `api_key`
es obligatorio para `nllclw`; Ollama acepta cualquier valor no vacío.

Referencia completa de configuración: [configuration.md](configuration.md).

Para eliminar archivos creados por el wizard y runtime state:

```sh
nllclw uninstall
```

## Ejecutar

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Si no has instalado el binario globalmente:

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

Sal del chat loop con:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` es el default, pero el default tool loop es non-streaming
porque tool calls deben parsearse antes de ejecutar local functions. Para pure
streaming chat, deshabilita tools:

```sh
NLLCLW_TOOLS=off
```

Deshabilita streaming explícitamente con:

```sh
NLLCLW_STREAM=off
```

## Persona

La persona por defecto es neutral. Elige un startup style con:

```sh
NLLCLW_PERSONA=technical
```

Cambia persona en direct CLI, REPL o Telegram con:

```sh
nllclw /persona friendly
```

Los modos soportados son `neutral`, `friendly`, `technical` y `witty`.

## Habilitar memoria

Transcript memory está habilitada por defecto:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory está disponible mediante el default local tool loop:

```sh
NLLCLW_MEMORY=on
```

Inspecciona local facts:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Detalles de memoria: [memory.md](memory.md).

## Herramientas

Local tools que no requieren external services están habilitadas por defecto:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Pon cualquiera de ellas en `off` para deshabilitar una capacidad.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo puede usarse como no-key Instant Answer fallback, pero no es una API
completa de web results:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Detalles de herramientas y notas de seguridad:
[tools.md](tools.md) y [security.md](security.md).

Crea reusable macro tools mediante el asistente:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Añade optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files se resumen en el system prompt y se cargan bajo demanda con
`read_file`.

## Telegram

Crea un bot con BotFather. Si habilitaste Telegram en `nllclw init`, inicia
polling justo después de que el wizard escriba la config:

```sh
nllclw telegram
```

Para configuración manual por env, define el bot token y un chat allowlisted.
La allowlist acepta un numeric chat id, un private-chat username o un public
chat username con o sin `@`:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Ejemplo de username allowlist:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

Telegram se niega a arrancar sin `NLLCLW_TELEGRAM_CHAT_ID`.
Después de startup, envía `/chatid` en Telegram para ver el numeric chat id y
available username fields.

Detalles de canales: [channels.md](channels.md).

## Canal WebSocket UI

Inicia un loopback WebSocket server para una custom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

Envía un JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds requieren un token explícito:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Para remote binds, autentica con `Authorization: Bearer change-me`. Query
tokens se aceptan solo en loopback binds.

Detalles del protocolo WebSocket: [channels.md](channels.md).

## Heartbeat y Daemon

Ejecuta un heartbeat pass desde `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

Ejecuta due schedules y heartbeat tasks repetidamente:

```sh
nllclw daemon
```

Settings útiles:

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Verificar el repositorio

Ejecuta los checks estándar:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
