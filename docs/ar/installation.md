# Installation

ينبغي لمعظم المستخدمين تثبيت `nllclw` عبر تنزيل binary جاهز من أحدث
GitHub Release. ثبّت Zig فقط عندما تريد البناء من source أو تطوير المشروع أو
تشغيل test suite. تتطلب source builds Zig `0.16.0`.

استخدم هذه الصفحة عند إعداد machine جديدة أو CI runner أو container أو existing
embedded development shell مثل ESP-IDF.

المراجع الرسمية:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## تثبيت release binary

1. افتح
   [أحدث GitHub Release](https://github.com/nullclaw/nllclw/releases/latest).
2. نزّل asset المناسب للـ OS والـ CPU لديك:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. استخرج asset إذا كان packaged؛ `.bin` assets الجاهزة يمكن استخدامها مباشرة.
4. على macOS/Linux، اجعل binary قابلاً للتنفيذ:

```sh
chmod +x nllclw
```

5. شغّله مباشرة أو انقله إلى directory ضمن `PATH`:

```sh
./nllclw --help
./nllclw init
```

ما دام repository خاصاً، تتطلب downloads من releases صلاحية وصول إلى
`nullclaw/nllclw`.

## Support Matrix

| Environment | Goal | Status |
|---|---|---|
| macOS host | Build and run `nllclw` | Supported |
| Linux host | Build and run `nllclw` | Supported |
| Windows host | Build and run `nllclw` | Supported |
| BSD host | تثبيت Zig من official archive، ثم build | Expected to work where Zig `0.16.0` supports the host |
| Container | Build and test in CI/dev containers | Supported |
| GitHub Actions | Build and test in CI | Supported |
| ESP-IDF shell | Build host `nllclw` while ESP-IDF tools are also active | Supported |
| ESP32/ESP-IDF firmware target | Run `nllclw` on a microcontroller | Not supported |

## البناء من source

يوزع Zig كself-contained compiler/toolchain archive. لا تحتاج system-wide installer.
The reliable source-build setup is:

1. Download exact Zig `0.16.0` archive المناسب لOS وCPU لديك.
2. Extract إلى stable directory.
3. Add that directory to `PATH`.
4. Verify `zig version`.

بعد ذلك يُبنى `nllclw` عبر:

```sh
zig build --release=small
```

## التحقق من Zig

After installing Zig for a source build, these commands should work:

```sh
zig version
zig env
```

Expected version:

```text
0.16.0
```

إذا كان version مختلفاً، أصلح `PATH` قبل build `nllclw`.

## Direct Download

Direct download هو preferred method عندما تحتاج بالضبط Zig `0.16.0`.

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

أضف Zig إلى shell startup file:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

استخدم `~/.bashrc` أو `~/.profile` بدلاً من ذلك إذا كان shell لا يقرأ `~/.zshrc`.

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

أضف Zig إلى `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

إذا كان interactive shell يقرأ `~/.bashrc` أو `~/.zshrc` بدلاً من ذلك، ضع line
نفسها `export PATH=...` هناك.

### Windows

1. نزّل `zig-x86_64-windows-0.16.0.zip` أو `zig-aarch64-windows-0.16.0.zip` من
   [ziglang.org/download](https://ziglang.org/download/).
2. Extract إلى stable directory، مثلاً:

```text
C:\Tools\zig-0.16.0
```

3. أضف ذلك directory إلى user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

افتح terminal جديداً وتحقق:

```powershell
zig version
```

### BSD

توفر official Zig downloads page `0.16.0` archives لBSD targets مثل FreeBSD وNetBSD
وOpenBSD. استخدم direct-download pattern نفسه:

1. Download archive المناسب لBSD وCPU لديك.
2. Extract إلى stable directory.
3. Add extracted directory to `PATH`.
4. Verify `zig version`.

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

Package managers مريحة، لكنها قد تتقدم بعد `0.16.0`. تحقق دائماً:

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

إذا ثبت package manager إصدار Zig مختلفاً، استخدم direct download.

## Version Managers

Version managers مفيدة عندما تعمل على Zig projects متعددة.

القاعدة نفسها: install أو select `0.16.0`، ثم verify `zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

إذا كان version manager لديك يدعم project-local configuration، فثبّت `0.16.0` لهذا
repository. لا تعتمد على floating `master` أو development build ل`nllclw`.

## Containers

ينبغي لminimal container setup تثبيت Zig `0.16.0`، وcopy repository، ثم run
`zig build`.

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

لaarch64 containers، استخدم `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

إذا لم يكن CI يوفر Zig `0.16.0` بالفعل، ثبته explicitly أو استخدم trusted Zig
setup action pinned to `0.16.0`.

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

ESP-IDF هو development framework من Espressif لfirmware من فئة ESP32. له toolchain
وPython environment و`idf.py` وexport scripts خاصة به. هذا منفصل عن تثبيت Zig
ل`nllclw`.

هناك حالتا استخدام valid:

1. تريد build وتشغيل `nllclw` على host machine بينما shell لديه ESP-IDF available أيضاً.
2. تريد Zig/ESP-IDF firmware project مستقبلياً. هذا مشروع مختلف؛ `nllclw` ليس firmware
   ولا يستهدف ESP-IDF حالياً.

### Host Shell With ESP-IDF and Zig

ثبّت ESP-IDF باستخدام دليل Espressif. Layout شائع على Linux/macOS:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

ثبّت Zig separately باستخدام أحد direct-download methods أعلاه، ثم اجعل الأداتين
visible في shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

يمكنك الآن build `nllclw` من shell نفسه:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

يضبط ESP-IDF export script environment variables لأدوات ESP-IDF. لا يثبت Zig، ولا
يجعل `nllclw` ESP32 application.

### Windows ESP-IDF Shell

على Windows، ثبّت ESP-IDF باستخدام installer الرسمي من Espressif أو VS Code
extension workflow. ثم ثبّت Zig بخطوات Windows direct-download أعلاه وافتح fresh
ESP-IDF command prompt أو PowerShell.

تحقق من الأداتين:

```powershell
idf.py --version
zig version
```

إذا كان `idf.py` يعمل لكن `zig` لا يعمل، أضف Zig `0.16.0` directory إلى user `Path`
وافتح terminal جديداً. إذا كان `zig` يعمل لكن `idf.py` لا يعمل، ابدأ من ESP-IDF
terminal/export workflow الذي توفره ESP-IDF installation لديك.

### Important ESP-IDF Boundary

`nllclw` هو host CLI assistant. يستخدم `std.http.Client` وlocal files وstdin/stdout
وOS process conventions. لم يُصمم للعمل على ESP32 microcontroller أو داخل ESP-IDF
firmware.

لا تتوقع أن يعمل هذا:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

إذا أردت Zig component لESP-IDF firmware، فتعامل مع ذلك كمشروع embedded منفصل
بtarget وallocator وnetworking وTLS وstorage وevent-loop decisions خاصة به.

## Building nllclw After Zig Is Installed

من repository:

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

Zig directory لديك ليست على `PATH`.

Check:

```sh
echo "$PATH"
```

ثم أضف extracted Zig directory إلى shell startup file وأعد تشغيل terminal.

### Wrong Zig Version

تحقق من executable المستخدم:

```sh
which zig
zig version
```

On Windows PowerShell:

```powershell
Get-Command zig
zig version
```

انقل Zig `0.16.0` directory إلى موضع أبكر في `PATH`.

### ESP-IDF `idf.py` Works but `zig` Does Not

ESP-IDF export scripts تضبط ESP-IDF tools فقط. ثبّت Zig separately وأضفه إلى `PATH`
بعد sourcing `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` Works but `idf.py` Does Not

Source ESP-IDF export script في shell الحالي:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

على Windows، استخدم ESP-IDF export script الذي توفره ESP-IDF installation لديك أو
official VS Code/installer workflow.
