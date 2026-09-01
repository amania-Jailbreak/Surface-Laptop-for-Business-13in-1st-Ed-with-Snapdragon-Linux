#!/usr/bin/env python3
"""Select matching base modules and their dependencies for an initramfs."""

from __future__ import annotations

import gzip
import os
import sys


def align4(value: int) -> int:
    return (value + 3) & ~3


def base_modules(path: str) -> set[str]:
    data = gzip.decompress(open(path, "rb").read())
    result: set[str] = set()
    offset = 0
    while offset + 110 <= len(data):
        header = data[offset : offset + 110]
        if header[:6] not in (b"070701", b"070702"):
            raise ValueError(f"invalid newc header at offset {offset}")
        filesize = int(header[54:62], 16)
        namesize = int(header[94:102], 16)
        name_start = offset + 110
        name_end = name_start + namesize
        name = data[name_start:name_end].rstrip(b"\0").decode(
            "utf-8", "surrogateescape"
        )
        if name == "TRAILER!!!":
            break
        parts = name.split("/")
        if (
            len(parts) >= 6
            and parts[:3] == ["usr", "lib", "modules"]
            and parts[4] == "kernel"
            and name.endswith(".ko")
        ):
            result.add("/".join(parts[4:]))
        offset = align4(name_end) + align4(filesize)
    else:
        raise ValueError("newc trailer not found")
    return result


def module_dependencies(module_root: str) -> dict[str, list[str]]:
    path = os.path.join(module_root, "modules.dep")
    result: dict[str, list[str]] = {}
    if not os.path.isfile(path):
        return result
    with open(path, encoding="utf-8", errors="surrogateescape") as depfile:
        for line in depfile:
            if ":" not in line:
                continue
            name, dependencies = line.rstrip("\n").split(":", 1)
            name = name.strip().lstrip("/")
            result[name] = [
                item.strip().lstrip("/")
                for item in dependencies.split()
                if item.strip()
            ]
    return result


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            f"usage: {sys.argv[0]} BASE_INITRD MODULE_ROOT SEEDS OUTPUT"
        )
    base, module_root, seeds_path, output = sys.argv[1:]
    seeds = base_modules(base)
    with open(seeds_path, encoding="utf-8") as seedfile:
        seeds.update(
            line.strip().lstrip("/")
            for line in seedfile
            if line.strip() and not line.lstrip().startswith("#")
        )

    dependencies = module_dependencies(module_root)
    selected: set[str] = set()
    pending = sorted(seeds)
    while pending:
        module = pending.pop()
        if module in selected or not module.endswith(".ko"):
            continue
        if not os.path.isfile(os.path.join(module_root, module)):
            continue
        selected.add(module)
        pending.extend(dependencies.get(module, []))

    with open(output, "w", encoding="utf-8") as selected_file:
        for module in sorted(selected):
            selected_file.write(module + "\n")


if __name__ == "__main__":
    main()
