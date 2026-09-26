#!/usr/bin/env python3
"""Rebuild and AVB-sign an Android boot image using a reference container."""
from __future__ import annotations
import argparse
import base64
import hashlib
import os
import shlex
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(shlex.quote(x) for x in cmd), flush=True)
    return subprocess.run(cmd, check=True, text=True, **kwargs)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference", required=True, type=Path)
    ap.add_argument("--kernel", required=True, type=Path)
    ap.add_argument("--unpack-tool", required=True, type=Path)
    ap.add_argument("--mkbootimg-tool", required=True, type=Path)
    ap.add_argument("--avbtool", required=True, type=Path)
    ap.add_argument("--avb-key", required=True, type=Path)
    ap.add_argument("--avb-algorithm", default="SHA256_RSA2048")
    ap.add_argument("--expected-reference-sha256", required=True)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()

    for p in (args.reference, args.kernel, args.unpack_tool, args.mkbootimg_tool, args.avbtool, args.avb_key):
        if not p.is_file() or p.stat().st_size == 0:
            raise SystemExit(f"missing or empty input: {p}")
    actual = sha256(args.reference)
    if actual.lower() != args.expected_reference_sha256.lower():
        raise SystemExit(f"reference SHA-256 mismatch: expected {args.expected_reference_sha256}, got {actual}")

    work = args.output.parent / ".bootimg-work"
    work.mkdir(parents=True, exist_ok=True)
    unpack_dir = work / "unpacked"
    unpack_dir.mkdir(parents=True, exist_ok=True)
    run([sys.executable, str(args.unpack_tool), "--boot_img", str(args.reference), "--out", str(unpack_dir)])
    meta = run([sys.executable, str(args.unpack_tool), "--boot_img", str(args.reference), "--out", str(unpack_dir), "--format", "mkbootimg"], capture_output=True).stdout.strip()
    mkargs = shlex.split(meta)
    if "--kernel" not in mkargs:
        raise SystemExit("unpack_bootimg did not provide --kernel metadata")
    mkargs[mkargs.index("--kernel") + 1] = str(args.kernel)
    unsigned = work / "boot-unsigned.img"
    mkargs += ["--output", str(unsigned)]
    os.environ["PYTHONPATH"] = str(args.mkbootimg_tool.parent) + os.pathsep + os.environ.get("PYTHONPATH", "")
    run([sys.executable, str(args.mkbootimg_tool), *mkargs])

    args.output.unlink(missing_ok=True)
    partition_size = args.reference.stat().st_size
    run([
        sys.executable, str(args.avbtool), "add_hash_footer",
        "--image", str(unsigned),
        "--partition_name", "boot",
        "--partition_size", str(partition_size),
        "--algorithm", args.avb_algorithm,
        "--key", str(args.avb_key),
    ])
    unsigned.rename(args.output)
    print(f"boot_img={args.output}")
    print(f"boot_img_size={args.output.stat().st_size}")
    print(f"boot_img_sha256={sha256(args.output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
