# Localization

الإنجليزية هي source language لتوثيق `nllclw`. أبق تغييرات الإنجليزية مكتملة
أولاً، ثم ترجم من ملفات الإنجليزية الحالية.

## File Layout

| Path | Purpose |
|---|---|
| `README.md` | English project overview for GitHub. |
| `README.<locale>.md` | ملفات README مترجمة اختيارية في الجذر. |
| `docs/README.md` | Language index. |
| `docs/en/` | English long-form documentation. |
| `docs/<locale>/` | وثائق طويلة مترجمة مستقبلاً. |

استخدم علامات لغة BCP 47-style lowercase للأدلة عندما يكون ذلك ممكناً:
`ru`, `es`, `pt-BR`, `zh-CN`, `ja`, وما شابه.

## Translation Contract

- اعكس قائمة ملفات `docs/en/` ما لم يكن الملف English-only.
- حافظ على نفس ترتيب الأقسام العليا الموجود في المصدر الإنجليزي.
- أبق command names وenvironment variables وfile paths وURLs وJSON keys وZig
  identifiers وprotocol names بدون تغيير.
- ترجم prose وheadings وtable descriptions وexplanatory comments.
- حافظ على relative links. حدّث فقط locale segment عند الربط إلى صفحة مترجمة.
- لا تترجم generated command output ما لم يكن prose معروضاً للمستخدمين.
- لا تضف claims مترجمة غير موجودة في المصدر الإنجليزي.
- حدّث `docs/README.md` عندما يصبح دليل لغة جديداً مفيداً للمستخدمين.

## Writing English For Translation

تبدأ جودة الترجمة من المصدر الإنجليزي.

- استخدم جملاً قصيرة ومباشرة.
- فضّل active voice.
- تجنب idioms وjokes وslang والإشارات الخاصة بثقافة معينة.
- عرّف المصطلح عند ظهوره لأول مرة.
- ضع تعليمة أو حقيقة واحدة في كل جملة عندما يكون ذلك عملياً.
- اجعل القوائم متوازية: ابدأ كل item بنوع الكلمة نفسه.
- تجنب "this" و"that" و"it" عندما يكون الاسم المقصود غير واضح.
- استخدم تواريخ exact بدلاً من relative dates في الوثائق طويلة العمر.
- اجعل screenshots وdiagrams اختيارية؛ يجب أن يحمل النص التعليمة.

## Protected Terms

لا تترجم هذه المصطلحات إلا إذا كان للغة ترجمة تقنية شائعة وتحافظ على المعنى بدقة.

| Term | Reason |
|---|---|
| `nllclw` | اسم المنتج والbinary. |
| Zig | اسم لغة البرمجة. |
| Chat Completions | عقد Provider API. |
| OpenAI, OpenRouter | أسماء providers. |
| WebSocket, Telegram, JSONL, SSE | أسماء protocol أو format. |
| `NLLCLW_*` | Namespace لمتغيرات البيئة. |
| `src/`, `docs/en/`, `config.json`, `.env` | Paths وأسماء ملفات literal. |
| `shell_exec` | اسم tool وsecurity boundary. |

## Twelve-Language Rollout

عند إضافة مجموعة الترجمات المخطط لها:

1. أنهِ تعديلات الإنجليزية أولاً.
2. اختر exact locale tags.
3. انسخ `docs/en/` إلى كل `docs/<locale>/`.
4. ترجم prose مع الحفاظ على commands وconfig keys وcode blocks وأسماء الملفات.
5. أضف translated root README files فقط عندما تكون maintained.
6. أضف كل لغة مكتملة إلى `docs/README.md`.
7. افحص links داخل كل locale.
8. شغّل `git diff --check`.

لا تنشئ أدلة لغات فارغة. يجب أن تظهر اللغة في `docs/README.md` فقط بعد وجود
entry point الخاص بها.

## Source Update Checklist

عندما تتغير English docs بعد وجود الترجمات:

1. حدّث English source file.
2. حدّث روابط README ذات الصلة أو docs hub entries.
3. دوّن ما إذا كانت الملفات المترجمة تحتاج تغيير المحتوى نفسه.
4. أبق metrics في [benchmarks.md](benchmarks.md) وREADME snapshot متزامنين عندما
   يتغير binary size أو test counts أو source file counts أو LOC.
5. شغّل أوامر التحقق المحلية من [development.md](development.md).

## References

تتوافق هذه القواعد مع إرشادات التوثيق العامة:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
