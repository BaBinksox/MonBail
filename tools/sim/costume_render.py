#!/usr/bin/env python3
"""
Rendu de contrôle des tenues fabriquées (sortie de costume_dump.luau).

Usage : costume_render.py dump.txt dossier_sortie
Produit un PNG par tenue (face, trois-quarts, profil, dos) et une planche comparative.
Projection orthographique, tri des faces du plus loin au plus proche, ombrage simple.
Les corps sont des blocs R15 standard (les corps Roblox réels sont arrondis) : c'est un contrôle
de proportions et de placement, pas un rendu final.
"""
import json, sys, math, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

dump_path, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(out_dir, exist_ok=True)

figures = []
for line in open(dump_path, encoding="utf-8"):
    if line.startswith("FIG "):
        figures.append(json.loads(line[4:]))

LIGHT = np.array([-0.4, 0.8, -0.45])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def unit_box():
    c = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], dtype=float) * 0.5
    idx = lambda x, y, z: ((x > 0) * 4 + (y > 0) * 2 + (z > 0) * 1)
    faces = [
        [idx(-1, -1, -1), idx(1, -1, -1), idx(1, 1, -1), idx(-1, 1, -1)],  # -Z (devant)
        [idx(-1, -1, 1), idx(-1, 1, 1), idx(1, 1, 1), idx(1, -1, 1)],  # +Z
        [idx(-1, -1, -1), idx(-1, 1, -1), idx(-1, 1, 1), idx(-1, -1, 1)],  # -X
        [idx(1, -1, -1), idx(1, -1, 1), idx(1, 1, 1), idx(1, 1, -1)],  # +X
        [idx(-1, 1, -1), idx(1, 1, -1), idx(1, 1, 1), idx(-1, 1, 1)],  # +Y
        [idx(-1, -1, -1), idx(-1, -1, 1), idx(1, -1, 1), idx(1, -1, -1)],  # -Y
    ]
    return c, faces


def unit_wedge():
    # Coin Roblox : base pleine (y-), face verticale à l'arrière (z+), pente vers l'avant (z-).
    v = np.array([
        [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5],
        [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5],
    ])
    faces = [[0, 3, 2, 1], [3, 5, 4, 2], [0, 1, 4, 5], [0, 5, 3], [1, 2, 4]]
    return v, faces


def unit_sphere(nu=12, nv=8):
    verts, faces = [], []
    for i in range(nv + 1):
        th = math.pi * i / nv
        for j in range(nu):
            ph = 2 * math.pi * j / nu
            verts.append([0.5 * math.sin(th) * math.cos(ph), 0.5 * math.cos(th), 0.5 * math.sin(th) * math.sin(ph)])
    for i in range(nv):
        for j in range(nu):
            a = i * nu + j
            b = i * nu + (j + 1) % nu
            c = (i + 1) * nu + (j + 1) % nu
            d = (i + 1) * nu + j
            faces.append([a, b, c, d])
    return np.array(verts), faces


def unit_cylinder(n=14):
    # Axe X (comme Roblox).
    verts = []
    for j in range(n):
        ph = 2 * math.pi * j / n
        verts.append([-0.5, 0.5 * math.cos(ph), 0.5 * math.sin(ph)])
    for j in range(n):
        ph = 2 * math.pi * j / n
        verts.append([0.5, 0.5 * math.cos(ph), 0.5 * math.sin(ph)])
    faces = [[j, (j + 1) % n, n + (j + 1) % n, n + j] for j in range(n)]
    faces.append(list(range(n))[::-1])
    faces.append(list(range(n, 2 * n)))
    return np.array(verts), faces


SHAPES = {"block": unit_box(), "wedge": unit_wedge(), "ellipsoid": unit_sphere(), "cylinder": unit_cylinder()}


