#!/usr/bin/env python3
"""Bake every PBR texture the house uses, from nothing but numpy.

Run from the project root:

    python3 tools/make_textures.py            # all of them (slow, ~3 min)
    python3 tools/make_textures.py oak_floor  # just one, while tweaking it

Writes assets/textures/<name>_albedo.png, _normal.png and _rough.png, plus a
manifest.json recording the physical size each texture represents so the
material library can work out its UV scale. Nothing here needs the network or a
downloaded asset pack: the point is a house that looks real on a machine that
cannot reach kenney.nl.

Every map is seamless. Albedo carries baked contact darkening in the grooves --
cheaper than a separate AO map and it reads the same at these distances.
"""

import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from texlib import (blur, cell_ids, edge_falloff, fbm, hexcolor, normal_map,  # noqa: E402
                    resize_gray, resize_rgb, ridged, save_gray, save_rgb,
                    tint, value_noise, worley)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")


# ---------------------------------------------------------------------------
#  Floors
# ---------------------------------------------------------------------------

def oak_floor(res):
    """Wide engineered-oak boards, satin lacquer. 8 boards over 2 m."""
    rows, segs = 8, 2
    ys = np.linspace(0.0, rows, res, endpoint=False, dtype=np.float32)
    xs = np.linspace(0.0, segs, res, endpoint=False, dtype=np.float32)
    V, U = np.meshgrid(ys, xs, indexing="ij")
    row = np.floor(V).astype(np.int32)

    rg = np.random.default_rng(7)
    phase = rg.random(rows).astype(np.float32)
    shade = rg.random(rows * segs).astype(np.float32)

    U = U + phase[row]
    seg = np.floor(U).astype(np.int32) % segs
    plank = (row * segs + seg) % (rows * segs)

    fu = U % 1.0
    fv = V % 1.0

    # Grain: long streaks plus a cathedral figure from a warped sine.
    warp = fbm(res, 3, 4, 21, aniso=0.08)
    streak = fbm(res, 6, 6, 33, aniso=0.05)
    figure = 0.5 + 0.5 * np.sin((fv * 3.0 + warp * 2.6) * np.pi * 2.0)
    grain = np.clip(streak * 0.62 + figure * 0.38, 0.0, 1.0)
    pores = np.clip(fbm(res, 90, 3, 44, aniso=0.15) - 0.55, 0.0, 1.0) * 2.2

    light = hexcolor("#c08a54")
    dark = hexcolor("#7d4f2a")
    col = light[None, None, :] * (1.0 - grain[..., None]) + dark[None, None, :] * grain[..., None]
    col *= (0.86 + 0.28 * shade[plank])[..., None]
    col *= (1.0 - pores * 0.35)[..., None]

    # Board joints: a chamfer either side of a narrow groove.
    gap_v = 1.0 - edge_falloff(fv, fv, 0.02)
    gap_u = np.clip(1.0 - np.minimum(fu, 1.0 - fu) / 0.012, 0.0, 1.0)
    groove = np.maximum(gap_v, gap_u)

    height = 0.62 + grain * 0.06 - pores * 0.10 - groove * 0.55
    col *= (1.0 - groove * 0.5)[..., None]

    rough = 0.30 + grain * 0.07 + pores * 0.30 + groove * 0.45
    rough += (fbm(res, 8, 3, 55) - 0.5) * 0.06
    return np.clip(col, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.4


def tile_floor(res):
    """Large marble-effect porcelain, 300 mm. Bathroom floor.

    The veining has to stay FAINT. Real marble-effect porcelain is a pale field
    with a few darker drifts through it; push the veins hard and it stops
    reading as a floor and starts reading as cracked ice.
    """
    n = 4
    u, v, col_i, row_i = cell_ids(res, n, n)
    inner = edge_falloff(u, v, 0.022)

    drift = fbm(res, 5, 4, 92)
    vein = ridged(res, 3, 4, 91)
    mottle = fbm(res, 40, 3, 94)

    face = 0.95 + (drift - 0.5) * 0.09 + (mottle - 0.5) * 0.04
    face -= np.clip(vein - 0.86, 0, 1) * 0.85
    stone = hexcolor("#e9e6e0")[None, None, :] * np.clip(face, 0, 1.05)[..., None]

    ids = (row_i * n + col_i).astype(np.int32)
    jitter = np.random.default_rng(93).random(n * n).astype(np.float32)
    stone *= (0.975 + 0.045 * jitter[ids])[..., None]

    grout = hexcolor("#8e8981")
    mask = inner[..., None]
    alb = stone * mask + grout[None, None, :] * (1.0 - mask)
    alb *= (1.0 - (1.0 - inner) * 0.16)[..., None]

    height = 0.4 + inner * 0.55
    rough = 0.10 + (1.0 - inner) * 0.74 + mottle * 0.03
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 1.4

def slate_floor(res):
    """Riven slate-effect tiles, 0.4 m. Kitchen and hallway."""
    n = 4
    u, v, col_i, row_i = cell_ids(res, n, n)
    inner = edge_falloff(u, v, 0.03)

    riven = fbm(res, 12, 6, 61)
    flake = ridged(res, 26, 4, 62)
    base = hexcolor("#4a4e52")
    warm = hexcolor("#6b6357")
    mix = np.clip(riven * 1.1 - 0.1, 0, 1)
    alb = base[None, None, :] * (1.0 - mix[..., None]) + warm[None, None, :] * mix[..., None]
    alb *= (0.8 + flake * 0.4)[..., None]

    ids = (row_i * n + col_i).astype(np.int32)
    jit = np.random.default_rng(63).random(n * n).astype(np.float32)
    alb *= (0.88 + 0.24 * jit[ids])[..., None]

    grout = hexcolor("#3a3d40")
    m = inner[..., None]
    alb = alb * m + grout[None, None, :] * (1.0 - m)
    alb *= (1.0 - (1.0 - inner) * 0.25)[..., None]

    height = 0.3 + inner * 0.5 + riven * 0.16 + flake * 0.06
    rough = 0.42 + riven * 0.2 + (1.0 - inner) * 0.3
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.0


def carpet(res):
    """Cut-pile carpet. Bedroom."""
    fine = fbm(res, 120, 3, 71)
    tuft = worley(res, 46, 72, 0.95)[0]
    tuft = np.clip(tuft * 1.5, 0, 1)
    drag = fbm(res, 10, 3, 73, aniso=0.3)

    base = hexcolor("#b6a893")
    alb = tint(base, fine * 0.5 + drag * 0.5, 0.16)
    alb *= (0.9 + (1.0 - tuft) * 0.2)[..., None]

    height = fine * 0.55 + (1.0 - tuft) * 0.45
    rough = 0.9 + fine * 0.08
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 3.2


def wool_rug(res):
    """Flat-weave wool rug: a crisp bordered field with a lozenge motif."""
    n = 5
    u, v, ci, ri = cell_ids(res, n, n)
    diamond = (np.abs(u - 0.5) + np.abs(v - 0.5)) * 2.0
    outline = np.clip((0.95 - np.abs(diamond - 0.72) / 0.10), 0, 1)
    fill = np.clip((0.66 - diamond) / 0.08, 0, 1)
    checker = ((ci + ri) % 2).astype(np.float32)

    uu = np.linspace(0, 1, res, endpoint=False, dtype=np.float32)
    Y, X = np.meshgrid(uu, uu, indexing="ij")
    edge_d = np.minimum(np.minimum(X, 1 - X), np.minimum(Y, 1 - Y))
    border = np.clip(edge_d / 0.05, 0, 1)
    stripe = np.clip(np.abs(edge_d - 0.085) / 0.012, 0, 1)

    field = hexcolor("#8f5043")
    accent = hexcolor("#ddc9a7")
    ink = hexcolor("#3c4148")

    alb = field[None, None, :].repeat(res, 0).repeat(res, 1)
    m = np.clip(fill * (0.35 + 0.65 * checker), 0, 1)[..., None]
    alb = alb * (1 - m) + accent[None, None, :] * m
    m2 = np.clip(outline, 0, 1)[..., None]
    alb = alb * (1 - m2) + ink[None, None, :] * m2
    alb = alb * border[..., None] + ink[None, None, :] * (1 - border[..., None])
    alb = alb * stripe[..., None] + accent[None, None, :] * (1 - stripe[..., None])

    weave = fbm(res, 170, 2, 81, aniso=0.6)
    alb *= (0.88 + weave * 0.24)[..., None]

    height = weave * 0.7 + border * 0.18 + fill * 0.12
    rough = 0.88 + weave * 0.1
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.2

def plaster_wall(res):
    """Painted skim plaster with a faint orange-peel roll. Most walls."""
    peel = fbm(res, 48, 4, 101)
    broad = fbm(res, 5, 3, 102)
    alb = tint(hexcolor("#e4ded2"), broad * 0.65 + peel * 0.35, 0.045)
    height = peel * 0.6 + broad * 0.4
    rough = 0.86 + peel * 0.09 + (broad - 0.5) * 0.04
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 0.45


def ceiling_plaster(res):
    """Flat white ceiling: finer, brighter, matter."""
    peel = fbm(res, 70, 3, 111)
    alb = tint(hexcolor("#f2f0ea"), peel, 0.03)
    return np.clip(alb, 0, 1), peel * 0.5, np.clip(0.93 + peel * 0.05, 0, 1), 0.3


def wallpaper(res):
    """Sage-green paper, narrow stripe with a soft damask. Living room."""
    uu = np.linspace(0, 12, res, endpoint=False, dtype=np.float32)
    stripe = 0.5 + 0.5 * np.sin(uu * np.pi * 2.0)
    stripe = np.tile(stripe[None, :], (res, 1))

    u, v, ci, ri = cell_ids(res, 3, 4, stagger=0.5)
    r = np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2)
    damask = np.clip(1.0 - r / 0.33, 0, 1) ** 0.6
    damask *= 0.5 + 0.5 * np.sin(np.arctan2(v - 0.5, u - 0.5) * 6.0)
    damask = blur(np.clip(damask, 0, 1), 1, 1)

    base = hexcolor("#c3cbb8")
    light = hexcolor("#d7ddcd")
    alb = base[None, None, :] * (1 - stripe[..., None] * 0.55) + light[None, None, :] * (stripe[..., None] * 0.55)
    alb *= (1.0 - damask * 0.12)[..., None]
    tooth = fbm(res, 130, 2, 121)
    alb *= (0.96 + tooth * 0.08)[..., None]

    height = tooth * 0.5 + damask * 0.35 + stripe * 0.1
    rough = 0.84 + tooth * 0.1 - damask * 0.05
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 0.6


