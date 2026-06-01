# 本地化

英语是 `nllclw` 文档的源语言。请先完整更新英语内容，再从当前英语文件
翻译。

## 文件布局

| 路径 | 用途 |
|---|---|
| `README.md` | 面向 GitHub 的英文项目概览。 |
| `README.<locale>.md` | 可选的根目录翻译 README 文件。 |
| `docs/README.md` | 语言索引。 |
| `docs/en/` | 英文长文档。 |
| `docs/<locale>/` | 未来的翻译长文档。 |

目录名尽量使用 BCP 47 风格的小写语言标签：`ru`、`es`、`pt-BR`、
`zh-CN`、`ja` 等。

## 翻译契约

- 除非文件只适用于英文，否则镜像 `docs/en/` 的文件列表。
- 保持与英文源文件相同的顶级 section 顺序。
- 保持 command names、environment variables、file paths、URLs、JSON keys、
  Zig identifiers 和 protocol names 不变。
- 翻译 prose、headings、table descriptions 和 explanatory comments。
- 保留 relative links。链接到翻译页面时只更新 locale segment。
- 不翻译生成的 command output，除非它是展示给用户的 prose。
- 不添加英文源文档中没有的翻译声明。
- 新语言目录对用户有用时，更新 `docs/README.md`。

## 为翻译编写英文

翻译质量始于英文源文档。

- 使用短而直接的句子。
- 优先使用主动语态。
- 避免 idioms、jokes、slang 和特定文化引用。
- 术语首次出现时给出定义。
- 在可行时，每句只包含一个 instruction 或 fact。
- 保持列表并列：每项以相同类型的词开头。
- 当名词可能不清楚时，避免使用 "this"、"that" 或 "it"。
- 在长期文档中使用精确日期，而不是相对日期。
- 截图和图表应是可选的；文本本身必须承载说明。

## 受保护术语

除非某种语言有广泛接受的技术译法且含义保持精确，否则不要翻译这些术语。

| 术语 | 原因 |
|---|---|
| `nllclw` | 产品名和 binary 名。 |
| Zig | 编程语言名称。 |
| Chat Completions | Provider API contract。 |
| OpenAI, OpenRouter | Provider names。 |
| WebSocket, Telegram, JSONL, SSE | Protocol 或 format names。 |
| `NLLCLW_*` | Environment variable namespace。 |
| `src/`, `docs/en/`, `config.json`, `.env` | 字面 path 和 file names。 |
| `shell_exec` | Tool name 和 security boundary。 |

## 十二语言 rollout

添加计划中的翻译集时：

1. 先完成英文修改。
2. 选择精确的 locale tags。
3. 将 `docs/en/` 复制到每个 `docs/<locale>/`。
4. 翻译 prose，同时保留 commands、config keys、code blocks 和 file names。
5. 只有在维护时才添加根目录翻译 README files。
6. 将每个完成的语言添加到 `docs/README.md`。
7. 检查每个 locale 内的 links。
8. 运行 `git diff --check`。

不要创建空语言目录。只有在 entry point 已存在后，语言才应出现在
`docs/README.md` 中。

## 源文档更新 checklist

当英文文档在已有翻译后发生变化：

1. 更新英文源文件。
2. 更新相关 README links 或 docs hub entries。
3. 记录翻译文件是否需要相同内容变更。
4. 当 binary size、test counts、source file counts 或 LOC 变化时，保持
   [benchmarks.md](benchmarks.md) 中的 metrics 与 README snapshot 同步。
5. 运行 [development.md](development.md) 中的本地验证命令。

## 参考

这些规则与公开文档指南一致：

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
