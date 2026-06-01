# Установка

Большинству пользователей стоит установить `nllclw`, скачав готовый binary из
последнего GitHub Release. Zig нужен только если вы собираете из source,
разрабатываете проект или запускаете test suite. Source builds требуют Zig
`0.16.0`.

Используйте эту страницу при настройке новой машины, CI runner, container или
существующей embedded development shell, например ESP-IDF.

Официальные ссылки:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Установка release binary

1. Откройте
   [последний GitHub Release](https://github.com/nullclaw/nllclw/releases/latest).
2. Скачайте asset для вашей OS и CPU:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Распакуйте asset, если он packaged; plain `.bin` assets можно использовать напрямую.
4. На macOS/Linux сделайте binary executable:

```sh
chmod +x nllclw
```

5. Запустите напрямую или переместите в directory из `PATH`:

```sh
./nllclw --help
./nllclw init
```

Пока repository private, downloads требуют доступ к `nullclaw/nllclw`.

## Матрица поддержки

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

## Сборка из source

Zig распространяется как self-contained compiler/toolchain archive. System-wide
installer не нужен. Надежная настройка для source-build:

1. Скачайте точный архив Zig `0.16.0` для вашей OS и CPU.
2. Распакуйте его в стабильный каталог.
3. Добавьте этот каталог в `PATH`.
4. Проверьте `zig version`.

После этого `nllclw` собирается так:

```sh
zig build --release=small
```

## Проверка Zig

После установки Zig для source build должны работать команды:

```sh
zig version
zig env
```

Ожидаемая версия:

```text
0.16.0
```

Если версия отличается, исправьте `PATH` перед сборкой `nllclw`.

## Прямая загрузка

Direct download — предпочтительный метод, когда нужен ровно Zig `0.16.0`.

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

Добавьте Zig в shell startup file:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Используйте `~/.bashrc` или `~/.profile`, если ваша shell не читает
`~/.zshrc`.

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

Добавьте Zig в `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Если ваша interactive shell читает `~/.bashrc` или `~/.zshrc`, поместите ту же
строку `export PATH=...` туда.

### Windows

1. Скачайте `zig-x86_64-windows-0.16.0.zip` или
   `zig-aarch64-windows-0.16.0.zip` со страницы
   [ziglang.org/download](https://ziglang.org/download/).
2. Распакуйте в стабильный каталог, например:

```text
C:\Tools\zig-0.16.0
```

3. Добавьте этот каталог в user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

Откройте новый terminal и проверьте:

```powershell
zig version
```

### BSD

Официальная страница загрузок Zig предоставляет archives `0.16.0` для BSD
targets, таких как FreeBSD, NetBSD и OpenBSD. Используйте тот же
direct-download pattern:

1. Скачайте archive для вашей BSD и CPU.
2. Распакуйте в стабильный каталог.
3. Добавьте распакованный каталог в `PATH`.
4. Проверьте `zig version`.

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

Package managers удобны, но могут уйти вперед от `0.16.0`. Всегда проверяйте:

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

Если package manager устанавливает другую версию Zig, используйте direct
download.

## Version Managers

Version managers полезны, когда вы работаете с несколькими Zig projects.

Правило то же: install или select `0.16.0`, затем verify `zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

Если ваш version manager поддерживает project-local configuration, pin
`0.16.0` для этого repository. Не полагайтесь на floating `master` или
development build для `nllclw`.

## Containers

Minimal container setup должен установить Zig `0.16.0`, скопировать repository,
затем запустить `zig build`.

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

Для aarch64 containers используйте `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

Если CI еще не предоставляет Zig `0.16.0`, установите его явно или используйте
trusted Zig setup action, pinned to `0.16.0`.

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

ESP-IDF — development framework Espressif для ESP32-class firmware. У него есть
собственный toolchain, Python environment, `idf.py` и export scripts. Это
отдельно от установки Zig для `nllclw`.

Есть два valid use cases:

1. Вы хотите собрать и запустить `nllclw` на host machine, пока ваша shell
   также имеет ESP-IDF available.
2. Вы хотите будущий Zig/ESP-IDF firmware project. Это другой project;
   `nllclw` не является firmware и сейчас не target ESP-IDF.

### Host Shell With ESP-IDF and Zig

Установите ESP-IDF по guide Espressif. Common Linux/macOS layout:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

Установите Zig отдельно одним из direct-download methods выше, затем сделайте
оба инструмента видимыми в shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

Теперь можно собрать `nllclw` из той же shell:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

ESP-IDF export script задает environment variables для ESP-IDF tools. Он не
устанавливает Zig и не делает `nllclw` ESP32 application.

### Windows ESP-IDF Shell

На Windows установите ESP-IDF через official installer Espressif или VS Code
extension workflow. Затем установите Zig с Windows direct-download steps выше и
откройте свежий ESP-IDF command prompt или PowerShell.

Проверьте оба tools:

```powershell
idf.py --version
zig version
```

Если `idf.py` работает, а `zig` нет, добавьте каталог Zig `0.16.0` в user
`Path` и откройте новый terminal. Если `zig` работает, а `idf.py` нет, начните
с ESP-IDF terminal/export workflow, предоставленного вашей ESP-IDF installation.

### Важная граница ESP-IDF

`nllclw` — host CLI assistant. Он использует `std.http.Client`, local files,
stdin/stdout и OS process conventions. Он не рассчитан на запуск на ESP32
microcontroller или внутри ESP-IDF firmware.

Не ожидайте, что это сработает:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

Если вам нужен Zig component для ESP-IDF firmware, рассматривайте это как
отдельный embedded project со своим target, allocator, networking, TLS,
storage и event-loop decisions.

## Сборка nllclw после установки Zig

Из repository:

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

Ваш каталог Zig не находится в `PATH`.

Check:

```sh
echo "$PATH"
```

Затем добавьте extracted Zig directory в shell startup file и перезапустите
terminal.

### Неверная версия Zig

Проверьте, какой executable используется:

```sh
which zig
zig version
```

В Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Переместите каталог Zig `0.16.0` раньше в `PATH`.

### ESP-IDF `idf.py` работает, но `zig` нет

ESP-IDF export scripts настраивают только ESP-IDF tools. Установите Zig
отдельно и добавьте его в `PATH` после sourcing `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` работает, но `idf.py` нет

Source ESP-IDF export script в текущей shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

На Windows используйте ESP-IDF export script, предоставленный вашей ESP-IDF
installation, или официальный VS Code/installer workflow.
