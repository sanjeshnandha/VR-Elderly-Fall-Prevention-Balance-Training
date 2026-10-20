#!/usr/bin/env python3
"""List every model in an asset folder with its real-world size.

Reads .glb files directly (the JSON chunk carries each mesh's min/max), so the
size of every piece of furniture can be checked WITHOUT opening Godot -- which
is how the scenes know whether a pack is authored in metres, and how each model
is matched to the right `box_size`.

Usage:
    python3 tools/inspect_models.py assets/kenney_furniture
    python3 tools/inspect_models.py assets/kenney_furniture --grep sofa
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys


def glb_bounds(path: str) -> tuple[list[float], list[float]] | None:
    """Overall min/max of every POSITION accessor in a .glb."""
    with open(path, "rb") as handle:
        magic, _version, _length = struct.unpack("<4sII", handle.read(12))
        if magic != b"glTF":
            return None
        chunk_length, chunk_type = struct.unpack("<II", handle.read(8))
        if chunk_type != 0x4E4F534A:  # 'JSON'
            return None
        gltf = json.loads(handle.read(chunk_length).decode("utf-8"))

    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    accessors = gltf.get("accessors", [])
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            index = primitive.get("attributes", {}).get("POSITION")
            if index is None:
                continue
            accessor = accessors[index]
            if "min" not in accessor or "max" not in accessor:
                continue
            for axis in range(3):
                lo[axis] = min(lo[axis], accessor["min"][axis])
                hi[axis] = max(hi[axis], accessor["max"][axis])
    if lo[0] == float("inf"):
        return None
    return lo, hi


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("folder", help="folder of .glb files")
    parser.add_argument("--grep", help="only names containing this")
    args = parser.parse_args()

    rows = []
    for root, _dirs, files in os.walk(os.path.expanduser(args.folder)):
        for name in sorted(files):
            if not name.lower().endswith(".glb"):
                continue
            if args.grep and args.grep.lower() not in name.lower():
                continue
            bounds = glb_bounds(os.path.join(root, name))
            if bounds is None:
                rows.append((name, None))
                continue
            lo, hi = bounds
            rows.append((name, [hi[i] - lo[i] for i in range(3)]))

    if not rows:
        sys.exit(f"No .glb files in {args.folder}")

    print(f"{'model':<34} {'width':>7} {'height':>7} {'depth':>7}   (model units)")
    print("-" * 68)
    for name, size in rows:
        if size is None:
            print(f"{name:<34}        (could not read)")
        else:
            print(f"{name:<34} {size[0]:>7.2f} {size[1]:>7.2f} {size[2]:>7.2f}")

    sizes = [s for _n, s in rows if s]
    if sizes:
        tallest = max(s[1] for s in sizes)
        print(f"\n{len(sizes)} models. Tallest is {tallest:.2f} units.")
        print("If that is roughly 2 for a wardrobe or a door, the pack is in metres.")


if __name__ == "__main__":
    main()
