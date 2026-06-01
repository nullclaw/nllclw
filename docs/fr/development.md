# Développement

Commandes et conventions pour modifier `nllclw`.

## Prérequis

- Zig `0.16.0`
- Aucune dépendance de paquet au-delà de Zig stdlib

Vérifiez les métadonnées du paquet:

```sh
cat build.zig.zon
```

## Commandes de build

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

Vérifications release cross-target utilisées par le projet:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Commandes de test

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

L'étape de test par défaut couvre:

- le module public du paquet;
- le module executable;
- `src/all_tests.zig`, qui importe des modules internes pour couvrir la
  compilation et le comportement.

Avant de rendre des changements, exécutez le gate local complet:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

## Métriques

La taille du binaire, le démarrage, la RAM, le nombre de tests, le nombre de
sources et les commandes de reproduction sont documentés dans
[benchmarks.md](benchmarks.md).

## Ajouter un preset de fournisseur

Les presets de fournisseurs vivent dans `src/providers.zig`.

Checklist:

1. Ajoutez un enum tag `ProviderKind`.
2. Ajoutez le parsing de configuration dans `src/config/resolve.zig`.
3. Résolvez endpoint et headers dans `src/providers.zig`.
4. Ajoutez des tests pour endpoint, headers, configuration invalide et header
   injection.
5. Documentez le fournisseur dans [configuration.md](configuration.md).

Gardez le corps de requête provider-neutral sauf si le fournisseur reste
compatible avec le contrat minimal Chat Completions.

## Ajouter un canal

Les canaux appartiennent à `src/channels/` lorsqu'ils sont une orchestration
orientée utilisateur.

Checklist:

1. Gardez le parsing et l'I/O dans le module du canal.
2. Utilisez `runtime.Runtime` pour la configuration, HTTP, la mémoire, les
   outils et les completions.
3. Évitez la logique directe de fournisseur ou de système de fichiers dans le
   canal, sauf s'il s'agit d'état spécifique au canal, comme les offsets
   Telegram.
4. Ajoutez le texte de commande/aide dans `src/channels/cli.zig` si le canal est
   lancé depuis l'executable principal.
5. Placez le wire parsing/formatting réutilisable dans un module de protocole
   voisin lorsque le canal possède une surface protocolaire, comme WebSocket
   dans `src/websocket.zig`.
6. Ajoutez des tests pour la reconnaissance de commandes, le parsing de
   protocole et le mapping d'erreurs.
7. Documentez le canal dans [channels.md](channels.md).

## Ajouter un outil

Les outils appartiennent à `src/tools/` et sont enregistrés dans
`src/tools/catalog.zig`. Consultez [tools.md](tools.md) pour la checklist
complète.

Version courte:

- définissez un `chat.ToolDefinition`;
- parsez les arguments avec `std.json`;
- retournez du texte UTF-8 owned;
- plafonnez la sortie;
- placez les capacités d'état local derrière des flags de configuration
  explicites;
- testez les comportements positifs et négatifs.

## Ajouter un stockage de mémoire

Le domaine mémoire vit dans `src/memory.zig`; le stockage concret vit dans
`src/adapters/`.

Pour ajouter un autre storage backend:

1. Implémentez `memory.TranscriptStore` et/ou `memory.FactStore`.
2. Gardez les détails fichier/base de données/réseau spécifiques au backend hors
   de `memory.zig`.
3. Branchez le backend dans `runtime.zig`.
4. Ajoutez des adapter tests pour malformed data, bounds, duplicate keys et
   deletion.

## Règles de documentation

- Gardez `README.md` structuré, pratique et utile pour apprendre.
- Gardez la documentation longue anglaise dans `docs/en/`.
- Gardez `docs/README.md` comme index des langues et ne listez que les langues
  avec un vrai point d'entrée.
- Placez les traductions README dans des fichiers séparés comme `README.ru.md`.
- Préservez l'ordre des sections du README anglais dans les README traduits.
- Utilisez des diagrammes Mermaid pour que GitHub les rende nativement.
- Toute nouvelle capacité runtime nécessite une documentation de configuration
  et des notes de sécurité.
- Toute nouvelle commande doit apparaître dans le README ou [channels.md](channels.md).
- Toute nouvelle docs page doit être liée depuis le [English docs hub](README.md)
  et, lorsqu'elle est orientée utilisateur, depuis le [README](../../README.md)
  racine.
- Suivez [localization.md](localization.md) pour une écriture prête à traduire.