def polygons(part):
    shape = part["s"]
    size = np.array(part["size"])
    if shape == "head":
        verts, faces = unit_sphere(14, 10)
        size = np.array([1.2, 1.25, 1.2])
    else:
        verts, faces = SHAPES[shape]
    r = np.array(part["r"]).reshape(3, 3)
    p = np.array(part["p"])
    world = (r @ (verts * size).T).T + p
    out = []
    for face in faces:
        pts = world[face]
        if len(pts) < 3:
            continue
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        norm = np.linalg.norm(n)
        if norm < 1e-9:
            n = np.cross(pts[2] - pts[0], pts[-1] - pts[0])
            norm = np.linalg.norm(n)
            if norm < 1e-9:
                continue
        out.append((pts, n / norm))
    return out


def view_matrix(yaw_deg):
    # Caméra qui regarde le personnage depuis l'avant (yaw 0), en tournant autour de lui.
    a = math.radians(yaw_deg)
    # Direction de la caméra vers le personnage.
    forward = np.array([math.sin(a), 0, math.cos(a)])  # yaw 0 : la caméra est en -Z et regarde +Z
    right = np.array([math.cos(a), 0, -math.sin(a)]) * -1
    up = np.array([0, 1, 0])
    return forward, right, up


def render(ax, fig, yaw, title):
    forward, right, up = view_matrix(yaw)
    polys = []
    for part in fig["parts"]:
        color = np.array(part["c"]) / 255.0
        alpha = 1 - float(part.get("t", 0)) * 0.8
        metal = part.get("m") == "Metal"
        for pts, n in polygons(part):
            facing = -np.dot(n, forward)
            depth = float(np.mean(pts @ forward))
            lam = max(0.0, float(np.dot(n, LIGHT)))
            shade = 0.55 + 0.55 * lam
            if metal:
                shade = min(1.15, shade * 1.08 + 0.05 * max(0, facing))
            c = np.clip(color * shade, 0, 1)
            xy = np.stack([pts @ right, pts @ up], axis=1)
            polys.append((depth, xy, c, alpha))
    polys.sort(key=lambda t: -t[0])
    for _, xy, c, alpha in polys:
        ax.add_patch(Polygon(xy, closed=True, facecolor=c, edgecolor=(0, 0, 0, 0.18), linewidth=0.3, alpha=alpha))
    ax.set_xlim(-3.4, 3.4)
    ax.set_ylim(-0.3, 7.3)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(title, fontsize=9, color="#ddd")
    ax.axhline(0, color="#555", linewidth=0.8)


VIEWS = [(0, "Face"), (35, "Trois-quarts"), (90, "Profil"), (180, "Dos")]
plt.rcParams["figure.facecolor"] = "#1d1b22"

for fig in figures:
    f, axes = plt.subplots(1, 4, figsize=(12, 4.6))
    for ax, (yaw, title) in zip(axes, VIEWS):
        ax.set_facecolor("#1d1b22")
        render(ax, fig, yaw, title)
    f.suptitle(fig["label"], color="#f0e2c0", fontsize=13)
    f.tight_layout()
    name = "".join(ch if ch.isalnum() else "_" for ch in fig["label"].lower())
    f.savefig(os.path.join(out_dir, f"costume_{name}.png"), dpi=110, facecolor=f.get_facecolor())
    plt.close(f)

# Planche : toutes les tenues, de face et de trois-quarts.
f, axes = plt.subplots(2, len(figures), figsize=(3 * len(figures), 9))
for col, fig in enumerate(figures):
    for row, (yaw, title) in enumerate([(0, "Face"), (35, "Trois-quarts")]):
        ax = axes[row][col]
        ax.set_facecolor("#1d1b22")
        render(ax, fig, yaw, fig["label"] if row == 0 else title)
f.tight_layout()
f.savefig(os.path.join(out_dir, "costumes_planche.png"), dpi=100, facecolor=f.get_facecolor())
print(f"{len(figures)} figures rendues dans {out_dir}")
