#!/usr/bin/env bash
# Variant A: tactile kernel state from 2026-08-23 with the 2026-09-20 boot/DTBO base.
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUNDLE_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=${ROOT:-$BUNDLE_DIR/work-variant-a}
KERNEL_DIR=${KERNEL_DIR:-$ROOT/kernel}
OUT=${OUT:-$KERNEL_DIR/out}
ARTIFACTS=${ARTIFACTS:-$ROOT/artifacts}
LOG=${LOG:-$ROOT/build.log}
JOBS=${JOBS:-2}
ARCH=${ARCH:-arm64}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
DEFCONFIG=${DEFCONFIG:-vendor/lito-perf_defconfig}
SOURCE_URL=${SOURCE_URL:-https://github.com/Albanel22/android_kernel_motorola_sm8250}
SOURCE_COMMIT=${SOURCE_COMMIT:-a49e18994c494d71647f675df48e5c7349580747}
RESUKISU_URL=${RESUKISU_URL:-https://github.com/ReSukiSU/ReSukiSU.git}
RESUKISU_COMMIT=${RESUKISU_COMMIT:-90b4a4c70f70c835b01c2be6deac58ee3c0cb4c2}
BOOT_IMAGE_URL=${BOOT_IMAGE_URL:-https://mirrorbits.lineageos.org/full/kiev/20260920/boot.img}
BOOT_IMAGE_SHA256=${BOOT_IMAGE_SHA256:-f7938eb61b59df097d1720dc20495db9ad663a3491f94fb3759b1106a5579c3e}
DTBO_IMAGE_URL=${DTBO_IMAGE_URL:-https://mirrorbits.lineageos.org/full/kiev/20260920/dtbo.img}
DTBO_IMAGE_SHA256=${DTBO_IMAGE_SHA256:-323789569f56ba30d00f1372e6f4965702a5a294c7253a81a9ff7f0a7e984e1c}
MAGISKBOOT_APK_URL=${MAGISKBOOT_APK_URL:-https://github.com/topjohnwu/Magisk/releases/download/v27.0/Magisk-v27.0.apk}
MAGISKBOOT_APK_SHA256=${MAGISKBOOT_APK_SHA256:-f511bd33d3242911d05b0939f910a3133ef2ba0e0ff1e098128f9f3cd0c16610}
MAGISKBOOT_SHA256=${MAGISKBOOT_SHA256:-b5e3c57d26735efb4e37a058cf21e6b8c1db2cb1c832a7b1da0989cceb22cabe}
err(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || err "missing command: $1"; }
for cmd in bash git curl sha256sum unzip python3 make file stat find tar; do need "$cmd"; done
[[ "$ARCH" == arm64 ]] || err "Variant A requires ARCH=arm64"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || err "JOBS must be positive"
need "${CROSS_COMPILE}gcc"
rm -rf -- "$ROOT"; mkdir -p "$ROOT" "$ARTIFACTS"
exec > >(tee "$LOG") 2>&1
printf '== kiev Variant A ==\nkernel_commit=%s\nboot_base=LineageOS 2026-09-20\nmanual_hooks=enabled\nsusfs=disabled\n' "$SOURCE_COMMIT"
git clone --filter=blob:none --no-checkout "$SOURCE_URL" "$KERNEL_DIR"
git -C "$KERNEL_DIR" fetch --depth=1 origin "$SOURCE_COMMIT"
git -C "$KERNEL_DIR" checkout --detach "$SOURCE_COMMIT"
test "$(git -C "$KERNEL_DIR" rev-parse HEAD)" = "$SOURCE_COMMIT"
ROOT="$ROOT" KERNEL_DIR="$KERNEL_DIR" BUNDLE_DIR="$BUNDLE_DIR" SOURCE_COMMIT="$SOURCE_COMMIT" RESUKISU_URL="$RESUKISU_URL" RESUKISU_COMMIT="$RESUKISU_COMMIT" bash "$BUNDLE_DIR/scripts/prepare.sh"
ROOT="$ROOT" KERNEL_DIR="$KERNEL_DIR" OUT="$OUT" LOG="$LOG" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" JOBS="$JOBS" DEFCONFIG="$DEFCONFIG" bash "$BUNDLE_DIR/scripts/build.sh"
KERNEL_IMAGE="$OUT/arch/arm64/boot/Image"
test -s "$KERNEL_IMAGE"; file "$KERNEL_IMAGE" | grep -qi 'Linux kernel ARM64 boot executable Image' || err "invalid raw Image"
BOOT_IN="$ROOT/boot-input/reference-boot.img"; DTBO_IN="$ROOT/boot-input/dtbo.img"; TOOLS="$ROOT/boot-tools"; mkdir -p "$(dirname "$BOOT_IN")" "$TOOLS"
curl --fail --location --retry 3 "$BOOT_IMAGE_URL" -o "$BOOT_IN"; printf '%s  %s\n' "$BOOT_IMAGE_SHA256" "$BOOT_IN" | sha256sum -c -
curl --fail --location --retry 3 "$DTBO_IMAGE_URL" -o "$DTBO_IN"; printf '%s  %s\n' "$DTBO_IMAGE_SHA256" "$DTBO_IN" | sha256sum -c -
test "$(stat -c '%s' "$BOOT_IN")" -eq 100663296; test "$(stat -c '%s' "$DTBO_IN")" -eq 8388608
APK="$TOOLS/Magisk-v27.0.apk"; MAGISKBOOT="$TOOLS/magiskboot"
curl --fail --location --retry 3 "$MAGISKBOOT_APK_URL" -o "$APK"; printf '%s  %s\n' "$MAGISKBOOT_APK_SHA256" "$APK" | sha256sum -c -
unzip -p "$APK" lib/x86_64/libmagiskboot.so > "$MAGISKBOOT"; chmod 0755 "$MAGISKBOOT"; printf '%s  %s\n' "$MAGISKBOOT_SHA256" "$MAGISKBOOT" | sha256sum -c -
python3 "$BUNDLE_DIR/scripts/package_bootimg.py" --reference "$BOOT_IN" --kernel "$KERNEL_IMAGE" --magiskboot "$MAGISKBOOT" --expected-reference-sha256 "$BOOT_IMAGE_SHA256" --expected-magiskboot-sha256 "$MAGISKBOOT_SHA256" --output "$ARTIFACTS/boot-unsigned.img"
cp "$DTBO_IN" "$ARTIFACTS/dtbo.img"
test "$(stat -c '%s' "$ARTIFACTS/boot-unsigned.img")" -eq 100663296
python3 "$BUNDLE_DIR/scripts/inspect_bootimg.py" "$ARTIFACTS/boot-unsigned.img"
printf '\nVARIANT_A_STATUS=PASS\nARTIFACT=%s\n' "$ARTIFACTS/boot-unsigned.img"
