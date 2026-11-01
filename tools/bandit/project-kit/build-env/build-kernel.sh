#!/usr/bin/env bash
# Compila il kernel bandit (../kernel) fuori dall'albero Android, con la
# toolchain GCC 4.9 di LineageOS 18.1, nel container los18-build.
# Uscita: ../kernel/out/arch/arm/boot/zImage-dtb
# Uso: build-kernel.sh [target make...]   (default: defconfig + zImage-dtb)
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
src=$(cd -- "$here/../los18" && pwd)
kern=$(cd -- "$here/../kernel" && pwd)
targets="${*:-zImage-dtb}"
exec docker run --rm -v "$src:/src:ro" -v "$kern:/kernel" -w /kernel \
	--name "bandit18-kernel-$$" los18-build bash -c "
set -e
export PATH=/src/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin:\$PATH
M='make O=/kernel/out ARCH=arm CROSS_COMPILE=arm-linux-androideabi- -j$(nproc)'
mkdir -p out; [ -f out/.config ] || \$M lineage_bandit_defconfig
\$M $targets
"
