# Installation

La plupart des utilisateurs devraient installer `nllclw` en téléchargeant un
binaire précompilé depuis le dernier GitHub Release. Installez Zig seulement si
vous voulez construire depuis les sources, développer le projet ou exécuter la
test suite. Les builds depuis les sources exigent Zig `0.16.0`.

Utilisez cette page lorsque vous préparez une nouvelle machine, un CI runner, un
container ou un shell de développement embedded existant comme ESP-IDF.

Références officielles:

- [Zig Downloads](https://ziglang.org/download/)
- [Zig Getting Started](https://ziglang.org/learn/getting-started/)
- [ESP-IDF Linux/macOS setup](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/linux-macos-setup.html)
- [ESP-IDF tools guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)

## Installer le binaire de release

1. Ouvrez le
   [dernier GitHub Release](https://github.com/nullclaw/nllclw/releases/latest).
2. Téléchargez l'asset pour votre OS et CPU:
   - macOS/Linux: `nllclw-<target>.bin`
   - Windows: `nllclw-windows-<arch>.zip`
   - Source archive: `nllclw-source-vYYYY.M.D.tar.gz`
3. Extrayez l'asset s'il est empaqueté; les assets `.bin` simples sont prêts à utiliser.
4. Sur macOS/Linux, rendez le binaire exécutable:

```sh
chmod +x nllclw
```

5. Lancez-le directement ou déplacez-le dans un répertoire de `PATH`:

```sh
./nllclw --help
./nllclw init
```

Tant que le dépôt est privé, les téléchargements de releases exigent l'accès à
`nullclaw/nllclw`.

## Matrice de support

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

## Construire depuis les sources

Zig est distribué comme une archive compiler/toolchain autonome. Vous n'avez pas
besoin d'un installateur system-wide. La configuration fiable pour build depuis les sources est:

1. Téléchargez l'archive Zig `0.16.0` exacte pour votre OS et CPU.
2. Extrayez-la dans un répertoire stable.
3. Ajoutez ce répertoire à `PATH`.
4. Vérifiez `zig version`.

`nllclw` est ensuite construit avec:

```sh
zig build --release=small
```

## Vérifier Zig

Après l’installation de Zig pour un build depuis les sources, ces commandes doivent fonctionner:

```sh
zig version
zig env
```

Version attendue:

```text
0.16.0
```

Si la version est différente, corrigez `PATH` avant de compiler `nllclw`.

## Téléchargement direct

Le téléchargement direct est la méthode préférée lorsque vous avez besoin de
Zig `0.16.0` exactement.

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

Ajoutez Zig à votre fichier de démarrage shell:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.zshrc
source ~/.zshrc
zig version
```

Utilisez `~/.bashrc` ou `~/.profile` à la place si votre shell ne lit pas
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

Ajoutez Zig à `PATH`:

```sh
echo 'export PATH="$HOME/tools/zig-0.16.0:$PATH"' >> ~/.profile
. ~/.profile
zig version
```

Si votre interactive shell lit plutôt `~/.bashrc` ou `~/.zshrc`, placez-y la
même ligne `export PATH=...`.

### Windows

1. Téléchargez `zig-x86_64-windows-0.16.0.zip` ou
   `zig-aarch64-windows-0.16.0.zip` depuis
   [ziglang.org/download](https://ziglang.org/download/).
2. Extrayez-le dans un répertoire stable, par exemple:

```text
C:\Tools\zig-0.16.0
```

3. Ajoutez ce répertoire au user `Path`.

PowerShell example:

```powershell
$zig = "C:\Tools\zig-0.16.0"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$zig",
  "User"
)
```

Ouvrez un nouveau terminal et vérifiez:

```powershell
zig version
```

### BSD

La page officielle de téléchargements Zig fournit des archives `0.16.0` pour les
targets BSD comme FreeBSD, NetBSD et OpenBSD. Utilisez le même modèle de
téléchargement direct:

1. Téléchargez l'archive pour votre BSD et CPU.
2. Extrayez-la dans un répertoire stable.
3. Ajoutez le répertoire extrait à `PATH`.
4. Vérifiez `zig version`.

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

Les package managers sont pratiques, mais ils peuvent avancer au-delà de
`0.16.0`. Vérifiez toujours:

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

Si un package manager installe une version Zig différente, utilisez le
téléchargement direct.

## Version Managers

Les version managers sont utiles lorsque vous travaillez sur plusieurs projets
Zig.

La règle est la même: installez ou sélectionnez `0.16.0`, puis vérifiez
`zig version`.

Example workflow:

```sh
zig version
```

Expected:

```text
0.16.0
```

Si votre version manager prend en charge une configuration project-local,
épinglez `0.16.0` pour ce dépôt. Ne comptez pas sur un `master` flottant ou un
development build pour `nllclw`.

## Containers

Une configuration minimale de conteneur doit installer Zig `0.16.0`, copier le
dépôt, puis exécuter `zig build`.

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

Pour les conteneurs aarch64, utilisez `zig-aarch64-linux-0.16.0.tar.xz`.

## GitHub Actions

Si la CI ne fournit pas déjà Zig `0.16.0`, installez-le explicitement ou
utilisez une trusted Zig setup action épinglée à `0.16.0`.

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

## Environnements ESP-IDF

ESP-IDF est le framework de développement d'Espressif pour firmware de classe
ESP32. Il a son propre toolchain, Python environment, `idf.py` et export
scripts. C'est séparé de l'installation de Zig pour `nllclw`.

Il existe deux valid use cases:

1. Vous voulez compiler et exécuter `nllclw` sur votre host machine pendant que
   votre shell a aussi ESP-IDF disponible.
2. Vous voulez un futur projet firmware Zig/ESP-IDF. C'est un autre projet;
   `nllclw` n'est pas du firmware et ne cible pas actuellement ESP-IDF.

### Host Shell avec ESP-IDF et Zig

Installez ESP-IDF avec le guide Espressif. Un layout Linux/macOS courant est:

```sh
mkdir -p "$HOME/esp"
cd "$HOME/esp"
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
. ./export.sh
idf.py --version
```

Installez Zig séparément avec l'une des méthodes de téléchargement direct
ci-dessus, puis rendez les deux outils visibles dans le shell:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"

idf.py --version
zig version
```

Vous pouvez maintenant compiler `nllclw` depuis le même shell:

```sh
cd /path/to/nllclw
zig build --release=small
./zig-out/bin/nllclw --help
```

Le script export ESP-IDF définit des environment variables pour les outils
ESP-IDF. Il n'installe pas Zig et ne transforme pas `nllclw` en application
ESP32.

### Windows ESP-IDF Shell

Sur Windows, installez ESP-IDF avec l'installateur officiel Espressif ou le flux
d'extension VS Code. Ensuite, installez Zig avec les étapes de téléchargement
direct Windows ci-dessus et ouvrez un nouveau prompt ESP-IDF ou PowerShell.

Vérifiez les deux outils:

```powershell
idf.py --version
zig version
```

Si `idf.py` fonctionne mais pas `zig`, ajoutez le répertoire Zig `0.16.0` au
user `Path` et ouvrez un nouveau terminal. Si `zig` fonctionne mais pas
`idf.py`, repartez du flux ESP-IDF terminal/export fourni par votre installation
ESP-IDF.

### Frontière importante ESP-IDF

`nllclw` est un host CLI assistant. Il utilise `std.http.Client`, local files,
stdin/stdout et OS process conventions. Il n'est pas conçu pour s'exécuter sur
un microcontrôleur ESP32 ou dans un firmware ESP-IDF.

Ne vous attendez pas à ce que cela fonctionne:

```sh
zig build -Dtarget=xtensa-esp32-espidf
```

Si vous voulez un composant Zig pour firmware ESP-IDF, traitez cela comme un
projet embarqué séparé avec ses propres target, allocator, networking, TLS,
storage et event-loop decisions.

## Compiler nllclw après l'installation de Zig

Depuis le dépôt:

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

Votre répertoire Zig n'est pas dans `PATH`.

Check:

```sh
echo "$PATH"
```

Ajoutez ensuite le répertoire Zig extrait à votre fichier de démarrage shell et
redémarrez le terminal.

### Mauvaise version de Zig

Vérifiez quel executable est utilisé:

```sh
which zig
zig version
```

Sur Windows PowerShell:

```powershell
Get-Command zig
zig version
```

Déplacez le répertoire Zig `0.16.0` plus tôt dans `PATH`.

### ESP-IDF `idf.py` fonctionne mais `zig` ne fonctionne pas

Les scripts export ESP-IDF configurent seulement les outils ESP-IDF. Installez
Zig séparément et ajoutez-le à `PATH` après le sourcing de `export.sh`:

```sh
. "$HOME/esp/esp-idf/export.sh"
export PATH="$HOME/tools/zig-0.16.0:$PATH"
```

### `zig` fonctionne mais `idf.py` ne fonctionne pas

Sourcez le script export ESP-IDF dans le shell courant:

```sh
. "$HOME/esp/esp-idf/export.sh"
idf.py --version
```

Sur Windows, utilisez le script export ESP-IDF fourni par votre installation
ESP-IDF ou le flux officiel VS Code/installer.
