#!/usr/bin/env bash
# Build a raw ARM64 Image plus modules for the kiev 4.19 kernel.
# Phase 1: ReSukiSU manual hooks only. SUSFS is deliberately disabled.
#
# This script is fail-closed:
# - it enables CONFIG_KSU and CONFIG_KSU_MANUAL_HOOK;
# - it disables CONFIG_KSU_SUSFS and SUSFS feature symbols;
# - it requires the manual-hook source signatures for faccessat/stat;
# - it refuses to compile if SUSFS is still selected in .config.
set -Eeuo pipefail

ROOT="${ROOT:-$PWD}"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel}"
OUT="${OUT:-$KERNEL_DIR/out}"
LOG="${LOG:-$ROOT/build.log}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
JOBS="${JOBS:-$(nproc)}"
DEFCONFIG="${DEFCONFIG:-vendor/lito-perf_defconfig}"

err() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local status=$?
  printf '\nBuild failed with exit status %s. Review: %s\n' "$status" "$LOG" >&2
  exit "$status"
}
trap on_error ERR

[[ -d "$KERNEL_DIR" ]] || err "kernel directory does not exist: $KERNEL_DIR"
[[ "$ARCH" == arm64 ]] || err "this kiev script requires ARCH=arm64"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || err "JOBS must be a positive integer: $JOBS"

case "$OUT" in
  "$KERNEL_DIR"/*|"$ROOT"/*) ;;
  *) err "OUT must be below KERNEL_DIR or ROOT: $OUT" ;;
esac
[[ "$OUT" != / && "$OUT" != "$KERNEL_DIR" && "$OUT" != "$ROOT" ]] || \
  err "refusing to remove a project root: OUT=$OUT"

mkdir -p "$(dirname "$LOG")"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

printf '== kiev kernel build: ReSukiSU manual hooks only ==\n'
printf 'kernel_dir=%s\nout=%s\narch=%s\ncross_compile=%s\njobs=%s\ndefconfig=%s\n' \
  "$KERNEL_DIR" "$OUT" "$ARCH" "$CROSS_COMPILE" "$JOBS" "$DEFCONFIG"
printf 'susfs=disabled\nmanual_hooks=enabled\n'

command -v make >/dev/null || err "make is not installed"
command -v file >/dev/null || err "file is required for payload validation"
command -v sha256sum >/dev/null || err "sha256sum is required"
command -v perl >/dev/null || err "perl is required for source-hook validation"
command -v "${CROSS_COMPILE}gcc" >/dev/null || \
  err "cross compiler is missing: ${CROSS_COMPILE}gcc"

CONFIG_TOOL="$KERNEL_DIR/scripts/config"
[[ -f "$CONFIG_TOOL" ]] || err "kernel scripts/config is missing: $CONFIG_TOOL"
[[ -x "$CONFIG_TOOL" ]] || chmod +x "$CONFIG_TOOL"

rm -rf -- "$OUT"
mkdir -p "$OUT"
cd "$KERNEL_DIR"

printf '\n== Base configuration ==\n'
make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$DEFCONFIG"
[[ -s "$OUT/.config" ]] || err "defconfig did not create $OUT/.config"

printf '\n== Applying KSU manual-hook configuration ==\n'
# Enable only the KSU manual-hook path. Do not append duplicate config lines.
"$CONFIG_TOOL" --file "$OUT/.config" \
  -e KSU \
  -e KSU_MANUAL_HOOK \
  -e KSU_MULTI_MANAGER_SUPPORT \
  -e BUILD_ARM64_UNCOMPRESSED_KERNEL \
  -d KSU_SUSFS \
  -d KSU_SUSFS_SUS_SU \
  -d KSU_SUSFS_SUS_PATH \
  -d KSU_SUSFS_SUS_MOUNT \
  -d KSU_SUSFS_SUS_KSTAT \
  -d KSU_SUSFS_SPOOF_UNAME \
  -d KSU_SUSFS_ENABLE_LOG \
  -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
  -d KSU_SUSFS_OPEN_REDIRECT \
  -d KSU_SUSFS_SUS_MAP

make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

config_is_y() {
  local key=$1
  grep -q "^CONFIG_${key}=y$" "$OUT/.config" || \
    err "CONFIG_${key}=y was not retained after olddefconfig"
}

config_is_disabled() {
  local key=$1
  if grep -q "^CONFIG_${key}=y$" "$OUT/.config"; then
    err "CONFIG_${key} must be disabled for this manual-hooks-only build"
  fi
}

config_is_y KSU
config_is_y KSU_MANUAL_HOOK
config_is_y BUILD_ARM64_UNCOMPRESSED_KERNEL
config_is_disabled KSU_SUSFS
config_is_disabled KSU_SUSFS_SUS_SU
config_is_disabled KSU_SUSFS_SUS_PATH
config_is_disabled KSU_SUSFS_SUS_MOUNT
config_is_disabled KSU_SUSFS_SUS_KSTAT
config_is_disabled KSU_SUSFS_SPOOF_UNAME
config_is_disabled KSU_SUSFS_ENABLE_LOG
config_is_disabled KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
config_is_disabled KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
config_is_disabled KSU_SUSFS_OPEN_REDIRECT
config_is_disabled KSU_SUSFS_SUS_MAP

printf '\n== Verifying manual-hook source integration ==\n'
[[ -f fs/exec.c ]] || err "missing fs/exec.c"
[[ -f fs/open.c ]] || err "missing fs/open.c"
[[ -f fs/stat.c ]] || err "missing fs/stat.c"
[[ -f fs/read_write.c ]] || err "missing fs/read_write.c"
[[ -f kernel/reboot.c ]] || err "missing kernel/reboot.c"
[[ -f kernel/sys.c ]] || err "missing kernel/sys.c"
[[ -f drivers/input/input.c ]] || err "missing drivers/input/input.c"

# Required ReSukiSU manual hooks.
grep -Eq 'ksu_handle_execveat' fs/exec.c || err "missing manual execveat hook"
grep -Eq 'ksu_handle_faccessat' fs/open.c || err "missing manual faccessat hook"
grep -Eq 'ksu_handle_stat' fs/stat.c || err "missing manual stat hook"
grep -Eq 'ksu_handle_sys_read' fs/read_write.c || err "missing manual sys_read hook"
grep -Eq 'ksu_handle_sys_reboot' kernel/reboot.c || err "missing manual sys_reboot hook"
grep -Eq 'ksu_handle_setresuid' kernel/sys.c || err "missing manual setresuid hook"
grep -Eq 'ksu_handle_input_handle_event' drivers/input/input.c || \
  err "missing manual input hook"

# Manual hooks on this 4.19 tree intentionally use the user-pointer ABI.
# Do not accept the newer SUSFS struct filename ** ABI in this phase.
perl -0777 -ne 'exit 0 if /ksu_handle_faccessat\s*\(.*?const\s+char\s+__user\s*\*\*/s; exit 1' fs/open.c || \
  err "faccessat hook is not using the manual const char __user ** ABI"
