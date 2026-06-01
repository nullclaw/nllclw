# Localização

O inglês é o idioma fonte da documentação do `nllclw`. Primeiro mantenha as
mudanças em inglês completas, depois traduza a partir dos arquivos ingleses
atuais.

## Layout de arquivos

| Caminho | Objetivo |
|---|---|
| `README.md` | Visão geral do projeto em inglês para GitHub. |
| `README.<locale>.md` | Arquivos README traduzidos opcionais na raiz. |
| `docs/README.md` | Índice de idiomas. |
| `docs/en/` | Documentação longa em inglês. |
| `docs/<locale>/` | Documentação longa traduzida futura. |

Use tags de idioma em minúsculas no estilo BCP 47 para diretórios quando
possível: `ru`, `es`, `pt-BR`, `zh-CN`, `ja` e similares.

## Contrato de tradução

- Espelhe a lista de arquivos de `docs/en/`, exceto quando um arquivo for
  somente em inglês.
- Mantenha a mesma ordem de seções de primeiro nível da fonte inglesa.
- Mantenha nomes de comandos, variáveis de ambiente, caminhos de arquivos, URLs,
  chaves JSON, identificadores Zig e nomes de protocolos sem alterações.
- Traduza prosa, títulos, descrições de tabelas e comentários explicativos.
- Preserve links relativos. Atualize apenas o segmento de locale ao apontar para
  uma página traduzida.
- Não traduza saída gerada por comandos, exceto quando for prosa mostrada aos
  usuários.
- Não adicione na tradução afirmações que não existem na fonte inglesa.
- Atualize `docs/README.md` sempre que um novo diretório de idioma for útil para
  usuários.

## Escrever inglês para tradução

A qualidade da tradução começa na fonte inglesa.

- Use frases curtas e diretas.
- Prefira voz ativa.
- Evite expressões idiomáticas, piadas, gírias e referências culturais
  específicas.
- Defina um termo na primeira vez em que ele aparece.
- Mantenha uma instrução ou fato por frase quando for prático.
- Mantenha listas paralelas: comece cada item com o mesmo tipo de palavra.
- Evite "this", "that" ou "it" quando o substantivo puder ser ambíguo.
- Use datas exatas em vez de datas relativas em documentação duradoura.
- Mantenha capturas de tela e diagramas opcionais; o texto deve carregar a
  instrução.

## Termos protegidos

Não traduza estes termos, exceto quando o idioma tiver uma tradução técnica
amplamente aceita e o significado permanecer exato.

| Termo | Razão |
|---|---|
| `nllclw` | Nome do produto e do binário. |
| Zig | Nome da linguagem de programação. |
| Chat Completions | Contrato de API do provedor. |
| OpenAI, OpenRouter | Nomes de provedores. |
| WebSocket, Telegram, JSONL, SSE | Nomes de protocolos ou formatos. |
| `NLLCLW_*` | Namespace de variáveis de ambiente. |
| `src/`, `docs/en/`, `config.json`, `.env` | Caminhos e nomes de arquivos literais. |
| `shell_exec` | Nome de ferramenta e limite de segurança. |

## Implantação em doze idiomas

Ao adicionar o conjunto de traduções planejado:

1. Termine primeiro as alterações em inglês.
2. Escolha as tags de locale exatas.
3. Copie `docs/en/` para cada `docs/<locale>/`.
4. Traduza a prosa preservando comandos, chaves de configuração, blocos de
   código e nomes de arquivos.
5. Adicione README traduzidos na raiz apenas quando eles forem mantidos.
6. Adicione cada idioma concluído a `docs/README.md`.
7. Verifique os links dentro de cada locale.
8. Execute `git diff --check`.

Não crie diretórios de idioma vazios. Um idioma deve aparecer em
`docs/README.md` somente depois que seu ponto de entrada existir.

## Checklist de atualização da fonte

Quando a documentação inglesa mudar depois que traduções existirem:

1. Atualize o arquivo fonte em inglês.
2. Atualize links relacionados do README ou entradas do docs hub.
3. Anote se os arquivos traduzidos precisam da mesma mudança de conteúdo.
4. Mantenha métricas em [benchmarks.md](benchmarks.md) e o snapshot do README
   sincronizados quando tamanho do binário, contagens de testes, contagens de
   arquivos fonte ou LOC mudarem.
5. Execute os comandos locais de verificação de [development.md](development.md).

## Referências

Estas regras estão alinhadas a guias públicos de documentação:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
