# Lokalisasi

Bahasa Inggris adalah bahasa sumber untuk dokumentasi `nllclw`. Selesaikan
perubahan bahasa Inggris terlebih dahulu, lalu terjemahkan dari file bahasa
Inggris saat ini.

## Layout file

| Path | Tujuan |
|---|---|
| `README.md` | Ringkasan proyek berbahasa Inggris untuk GitHub. |
| `README.<locale>.md` | File README root terjemahan opsional. |
| `docs/README.md` | Indeks bahasa. |
| `docs/en/` | Dokumentasi panjang berbahasa Inggris. |
| `docs/<locale>/` | Dokumentasi panjang terjemahan di masa depan. |

Gunakan tag bahasa lowercase bergaya BCP 47 untuk direktori jika memungkinkan:
`ru`, `es`, `pt-BR`, `zh-CN`, `ja`, dan sejenisnya.

## Kontrak terjemahan

- Cerminkan daftar file `docs/en/`, kecuali file tersebut hanya untuk bahasa
  Inggris.
- Pertahankan urutan section level atas yang sama dengan sumber bahasa Inggris.
- Jangan ubah nama command, environment variable, path file, URL, key JSON,
  identifier Zig, dan nama protocol.
- Terjemahkan prosa, heading, deskripsi tabel, dan komentar penjelas.
- Pertahankan link relatif. Ubah hanya segmen locale saat menautkan ke halaman
  terjemahan.
- Jangan terjemahkan output command yang dihasilkan kecuali output tersebut
  adalah prosa yang ditampilkan kepada pengguna.
- Jangan tambahkan klaim terjemahan yang tidak ada dalam sumber bahasa Inggris.
- Perbarui `docs/README.md` saat direktori bahasa baru berguna bagi pengguna.

## Menulis bahasa Inggris untuk diterjemahkan

Kualitas terjemahan dimulai dari sumber bahasa Inggris.

- Gunakan kalimat pendek dan langsung.
- Pilih kalimat aktif.
- Hindari idiom, lelucon, slang, dan rujukan budaya yang spesifik.
- Definisikan istilah saat pertama kali muncul.
- Pertahankan satu instruksi atau fakta per kalimat jika praktis.
- Buat daftar tetap paralel: mulai tiap item dengan jenis kata yang sama.
- Hindari "this", "that", atau "it" jika noun dapat menjadi tidak jelas.
- Gunakan tanggal pasti, bukan tanggal relatif, dalam dokumentasi jangka panjang.
- Jadikan screenshot dan diagram opsional; teks harus memuat instruksi.

## Istilah yang dilindungi

Jangan terjemahkan istilah ini kecuali bahasa tersebut memiliki terjemahan
teknis yang diterima luas dan maknanya tetap tepat.

| Istilah | Alasan |
|---|---|
| `nllclw` | Nama produk dan binary. |
| Zig | Nama bahasa pemrograman. |
| Chat Completions | Kontrak API provider. |
| OpenAI, OpenRouter | Nama provider. |
| WebSocket, Telegram, JSONL, SSE | Nama protocol atau format. |
| `NLLCLW_*` | Namespace environment variable. |
| `src/`, `docs/en/`, `config.json`, `.env` | Path dan nama file literal. |
| `shell_exec` | Nama alat dan batas keamanan. |

## Rollout dua belas bahasa

Saat menambahkan set terjemahan yang direncanakan:

1. Selesaikan perubahan bahasa Inggris terlebih dahulu.
2. Pilih tag locale yang tepat.
3. Salin `docs/en/` ke setiap `docs/<locale>/`.
4. Terjemahkan prosa sambil mempertahankan command, key konfigurasi, blok kode,
   dan nama file.
5. Tambahkan README root terjemahan hanya jika file tersebut dipelihara.
6. Tambahkan setiap bahasa yang selesai ke `docs/README.md`.
7. Periksa link di dalam setiap locale.
8. Jalankan `git diff --check`.

Jangan buat direktori bahasa kosong. Bahasa harus muncul di `docs/README.md`
hanya setelah entry point-nya ada.

## Checklist pembaruan sumber

Saat dokumentasi bahasa Inggris berubah setelah terjemahan ada:

1. Perbarui file sumber bahasa Inggris.
2. Perbarui link README terkait atau entry docs hub.
3. Catat apakah file terjemahan memerlukan perubahan konten yang sama.
4. Jaga metrik di [benchmarks.md](benchmarks.md) dan snapshot README tetap sinkron
   saat ukuran binary, jumlah test, jumlah source file, atau LOC berubah.
5. Jalankan command verifikasi lokal dari [development.md](development.md).

## Referensi

Aturan ini selaras dengan panduan dokumentasi publik:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