def subway_tile(res):
    """Glazed 200 x 100 mm brick-bond wall tile. Bathroom and splashback."""
    nx, ny = 4, 8
    u, v, ci, ri = cell_ids(res, nx, ny, stagger=0.5)
    inner = edge_falloff(u, v, 0.05)

    glaze = fbm(res, 6, 3, 131)
    ids = (ri * nx + ci).astype(np.int32)
    jit = np.random.default_rng(132).random(nx * ny).astype(np.float32)
    face = hexcolor("#f4f2ec")[None, None, :] * (0.95 + glaze[..., None] * 0.08)
    face = face * (0.97 + 0.06 * jit[ids])[..., None]

    grout = hexcolor("#c4bdb1")
    m = inner[..., None]
    alb = face * m + grout[None, None, :] * (1 - m)
    alb *= (1.0 - (1.0 - inner) * 0.2)[..., None]

    pillow = 1.0 - (1.0 - inner) ** 1.6
    height = 0.3 + inner * 0.55 + pillow * 0.08
    rough = 0.09 + (1.0 - inner) * 0.78 + glaze * 0.04
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 1.1


def brick(res):
    """Stock brick, running bond, struck mortar. Exterior."""
    nx, ny = 4, 12
    u, v, ci, ri = cell_ids(res, nx, ny, stagger=0.5)
    inner = edge_falloff(u, v, 0.06)

    grit = fbm(res, 40, 4, 141)
    blotch = fbm(res, 8, 3, 142)
    ids = (ri * nx + ci).astype(np.int32)
    jit = np.random.default_rng(143).random(nx * ny * 2).astype(np.float32)

    warm = hexcolor("#9c5340")
    cool = hexcolor("#6f4438")
    face = warm[None, None, :] * (1 - blotch[..., None] * 0.5) + cool[None, None, :] * (blotch[..., None] * 0.5)
    face *= (0.84 + 0.32 * jit[ids])[..., None]
    face *= (0.85 + grit * 0.3)[..., None]

    mortar = hexcolor("#b8b3a6")[None, None, :] * (0.85 + fbm(res, 60, 3, 144)[..., None] * 0.3)
    m = inner[..., None]
    alb = face * m + mortar * (1 - m)
    alb *= (1.0 - (1.0 - inner) * 0.3)[..., None]

    height = 0.25 + inner * 0.62 + grit * 0.12
    rough = 0.72 + grit * 0.18 + (1.0 - inner) * 0.1
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.6


