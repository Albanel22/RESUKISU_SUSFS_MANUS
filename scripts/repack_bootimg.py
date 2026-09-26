#!/usr/bin/env python3
"""Deliberately refuse the old unsafe v0-style repackaging path.

The kiev reference image is Android boot header v2 and contains AVB metadata.
A valid replacement requires a controlled mkbootimg/avbtool pipeline and the
correct signing policy. Producing a boot.img by copying the old tail would be
misleading and can create a non-bootable artifact.
"""
import struct
import sys
from pathlib import Path

p = Path(sys.argv[1]) if len(sys.argv) == 2 else Path("reference/boot.img")
data = p.read_bytes()
if data[:8] != b"ANDROID!":
    raise SystemExit("ERROR: reference is not an Android boot image")
version = struct.unpack_from("<I", data, 40)[0]
avb = data.find(b"AVB0") >= 0 or data.rfind(b"AVBf") >= 0
if version >= 2 or avb:
    raise SystemExit(
        "ERROR: refusing unsafe manual repack of Android boot v2/AVB image; "
        "use a verified mkbootimg + avbtool pipeline with the correct keys"
    )
raise SystemExit(
    "ERROR: repackaging is disabled in this kit; build Image/modules first "
    "and validate the device-specific boot/AVB process separately"
)
