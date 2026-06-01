# Localization

English হলো `nllclw` documentation-এর source language। আগে English changes
complete রাখুন, তারপর current English files থেকে translate করুন।

## File Layout

| Path | Purpose |
|---|---|
| `README.md` | GitHub-এর জন্য English project overview। |
| `README.<locale>.md` | Optional translated root README files। |
| `docs/README.md` | Language index। |
| `docs/en/` | English long-form documentation। |
| `docs/<locale>/` | Future translated long-form documentation। |

সম্ভব হলে directories-এর জন্য BCP 47-style lowercase language tags ব্যবহার করুন:
`ru`, `es`, `pt-BR`, `zh-CN`, `ja`, এবং একই ধরনের tags।

## Translation Contract

- কোনো file English-only না হলে `docs/en/` file list mirror করুন।
- English source-এর মতো একই top-level section order রাখুন।
- Command names, environment variables, file paths, URLs, JSON keys, Zig
  identifiers এবং protocol names unchanged রাখুন।
- Prose, headings, table descriptions এবং explanatory comments translate করুন।
- Relative links preserve করুন। Translated page-এ link করলে শুধু locale segment update করুন।
- Generated command output translate করবেন না, যদি না সেটি users-কে দেখানো prose হয়।
- English source-এ নেই এমন translated claims যোগ করবেন না।
- নতুন language directory users-এর জন্য useful হলে `docs/README.md` update করুন।

## Writing English For Translation

Translation quality English source থেকেই শুরু হয়।

- ছোট, সরাসরি sentences ব্যবহার করুন।
- Active voice prefer করুন।
- Idioms, jokes, slang এবং culture-specific references এড়িয়ে চলুন।
- Term প্রথমবার এলে define করুন।
- Practical হলে এক sentence-এ এক instruction বা fact রাখুন।
- Lists parallel রাখুন: প্রতিটি item একই ধরনের word দিয়ে শুরু করুন।
- Noun unclear হতে পারে এমন জায়গায় "this", "that", বা "it" এড়িয়ে চলুন।
- Long-lived docs-এ relative dates-এর বদলে exact dates ব্যবহার করুন।
- Screenshots এবং diagrams optional রাখুন; instruction text দিয়েই বোঝা যেতে হবে।

## Protected Terms

কোনো language-এ widely accepted technical translation না থাকলে এবং meaning exact
না থাকলে এই terms translate করবেন না।

| Term | Reason |
|---|---|
| `nllclw` | Product এবং binary name। |
| Zig | Programming language name। |
| Chat Completions | Provider API contract। |
| OpenAI, OpenRouter | Provider names। |
| WebSocket, Telegram, JSONL, SSE | Protocol বা format names। |
| `NLLCLW_*` | Environment variable namespace। |
| `src/`, `docs/en/`, `config.json`, `.env` | Literal paths এবং file names। |
| `shell_exec` | Tool name এবং security boundary। |

## Twelve-Language Rollout

Planned translation set যোগ করার সময়:

1. আগে English edits finish করুন।
2. Exact locale tags বেছে নিন।
3. `docs/en/` প্রতিটি `docs/<locale>/`-এ copy করুন।
4. Commands, config keys, code blocks এবং file names preserve রেখে prose translate করুন।
5. Translated root README files শুধু maintained হলে যোগ করুন।
6. প্রতিটি completed language `docs/README.md`-এ যোগ করুন।
7. প্রতিটি locale-এর links check করুন।
8. `git diff --check` চালান।

Empty language directories তৈরি করবেন না। কোনো language `docs/README.md`-এ শুধু
তখনই থাকবে যখন তার entry point exists করে।

## Source Update Checklist

Translations থাকার পর English docs বদলালে:

1. English source file update করুন।
2. Related README links বা docs hub entries update করুন।
3. Translated files-এ একই content change দরকার কি না note করুন।
4. Binary size, test counts, source file counts বা LOC বদলালে
   [benchmarks.md](benchmarks.md) metrics এবং README snapshot sync রাখুন।
5. [development.md](development.md) থেকে local verification commands চালান।

## References

এই rules public documentation guidance-এর সঙ্গে aligned:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
