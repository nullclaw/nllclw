# Pengembangan

Command dan konvensi untuk mengubah `nllclw`.

## Persyaratan

- Zig `0.16.0`
- Tidak ada package dependency selain Zig stdlib

Periksa metadata package:

```sh
cat build.zig.zon
```

## Command build

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

Pemeriksaan release cross-target yang digunakan proyek:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Command test

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

Langkah test default mencakup:

- modul package publik;
- modul executable;
- `src/all_tests.zig`, yang mengimpor modul internal untuk cakupan compile dan
  behavior.

Sebelum menyerahkan perubahan, jalankan gate lokal penuh:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

## Metrik

Ukuran binary, startup, RAM, jumlah test, jumlah source, dan command reproduksi
didokumentasikan di [benchmarks.md](benchmarks.md).

## Menambahkan preset provider

Preset provider berada di `src/providers.zig`.

Checklist:

1. Tambahkan enum tag `ProviderKind`.
2. Tambahkan parsing konfigurasi di `src/config/resolve.zig`.
3. Resolve endpoint dan headers di `src/providers.zig`.
4. Tambahkan test untuk endpoint, headers, konfigurasi invalid, dan header
   injection.
5. Dokumentasikan provider di [configuration.md](configuration.md).

Pertahankan request body tetap provider-neutral kecuali provider masih
kompatibel dengan kontrak minimal Chat Completions.

## Menambahkan channel

Channel berada di `src/channels/` ketika merupakan orkestrasi yang menghadap
pengguna.

Checklist:

1. Pertahankan parsing dan I/O di modul channel.
2. Gunakan `runtime.Runtime` untuk konfigurasi, HTTP, memory, tools, dan
   completions.
3. Hindari logika provider atau filesystem langsung di channel kecuali itu
   adalah state khusus channel, seperti Telegram offsets.
4. Tambahkan teks command/help di `src/channels/cli.zig` jika channel diluncurkan
   dari executable utama.
5. Letakkan wire parsing/formatting yang dapat digunakan ulang di modul protocol
   saudara saat channel memiliki surface protocol, seperti WebSocket di
   `src/websocket.zig`.
6. Tambahkan test untuk pengenalan command, parsing protocol, dan error mapping.
7. Dokumentasikan channel di [channels.md](channels.md).

## Menambahkan tool

Tools berada di `src/tools/` dan didaftarkan di `src/tools/catalog.zig`. Lihat
[tools.md](tools.md) untuk checklist tool lengkap.

Versi singkat:

- definisikan `chat.ToolDefinition`;
- parse argument dengan `std.json`;
- kembalikan owned UTF-8 text;
- batasi output;
- letakkan capability local-state di balik flag konfigurasi eksplisit;
- test behavior positif dan negatif.

## Menambahkan storage memory

Domain memory berada di `src/memory.zig`; storage konkret berada di
`src/adapters/`.

Untuk menambahkan storage backend lain:

1. Implementasikan `memory.TranscriptStore` dan/atau `memory.FactStore`.
2. Jauhkan detail file/database/network khusus backend dari `memory.zig`.
3. Hubungkan backend di `runtime.zig`.
4. Tambahkan adapter tests untuk malformed data, bounds, duplicate keys, dan
   deletion.

## Aturan dokumentasi

- Jaga `README.md` tetap terstruktur, praktis, dan berguna untuk belajar.
- Simpan dokumentasi panjang bahasa Inggris di `docs/en/`.
- Jadikan `docs/README.md` sebagai indeks bahasa dan cantumkan hanya bahasa
  dengan entry point nyata.
- Letakkan terjemahan README dalam file terpisah seperti `README.ru.md`.
- Pertahankan urutan section README bahasa Inggris dalam file README terjemahan.
- Gunakan Mermaid diagrams agar GitHub merendernya secara native.
- Setiap capability runtime baru memerlukan dokumentasi konfigurasi dan catatan
  keamanan.
- Setiap command baru harus muncul di README atau [channels.md](channels.md).
- Setiap docs page baru harus ditautkan dari [English docs hub](README.md) dan,
  jika menghadap pengguna, dari [README](../../README.md) root.
- Ikuti [localization.md](localization.md) untuk penulisan siap-terjemah.
