# Documentação do nllclw em português

O README do repositório é o ponto de entrada rápido. Estes documentos cobrem
instalação, operação, segurança e desenvolvimento com mais detalhes.

| Documento | Objetivo |
|---|---|
| [installation.md](installation.md) | Instale primeiro um binário de release, ou instale Zig `0.16.0` ao compilar a partir do source. |
| [getting-started.md](getting-started.md) | Configure um provedor e execute o assistente a partir de um binário de release ou de um build do source. |
| [architecture.md](architecture.md) | Limites do sistema, fluxos de requisição, mapa de módulos e forma da API pública. |
| [configuration.md](configuration.md) | Todas as chaves de configuração, comportamento de `config.json` e `.env`, presets de provedores e regras de validação. |
| [context.md](context.md) | Arquivos de contexto do assistente, como `SOUL.md`, `AGENTS.md` e `MEMORY.md`. |
| [memory.md](memory.md) | Memória de transcript, memória durável de fatos, formatos JSONL e ferramentas de memória. |
| [tools.md](tools.md) | Registro de ferramentas, fluxo tool-call, capability gates e modelo de segurança do sistema de arquivos. |
| [channels.md](channels.md) | CLI, REPL interativo, polling do Telegram, canal WebSocket de UI, heartbeat e comportamento daemon. |
| [security.md](security.md) | Limites de capacidades, segurança de arquivos locais, tratamento de chaves de provedor e threat model. |
| [benchmarks.md](benchmarks.md) | Tamanho do binário, inicialização, RAM, testes, contagens de fontes e comandos de reprodução. |
| [localization.md](localization.md) | Regras de escrita prontas para tradução e layout esperado da documentação multilíngue. |
| [development.md](development.md) | Comandos de build/teste, convenções do projeto e receitas de extensão. |

## Ordem de leitura

1. Comece pelo [README](../../README.md) do repositório para a visão geral do projeto.
2. Use [installation.md](installation.md) para instalar o binário de release ou preparar Zig para builds a partir do source.
3. Siga [getting-started.md](getting-started.md) para configurar e executar.
4. Leia [configuration.md](configuration.md) antes de usar uma chave real de provedor.
5. Leia [context.md](context.md), [memory.md](memory.md) e [tools.md](tools.md) antes de habilitar capacidades locais.
6. Leia [security.md](security.md) antes de executar em um diretório sensível.
7. Leia [architecture.md](architecture.md) e [development.md](development.md) ao modificar o código.
8. Leia [localization.md](localization.md) antes de traduzir a documentação.

## Resumo do design

`nllclw` mantém canais voltados ao usuário, composição do runtime, lógica do
agente, resolução de provedor, memória, ferramentas e adaptadores stdlib em
módulos separados. O build padrão usa apenas Zig e a biblioteca padrão do Zig em
tempo de execução.
