#!/usr/bin/env python3
"""Static checks for the whole project, for when there is no engine to hand.

    python3 tools/check_project.py              # check everything
    python3 tools/check_project.py --inventory  # also print the gameplay inventory
    python3 tools/check_project.py --json out.json   # save the inventory to diff later

WHY THIS EXISTS. Most of this project was built and changed without being able
to open Godot, so "it parses and every reference resolves" is the only safety
net there is. These are the mistakes that actually happened while building it,
each now checked for:

  * a .tscn pointing at a script or scene file that had been renamed
  * ExtResource("7_x") used but never declared in the header
  * load_steps left behind after a sub_resource was added
  * a NodePath export pointing at a node that no longer exists
  * two sibling nodes given the same name, so one silently replaces the other
  * a surface name in a scene that the material library has never heard of
  * a texture referenced by the library with no PNG baked for it
  * a hazard with no hazard_id, or a room name the scoring does not know

The gameplay inventory is the important one for a visual pass: dump it before
touching the scenes, dump it again afterwards, diff the two, and you have proof
that making the house prettier did not move a single hazard, teleport disc,
handrail or trigger volume.
"""

import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".godot", "_backup_before_fixes", ".git", "texcheck"}

problems = []
notes = []


def fail(where, msg):
    problems.append("%s: %s" % (where, msg))


def walk(ext):
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for f in sorted(files):
            if f.endswith(ext):
                yield os.path.join(base, f)


def rel(path):
    return os.path.relpath(path, ROOT)


# ---------------------------------------------------------------------------
#  GDScript
# ---------------------------------------------------------------------------

def check_scripts():
    try:
        subprocess.run(["gdparse", "--version"], capture_output=True, check=False)
    except FileNotFoundError:
        notes.append("gdparse not installed (pip install gdtoolkit); scripts not parsed")
        return 0
    n = 0
    for path in walk(".gd"):
        n += 1
        r = subprocess.run(["gdparse", path], capture_output=True, text=True)
        if r.returncode != 0:
            fail(rel(path), "does not parse: " + (r.stdout + r.stderr).strip()[:300])
    return n


# ---------------------------------------------------------------------------
#  Scenes
# ---------------------------------------------------------------------------

EXT_RE = re.compile(r'\[ext_resource type="([^"]+)"(?:\s+uid="[^"]*")?\s+path="res://([^"]+)"\s+id="([^"]+)"\]')
USE_RE = re.compile(r'ExtResource\("([^"]+)"\)')
SUBUSE_RE = re.compile(r'SubResource\("([^"]+)"\)')
SUBDEF_RE = re.compile(r'\[sub_resource type="[^"]+" id="([^"]+)"\]')
NODE_RE = re.compile(r'\[node name="([^"]+)"(?:\s+type="([^"]+)")?(?:\s+parent="([^"]*)")?'
                     r'(?:\s+instance=ExtResource\("([^"]+)"\))?[^\]]*\]')
NODEPATH_RE = re.compile(r'(\w+)\s*=\s*NodePath\("([^"]*)"\)')
LOADSTEPS_RE = re.compile(r'load_steps=(\d+)')
PROP_RE = re.compile(r'^(\w+)\s*=\s*(.+)$', re.M)


def parse_scene(path):
    txt = open(path, encoding="utf-8").read()
    ext = {m.group(3): (m.group(1), m.group(2)) for m in EXT_RE.finditer(txt)}
    subs = set(SUBDEF_RE.findall(txt))

    nodes = []           # (name, type, parent, instance_id, body)
    chunks = re.split(r'(?m)^(?=\[node )', txt)
    for chunk in chunks[1:]:
        m = NODE_RE.match(chunk)
        if not m:
            fail(rel(path), "unparsable node header: " + chunk.splitlines()[0][:100])
            continue
        body = chunk[m.end():]
        nodes.append((m.group(1), m.group(2) or "", m.group(3), m.group(4), body))
    return txt, ext, subs, nodes


def node_paths(nodes):
    """Every node's path from the scene root, as Godot would address it."""
    out = {"."}
    for name, _type, parent, _inst, _body in nodes:
        if parent is None:
            continue
        out.add(name if parent == "." else parent + "/" + name)
    return out


def check_scene(path, inventory, scene_props):
    txt, ext, subs, nodes = parse_scene(path)
    where = rel(path)

    for res_id, (_type, res_path) in ext.items():
        if not os.path.exists(os.path.join(ROOT, res_path)):
            fail(where, "ext_resource %s points at missing file res://%s" % (res_id, res_path))
    for used in sorted(set(USE_RE.findall(txt))):
        if used not in ext:
            fail(where, 'ExtResource("%s") is used but never declared' % used)
    for used in sorted(set(SUBUSE_RE.findall(txt))):
        if used not in subs:
            fail(where, 'SubResource("%s") is used but never declared' % used)

    m = LOADSTEPS_RE.search(txt)
    if m:
        want = len(ext) + len(subs) + 1
        if int(m.group(1)) != want:
            fail(where, "load_steps=%s but the file has %d ext + %d sub resources (want %d)"
                 % (m.group(1), len(ext), len(subs), want))
    elif ext or subs:
        # load_steps is only a preallocation hint and Godot omits it in some
        # hand-written scenes, so its absence is fine -- a WRONG one is not.
        pass

    seen = set()
    for name, _type, parent, _inst, _body in nodes:
        key = (parent or "", name)
        if key in seen:
            fail(where, "two nodes named %r under %r" % (name, parent))
        seen.add(key)

    paths = node_paths(nodes)
    for name, _type, parent, _inst, body in nodes:
        for prop, target in NODEPATH_RE.findall(body):
            if not target.startswith("../"):
                continue          # relative to the node itself; resolved at runtime
            rest = target[3:]
            if rest and rest not in paths:
                fail(where, "%s.%s = NodePath(%r) does not resolve" % (name, prop, target))

    for name, node_type, _parent, inst, body in nodes:
        props = dict(PROP_RE.findall(body))
        if inst:
            continue        # an instanced scene: its own file is checked separately
        script_path = ""
        m2 = re.match(r'ExtResource\("([^"]+)"\)', props.get("script", ""))
        if m2 and m2.group(1) in ext:
            script_path = "res://" + ext[m2.group(1)][1]
        scene_props.append((where, name, node_type, script_path,
                            [k for k in props if k != "script"]))

    # GAMEPLAY INVENTORY: everything a visual pass must leave alone.
    #
    # Classified by the RESOLVED script path, not by the ExtResource id -- the id
    # is arbitrary per scene ("8_point" in one file, "4_rail" in another), so
    # matching on it silently found nothing, which is exactly the kind of quiet
    # false pass a safety net must not have.
    for name, _type, _parent, inst, body in nodes:
        if inst:
            continue
        props = dict(PROP_RE.findall(body))
        script_file = ""
        m3 = re.match(r'ExtResource\("([^"]+)"\)', props.get("script", ""))
        if m3 and m3.group(1) in ext:
            script_file = os.path.basename(ext[m3.group(1)][1])

        bucket = GAMEPLAY_SCRIPTS.get(script_file)
        if bucket is not None:
            row = {"scene": where, "node": name}
            row.update({k: v for k, v in props.items() if k != "script"})
            inventory[bucket].append(row)

        if bucket == "hazards" and not props.get("hazard_id", "").strip('"'):
            fail(where, "hazard %r has no hazard_id" % name)

        for key in ("collision_layer", "collision_mask"):
            if key in props:
                inventory["collision"].append({
                    "scene": where, "node": name, key: props[key]})

    return nodes


