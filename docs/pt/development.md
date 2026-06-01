# Desenvolvimento

Comandos e convenções para alterar o `nllclw`.

## Requisitos

- Zig `0.16.0`
- Nenhuma dependência de pacote além da Zig stdlib

Verifique os metadados do pacote:

```sh
cat build.zig.zon
```

## Comandos de build

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

Verificações release cross-target usadas pelo projeto:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Comandos de teste

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

A etapa de teste padrão cobre:

- o módulo público do pacote;
- o módulo executable;
- `src/all_tests.zig`, que importa módulos internos para cobertura de
  compilação e comportamento.

Antes de devolver alterações, execute o gate local completo:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

## Métricas

Tamanho do binário, inicialização, RAM, contagens de testes, contagens de fontes
e comandos de reprodução estão documentados em [benchmarks.md](benchmarks.md).

## Adicionar um preset de provedor

Presets de provedores ficam em `src/providers.zig`.

Checklist:

1. Adicione uma enum tag de `ProviderKind`.
2. Adicione parsing de configuração em `src/config/resolve.zig`.
3. Resolva endpoint e headers em `src/providers.zig`.
4. Adicione testes para endpoint, headers, configuração inválida e header
   injection.
5. Documente o provedor em [configuration.md](configuration.md).

Mantenha o corpo da requisição provider-neutral, exceto quando o provedor ainda
for compatível com o contrato mínimo Chat Completions.

## Adicionar um canal

Canais pertencem a `src/channels/` quando são orquestração voltada ao usuário.

Checklist:

1. Mantenha parsing e I/O no módulo do canal.
2. Use `runtime.Runtime` para configuração, HTTP, memória, ferramentas e
   completions.
3. Evite lógica direta de provedor ou sistema de arquivos no canal, exceto
   quando for estado específico do canal, como offsets do Telegram.
4. Adicione texto de comando/ajuda em `src/channels/cli.zig` se o canal for
   lançado pelo executable principal.
5. Coloque wire parsing/formatting reutilizável em um módulo de protocolo
   irmão quando o canal tiver uma superfície de protocolo, como WebSocket faz em
   `src/websocket.zig`.
6. Adicione testes para reconhecimento de comandos, parsing de protocolo e
   mapeamento de erros.
7. Documente o canal em [channels.md](channels.md).

## Adicionar uma ferramenta

Ferramentas pertencem a `src/tools/` e são registradas em
`src/tools/catalog.zig`. Veja [tools.md](tools.md) para o checklist completo de
ferramentas.

A versão curta:

- defina um `chat.ToolDefinition`;
- faça parse dos argumentos com `std.json`;
- retorne texto UTF-8 owned;
- limite a saída;
- coloque capacidades de estado local atrás de flags de configuração
  explícitos;
- teste comportamento positivo e negativo.

## Adicionar armazenamento de memória

O domínio de memória fica em `src/memory.zig`; o armazenamento concreto fica em
`src/adapters/`.

Para adicionar outro storage backend:

1. Implemente `memory.TranscriptStore` e/ou `memory.FactStore`.
2. Mantenha detalhes de arquivo/banco de dados/rede específicos do backend fora
   de `memory.zig`.
3. Conecte o backend em `runtime.zig`.
4. Adicione adapter tests para malformed data, bounds, duplicate keys e
   deletion.

## Regras de documentação

- Mantenha `README.md` estruturado, prático e útil para aprender.
- Mantenha a documentação longa em inglês em `docs/en/`.
- Mantenha `docs/README.md` como índice de idiomas e liste apenas idiomas com
  ponto de entrada real.
- Coloque traduções do README em arquivos separados, como `README.ru.md`.
- Preserve a ordem de seções do README inglês nos README traduzidos.
- Use diagramas Mermaid para que o GitHub os renderize nativamente.
- Toda nova capacidade runtime precisa de documentação de configuração e notas
  de segurança.
- Todo novo comando deve aparecer no README ou em [channels.md](channels.md).
- Toda nova docs page deve ser vinculada pelo [English docs hub](README.md) e,
  quando voltada ao usuário, pelo [README](../../README.md) raiz.
- Siga [localization.md](localization.md) para escrita pronta para tradução.