def exterior_render(res):
    """Painted sand-and-cement render. Exterior walls."""
    sand = fbm(res, 90, 4, 151)
    broad = fbm(res, 4, 3, 152)
    alb = tint(hexcolor("#d9d2c4"), sand * 0.6 + broad * 0.4, 0.07)
    alb *= (1.0 - np.clip(broad - 0.72, 0, 1) * 0.5)[..., None]
    height = sand * 0.7 + broad * 0.3
    rough = 0.9 + sand * 0.07
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 1.2


# ---------------------------------------------------------------------------
#  Outside
# ---------------------------------------------------------------------------

def paving(res):
    """Cast concrete paving slabs, 600 mm, with aggregate and weathering."""
    n = 3
    u, v, ci, ri = cell_ids(res, n, n)
    inner = edge_falloff(u, v, 0.028)

    agg = worley(res, 60, 161, 0.95)[0]
    agg = np.clip(agg * 1.4, 0, 1)
    grit = fbm(res, 70, 4, 162)
    stain = fbm(res, 5, 4, 163)

    base = hexcolor("#b4b1a9")
    alb = tint(base, grit * 0.5 + agg * 0.5, 0.11)
    alb *= (1.0 - np.clip(stain - 0.6, 0, 1) * 0.55)[..., None]
    ids = (ri * n + ci).astype(np.int32)
    jit = np.random.default_rng(164).random(n * n).astype(np.float32)
    alb *= (0.92 + 0.15 * jit[ids])[..., None]

    joint = hexcolor("#6d6a63")
    m = inner[..., None]
    alb = alb * m + joint[None, None, :] * (1 - m)
    alb *= (1.0 - (1.0 - inner) * 0.35)[..., None]

    height = 0.3 + inner * 0.55 + grit * 0.1 + (1.0 - agg) * 0.08
    rough = 0.8 + grit * 0.15 + (1.0 - inner) * 0.1
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.2


