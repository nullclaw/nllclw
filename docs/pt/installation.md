# Instalação

A maioria dos usuários deve instalar `nllclw` baixando um binário prebuilt do
GitHub Release mais recente. Instale Zig apenas se quiser compilar a partir do
source, desenvolver o projeto ou executar a test suite. Builds a partir do source
exigem Zig `0.16.0`.

Use esta página ao preparar uma máquina nova, CI runner, container ou shell de
desenvolvimento embedded existente como ESP-IDF.

Referências oficiais:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Instalar o binário de release

1. Abra o
   [GitHub Release mais recente](https://github.com/nullclaw/nllclw/releases/latest).
2. Baixe o asset para seu OS e CPU:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Extraia o asset se estiver packaged; assets `.bin` simples já estão prontos para uso.
4. No macOS/Linux, torne o binary executable:

```sh
chmod +x nllclw
```

5. Execute diretamente ou mova para um diretório em `PATH`:

```sh
./nllclw --help
./nllclw init
```

Enquanto o repositório estiver private, release downloads exigem acesso a
`nullclaw/nllclw`.

## Matriz de suporte

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

## Compilar a partir do source

Zig é distribuído como um arquivo compiler/toolchain autocontido. Você não
precisa de um instalador system-wide. The reliable source-build setup is:

1. Baixe o arquivo Zig `0.16.0` exato para seu OS e CPU.
2. Extraia-o em um diretório estável.
3. Adicione esse diretório ao `PATH`.
4. Verifique `zig version`.

Então `nllclw` é compilado com:

```sh
zig build --release=small
```

## Verificar Zig

Depois de instalar Zig para um build a partir do source, estes comandos devem funcionar:

```sh
zig version
zig env
```

Versão esperada:

```text
0.16.0
```

Se a versão for diferente, corrija `PATH` antes de compilar `nllclw`.

## Download direto

Download direto é o método preferido quando você precisa exatamente do Zig
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

Adicione Zig ao seu shell startup file:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Use `~/.bashrc` ou `~/.profile` se seu shell não ler `~/.zshrc`.

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

Adicione Zig ao `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Se seu interactive shell ler `~/.bashrc` ou `~/.zshrc`, coloque a mesma linha
`export PATH=...` lá.

### Windows

1. Baixe `zig-x86_64-windows-0.16.0.zip` ou
   `zig-aarch64-windows-0.16.0.zip` em
   [ziglang.org/download](https://ziglang.org/download/).
2. Extraia para um diretório estável, por exemplo:

```text
C:\Tools\zig-0.16.0
```

3. Adicione esse diretório ao user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

Abra um novo terminal e verifique:

```powershell
zig version
```

### BSD

A página oficial de downloads do Zig fornece archives `0.16.0` para targets BSD
como FreeBSD, NetBSD e OpenBSD. Use o mesmo padrão de download direto:

1. Baixe o archive para seu BSD e CPU.
2. Extraia-o em um diretório estável.
3. Adicione o diretório extraído ao `PATH`.
4. Verifique `zig version`.

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

Package managers são convenientes, mas podem avançar além de `0.16.0`. Sempre
verifique:

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

Se um package manager instalar uma versão diferente do Zig, use download direto.

## Version Managers

Version managers são úteis quando você trabalha em vários projetos Zig.

A regra é a mesma: instale ou selecione `0.16.0`, então verifique
`zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

Se seu version manager oferecer suporte a configuração project-local, fixe
`0.16.0` para este repositório. Não confie em um `master` flutuante ou em um
development build para `nllclw`.

## Containers

Uma configuração mínima de contêiner deve instalar Zig `0.16.0`, copiar o
repositório e então executar `zig build`.

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

Para contêineres aarch64, use `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

Se a CI ainda não fornece Zig `0.16.0`, instale explicitamente ou use uma
trusted Zig setup action fixada em `0.16.0`.

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

## Ambientes ESP-IDF

ESP-IDF é o framework de desenvolvimento da Espressif para firmware da classe
ESP32. Ele tem seu próprio toolchain, Python environment, `idf.py` e export
scripts. Isso é separado de instalar Zig para `nllclw`.

Há dois valid use cases:

1. Você quer compilar e executar `nllclw` na sua host machine enquanto seu shell
   também tem ESP-IDF disponível.
2. Você quer um futuro projeto de firmware Zig/ESP-IDF. Esse é outro projeto;
   `nllclw` não é firmware e atualmente não tem ESP-IDF como target.

### Host Shell com ESP-IDF e Zig

Instale ESP-IDF usando o guia da Espressif. Um layout comum em Linux/macOS é:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

Instale Zig separadamente usando um dos métodos de download direto acima, então
deixe ambas as ferramentas visíveis no shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

Agora você pode compilar `nllclw` pelo mesmo shell:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

O script export do ESP-IDF define environment variables para ferramentas
ESP-IDF. Ele não instala Zig e não transforma `nllclw` em uma aplicação ESP32.

### Windows ESP-IDF Shell

No Windows, instale ESP-IDF usando o instalador oficial da Espressif ou o fluxo
da extensão VS Code. Depois instale Zig com os passos de download direto para
Windows acima e abra um ESP-IDF command prompt ou PowerShell novo.

Verifique ambas as ferramentas:

```powershell
idf.py --version
zig version
```

Se `idf.py` funciona mas `zig` não, adicione o diretório Zig `0.16.0` ao user
`Path` e abra um novo terminal. Se `zig` funciona mas `idf.py` não, comece pelo
fluxo de terminal/export ESP-IDF fornecido pela sua instalação ESP-IDF.

### Limite importante do ESP-IDF

`nllclw` é um host CLI assistant. Ele usa `std.http.Client`, local files,
stdin/stdout e OS process conventions. Ele não foi projetado para rodar em um
microcontrolador ESP32 ou dentro de firmware ESP-IDF.

Não espere que isto funcione:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

Se você quer um componente Zig para firmware ESP-IDF, trate isso como um projeto
embarcado separado com seu próprio target, allocator, networking, TLS, storage e
event-loop decisions.

## Compilar nllclw depois que Zig estiver instalado

A partir do repositório:

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

Seu diretório Zig não está no `PATH`.

Check:

```sh
echo "$PATH"
```

Depois adicione o diretório Zig extraído ao seu shell startup file e reinicie o
terminal.

### Versão errada do Zig

Verifique qual executable está sendo usado:

```sh
which zig
zig version
```

No Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Mova o diretório Zig `0.16.0` para antes no `PATH`.

### ESP-IDF `idf.py` funciona, mas `zig` não

Scripts export do ESP-IDF configuram apenas ferramentas ESP-IDF. Instale Zig
separadamente e adicione-o ao `PATH` depois de fazer source de `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` funciona, mas `idf.py` não

Faça source do script export ESP-IDF no shell atual:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

No Windows, use o script export ESP-IDF fornecido pela sua instalação ESP-IDF ou
o fluxo oficial VS Code/installer.
