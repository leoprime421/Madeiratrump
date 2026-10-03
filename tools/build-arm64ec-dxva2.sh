#!/bin/bash
# Build Wine's dxva2.dll for ARM64EC and stage it into Madeira.app.
set -euo pipefail

R="$(cd "$(dirname "$0")/.." && pwd)"
MINGW="${MINGW:-$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin}"
TOOLS="${1:-$R/wine/build-native}"
B="${WINE_EC_BUILD:-$R/wine/build-arm64ec}"
OUT="$R/app/Madeira/arm64ec-windows"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

export PATH="$MINGW:$PATH"
test -x "$MINGW/arm64ec-w64-mingw32-clang" || {
  echo "::error::llvm-mingw ARM64EC compiler not found at $MINGW"
  exit 1
}
test -d "$R/wine/dlls/dxva2" || {
  echo "::error::wine/dlls/dxva2 is missing"
  exit 1
}

if [ ! -f "$B/Makefile" ]; then
  mkdir -p "$B"
  (
    cd "$B"
    "$R/wine/configure" --enable-archs=arm64ec --without-x --disable-tests       --without-freetype --without-gnutls       --with-wine-tools="$TOOLS"
  ) > "$B.configure.log" 2>&1 || {
    tail -80 "$B.configure.log" || true
    exit 1
  }
fi

mkdir -p "$B/dlls/dxva2/arm64ec-windows"
make -C "$B" -j"$JOBS" dlls/dxva2/arm64ec-windows/dxva2.dll   > "$B.dxva2.log" 2>&1 || {
    grep -n -m20 -B2 -A5 "error:" "$B.dxva2.log" || tail -80 "$B.dxva2.log"
    exit 1
  }

SRC="$B/dlls/dxva2/arm64ec-windows/dxva2.dll"
test -s "$SRC"
mkdir -p "$OUT"
cp "$SRC" "$OUT/dxva2.dll.tmp"
"$MINGW/llvm-strip" "$OUT/dxva2.dll.tmp" || true

python3 - "$OUT/dxva2.dll.tmp" <<'PY'
import struct, sys
p=sys.argv[1]
d=open(p,'rb').read()
pe=struct.unpack_from('<I',d,0x3c)[0]
size=struct.unpack_from('<I',d,pe+24+56)[0]
target=size+0x10000
if len(d)<target:
    with open(p,'ab') as f:
        f.write(b'\0'*(target-len(d)))
PY
mv "$OUT/dxva2.dll.tmp" "$OUT/dxva2.dll"
echo "::notice::ARM64EC dxva2.dll staged ($(wc -c < "$OUT/dxva2.dll" | tr -d ' ') bytes)"
