# Documentation nllclw en français

Le README du dépôt est le point d'entrée rapide. Ces documents couvrent
l'installation, l'utilisation, la sécurité et le développement plus en détail.

| Document | Objectif |
|---|---|
| [installation.md](installation.md) | Installez d’abord un binaire de release, ou installez Zig `0.16.0` pour construire depuis les sources. |
| [getting-started.md](getting-started.md) | Configurez un fournisseur et lancez l’assistant depuis un binaire de release ou un build depuis les sources. |
| [architecture.md](architecture.md) | Frontières du système, flux de requêtes, carte des modules et forme de l'API publique. |
| [configuration.md](configuration.md) | Toutes les clés de configuration, le comportement de `config.json` et `.env`, les presets de fournisseurs et les règles de validation. |
| [context.md](context.md) | Fichiers de contexte de l'assistant tels que `SOUL.md`, `AGENTS.md` et `MEMORY.md`. |
| [memory.md](memory.md) | Mémoire de transcript, mémoire durable de faits, formats JSONL et outils de mémoire. |
| [tools.md](tools.md) | Registre des outils, flux tool-call, capability gates et modèle de sécurité du système de fichiers. |
| [channels.md](channels.md) | CLI, REPL interactif, polling Telegram, canal WebSocket d'interface, heartbeat et comportement daemon. |
| [security.md](security.md) | Frontières des capacités, sécurité des fichiers locaux, gestion des clés de fournisseur et threat model. |
| [benchmarks.md](benchmarks.md) | Taille du binaire, démarrage, RAM, tests, nombre de fichiers source et commandes de reproduction. |
| [localization.md](localization.md) | Règles d'écriture prêtes pour la traduction et structure attendue de la documentation multilingue. |
| [development.md](development.md) | Commandes de build/test, conventions du projet et recettes d'extension. |

## Ordre de lecture

1. Commencez par le [README](../../README.md) du dépôt pour la vue d'ensemble du projet.
2. Utilisez [installation.md](installation.md) pour installer le binaire de release ou préparer Zig pour les builds depuis les sources.
3. Suivez [getting-started.md](getting-started.md) pour configurer et lancer.
4. Lisez [configuration.md](configuration.md) avant d'utiliser une vraie clé de fournisseur.
5. Lisez [context.md](context.md), [memory.md](memory.md) et [tools.md](tools.md) avant d'activer les capacités locales.
6. Lisez [security.md](security.md) avant d'exécuter dans un répertoire sensible.
7. Lisez [architecture.md](architecture.md) et [development.md](development.md) lorsque vous modifiez le code.
8. Lisez [localization.md](localization.md) avant de traduire la documentation.

## Résumé du design

`nllclw` garde les canaux utilisateur, la composition du runtime, la logique de
l'agent, la résolution du fournisseur, la mémoire, les outils et les adaptateurs
stdlib dans des modules séparés. Le build par défaut n'utilise que Zig et la
bibliothèque standard de Zig au runtime.
