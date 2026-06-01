# Installation

Most users should install `nllclw` by downloading a prebuilt binary from the
latest GitHub Release. Install Zig only when you want to build from source,
develop the project, or run the test suite. Source builds require Zig `0.16.0`.

Use this page when you are setting up a new machine, CI runner, container, or an
existing embedded development shell such as ESP-IDF.

Official references:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Install the Release Binary

1. Open the
   [latest GitHub Release](https://github.com/nullclaw/nllclw/releases/latest).
2. Download the asset for your OS and CPU:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Extract the asset if it is packaged; plain `.bin` assets are ready to use.
4. On macOS/Linux, make the binary executable:

```sh
chmod +x nllclw
```

5. Run it directly or move it to a directory on `PATH`:

```sh
./nllclw --help
./nllclw init
```

While the repository is private, release downloads require access to
`nullclaw/nllclw`.

## Support Matrix

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

## Build From Source

Zig is distributed as a self-contained compiler/toolchain archive. You do not
need a system-wide installer. The reliable source-build setup is:

1. Download the exact Zig `0.16.0` archive for your OS and CPU.
2. Extract it into a stable directory.
3. Add that directory to `PATH`.
4. Verify `zig version`.

`nllclw` is then built with:

```sh
zig build --release=small
```

## Verify Zig

After installing Zig for a source build, these commands should work:

```sh
zig version
zig env
```

Expected version:

```text
0.16.0
```

If the version is different, fix `PATH` before building `nllclw`.

## Direct Download

Direct download is the preferred method when you need exactly Zig `0.16.0`.

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

Add Zig to your shell startup file:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Use `~/.bashrc` or `~/.profile` instead if your shell does not read `~/.zshrc`.

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

Add Zig to `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

If your interactive shell reads `~/.bashrc` or `~/.zshrc` instead, put the same
`export PATH=...` line there.

### Windows

1. Download `zig-x86_64-windows-0.16.0.zip` or
   `zig-aarch64-windows-0.16.0.zip` from
   [ziglang.org/download](https://ziglang.org/download/).
2. Extract it to a stable directory, for example:

```text
C:\Tools\zig-0.16.0
```

3. Add that directory to the user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

Open a new terminal and verify:

```powershell
zig version
```

### BSD

The official Zig downloads page provides `0.16.0` archives for BSD targets such
as FreeBSD, NetBSD, and OpenBSD. Use the same direct-download pattern:

1. Download the archive for your BSD and CPU.
2. Extract it into a stable directory.
3. Add the extracted directory to `PATH`.
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

Package managers are convenient, but they may move ahead of `0.16.0`. Always
verify:

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

If a package manager installs a different Zig version, use direct download.

## Version Managers

Version managers are useful when you work on multiple Zig projects.

The rule is the same: install or select `0.16.0`, then verify `zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

If your version manager supports project-local configuration, pin `0.16.0` for
this repository. Do not rely on a floating `master` or development build for
`nllclw`.

## Containers

A minimal container setup should install Zig `0.16.0`, copy the repository, then
run `zig build`.

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

For aarch64 containers, use `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

If CI does not already provide Zig `0.16.0`, install it explicitly or use a
trusted Zig setup action pinned to `0.16.0`.

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

ESP-IDF is Espressif's development framework for ESP32-class firmware. It has
its own toolchain, Python environment, `idf.py`, and export scripts. That is
separate from installing Zig for `nllclw`.

There are two valid use cases:

1. You want to build and run `nllclw` on your host machine while your shell also
   has ESP-IDF available.
2. You want a future Zig/ESP-IDF firmware project. That is a different project;
   `nllclw` is not firmware and does not currently target ESP-IDF.

### Host Shell With ESP-IDF and Zig

Install ESP-IDF using Espressif's guide. A common Linux/macOS layout is:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

Install Zig separately using one of the direct-download methods above, then make
both tools visible in the shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

Now you can build `nllclw` from the same shell:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

The ESP-IDF export script sets environment variables for ESP-IDF tools. It does
not install Zig, and it does not make `nllclw` an ESP32 application.

### Windows ESP-IDF Shell

On Windows, install ESP-IDF using Espressif's official installer or VS Code
extension workflow. Then install Zig with the Windows direct-download steps
above and open a fresh ESP-IDF command prompt or PowerShell.

Verify both tools:

```powershell
idf.py --version
zig version
```

If `idf.py` works but `zig` does not, add the Zig `0.16.0` directory to the user
`Path` and open a new terminal. If `zig` works but `idf.py` does not, start from
the ESP-IDF terminal/export workflow provided by your ESP-IDF installation.

### Important ESP-IDF Boundary

`nllclw` is a host CLI assistant. It uses `std.http.Client`, local files,
stdin/stdout, and OS process conventions. It is not designed to run on an ESP32
microcontroller or inside ESP-IDF firmware.

Do not expect this to work:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

If you want a Zig component for ESP-IDF firmware, treat that as a separate
embedded project with its own target, allocator, networking, TLS, storage, and
event-loop decisions.

## Building nllclw After Zig Is Installed

From the repository:

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

Your Zig directory is not on `PATH`.

Check:

```sh
echo "$PATH"
```

Then add the extracted Zig directory to your shell startup file and restart the
terminal.

### Wrong Zig Version

Check which executable is being used:

```sh
which zig
zig version
```

On Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Move the Zig `0.16.0` directory earlier in `PATH`.

### ESP-IDF `idf.py` Works but `zig` Does Not

ESP-IDF export scripts configure ESP-IDF tools only. Install Zig separately and
add it to `PATH` after sourcing `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` Works but `idf.py` Does Not

Source the ESP-IDF export script in the current shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

On Windows, use the ESP-IDF export script provided by your ESP-IDF installation
or the official VS Code/installer workflow.