# ---------------------------------------------------------------------------
#  GDScript runtime traps a parser will not catch
# ---------------------------------------------------------------------------
#  gdparse only checks syntax, so these compile cleanly and fail when the line
#  is actually reached -- which, for a @tool script, means the room silently
#  loses its trim in the editor and you find out from the Errors tab.

TYPED_ARRAY_TERNARY = re.compile(
    r'(?m)^\s*var\s+\w+\s*:\s*Array\[[^\]]+\]\s*=\s*.*\bif\b.*\belse\b')

## A typed array assigned (not declared) from a bare literal: the literal is
## built untyped first, so the assignment can fail the same way.
TYPED_ARRAY_REASSIGN = re.compile(
    r'(?m)^\s*(\w+)\s*=\s*\[.*\]\s*$')


def check_gdscript_traps():
    for path in walk(".gd"):
        txt = open(path, encoding="utf-8").read()
        where = rel(path)
        typed_vars = set(re.findall(r'var\s+(\w+)\s*:\s*Array\[', txt))
        for i, line in enumerate(txt.splitlines(), 1):
            if TYPED_ARRAY_TERNARY.match(line):
                fail(where, "line %d: a typed Array assigned from a conditional. "
                     "GDScript cannot infer the element type through `if/else`, so "
                     "this fails at RUNTIME with \"Trying to assign an array of "
                     "type Array\". Build it with a plain branch, or use a Packed "
                     "array." % i)
            m = TYPED_ARRAY_REASSIGN.match(line)
            if m and m.group(1) in typed_vars and "[]" not in line:
                fail(where, "line %d: %s is a typed Array being assigned a bare "
                     "literal; that literal is built untyped and the assignment "
                     "can fail at runtime." % (i, m.group(1)))


# ---------------------------------------------------------------------------
#  Props with nothing holding them up
# ---------------------------------------------------------------------------
#  A branch at head height with no tree above it; a drain cover hovering 15 mm
#  over the paving. Both shipped, and both were reported by the participant
#  rather than caught here, because nothing in this file had an opinion about
#  what a prop was RESTING ON.
#
#  The rule: every prop must be connected to the ground. Two props are joined
#  when their boxes touch (within TOUCH), a prop is grounded when its underside
#  is within TOUCH of the lowest surface in the scene, and anything left over
#  after a walk out from the grounded ones is floating. Mutual support does not
#  count -- a stick resting on a leaf cluster resting on the stick is exactly
#  the shape of the bug.
#
#  Outdoor scenes only. Indoors the floor and walls are built by RoomBuilder at
#  run time, so half the props would look unsupported for want of a wall.
TOUCH = 0.03

#  Things this check cannot see the support for, and the ground itself. They
#  still hold other props up -- they are simply never reported as floating
#  themselves. Keep it short: every entry is a prop the check cannot protect.
FLOATING_OK = {
    "GroundPlane",      # it IS the ground
    "TreelineNorth", "TreelineWest", "TreelineEast",   # painted-on horizon
    # The house's own walls are built by RoomBuilder inside the ROOM scenes, so
    # from inside street.tscn everything fixed to the house looks unsupported.
    "FrontDoor", "DoorKnocker", "Letterbox", "HouseNumber", "DoorCanopy",
    "RoofNorth", "RoofKitchen", "RoofSouthWest", "RoofSouthEast",
    "RoofStairShaft",
}


def _script_id(txt, script):
    m = re.search(r'path="res://scripts/world/%s"\s+id="([^"]+)"' % re.escape(script), txt)
    return m.group(1) if m else None


