# Installation

अधिकांश users को latest GitHub Release से prebuilt binary download करके
`nllclw` install करना चाहिए। Zig केवल तब install करें जब आप source से build,
project development, या test suite चलाना चाहते हों। Source builds के लिए Zig
`0.16.0` चाहिए।

इस page का उपयोग new machine, CI runner, container, या ESP-IDF जैसे existing
embedded development shell setup करते समय करें।

Official references:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Release binary install करें

1. [Latest GitHub Release](https://github.com/nullclaw/nllclw/releases/latest) खोलें।
2. अपने OS और CPU के लिए asset download करें:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Asset packaged हो तो extract करें; plain `.bin` assets सीधे उपयोग के लिए तैयार हैं।
4. macOS/Linux पर binary executable बनाएँ:

```sh
chmod +x nllclw
```

5. इसे सीधे चलाएँ या `PATH` की किसी directory में ले जाएँ:

```sh
./nllclw --help
./nllclw init
```

Repository private रहने तक release downloads के लिए `nullclaw/nllclw` access
चाहिए।

## Support Matrix

| Environment | Goal | Status |
|---|---|---|
| macOS host | `nllclw` build और run करें | Supported |
| Linux host | `nllclw` build और run करें | Supported |
| Windows host | `nllclw` build और run करें | Supported |
| BSD host | Official archive से Zig install करें, फिर build करें | Expected to work where Zig `0.16.0` supports the host |
| Container | CI/dev containers में build और test करें | Supported |
| GitHub Actions | CI में build और test करें | Supported |
| ESP-IDF shell | ESP-IDF tools active रहते हुए host `nllclw` build करें | Supported |
| ESP32/ESP-IDF firmware target | Microcontroller पर `nllclw` run करें | Not supported |

## Source से build करें

Zig self-contained compiler/toolchain archive के रूप में distributed है। आपको
system-wide installer नहीं चाहिए। The reliable source-build setup is:

1. अपने OS और CPU के लिए exact Zig `0.16.0` archive download करें।
2. उसे stable directory में extract करें।
3. उस directory को `PATH` में add करें।
4. `zig version` verify करें।

फिर `nllclw` इस command से built होता है:

```sh
zig build --release=small
```

## Zig verify करें

After installing Zig for a source build, these commands should work:

```sh
zig version
zig env
```

Expected version:

```text
0.16.0
```

अगर version अलग है, `nllclw` build करने से पहले `PATH` fix करें।

## Direct Download

जब exactly Zig `0.16.0` चाहिए, direct download preferred method है।

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

Zig को shell startup file में add करें:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

अगर आपका shell `~/.zshrc` नहीं पढ़ता, तो `~/.bashrc` या `~/.profile` use करें।

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

Zig को `PATH` में add करें:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

अगर आपका interactive shell इसके बजाय `~/.bashrc` या `~/.zshrc` पढ़ता है, तो वही
`export PATH=...` line वहाँ रखें।

### Windows

1. [ziglang.org/download](https://ziglang.org/download/) से
   `zig-x86_64-windows-0.16.0.zip` या `zig-aarch64-windows-0.16.0.zip` download करें।
2. इसे stable directory में extract करें, उदाहरण:

```text
C:\Tools\zig-0.16.0
```

3. उस directory को user `Path` में add करें।

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

New terminal खोलें और verify करें:

```powershell
zig version
```

### BSD

Official Zig downloads page FreeBSD, NetBSD और OpenBSD जैसे BSD targets के लिए
`0.16.0` archives देता है। Same direct-download pattern use करें:

1. अपने BSD और CPU के लिए archive download करें।
2. Stable directory में extract करें।
3. Extracted directory को `PATH` में add करें।
4. `zig version` verify करें।

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

Package managers convenient हैं, लेकिन वे `0.16.0` से आगे जा सकते हैं। हमेशा verify करें:

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

अगर package manager अलग Zig version install करे, direct download use करें।

## Version Managers

Multiple Zig projects पर काम करते समय version managers useful हैं।

Rule वही है: `0.16.0` install या select करें, फिर `zig version` verify करें।

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

अगर आपका version manager project-local configuration support करता है, इस repository
के लिए `0.16.0` pin करें। `nllclw` के लिए floating `master` या development build
पर rely न करें।

## Containers

Minimal container setup Zig `0.16.0` install करे, repository copy करे, फिर
`zig build` run करे।

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

aarch64 containers के लिए `zig-aarch64-linux-0.16.0.tar.xz` use करें।

## GitHub Actions

अगर CI पहले से Zig `0.16.0` provide नहीं करता, इसे explicitly install करें या
trusted Zig setup action use करें जो `0.16.0` पर pinned हो।

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

ESP-IDF Espressif का ESP32-class firmware development framework है। इसका अपना
toolchain, Python environment, `idf.py`, और export scripts हैं। यह `nllclw` के लिए
Zig install करने से अलग है।

दो valid use cases हैं:

1. आप host machine पर `nllclw` build और run करना चाहते हैं जबकि shell में ESP-IDF
   भी available है।
2. आप भविष्य का Zig/ESP-IDF firmware project चाहते हैं। वह अलग project है;
   `nllclw` firmware नहीं है और currently ESP-IDF target नहीं करता।

### Host Shell With ESP-IDF and Zig

Espressif guide से ESP-IDF install करें। Common Linux/macOS layout:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

ऊपर के direct-download methods में से किसी एक से Zig separately install करें, फिर
दोनों tools shell में visible करें:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

अब same shell से `nllclw` build कर सकते हैं:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

ESP-IDF export script ESP-IDF tools के लिए environment variables set करता है। यह
Zig install नहीं करता, और यह `nllclw` को ESP32 application नहीं बनाता।

### Windows ESP-IDF Shell

Windows पर Espressif के official installer या VS Code extension workflow से
ESP-IDF install करें। फिर ऊपर के Windows direct-download steps से Zig install करें
और fresh ESP-IDF command prompt या PowerShell खोलें।

दोनों tools verify करें:

```powershell
idf.py --version
zig version
```

अगर `idf.py` work करता है लेकिन `zig` नहीं, Zig `0.16.0` directory को user `Path`
में add करें और new terminal खोलें। अगर `zig` work करता है लेकिन `idf.py` नहीं,
तो अपनी ESP-IDF installation के ESP-IDF terminal/export workflow से शुरू करें।

### Important ESP-IDF Boundary

`nllclw` host CLI assistant है। यह `std.http.Client`, local files, stdin/stdout
और OS process conventions use करता है। यह ESP32 microcontroller पर या ESP-IDF
firmware के अंदर run करने के लिए designed नहीं है।

यह work करने की उम्मीद न करें:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

अगर आप ESP-IDF firmware के लिए Zig component चाहते हैं, तो उसे अलग embedded project
मानें, अपने target, allocator, networking, TLS, storage और event-loop decisions के
साथ।

## Building nllclw After Zig Is Installed

Repository से:

```sh
zig build
zig build --release=small
./zig-out/bin/nllclw --help
```

Tests चलाएँ:

```sh
zig build test --summary all
zig build test --summary all -Dshell-tool=true
```

इस project द्वारा इस्तेमाल किए जाने वाले cross-target release checks:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Troubleshooting

### `zig: command not found`

आपकी Zig directory `PATH` पर नहीं है।

Check:

```sh
echo "$PATH"
```

फिर extracted Zig directory को shell startup file में add करें और terminal restart करें।

### Wrong Zig Version

Check करें कौन सा executable use हो रहा है:

```sh
which zig
zig version
```

Windows PowerShell पर:

```powershell
Get-Command zig
zig version
```

Zig `0.16.0` directory को `PATH` में पहले रखें।

### ESP-IDF `idf.py` Works but `zig` Does Not

ESP-IDF export scripts केवल ESP-IDF tools configure करते हैं। Zig separately
install करें और `export.sh` source करने के बाद उसे `PATH` में add करें:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` Works but `idf.py` Does Not

Current shell में ESP-IDF export script source करें:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

Windows पर, अपनी ESP-IDF installation द्वारा provided ESP-IDF export script या
official VS Code/installer workflow use करें।
