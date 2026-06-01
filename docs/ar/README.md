# توثيق nllclw بالعربية

يعد README في جذر المستودع نقطة الدخول السريعة. تغطي هذه المستندات الإعداد
والتشغيل والأمان والتطوير بمزيد من التفصيل.

| المستند | الغرض |
|---|---|
| [installation.md](installation.md) | ثبّت release binary أولاً، أو ثبّت Zig `0.16.0` عند البناء من source. |
| [getting-started.md](getting-started.md) | اضبط provider وشغّل المساعد من release binary أو source build. |
| [architecture.md](architecture.md) | حدود النظام، وتدفقات الطلبات، وخريطة الوحدات، وشكل public API. |
| [configuration.md](configuration.md) | جميع مفاتيح configuration، وسلوك `config.json` و`.env`، وprovider presets، وقواعد validation. |
| [context.md](context.md) | ملفات Assistant context مثل `SOUL.md` و`AGENTS.md` و`MEMORY.md`. |
| [memory.md](memory.md) | Transcript memory، وdurable fact memory، وتنسيقات JSONL، وmemory tools. |
| [tools.md](tools.md) | Tool registry، وtool-call flow، وcapability gates، ونموذج أمان filesystem. |
| [channels.md](channels.md) | CLI وinteractive REPL وTelegram polling وWebSocket UI channel وheartbeat وdaemon behavior. |
| [security.md](security.md) | Capability boundaries، وأمان الملفات المحلية، والتعامل مع provider keys، وthreat model. |
| [benchmarks.md](benchmarks.md) | Binary size، وstartup، وRAM، والاختبارات، وعدد ملفات المصدر، وأوامر إعادة القياس. |
| [localization.md](localization.md) | قواعد الكتابة المناسبة للترجمة وتخطيط الوثائق متعددة اللغات المتوقع. |
| [development.md](development.md) | Build/test commands، واتفاقيات المشروع، ووصفات التوسعة. |

## ترتيب القراءة

1. ابدأ من [README](../../README.md) في جذر المستودع للحصول على نظرة عامة على المشروع.
2. استخدم [installation.md](installation.md) لتثبيت release binary أو إعداد Zig لبناء source.
3. اتبع [getting-started.md](getting-started.md) للإعداد والتشغيل.
4. اقرأ [configuration.md](configuration.md) قبل استخدام provider key حقيقي.
5. اقرأ [context.md](context.md) و[memory.md](memory.md) و[tools.md](tools.md) قبل تفعيل القدرات المحلية.
6. اقرأ [security.md](security.md) قبل التشغيل داخل دليل حساس.
7. اقرأ [architecture.md](architecture.md) و[development.md](development.md) عند تعديل الكود.
8. اقرأ [localization.md](localization.md) قبل ترجمة الوثائق.

## ملخص التصميم

يفصل `nllclw` بين user-facing channels وruntime composition وagent logic وprovider
resolution وmemory وtools وstdlib adapters في وحدات مستقلة. يستخدم default build
وقت التشغيل Zig وZig standard library فقط.