def asphalt(res):
    """Worn bitmac: chippings, a little polish in the wheel tracks."""
    chip = worley(res, 80, 171, 1.0)[0]
    chip = np.clip(chip * 1.6, 0, 1)
    grit = fbm(res, 110, 4, 172)
    patch = fbm(res, 4, 3, 173)

    alb = tint(hexcolor("#3b3b3d"), grit * 0.6 + chip * 0.4, 0.35)
    alb *= (0.9 + patch * 0.2)[..., None]

    height = (1.0 - chip) * 0.6 + grit * 0.4
    rough = 0.82 + grit * 0.14 - np.clip(patch - 0.6, 0, 1) * 0.5
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.6


def grass(res):
    """Mown lawn from above: fine blades, soft clumping, a few thin patches.

    Higher blade frequency and more octaves on the clumping; at low frequency
    the value-noise lattice shows through as squares.
    """
    blades = fbm(res, 220, 4, 181, aniso=0.5)
    fibre = fbm(res, 90, 3, 184, aniso=0.35)
    clump = fbm(res, 18, 5, 182)
    bare = np.clip(fbm(res, 8, 4, 183) - 0.70, 0, 1) * 3.0

    deep = hexcolor("#4c6b34")
    pale = hexcolor("#7d9349")
    dirt = hexcolor("#6d5f45")
    alb = deep[None, None, :] * (1 - clump[..., None]) + pale[None, None, :] * clump[..., None]
    alb *= (0.82 + blades * 0.24 + fibre * 0.14)[..., None]
    b = np.clip(bare, 0, 1)[..., None]
    alb = alb * (1 - b) + dirt[None, None, :] * b

    height = blades * 0.6 + fibre * 0.25 + clump * 0.15
    rough = 0.9 + blades * 0.08
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 3.0

