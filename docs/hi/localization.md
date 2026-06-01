# Localization

English `nllclw` documentation की source language है। पहले English changes
complete रखें, फिर current English files से translate करें।

## File Layout

| Path | Purpose |
|---|---|
| `README.md` | GitHub के लिए English project overview। |
| `README.<locale>.md` | Optional translated root README files। |
| `docs/README.md` | Language index। |
| `docs/en/` | English long-form documentation। |
| `docs/<locale>/` | Future translated long-form documentation। |

जब संभव हो directories के लिए BCP 47-style lowercase language tags इस्तेमाल करें:
`ru`, `es`, `pt-BR`, `zh-CN`, `ja`, और इसी तरह।

## Translation Contract

- जब तक कोई file English-only न हो, `docs/en/` file list को mirror करें।
- English source जैसा ही top-level section order रखें।
- Command names, environment variables, file paths, URLs, JSON keys, Zig
  identifiers और protocol names unchanged रखें।
- Prose, headings, table descriptions और explanatory comments translate करें।
- Relative links preserve करें। Translated page पर link करते समय केवल locale
  segment update करें।
- Generated command output translate न करें, जब तक वह users को दिखाया गया prose न हो।
- English source में मौजूद नहीं हैं ऐसे translated claims न जोड़ें।
- जब नई language directory users के लिए उपयोगी हो, `docs/README.md` update करें।

## Writing English For Translation

Translation quality English source से शुरू होती है।

- छोटे, सीधे sentences लिखें।
- Active voice को प्राथमिकता दें।
- Idioms, jokes, slang और culture-specific references से बचें।
- Term पहली बार आए तो define करें।
- Practical हो तो प्रत्येक sentence में एक instruction या fact रखें।
- Lists parallel रखें: हर item समान तरह के word से शुरू हो।
- जब noun unclear हो सकता है तो "this", "that", या "it" से बचें।
- Long-lived docs में relative dates की जगह exact dates इस्तेमाल करें।
- Screenshots और diagrams optional रखें; instruction text से स्पष्ट होना चाहिए।

## Protected Terms

इन terms को translate न करें, जब तक किसी language में widely accepted technical
translation न हो और meaning exact न रहे।

| Term | Reason |
|---|---|
| `nllclw` | Product और binary name। |
| Zig | Programming language name। |
| Chat Completions | Provider API contract। |
| OpenAI, OpenRouter | Provider names। |
| WebSocket, Telegram, JSONL, SSE | Protocol या format names। |
| `NLLCLW_*` | Environment variable namespace। |
| `src/`, `docs/en/`, `config.json`, `.env` | Literal paths और file names। |
| `shell_exec` | Tool name और security boundary। |

## Twelve-Language Rollout

Planned translation set जोड़ते समय:

1. पहले English edits complete करें।
2. Exact locale tags चुनें।
3. `docs/en/` को हर `docs/<locale>/` में copy करें।
4. Commands, config keys, code blocks और file names preserve करते हुए prose translate करें।
5. Translated root README files केवल तब जोड़ें जब वे maintained हों।
6. हर completed language को `docs/README.md` में जोड़ें।
7. हर locale में links check करें।
8. `git diff --check` चलाएँ।

Empty language directories न बनाएँ। किसी language को `docs/README.md` में केवल
तभी दिखाएँ जब उसका entry point मौजूद हो।

## Source Update Checklist

Translations मौजूद होने के बाद English docs बदलें तो:

1. English source file update करें।
2. Related README links या docs hub entries update करें।
3. Note करें कि translated files में वही content change चाहिए या नहीं।
4. Binary size, test counts, source file counts या LOC बदलने पर
   [benchmarks.md](benchmarks.md) metrics और README snapshot sync रखें।
5. [development.md](development.md) के local verification commands चलाएँ।

## References

ये rules public documentation guidance से aligned हैं:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
