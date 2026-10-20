#!/usr/bin/env python3
"""Can you still get everywhere, now that the walls are solid?

The desktop rig used to walk through walls, so nothing in this project had ever
had to be WALKABLE -- only to look right. With collision turned on, a doorway
0.1 m too narrow, a room whose open side does not meet the hallway, or a console
table left across a door, each traps the participant somewhere they cannot get
out of. None of that is visible in a screenshot.

This composes the house the way main.tscn does -- each room scene at its own
offset -- and checks:

  * every room has a way in;
  * every doorway is wide and tall enough for the body in flat_debug_rig.gd;
  * the open side of a room actually meets the wall it is supposed to;
  * nothing solid stands in a doorway.

Wall indices are room_builder.gd's: 0 = +Z, 1 = -Z, 2 = +X, 3 = -X.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, "scenes", "main.tscn")

# Must agree with flat_debug_rig.gd.
BODY_RADIUS = 0.22
STEP_CLEARANCE = 0.26
BODY_HEIGHT = 1.70
# Shoulders plus a hand each side. Below this a doorway is a squeeze, and in a
# headset you cannot feel the frame to correct against.
MIN_WIDTH = BODY_RADIUS * 2 + 0.30
MIN_HEIGHT = BODY_HEIGHT + 0.15

problems = []
notes = []


def fail(msg):
    problems.append(msg)


def vec(text):
    return [float(v) for v in text.split(",")]


def nodes(txt):
    for block in txt.split("[node ")[1:]:
        m = re.match(r'name="([^"]+)"', block)
        if m:
            yield m.group(1), block


def xform(block):
    m = re.search(r"transform = Transform3D\(([^)]*)\)", block)
    if not m:
        return (0.0, 0.0, 0.0)
    v = vec(m.group(1))
    return (v[9], v[10], v[11])


def ext_id(txt, script):
    m = re.search(r'path="res://scripts/world/%s"\s+id="([^"]+)"' % re.escape(script), txt)
    return m.group(1) if m else None


def placed_rooms():
    """name -> (scene path, world offset), as main.tscn instances them."""
    txt = open(MAIN, encoding="utf-8").read()
    paths = dict(re.findall(r'\[ext_resource type="PackedScene"[^\]]*?'
                            r'path="res://([^"]+)"\s+id="([^"]+)"', txt)[::1])
    paths = {i: p for p, i in re.findall(
        r'\[ext_resource type="PackedScene"[^\]]*?path="res://([^"]+)"\s+id="([^"]+)"', txt)}
    out = {}
    for name, block in nodes(txt):
        m = re.search(r'instance=ExtResource\("([^"]+)"\)', block)
        if not m or m.group(1) not in paths:
            continue
        rel = paths[m.group(1)]
        if not rel.startswith("scenes/rooms/") and not rel.startswith("scenes/outdoor/"):
            continue
        out[name] = (os.path.join(ROOT, rel), xform(block))
    return out


def room_shell(path, offset):
    """The RoomBuilder in `path`: its floor rectangle, which walls exist, and
    the doorways in them, all in world coordinates."""
    txt = open(path, encoding="utf-8").read()
    bid = ext_id(txt, "room_builder.gd")
    if bid is None:
        return None
    for _name, block in nodes(txt):
        if 'ExtResource("%s")' % bid not in block:
            continue
        size = re.search(r"\nsize = Vector2\(([^)]*)\)", block)
        if not size:
            return None
        w, d = vec(size.group(1))
        ox, _oy, oz = offset
        walls = re.search(r"\nbuild_walls = Array\[bool\]\(\[([^\]]*)\]\)", block)
        built = [s.strip() == "true" for s in walls.group(1).split(",")] if walls else [True] * 4
        doors = []
        op = re.search(r"\nopenings = Array\[Vector4\]\(\[(.*?)\]\)", block)
        if op:
            for one in re.findall(r"Vector4\(([^)]*)\)", op.group(1)):
                wall, centre, width, height = vec(one)
                doors.append((int(wall), centre, width, height))
        return {
            "x": (ox - w / 2, ox + w / 2),
            "z": (oz - d / 2, oz + d / 2),
            "built": built,
            "doors": doors,
            "offset": offset,
        }
    return None


def wall_plane(shell, index):
    """(axis, coordinate) of a wall: 0 = +Z, 1 = -Z, 2 = +X, 3 = -X."""
    return {0: ("z", shell["z"][1]), 1: ("z", shell["z"][0]),
            2: ("x", shell["x"][1]), 3: ("x", shell["x"][0])}[index]


def door_span(shell, index, centre, width):
    """The world span of a doorway along the wall it is in."""
    axis, coord = wall_plane(shell, index)
    along = "x" if axis == "z" else "z"
    mid = (shell[along][0] + shell[along][1]) / 2 + centre
    return along, (mid - width / 2, mid + width / 2), axis, coord


def solid_props(path, offset):
    """World-space footprints of everything tall enough to walk into."""
    txt = open(path, encoding="utf-8").read()
    pid = ext_id(txt, "prop.gd")
    out = []
    if pid is None:
        return out
    ox, oy, oz = offset
    for name, block in nodes(txt):
        if 'ExtResource("%s")' % pid not in block:
            continue
        if "\ncollide = false" in block:
            continue
        s = re.search(r"\nbox_size = Vector3\(([^)]*)\)", block)
        if not s:
            continue
        sx, sy, sz = [abs(v) for v in vec(s.group(1))]
        cx, cy, cz = xform(block)
        cx, cy, cz = cx + ox, cy + oy, cz + oz
        if cy + sy / 2 <= STEP_CLEARANCE:
            continue                     # stepped over, not walked into
        if cy - sy / 2 >= BODY_HEIGHT:
            continue                     # passed under: roofs, gables, lintels
        out.append((name, cx - sx / 2, cz - sz / 2, cx + sx / 2, cz + sz / 2))
    return out


## A WallButton's FRONT is its local +Z: that is where wall_button.gd puts the
## labels, and a Label3D reads from its own +Z side. Turn one round and it
## presents its back to the room -- and because a Label3D is double-sided by
## default, the text is still there, mirrored and half hidden behind the plate.
## All nine of them were like that, and it read as "the labels are unclear"
## rather than as nine buttons mounted backwards.
def check_button_facing(shells):
    txt = open(MAIN, encoding="utf-8").read()
    m = re.search(r'path="res://scripts/ui/wall_button\.gd"\s+id="([^"]+)"', txt)
    if not m:
        return 0
    bid = m.group(1)
    checked = 0
    for name, block in nodes(txt):
        if 'ExtResource("%s")' % bid not in block:
            continue
        t = re.search(r"transform = Transform3D\(([^)]*)\)", block)
        if not t:
            continue
        v = vec(t.group(1))
        front = (v[6], v[8])                 # the z basis column, in plan
        at = (v[9], v[11])
        checked += 1
        step = (at[0] + front[0] * 0.3, at[1] + front[1] * 0.3)
        inside = any(shell["x"][0] < step[0] < shell["x"][1]
                     and shell["z"][0] < step[1] < shell["z"][1]
                     for shell in shells.values())
        if not inside:
            fail("main.tscn: %s faces the wall. Its front (local +Z) points to "
                 "(%.2f, %.2f), which is not inside any room, so its labels are "
                 "mirrored and behind the plate." % (name, step[0], step[1]))
    return checked


def main():
    rooms = placed_rooms()
    shells = {}
    solids = []
    for name, (path, offset) in sorted(rooms.items()):
        shell = room_shell(path, offset)
        if shell:
            shells[name] = shell
        for prop in solid_props(path, offset):
            solids.append((name + "/" + prop[0],) + prop[1:])

    doors = []        # (owner, index, along, span, axis, coord, width, height)
    for name, shell in shells.items():
        for index, centre, width, height in shell["doors"]:
            along, span, axis, coord = door_span(shell, index, centre, width)
            doors.append((name, index, along, span, axis, coord, width, height))
            if width < MIN_WIDTH:
                fail("%s: a doorway is %.2f m wide; the body needs %.2f m."
                     % (name, width, MIN_WIDTH))
            if height < MIN_HEIGHT:
                fail("%s: a doorway is %.2f m tall; the body is %.2f m."
                     % (name, height, MIN_HEIGHT))

    # Every room must have a way in: its own doorway, or an open side that lands
    # on somebody else's doorway.
    for name, shell in shells.items():
        if shell["doors"]:
            continue
        open_sides = [i for i, built in enumerate(shell["built"]) if not built]
        if not open_sides:
            fail("%s has no doorway and no open side: it cannot be entered."
                 % name)
            continue
        reachable = False
        for index in open_sides:
            axis, coord = wall_plane(shell, index)
            along = "x" if axis == "z" else "z"
            for other, _i, oalong, span, oaxis, ocoord, _w, _h in doors:
                if other == name or oaxis != axis or oalong != along:
                    continue
                if abs(ocoord - coord) > 0.05:
                    continue
                if span[0] >= shell[along][0] - 0.01 and span[1] <= shell[along][1] + 0.01:
                    reachable = True
                    notes.append("%s is entered through %s's doorway at %s %.2f"
                                 % (name, other, along, sum(span) / 2))
        if not reachable:
            fail("%s is open on %s but no doorway meets that side: with solid "
                 "walls there is no way in."
                 % (name, ", ".join("wall %d" % i for i in open_sides)))

    # Nothing solid standing in a doorway.
    for owner, _index, along, span, axis, coord, _w, _h in doors:
        lo, hi = span
        for pname, x0, z0, x1, z1 in solids:
            a0, a1 = (x0, x1) if along == "x" else (z0, z1)
            c0, c1 = (z0, z1) if along == "x" else (x0, x1)
            if c0 - 0.25 > coord or c1 + 0.25 < coord:
                continue                 # not in the plane of the door
            # How much of the doorway is left once this prop is in it?
            overlap = min(hi, a1) - max(lo, a0)
            if overlap <= 0:
                continue
            left = max(a0 - lo, hi - a1)
            if left < MIN_WIDTH:
                fail("%s's doorway at %s %.2f is blocked by %s: %.2f m of gap "
                     "left, %.2f m needed."
                     % (owner, along, sum(span) / 2, pname, max(left, 0.0), MIN_WIDTH))

    buttons = check_button_facing(shells)

    print("checked %d placed scene(s), %d room shell(s), %d doorway(s), %d solid prop(s), "
          "%d button(s)" % (len(rooms), len(shells), len(doors), len(solids), buttons))
    print("  body: %.2f m wide, %.2f m tall, steps over %.0f mm"
          % (BODY_RADIUS * 2, BODY_HEIGHT, STEP_CLEARANCE * 1000))
    for n in sorted(set(notes)):
        print("  - " + n)
    if problems:
        print("")
        for p in problems:
            print("  ! " + p)
        print("\n%d problem(s)" % len(problems))
        return 1
    print("\nno problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
