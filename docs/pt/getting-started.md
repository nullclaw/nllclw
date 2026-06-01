# Primeiros passos

Instale, configure e execute `nllclw`. Para a maioria dos usuários, o primeiro
passo é baixar o release binary mais recente em vez de compilar a partir do
source.

## Requisitos

- Um release binary de `nllclw` em
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest), ou Zig
  `0.16.0` e Git se você for compilar a partir do source.
- Acesso ao provedor: uma chave de API cloud, ou um servidor local
  OpenAI-compatible como Ollama.

Enquanto o repositório estiver private, release downloads exigem acesso a
`nullclaw/nllclw`.

Referências oficiais:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## Instalar nllclw

Baixe o release asset mais recente para seu OS e CPU, extraia e confira o
binary:

```sh
./nllclw --help
```

No macOS/Linux, torne-o executable primeiro se necessário:

```sh
chmod +x nllclw
```

## Compilar a partir do source

Ignore esta seção ao usar um release binary. Builds a partir do source exigem
Zig `0.16.0`:

```sh
zig version
```

Os caminhos de instalação detalhados para macOS, Linux, Windows, containers, CI
e shells host de ESP-IDF estão em [installation.md](installation.md).

Clone e compile:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Compile o release binary pequeno:

```sh
zig build --release=small
```

Confira o binary:

```sh
./zig-out/bin/nllclw --help
```

Instale globalmente se quiser:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

Em plataformas sem `/usr/local/bin` ou BSD/GNU `install`, copie
`zig-out/bin/nllclw` para qualquer diretório no seu `PATH`.

## Configurar um provedor

Execute o wizard uma vez:

```sh
nllclw init
```

O wizard usa numbered menus para provider, `max_tokens` opcional, assistant
style, local capability profile, Telegram, WebSocket e configuração de web
search. Pressione Enter para aceitar um menu default.

`nllclw` lê OS env primeiro, `config.json` no user config directory segundo e
`.env` no mesmo diretório terceiro. OS env sobrescreve file config, e
`config.json` sobrescreve `.env`. Para uso normal, prefira o `config.json` criado
por `nllclw init`; use OS env para overrides pontuais ou CI. Use
`nllclw init --env` somente se preferir o formato `.env`.

Exemplos manuais de `config.json`:

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

Atlas Cloud pelo provedor compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Modelo local Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Para provedores HTTP locais, apenas hosts loopback exatos são permitidos. `api_key`
é exigido pelo `nllclw`; Ollama aceita qualquer valor não vazio.

Referência completa de configuração: [configuration.md](configuration.md).

Para remover arquivos criados pelo wizard e runtime state:

```sh
nllclw uninstall
```

## Executar

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Se você não instalou o binário globalmente:

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

Saia do chat loop com:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` é o default, mas o default tool loop é non-streaming porque
tool calls precisam ser parseadas antes que local functions sejam executadas.
Para pure streaming chat, desabilite tools:

```sh
NLLCLW_TOOLS=off
```

Desabilite streaming explicitamente com:

```sh
NLLCLW_STREAM=off
```

## Persona

A persona padrão é neutral. Escolha um startup style com:

```sh
NLLCLW_PERSONA=technical
```

Altere persona em direct CLI, REPL ou Telegram com:

```sh
nllclw /persona friendly
```

Os modos suportados são `neutral`, `friendly`, `technical` e `witty`.

## Habilitar memória

Transcript memory é ligada por padrão:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory fica disponível pelo default local tool loop:

```sh
NLLCLW_MEMORY=on
```

Inspecione local facts:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Detalhes de memória: [memory.md](memory.md).

## Ferramentas

Local tools que não exigem external services são habilitadas por padrão:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Defina qualquer uma delas como `off` para desabilitar uma capability.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo pode ser usado como no-key Instant Answer fallback, mas não é uma API
completa de web results:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Detalhes de ferramentas e notas de segurança:
[tools.md](tools.md) e [security.md](security.md).

Crie reusable macro tools pelo assistente:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Adicione optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Skill files são resumidos no system prompt e carregados sob demanda com
`read_file`.

## Telegram

Crie um bot com BotFather. Se você habilitou Telegram em `nllclw init`, inicie
polling imediatamente depois que o wizard escrever a config:

```sh
nllclw telegram
```

Para configuração manual via env, defina o bot token e um chat allowlisted. A
allowlist aceita um numeric chat id, um private-chat username ou um public chat
username com ou sem `@`:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Exemplo de username allowlist:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

Telegram se recusa a iniciar sem `NLLCLW_TELEGRAM_CHAT_ID`.
Depois do startup, envie `/chatid` no Telegram para ver o numeric chat id e
available username fields.

Detalhes dos canais: [channels.md](channels.md).

## Canal WebSocket UI

Inicie um loopback WebSocket server para uma custom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

Envie um JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Remote binds exigem um token explícito:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Para remote binds, autentique com `Authorization: Bearer change-me`. Query
tokens são aceitos apenas em loopback binds.

Detalhes do protocolo WebSocket: [channels.md](channels.md).

## Heartbeat e Daemon

Execute um heartbeat pass a partir de `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

Execute due schedules e heartbeat tasks repetidamente:

```sh
nllclw daemon
```

Settings úteis:

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Verificar o repositório

Execute as verificações padrão:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