def _prop_boxes(txt, pid):
    """name -> (lo, hi) world AABB, for every prop with a box_size."""
    out = {}
    for block in txt.split("[node ")[1:]:
        m = re.match(r'name="([^"]+)"', block)
        if not m or not pid or 'ExtResource("%s")' % pid not in block:
            continue
        size = re.search(r"\nbox_size = Vector3\(([^)]*)\)", block)
        if not size:
            continue
        s = [abs(float(v)) for v in size.group(1).split(",")]
        t = re.search(r"transform = Transform3D\(([^)]*)\)", block)
        v = [float(x) for x in t.group(1).split(",")] if t else [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        centre = v[9:12]
        # The basis may be a rotation, so take the extent of the rotated box.
        half = []
        for axis in range(3):
            half.append(0.5 * sum(abs(v[col * 3 + axis]) * s[col] for col in range(3)))
        out[m.group(1)] = ([centre[i] - half[i] for i in range(3)],
                           [centre[i] + half[i] for i in range(3)])
    return out


def _touching(a, b):
    lo_a, hi_a = a
    lo_b, hi_b = b
    return all(lo_a[i] - TOUCH <= hi_b[i] and lo_b[i] - TOUCH <= hi_a[i]
               for i in range(3))


def check_floating():
    for path in walk(".tscn"):
        txt = open(path, encoding="utf-8").read()
        if _script_id(txt, "room_builder.gd"):
            continue
        boxes = _prop_boxes(txt, _script_id(txt, "prop.gd"))
        # FLOATING_OK props stay IN the graph -- they are simply never reported.
        # Taking them out made the ground plane disappear from the world, so
        # anything resting on nothing but the ground read as floating: a row of
        # houses standing on the grass was reported as hanging in the air.
        if not boxes:
            continue
        floor = min(lo[1] for lo, _hi in boxes.values())
        reached = {n for n, (lo, _hi) in boxes.items() if lo[1] <= floor + TOUCH}
        frontier = list(reached)
        while frontier:
            here = frontier.pop()
            for other, box in boxes.items():
                if other in reached or not _touching(boxes[here], box):
                    continue
                reached.add(other)
                frontier.append(other)
        for name in sorted(set(boxes) - reached - FLOATING_OK):
            lo, hi = boxes[name]
            fail(rel(path), "%s floats: its underside is at y %+.3f and it "
                 "touches nothing that reaches the ground. Either stand it on "
                 "something, attach it to something, or add it to FLOATING_OK "
                 "in this file." % (name, lo[1]))


# ---------------------------------------------------------------------------
#  Two buttons in the same place
# ---------------------------------------------------------------------------
#  A WallButton draws a plate and two floating labels, and nothing anywhere
#  stops two of them being put at the same spot on the same wall. The night
#  button went in 0.15 m from ButtonAgain -- two 0.30 m plates sharing a place
#  -- and the only way that showed up was a participant looking at it.
BUTTON_GAP = 0.12          # a finger's width between plates


def check_button_spacing():
    buttons = []
    for path in walk(".tscn"):
        txt = open(path, encoding="utf-8").read()
        bid = None
        m = re.search(r'path="res://scripts/ui/wall_button\.gd"\s+id="([^"]+)"', txt)
        if m:
            bid = m.group(1)
        if bid is None:
            continue
        for block in txt.split("[node ")[1:]:
            name = re.match(r'name="([^"]+)"', block)
            if not name or 'ExtResource("%s")' % bid not in block:
                continue
            t = re.search(r"transform = Transform3D\(([^)]*)\)", block)
            v = [float(x) for x in t.group(1).split(",")] if t else [0] * 12
            size = re.search(r"button_size = Vector2\(([^)]*)\)", block)
            w = float(size.group(1).split(",")[0]) if size else 0.22
            buttons.append((rel(path), name.group(1), v[9], v[10], v[11], w))
    for i, a in enumerate(buttons):
        for b in buttons[i + 1:]:
            gap = sum((a[2 + k] - b[2 + k]) ** 2 for k in range(3)) ** 0.5
            need = (a[5] + b[5]) / 2 + BUTTON_GAP
            if gap < need:
                fail(a[0], "%s and %s are %.2f m apart and their plates are "
                     "%.2f m and %.2f m wide: they overlap. %.2f m of centres "
                     "is the minimum." % (a[1], b[1], gap, a[5], b[5], need))
    notes.append("%d wall button(s), none overlapping" % len(buttons))


# ---------------------------------------------------------------------------
#  A light night mode does not know about
# ---------------------------------------------------------------------------
#  Night mode switches the world by GROUP: `room_light` lamps come up and keep
#  their own authored energy, `daylight` beams go off, `street_light` comes on.
#  A light in none of them is simply left as it was -- so a new ceiling light
#  would stay blazing at midnight, and a new sunbeam would pour through a window
#  at two in the morning, with nothing anywhere reporting it.
LIGHT_GROUPS = ("room_light", "daylight", "street_light")
LIGHT_NODE = re.compile(r'\[node name="([^"]+)" type="(Omni|Spot)Light3D"([^\]]*)\]')


def check_lighting():
    counts = dict.fromkeys(LIGHT_GROUPS, 0)
    for path in walk(".tscn"):
        if "scenes/rooms" not in rel(path) and "scenes/outdoor" not in rel(path):
            continue
        txt = open(path, encoding="utf-8").read()
        for name, _kind, rest in LIGHT_NODE.findall(txt):
            found = [g for g in LIGHT_GROUPS if '"%s"' % g in rest]
            if not found:
                fail(rel(path), "light '%s' is in none of %s, so night mode "
                     "cannot switch it: it will stay exactly as it is after "
                     "dark." % (name, "/".join(LIGHT_GROUPS)))
            elif len(found) > 1:
                fail(rel(path), "light '%s' is in %d lighting groups; it must "
                     "be in exactly one." % (name, len(found)))
            else:
                counts[found[0]] += 1
    notes.append("lighting: " + ", ".join("%d %s" % (counts[g], g) for g in LIGHT_GROUPS))


# ---------------------------------------------------------------------------
#  A room with nothing to say
# ---------------------------------------------------------------------------
#  Each room's guidance is spoken when the participant walks into it, from
#  ROOM_GUIDES in session_director.gd. A room missing from that table falls back
#  to silence -- which is how the whole house came to be briefed once, at the
#  start, with one block of text that talked about pedestrian crossings while
#  the participant stood in the bathroom.


def check_room_guides():
    director = os.path.join(ROOT, "scripts", "session_director.gd")
    manager = os.path.join(ROOT, "scripts", "autoload", "session_manager.gd")
    if not (os.path.exists(director) and os.path.exists(manager)):
        return
    dtxt = open(director, encoding="utf-8").read()
    mtxt = open(manager, encoding="utf-8").read()
    block = re.search(r"const ROOM_GUIDES := \{(.*?)\n\}", dtxt, re.S)
    order = re.search(r"const ROOM_ORDER: Array\[String\] = \[(.*?)\]", mtxt, re.S)
    if not block or not order:
        fail(rel(director), "cannot find ROOM_GUIDES or ROOM_ORDER to compare")
        return
    guides = set(re.findall(r'"(\w+)":\s*\{', block.group(1)))
    rooms = set(re.findall(r'"(\w+)"', order.group(1)))
    for room in sorted(rooms - guides):
        fail(rel(director), "room '%s' is scored but has no entry in ROOM_GUIDES, "
             "so nothing is said when the participant walks into it." % room)
    for room in sorted(guides - rooms):
        fail(rel(director), "ROOM_GUIDES has an entry for '%s', which is not a "
             "room in ROOM_ORDER." % room)
    for room in sorted(guides & rooms):
        body = re.search(r'"%s":\s*\{(.*?)\n\t\}' % room, block.group(1), re.S)
        if body and not re.search(r'"body":\s*"[^"]{20,}"', body.group(1)):
            fail(rel(director), "ROOM_GUIDES['%s'] has no usable body text." % room)


# ---------------------------------------------------------------------------
#  Private methods that do not exist
# ---------------------------------------------------------------------------
#  A call to a method that is not there is a PARSER error, so the script does
#  not load at all and every node using it is dead -- but `gdparse` only checks
#  syntax, so it reports the file as fine. This cost a run of the whole project
#  once: a rewrite left `_gather_meshes_recursive(self)` behind in hazard.gd
#  after the function it named had been replaced, and nothing short of opening
#  the editor said so.
#
#  Only underscore-prefixed calls are checked, because those are by convention
#  the ones defined in the same file. Engine virtuals are not defined there and
#  are listed instead.
GODOT_VIRTUALS = {
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_shortcut_input", "_gui_input", "_enter_tree",
    "_exit_tree", "_notification", "_init", "_draw", "_get", "_set",
    "_to_string", "_get_property_list", "_validate_property",
    "_integrate_forces", "_get_configuration_warnings", "_property_can_revert",
    "_property_get_revert",
}
PRIVATE_CALL = re.compile(r"(?<![\w.])(_\w+)\s*\(")


def check_private_calls():
    for path in walk(".gd"):
        txt = open(path, encoding="utf-8").read()
        defined = set(re.findall(r"^(?:static )?func (_\w+)", txt, re.M))
        for m in PRIVATE_CALL.finditer(txt):
            name = m.group(1)
            if name in defined or name in GODOT_VIRTUALS:
                continue
            line_start = txt.rfind("\n", 0, m.start()) + 1
            if txt[line_start:m.start()].lstrip().startswith("#"):
                continue
            fail(rel(path), "line %d: calls %s(), which is not defined in this "
                 "file. That is a parser error, so the script will not load at "
                 "all and every node using it is dead."
                 % (txt[:m.start()].count("\n") + 1, name))


# ---------------------------------------------------------------------------
#  Property names
# ---------------------------------------------------------------------------
#  Godot silently DROPS an assignment in a .tscn whose property name does not
#  exist on that node -- no error, no warning, and the line is deleted the next
#  time the editor saves the scene. That makes a typo here the one mistake a
#  test-run would not catch either, so the names are checked against the
#  @export lists of the scripts and an allowlist of the engine properties this
#  project actually uses.


## Script file -> inventory bucket. Every one of these carries behaviour the
## realism pass must not disturb: what can be flagged and for how many points,
## where you are allowed to stand, what the hand can hold, and which room the
## scoring thinks you are in.
GAMEPLAY_SCRIPTS = {
    "hazard.gd": "hazards",
    "slip_zone.gd": "slip_zones",
    "room_route.gd": "routes",
    "route_marker.gd": "route_markers",
    "room_zone.gd": "room_zones",
    "gated_teleport_point.gd": "teleport_points",
    "gated_region.gd": "gated_regions",
    "grab_rail.gd": "rails",
    "handrail_zone.gd": "handrail_zones",
    "street_crossing.gd": "crossings",
    "street_car.gd": "cars",
    "staircase.gd": "staircases",
    "balance_exercise.gd": "balance",
    "balance_orb.gd": "balance",
    "focus_beacon.gd": "beacons",
    "wall_button.gd": "buttons",
}

INVENTORY_KEYS = sorted(set(GAMEPLAY_SCRIPTS.values())) + ["collision"]

EXPORT_RE = re.compile(r'^@export(?:_\w+)?(?:\([^)]*\))?\s+var\s+(\w+)', re.M)

## Every node can take these, whatever it is.
COMMON = {"script", "transform", "position", "rotation", "rotation_degrees",
          "scale", "visible", "process_mode", "name", "owner", "unique_name_in_owner",
          "editor_description", "top_level", "visibility_parent"}

## Engine properties used by the scenes in this project, by node type. Add to
## these when a scene starts using a new one; an unknown name is a hard failure
## precisely because Godot will not tell you about it.
ENGINE_PROPS = {
    "Node3D": set(),
    "Node": set(),
    "Area3D": {"monitoring", "monitorable", "collision_layer", "collision_mask",
               "input_ray_pickable", "priority", "gravity_space_override"},
    "StaticBody3D": {"collision_layer", "collision_mask", "physics_material_override"},
    "CollisionShape3D": {"shape", "disabled"},
    "MeshInstance3D": {"mesh", "material_override", "material_overlay", "cast_shadow",
                       "gi_mode", "transparency"},
    "OmniLight3D": {"light_color", "light_energy", "light_indirect_energy",
                    "light_specular", "light_size", "light_negative", "light_volumetric_fog_energy",
                    "light_cull_mask", "light_bake_mode", "shadow_enabled", "shadow_bias",
                    "shadow_normal_bias", "shadow_blur", "shadow_opacity", "shadow_reverse_cull_face",
                    "omni_range", "omni_attenuation", "omni_shadow_mode", "distance_fade_enabled",
                    "distance_fade_begin", "distance_fade_length", "distance_fade_shadow", "editor_only"},
    "SpotLight3D": {"light_color", "light_energy", "light_indirect_energy", "light_specular",
                    "light_size", "light_negative", "light_volumetric_fog_energy", "light_cull_mask",
                    "light_bake_mode", "shadow_enabled", "shadow_bias", "shadow_normal_bias",
                    "shadow_blur", "shadow_opacity", "spot_range", "spot_attenuation",
                    "spot_angle", "spot_angle_attenuation", "distance_fade_enabled",
                    "distance_fade_begin", "distance_fade_length", "distance_fade_shadow", "editor_only"},
    "DirectionalLight3D": {"light_color", "light_energy", "light_indirect_energy",
                           "light_specular", "light_angular_distance", "light_negative",
                           "light_volumetric_fog_energy", "light_cull_mask", "light_bake_mode",
                           "shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur",
                           "shadow_opacity", "shadow_reverse_cull_face",
                           "directional_shadow_mode", "directional_shadow_split_1",
                           "directional_shadow_split_2", "directional_shadow_split_3",
                           "directional_shadow_blend_splits", "directional_shadow_fade_start",
                           "directional_shadow_max_distance", "directional_shadow_pancake_size",
                           "sky_mode", "editor_only"},
    "WorldEnvironment": {"environment", "camera_attributes", "compositor"},
    "Marker3D": {"gizmo_extents"},
    "Camera3D": {"fov", "near", "far", "current", "environment", "attributes",
                 "projection", "size", "cull_mask", "doppler_tracking"},
    "Label3D": {"text", "font", "font_size", "pixel_size", "billboard", "double_sided",
                "no_depth_test", "modulate", "outline_size", "outline_modulate",
                "horizontal_alignment", "vertical_alignment", "width", "autowrap_mode",
                "shaded", "alpha_cut", "render_priority", "fixed_size"},
    "AudioStreamPlayer": {"stream", "volume_db", "autoplay", "bus", "pitch_scale",
                          "max_polyphony", "playback_type"},
    "AudioStreamPlayer3D": {"stream", "volume_db", "autoplay", "bus", "pitch_scale",
                            "unit_size", "max_db", "max_distance", "attenuation_model",
                            "panning_strength", "doppler_tracking"},
    "SubViewport": {"size", "size_2d_override", "size_2d_override_stretch",
                    "transparent_bg", "render_target_update_mode", "render_target_clear_mode",
                    "handle_input_locally", "gui_disable_input", "msaa_2d", "msaa_3d",
                    "own_world_3d", "world_3d", "disable_3d", "canvas_item_default_texture_filter"},
}

## Node types whose properties we do not police, because they are UI or XR nodes
## with very large surfaces and the scenes only set a handful of obvious ones.
UNPOLICED_PREFIXES = ("XR", "Control", "Panel", "Label", "Rich", "VBox", "HBox",
                      "Grid", "Margin", "Color", "Texture", "Button", "Scroll",
                      "Center", "Separator", "Timer", "Animation", "CanvasLayer")


def script_exports():
    """Exported property names for every script, by its res:// path."""
    out = {}
    for path in walk(".gd"):
        txt = open(path, encoding="utf-8").read()
        names = set(EXPORT_RE.findall(txt))
        # A script inherits its base class's exports when it extends another of
        # ours; follow one level, which is all this project uses.
        out["res://" + rel(path).replace(os.sep, "/")] = names
    return out


def check_properties(scene_props, exports):
    for where, node, node_type, script_path, keys in scene_props:
        allowed = set(COMMON)
        if script_path:
            if script_path not in exports:
                fail(where, "%s has script %s, which is not a file in this project"
                     % (node, script_path))
                continue
            allowed |= exports[script_path]
        if node_type:
            if node_type.startswith(UNPOLICED_PREFIXES):
                continue
            if node_type in ENGINE_PROPS:
                allowed |= ENGINE_PROPS[node_type]
                # 3D nodes all inherit the Node3D/VisualInstance3D basics.
                allowed |= {"layers", "sorting_offset", "gi_mode",
                            "extra_cull_margin", "lod_bias"}
            elif not script_path:
                notes.append("%s: %s is a %s, whose properties are not in the "
                             "allowlist -- names not checked" % (where, node, node_type))
                continue
        for key in keys:
            if key not in allowed:
                fail(where, "%s.%s does not exist -- Godot will silently DROP this line"
                     % (node, key))


## Resource properties used in [sub_resource] blocks. The environment block is
## the worst place in the project for a typo: it is one long list of names, a
## wrong one is dropped in silence, and the only symptom is that the house looks
## slightly wrong in a way you would blame on the values.
RESOURCE_PROPS = {
    "Environment": {
        "background_mode", "background_color", "background_energy_multiplier",
        "background_intensity", "background_canvas_max_layer", "background_camera_feed_id",
        "sky", "sky_custom_fov", "sky_rotation",
        "ambient_light_source", "ambient_light_color", "ambient_light_sky_contribution",
        "ambient_light_energy", "reflected_light_source",
        "tonemap_mode", "tonemap_exposure", "tonemap_white",
        "ssr_enabled", "ssr_max_steps", "ssr_fade_in", "ssr_fade_out", "ssr_depth_tolerance",
        "ssao_enabled", "ssao_radius", "ssao_intensity", "ssao_power", "ssao_detail",
        "ssao_horizon", "ssao_sharpness", "ssao_light_affect", "ssao_ao_channel_affect",
        "ssil_enabled", "ssil_radius", "ssil_intensity", "ssil_sharpness",
        "ssil_normal_rejection",
        "sdfgi_enabled", "sdfgi_use_occlusion", "sdfgi_read_sky_light", "sdfgi_bounce_feedback",
        "sdfgi_cascades", "sdfgi_min_cell_size", "sdfgi_cascade0_distance", "sdfgi_max_distance",
        "sdfgi_y_scale", "sdfgi_energy", "sdfgi_normal_bias", "sdfgi_probe_bias",
        "glow_enabled", "glow_normalized", "glow_intensity", "glow_strength", "glow_mix",
        "glow_bloom", "glow_blend_mode", "glow_hdr_threshold", "glow_hdr_scale",
        "glow_hdr_luminance_cap", "glow_map_strength", "glow_map",
        "fog_enabled", "fog_mode", "fog_light_color", "fog_light_energy", "fog_sun_scatter",
        "fog_density", "fog_aerial_perspective", "fog_sky_affect", "fog_height",
        "fog_height_density", "fog_depth_curve", "fog_depth_begin", "fog_depth_end",
        "volumetric_fog_enabled", "volumetric_fog_density", "volumetric_fog_albedo",
        "volumetric_fog_emission", "volumetric_fog_emission_energy", "volumetric_fog_gi_inject",
        "volumetric_fog_anisotropy", "volumetric_fog_length", "volumetric_fog_detail_spread",
        "volumetric_fog_ambient_inject", "volumetric_fog_sky_affect",
        "volumetric_fog_temporal_reprojection_enabled", "volumetric_fog_temporal_reprojection_amount",
        "adjustment_enabled", "adjustment_brightness", "adjustment_contrast",
        "adjustment_saturation", "adjustment_color_correction",
    },
    "Sky": {"sky_material", "process_mode", "radiance_size"},
    "PhysicalSkyMaterial": {"rayleigh_coefficient", "rayleigh_color", "mie_coefficient",
                            "mie_eccentricity", "mie_color", "turbidity", "sun_disk_scale",
                            "ground_color", "energy_multiplier", "use_debanding", "night_sky"},
    "ProceduralSkyMaterial": {"sky_top_color", "sky_horizon_color", "sky_curve",
                              "sky_energy_multiplier", "sky_cover", "sky_cover_modulate",
                              "ground_bottom_color", "ground_horizon_color", "ground_curve",
                              "ground_energy_multiplier", "sun_angle_max", "sun_curve",
                              "use_debanding", "energy_multiplier"},
    "BoxShape3D": {"size"},
    "BoxMesh": {"size", "subdivide_width", "subdivide_height", "subdivide_depth"},
    "CylinderShape3D": {"radius", "height"},
    "SphereShape3D": {"radius"},
    "CapsuleShape3D": {"radius", "height"},
}

RESOURCE_COMMON = {"resource_local_to_scene", "resource_name", "resource_path", "script"}

SUBRES_RE = re.compile(r'\[sub_resource type="([^"]+)" id="([^"]+)"\]')


def check_sub_resources(path):
    """Property names inside [sub_resource] blocks -- same silent-drop trap."""
    txt = open(path, encoding="utf-8").read()
    where = rel(path)
    chunks = re.split(r'(?m)^(?=\[sub_resource )', txt)
    for chunk in chunks[1:]:
        m = SUBRES_RE.match(chunk)
        if not m:
            continue
        res_type, res_id = m.group(1), m.group(2)
        body = chunk[m.end():].split("\n[", 1)[0]
        keys = [k for k, _v in PROP_RE.findall(body)]
        if res_type not in RESOURCE_PROPS:
            if keys:
                notes.append("%s: sub_resource %s is a %s, not in the allowlist -- "
                             "names not checked" % (where, res_id, res_type))
            continue
        allowed = RESOURCE_PROPS[res_type] | RESOURCE_COMMON
        for key in keys:
            if key not in allowed:
                fail(where, "%s (%s).%s does not exist -- Godot will silently DROP this line"
                     % (res_id, res_type, key))


# ---------------------------------------------------------------------------
#  Surfaces and textures
# ---------------------------------------------------------------------------

def known_surfaces():
    path = os.path.join(ROOT, "scripts", "util", "surfaces.gd")
    if not os.path.exists(path):
        return None
    txt = open(path, encoding="utf-8").read()
    block = txt.split("const SPECS := {", 1)
    if len(block) < 2:
        return None
    return set(re.findall(r'^\t"([a-z0-9_]+)":', block[1], re.M))


def check_surfaces():
    known = known_surfaces()
    if known is None:
        notes.append("scripts/util/surfaces.gd not found; surface names not checked")
        return
    notes.append("material library knows %d surfaces" % len(known))

    tex_dir = os.path.join(ROOT, "assets", "textures")
    manifest_path = os.path.join(tex_dir, "manifest.json")
    baked = set()
    if os.path.exists(manifest_path):
        baked = set(json.load(open(manifest_path)))
    missing_maps = []
    for name in sorted(baked):
        for kind in ("albedo", "normal", "rough"):
            f = os.path.join(tex_dir, "%s_%s.png" % (name, kind))
            if not os.path.exists(f):
                missing_maps.append(rel(f))
    if missing_maps:
        fail("assets/textures", "manifest lists maps that are not on disk: "
             + ", ".join(missing_maps[:6]))
    unbaked = sorted(baked - known)
    if unbaked:
        fail("surfaces.gd", "textures baked but no surface uses them: " + ", ".join(unbaked))
    notes.append("%d surfaces have baked PBR maps, %d are plain by design"
                 % (len(baked & known), len(known - baked)))

    used = {}
    for path in list(walk(".tscn")) + list(walk(".gd")):
        txt = open(path, encoding="utf-8").read()
        for m in re.finditer(r'(?:surface|_surface)\s*=\s*"([a-z0-9_]*)"', txt):
            if m.group(1):
                used.setdefault(m.group(1), []).append(rel(path))
    for name, where in sorted(used.items()):
        if name not in known:
            fail(where[0], 'surface "%s" is not in Surfaces.SPECS' % name)
    notes.append("%d distinct surfaces referenced by scenes" % len(used))


# ---------------------------------------------------------------------------
#  Room geometry
# ---------------------------------------------------------------------------
#  RoomBuilder turns a size, a ceiling height and two arrays of holes into wall
#  segments. Getting that wrong does not raise an error -- it produces a wall
#  with a gap in it, or two segments in the same place z-fighting, or a window
#  cut into a wall that was never built. None of those look like a bug until you
#  are standing in the room, so every room's real numbers are swept here.

VEC4_RE = re.compile(r'Vector4\(([^)]*)\)')


def _room_builders():
    """(scene, size, height, walls, doorways, windows, sill) for every room."""
    out = []
    for path in walk(".tscn"):
        txt = open(path, encoding="utf-8").read()
        for m in re.finditer(r'(?m)^\[node name="[^"]*" type="Node3D"[^\]]*\]\n', txt):
            body = txt[m.end():]
            nxt = body.find("\n[")
            body = body if nxt < 0 else body[:nxt]
            if "room_builder.gd" not in body and "1_room" not in body:
                continue
            size = re.search(r'(?m)^size = Vector2\(([^)]*)\)$', body)
            if not size:
                continue

            def num(key, default):
                mm = re.search(r'(?m)^%s = ([-\d.eE]+)$' % key, body)
                return float(mm.group(1)) if mm else default

            def holes(key):
                mm = re.search(r'(?m)^%s = Array\[Vector4\]\(\[(.*?)\]\)$' % key, body, re.S)
                if not mm or not mm.group(1).strip():
                    return []
                return [tuple(float(x) for x in v.split(","))
                        for v in VEC4_RE.findall(mm.group(1))]

            walls = [True] * 4
            bw = re.search(r'(?m)^build_walls = Array\[bool\]\(\[(.*?)\]\)$', body)
            if bw:
                walls = [x.strip() == "true" for x in bw.group(1).split(",")]

            out.append({
                "scene": rel(path),
                "size": tuple(float(x) for x in size.group(1).split(",")),
                "height": num("height", 2.4),
                "walls": walls,
                "doorways": holes("openings"),
                "windows": holes("window_openings"),
                "sill": num("window_sill_height", 0.85),
            })
    return out


def check_room_geometry():
    rooms = _room_builders()
    if not rooms:
        return
    swept = 0
    for r in rooms:
        where = r["scene"]
        sx, sz = r["size"]
        height = r["height"]
        for w in range(4):
            length = (sx, sx, sz, sz)[w]
            holes = []
            for o in r["doorways"]:
                if int(o[0]) == w:
                    holes.append([o[1] - o[2] / 2, o[1] + o[2] / 2,
                                  0.0, min(o[3], height), "doorway"])
            for o in r["windows"]:
                if int(o[0]) == w:
                    holes.append([o[1] - o[2] / 2, o[1] + o[2] / 2, r["sill"],
                                  min(r["sill"] + o[3], height), "window"])
            if holes and not r["walls"][w]:
                fail(where, "wall %d is not built, but %d hole(s) are declared in it -- "
                     "they will simply not exist" % (w, len(holes)))
                continue
            if not r["walls"][w]:
                continue
            holes.sort()
            for i, (a, b, bottom, top, kind) in enumerate(holes):
                if a < -length / 2 - 1e-9 or b > length / 2 + 1e-9:
                    fail(where, "wall %d: %s runs off the end of a %.2f m wall" % (w, kind, length))
                if top > height + 1e-9:
                    fail(where, "wall %d: %s reaches above the ceiling" % (w, kind))
                if top - bottom <= 0.01:
                    fail(where, "wall %d: %s has no height" % (w, kind))
                if kind == "window" and bottom <= 0.01:
                    fail(where, "wall %d: window sits on the floor -- use `openings` "
                         "for a doorway" % w)
                if i and holes[i - 1][1] > a + 1e-9:
                    fail(where, "wall %d: %s overlaps the hole beside it" % (w, kind))

            # Sweep the wall plane: every point is either inside a hole or
            # covered by exactly one segment.
            segments = []
            cursor = -length / 2
            for a, b, bottom, top, _k in holes:
                a = max(a, -length / 2)
                b = min(b, length / 2)
                if a > cursor:
                    segments.append((cursor, a, 0.0, height))
                if bottom > 0.001:
                    segments.append((a, b, 0.0, bottom))
                if top < height - 0.001:
                    segments.append((a, b, top, height))
                cursor = max(cursor, b)
            if cursor < length / 2:
                segments.append((cursor, length / 2, 0.0, height))

            step_t = max(length / 120.0, 0.02)
            step_y = max(height / 60.0, 0.02)
            t = -length / 2 + step_t * 0.5
            while t < length / 2:
                y = step_y * 0.5
                while y < height:
                    in_hole = any(a < t < b and lo < y < hi for a, b, lo, hi, _k in holes)
                    n = sum(1 for a, b, lo, hi in segments if a <= t <= b and lo <= y <= hi)
                    if in_hole and n:
                        fail(where, "wall %d: solid wall inside a hole at %.2f, %.2f" % (w, t, y))
                        y = height
                    elif not in_hole and n == 0:
                        fail(where, "wall %d: GAP in the wall at %.2f, %.2f" % (w, t, y))
                        y = height
                    elif n > 1:
                        fail(where, "wall %d: %d overlapping wall segments at %.2f, %.2f"
                             % (w, n, t, y))
                        y = height
                    y += step_y
                t += step_t
        swept += 1
    notes.append("swept the wall geometry of %d rooms (%d doorways, %d windows)"
                 % (swept, sum(len(r["doorways"]) for r in rooms),
                    sum(len(r["windows"]) for r in rooms)))


# ---------------------------------------------------------------------------
#  Route markers
# ---------------------------------------------------------------------------

def check_hazard_volumes():
    """Two hazards in one room must not have overlapping aim volumes.

    The pointer ray returns the nearest collider. Where two aim volumes
    intersect, which hazard lights up depends on where the participant happens
    to be standing -- so one of them can become effectively unreachable, and a
    decoy sitting inside a real hazard would punish a correct answer.
    """
    for path in walk(".tscn"):
        txt = open(path, encoding="utf-8").read()
        m = re.search(r'path="res://scripts/world/hazard\.gd"\s+id="([^"]+)"', txt)
        if not m:
            continue
        rid = m.group(1)
        vols = []
        for block in txt.split("[node ")[1:]:
            if 'ExtResource("%s")' % rid not in block:
                continue
            name = re.match(r'name="([^"]+)"', block).group(1)
            tr = re.search(r"transform = Transform3D\(([^)]*)\)", block)
            v = [float(x) for x in tr.group(1).split(",")] if tr else [0.0] * 12
            ex = re.search(r"extents = Vector3\(([^)]*)\)", block)
            e = [float(x) for x in ex.group(1).split(",")] if ex else [0.6, 0.6, 0.6]
            vols.append((name, v[9], v[10], v[11], e[0] / 2.0, e[1] / 2.0, e[2] / 2.0))
        for i in range(len(vols)):
            for j in range(i + 1, len(vols)):
                a, b = vols[i], vols[j]
                # 1 mm of slack: volumes that merely touch are fine, and exact
                # arithmetic on scene floats would otherwise read as a clash.
                if all(abs(a[1 + k] - b[1 + k]) < a[4 + k] + b[4 + k] - 0.001
                       for k in range(3)):
                    fail(path, "hazard aim volumes %s and %s overlap -- which one "
                         "the pointer finds would depend on where you stand"
                         % (a[0], b[0]))
        if vols:
            notes.append("%s: %d hazard aim volumes, none overlapping"
                         % (os.path.basename(path), len(vols)))


def check_street():
    """The crossing has to line up with itself.

    The street is the one place where geometry, a signal and moving traffic all
    have to agree: a stop line on the wrong side of the crossing, or a lane
    whose cars drive on the centre line, is invisible in the scene file and
    obvious the moment somebody stands at the kerb.
    """
    path = os.path.join(ROOT, "scenes", "outdoor", "street.tscn")
    if not os.path.exists(path):
        return
    txt = open(path, encoding="utf-8").read()
    blocks = {}
    for block in re.split(r"\n(?=\[node )", txt):
        m = re.match(r'\[node name="([^"]+)"', block)
        if m:
            blocks[m.group(1)] = block

    def pos(name):
        m = re.search(r"transform = Transform3D\(([^)]*)\)", blocks[name])
        v = [float(x) for x in m.group(1).split(",")]
        return v[9], v[10], v[11]

    def box(name):
        m = re.search(r"box_size = Vector3\(([^)]*)\)", blocks[name])
        return [float(x) for x in m.group(1).split(",")]

    def num(name, key, default=0.0):
        m = re.search(r"\n%s = (-?[\d.]+)" % key, blocks[name])
        return float(m.group(1)) if m else default

    for required in ("Road", "Pavement", "FarPavement", "RoadCrossing"):
        if required not in blocks:
            fail(path, "street is missing its %s" % required)
            return

    road_z, road_d = pos("Road")[2], box("Road")[2]
    near_edge, far_edge = road_z - road_d / 2.0, road_z + road_d / 2.0

    # A kerb stands in the gap between pavement and carriageway, so the two are
    # not expected to meet -- what matters is that the gap is kerb-sized and
    # that a kerb is actually in it.
    def kerb_bridges(lo, hi, prefix):
        for name in blocks:
            if name.startswith(prefix) and lo - 0.08 <= pos(name)[2] <= hi + 0.08:
                return True
        return False

    pav_z, pav_d = pos("Pavement")[2], box("Pavement")[2]
    gap_lo, gap_hi = pav_z + pav_d / 2.0, near_edge
    if not (0.0 <= gap_hi - gap_lo <= 0.25) or not kerb_bridges(gap_lo, gap_hi, "KerbNear"):
        fail(path, "near pavement ends at z %.2f, the road starts at %.2f, and no "
             "kerb bridges them" % (gap_lo, gap_hi))
    far_z, far_d = pos("FarPavement")[2], box("FarPavement")[2]
    gap_lo, gap_hi = far_edge, far_z - far_d / 2.0
    if not (0.0 <= gap_hi - gap_lo <= 0.25) or not kerb_bridges(gap_lo, gap_hi, "KerbFar"):
        fail(path, "road ends at z %.2f, the far pavement starts at %.2f, and no "
             "kerb bridges them" % (gap_lo, gap_hi))

    half = num("RoadCrossing", "crossing_half_width", 1.8)
    centre = num("RoadCrossing", "crossing_centre_x", 0.0)
    bars = sorted(n for n in blocks if n.startswith("CrossingBar"))
    for name in bars:
        bx, _by, bz = pos(name)
        bw = box(name)[0]
        if bz < near_edge - 0.1 or bz > far_edge + 0.1:
            fail(path, "%s at z %.2f is off the carriageway (%.2f..%.2f)"
                 % (name, bz, near_edge, far_edge))
        if abs(bw / 2.0 - half) > 0.25 or abs(bx - centre) > 0.05:
            fail(path, "%s is %.2f m wide at x %.2f, but the scored crossing is "
                 "%.2f m either side of %.2f" % (name, bw, bx, half, centre))
    if bars and (min(pos(n)[2] for n in bars) - near_edge > 1.2
                 or far_edge - max(pos(n)[2] for n in bars) > 1.2):
        fail(path, "the zebra does not reach both kerbs")

    # Lanes. Driving on the left: eastbound (+X) uses the near half.
    for name, block in blocks.items():
        if "street_car.gd" not in block and 'ExtResource("5_car")' not in block:
            continue
        cz = pos(name)[2]
        sx = num(name, "start_x", -26.0)
        ex = num(name, "end_x", 26.0)
        direction = 1.0 if ex >= sx else -1.0
        if cz < near_edge + 0.6 or cz > far_edge - 0.6:
            fail(path, "%s drives at z %.2f, not inside the carriageway" % (name, cz))
        if abs(cz - road_z) < 0.5:
            fail(path, "%s drives along the centre line at z %.2f" % (name, cz))
        wants_near = direction > 0.0
        is_near = cz < road_z
        if wants_near != is_near:
            fail(path, "%s travels %s but is in the %s lane -- driving on the left "
                 "puts eastbound traffic on the near side"
                 % (name, "+X" if direction > 0 else "-X", "near" if is_near else "far"))
        line = num(name, "stop_line_x", 0.0)
        if line != 0.0 and (line - centre) * direction > -half:
            fail(path, "%s holds at x %.2f, which is not short of the crossing it "
                 "is approaching" % (name, line))

    for name in ("StopLineNear", "StopLineFar"):
        if name not in blocks:
            continue
        lx, _ly, lz = pos(name)
        if lz < near_edge or lz > far_edge:
            fail(path, "%s is not on the carriageway" % name)
        if abs(lx) <= half:
            fail(path, "%s is painted across the crossing itself" % name)

    posts = [n for n, b in blocks.items() if 'ExtResource("8_post")' in b]
    for name in posts:
        px, _py, pz = pos(name)
        if near_edge < pz < far_edge:
            fail(path, "%s stands in the road at z %.2f" % (name, pz))
        # A pole in the front path is a pole to walk into on the way out of
        # your own gate, and nothing else in the file would say so.
        if "FrontPath" in blocks:
            fx, _fy, fz = pos("FrontPath")
            fs = box("FrontPath")
            if (abs(px - fx) < fs[0] / 2.0 + 0.25
                    and abs(pz - fz) < fs[2] / 2.0 + 0.25):
                fail(path, "%s at x %.2f stands in the front path" % (name, px))
    for i in range(len(posts)):
        for j in range(i + 1, len(posts)):
            a, b = pos(posts[i]), pos(posts[j])
            if abs(a[0] - b[0]) < 0.45 and abs(a[2] - b[2]) < 0.45:
                fail(path, "signal posts %s and %s are %.2f m apart; their heads "
                     "overlap" % (posts[i], posts[j], abs(a[0] - b[0])))

    # Heights. The backdrop under everything is a flat box, and if its top ends
    # up above the carriageway it hides the road, the zebra, the lines and the
    # drain all at once -- the street then renders as a lawn with a pavement
    # round it, with no error anywhere to say so.
    def top_of(name):
        return pos(name)[1] + box(name)[1] / 2.0

    if "GroundPlane" in blocks:
        ground = top_of("GroundPlane")
        buried = []
        for name, block in blocks.items():
            if name == "GroundPlane" or 'ExtResource("1_prop")' not in block:
                continue
            if not re.search(r"box_size = Vector3\(", block):
                continue
            surface = top_of(name)
            if surface > 0.3:
                continue                      # not a ground-level thing
            if surface <= ground:
                buried.append((name, surface))
        for name, surface in sorted(buried, key=lambda r: r[1]):
            fail(path, "%s has its surface at y %.3f, at or under the ground "
                 "plane at %.3f -- it is buried" % (name, surface, ground))
        if not buried:
            notes.append("street: ground plane at y %.3f, under every surface it backs"
                         % ground)

    if "Road" in blocks and "Pavement" in blocks:
        kerb = top_of("Pavement") - top_of("Road")
        if not 0.08 <= kerb <= 0.2:
            fail(path, "kerb is %.0f mm high (pavement %.3f, road %.3f); a real one "
                 "is 100-150" % (kerb * 1000, top_of("Pavement"), top_of("Road")))
        for name in blocks:
            if not (name.startswith("CrossingBar") or name.startswith("CentreLine")
                    or name.startswith("StopLine") or name.startswith("CrossingEdge")):
                continue
            proud = top_of(name) - top_of("Road")
            if proud <= 0.0 or proud > 0.05:
                fail(path, "%s sits %.0f mm relative to the road surface; markings "
                     "need to be just proud of it" % (name, proud * 1000))

    notes.append("street: %.0f m of road, %.1f m wide, zebra %.1f m, %d signal post(s), "
                 "%d car(s)"
                 % (box("Road")[0], road_d, half * 2,
                    sum(1 for b in blocks.values() if 'ExtResource("8_post")' in b),
                    sum(1 for b in blocks.values() if 'ExtResource("5_car")' in b)))


def check_slip_zones():
    """A SlipZone's warning volume must contain the footprint it scores.

    `extents` is the volume that starts watching and speaks the warning;
    `route_extents` is the smaller footprint that actually costs a near miss,
    plus `contact_margin`. The contact test only runs while the probe is inside
    the warning volume, so any part of the scored footprint sticking out beyond
    it can never fire -- and a scored volume as big as the warning volume is the
    original bug: being penalised for standing near a coffee table.
    """
    margin = 0.10
    for path in walk(".tscn"):
        txt = open(path, encoding="utf-8").read()
        m = re.search(r'path="res://scripts/world/slip_zone\.gd"\s+id="([^"]+)"', txt)
        if not m:
            continue
        for block in re.split(r"\n(?=\[node )", txt):
            if not block.startswith("[node ") or 'ExtResource("%s")' % m.group(1) not in block:
                continue
            name = re.match(r'\[node name="([^"]+)"', block).group(1)
            em = re.search(r"\nextents = Vector3\(([^)]*)\)", block)
            rm = re.search(r"\nroute_extents = Vector3\(([^)]*)\)", block)
            if em is None:
                continue
            e = [float(x) for x in em.group(1).split(",")]
            if rm is None:
                fail(path, "SlipZone %s has no route_extents, so the volume that "
                     "warns you is also the volume that penalises you" % name)
                continue
            r = [float(x) for x in rm.group(1).split(",")]
            for axis, i in (("x", 0), ("z", 2)):
                if r[i] + 2 * margin > e[i] + 1e-6:
                    fail(path, "SlipZone %s: scored footprint (%s %.2f + margin) is "
                         "wider than the warning volume (%.2f)"
                         % (name, axis, r[i], e[i]))
            if r[0] * r[2] >= e[0] * e[2] - 1e-6:
                fail(path, "SlipZone %s: the scored footprint is the whole warning "
                     "volume -- standing near it would count as standing on it" % name)
        notes.append("%s: slip zones warn wider than they score"
                     % os.path.basename(path))


def check_route_markers():
    """No two markers on one route may have overlapping trigger boxes.

    A marker arms when the one before it is reached, and because the
    participant may already be standing where it appears, it also fires on an
    overlap that is already there. If two boxes overlap, standing on ring N
    would therefore complete ring N+1 as well -- a leg scored clean without
    anyone moving a foot. The rings are 0.68 m across, so boxes much over that
    start to touch in a small room; this is the check that says so.
    """
    checked = 0
    for path in walk(".tscn"):
        txt = open(path, encoding="utf-8").read()
        m = re.search(r'path="res://scripts/world/route_marker\.gd"\s+id="([^"]+)"', txt)
        if not m:
            continue
        rid = m.group(1)
        markers = []
        for block in txt.split("[node ")[1:]:
            if 'ExtResource("%s")' % rid not in block:
                continue
            name = re.match(r'name="([^"]+)"', block).group(1)
            tr = re.search(r"transform = Transform3D\(([^)]*)\)", block)
            v = [float(x) for x in tr.group(1).split(",")] if tr else [0.0] * 12
            ex = re.search(r"extents = Vector3\(([^)]*)\)", block)
            e = [float(x) for x in ex.group(1).split(",")] if ex else [0.9, 2.0, 0.9]
            markers.append((name, v[9], v[11], e[0] / 2.0, e[2] / 2.0))
        if not markers:
            continue
        checked += 1
        for i in range(len(markers)):
            for j in range(i + 1, len(markers)):
                a, b = markers[i], markers[j]
                if (abs(a[1] - b[1]) < a[3] + b[3] - 0.001
                        and abs(a[2] - b[2]) < a[4] + b[4] - 0.001):
                    fail(path, "route markers %s and %s have overlapping trigger "
                         "boxes -- standing on one would complete the other"
                         % (a[0], b[0]))
        notes.append("%s: %d route markers, no overlapping triggers"
                     % (os.path.basename(path), len(markers)))
    if checked:
        notes.append("checked route marker spacing in %d scene(s)" % checked)


# ---------------------------------------------------------------------------
#  Rooms and scoring
# ---------------------------------------------------------------------------

def check_rooms(inventory):
    sm = os.path.join(ROOT, "scripts", "autoload", "session_manager.gd")
    if not os.path.exists(sm):
        return
    txt = open(sm, encoding="utf-8").read()
    m = re.search(r'const ROOM_ORDER: Array\[String\] = \[([^\]]+)\]', txt)
    if not m:
        return
    rooms = set(re.findall(r'"([a-z_]+)"', m.group(1)))
    notes.append("scoring knows %d rooms: %s" % (len(rooms), ", ".join(sorted(rooms))))
    for h in inventory["hazards"]:
        room = h.get("room", "").strip('"')
        if room and room not in rooms:
            fail(h["scene"], "hazard %s is in room %r, which the scoring does not know"
                 % (h.get("hazard_id", h["node"]), room))
    per_room = {}
    for h in inventory["hazards"]:
        if h.get("is_hazard", "true").startswith("f"):
            continue
        room = h.get("room", "").strip('"')
        per_room[room] = per_room.get(room, 0) + 1
    decoys = sum(1 for h in inventory["hazards"]
                 if h.get("is_hazard", "true").startswith("f"))
    notes.append("%d real hazards (%s) and %d decoys"
                 % (sum(per_room.values()),
                    ", ".join("%s %d" % kv for kv in sorted(per_room.items())), decoys))


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", action="store_true", help="print the gameplay inventory")
    ap.add_argument("--json", metavar="FILE", help="write the inventory as JSON, to diff later")
    args = ap.parse_args()

    inventory = {key: [] for key in INVENTORY_KEYS}
    scene_props = []

    n_scripts = check_scripts()
    check_gdscript_traps()
    check_private_calls()
    check_floating()
    check_room_guides()
    check_lighting()
    check_button_spacing()
    scenes = list(walk(".tscn"))
    for path in scenes:
        check_scene(path, inventory, scene_props)
        check_sub_resources(path)
    check_properties(scene_props, script_exports())
    check_surfaces()
    check_room_geometry()
    check_route_markers()
    check_hazard_volumes()
    check_slip_zones()
    check_street()
    check_rooms(inventory)

    print("checked %d scripts and %d scenes" % (n_scripts, len(scenes)))
    for n in notes:
        print("  - " + n)
    print("  - inventory: " + ", ".join(
        "%d %s" % (len(inventory[k]), k.replace("_", " "))
        for k in INVENTORY_KEYS if inventory[k]))

    if args.inventory:
        for key in INVENTORY_KEYS:
            if not inventory[key]:
                continue
            print("\n%s:" % key)
            for row in inventory[key]:
                label = row.get("hazard_id", row.get("zone_id", row.get("room", "")))
                print("   %-30s %-24s %s" % (row.get("node", ""), label.strip('"'), row["scene"]))

    if args.json:
        for key in inventory:
            inventory[key].sort(key=lambda r: (r["scene"], r.get("node", "")))
        with open(args.json, "w") as fh:
            json.dump(inventory, fh, indent=1, sort_keys=True)
        print("\ninventory written to %s" % args.json)

    if problems:
        print("\n%d PROBLEM(S):" % len(problems))
        for p in problems:
            print("  ! " + p)
        return 1
    print("\nno problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
