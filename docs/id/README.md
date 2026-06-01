# Dokumentasi nllclw dalam bahasa Indonesia

README repositori adalah titik masuk cepat. Dokumen-dokumen ini membahas
instalasi, operasi, keamanan, dan pengembangan secara lebih rinci.

| Dokumen | Tujuan |
|---|---|
| [installation.md](installation.md) | Instal release binary terlebih dahulu, atau instal Zig `0.16.0` saat build dari source. |
| [getting-started.md](getting-started.md) | Konfigurasi provider dan jalankan asisten dari release binary atau source build. |
| [architecture.md](architecture.md) | Batas sistem, alur request, peta modul, dan bentuk API publik. |
| [configuration.md](configuration.md) | Semua key konfigurasi, perilaku `config.json` dan `.env`, preset provider, dan aturan validasi. |
| [context.md](context.md) | File konteks asisten seperti `SOUL.md`, `AGENTS.md`, dan `MEMORY.md`. |
| [memory.md](memory.md) | Transcript memory, durable fact memory, format JSONL, dan alat memory. |
| [tools.md](tools.md) | Registry alat, alur tool-call, capability gates, dan model keamanan filesystem. |
| [channels.md](channels.md) | CLI, REPL interaktif, polling Telegram, channel WebSocket UI, heartbeat, dan perilaku daemon. |
| [security.md](security.md) | Batas capability, keamanan file lokal, penanganan key provider, dan threat model. |
| [benchmarks.md](benchmarks.md) | Ukuran binary, startup, RAM, test, jumlah source, dan command reproduksi. |
| [localization.md](localization.md) | Aturan penulisan siap-terjemah dan layout dokumentasi multibahasa yang diharapkan. |
| [development.md](development.md) | Command build/test, konvensi proyek, dan resep ekstensi. |

## Urutan baca

1. Mulai dari [README](../../README.md) repositori untuk ringkasan proyek.
2. Gunakan [installation.md](installation.md) untuk menginstal release binary atau menyiapkan Zig untuk source build.
3. Ikuti [getting-started.md](getting-started.md) untuk konfigurasi dan menjalankan.
4. Baca [configuration.md](configuration.md) sebelum memakai key provider nyata.
5. Baca [context.md](context.md), [memory.md](memory.md), dan [tools.md](tools.md) sebelum mengaktifkan capability lokal.
6. Baca [security.md](security.md) sebelum menjalankan di direktori sensitif.
7. Baca [architecture.md](architecture.md) dan [development.md](development.md) saat mengubah kode.
8. Baca [localization.md](localization.md) sebelum menerjemahkan dokumentasi.

## Ringkasan desain

`nllclw` memisahkan channel yang menghadap pengguna, komposisi runtime, logika
agent, resolusi provider, memory, tools, dan adapter stdlib ke dalam modul yang
berbeda. Build default hanya memakai Zig dan Zig standard library saat runtime.
