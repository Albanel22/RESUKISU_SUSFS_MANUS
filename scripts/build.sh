#!/usr/bin/env bash
# Build a raw ARM64 Image plus modules for the kiev 4.19 kernel.
# This script deliberately fails closed: it does not produce a claimed-good
# artifact when the ReSukiSU/SUSFS integration or configuration is inconsistent.
set -Eeuo pipefail

ROOT="${ROOT:-$PWD}"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel}"
OUT="${OUT:-$KERNEL_DIR/out}"
LOG="${LOG:-$ROOT/build.log}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
JOBS="${JOBS:-$(nproc)}"
DEFCONFIG="${DEFCONFIG:-vendor/lito-perf_defconfig}"

# SUSFS_SUS_SU is intentionally disabled for the first safe validation build.
# Set ENABLE_SUS_SU=1 only after a boot is validated with the minimal feature set.
ENABLE_SUS_SU="${ENABLE_SUS_SU:-0}"

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
[[ "$ENABLE_SUS_SU" == 0 || "$ENABLE_SUS_SU" == 1 ]] || err "ENABLE_SUS_SU must be 0 or 1"

# Refuse dangerous clean targets. The default is safe; custom OUT paths must
# stay inside KERNEL_DIR or ROOT and may be cleaned only explicitly.
case "$OUT" in
  "$KERNEL_DIR"/*|"$ROOT"/*) ;;
  *) err "OUT must be below KERNEL_DIR or ROOT: $OUT" ;;
esac
[[ "$OUT" != / && "$OUT" != "$KERNEL_DIR" && "$OUT" != "$ROOT" ]] || \
  err "refusing to remove a project root: OUT=$OUT"

mkdir -p "$(dirname "$LOG")"
: > "$LOG"

# Log all command output while preserving the shell's pipefail behavior.
exec > >(tee -a "$LOG") 2>&1

printf '== kiev kernel build ==\n'
printf 'kernel_dir=%s\nout=%s\narch=%s\ncross_compile=%s\njobs=%s\ndefconfig=%s\n' \
  "$KERNEL_DIR" "$OUT" "$ARCH" "$CROSS_COMPILE" "$JOBS" "$DEFCONFIG"

command -v make >/dev/null || err "make is not installed"
command -v file >/dev/null || err "file is required for payload validation"
command -v sha256sum >/dev/null || err "sha256sum is required"
command -v "${CROSS_COMPILE}gcc" >/dev/null || \
  err "cross compiler is missing: ${CROSS_COMPILE}gcc"

CONFIG_TOOL="$KERNEL_DIR/scripts/config"
if [[ ! -x "$CONFIG_TOOL" ]]; then
  # scripts/config may be a generated host utility in this kernel tree.
  make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" scripts/config
fi
[[ -x "$CONFIG_TOOL" ]] || err "kernel scripts/config could not be built: $CONFIG_TOOL"

# Rebuild from a clean output directory. Do not silently clean an arbitrary
# path supplied by a caller unless it passed the checks above.
rm -rf -- "$OUT"
mkdir -p "$OUT"

cd "$KERNEL_DIR"

printf '\n== Base configuration ==\n'
make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$DEFCONFIG"
[[ -s "$OUT/.config" ]] || err "defconfig did not create $OUT/.config"

printf '\n== Applying KSU/SUSFS configuration through scripts/config ==\n'
# Do not append duplicate lines to .config. scripts/config edits the existing
# configuration and olddefconfig resolves the Kconfig choice consistently.
"$CONFIG_TOOL" --file "$OUT/.config" \
  -e KSU \
  -e KSU_MULTI_MANAGER_SUPPORT \
  -e KSU_SUSFS \
  -e KSU_SUSFS_SUS_PATH \
  -e KSU_SUSFS_SUS_MOUNT \
  -e KSU_SUSFS_SUS_KSTAT \
  -e KSU_SUSFS_SPOOF_UNAME \
  -e KSU_SUSFS_ENABLE_LOG \
  -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
  -e KSU_SUSFS_OPEN_REDIRECT \
  -e KSU_SUSFS_SUS_MAP \
  -e BUILD_ARM64_UNCOMPRESSED_KERNEL

# SUSFS uses ReSukiSU's inline-hook path. The legacy manual-hook choice must
# not remain selected at the same time.
"$CONFIG_TOOL" --file "$OUT/.config" -d KSU_MANUAL_HOOK
if [[ "$ENABLE_SUS_SU" == 1 ]]; then
  "$CONFIG_TOOL" --file "$OUT/.config" -e KSU_SUSFS_SUS_SU
else
  "$CONFIG_TOOL" --file "$OUT/.config" -d KSU_SUSFS_SUS_SU
fi

make O="$OUT" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

config_is_y() {
  local key=$1
  grep -q "^CONFIG_${key}=y$" "$OUT/.config" || \
    err "CONFIG_${key}=y was not retained after olddefconfig"
}
config_is_not_set() {
  local key=$1
  if grep -q "^CONFIG_${key}=y$" "$OUT/.config"; then
    err "CONFIG_${key} must not be enabled"
  fi
}

config_is_y KSU
config_is_y KSU_SUSFS
config_is_y BUILD_ARM64_UNCOMPRESSED_KERNEL
config_is_not_set KSU_MANUAL_HOOK
if [[ "$ENABLE_SUS_SU" == 1 ]]; then
  config_is_y KSU_SUSFS_SUS_SU
else
  config_is_not_set KSU_SUSFS_SUS_SU
fi

printf '\n== Verifying source hooks before compilation ==\n'
# These checks mirror the ReSukiSU SUSFS inline-hook checks and, importantly,
# catch the dangerous const char __user ** versus struct filename ** mismatch.
[[ -f fs/exec.c ]] || err "missing fs/exec.c"
[[ -f fs/open.c ]] || err "missing fs/open.c"
[[ -f fs/stat.c ]] || err "missing fs/stat.c"
[[ -f fs/read_write.c ]] || err "missing fs/read_write.c"
[[ -f kernel/reboot.c ]] || err "missing kernel/reboot.c"
[[ -f kernel/sys.c ]] || err "missing kernel/sys.c"
[[ -f drivers/input/input.c ]] || err "missing drivers/input/input.c"

grep -Eq 'ksu_handle_execveat' fs/exec.c || err "missing execveat hook"
grep -Eq 'ksu_handle_faccessat' fs/open.c || err "missing faccessat hook"
grep -Eq 'ksu_handle_stat' fs/stat.c || err "missing stat hook"
grep -Eq 'ksu_handle_sys_read' fs/read_write.c || err "missing sys_read hook"
grep -Eq 'ksu_handle_sys_reboot' kernel/reboot.c || err "missing sys_reboot hook"
grep -Eq 'ksu_handle_setresuid' kernel/sys.c || err "missing setresuid hook"
grep -Eq 'ksu_handle_input_handle_event' drivers/input/input.c || \
  err "missing input hook"

# In SUSFS mode, callers and declarations must use struct filename **.
perl -0777 -ne 'exit 0 if /ksu_handle_faccessat\s*\(.*?struct\s+filename\s*\*\*/s; exit 1' fs/open.c || \
  err "faccessat prototype is not the SUSFS struct filename ** form"
