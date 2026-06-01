# Documentación de nllclw en español

El README del repositorio es el punto de entrada rápido. Estos documentos cubren
la instalación, la operación, la seguridad y el desarrollo con más detalle.

| Documento | Propósito |
|---|---|
| [installation.md](installation.md) | Instala primero un release binary, o instala Zig `0.16.0` cuando compiles desde source. |
| [getting-started.md](getting-started.md) | Configura un proveedor y ejecuta el asistente desde un release binary o un build desde source. |
| [architecture.md](architecture.md) | Límites del sistema, flujos de solicitud, mapa de módulos y forma de la API pública. |
| [configuration.md](configuration.md) | Todas las claves de configuración, comportamiento de `config.json` y `.env`, presets de proveedores y reglas de validación. |
| [context.md](context.md) | Archivos de contexto del asistente, como `SOUL.md`, `AGENTS.md` y `MEMORY.md`. |
| [memory.md](memory.md) | Memoria de transcript, memoria durable de hechos, formatos JSONL y herramientas de memoria. |
| [tools.md](tools.md) | Registro de herramientas, flujo tool-call, capability gates y modelo de seguridad del sistema de archivos. |
| [channels.md](channels.md) | CLI, REPL interactivo, polling de Telegram, canal WebSocket para UI, heartbeat y comportamiento daemon. |
| [security.md](security.md) | Límites de capacidades, seguridad de archivos locales, manejo de claves del proveedor y threat model. |
| [benchmarks.md](benchmarks.md) | Tamaño del binario, arranque, RAM, pruebas, conteos de fuentes y comandos de reproducción. |
| [localization.md](localization.md) | Reglas de escritura listas para traducir y la estructura esperada de documentación multilingüe. |
| [development.md](development.md) | Comandos de compilación y prueba, convenciones del proyecto y recetas de extensión. |

## Orden de lectura

1. Empieza con el [README](../../README.md) del repositorio para ver el panorama general del proyecto.
2. Usa [installation.md](installation.md) para instalar el release binary o preparar Zig para builds desde source.
3. Sigue [getting-started.md](getting-started.md) para configurar y ejecutar.
4. Lee [configuration.md](configuration.md) antes de usar una clave real de proveedor.
5. Lee [context.md](context.md), [memory.md](memory.md) y [tools.md](tools.md) antes de habilitar capacidades locales.
6. Lee [security.md](security.md) antes de ejecutar en un directorio sensible.
7. Lee [architecture.md](architecture.md) y [development.md](development.md) cuando modifiques el código.
8. Lee [localization.md](localization.md) antes de traducir documentación.

## Resumen de diseño

`nllclw` mantiene los canales de usuario, la composición del runtime, la lógica
del agente, la resolución del proveedor, la memoria, las herramientas y los
adaptadores stdlib en módulos separados. La compilación por defecto usa solo Zig
y la biblioteca estándar de Zig en tiempo de ejecución.
