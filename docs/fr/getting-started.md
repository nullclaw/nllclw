# Bien démarrer

Installez, configurez et lancez `nllclw`. Pour la plupart des utilisateurs, la
première étape consiste à télécharger le dernier binaire de release plutôt qu'à
construire depuis les sources.

## Prérequis

- Un binaire de release `nllclw` depuis
  [GitHub Releases](https://github.com/nullclaw/nllclw/releases/latest), ou Zig
  `0.16.0` et Git si vous construisez depuis les sources.
- Accès au fournisseur: une clé d'API cloud, ou un serveur local
  OpenAI-compatible comme Ollama.

Tant que le dépôt est privé, les téléchargements de releases exigent l'accès à
`nullclaw/nllclw`.

Références officielles:

- [nllclw Releases](https://github.com/nullclaw/nllclw/releases/latest)
- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [Atlas Cloud LLM API](https://www.atlascloud.ai/docs/en/how-it-works)

## Installer nllclw

Téléchargez le dernier release asset pour votre OS et CPU, extrayez-le, puis
vérifiez le binaire:

```sh
./nllclw --help
```

Sur macOS/Linux, rendez-le d'abord exécutable si nécessaire:

```sh
chmod +x nllclw
```

## Construire depuis les sources

Ignorez cette section lorsque vous utilisez un binaire de release. Les builds
depuis les sources exigent Zig `0.16.0`:

```sh
zig version
```

Les chemins d'installation détaillés pour macOS, Linux, Windows, containers, CI
et shells hôtes ESP-IDF sont dans [installation.md](installation.md).

Clonez et construisez:

```sh
git clone https://github.com/nullclaw/nllclw.git
cd nllclw
zig build
```

Construisez le petit binaire de release:

```sh
zig build --release=small
```

Vérifiez le binaire:

```sh
./zig-out/bin/nllclw --help
```

Installez-le globalement si vous le souhaitez:

```sh
install -m 0755 zig-out/bin/nllclw /usr/local/bin/nllclw
```

Sur les plateformes sans `/usr/local/bin` ou BSD/GNU `install`, copiez
`zig-out/bin/nllclw` dans n'importe quel répertoire de votre `PATH`.

## Configurer un fournisseur

Exécutez le wizard une fois:

```sh
nllclw init
```

Le wizard utilise des numbered menus pour provider, `max_tokens` optionnel,
assistant style, local capability profile, Telegram, WebSocket et configuration
web search. Appuyez sur Entrée pour accepter un menu default.

`nllclw` lit d'abord OS env, puis `config.json` dans le user config directory,
puis `.env` dans le même répertoire. OS env override la file config, et
`config.json` override `.env`. Pour l'usage normal, préférez le `config.json`
créé par `nllclw init`; utilisez OS env pour des overrides ponctuels ou CI.
Utilisez `nllclw init --env` seulement si vous préférez le format `.env`.

Exemples manuels de `config.json`:

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

Atlas Cloud via le fournisseur compatible:

```json
{
  "provider": "compatible",
  "base_url": "https://api.atlascloud.ai/v1",
  "api_key": "atlas-cloud-api-key",
  "model": "deepseek-v3"
}
```

Modèle local Ollama:

```json
{
  "provider": "compatible",
  "base_url": "http://127.0.0.1:11434/v1",
  "allow_http_base_url": true,
  "api_key": "ollama",
  "model": "llama3.2"
}
```

Pour les fournisseurs HTTP locaux, seuls les hosts loopback exacts sont autorisés.
`api_key` est requis par `nllclw`; Ollama accepte toute valeur non vide.

Référence complète de configuration: [configuration.md](configuration.md).

Pour supprimer les fichiers créés par le wizard et le runtime state:

```sh
nllclw uninstall
```

## Exécuter

Direct prompt:

```sh
nllclw "summarize what this project does"
```

Si vous n'avez pas installé le binaire globalement:

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

Quittez la boucle chat avec:

```text
:q
:quit
exit
```

`NLLCLW_STREAM=on` est le default, mais le default tool loop est non-streaming
parce que les tool calls doivent être parsées avant l'exécution des local
functions. Pour du pure streaming chat, désactivez tools:

```sh
NLLCLW_TOOLS=off
```

Désactivez explicitement le streaming avec:

```sh
NLLCLW_STREAM=off
```

## Persona

La persona par défaut est neutral. Choisissez un startup style avec:

```sh
NLLCLW_PERSONA=technical
```

Changez de persona en direct CLI, REPL ou Telegram avec:

```sh
nllclw /persona friendly
```

Les modes pris en charge sont `neutral`, `friendly`, `technical` et `witty`.

## Activer la mémoire

Transcript memory est activée par défaut:

```sh
NLLCLW_MEMORY=on
# Default path: user state dir/memory.jsonl
NLLCLW_MEMORY_MAX_MESSAGES=20
```

Durable fact memory est disponible via le default local tool loop:

```sh
NLLCLW_MEMORY=on
```

Inspecter les local facts:

```sh
nllclw memory list
nllclw memory get project.goal
nllclw memory forget project.goal
nllclw memory reset
```

Détails mémoire: [memory.md](memory.md).

## Outils

Les local tools qui ne nécessitent pas de services externes sont activés par
défaut:

```sh
NLLCLW_TOOLS=on
NLLCLW_FILE_READ=on
NLLCLW_FILE_WRITE=on
NLLCLW_SCHEDULE_TOOLS=on
```

Définissez l'un de ces réglages sur `off` pour désactiver une capacité.

Web search:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=auto
NLLCLW_SEARCH_TAVILY_KEY=tvly-...
# or NLLCLW_SEARCH_BRAVE_KEY=...
# or NLLCLW_SEARCH_EXA_KEY=...
# or NLLCLW_SEARCH_FIRECRAWL_KEY=...
```

DuckDuckGo peut être utilisé comme no-key Instant Answer fallback, mais ce n'est
pas une API complète de web results:

```sh
NLLCLW_TOOLS=on
NLLCLW_SEARCH_PROVIDER=duckduckgo
```

Détails d'outils et notes de sécurité:
[tools.md](tools.md) et [security.md](security.md).

Créez des reusable macro tools via l'assistant:

```text
Create a tool named daily_brief that searches current project news and stores a concise summary.
```

Ajoutez des optional local skills:

```sh
mkdir -p skills
$EDITOR skills/deploy.md
```

Les skill files sont résumés dans le system prompt et chargés à la demande avec
`read_file`.

## Telegram

Créez un bot avec BotFather. Si vous avez activé Telegram dans `nllclw init`,
démarrez polling immédiatement après l'écriture de la config par le wizard:

```sh
nllclw telegram
```

Pour une configuration env manuelle, définissez le bot token et un chat
allowlisted. L'allowlist accepte un numeric chat id, un private-chat username ou
un public chat username avec ou sans `@`:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=123456789
NLLCLW_TELEGRAM_RATE_LIMIT_PER_MINUTE=20
nllclw telegram
```

Exemple username allowlist:

```sh
NLLCLW_TELEGRAM_TOKEN=123456:bot-token
NLLCLW_TELEGRAM_CHAT_ID=@donprus
nllclw telegram
```

Telegram refuse de démarrer sans `NLLCLW_TELEGRAM_CHAT_ID`.
Après startup, envoyez `/chatid` dans Telegram pour voir le numeric chat id et
les available username fields.

Détails des canaux: [channels.md](channels.md).

## Canal WebSocket UI

Démarrez un serveur WebSocket loopback pour une custom UI:

```sh
NLLCLW_WS_TOKEN=change-me nllclw websocket
```

Default endpoint:

```text
ws://127.0.0.1:8765/ws?token=change-me
```

Envoyez une JSON text frame:

```json
{ "type": "chat", "prompt": "what is nllclw?" }
```

Les remote binds exigent un token explicite:

```sh
env NLLCLW_WS_HOST=0.0.0.0 \
  NLLCLW_WS_ALLOW_REMOTE=on \
  NLLCLW_WS_TOKEN=change-me \
  nllclw websocket
```

Pour les remote binds, authentifiez avec `Authorization: Bearer change-me`. Les
query tokens ne sont acceptés que sur les loopback binds.

Détails du protocole WebSocket: [channels.md](channels.md).

## Heartbeat et Daemon

Exécutez un heartbeat pass depuis `HEARTBEAT.md`:

```sh
nllclw heartbeat
```

Exécutez due schedules et heartbeat tasks de façon répétée:

```sh
nllclw daemon
```

Settings utiles:

```sh
# Default path: user state dir/schedule.jsonl
NLLCLW_DAEMON_INTERVAL_SECONDS=60
NLLCLW_HEARTBEAT_INTERVAL_SECONDS=1800
NLLCLW_TIMEZONE_OFFSET_MINUTES=0
```

## Vérifier le dépôt

Exécutez les checks standard:

```sh
zig fmt --check build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```