perl -0777 -ne 'exit 0 if /ksu_handle_stat\s*\(.*?struct\s+filename\s*\*\*/s; exit 1' fs/stat.c || \
  err "stat prototype is not the SUSFS struct filename ** form"

# Reject old incompatible hooks which should have been replaced by the
# current ReSukiSU/SUSFS hooks.
if grep -Eq 'ksu_vfs_read_hook' fs/read_write.c; then
  err "obsolete incompatible ksu_vfs_read_hook remains in fs/read_write.c"
fi
if grep -Eq 'ksu_execveat_hook' fs/exec.c; then
  err "obsolete incompatible ksu_execveat_hook remains in fs/exec.c"
fi
if grep -Eq 'ksu_init_rc_hook' fs/read_write.c fs/stat.c; then
  err "obsolete incompatible ksu_init_rc_hook remains in filesystem hooks"
fi

printf '\n== Compiling raw Image and modules ==\n'
# Image is intentional: the stock kiev boot image and defconfig use an
# uncompressed ARM64 payload. Do not change this to Image.gz without also
# proving that the target boot chain expects gzip.
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

# The repacker must use this value rather than a hard-coded module directory.
printf '%s\n' "$KERNELRELEASE" > "$OUT/KERNELRELEASE"

# A patch reject anywhere in the source tree is a hard failure.
if find "$KERNEL_DIR" -type f \( -name '*.rej' -o -name '*.orig' \) -print -quit | grep -q .; then
  err "rejected/original patch files remain in the kernel tree"
fi

printf '\n== Build artifacts ==\n'
sha256sum "$KERNEL_IMAGE"
printf 'image=%s\n' "$KERNEL_IMAGE"
printf 'release_file=%s\n' "$OUT/KERNELRELEASE"
printf 'status=PASS\n'
