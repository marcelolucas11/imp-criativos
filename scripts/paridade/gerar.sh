#!/bin/bash
# 1.0.0-beta.27: gera o arquivo de paridade Mac → Windows (ver scripts/paridade/main.swift). Só roda no macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/windows/tests/IMPCriativos.Tests/fixtures/paridade-mac.json}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FILES=$(find "$ROOT/Sources/IMPCriativos" -name '*.swift' ! -name 'IMPCriativosApp.swift')
swiftc -O -module-name IMPParidade -I "$ROOT/Vendor/CTurboJPEG" -L "$ROOT/Vendor/libjpeg-turbo/lib" \
  $FILES "$ROOT/scripts/paridade/main.swift" -o "$WORK/paridade"
"$WORK/paridade" "$OUT"