perl -0777 -ne 'exit 0 if /ksu_handle_stat\s*\(.*?const\s+char\s+__user\s*\*\*/s; exit 1' fs/stat.c || \
  err "stat hook is not using the manual const char __user ** ABI"

# These are SUSFS-only call sites and must not be active in this phase.
if grep -RInE '^[[:space:]]*#ifdef[[:space:]]+CONFIG_KSU_SUSFS' \
    fs/open.c fs/stat.c fs/exec.c fs/read_write.c kernel/reboot.c kernel/sys.c drivers/input/input.c; then
  err "manual-hook files still guard required hooks with CONFIG_KSU_SUSFS; use CONFIG_KSU_MANUAL_HOOK for those hook blocks"
fi

# Reject known obsolete hooks that conflict with current ReSukiSU manual hooks.
if grep -Eq 'ksu_vfs_read_hook' fs/read_write.c; then
  err "obsolete ksu_vfs_read_hook remains in fs/read_write.c"
fi
if grep -Eq 'ksu_execveat_hook' fs/exec.c; then
  err "obsolete ksu_execveat_hook remains in fs/exec.c"
fi
if grep -Eq 'ksu_init_rc_hook' fs/read_write.c fs/stat.c; then
  err "obsolete ksu_init_rc_hook remains in filesystem hooks"
fi

printf '\n== Compiling raw Image and modules ==\n'
make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
  KCFLAGS="${KCFLAGS:--Wno-error}" -j"$JOBS" Image modules

KERNEL_IMAGE="$OUT/arch/arm64/boot/Image"
[[ -s "$KERNEL_IMAGE" ]] || err "compiled Image is missing or empty: $KERNEL_IMAGE"

printf '\n== Validating kernel payload ==\n'
KERNEL_FILE=$(file -b "$KERNEL_IMAGE")
printf 'payload=%s\n' "$KERNEL_FILE"
grep -qi 'Linux kernel ARM64 boot executable Image' <<<"$KERNEL_FILE" || \
  err "payload is not identified as a raw ARM64 Image"
if head -c 3 "$KERNEL_IMAGE" | od -An -tx1 | grep -qi '1f 8b 08'; then
  err "payload is gzip-compressed; expected raw Image"
fi

printf '\n== Validating modules and release ==\n'
mapfile -t MODULES < <(find "$OUT" -type f -name '*.ko' -print | sort)
((${#MODULES[@]} > 0)) || err "no kernel modules were produced"
KERNELRELEASE=$(make -s O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" kernelrelease)
[[ -n "$KERNELRELEASE" ]] || err "kernelrelease is empty"
printf 'kernelrelease=%s\nmodules=%s\n' "$KERNELRELEASE" "${#MODULES[@]}"
printf '%s\n' "$KERNELRELEASE" > "$OUT/KERNELRELEASE"

if find "$KERNEL_DIR" -type f \( -name '*.rej' -o -name '*.orig' \) -print -quit | grep -q .; then
  err "rejected/original patch files remain in the kernel tree"
fi

printf '\n== Build artifacts ==\n'
sha256sum "$KERNEL_IMAGE"
printf 'image=%s\nrelease_file=%s\nstatus=PASS\n' "$KERNEL_IMAGE" "$OUT/KERNELRELEASE"
