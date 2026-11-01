#!/usr/bin/env bash
# Compila lk1st (lk2nd single-device) per il Lumia 1520 "bandit" in un container
# Debian con gcc-arm-none-eabi. Varianti:
#   base    -> come il port KorelisLabs (nessun display in lk, provato su RM-940)
#   splash  -> cont-splash sul framebuffer UEFI (non provato sul 1520)
#   base-0ff -> come base, ingresso a 0x0FF00000 (verificata su RM-937)
# Uso: build-lk1st.sh [base|splash|base-0ff]
set -euo pipefail
VARIANT="${1:-base-0ff}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LK="$ROOT/src/lk2nd"
OUT="$ROOT/kit/lk1st/$VARIANT"
IMG="lk2nd-build:bookworm"

[ -d "$LK/.git" ] || { echo "manca $LK"; exit 1; }

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  docker build -t "$IMG" - <<'DOCKER'
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    make gcc-arm-none-eabi libnewlib-arm-none-eabi device-tree-compiler \
    python3 binutils-arm-none-eabi gcc libc6-dev git ca-certificates && rm -rf /var/lib/apt/lists/*
DOCKER
fi

case "$VARIANT" in
  base)   EXTRA="DEBUG=1 DEBUG_FBCON=0" ;;
  splash) EXTRA="DEBUG=1 DEBUG_FBCON=1 ENABLE_DISPLAY=1 LK2ND_DISPLAY=cont-splash" ;;
  base-0ff) EXTRA="DEBUG=1 DEBUG_FBCON=0 MEMBASE=0x0FF00000" ;;
  *) echo "variante sconosciuta: $VARIANT"; exit 1 ;;
esac

BUILDDIR="build-lk1st-msm8974-$VARIANT"
docker run --rm -u "$(id -u):$(id -g)" -v "$LK:/lk" -w /lk "$IMG" \
  make -j"$(nproc)" TOOLCHAIN_PREFIX=arm-none-eabi- $EXTRA \
       BUILDDIR="$BUILDDIR" LK2ND_BUNDLE_DTB=msm8974-nokia-bandit.dtb lk1st-msm8974

mkdir -p "$OUT"
cp "$LK/$BUILDDIR/lk_s.elf" "$OUT/emmc_appsboot.mbn"   # BootShim vuole l'ELF
cp "$LK/$BUILDDIR/lk2nd/device/dts/msm8974/msm8974-nokia-bandit.dtb" "$OUT/" 2>/dev/null || true
(cd "$OUT" && sha256sum emmc_appsboot.mbn > SHA256SUMS)
echo "== $OUT"; ls -l "$OUT"
