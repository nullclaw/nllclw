# Instalación

La mayoría de usuarios debería instalar `nllclw` descargando un binario
precompilado del último GitHub Release. Instala Zig solo si quieres compilar
from source, desarrollar el proyecto o ejecutar la test suite. Los source builds
requieren Zig `0.16.0`.

Usa esta página cuando prepares una máquina nueva, un CI runner, un container o
un shell de desarrollo embedded existente como ESP-IDF.

Referencias oficiales:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Instalar el release binary

1. Abre el
   [último GitHub Release](https://github.com/nullclaw/nllclw/releases/latest).
2. Descarga el asset para tu OS y CPU:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Extrae el asset si está empaquetado; los assets `.bin` planos ya están listos para usar.
4. En macOS/Linux, haz que el binary sea executable:

```sh
chmod +x nllclw
```

5. Ejecútalo directamente o muévelo a un directorio en `PATH`:

```sh
./nllclw --help
./nllclw init
```

Mientras el repositorio sea privado, las descargas de releases requieren acceso
a `nullclaw/nllclw`.

## Matriz de soporte

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

## Compilar desde source

Zig se distribuye como un archivo compiler/toolchain self-contained. No
necesitas un instalador system-wide. El setup fiable para source build es:

1. Descarga el archivo exacto Zig `0.16.0` para tu OS y CPU.
2. Extráelo en un directorio estable.
3. Añade ese directorio a `PATH`.
4. Verifica `zig version`.

Después `nllclw` se compila con:

```sh
zig build --release=small
```

## Verificar Zig

Después de instalar Zig para un source build, estos comandos deben funcionar:

```sh
zig version
zig env
```

Versión esperada:

```text
0.16.0
```

Si la versión es diferente, corrige `PATH` antes de compilar `nllclw`.

## Descarga directa

La descarga directa es el método preferido cuando necesitas exactamente Zig
`0.16.0`.

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

Añade Zig a tu shell startup file:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Usa `~/.bashrc` o `~/.profile` en su lugar si tu shell no lee `~/.zshrc`.

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

Añade Zig a `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Si tu interactive shell lee `~/.bashrc` o `~/.zshrc` en su lugar, pon allí la
misma línea `export PATH=...`.

### Windows

1. Descarga `zig-x86_64-windows-0.16.0.zip` o
   `zig-aarch64-windows-0.16.0.zip` desde
   [ziglang.org/download](https://ziglang.org/download/).
2. Extráelo en un directorio estable, por ejemplo:

```text
C:\Tools\zig-0.16.0
```

3. Añade ese directorio al user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

Abre un terminal nuevo y verifica:

```powershell
zig version
```

### BSD

La página oficial de descargas de Zig proporciona archivos `0.16.0` para BSD
targets como FreeBSD, NetBSD y OpenBSD. Usa el mismo patrón de descarga directa:

1. Descarga el archivo para tu BSD y CPU.
2. Extráelo en un directorio estable.
3. Añade el directorio extraído a `PATH`.
4. Verifica `zig version`.

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

Package managers son convenientes, pero pueden adelantarse a `0.16.0`. Siempre
verifica:

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

Si un package manager instala una versión distinta de Zig, usa descarga directa.

## Version Managers

Version managers son útiles cuando trabajas en varios proyectos Zig.

La regla es la misma: instala o selecciona `0.16.0`, luego verifica
`zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

Si tu version manager soporta project-local configuration, fija `0.16.0` para
este repositorio. No confíes en un `master` flotante ni en una development build
para `nllclw`.

## Containers

Una configuración mínima de contenedor debe instalar Zig `0.16.0`, copiar el
repositorio y luego ejecutar `zig build`.

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

Para contenedores aarch64, usa `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

Si CI todavía no proporciona Zig `0.16.0`, instálalo explícitamente o usa una
trusted Zig setup action fijada a `0.16.0`.

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

## Entornos ESP-IDF

ESP-IDF es el framework de desarrollo de Espressif para firmware de clase
ESP32. Tiene su propio toolchain, Python environment, `idf.py` y export
scripts. Eso es separado de instalar Zig para `nllclw`.

Hay dos valid use cases:

1. Quieres compilar y ejecutar `nllclw` en tu host machine mientras tu shell
   también tiene ESP-IDF disponible.
2. Quieres un futuro proyecto firmware Zig/ESP-IDF. Ese es otro proyecto;
   `nllclw` no es firmware y actualmente no apunta a ESP-IDF.

### Host Shell con ESP-IDF y Zig

Instala ESP-IDF usando la guía de Espressif. Un layout común de Linux/macOS es:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

Instala Zig por separado usando uno de los métodos de descarga directa
anteriores, luego haz visibles ambas herramientas en la shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

Ahora puedes compilar `nllclw` desde la misma shell:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

El export script de ESP-IDF configura environment variables para ESP-IDF tools.
No instala Zig y no convierte `nllclw` en una ESP32 application.

### Windows ESP-IDF Shell

En Windows, instala ESP-IDF usando el instalador oficial de Espressif o el flujo
de extensión de VS Code. Luego instala Zig con los pasos de descarga directa de
Windows anteriores y abre un ESP-IDF command prompt o PowerShell nuevo.

Verifica ambas herramientas:

```powershell
idf.py --version
zig version
```

Si `idf.py` funciona pero `zig` no, añade el directorio Zig `0.16.0` al user
`Path` y abre un terminal nuevo. Si `zig` funciona pero `idf.py` no, empieza
desde el flujo ESP-IDF terminal/export proporcionado por tu instalación ESP-IDF.

### Límite importante de ESP-IDF

`nllclw` es un host CLI assistant. Usa `std.http.Client`, local files,
stdin/stdout y OS process conventions. No está diseñado para ejecutarse en un
microcontrolador ESP32 ni dentro de ESP-IDF firmware.

No esperes que esto funcione:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

Si quieres un componente Zig para ESP-IDF firmware, trátalo como un proyecto
embedded separado con su propio target, allocator, networking, TLS, storage y
event-loop decisions.

## Compilar nllclw después de instalar Zig

Desde el repositorio:

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

Tu directorio Zig no está en `PATH`.

Check:

```sh
echo "$PATH"
```

Luego añade el directorio Zig extraído a tu shell startup file y reinicia el
terminal.

### Versión Zig incorrecta

Revisa qué executable se está usando:

```sh
which zig
zig version
```

En Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Mueve el directorio Zig `0.16.0` antes en `PATH`.

### ESP-IDF `idf.py` funciona pero `zig` no

Los export scripts de ESP-IDF configuran solo ESP-IDF tools. Instala Zig por
separado y añádelo a `PATH` después de sourcing `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` funciona pero `idf.py` no

Source el ESP-IDF export script en la shell actual:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

En Windows, usa el ESP-IDF export script proporcionado por tu instalación
ESP-IDF o el flujo oficial de VS Code/installer.
