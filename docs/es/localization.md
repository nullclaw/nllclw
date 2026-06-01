# Localización

El inglés es el idioma fuente de la documentación de `nllclw`. Mantén primero
completos los cambios en inglés y luego traduce desde los archivos ingleses
actuales.

## Estructura de archivos

| Ruta | Propósito |
|---|---|
| `README.md` | Resumen del proyecto en inglés para GitHub. |
| `README.<locale>.md` | Archivos README traducidos opcionales en la raíz. |
| `docs/README.md` | Índice de idiomas. |
| `docs/en/` | Documentación larga en inglés. |
| `docs/<locale>/` | Documentación larga traducida futura. |

Usa etiquetas de idioma en minúsculas al estilo BCP 47 para los directorios
cuando sea posible: `ru`, `es`, `pt-BR`, `zh-CN`, `ja` y similares.

## Contrato de traducción

- Refleja la lista de archivos de `docs/en/`, salvo que un archivo sea solo para
  inglés.
- Mantén el mismo orden de secciones de nivel superior que la fuente inglesa.
- Mantén sin cambios los nombres de comandos, variables de entorno, rutas de
  archivo, URL, claves JSON, identificadores Zig y nombres de protocolos.
- Traduce la prosa, los encabezados, las descripciones de tablas y los
  comentarios explicativos.
- Conserva los enlaces relativos. Actualiza solo el segmento de locale cuando
  enlaces a una página traducida.
- No traduzcas salida generada por comandos salvo que sea prosa mostrada a los
  usuarios.
- No añadas afirmaciones traducidas que no estén en la fuente inglesa.
- Actualiza `docs/README.md` cuando un nuevo directorio de idioma sea útil para
  los usuarios.

## Escribir inglés para traducción

La calidad de la traducción empieza en la fuente inglesa.

- Usa oraciones cortas y directas.
- Prefiere la voz activa.
- Evita modismos, bromas, jerga y referencias culturales específicas.
- Define un término la primera vez que aparece.
- Mantén una instrucción o hecho por oración cuando sea práctico.
- Mantén las listas paralelas: empieza cada elemento con el mismo tipo de palabra.
- Evita "this", "that" o "it" cuando el sustantivo pueda ser ambiguo.
- Usa fechas exactas en vez de fechas relativas en documentación duradera.
- Mantén capturas de pantalla y diagramas como opcionales; el texto debe llevar
  la instrucción.

## Términos protegidos

No traduzcas estos términos salvo que un idioma tenga una traducción técnica
ampliamente aceptada y el significado se mantenga exacto.

| Término | Razón |
|---|---|
| `nllclw` | Nombre del producto y del binario. |
| Zig | Nombre del lenguaje de programación. |
| Chat Completions | Contrato de API del proveedor. |
| OpenAI, OpenRouter | Nombres de proveedores. |
| WebSocket, Telegram, JSONL, SSE | Nombres de protocolos o formatos. |
| `NLLCLW_*` | Espacio de nombres de variables de entorno. |
| `src/`, `docs/en/`, `config.json`, `.env` | Rutas y nombres de archivo literales. |
| `shell_exec` | Nombre de herramienta y límite de seguridad. |

## Despliegue en doce idiomas

Al añadir el conjunto de traducciones planificado:

1. Termina primero los cambios en inglés.
2. Elige las etiquetas de locale exactas.
3. Copia `docs/en/` a cada `docs/<locale>/`.
4. Traduce la prosa mientras conservas comandos, claves de configuración,
   bloques de código y nombres de archivo.
5. Añade README traducidos en la raíz solo cuando se mantengan.
6. Añade cada idioma completado a `docs/README.md`.
7. Revisa los enlaces dentro de cada locale.
8. Ejecuta `git diff --check`.

No crees directorios de idioma vacíos. Un idioma debe aparecer en
`docs/README.md` solo después de que exista su punto de entrada.

## Checklist de actualización de la fuente

Cuando la documentación inglesa cambie después de que existan traducciones:

1. Actualiza el archivo fuente en inglés.
2. Actualiza enlaces relacionados del README o entradas del docs hub.
3. Anota si los archivos traducidos necesitan el mismo cambio de contenido.
4. Mantén sincronizadas las métricas en [benchmarks.md](benchmarks.md) y el
   snapshot del README cuando cambien tamaño de binario, conteos de pruebas,
   conteos de archivos fuente o LOC.
5. Ejecuta los comandos locales de verificación de [development.md](development.md).

## Referencias

Estas reglas están alineadas con guías públicas de documentación:

- [GitHub Docs: Writing content to be translated](https://docs.github.com/en/contributing/writing-for-github-docs/writing-content-to-be-translated)
- [GitHub Docs: Basic writing and formatting syntax](https://docs.github.com/articles/basic-writing-and-formatting-syntax)
- [Google developer documentation style guide: READMEs](https://google.github.io/styleguide/docguide/READMEs.html)
- [Read the Docs: Localization and internationalization](https://docs.readthedocs.com/platform/latest/localization.html)
