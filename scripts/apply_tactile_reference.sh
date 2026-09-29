#!/usr/bin/env bash
# Port only the hardware compatibility shim verified in
# Albanel22/backslashxx-DPSK branch Albanel22-patch-3.
# This script does NOT install BackslashXX KernelSU and does NOT enable SUSFS.
set -Eeuo pipefail

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR is required}
DRIVER="$KERNEL_DIR/techpack/display/msm/msm_drv.c"
MARKER='BackslashXX patch-3 tactile compatibility reference'

[[ -f "$DRIVER" ]] || { printf 'ERROR: missing display driver: %s\n' "$DRIVER" >&2; exit 1; }

if grep -qF "$MARKER" "$DRIVER"; then
  printf 'tactile_reference=already_present\n'
  exit 0
fi

if grep -qE '(^|[[:space:]])(panel_register_notifier|panel_unregister_notifier|touch_set_state)[[:space:]]*\(' "$DRIVER"; then
  printf 'ERROR: tactile symbols already exist without the reference marker\n' >&2
  exit 1
fi

cat >> "$DRIVER" <<'EOF'

/* --- BackslashXX patch-3 tactile compatibility reference --- */
#include <linux/notifier.h>
#include <linux/module.h>
static BLOCKING_NOTIFIER_HEAD(motorola_panel_notifier_list);
int panel_register_notifier(struct notifier_block *nb)
{
    return blocking_notifier_chain_register(&motorola_panel_notifier_list, nb);
}
EXPORT_SYMBOL(panel_register_notifier);
int panel_unregister_notifier(struct notifier_block *nb)
{
    return blocking_notifier_chain_unregister(&motorola_panel_notifier_list, nb);
}
EXPORT_SYMBOL(panel_unregister_notifier);
void touch_set_state(int state) { return; }
EXPORT_SYMBOL(touch_set_state);
/* --- End BackslashXX patch-3 tactile compatibility reference --- */
EOF

grep -qF "$MARKER" "$DRIVER" || { printf 'ERROR: tactile reference was not applied\n' >&2; exit 1; }
grep -qF 'EXPORT_SYMBOL(panel_register_notifier)' "$DRIVER" || { printf 'ERROR: panel notifier export missing\n' >&2; exit 1; }
grep -qF 'EXPORT_SYMBOL(touch_set_state)' "$DRIVER" || { printf 'ERROR: touch_set_state export missing\n' >&2; exit 1; }
printf 'tactile_reference=applied\nsource=Albanel22/backslashxx-DPSK@Albanel22-patch-3\n'
