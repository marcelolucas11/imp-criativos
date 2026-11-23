#!/bin/bash
# 1.0.0-beta.21: compila a libjpeg-turbo (estática, Apple Silicon, macOS 14+) para o Otimizador em Lote.
# O app usa a TurboJPEG só para gravar JPEG com subamostragem escolhida (4:2:0 / 4:4:4),
# baseline ou progressivo e perfil sRGB limpo — coisas que o ImageIO da Apple não deixa escolher.
#
# Saída (fora do Git, ver .gitignore):
#   Vendor/libjpeg-turbo/lib/libturbojpeg.a   biblioteca estática ligada ao app
#   Vendor/CTurboJPEG/turbojpeg.h             cabeçalho usado pelo module.modulemap (import CTurboJPEG)
#
# Uso: scripts/build_libjpeg_turbo.sh   (rodado pelo GitHub Actions antes do xcodegen; pula se já estiver compilada)
set -euo pipefail

VERSION="3.2.1"
SHA256="c27ad72a68da151177929aa969ae773a2da5ac2af9ce946079314fdac8cece7f"
URL="https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$VERSION/libjpeg-turbo-$VERSION.tar.gz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/libjpeg-turbo"
HEADER="$ROOT/Vendor/CTurboJPEG/turbojpeg.h"

if [ -f "$OUT/lib/libturbojpeg.a" ] && [ -f "$HEADER" ] && [ "$(cat "$OUT/VERSION" 2>/dev/null)" = "$VERSION" ]; then
  echo "libjpeg-turbo $VERSION já compilada em $OUT"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Baixando libjpeg-turbo $VERSION…"
curl -fsSL --retry 3 -o "$WORK/src.tar.gz" "$URL"
echo "$SHA256  $WORK/src.tar.gz" | shasum -a 256 -c -
tar xzf "$WORK/src.tar.gz" -C "$WORK"

rm -rf "$OUT"
cmake -S "$WORK/libjpeg-turbo-$VERSION" -B "$WORK/build" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX="$OUT" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
  -DWITH_TURBOJPEG=ON -DWITH_TOOLS=OFF -DWITH_JAVA=OFF
cmake --build "$WORK/build" -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
cmake --install "$WORK/build"

# Só a biblioteca da TurboJPEG fica na pasta de busca (evita ligar a libjpeg por engano)
find "$OUT/lib" -maxdepth 1 -type f ! -name 'libturbojpeg.a' -delete
cp "$OUT/include/turbojpeg.h" "$HEADER"
cp "$WORK/libjpeg-turbo-$VERSION/LICENSE.md" "$OUT/LICENSE.md"
echo "$VERSION" > "$OUT/VERSION"
echo "libjpeg-turbo $VERSION pronta:"
ls -la "$OUT/lib"
