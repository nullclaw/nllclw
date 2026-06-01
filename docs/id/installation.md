# Instalasi

Sebagian besar pengguna sebaiknya menginstal `nllclw` dengan mengunduh binary
prebuilt dari GitHub Release terbaru. Instal Zig hanya saat Anda ingin build
dari source, mengembangkan proyek, atau menjalankan test suite. Source build
memerlukan Zig `0.16.0`.

Gunakan halaman ini saat menyiapkan mesin baru, CI runner, container, atau shell
embedded development yang sudah ada seperti ESP-IDF.

Referensi resmi:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Instal release binary

1. Buka
   [GitHub Release terbaru](https://github.com/nullclaw/nllclw/releases/latest).
2. Unduh asset untuk OS dan CPU Anda:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Extract asset jika packaged; asset `.bin` biasa siap digunakan langsung.
4. Di macOS/Linux, buat binary executable:

```sh
chmod +x nllclw
```

5. Jalankan langsung atau pindahkan ke directory di `PATH`:

```sh
./nllclw --help
./nllclw init
```

Selama repository private, release downloads memerlukan access ke
`nullclaw/nllclw`.

## Matriks dukungan

| Environment | Goal | Status |
|---|---|---|
| macOS host | Build and run `nllclw` | Supported |
| Linux host | Build and run `nllclw` | Supported |
| Windows host | Build and run `nllclw` | Supported |
| BSD host | Install Zig from official archive, then build | Expected to work where Zig `0.16.0` supports the host |
| Container | Build and test in CI/dev containers | Supported |
| GitHub Actions | Build and test in CI | Supported |
| ESP-IDF shell | Build host `nllclw` while ESP-IDF tools are also active | Supported |
| ESP32/ESP-IDF firmware target | Run `nllclw` on a microcontroller | Not supported |

## Build dari source

Zig didistribusikan sebagai archive compiler/toolchain mandiri. Anda tidak
memerlukan installer system-wide. Setup yang andal:

1. Download archive Zig `0.16.0` yang tepat untuk OS dan CPU Anda.
2. Extract ke direktori stabil.
3. Tambahkan direktori tersebut ke `PATH`.
4. Verifikasi `zig version`.

`nllclw` kemudian dibuild dengan:

```sh
zig build --release=small
```

## Verifikasi Zig

Setelah menginstal Zig untuk source build, command berikut harus bekerja:

```sh
zig version
zig env
```

Versi yang diharapkan:

```text
0.16.0
```

Jika versinya berbeda, perbaiki `PATH` sebelum build `nllclw`.

## Download langsung

Download langsung adalah metode yang disarankan saat Anda memerlukan Zig
`0.16.0` secara tepat.

### macOS

Apple Silicon:

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz
tar -xf zig-aarch64-macos-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-aarch64-macos-0.16.0" "$HOME/tools/zig-0.16.0"
```

Intel macOS:

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-x86_64-macos-0.16.0.tar.xz
tar -xf zig-x86_64-macos-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-x86_64-macos-0.16.0" "$HOME/tools/zig-0.16.0"
```

Tambahkan Zig ke shell startup file:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Gunakan `~/.bashrc` atau `~/.profile` jika shell Anda tidak membaca `~/.zshrc`.

### Linux

x86_64 Linux:

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz
tar -xf zig-x86_64-linux-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-x86_64-linux-0.16.0" "$HOME/tools/zig-0.16.0"
```

aarch64 Linux:

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz
tar -xf zig-aarch64-linux-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-aarch64-linux-0.16.0" "$HOME/tools/zig-0.16.0"
```

Tambahkan Zig ke `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Jika interactive shell Anda membaca `~/.bashrc` atau `~/.zshrc`, letakkan baris
`export PATH=...` yang sama di sana.

### Windows

1. Download `zig-x86_64-windows-0.16.0.zip` atau
   `zig-aarch64-windows-0.16.0.zip` dari
   [ziglang.org/download](https://ziglang.org/download/).
2. Extract ke direktori stabil, misalnya:

```text
C:\Tools\zig-0.16.0
```

3. Tambahkan direktori tersebut ke user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

Buka terminal baru dan verifikasi:

```powershell
zig version
```

### BSD

Halaman download resmi Zig menyediakan archive `0.16.0` untuk target BSD seperti
FreeBSD, NetBSD, dan OpenBSD. Gunakan pola download langsung yang sama:

1. Download archive untuk BSD dan CPU Anda.
2. Extract ke direktori stabil.
3. Tambahkan direktori hasil extract ke `PATH`.
4. Verifikasi `zig version`.

Example shape:

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
# Download the matching 0.16.0 BSD archive from ziglang.org/download.
tar -xf zig-*-0.16.0.tar.xz
export PATH="$HOME/tools/<extracted-zig-directory>:$PATH"
zig version
```

## Package Managers

Package managers praktis, tetapi dapat bergerak melewati `0.16.0`. Selalu
verifikasi:

```sh
zig version
```

macOS Homebrew:

```sh
brew install zig
zig version
```

macOS MacPorts:

```sh
sudo port install zig
zig version
```

Windows WinGet:

```powershell
winget install -e --id zig.zig
zig version
```

Windows Chocolatey:

```powershell
choco install zig
zig version
```

Windows Scoop:

```powershell
scoop install zig
zig version
```

Linux:

```sh
# Use your distribution package manager only if it provides Zig 0.16.0.
zig version
```

Jika package manager menginstal versi Zig berbeda, gunakan download langsung.

## Version Managers

Version managers berguna saat Anda bekerja pada beberapa proyek Zig.

Aturannya sama: instal atau pilih `0.16.0`, lalu verifikasi `zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

Jika version manager mendukung project-local configuration, pin `0.16.0` untuk
repositori ini. Jangan bergantung pada `master` yang floating atau development
build untuk `nllclw`.

## Containers

Setup container minimal harus menginstal Zig `0.16.0`, menyalin repositori,
lalu menjalankan `zig build`.

Example Linux x86_64 Dockerfile fragment:

```Dockerfile
FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils git \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/zig \
  && curl -L https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz \
    | tar -xJ --strip-components=1 -C /opt/zig

ENV PATH="/opt/zig:${PATH}"

WORKDIR /src
COPY . .
RUN zig version && zig build --release=small
```

Untuk container aarch64, gunakan `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

Jika CI belum menyediakan Zig `0.16.0`, instal secara eksplisit atau gunakan
trusted Zig setup action yang dipin ke `0.16.0`.

Generic direct-download shape:

```yaml
steps:
  - uses: actions/checkout@v4
  - name: Install Zig
    run: |
      mkdir -p "$HOME/tools"
      curl -L https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz \
        | tar -xJ -C "$HOME/tools"
      echo "$HOME/tools/zig-x86_64-linux-0.16.0" >> "$GITHUB_PATH"
  - name: Test
    run: |
      zig version
      zig build test --summary all
```

## Lingkungan ESP-IDF

ESP-IDF adalah framework pengembangan Espressif untuk firmware kelas ESP32. Ia
memiliki toolchain, Python environment, `idf.py`, dan export scripts sendiri.
Itu terpisah dari instalasi Zig untuk `nllclw`.

Ada dua valid use cases:

1. Anda ingin membuild dan menjalankan `nllclw` di host machine saat shell Anda
   juga memiliki ESP-IDF available.
2. Anda ingin proyek firmware Zig/ESP-IDF di masa depan. Itu proyek berbeda;
   `nllclw` bukan firmware dan saat ini tidak menargetkan ESP-IDF.

### Host Shell dengan ESP-IDF dan Zig

Instal ESP-IDF dengan panduan Espressif. Layout Linux/macOS yang umum:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

Instal Zig secara terpisah dengan salah satu metode download langsung di atas,
lalu buat kedua alat terlihat di shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

Sekarang Anda dapat build `nllclw` dari shell yang sama:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

ESP-IDF export script mengatur environment variables untuk ESP-IDF tools. Script
itu tidak menginstal Zig dan tidak membuat `nllclw` menjadi aplikasi ESP32.

### Windows ESP-IDF Shell

Di Windows, instal ESP-IDF memakai installer resmi Espressif atau workflow
ekstensi VS Code. Lalu instal Zig dengan langkah download langsung Windows di
atas dan buka ESP-IDF command prompt atau PowerShell baru.

Verifikasi kedua alat:

```powershell
idf.py --version
zig version
```

Jika `idf.py` berfungsi tetapi `zig` tidak, tambahkan direktori Zig `0.16.0` ke
user `Path` dan buka terminal baru. Jika `zig` berfungsi tetapi `idf.py` tidak,
mulai dari ESP-IDF terminal/export workflow yang disediakan instalasi ESP-IDF
Anda.

### Batas penting ESP-IDF

`nllclw` adalah host CLI assistant. Ia memakai `std.http.Client`, local files,
stdin/stdout, dan OS process conventions. Ia tidak dirancang untuk berjalan di
microcontroller ESP32 atau di dalam firmware ESP-IDF.

Jangan harapkan ini berfungsi:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

Jika Anda menginginkan komponen Zig untuk firmware ESP-IDF, anggap itu sebagai
proyek embedded terpisah dengan target, allocator, networking, TLS, storage, dan
event-loop decisions sendiri.

## Build nllclw setelah Zig terpasang

Dari repositori:

```sh
zig build
zig build --release=small
./zig-out/bin/nllclw --help
```

Run tests:

```sh
zig build test --summary all
zig build test --summary all -Dshell-tool=true
```

Cross-target release checks used by this project:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Troubleshooting

### `zig: command not found`

Direktori Zig Anda tidak ada di `PATH`.

Check:

```sh
echo "$PATH"
```

Lalu tambahkan direktori Zig hasil extract ke shell startup file dan restart
terminal.

### Versi Zig salah

Periksa executable mana yang digunakan:

```sh
which zig
zig version
```

Di Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Pindahkan direktori Zig `0.16.0` lebih awal di `PATH`.

### ESP-IDF `idf.py` berfungsi tetapi `zig` tidak

ESP-IDF export scripts hanya mengonfigurasi ESP-IDF tools. Instal Zig secara
terpisah dan tambahkan ke `PATH` setelah sourcing `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` berfungsi tetapi `idf.py` tidak

Source ESP-IDF export script di shell saat ini:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

Di Windows, gunakan ESP-IDF export script yang disediakan instalasi ESP-IDF Anda
atau workflow resmi VS Code/installer.
