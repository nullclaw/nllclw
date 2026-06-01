# Localization

English is the source language for `nllclw` documentation. Keep English changes
complete first, then translate from the current English files.

## File Layout

| Path | Purpose |
|---|---|
| `README.md` | English project overview for GitHub. |
| `README.<locale>.md` | Optional translated root README files. |
| `docs/README.md` | Language index. |
| `docs/en/` | English long-form documentation. |
| `docs/<locale>/` | Future translated long-form documentation. |

Use BCP 47-style lowercase language tags for directories when possible:
`ru`, `es`, `pt-BR`, `zh-CN`, `ja`, and similar.

## Translation Contract

- Mirror the `docs/en/` file list unless a file is English-only.
- Keep the same top-level section order as the English source.
- Keep command names, environment variables, file paths, URLs, JSON keys, Zig
  identifiers, and protocol names unchanged.
- Translate prose, headings, table descriptions, and explanatory comments.
- Preserve relative links. Update only the locale segment when linking to a
  translated page.
- Do not translate generated command output unless it is prose shown to users.
- Do not add translated claims that are not present in the English source.
- Update `docs/README.md` whenever a new language directory is useful to users.

## Writing English For Translation

Translation quality starts in the English source.

- Use short, direct sentences.
- Prefer active voice.
- Avoid idioms, jokes, slang, and culture-specific references.
- Define a term the first time it appears.
- Keep one instruction or fact per sentence when practical.
- Keep lists parallel: start each item with the same kind of word.
- Avoid "this", "that", or "it" when the noun could be unclear.
- Use exact dates instead of relative dates in long-lived docs.
- Keep screenshots and diagrams optional; text must carry the instruction.

## Protected Terms

Do not translate these terms unless a language has a widely accepted technical
translation and the meaning stays exact.

| Term | Reason |
|---|---|
| `nllclw` | Product and binary name. |
| Zig | Programming language name. |
| Chat Completions | Provider API contract. |
| OpenAI, OpenRouter | Provider names. |
| WebSocket, Telegram, JSONL, SSE | Protocol or format names. |
| `NLLCLW_*` | Environment variable namespace. |
| `src/`, `docs/en/`, `config.json`, `.env` | Literal paths and file names. |
| `shell_exec` | Tool name and security boundary. |

## Twelve-Language Rollout

When adding the planned translation set:

1. Finish English edits first.
2. Choose the exact locale tags.
3. Copy `docs/en/` to each `docs/<locale>/`.
4. Translate prose while preserving commands, config keys, code blocks, and file names.
5. Add translated root README files only when they are maintained.
6. Add each completed language to `docs/README.md`.
7. Check links within each locale.
8. Run `git diff --check`.

Do not create empty language directories. A language should appear in
`docs/README.md` only after its entry point exists.

## Source Update Checklist

When English docs change after translations exist:

1. Update the English source file.
2. Update related README links or docs hub entries.
3. Note whether translated files need the same content change.
4. Keep metrics in [benchmarks.md](benchmarks.md) and the README snapshot in sync
   when binary size, test counts, source file counts, or LOC change.
5. Run the local verification commands from [development.md](development.md).

## References

These rules are aligned with public documentation guidance:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
