#!/usr/bin/env bash
set -euo pipefail

zig fmt --check build.zig build.zig.zon src
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build --release=small

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    bin="./zig-out/bin/nllclw.exe"
    ;;
  *)
    bin="./zig-out/bin/nllclw"
    ;;
esac
"${bin}" --help >/dev/null

if command -v strings >/dev/null 2>&1; then
  shell_markers='shell_exec|NLLCLW_SHELL|NLLCLW_TOOL_TIMEOUT_MS'
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      ;;
    *)
      shell_markers="${shell_markers}|cmd\\.exe|sh -c"
      ;;
  esac
  if strings "${bin}" | grep -E "${shell_markers}"; then
    echo "default binary contains shell-only strings"
    exit 1
  fi
else
  echo "strings is not available; skipping shell-only string scan"
fi

zig build --release=small -Dshell-tool=true
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
