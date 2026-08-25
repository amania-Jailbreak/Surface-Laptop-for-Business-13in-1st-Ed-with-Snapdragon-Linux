#!/usr/bin/env python3
"""Replace/add regular files in a gzip-compressed newc initramfs."""

from __future__ import annotations

import gzip
import os
import stat
import sys
import time


def align4(value: int) -> int:
    return (value + 3) & ~3


def newc_entry(name: bytes, payload: bytes, mode: int, ino: int) -> bytes:
    namesize = len(name) + 1
    header = (
        b"070701"
        + f"{ino:08x}".encode()
        + f"{mode:08x}".encode()
        + f"{0:08x}".encode()
        + f"{0:08x}".encode()
        + f"{1:08x}".encode()
        + f"{int(time.time()):08x}".encode()
        + f"{len(payload):08x}".encode()
        + f"{0:08x}".encode()
        + f"{0:08x}".encode()
        + f"{0:08x}".encode()
        + f"{0:08x}".encode()
        + f"{namesize:08x}".encode()
        + f"{0:08x}".encode()
    )
    assert len(header) == 110
    name_block = name + b"\0" + b"\0" * (align4(110 + namesize) - 110 - namesize)
    data_block = payload + b"\0" * (align4(len(payload)) - len(payload))
    return header + name_block + data_block


def parse_entries(cpio: bytes) -> tuple[list[tuple[str, bytes]], bytes]:
    entries: list[tuple[str, bytes]] = []
    offset = 0
    while offset + 110 <= len(cpio):
        header = cpio[offset : offset + 110]
        if header[:6] not in (b"070701", b"070702"):
            raise ValueError(f"invalid newc header at offset {offset}")
        filesize = int(header[54:62], 16)
        namesize = int(header[94:102], 16)
        name_start = offset + 110
        name_end = name_start + namesize
        name = cpio[name_start:name_end].rstrip(b"\0").decode("utf-8", "surrogateescape")
        data_start = align4(name_end)
        next_offset = data_start + align4(filesize)
        raw = cpio[offset:next_offset]
        if name == "TRAILER!!!":
            return entries, raw
        entries.append((name, raw))
        offset = next_offset
    raise ValueError("newc trailer not found")


def read_manifest(path: str) -> dict[str, tuple[bytes, int]]:
    replacements: dict[str, tuple[bytes, int]] = {}
    with open(path, encoding="utf-8") as manifest:
        for line_number, line in enumerate(manifest, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            if len(fields) not in (2, 3):
                raise ValueError(f"manifest line {line_number}: expected DEST SOURCE [MODE]")
            destination, source = fields[:2]
            if destination.startswith("/") or ".." in destination.split("/"):
                raise ValueError(f"unsafe destination: {destination}")
            mode = int(fields[2], 8) if len(fields) == 3 else stat.S_IMODE(os.stat(source).st_mode)
            replacements[destination] = (open(source, "rb").read(), stat.S_IFREG | mode)
    return replacements


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT OUTPUT MANIFEST")
    source, target, manifest = sys.argv[1:]
    entries, trailer = parse_entries(gzip.decompress(open(source, "rb").read()))
    replacements = read_manifest(manifest)
    kept = [(name, raw) for name, raw in entries if name not in replacements]
    ino = len(kept) + 1
    additions = [
        (name, newc_entry(name.encode("utf-8", "surrogateescape"), payload, mode, ino + i))
        for i, (name, (payload, mode)) in enumerate(replacements.items())
    ]
    packed = gzip.compress(
        b"".join(raw for _, raw in kept + additions) + trailer,
        compresslevel=9,
        mtime=0,
    )
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    with open(target, "xb") as output:
        output.write(packed)
    os.chmod(target, 0o644)


if __name__ == "__main__":
    main()
