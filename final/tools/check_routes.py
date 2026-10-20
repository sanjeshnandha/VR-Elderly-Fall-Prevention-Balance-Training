#!/usr/bin/env python3
"""Walk every room's route against that room's real obstacle map.

Core System I only works if each leg is *awkward but possible*: the straight
line from one ring to the next should usually be blocked by a hazard footprint,
and there should always be some way round it. A leg with a clear straight line
tests nothing; a leg with no clear path at all is a broken room, not a hard one.

Everything here is read out of the scene files, so it stays true as the rooms
are edited. Run it after moving any marker, hazard or piece of furniture:

    python3 tools/check_routes.py

Reports, per leg:
    direct line clear    nothing in the way -- the leg tests nothing
    must go round X      the straight line hits X, and a clear path exists
    NO CLEAR PATH        the straight line hits X and nothing else gets there
"""
import math
import os
import re
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE_DIRS = [os.path.join(ROOT, "scenes", "rooms"),
              os.path.join(ROOT, "scenes", "outdoor")]

CELL = 0.05          # grid used for the "is there any way round" search
BODY = 0.20          # half-width of a person, for clearance against furniture
WALL_PAD = 0.12      # you cannot stand with your shoulder inside the plaster
# A prop is an obstacle only if it stands high enough to walk into. A rug is
# 14 mm thick and a doormat 18 mm: you step on those, you do not go round them.
OBSTACLE_MIN_TOP = 0.15
# A ring, though, must not stand on ANYTHING you would feel underfoot. A 100 mm
# shoe box is something you step over, not something you stand on, so the ring
# test uses a far lower bar than the walking test.
RING_MIN_TOP = 0.04


def ext_id(txt, script):
    m = re.search(r'path="res://scripts/world/%s"\s+id="([^"]+)"'
                  % re.escape(script), txt)
    return m.group(1) if m else None


def nodes_with(txt, rid):
    for block in txt.split("[node ")[1:]:
        if rid and 'ExtResource("%s")' % rid in block:
            yield re.match(r'name="([^"]+)"', block).group(1), block


def xform(block):
    m = re.search(r"transform = Transform3D\(([^)]*)\)", block)
    if not m:
        return 0.0, 0.0, 0.0
    v = [float(x) for x in m.group(1).split(",")]
    return v[9], v[10], v[11]


def vec3(block, key, default):
    m = re.search(r"%s = Vector3\(([^)]*)\)" % key, block)
    return [float(x) for x in m.group(1).split(",")] if m else list(default)


def rect(cx, cz, sx, sz):
    return (cx - sx / 2.0, cz - sz / 2.0, cx + sx / 2.0, cz + sz / 2.0)


def inside(r, x, z, pad=0.0):
    return r[0] - pad <= x <= r[2] + pad and r[1] - pad <= z <= r[3] + pad


