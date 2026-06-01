# Desarrollo

Comandos y convenciones para cambiar `nllclw`.

## Requisitos

- Zig `0.16.0`
- Sin dependencias de paquetes más allá de Zig stdlib

Revisa la metadata del paquete:

```sh
cat build.zig.zon
```

## Comandos de compilación

```sh
zig build
zig build --release=small
zig build --release=small -Dsize-tuned=false
zig build -Dshell-tool=true
```

Comprobaciones release cross-target usadas por el proyecto:

```sh
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

## Comandos de prueba

```sh
zig fmt --check build.zig build.zig.zon $(rg --files src -g '*.zig')
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small --summary all
```

El paso de pruebas por defecto cubre:

- el módulo público del paquete;
- el módulo executable;
- `src/all_tests.zig`, que importa módulos internos para cobertura de
  compilación y comportamiento.

Antes de devolver cambios, ejecuta el gate local completo:

```sh
zig fmt build.zig build.zig.zon $(find src -name '*.zig' -type f | sort)
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small
./zig-out/bin/nllclw --help >/dev/null
strings ./zig-out/bin/nllclw | rg 'shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS|cmd\.exe|sh -c' || true
git diff --check
```

## Métricas

El tamaño del binario, el arranque, la RAM, los conteos de pruebas, los conteos
de fuentes y los comandos de reproducción están documentados en
[benchmarks.md](benchmarks.md).

## Añadir un preset de proveedor

Los presets de proveedores viven en `src/providers.zig`.

Checklist:

1. Añade un enum tag de `ProviderKind`.
2. Añade parsing de configuración en `src/config/resolve.zig`.
3. Resuelve endpoint y headers en `src/providers.zig`.
4. Añade pruebas para endpoint, headers, configuración inválida e inyección de
   headers.
5. Documenta el proveedor en [configuration.md](configuration.md).

Mantén el cuerpo de solicitud provider-neutral salvo que el proveedor siga
siendo compatible con el contrato mínimo de Chat Completions.

## Añadir un canal

Los canales pertenecen en `src/channels/` cuando son orquestación de cara al
usuario.

Checklist:

1. Mantén parsing e I/O en el módulo del canal.
2. Usa `runtime.Runtime` para configuración, HTTP, memoria, herramientas y
   completions.
3. Evita lógica directa de proveedor o sistema de archivos en el canal salvo que
   sea estado específico del canal, como offsets de Telegram.
4. Añade texto de comando/ayuda en `src/channels/cli.zig` si el canal se lanza
   desde el executable principal.
5. Pon parsing/formateo wire reutilizable en un módulo de protocolo hermano
   cuando el canal tenga una superficie de protocolo, como WebSocket en
   `src/websocket.zig`.
6. Añade pruebas para reconocimiento de comandos, parsing de protocolo y mapeo
   de errores.
7. Documenta el canal en [channels.md](channels.md).

## Añadir una herramienta

Las herramientas pertenecen en `src/tools/` y se registran en
`src/tools/catalog.zig`. Consulta [tools.md](tools.md) para el checklist
completo de herramientas.

La versión corta:

- define un `chat.ToolDefinition`;
- parsea argumentos con `std.json`;
- devuelve texto UTF-8 owned;
- limita la salida;
- pon capacidades de estado local detrás de flags explícitos de configuración;
- prueba comportamiento positivo y negativo.

## Añadir almacenamiento de memoria

El dominio de memoria vive en `src/memory.zig`; el almacenamiento concreto vive
en `src/adapters/`.

Para añadir otro storage backend:

1. Implementa `memory.TranscriptStore` y/o `memory.FactStore`.
2. Mantén los detalles específicos de archivo/base de datos/red fuera de
   `memory.zig`.
3. Conecta el backend en `runtime.zig`.
4. Añade adapter tests para datos malformed, bounds, duplicate keys y deletion.

## Reglas de documentación

- Mantén `README.md` estructurado, práctico y útil para aprender.
- Mantén la documentación larga en inglés en `docs/en/`.
- Mantén `docs/README.md` como índice de idiomas y lista solo idiomas con un
  punto de entrada real.
- Pon traducciones del README en archivos separados como `README.ru.md`.
- Conserva el orden de secciones del README inglés en los README traducidos.
- Usa diagramas Mermaid para que GitHub los renderice de forma nativa.
- Cada nueva capacidad de runtime necesita documentación de configuración y
  notas de seguridad.
- Cada nuevo comando debe aparecer en README o [channels.md](channels.md).
- Cada nueva docs page debe estar enlazada desde el
  [English docs hub](README.md) y, cuando sea de cara al usuario, desde el
  [README](../../README.md) raíz.
- Sigue [localization.md](localization.md) para escritura lista para traducir.
