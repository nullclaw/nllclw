# Installation

大多数用户应从最新 GitHub Release 下载 prebuilt binary 来安装 `nllclw`。
只有在需要从 source 构建、开发项目或运行 test suite 时才需要安装 Zig。
Source builds 需要 Zig `0.16.0`。

当你设置新机器、CI runner、container，或现有 embedded development shell
（例如 ESP-IDF）时，请使用本页面。

Official references：

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## 安装 release binary

1. 打开
   [最新 GitHub Release](https://github.com/nullclaw/nllclw/releases/latest)。
2. 下载适合你的 OS 和 CPU 的 asset：
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. 如果 asset 是 packaged，请解压；plain `.bin` assets 可以直接使用。
4. 在 macOS/Linux 上，将 binary 设为 executable：

```sh
chmod +x nllclw
```

5. 直接运行，或移动到 `PATH` 中的 directory：

```sh
./nllclw --help
./nllclw init
```

Repository 保持 private 时，release downloads 需要 `nullclaw/nllclw` access。

## Support Matrix

| Environment | Goal | Status |
|---|---|---|
| macOS host | 构建并运行 `nllclw` | Supported |
| Linux host | 构建并运行 `nllclw` | Supported |
| Windows host | 构建并运行 `nllclw` | Supported |
| BSD host | 从 official archive 安装 Zig，然后 build | Expected to work where Zig `0.16.0` supports the host |
| Container | 在 CI/dev containers 中 build 和 test | Supported |
| GitHub Actions | 在 CI 中 build 和 test | Supported |
| ESP-IDF shell | 在 ESP-IDF tools 同时 active 时 build host `nllclw` | Supported |
| ESP32/ESP-IDF firmware target | 在 microcontroller 上运行 `nllclw` | Not supported |

## 从 source 构建

Zig 以 self-contained compiler/toolchain archive 分发。你不需要 system-wide
installer。可靠设置流程是：

1. 下载与你的 OS 和 CPU 匹配的精确 Zig `0.16.0` archive。
2. 解压到稳定目录。
3. 将该目录加入 `PATH`。
4. 验证 `zig version`。

之后用以下命令 build `nllclw`：

```sh
zig build --release=small
```

## 验证 Zig

After installing Zig for a source build, these commands should work:

```sh
zig version
zig env
```

Expected version：

```text
0.16.0
```

如果 version 不同，在 build `nllclw` 前先修正 `PATH`。

## Direct Download

当你需要精确 Zig `0.16.0` 时，direct download 是首选方法。

### macOS

Apple Silicon：

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz
tar -xf zig-aarch64-macos-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-aarch64-macos-0.16.0" "$HOME/tools/zig-0.16.0"
```

Intel macOS：

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-x86_64-macos-0.16.0.tar.xz
tar -xf zig-x86_64-macos-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-x86_64-macos-0.16.0" "$HOME/tools/zig-0.16.0"
```

把 Zig 加入 shell startup file：

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

如果你的 shell 不读取 `~/.zshrc`，请改用 `~/.bashrc` 或 `~/.profile`。

### Linux

x86_64 Linux：

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz
tar -xf zig-x86_64-linux-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-x86_64-linux-0.16.0" "$HOME/tools/zig-0.16.0"
```

aarch64 Linux：

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
curl -LO https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz
tar -xf zig-aarch64-linux-0.16.0.tar.xz
ln -sfn "$HOME/tools/zig-aarch64-linux-0.16.0" "$HOME/tools/zig-0.16.0"
```

把 Zig 加入 `PATH`：

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

如果你的 interactive shell 改为读取 `~/.bashrc` 或 `~/.zshrc`，把同一行
`export PATH=...` 放在那里。

### Windows

1. 从 [ziglang.org/download](https://ziglang.org/download/) 下载
   `zig-x86_64-windows-0.16.0.zip` 或 `zig-aarch64-windows-0.16.0.zip`。
2. 解压到稳定目录，例如：

```text
C:\Tools\zig-0.16.0
```

3. 将该目录加入用户 `Path`。

PowerShell example：

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

打开新 terminal 并验证：

```powershell
zig version
```

### BSD

官方 Zig downloads 页面提供面向 FreeBSD、NetBSD 和 OpenBSD 等 BSD targets 的
`0.16.0` archives。使用同样的 direct-download pattern：

1. 下载与你的 BSD 和 CPU 匹配的 archive。
2. 解压到稳定目录。
3. 将解压出的目录加入 `PATH`。
4. 验证 `zig version`。

Example shape：

```sh
mkdir -p "$HOME/tools"
cd "$HOME/tools"
# Download the matching 0.16.0 BSD archive from ziglang.org/download.
tar -xf zig-*-0.16.0.tar.xz
export PATH="$HOME/tools/<extracted-zig-directory>:$PATH"
zig version
```

## Package Managers

Package managers 很方便，但它们可能会超过 `0.16.0`。始终验证：

```sh
zig version
```

macOS Homebrew：

```sh
brew install zig
zig version
```

macOS MacPorts：

```sh
sudo port install zig
zig version
```

Windows WinGet：

```powershell
winget install -e --id zig.zig
zig version
```

Windows Chocolatey：

```powershell
choco install zig
zig version
```

Windows Scoop：

```powershell
scoop install zig
zig version
```

Linux：

```sh
# Use your distribution package manager only if it provides Zig 0.16.0.
zig version
```

如果 package manager 安装了不同的 Zig version，请使用 direct download。

## Version Managers

当你同时处理多个 Zig projects 时，version managers 很有用。

规则相同：install 或 select `0.16.0`，然后验证 `zig version`。

Example workflow：

```sh
zig version
```

Expected：

```text
0.16.0
```

如果你的 version manager 支持 project-local configuration，请为本 repository
pin `0.16.0`。不要为 `nllclw` 依赖 floating `master` 或 development build。

## Containers

Minimal container setup 应安装 Zig `0.16.0`、复制 repository，然后运行
`zig build`。

Example Linux x86_64 Dockerfile fragment：

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

aarch64 containers 使用 `zig-aarch64-linux-0.16.0.tar.xz`。

## GitHub Actions

如果 CI 尚未提供 Zig `0.16.0`，请显式安装，或使用可信的 Zig setup action 并
pin 到 `0.16.0`。

Generic direct-download shape：

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

ESP-IDF 是 Espressif 面向 ESP32-class firmware 的 development framework。它有
自己的 toolchain、Python environment、`idf.py` 和 export scripts。这与为
`nllclw` 安装 Zig 是分开的。

有两个 valid use cases：

1. 你想在 host machine 上 build 和 run `nllclw`，同时 shell 中也有 ESP-IDF。
2. 你想做未来的 Zig/ESP-IDF firmware project。那是另一个项目；`nllclw` 不是
   firmware，当前也不 target ESP-IDF。

### Host Shell With ESP-IDF and Zig

按 Espressif guide 安装 ESP-IDF。常见 Linux/macOS layout：

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

使用上面的 direct-download 方法之一单独安装 Zig，然后让两个 tools 都在 shell
中可见：

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

现在可以从同一个 shell build `nllclw`：

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

ESP-IDF export script 会为 ESP-IDF tools 设置 environment variables。它不会安装
Zig，也不会让 `nllclw` 变成 ESP32 application。

### Windows ESP-IDF Shell

在 Windows 上，使用 Espressif official installer 或 VS Code extension workflow
安装 ESP-IDF。然后按上面的 Windows direct-download steps 安装 Zig，并打开新的
ESP-IDF command prompt 或 PowerShell。

验证两个 tools：

```powershell
idf.py --version
zig version
```

如果 `idf.py` 可用但 `zig` 不可用，请将 Zig `0.16.0` directory 加入 user
`Path` 并打开新 terminal。如果 `zig` 可用但 `idf.py` 不可用，请从你的 ESP-IDF
installation 提供的 ESP-IDF terminal/export workflow 开始。

### Important ESP-IDF Boundary

`nllclw` 是 host CLI assistant。它使用 `std.http.Client`、local files、
stdin/stdout 和 OS process conventions。它不是为在 ESP32 microcontroller 上或
ESP-IDF firmware 内运行而设计的。

不要期待以下命令可用：

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

如果你想要一个用于 ESP-IDF firmware 的 Zig component，请把它作为单独的
embedded project 处理，配套自己的 target、allocator、networking、TLS、storage
和 event-loop decisions。

## Building nllclw After Zig Is Installed

从 repository：

```sh
zig build
zig build --release=small
./zig-out/bin/nllclw --help
```

运行 tests：

```sh
zig build test --summary all
zig build test --summary all -Dshell-tool=true
```

本项目使用的 cross-target release checks：

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Troubleshooting

### `zig: command not found`

你的 Zig directory 不在 `PATH` 上。

Check：

```sh
echo "$PATH"
```

然后将解压出的 Zig directory 加入 shell startup file，并重启 terminal。

### Wrong Zig Version

检查正在使用哪个 executable：

```sh
which zig
zig version
```

在 Windows PowerShell：

```powershell
Get-Command zig
zig version
```

把 Zig `0.16.0` directory 移到 `PATH` 更靠前的位置。

### ESP-IDF `idf.py` Works but `zig` Does Not

ESP-IDF export scripts 只配置 ESP-IDF tools。请单独安装 Zig，并在 source
`export.sh` 后将它加入 `PATH`：

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` Works but `idf.py` Does Not

在当前 shell 中 source ESP-IDF export script：

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

在 Windows 上，使用你的 ESP-IDF installation 提供的 ESP-IDF export script，或
official VS Code/installer workflow。
