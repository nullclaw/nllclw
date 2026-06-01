# Installation

ほとんどのユーザーは、最新の GitHub Release から prebuilt binary をダウンロードして
`nllclw` をインストールしてください。Source から build する、project を開発する、
または test suite を実行する場合だけ Zig をインストールします。Source builds には
Zig `0.16.0` が必要です。

新しい machine、CI runner、container、または ESP-IDF のような existing embedded
development shell を setup するときにこの page を使います。

Official references:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Release binary をインストールする

1. [最新の GitHub Release](https://github.com/nullclaw/nllclw/releases/latest) を開きます。
2. OS と CPU に合う asset をダウンロードします:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Asset が packaged の場合は展開します。Plain `.bin` assets はそのまま使えます。
4. macOS/Linux では binary を executable にします:

```sh
chmod +x nllclw
```

5. 直接実行するか、`PATH` 上の directory に移動します:

```sh
./nllclw --help
./nllclw init
```

Repository が private の間、release downloads には `nullclaw/nllclw` への
access が必要です。

## Support Matrix

| Environment | Goal | Status |
|---|---|---|
| macOS host | `nllclw` を build and run | Supported |
| Linux host | `nllclw` を build and run | Supported |
| Windows host | `nllclw` を build and run | Supported |
| BSD host | Official archive から Zig を install し、その後 build | Expected to work where Zig `0.16.0` supports the host |
| Container | CI/dev containers で build and test | Supported |
| GitHub Actions | CI で build and test | Supported |
| ESP-IDF shell | ESP-IDF tools も active なまま host `nllclw` を build | Supported |
| ESP32/ESP-IDF firmware target | Microcontroller で `nllclw` を run | Not supported |

## Source から build する

Zig は self-contained compiler/toolchain archive として distributed されます。
System-wide installer は必要ありません。Reliable setup は次の通りです:

1. OS と CPU に合う exact Zig `0.16.0` archive を download します。
2. Stable directory に extract します。
3. その directory を `PATH` に add します。
4. `zig version` を verify します。

その後、`nllclw` は次で built されます:

```sh
zig build --release=small
```

## Zig を verify する

After installing Zig for a source build, these commands should work:

```sh
zig version
zig env
```

Expected version:

```text
0.16.0
```

Version が異なる場合、`nllclw` を build する前に `PATH` を fix します。

## Direct Download

Exactly Zig `0.16.0` が必要な場合、direct download が preferred method です。

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

Zig を shell startup file に add:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Shell が `~/.zshrc` を読まない場合は `~/.bashrc` または `~/.profile` を使います。

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

Zig を `PATH` に add:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Interactive shell が代わりに `~/.bashrc` または `~/.zshrc` を読む場合、同じ
`export PATH=...` line をそこに置きます。

### Windows

1. [ziglang.org/download](https://ziglang.org/download/) から
   `zig-x86_64-windows-0.16.0.zip` または `zig-aarch64-windows-0.16.0.zip` を download します。
2. Stable directory に extract します。例:

```text
C:\Tools\zig-0.16.0
```

3. その directory を user `Path` に add します。

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

New terminal を開いて verify:

```powershell
zig version
```

### BSD

Official Zig downloads page は FreeBSD、NetBSD、OpenBSD などの BSD targets 向けに
`0.16.0` archives を提供しています。同じ direct-download pattern を使います:

1. BSD と CPU に合う archive を download します。
2. Stable directory に extract します。
3. Extracted directory を `PATH` に add します。
4. `zig version` を verify します。

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

Package managers は便利ですが、`0.16.0` より先に進んでいる場合があります。
常に verify してください:

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

Package manager が異なる Zig version を install した場合は direct download を使います。

## Version Managers

複数の Zig projects に取り組む場合、version managers は useful です。

Rule は同じです: `0.16.0` を install または select し、`zig version` を verify します。

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

Version manager が project-local configuration を support している場合、この
repository では `0.16.0` に pin します。`nllclw` では floating `master` や development
build に rely しないでください。

## Containers

Minimal container setup では Zig `0.16.0` を install し、repository を copy してから
`zig build` を run します。

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

aarch64 containers では `zig-aarch64-linux-0.16.0.tar.xz` を使います。

## GitHub Actions

CI が Zig `0.16.0` を already provide していない場合、explicitly install するか、
`0.16.0` に pinned された trusted Zig setup action を使います。

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

## ESP-IDF Environments

ESP-IDF は ESP32-class firmware のための Espressif の development framework です。
独自の toolchain、Python environment、`idf.py`、export scripts を持ちます。
これは `nllclw` のために Zig を install することとは separate です。

Valid use cases は 2 つあります:

1. Shell で ESP-IDF も available な状態で、host machine 上の `nllclw` を build and run したい。
2. 将来の Zig/ESP-IDF firmware project が欲しい。これは別 project です。
   `nllclw` は firmware ではなく、currently ESP-IDF を target していません。

### Host Shell With ESP-IDF and Zig

Espressif の guide に従って ESP-IDF を install します。Common Linux/macOS layout:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

上記 direct-download methods のいずれかで Zig を separately install し、両方の tools を
shell で visible にします:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

これで同じ shell から `nllclw` を build できます:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

ESP-IDF export script は ESP-IDF tools の environment variables を set します。
Zig を install せず、`nllclw` を ESP32 application にもしません。

### Windows ESP-IDF Shell

Windows では、Espressif の official installer または VS Code extension workflow
で ESP-IDF を install します。その後、上記 Windows direct-download steps で Zig
を install し、fresh ESP-IDF command prompt または PowerShell を開きます。

両方の tools を verify:

```powershell
idf.py --version
zig version
```

`idf.py` が動いて `zig` が動かない場合、Zig `0.16.0` directory を user `Path` に
add し、新しい terminal を開きます。`zig` が動いて `idf.py` が動かない場合、
ESP-IDF installation が提供する ESP-IDF terminal/export workflow から始めます。

### Important ESP-IDF Boundary

`nllclw` は host CLI assistant です。`std.http.Client`、local files、stdin/stdout、
OS process conventions を使います。ESP32 microcontroller 上や ESP-IDF firmware
内で run するようには designed されていません。

これが動くとは期待しないでください:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

ESP-IDF firmware 用の Zig component が欲しい場合、それは separate embedded project
として扱い、独自の target、allocator、networking、TLS、storage、event-loop decisions を持たせます。

## Building nllclw After Zig Is Installed

Repository から:

```sh
zig build
zig build --release=small
./zig-out/bin/nllclw --help
```

Tests を run:

```sh
zig build test --summary all
zig build test --summary all -Dshell-tool=true
```

This project で使われる cross-target release checks:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Troubleshooting

### `zig: command not found`

Zig directory が `PATH` 上にありません。

Check:

```sh
echo "$PATH"
```

次に extracted Zig directory を shell startup file に add し、terminal を restart します。

### Wrong Zig Version

どの executable が使われているか check:

```sh
which zig
zig version
```

On Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Zig `0.16.0` directory を `PATH` のより前に移動します。

### ESP-IDF `idf.py` Works but `zig` Does Not

ESP-IDF export scripts は ESP-IDF tools だけを configure します。Zig を separately
install し、`export.sh` を source した後で `PATH` に add します:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` Works but `idf.py` Does Not

Current shell で ESP-IDF export script を source します:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

Windows では、ESP-IDF installation が提供する ESP-IDF export script または official
VS Code/installer workflow を使います。
