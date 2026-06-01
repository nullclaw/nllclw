# Localisation

L'anglais est la langue source de la documentation de `nllclw`. Terminez d'abord
les changements anglais, puis traduisez depuis les fichiers anglais actuels.

## Organisation des fichiers

| Chemin | Objectif |
|---|---|
| `README.md` | Vue d'ensemble anglaise du projet pour GitHub. |
| `README.<locale>.md` | Fichiers README traduits optionnels à la racine. |
| `docs/README.md` | Index des langues. |
| `docs/en/` | Documentation longue en anglais. |
| `docs/<locale>/` | Future documentation longue traduite. |

Utilisez si possible des language tags minuscules de style BCP 47 pour les
répertoires: `ru`, `es`, `pt-BR`, `zh-CN`, `ja` et similaires.

## Contrat de traduction

- Reproduisez la liste de fichiers de `docs/en/`, sauf si un fichier est
  exclusivement anglais.
- Gardez le même ordre de sections de premier niveau que la source anglaise.
- Ne modifiez pas les noms de commandes, variables d'environnement, chemins de
  fichiers, URL, clés JSON, identifiants Zig et noms de protocoles.
- Traduisez la prose, les titres, les descriptions de tables et les commentaires
  explicatifs.
- Préservez les liens relatifs. Ne mettez à jour que le segment de locale pour
  les liens vers une page traduite.
- Ne traduisez pas la sortie générée par des commandes, sauf s'il s'agit de
  prose affichée aux utilisateurs.
- N'ajoutez pas dans la traduction des affirmations absentes de la source
  anglaise.
- Mettez à jour `docs/README.md` lorsqu'un nouveau répertoire de langue est utile
  aux utilisateurs.

## Écrire l'anglais pour la traduction

La qualité de la traduction commence dans la source anglaise.

- Utilisez des phrases courtes et directes.
- Préférez la voix active.
- Évitez les idiomes, blagues, argot et références culturelles spécifiques.
- Définissez un terme à sa première apparition.
- Gardez une instruction ou un fait par phrase lorsque c'est pratique.
- Gardez les listes parallèles: commencez chaque élément par le même type de mot.
- Évitez "this", "that" ou "it" lorsque le nom pourrait être ambigu.
- Utilisez des dates exactes plutôt que des dates relatives dans la documentation
  durable.
- Gardez les captures d'écran et diagrammes optionnels; le texte doit porter
  l'instruction.

## Termes protégés

Ne traduisez pas ces termes, sauf si la langue possède une traduction technique
largement acceptée et que le sens reste exact.

| Terme | Raison |
|---|---|
| `nllclw` | Nom du produit et du binaire. |
| Zig | Nom du langage de programmation. |
| Chat Completions | Contrat d'API du fournisseur. |
| OpenAI, OpenRouter | Noms de fournisseurs. |
| WebSocket, Telegram, JSONL, SSE | Noms de protocoles ou formats. |
| `NLLCLW_*` | Namespace des variables d'environnement. |
| `src/`, `docs/en/`, `config.json`, `.env` | Chemins et noms de fichiers littéraux. |
| `shell_exec` | Nom d'outil et frontière de sécurité. |

## Déploiement en douze langues

Lors de l'ajout du jeu de traductions prévu:

1. Terminez d'abord les changements anglais.
2. Choisissez les tags de locale exacts.
3. Copiez `docs/en/` vers chaque `docs/<locale>/`.
4. Traduisez la prose en préservant les commandes, clés de configuration, blocs
   de code et noms de fichiers.
5. N'ajoutez des README traduits à la racine que lorsqu'ils sont maintenus.
6. Ajoutez chaque langue terminée à `docs/README.md`.
7. Vérifiez les liens dans chaque locale.
8. Exécutez `git diff --check`.

Ne créez pas de répertoires de langue vides. Une langue ne doit apparaître dans
`docs/README.md` qu'après l'existence de son point d'entrée.

## Checklist de mise à jour de la source

Lorsque la documentation anglaise change après l'existence de traductions:

1. Mettez à jour le fichier source anglais.
2. Mettez à jour les liens README ou les entrées de docs hub associés.
3. Notez si les fichiers traduits ont besoin du même changement de contenu.
4. Gardez les métriques de [benchmarks.md](benchmarks.md) et le snapshot du
   README synchronisés lorsque la taille du binaire, le nombre de tests, le
   nombre de fichiers source ou les LOC changent.
5. Exécutez les commandes locales de vérification de [development.md](development.md).

## Références

Ces règles sont alignées avec des guides publics de documentation:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
