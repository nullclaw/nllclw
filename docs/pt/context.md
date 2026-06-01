# Arquivos de contexto do assistente

`nllclw` pode carregar arquivos markdown locais de instruções a partir do
diretório de trabalho atual e anexá-los ao system prompt. Isso dá a um
repositório ou projeto uma forma leve de definir identidade, regras de operação,
preferências do usuário, política de ferramentas e tarefas heartbeat.

Ele também indexa arquivos `skills/*.md`. Skills são anunciadas como um resumo
compacto; o arquivo completo é carregado depois por `read_file` apenas quando
uma tarefa corresponder a ele. Cada linha de resumo limita o título inline e a
descrição para que um arquivo skill grande não possa dominar o índice do system
prompt.

## Ordem de carregamento

Arquivos são carregados nesta ordem quando presentes:

1. `IDENTITY.md`
2. `SOUL.md`
3. `USER.md`
4. `AGENTS.md`
5. `MEMORY.md`
6. `TOOLS.md`
7. `HEARTBEAT.md`
8. `BOOTSTRAP.md`
9. resumo `skills/*.md`, ordenado por filename

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

Os arquivos são tratados como trusted local instructions. Eles não são buscados
em um serviço remoto.

Cada context file deve ser markdown UTF-8 válido sem binary control bytes e não
maior que 16 KiB. Bytes inválidos fazem o startup falhar em vez de serem
inseridos no provider JSON. Skill files também devem ser markdown UTF-8 válido
sem binary control bytes e não maiores que 8 KiB.

## Runtime Persona

`NLLCLW_PERSONA` e `/persona` adicionam uma pequena instrução final de estilo ao
system prompt. Os modos suportados são:

- `neutral`: direto e equilibrado;
- `friendly`: caloroso, mas conciso;
- `technical`: tom de engenharia preciso e atento a suposições;
- `witty`: humor leve sem sacrificar utilidade.

Persona controla apenas apresentação. Ela não sobrescreve `SOUL.md`, `TOOLS.md`,
memory policy, safety boundaries ou provider configuration.

## Papéis dos arquivos

| Arquivo | Papel |
|---|---|
| `IDENTITY.md` | Identidade estável do assistente e high-level project role. |
| `SOUL.md` | Constituição comportamental: tom, prioridades e regras não negociáveis. |
| `USER.md` | Preferências locais privadas do usuário. Ignorado pelo git. |
| `AGENTS.md` | Instruções canônicas de nível de repositório compartilhadas com coding agents. |
| `MEMORY.md` | Notas long-term mantidas por humanos. Separadas da JSONL runtime memory. |
| `TOOLS.md` | Política de ferramentas legível por humanos e notas de capacidades disponíveis. |
| `HEARTBEAT.md` | Fonte local de trabalho/tarefas recorrentes para `nllclw heartbeat` e daemon mode. |
| `BOOTSTRAP.md` | Notas privadas locais de startup/bootstrap. Ignorado pelo git. |
| `skills/*.md` | Instruções opcionais task-specific anunciadas como compact skill index. |

Use `AGENTS.md` para shared agent guidance em vez de manter arquivos de
instruções separados por ferramenta.

## Runtime Memory versus Markdown Memory

Há dois conceitos distintos:

| Mecanismo | Arquivo | Escrito por | Objetivo |
|---|---|---|---|
| Markdown context | `MEMORY.md` | Humanos ou edições normais de arquivo | Notas curated de projeto/usuário incluídas no system prompt. |
| Transcript memory | user state dir `memory.jsonl` | Runtime | Turnos recentes user/assistant enviados como chat history. |
| Fact memory | user state dir `facts.jsonl` | Memory tools | Durable key/value facts que o modelo pode armazenar ou recordar. |

Veja [memory.md](memory.md) para os sistemas de memória JSONL.

## Trust Model

Context files podem direcionar o assistente. Não execute `nllclw` em um
diretório não confiável, a menos que você aceite que esses arquivos influenciem
o prompt.

Prática recomendada:

- commit shared project instructions como `IDENTITY.md`, `SOUL.md`,
  `AGENTS.md`, `MEMORY.md` e `TOOLS.md`;
- mantenha private local preference files como `USER.md` e `BOOTSTRAP.md`;
- evite secrets em todos os context files.

## Heartbeat Tasks

`HEARTBEAT.md` é tanto um context file quanto uma fonte local de tarefas. O
heartbeat parser é conservador: apenas unchecked markdown tasks e linhas
`TODO:` viram prompts.

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

Crie arquivos markdown em `skills/`:

```md
# Deploy
Use this skill for deployment checks and release verification.
```

No startup, `nllclw` adiciona um resumo como:

```text
- Deploy: Use this skill for deployment checks and release verification. (read with read_file: skills/deploy.md)
```

A skill completa permanece local e é lida apenas quando o modelo decide que ela
é relevante e file-read tools estão habilitadas.

Skill filenames and contents devem ser markdown UTF-8 válido sem binary control
bytes. Skill summaries colapsam whitespace de título e descrição em uma única
linha compacta. Hidden files, non-`.md` files, nested paths e mais de 32 skill
files são ignorados.