def roof_tile(res):
    """Concrete interlocking roof tiles, seen from above and from the street."""
    nx, ny = 6, 10
    u, v, col_i, row_i = cell_ids(res, nx, ny, stagger=0.5)
    # Each course laps over the one below it, so the strong shadow line at the
    # head of every tile is what reads as a roof from the far pavement.
    head = np.clip((v - 0.78) / 0.22, 0, 1)
    side = np.clip(1.0 - np.minimum(u, 1.0 - u) / 0.06, 0, 1)
    grit = fbm(res, 60, 4, 301)
    moss = np.clip(fbm(res, 9, 3, 302) - 0.62, 0, 1) * 2.6

    base = hexcolor("#6b5a52")
    shadow = hexcolor("#3e3531")
    lichen = hexcolor("#5c6b43")
    ids = (row_i * nx + col_i).astype(np.int32)
    jit = np.random.default_rng(303).random(nx * ny).astype(np.float32)

    alb = base[None, None, :] * (0.85 + grit[..., None] * 0.3)
    alb *= (0.9 + 0.2 * jit[ids])[..., None]
    m = np.clip(moss, 0, 1)[..., None]
    alb = alb * (1 - m * 0.7) + lichen[None, None, :] * (m * 0.7)
    shade = np.maximum(head, side)
    alb = alb * (1 - shade[..., None]) + shadow[None, None, :] * shade[..., None]

    height = 0.35 + (1.0 - head) * 0.45 + (1.0 - side) * 0.12 + grit * 0.08
    rough = 0.82 + grit * 0.14
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.4


# ---------------------------------------------------------------------------
#  Furniture surfaces
# ---------------------------------------------------------------------------

def _wood(res, light_hex, dark_hex, seed, ring_freq, rough_base):
    warp = fbm(res, 4, 4, seed, aniso=0.07)
    streak = fbm(res, 9, 6, seed + 1, aniso=0.04)
    rings = 0.5 + 0.5 * np.sin((np.linspace(0, ring_freq, res, endpoint=False,
                                            dtype=np.float32)[:, None] + warp * 3.0) * np.pi * 2.0)
    grain = np.clip(streak * 0.55 + rings * 0.45, 0, 1)
    pores = np.clip(fbm(res, 120, 3, seed + 2, aniso=0.12) - 0.58, 0, 1) * 2.4

    light = hexcolor(light_hex)
    dark = hexcolor(dark_hex)
    alb = light[None, None, :] * (1 - grain[..., None]) + dark[None, None, :] * grain[..., None]
    alb *= (1.0 - pores * 0.3)[..., None]

    height = 0.5 + grain * 0.12 - pores * 0.35
    rough = rough_base + grain * 0.06 + pores * 0.25
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0)


def oak_wood(res):
    """Mid oak, satin lacquer: doors, skirtings, tables."""
    a, h, r = _wood(res, "#c39a68", "#8a6234", 201, 5.0, 0.36)
    return a, h, r, 1.6


def walnut_wood(res):
    """Dark walnut with ribbon figure: wardrobes, sideboards."""
    a, h, r = _wood(res, "#6b4a33", "#3a2519", 211, 7.0, 0.30)
    return a, h, r, 1.4


def paint_satin(res):
    """Brilliant-white satin on MDF: cabinet doors, architraves, skirting."""
    brush = fbm(res, 30, 3, 221, aniso=0.12)
    dust = fbm(res, 140, 2, 222)
    alb = tint(hexcolor("#f3f1ec"), brush * 0.6 + dust * 0.4, 0.025)
    height = brush * 0.6 + dust * 0.4
    rough = 0.33 + brush * 0.06 + dust * 0.04
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 0.6


def upholstery(res):
    """Woven twill: sofa, dining chairs."""
    n = 64
    u, v, ci, ri = cell_ids(res, n, n)
    over = ((ci + ri) % 2).astype(np.float32)
    thread = np.where(over > 0.5, np.sin(u * np.pi), np.sin(v * np.pi)) ** 0.7
    slub = fbm(res, 40, 3, 231)
    broad = fbm(res, 6, 3, 232)

    alb = tint(hexcolor("#6a7480"), broad * 0.5 + slub * 0.5, 0.12)
    alb *= (0.8 + thread * 0.3)[..., None]

    height = thread * 0.7 + slub * 0.3
    rough = 0.9 + slub * 0.07
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 2.2


