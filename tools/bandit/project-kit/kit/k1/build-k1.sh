#!/usr/bin/env bash
# Builds kit/k1/boot-k1.img: kernel bandit (zImage-dtb) + ramdisk with the
# static K1 init. RAM boot only: fastboot boot boot-k1.img
set -euo pipefail
K="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$K/../.." && pwd)"
ZIMG="$P/kernel/out/arch/arm/boot/zImage-dtb"
MKBOOTIMG="$P/los18/system/tools/mkbootimg/mkbootimg.py"
[ -f "$ZIMG" ] || { echo "manca $ZIMG (build-env/build-kernel.sh)"; exit 1; }

IMG=k0-armhf:bookworm
docker image inspect "$IMG" >/dev/null 2>&1 || docker build -q -t "$IMG" - <<'DOCKER'
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends gcc-arm-linux-gnueabihf libc6-dev-armhf-cross cpio gzip && rm -rf /var/lib/apt/lists/*
DOCKER

docker run --rm -u "$(id -u):$(id -g)" -v "$K:/k" -w /k "$IMG" bash -c '
set -e
arm-linux-gnueabihf-gcc -O2 -static -march=armv7-a -mfpu=vfpv3-d16 -Wall -o init init.c
rm -rf rd && mkdir -p rd/dev rd/proc rd/sys && cp init rd/init && chmod 755 rd/init
(cd rd && find . | cpio -o -H newc --owner=0:0 2>/dev/null) | gzip -9 > ramdisk-k1.cpio.gz
'

CMDLINE="console=tty0 fbcon=font:SUN12x22 ignore_loglevel nosmp maxcpus=1 msm_tz_restricted=1 androidboot.hardware=bandit rdinit=/init"
python3 "$MKBOOTIMG" --kernel "$ZIMG" --ramdisk "$K/ramdisk-k1.cpio.gz" \
	--base 0x10000000 --pagesize 2048 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x04000000 --tags_offset 0x03e00000 \
	--cmdline "$CMDLINE" -o "$K/boot-k1.img"
(cd "$K" && sha256sum boot-k1.img > boot-k1.img.sha256)
ls -l "$K/boot-k1.img"; echo "cmdline: $CMDLINE"