class Room:
    def __init__(self, name, sx, sz, solids, hazards, route, surfaces=None):
        self.name, self.sx, self.sz = name, sx, sz
        self.solids, self.hazards, self.route = solids, hazards, route
        self.underfoot = {}
        # Outdoors there is no RoomBuilder box to be inside of, so the ground
        # is the union of the surfaces marked walkable instead: the front path,
        # both pavements, the dropped kerbs and the carriageway.
        self.surfaces = surfaces

    def on_ground(self, x, z):
        if self.surfaces is None:
            return (abs(x) <= self.sx / 2.0 - WALL_PAD
                    and abs(z) <= self.sz / 2.0 - WALL_PAD)
        return any(inside(r, x, z) for r in self.surfaces.values())

    def blocked(self, x, z, pad=BODY):
        if not self.on_ground(x, z):
            return True
        return any(inside(r, x, z, pad) for r in self.solids.values())

    def dirty(self, x, z):
        for k, r in self.hazards.items():
            if inside(r, x, z):
                return k
        return None

    def straight_hits(self, a, b, n=64):
        hits = set()
        for i in range(n + 1):
            t = i / float(n)
            h = self.dirty(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            if h:
                hits.add(h)
        return hits

    def free(self, x, z):
        return not self.blocked(x, z) and self.dirty(x, z) is None

    def path_exists(self, a, b):
        def key(p):
            return (int(round(p[0] / CELL)), int(round(p[1] / CELL)))

        start, goal = key(a), key(b)
        seen = {start}
        queue = deque([start])
        while queue:
            cur = queue.popleft()
            if cur == goal:
                return True
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nxt = (cur[0] + dx, cur[1] + dz)
                if nxt in seen:
                    continue
                x, z = nxt[0] * CELL, nxt[1] * CELL
                # The end points are allowed to sit anywhere the ring sits.
                if nxt != goal and not self.free(x, z):
                    continue
                seen.add(nxt)
                queue.append(nxt)
        return False

    def report(self):
        ok = True
        print("\n== %s  (%.1f x %.1f m, %d solids, %d hazard footprints)"
              % (self.name, self.sx, self.sz, len(self.solids), len(self.hazards)))
        for i, (x, z, label) in enumerate(self.route, 1):
            problems = []
            if self.blocked(x, z, BODY * 0.6):
                problems.append("stands inside furniture or a wall")
            h = self.dirty(x, z)
            if h:
                problems.append("stands inside hazard footprint '%s'" % h)
            on = [k for k, r in self.underfoot.items() if inside(r, x, z)]
            if on:
                problems.append("stands on top of %s" % ", ".join(sorted(on)))
            if problems:
                ok = False
                print("   ! ring %d (%5.2f,%5.2f) %-20s %s"
                      % (i, x, z, label, "; ".join(problems)))
        detours = 0
        for i in range(len(self.route) - 1):
            a, b = self.route[i][:2], self.route[i + 1][:2]
            hits = self.straight_hits(a, b)
            if not hits:
                verdict = "direct line clear  (tests nothing)"
            elif self.path_exists(a, b):
                detours += 1
                verdict = "must go round %s" % ", ".join(sorted(hits))
            else:
                ok = False
                verdict = "NO CLEAR PATH past %s" % ", ".join(sorted(hits))
            print("   %s leg %d  (%5.2f,%5.2f) -> (%5.2f,%5.2f)  %s"
                  % ("!!" if "NO CLEAR" in verdict else "  ",
                     i + 1, a[0], a[1], b[0], b[1], verdict))
        print("   -> %s; %d of %d legs need a detour"
              % ("OK" if ok else "PROBLEM", detours, len(self.route) - 1))
        return ok


def load(path):
    txt = open(path, encoding="utf-8").read()
    # The room's own size, and ONLY the room's: this used to take the first
    # `size = Vector2(...)` anywhere in the file, which worked for exactly as
    # long as RoomBuilder was the only node with a property by that name. The
    # leaf drift on the street has one too, and the street promptly became a
    # 1.5 x 0.8 m room with no ground in it and six rings standing in walls.
    m = None
    builder = ext_id(txt, "room_builder.gd")
    if builder:
        for _name, block in nodes_with(txt, builder):
            m = re.search(r"\nsize = Vector2\(([^)]*)\)", block)
            if m:
                break
    surfaces = None
    sx = sz = 0.0
    if m:
        sx, sz = [float(v) for v in m.group(1).split(",")]

    solids = {}
    pid = ext_id(txt, "prop.gd")
    for name, block in nodes_with(txt, pid):
        x, y, z = xform(block)
        s = vec3(block, "box_size", (0, 0, 0))
        if y + s[1] / 2.0 < OBSTACLE_MIN_TOP:
            continue                      # flat on the floor: you step on it
        if y - s[1] / 2.0 > 1.25:
            continue                      # above head height on the way past
        solids[name] = rect(x, z, s[0], s[2])

    underfoot = {}
    for name, block in nodes_with(txt, pid):
        x, y, z = xform(block)
        s = vec3(block, "box_size", (0, 0, 0))
        if y + s[1] / 2.0 < RING_MIN_TOP or y - s[1] / 2.0 > 0.6:
            continue
        underfoot[name] = rect(x, z, s[0], s[2])

    if m is None:
        surfaces = {}
        for name, block in nodes_with(txt, pid):
            if "\nwalkable = true" not in block:
                continue
            x, _y, z = xform(block)
            sp = vec3(block, "box_size", (0, 0, 0))
            surfaces[name] = rect(x, z, sp[0], sp[2])
        if not surfaces:
            return []
        xs = [r[0] for r in surfaces.values()] + [r[2] for r in surfaces.values()]
        zs = [r[1] for r in surfaces.values()] + [r[3] for r in surfaces.values()]
        sx, sz = max(xs) - min(xs), max(zs) - min(zs)

    hazards = {}
    sid = ext_id(txt, "slip_zone.gd")
    for name, block in nodes_with(txt, sid):
        x, _y, z = xform(block)
        e = vec3(block, "route_extents", (0, 0, 0))
        if e[0] <= 0.001 or e[2] <= 0.001:
            e = vec3(block, "extents", (1.0, 2.0, 1.0))
        zid = re.search(r'zone_id = "([^"]+)"', block)
        hazards[zid.group(1) if zid else name] = rect(x, z, e[0], e[2])

    # One route per route NODE, not one per scene. The street has two of them,
    # and treating them as one invents a leg from the end of the footpath walk
    # to the start of the crossing practice -- straight across the road.
    routes = {}
    rid = ext_id(txt, "route_marker.gd")
    for name, block in nodes_with(txt, rid):
        owner = re.search(r'parent="([^"]*)"', block)
        key = owner.group(1) if owner else "."
        x, _y, z = xform(block)
        lbl = re.search(r'label_text = "([^"]*)"', block)
        routes.setdefault(key, []).append((x, z, lbl.group(1) if lbl else name))

    out = []
    for key, route in sorted(routes.items()):
        label = os.path.basename(path)
        if len(routes) > 1:
            label = "%s / %s" % (label, key)
        room = Room(label, sx, sz, solids, hazards, route, surfaces)
        room.underfoot = underfoot
        out.append(room)
    return out


def main():
    ok = True
    rooms = 0
    files = []
    for folder in SCENE_DIRS:
        if os.path.isdir(folder):
            files += [os.path.join(folder, f) for f in sorted(os.listdir(folder))
                      if f.endswith(".tscn")]
    for fn in files:
        for room in load(fn):
            rooms += 1
            ok = room.report() and ok
    print("\n%d route(s): %s" % (rooms, "all OK" if ok else "PROBLEMS ABOVE"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
