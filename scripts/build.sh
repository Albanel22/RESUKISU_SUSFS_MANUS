#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${ROOT:-$PWD}"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel}"
OUT="${OUT:-$KERNEL_DIR/out}"
JOBS="${JOBS:-$(nproc)}"
LOG="${LOG:-$ROOT/build.log}"
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-

cd "$KERNEL_DIR"
rm -rf "$OUT"
make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" vendor/lito-perf_defconfig

# ReSukiSU/SUSFS feature set used by the validated build.
cat >> "$OUT/.config" <<'EOF'
CONFIG_KSU=y
CONFIG_KSU_MULTI_MANAGER_SUPPORT=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" KCFLAGS=-Wno-error -j"$JOBS" Image.gz modules 2>&1 | tee "$LOG"

test -s "$OUT/arch/arm64/boot/Image.gz"
find "$OUT" -type f -name '*.ko' | grep -q .
sha256sum "$OUT/arch/arm64/boot/Image.gz"
