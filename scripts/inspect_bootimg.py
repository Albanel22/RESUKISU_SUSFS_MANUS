#!/usr/bin/env python3
import hashlib
import struct
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} BOOT_IMG")
p = Path(sys.argv[1])
data = p.read_bytes()
if data[:8] != b"ANDROID!":
    raise SystemExit("not an Android boot image")

def u32(off):
    return struct.unpack_from("<I", data, off)[0]
def u64(off):
    return struct.unpack_from("<Q", data, off)[0]
def align(n, page):
    return (n + page - 1) // page * page

page = u32(36)
version = u32(40)
header_size = u32(1644) if version >= 1 and len(data) >= 1648 else None
kernel_size, ramdisk_size, second_size = u32(8), u32(16), u32(24)
kernel_off = page
ramdisk_off = kernel_off + align(kernel_size, page)
second_off = ramdisk_off + align(ramdisk_size, page)
print(f"file={p}")
print(f"size={len(data)} sha256={hashlib.sha256(data).hexdigest()}")
print(f"header_version={version} header_size={header_size} page_size={page}")
print(f"kernel_size={kernel_size} ramdisk_size={ramdisk_size} second_size={second_size}")
print(f"offsets kernel=0x{kernel_off:x} ramdisk=0x{ramdisk_off:x} second=0x{second_off:x}")
if version >= 2 and len(data) >= 1660:
    print(f"dtb_size={u32(1648)} dtb_addr=0x{u64(1652):x}")
    print(f"recovery_dtbo_size={u32(1632)} recovery_dtbo_offset=0x{u64(1636):x}")
print(f"avb_header_offset={data.find(b'AVB0')}")
print(f"avb_footer_offset={data.rfind(b'AVBf')}")
if page != 4096:
    raise SystemExit("unsupported page size; expected 4096")
if version not in (0, 1, 2):
    raise SystemExit(f"unsupported Android boot header version: {version}")
if kernel_off + kernel_size > len(data) or ramdisk_off + ramdisk_size > len(data):
    raise SystemExit("component extends beyond image")
