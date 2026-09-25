#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${ROOT:-$PWD}"
KERNEL_DIR="${KERNEL_DIR:-$ROOT/kernel}"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT}"
SOURCE_COMMIT="${SOURCE_COMMIT:-c21b90c6860eeade8da37ea1212aa6135cf99e1f}"
RESUKISU_URL="${RESUKISU_URL:-https://github.com/ReSukiSU/ReSukiSU.git}"
RESUKISU_COMMIT="${RESUKISU_COMMIT:-90b4a4c70f70c835b01c2be6deac58ee3c0cb4c2}"
PATCH="${PATCH:-$BUNDLE_DIR/integration/kernel-adaptations.patch}"

err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ -d "$KERNEL_DIR/.git" ]] || err "kernel repository missing: $KERNEL_DIR"
[[ -f "$PATCH" ]] || err "integration patch missing: $PATCH"

# Reset only the pinned disposable checkout.
git -C "$KERNEL_DIR" fetch --depth=1 origin "$SOURCE_COMMIT"
git -C "$KERNEL_DIR" reset --hard "$SOURCE_COMMIT"
git -C "$KERNEL_DIR" clean -fdx

RS="$ROOT/ReSukiSU"
if [[ ! -d "$RS/.git" ]]; then
  git clone --filter=blob:none --no-checkout "$RESUKISU_URL" "$RS"
fi
git -C "$RS" fetch --depth=1 origin "$RESUKISU_COMMIT"
git -C "$RS" checkout --detach "$RESUKISU_COMMIT"

rm -rf "$KERNEL_DIR/KernelSU"
cp -a "$RS" "$KERNEL_DIR/KernelSU"
rm -f "$KERNEL_DIR/drivers/kernelsu"
ln -s ../KernelSU/kernel "$KERNEL_DIR/drivers/kernelsu"

for f in fs/sus_su.c fs/susfs.c include/linux/sus_su.h include/linux/susfs.h include/linux/susfs_def.h; do
  src="$BUNDLE_DIR/integration/$(basename "$f")"
  [[ -f "$src" ]] || err "missing bundled integration file: $src"
  install -D -m 0644 "$src" "$KERNEL_DIR/$f"
done

# Never apply partially. A rejected hunk is a hard failure.
git -C "$KERNEL_DIR" apply --check --whitespace=error "$PATCH" || {
  echo "ERROR: patch does not apply cleanly to $SOURCE_COMMIT" >&2
  exit 1
}
git -C "$KERNEL_DIR" apply --whitespace=error "$PATCH"

if find "$KERNEL_DIR" -type f \( -name '*.rej' -o -name '*.orig' \) -print -quit | grep -q .; then
  err "rejected/original patch files remain after apply"
fi

grep -q 'source "drivers/kernelsu/Kconfig"' "$KERNEL_DIR/drivers/Kconfig" || err "KernelSU Kconfig not wired"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$KERNEL_DIR/drivers/Makefile" || err "KernelSU Makefile not wired"
for f in fs/open.c fs/stat.c fs/exec.c fs/read_write.c kernel/reboot.c kernel/sys.c drivers/input/input.c; do
  if grep -qE '^[[:space:]]*#ifdef[[:space:]]+CONFIG_KSU_SUSFS$' "$KERNEL_DIR/$f"; then
    err "manual hook file still contains an exact CONFIG_KSU_SUSFS guard: $f"
  fi
done
grep -q 'ksu_handle_faccessat' "$KERNEL_DIR/fs/open.c" || err "manual faccessat hook missing"
grep -q 'ksu_handle_stat' "$KERNEL_DIR/fs/stat.c" || err "manual stat hook missing"
grep -q 'const char __user' "$KERNEL_DIR/fs/open.c" || err "manual faccessat ABI missing"
grep -q 'const char __user' "$KERNEL_DIR/fs/stat.c" || err "manual stat ABI missing"
git -C "$KERNEL_DIR" diff --check
printf 'Prepared kernel=%s\nPrepared ReSukiSU=%s\n' \
  "$(git -C "$KERNEL_DIR" rev-parse HEAD)" "$(git -C "$RS" rev-parse HEAD)"