def linen(res):
    """Washed linen: bedding, curtains."""
    n = 80
    u, v, ci, ri = cell_ids(res, n, n)
    weave = (np.sin(u * np.pi) + np.sin(v * np.pi)) * 0.5
    creases = ridged(res, 7, 4, 241, aniso=0.6)
    slub = fbm(res, 55, 3, 242, aniso=2.0)

    alb = tint(hexcolor("#e8e2d6"), weave * 0.4 + slub * 0.6, 0.07)
    alb *= (1.0 - np.clip(creases - 0.7, 0, 1) * 0.35)[..., None]

    height = weave * 0.45 + slub * 0.25 + creases * 0.3
    rough = 0.88 + slub * 0.08
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 1.8


def leather(res):
    """Pebble-grain leather: the good armchair.

    Bigger cells and a lighter tan -- small dark cells read as a rash rather
    than as hide.
    """
    f1, f2 = worley(res, 17, 251, 0.85)
    crease = np.clip((f2 - f1) * 3.2, 0, 1)
    pebble = 1.0 - np.clip(f1 * 1.45, 0, 1)
    pore = fbm(res, 85, 2, 252)

    alb = tint(hexcolor("#8d5f44"), pebble * 0.5 + pore * 0.5, 0.10)
    alb *= (1.0 - (1.0 - crease) * 0.26)[..., None]

    height = crease * 0.55 + pebble * 0.35 + pore * 0.1
    rough = 0.42 + (1.0 - crease) * 0.24 + pore * 0.06
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 1.6

def quartz(res):
    """Engineered quartz worktop: pale, lightly flecked, polished.

    Sparse is the whole point -- dense flecking reads as concrete.
    """
    speck = worley(res, 34, 261, 1.0)[0]
    fleck = np.clip(1.15 - speck * 2.4, 0, 1)
    fine = fbm(res, 70, 3, 263)

    alb = tint(hexcolor("#e7e4dd"), fine, 0.025)
    alb *= (1.0 - fleck * 0.22)[..., None]

    height = fine * 0.5 + fleck * 0.5
    rough = 0.10 + fine * 0.03 + fleck * 0.05
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 0.35

def brushed_metal(res):
    """Brushed stainless: taps, grab rails, appliance fronts."""
    streak = fbm(res, 8, 5, 271, aniso=0.02)
    fine = fbm(res, 200, 2, 272, aniso=0.02)
    alb = tint(hexcolor("#b9bcc0"), streak * 0.6 + fine * 0.4, 0.10)
    height = streak * 0.5 + fine * 0.5
    rough = 0.26 + streak * 0.14 + fine * 0.06
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.05, 1.0), 0.9


def cast_iron(res):
    """Weathered ductile iron: the gully frame and the grating lifted out of it.

    Not stainless. The drain ironwork was sharing `steel_dark` with the taps,
    which is bright, smooth and 85 % metallic -- so a gully grating rendered as
    a mirror lying on the path, which is a large part of why it read as a dark
    tile rather than as a casting.

    A sand casting is the opposite of a tap: a rough, slightly uneven skin with
    pin holes from the mould, a scatter of rust bloom where the paint has gone,
    and polish only on the high spots where feet have been over it.
    """
    skin = fbm(res, 10, 5, 431)                 # the cast surface itself
    pits = fbm(res, 90, 2, 432)                 # mould pin holes
    bloom = fbm(res, 4, 4, 433)                 # patches of rust

    alb = tint(hexcolor("#55524e"), skin * 0.7 + pits * 0.3, 0.16)
    # Rust only in the low, damp patches, and never over the whole face.
    rust = np.clip((bloom - 0.62) * 3.0, 0.0, 1.0) * (1.0 - skin * 0.5)
    alb = alb * (1.0 - rust[..., None]) + hexcolor("#7a4a2c") * rust[..., None]

    deep = np.clip((0.34 - pits) * 3.0, 0.0, 1.0)
    height = skin * 0.72 + (1.0 - deep) * 0.28
    # Rough where it is rusty or pitted, polished on the worn high spots.
    rough = 0.42 + rust * 0.34 + deep * 0.12 - np.clip(skin - 0.68, 0, 1) * 0.5
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.16, 1.0), 1.6


