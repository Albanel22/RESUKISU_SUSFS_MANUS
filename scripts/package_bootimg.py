#!/usr/bin/env python3
"""Repack a kiev Android boot v2 image with Magiskboot.

Magiskboot is used because the kiev boot container is exactly 96 MiB and
contains an AVB metadata/footer region that must remain structurally present.
This script does not create or claim a new AVB signature; it only asks the
pinned Magiskboot binary to unpack and repack the supplied reference image.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shlex
import shutil
import struct
import subprocess
import sys
from pathlib import Path

TARGET_SIZE = 100663296  # kiev boot partition: 96 MiB


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(shlex.quote(x) for x in cmd), flush=True)
    return subprocess.run(cmd, cwd=cwd, check=True, text=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ERROR: {message}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference", required=True, type=Path)
    ap.add_argument("--kernel", required=True, type=Path)
    ap.add_argument("--magiskboot", required=True, type=Path)
    ap.add_argument("--expected-reference-sha256", required=True)
    ap.add_argument("--expected-magiskboot-sha256", required=True)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    for path in (args.reference, args.kernel, args.magiskboot):
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"missing or empty input: {path}")
    if args.reference.stat().st_size != TARGET_SIZE:
        fail(f"reference boot size must be {TARGET_SIZE}, got {args.reference.stat().st_size}")
    if sha256(args.reference).lower() != args.expected_reference_sha256.lower():
        fail("reference boot SHA-256 mismatch")
    if sha256(args.magiskboot).lower() != args.expected_magiskboot_sha256.lower():
        fail("magiskboot SHA-256 mismatch")
    if args.reference.read_bytes()[:8] != b"ANDROID!":
        fail("reference is not an Android boot image")

    work = args.output.parent / ".magiskboot-work"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    reference = work / "boot.img"
    shutil.copy2(args.reference, reference)

    run([str(args.magiskboot), "unpack", str(reference)], cwd=work)
    unpacked_kernel = work / "kernel"
    if not unpacked_kernel.is_file() or unpacked_kernel.stat().st_size == 0:
        fail("magiskboot did not extract a kernel")
    if work.joinpath("ramdisk.cpio").exists() is False:
        fail("magiskboot did not extract ramdisk.cpio")

    shutil.copy2(args.kernel, unpacked_kernel)
    repacked = work / "new-boot.img"
    run([str(args.magiskboot), "repack", str(reference), str(repacked)], cwd=work)
    if not repacked.is_file() or repacked.stat().st_size != TARGET_SIZE:
        fail(f"repacked boot must be exactly {TARGET_SIZE} bytes, got {repacked.stat().st_size if repacked.exists() else 0}")

    data = repacked.read_bytes()
    if data[:8] != b"ANDROID!":
        fail("repacked output is not an Android boot image")
    if data.rfind(b"AVBf") < TARGET_SIZE - 4096:
        fail("repacked output does not retain the AVB footer region")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repacked, args.output)
    print(f"boot_img={args.output}")
    print(f"boot_img_size={args.output.stat().st_size}")
    print(f"boot_img_sha256={sha256(args.output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
