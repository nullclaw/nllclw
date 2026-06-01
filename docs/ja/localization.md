# Localization

English は `nllclw` documentation の source language です。English changes を
先に complete にし、その後で現在の English files から translate します。

## File Layout

| Path | Purpose |
|---|---|
| `README.md` | GitHub 向けの English project overview。 |
| `README.<locale>.md` | Optional translated root README files。 |
| `docs/README.md` | Language index。 |
| `docs/en/` | English long-form documentation。 |
| `docs/<locale>/` | 将来の translated long-form documentation。 |

可能な場合、directories には BCP 47-style lowercase language tags を使います:
`ru`、`es`、`pt-BR`、`zh-CN`、`ja` など。

## Translation Contract

- English-only の file でない限り、`docs/en/` file list を mirror します。
- English source と同じ top-level section order を維持します。
- Command names、environment variables、file paths、URLs、JSON keys、Zig
  identifiers、protocol names は変更しません。
- Prose、headings、table descriptions、explanatory comments を翻訳します。
- Relative links を preserve します。Translated page に link する場合だけ locale
  segment を update します。
- Users に表示される prose でない限り、generated command output は翻訳しません。
- English source にない translated claims を追加しません。
- 新しい language directory が users に有用になったら `docs/README.md` を update します。

## Writing English For Translation

Translation quality は English source から始まります。

- 短く直接的な sentences を使います。
- Active voice を優先します。
- Idioms、jokes、slang、culture-specific references を避けます。
- Term が初めて出るときに define します。
- Practical な場合は、1 sentence に 1 instruction または fact を置きます。
- Lists は parallel にします。各 item を同じ種類の word で始めます。
- Noun が不明確になる場合は "this"、"that"、"it" を避けます。
- Long-lived docs では relative dates ではなく exact dates を使います。
- Screenshots と diagrams は optional にします。Instruction は text だけで伝わる必要があります。

## Protected Terms

言語に広く受け入れられた technical translation があり、意味が exact に保たれる場合を除き、これらの terms は翻訳しません。

| Term | Reason |
|---|---|
| `nllclw` | Product and binary name。 |
| Zig | Programming language name。 |
| Chat Completions | Provider API contract。 |
| OpenAI, OpenRouter | Provider names。 |
| WebSocket, Telegram, JSONL, SSE | Protocol or format names。 |
| `NLLCLW_*` | Environment variable namespace。 |
| `src/`, `docs/en/`, `config.json`, `.env` | Literal paths and file names。 |
| `shell_exec` | Tool name and security boundary。 |

## Twelve-Language Rollout

Planned translation set を追加するとき:

1. English edits を先に finish します。
2. Exact locale tags を選びます。
3. `docs/en/` を各 `docs/<locale>/` に copy します。
4. Commands、config keys、code blocks、file names を preserve しながら prose を translate します。
5. Translated root README files は maintained される場合だけ追加します。
6. Completed language をそれぞれ `docs/README.md` に追加します。
7. 各 locale の links を check します。
8. `git diff --check` を実行します。

Empty language directories は作りません。Language は entry point が存在してから
`docs/README.md` に表示します。

## Source Update Checklist

Translations が存在した後に English docs が変わった場合:

1. English source file を update します。
2. Related README links または docs hub entries を update します。
3. Translated files に同じ content change が必要か note します。
4. Binary size、test counts、source file counts、LOC が変わった場合は、
   [benchmarks.md](benchmarks.md) の metrics と README snapshot を sync します。
5. [development.md](development.md) の local verification commands を実行します。

## References

これらの rules は public documentation guidance に aligned しています:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