def water(res):
    """A few millimetres of still water: the spill on the kitchen tile, the wet
    patch in the bathroom.

    Water has almost no colour of its own at this depth. A puddle is a mirror
    and a lens: what you see is the floor underneath it and the ceiling above
    it, which is why the albedo here is very nearly white and very nearly flat.

    What this set actually carries is the SURFACE -- a slow swell crossed by
    finer ripples -- and a roughness that lifts slightly on the slopes. That
    last part is what makes a highlight break into glints instead of lying
    across the puddle as one flat grey sheet, which is exactly how the old
    pale-blue slab read.
    """
    # Not fbm. Noise gives a stucco surface -- the first attempt at this looked
    # like wet sandpaper -- because water is not random: it is a few smooth wave
    # trains interfering. Integer wave numbers keep every train seamless across
    # the tile, and a little noise stops the interference pattern repeating
    # visibly.
    theta = np.linspace(0.0, 2.0 * np.pi, res, endpoint=False, dtype=np.float32)
    V, U = np.meshgrid(theta, theta, indexing="ij")
    rg = np.random.default_rng(811)
    height = np.zeros((res, res), dtype=np.float32)
    # Directions spread round the circle, or the trains line up and the result
    # is corduroy rather than water. The warp makes the bands wander, which is
    # what stops a puddle looking like a diffraction grating.
    warp_u = (fbm(res, 3, 3, 815) - 0.5) * 1.6
    warp_v = (fbm(res, 3, 3, 816) - 0.5) * 1.6
    for kx, kz, amp in ((1, 2, 1.00), (-2, 1, 0.90), (3, 1, 0.55), (1, -4, 0.45),
                        (-5, 2, 0.30), (4, 5, 0.22), (-3, -6, 0.16), (7, -2, 0.12)):
        height += amp * np.sin(kx * (U + warp_u) + kz * (V + warp_v)
                               + float(rg.random()) * 6.2832)
    height = (height - height.min()) / max(float(np.ptp(height)), 1e-6)

    alb = tint(hexcolor("#eef3f5"), height, 0.035)
    slope = 1.0 - np.abs(height - 0.5) * 2.0
    rough = 0.015 + slope * 0.045
    # A smooth height field has a tiny gradient, so the normal strength that
    # suits brick or carpet leaves this one perfectly flat -- the first bake
    # came out as a single lilac square. The surface is the whole point of a
    # water texture, so it is baked strong here and dialled back at runtime
    # with the material's normal_scale.
    return np.clip(alb, 0, 1), height, np.clip(rough, 0.01, 0.2), 9.0


# ---------------------------------------------------------------------------
#  Registry
# ---------------------------------------------------------------------------
#  name: (recipe, albedo resolution, metres the texture spans)

SPECS = {
    "oak_floor":       (oak_floor, 1024, 2.0),
    "tile_floor":      (tile_floor, 1024, 1.2),
    "slate_floor":     (slate_floor, 1024, 1.6),
    "carpet":          (carpet, 512, 1.0),
    "wool_rug":        (wool_rug, 1024, 2.4),
    "plaster_wall":    (plaster_wall, 1024, 2.5),
    "ceiling_plaster": (ceiling_plaster, 512, 2.5),
    "wallpaper":       (wallpaper, 1024, 1.6),
    "subway_tile":     (subway_tile, 512, 0.8),
    "brick":           (brick, 1024, 1.6),
    "exterior_render": (exterior_render, 512, 2.5),
    "roof_tile":       (roof_tile, 1024, 1.4),
    "paving":          (paving, 1024, 1.8),
    "asphalt":         (asphalt, 1024, 2.0),
    "grass":           (grass, 512, 1.5),
    "oak_wood":        (oak_wood, 512, 1.0),
    "walnut_wood":     (walnut_wood, 512, 1.0),
    "paint_satin":     (paint_satin, 512, 1.0),
    "upholstery":      (upholstery, 512, 0.5),
    "linen":           (linen, 512, 0.6),
    "leather":         (leather, 512, 0.6),
    "quartz":          (quartz, 512, 1.2),
    "brushed_metal":   (brushed_metal, 512, 0.5),
    "cast_iron":       (cast_iron, 512, 0.45),
    "water":           (water, 512, 0.55),
}


# ---------------------------------------------------------------------------
#  Extras: single images that are not PBR sets
# ---------------------------------------------------------------------------
#  The red man and the green man. White figure on black, used as BOTH the albedo
#  and the emission map of the lamp face, so the black is the unlit housing and
#  the figure is what glows. That avoids needing alpha, and it means one texture
#  works for either colour -- the material tints it.

