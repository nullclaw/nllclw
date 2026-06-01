# Installation

বেশিরভাগ ব্যবহারকারীর `nllclw` install করা উচিত latest GitHub Release থেকে
prebuilt binary download করে। Source থেকে build, project develop, বা test suite
চালাতে চাইলে তবেই Zig install করুন। Source builds-এর জন্য Zig `0.16.0` দরকার।

New machine, CI runner, container, বা ESP-IDF-এর মতো existing embedded development
shell setup করার সময় এই page ব্যবহার করুন।

Official references:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Release binary install

1. [Latest GitHub Release](https://github.com/nullclaw/nllclw/releases/latest) খুলুন।
2. আপনার OS এবং CPU-এর জন্য asset download করুন:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Asset packaged হলে extract করুন; plain `.bin` assets সরাসরি ব্যবহারযোগ্য।
4. macOS/Linux-এ binary executable করুন:

```sh
chmod +x nllclw
```

5. সরাসরি চালান বা `PATH`-এর কোনো directory-তে সরান:

```sh
./nllclw --help
./nllclw init
```

Repository private থাকা অবস্থায় release downloads-এর জন্য `nullclaw/nllclw`
access দরকার।

## Support Matrix

| Environment | Goal | Status |
|---|---|---|
| macOS host | `nllclw` build এবং run | Supported |
| Linux host | `nllclw` build এবং run | Supported |
| Windows host | `nllclw` build এবং run | Supported |
| BSD host | Official archive থেকে Zig install, তারপর build | Expected to work where Zig `0.16.0` supports the host |
| Container | CI/dev containers-এ build এবং test | Supported |
| GitHub Actions | CI-তে build এবং test | Supported |
| ESP-IDF shell | ESP-IDF tools active থাকতেও host `nllclw` build | Supported |
| ESP32/ESP-IDF firmware target | Microcontroller-এ `nllclw` run | Not supported |

## Source থেকে build

Zig self-contained compiler/toolchain archive হিসেবে distributed। System-wide
installer দরকার নেই। The reliable source-build setup is:

1. আপনার OS এবং CPU-এর exact Zig `0.16.0` archive download করুন।
2. Stable directory-তে extract করুন।
3. সেই directory `PATH`-এ add করুন।
4. `zig version` verify করুন।

তারপর `nllclw` build:

```sh
zig build --release=small
```

## Zig verify

After installing Zig for a source build, these commands should work:

```sh
zig version
zig env
```

Expected version:

```text
0.16.0
```

Version আলাদা হলে `nllclw` build করার আগে `PATH` fix করুন।

## Direct Download

Exactly Zig `0.16.0` দরকার হলে direct download preferred method।

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

Zig shell startup file-এ add করুন:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

আপনার shell `~/.zshrc` না পড়লে `~/.bashrc` বা `~/.profile` ব্যবহার করুন।

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

Zig `PATH`-এ add করুন:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Interactive shell এর বদলে `~/.bashrc` বা `~/.zshrc` পড়লে একই `export PATH=...`
line সেখানে রাখুন।

### Windows

1. [ziglang.org/download](https://ziglang.org/download/) থেকে
   `zig-x86_64-windows-0.16.0.zip` বা `zig-aarch64-windows-0.16.0.zip` download করুন।
2. Stable directory-তে extract করুন, যেমন:

```text
C:\Tools\zig-0.16.0
```

3. সেই directory user `Path`-এ add করুন।

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

New terminal খুলে verify করুন:

```powershell
zig version
```

### BSD

Official Zig downloads page FreeBSD, NetBSD, এবং OpenBSD-এর মতো BSD targets-এর
জন্য `0.16.0` archives দেয়। Same direct-download pattern ব্যবহার করুন:

1. আপনার BSD এবং CPU-এর archive download করুন।
2. Stable directory-তে extract করুন।
3. Extracted directory `PATH`-এ add করুন।
4. `zig version` verify করুন।

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

Package managers convenient, কিন্তু তারা `0.16.0` ছাড়িয়ে যেতে পারে। সবসময় verify করুন:

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

Package manager আলাদা Zig version install করলে direct download ব্যবহার করুন।

## Version Managers

Multiple Zig projects-এ কাজ করলে version managers useful।

Rule একই: `0.16.0` install বা select করুন, তারপর `zig version` verify করুন।

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

আপনার version manager project-local configuration support করলে এই repository-এর
জন্য `0.16.0` pin করুন। `nllclw`-এর জন্য floating `master` বা development build-এর
উপর rely করবেন না।

## Containers

Minimal container setup Zig `0.16.0` install করবে, repository copy করবে, তারপর
`zig build` run করবে।

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

aarch64 containers-এর জন্য `zig-aarch64-linux-0.16.0.tar.xz` ব্যবহার করুন।

## GitHub Actions

CI Zig `0.16.0` already provide না করলে explicitly install করুন বা `0.16.0`-এ
pinned trusted Zig setup action ব্যবহার করুন।

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

ESP-IDF হলো ESP32-class firmware-এর জন্য Espressif-এর development framework। এর
নিজস্ব toolchain, Python environment, `idf.py`, এবং export scripts আছে। এটি
`nllclw`-এর জন্য Zig install করার থেকে আলাদা।

দুটি valid use case আছে:

1. Shell-এ ESP-IDF available থাকা অবস্থায় host machine-এ `nllclw` build এবং run করতে চান।
2. ভবিষ্যতের Zig/ESP-IDF firmware project চান। সেটি আলাদা project; `nllclw`
   firmware নয় এবং currently ESP-IDF target করে না।

### Host Shell With ESP-IDF and Zig

Espressif guide দিয়ে ESP-IDF install করুন। Common Linux/macOS layout:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

উপরের direct-download methods-এর একটি দিয়ে Zig separately install করুন, তারপর
দুই tools shell-এ visible করুন:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

এখন একই shell থেকে `nllclw` build করতে পারেন:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

ESP-IDF export script ESP-IDF tools-এর environment variables set করে। এটি Zig
install করে না, এবং `nllclw`-কে ESP32 application বানায় না।

### Windows ESP-IDF Shell

Windows-এ Espressif-এর official installer বা VS Code extension workflow দিয়ে
ESP-IDF install করুন। তারপর উপরের Windows direct-download steps দিয়ে Zig install
করুন এবং fresh ESP-IDF command prompt বা PowerShell খুলুন।

দুই tools verify করুন:

```powershell
idf.py --version
zig version
```

`idf.py` কাজ করলেও `zig` না করলে Zig `0.16.0` directory user `Path`-এ add করুন এবং
new terminal খুলুন। `zig` কাজ করলেও `idf.py` না করলে আপনার ESP-IDF installation
provided ESP-IDF terminal/export workflow থেকে শুরু করুন।

### Important ESP-IDF Boundary

`nllclw` host CLI assistant। এটি `std.http.Client`, local files, stdin/stdout, এবং
OS process conventions ব্যবহার করে। এটি ESP32 microcontroller-এ বা ESP-IDF
firmware-এর ভিতরে run করার জন্য designed নয়।

এটি কাজ করবে বলে আশা করবেন না:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

ESP-IDF firmware-এর জন্য Zig component চাইলে সেটিকে আলাদা embedded project হিসেবে
ধরুন, নিজস্ব target, allocator, networking, TLS, storage, এবং event-loop decisions সহ।

## Building nllclw After Zig Is Installed

Repository থেকে:

```sh
zig build
zig build --release=small
./zig-out/bin/nllclw --help
```

Tests run করুন:

```sh
zig build test --summary all
zig build test --summary all -Dshell-tool=true
```

এই project-এ ব্যবহৃত cross-target release checks:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Troubleshooting

### `zig: command not found`

আপনার Zig directory `PATH`-এ নেই।

Check:

```sh
echo "$PATH"
```

তারপর extracted Zig directory shell startup file-এ add করুন এবং terminal restart করুন।

### Wrong Zig Version

কোন executable ব্যবহৃত হচ্ছে check করুন:

```sh
which zig
zig version
```

On Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Zig `0.16.0` directory `PATH`-এ আগে আনুন।

### ESP-IDF `idf.py` Works but `zig` Does Not

ESP-IDF export scripts শুধু ESP-IDF tools configure করে। Zig separately install
করুন এবং `export.sh` source করার পরে `PATH`-এ add করুন:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` Works but `idf.py` Does Not

Current shell-এ ESP-IDF export script source করুন:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

Windows-এ আপনার ESP-IDF installation provided ESP-IDF export script বা official
VS Code/installer workflow ব্যবহার করুন।
