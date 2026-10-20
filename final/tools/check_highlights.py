#!/usr/bin/env python3
"""Which prop will each hazard light up when it is hovered or flagged?

Mirrors scripts/world/hazard.gd: an explicit `highlight_meshes` list wins, and
otherwise the meshes whose bounds are at least INSIDE_FRACTION inside the aim
volume are taken. A hazard that lights up NOTHING gives the participant no
visual confirmation that the thing they pointed at is the thing that was
scored, which is the whole point of the glow.

Several kinds of mesh are considered, because the street and the house have
several:
  * a prop.gd sibling, whose box_size is written in the scene;
  * a puddle.gd sibling, which builds one flat "Water" surface the size of its
    `size` export at run time;
  * a staircase.gd sibling, which builds one solid block per tread, each one
    running from the floor up to that tread's top surface;
  * a drain_gully.gd sibling, which builds "Frame", "Shaft" and "Grate";
  * a leaf_litter.gd sibling, which builds "Leaves" and "Mulch".
All but the first exist only at run time, so they are modelled here from the
same exports the script reads. Anything named through `highlight_meshes` is checked
for existence rather than for overlap, since naming it is the point.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "scenes", "rooms"), os.path.join(ROOT, "scenes", "outdoor")]


def nodes(txt):
    out = {}
    for block in re.split(r"\n(?=\[node )", txt):
        m = re.match(r'\[node name="([^"]+)"', block)
        if m:
            out[m.group(1)] = block
    return out


def ext_id(txt, script):
    m = re.search(r'path="res://scripts/world/%s"\s+id="([^"]+)"' % re.escape(script), txt)
    return m.group(1) if m else None


def xform(block):
    m = re.search(r"transform = Transform3D\(([^)]*)\)", block)
    if not m:
        return 0.0, 0.0, 0.0
    v = [float(x) for x in m.group(1).split(",")]
    return v[9], v[10], v[11]


def vec3(block, key):
    m = re.search(r"\n%s = Vector3\(([^)]*)\)" % key, block)
    return [float(x) for x in m.group(1).split(",")] if m else None


def vec2(block, key):
    m = re.search(r"\n%s = Vector2\(([^)]*)\)" % key, block)
    return [float(x) for x in m.group(1).split(",")] if m else None


def num(block, key, default):
    m = re.search(r"\n%s = (-?[0-9.]+)" % key, block)
    return float(m.group(1)) if m else default


def named_meshes(block):
    """The `highlight_meshes` list, if the hazard names its meshes outright."""
    m = re.search(r"\nhighlight_meshes = .*", block)
    if not m:
        return []
    return re.findall(r'NodePath\("([^"]+)"\)', m.group(0))


## Scripts that build a known, fixed set of named meshes at run time. The
## bounds do not matter for these: a hazard that wants one names it, and the
## only question this file can usefully answer is whether the name is real.
GENERATED = {
    "drain_gully.gd": ["Frame", "Shaft", "Grate"],
    "leaf_litter.gd": ["Leaves", "Mulch"],
    "street_tree.gd": ["Trunk", "Canopy", "LowLimb", "LowLimbLeaves"],
}


def candidate_meshes(N, prop_id, puddle_id, stairs_id, generated=()):
    """Every mesh a hazard in this room could light up, as (name, centre, size)
    in room space -- props as the scene writes them, run-time geometry modelled
    from the same exports its script reads."""
    out = []
    for pname, pblock in N.items():
        px, py, pz = xform(pblock)
        if prop_id and 'ExtResource("%s")' % prop_id in pblock:
            s = vec3(pblock, "box_size")
            if s is not None:
                out.append((pname, (px, py, pz), s))
        elif puddle_id and 'ExtResource("%s")' % puddle_id in pblock:
            # One flat surface, `size` across, a few millimetres deep.
            sz = vec2(pblock, "size") or [1.7, 1.3]
            out.append(("%s/Water" % pname, (px, py, pz), [sz[0], 0.02, sz[1]]))
        elif stairs_id and 'ExtResource("%s")' % stairs_id in pblock:
            steps = int(num(pblock, "step_count", 8))
            rise = num(pblock, "rise", 0.19)
            going = num(pblock, "going", 0.25)
            width = num(pblock, "width", 0.9)
            uneven_at = int(num(pblock, "uneven_step_index", 0))
            extra = num(pblock, "uneven_extra_rise", 0.0)
            depth = num(pblock, "landing_depth", 1.6)

            def top_of(i):
                return i * rise + (extra if 0 < uneven_at <= i else 0.0)

            for i in range(1, steps + 1):
                top = top_of(i)
                out.append(("%s/Step%d" % (pname, i),
                            (px, py + top * 0.5, pz + (i - 0.5) * going),
                            [width, top, going]))
            top = top_of(steps)
            out.append(("%s/Landing" % pname,
                        (px, py + top * 0.5, pz + steps * going + depth * 0.5),
                        [width, top, depth]))
        else:
            for gid, names in generated:
                if 'ExtResource("%s")' % gid in pblock:
                    for nm in names:
                        # Far off to one side: these are reached by name, and a
                        # box here would only invite the overlap rule to guess.
                        out.append(("%s/%s" % (pname, nm), (9e3, 9e3, 9e3), [0.01] * 3))
    return out


def main():
    bad = 0
    for folder in DIRS:
        if not os.path.isdir(folder):
            continue
        for fn in sorted(os.listdir(folder)):
            if not fn.endswith(".tscn"):
                continue
            path = os.path.join(folder, fn)
            txt = open(path, encoding="utf-8").read()
            hid, pid = ext_id(txt, "hazard.gd"), ext_id(txt, "prop.gd")
            if not hid:
                continue
            N = nodes(txt)
            generated = [(ext_id(txt, script), names)
                         for script, names in GENERATED.items()
                         if ext_id(txt, script)]
            meshes = candidate_meshes(N, pid, ext_id(txt, "puddle.gd"),
                                      ext_id(txt, "staircase.gd"), generated)
            print("\n== %s" % fn)
            for name, block in N.items():
                if 'ExtResource("%s")' % hid not in block:
                    continue
                hx, hy, hz = xform(block)
                e = vec3(block, "extents") or [0.6, 0.6, 0.6]
                label = "(decoy)" if "is_hazard = false" in block else ""
                named = named_meshes(block)
                if named:
                    # Named outright, so the only question is whether the node
                    # is really there. A path into run-time geometry is matched
                    # against what that script will build.
                    known = {m[0] for m in meshes} | set(N.keys())
                    missing = [p for p in named
                               if p.replace("../", "").replace("./", "") not in known]
                    if missing:
                        bad += 1
                        print("   %-24s %-8s -> NAMED BUT MISSING: %s"
                              % (name, label, ", ".join(missing)))
                    else:
                        print("   %-24s %-8s -> %s  (named)"
                              % (name, label, ", ".join(named)))
                    continue
                hits = []
                for pname, centre, s in meshes:
                    px, py, pz = centre
                    whole = shared = 1.0
                    ok = True
                    for c, hc, hs, ps in ((0, hx, e[0], s[0]), (1, hy, e[1], s[1]),
                                          (2, hz, e[2], s[2])):
                        pc = (px, py, pz)[c]
                        size = max(ps, 0.02)
                        lo, hi = pc - ps / 2.0, pc + ps / 2.0
                        ov = min(hi, hc + hs / 2.0) - max(lo, hc - hs / 2.0)
                        if ov <= 0:
                            ok = False
                            break
                        whole *= size
                        shared *= max(ov, 0.02)
                    if ok and shared / whole >= 0.45:
                        hits.append(pname)
                if hits:
                    print("   %-24s %-8s -> %s" % (name, label, ", ".join(hits)))
                else:
                    bad += 1
                    print("   %-24s %-8s -> NOTHING; it will not glow" % (name, label))
    print("\n%d hazard(s) with nothing to light up" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
