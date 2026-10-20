#!/usr/bin/env python3
"""Noise, normal-map and image helpers for make_textures.py.

No external assets, no network: every map in assets/textures/ is baked from
these functions. Kept separate from the recipes so the recipes stay readable.

Conventions
    height      float array, 0..1, 1 = proud of the surface
    albedo      float array (h, w, 3), 0..1, linear-ish sRGB values
    roughness   float array, 0..1, absolute (the material sets roughness = 1.0
                and lets the texture carry the real value)
    normal      OpenGL / Y+ convention (green channel points up the texture),
                which is what Godot's StandardMaterial3D expects.

Every noise function is SEAMLESS: the lattice is periodic over the output, so
a texture tiles without a visible join. That matters more than resolution here
-- a 2 m floor plank texture is repeated twelve times down the hallway.
"""

import numpy as np
from PIL import Image

_rng = np.random.default_rng


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(res, fx, fy, seed):
    """Seamless bilinear value noise from an fy x fx periodic lattice."""
    fx = max(1, int(fx))
    fy = max(1, int(fy))
    g = _rng(seed).random((fy, fx)).astype(np.float32)

    xs = np.linspace(0.0, fx, res, endpoint=False, dtype=np.float32)
    ys = np.linspace(0.0, fy, res, endpoint=False, dtype=np.float32)
    x0 = np.floor(xs).astype(np.int32) % fx
    y0 = np.floor(ys).astype(np.int32) % fy
    x1 = (x0 + 1) % fx
    y1 = (y0 + 1) % fy
    tx = _smooth(xs - np.floor(xs))[None, :]
    ty = _smooth(ys - np.floor(ys))[:, None]

    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    return (a * (1 - tx) * (1 - ty) + b * tx * (1 - ty)
            + c * (1 - tx) * ty + d * tx * ty)


def fbm(res, freq, octaves=5, seed=0, gain=0.5, lac=2.0, aniso=1.0):
    """Fractal sum of value noise.

    aniso > 1 stretches features along the V axis, which is how wood grain and
    brushed metal get their direction.
    """
    total = np.zeros((res, res), np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        f = freq * (lac ** o)
        total += amp * value_noise(res, round(f), max(1, round(f / aniso)), seed + o * 1013)
        norm += amp
        amp *= gain
    return total / max(norm, 1e-6)


def ridged(res, freq, octaves=4, seed=0, aniso=1.0):
    """Sharp-crested noise: good for veins and torn edges."""
    n = fbm(res, freq, octaves, seed, aniso=aniso)
    return 1.0 - np.abs(n * 2.0 - 1.0)


def worley(res, cells, seed, jitter=0.9):
    """Seamless Worley noise. Returns (f1, f2) distances in cell units."""
    cells = max(2, int(cells))
    r = _rng(seed)
    base = np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij"), -1)
    pts = base.astype(np.float32) + 0.5 + (r.random((cells, cells, 2)).astype(np.float32) - 0.5) * jitter

    u = np.linspace(0.0, cells, res, endpoint=False, dtype=np.float32)
    Y, X = np.meshgrid(u, u, indexing="ij")
    ci = np.floor(Y).astype(np.int32)
    cj = np.floor(X).astype(np.int32)

    dists = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            iy = ci + dy
            ix = cj + dx
            wy = iy % cells
            wx = ix % cells
            p = pts[wy, wx]
            py = p[..., 0] - wy + iy
            px = p[..., 1] - wx + ix
            dists.append(np.sqrt((py - Y) ** 2 + (px - X) ** 2))
    stack = np.sort(np.stack(dists, 0), axis=0)
    return stack[0], stack[1]


def blur(a, radius=1, passes=1):
    """Cheap wrap-around box blur."""
    out = a.astype(np.float32)
    for _ in range(passes):
        acc = np.zeros_like(out)
        n = 0
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                acc += np.roll(np.roll(out, dy, 0), dx, 1)
                n += 1
        out = acc / n
    return out


def normal_map(height, strength=1.0):
    """Height -> OpenGL (Y+) tangent-space normal, as 0..1 RGB."""
    h = height.astype(np.float32)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    n = np.dstack([nx, ny, nz])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def tint(base, variation, amount):
    """Multiply an RGB triple by a scalar field, keeping it in gamut."""
    rgb = np.asarray(base, np.float32).reshape(1, 1, 3)
    return np.clip(rgb * (1.0 + (variation - 0.5) * 2.0 * amount)[..., None], 0.0, 1.0)


def hexcolor(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def stripes(res, count, axis=0, duty=0.5, phase=0.0):
    """Periodic 0/1 bands, seamless when `count` is an integer."""
    t = np.linspace(0.0, count, res, endpoint=False, dtype=np.float32) + phase
    band = ((t % 1.0) < duty).astype(np.float32)
    return np.tile(band[:, None], (1, res)) if axis == 0 else np.tile(band[None, :], (res, 1))


def cell_ids(res, nx, ny, stagger=0.0):
    """Brick/tile layout.

    Returns (u, v, col, row): u and v run 0..1 inside each cell, col and row are
    integer cell indices. `stagger` offsets every other row along U, which is
    what turns a grid of tiles into a running bond.
    """
    ys = np.linspace(0.0, ny, res, endpoint=False, dtype=np.float32)
    xs = np.linspace(0.0, nx, res, endpoint=False, dtype=np.float32)
    V, U = np.meshgrid(ys, xs, indexing="ij")
    row = np.floor(V).astype(np.int32)
    U = U + (row % 2) * stagger
    col = np.floor(U).astype(np.int32) % nx
    return U % 1.0, V % 1.0, col, row % ny


def edge_falloff(u, v, width):
    """1 in the middle of a cell, 0 at its border: the grout/mortar mask."""
    du = np.minimum(u, 1.0 - u)
    dv = np.minimum(v, 1.0 - v)
    d = np.minimum(du, dv)
    return np.clip(d / max(width, 1e-5), 0.0, 1.0)


def save_rgb(a, path):
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB").save(
        path, optimize=True)


def save_gray(a, path):
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "L").save(
        path, optimize=True)


def resize_gray(a, res):
    img = Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "L")
    return np.asarray(img.resize((res, res), Image.LANCZOS), np.float32) / 255.0


def resize_rgb(a, res):
    img = Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    return np.asarray(img.resize((res, res), Image.LANCZOS), np.float32) / 255.0