def _disc(Y, X, cy, cx, r):
    return (Y - cy) ** 2 + (X - cx) ** 2 <= r * r


def _limb(Y, X, p0, p1, r):
    """Capsule from p0 to p1, both (y, x) in pixels."""
    y0, x0 = p0
    y1, x1 = p1
    dy, dx = y1 - y0, x1 - x0
    length = max(dy * dy + dx * dx, 1e-6)
    t = np.clip(((Y - y0) * dy + (X - x0) * dx) / length, 0.0, 1.0)
    return (Y - (y0 + t * dy)) ** 2 + (X - (x0 + t * dx)) ** 2 <= r * r


def _figure(parts, res=128, ss=4):
    """Draw at `ss` times the size and average down, for a clean edge."""
    big = res * ss
    ys = np.arange(big, dtype=np.float32)
    Y, X = np.meshgrid(ys, ys, indexing="ij")
    mask = np.zeros((big, big), dtype=bool)
    for part in parts:
        if part[0] == "disc":
            mask |= _disc(Y, X, part[1] * ss, part[2] * ss, part[3] * ss)
        else:
            mask |= _limb(Y, X, (part[1][0] * ss, part[1][1] * ss),
                          (part[2][0] * ss, part[2][1] * ss), part[3] * ss)
    out = mask.astype(np.float32).reshape(res, ss, res, ss).mean(axis=(1, 3))
    return out


def signal_stand(res=128):
    """The red man: standing still, feet together, arms down."""
    return _figure([
        ("disc", 30, 64, 13),
        ("limb", (48, 64), (74, 64), 12),
        ("limb", (74, 62), (104, 56), 7),
        ("limb", (74, 66), (104, 72), 7),
        ("limb", (54, 56), (78, 48), 6),
        ("limb", (54, 72), (78, 80), 6),
    ], res)


def signal_walk(res=128):
    """The green man: mid-stride, leaning forward, arms swinging."""
    return _figure([
        ("disc", 28, 58, 13),
        ("limb", (46, 60), (72, 66), 12),
        ("limb", (72, 66), (101, 86), 7),
        ("limb", (72, 64), (104, 44), 7),
        ("limb", (52, 58), (74, 38), 6),
        ("limb", (52, 64), (71, 84), 6),
    ], res)


EXTRAS = {
    "signal_stand": signal_stand,
    "signal_walk": signal_walk,
}


def bake_extra(name):
    img = EXTRAS[name](128)
    save_gray(img, os.path.join(OUT, "%s.png" % name))
    print("  %-18s  128px  (figure)" % name)


def bake(name):
    fn, res, metres = SPECS[name]
    t0 = time.time()
    albedo, height, rough, nstrength = fn(res)

    save_rgb(albedo, os.path.join(OUT, "%s_albedo.png" % name))
    nrm = normal_map(height, nstrength)
    nres = res if res <= 512 else res // 2
    if nres != res:
        nrm = resize_rgb(nrm, nres)
    save_rgb(nrm, os.path.join(OUT, "%s_normal.png" % name))
    save_gray(resize_gray(rough, max(256, res // 4)),
              os.path.join(OUT, "%s_rough.png" % name))

    print("  %-18s %4dpx  %4.1f m  %5.1fs" % (name, res, metres, time.time() - t0))
    return {"resolution": res, "metres": metres, "normal_strength": nstrength}


def main():
    os.makedirs(OUT, exist_ok=True)
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")]
    names = [w for w in wanted if w not in EXTRAS] if wanted else list(SPECS)
    for w in wanted:
        if w in EXTRAS:
            os.makedirs(OUT, exist_ok=True)
            bake_extra(w)
    for n in names:
        if n in EXTRAS:
            continue
        if n not in SPECS:
            raise SystemExit("unknown texture %r; known: %s"
                             % (n, ", ".join(list(SPECS) + list(EXTRAS))))

    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as fh:
            manifest = json.load(fh)

    print("baking %d texture set(s) into assets/textures/" % len(names))
    for n in names:
        manifest[n] = bake(n)
    if not wanted:
        for n in EXTRAS:
            bake_extra(n)

    with open(manifest_path, "w") as fh:
        json.dump(dict(sorted(manifest.items())), fh, indent=2)
    print("manifest: %d entries" % len(manifest))


if __name__ == "__main__":
    main()
