#!/usr/bin/env python3
"""
Rendu de contrôle de la carte générée (sortie JSON de run_builder.luau).

Usage : render.py scene.json out_prefix [zone]
  zone : "all" (défaut) | "village" | "forest" | "north" | x0,z0,x1,z1 (coordonnées LOCALES)
Produit <out_prefix>_top.png (vue de dessus) et <out_prefix>_iso.png (vue en perspective cavalière).
"""
import json, sys, math
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

scene_path, prefix = sys.argv[1], sys.argv[2]
zone = sys.argv[3] if len(sys.argv) > 3 else "all"
data = json.load(open(scene_path))
ox, oy, oz = data["origin"]

ZONES = {
    "all": (-720, -660, 280, 360),
    "village": (-200, -250, 260, 320),
    "forest": (-700, -340, -170, 280),
    "north": (-220, -660, 220, -150),
    "crypt": (-100, -80, 20, 50),
}
if zone in ZONES:
    X0, Z0, X1, Z1 = ZONES[zone]
else:
    X0, Z0, X1, Z1 = [float(v) for v in zone.split(",")]

MATERIAL_COLORS = {
    "Grass": (0.33, 0.42, 0.22), "LeafyGrass": (0.28, 0.38, 0.2), "Ground": (0.36, 0.3, 0.22), "Mud": (0.3, 0.24, 0.18),
    "Rock": (0.42, 0.42, 0.42), "Slate": (0.35, 0.36, 0.38), "Basalt": (0.22, 0.22, 0.24), "Sand": (0.62, 0.56, 0.4),
    "Water": (0.12, 0.2, 0.28), "Cobblestone": (0.4, 0.38, 0.36), "Asphalt": (0.2, 0.2, 0.2), "Snow": (0.9, 0.9, 0.92),
    "Ice": (0.6, 0.75, 0.85), "Glacier": (0.55, 0.7, 0.8), "Limestone": (0.6, 0.57, 0.5), "Sandstone": (0.6, 0.48, 0.35),
    "CrackedLava": (0.35, 0.15, 0.08), "Salt": (0.75, 0.73, 0.7), "Pavement": (0.38, 0.38, 0.38), "Brick": (0.45, 0.25, 0.2),
    "WoodPlanks": (0.4, 0.3, 0.2), "Concrete": (0.5, 0.5, 0.5), "Air": None,
}

def mat_name(m):
    return m if isinstance(m, str) else "Ground"

# ---------------------------------------------------------------------------------------------
# Terrain : carte de hauteur + matériaux (approximation colonne par colonne, dans l'ordre des opérations)
# ---------------------------------------------------------------------------------------------
RES = 2.0
nx, nz = int((X1 - X0) / RES), int((Z1 - Z0) / RES)
xs = X0 + (np.arange(nx) + 0.5) * RES
zs = Z0 + (np.arange(nz) + 0.5) * RES
GX, GZ = np.meshgrid(xs, zs)  # [nz, nx]
height = np.full(GX.shape, -np.inf)
matcol = np.zeros(GX.shape + (3,))
water = np.zeros(GX.shape, dtype=bool)

def cf_parse(cf):
    p = np.array(cf["p"], dtype=float) - np.array([ox, oy, oz])
    r = np.array(cf["r"], dtype=float).reshape(3, 3)
    return p, r

def apply_column(mask, top, bottom, mname):
    global height
    col = MATERIAL_COLORS.get(mname, (0.5, 0.45, 0.4))
    if mname == "Air":
        carve = mask & (height <= top) & (height > bottom)
        height[carve] = bottom[carve] if np.ndim(bottom) else bottom
        return
    raise_ = mask & (top > height)
    height[raise_] = top[raise_] if np.ndim(top) else top
    matcol[raise_] = col
    if mname == "Water":
        water[raise_] = True
    else:
        water[raise_] = False

for op in data.get("terrain", []):
    k, a = op["k"], op["a"]
    try:
        if k == "FillBlock" or k == "FillWedge":
            p, r = cf_parse(a[0]); size = np.array(a[1]); mname = mat_name(a[2])
            # Coordonnées locales de chaque cellule dans le repère du bloc (rotation quelconque : on teste
            # le rectangle projeté, et on prend la hauteur haute de la face supérieure approchée).
            dx, dz = GX - p[0], GZ - p[2]
            right, up, back = r[:, 0], r[:, 1], r[:, 2]
            # On ne gère correctement que les blocs dont l'axe up est ~vertical (cas courant du terrain).
            lx = dx * right[0] + dz * right[2]
            lz = dx * back[0] + dz * back[2]
            mask = (np.abs(lx) <= size[0] / 2) & (np.abs(lz) <= size[2] / 2)
            if k == "FillWedge":
                frac = (lz + size[2] / 2) / max(size[2], 1e-6)
                top = p[1] - size[1] / 2 + size[1] * frac
            else:
                top = np.full(GX.shape, p[1] + size[1] / 2 * abs(up[1]) + 0 * dx)
            bottom = np.full(GX.shape, p[1] - size[1] / 2)
            apply_column(mask, top, bottom, mname)
        elif k == "FillBall":
            c = np.array(a[0]) - np.array([ox, oy, oz]); rad = a[1]; mname = mat_name(a[2])
            d2 = (GX - c[0]) ** 2 + (GZ - c[2]) ** 2
            mask = d2 <= rad * rad
            h = np.sqrt(np.maximum(rad * rad - d2, 0))
            apply_column(mask, c[1] + h, c[1] - h, mname)
        elif k == "FillCylinder":
            p, r = cf_parse(a[0]); h = a[1]; rad = a[2]; mname = mat_name(a[3])
            up = r[:, 1]
            if abs(up[1]) > 0.7:
                d2 = (GX - p[0]) ** 2 + (GZ - p[2]) ** 2
                mask = d2 <= rad * rad
                apply_column(mask, np.full(GX.shape, p[1] + h / 2), np.full(GX.shape, p[1] - h / 2), mname)
            else:
                # cylindre couché : approximé par une boîte
                ax = np.array([up[0], up[2]]); ax = ax / (np.linalg.norm(ax) + 1e-9)
                dx, dz = GX - p[0], GZ - p[2]
                along = dx * ax[0] + dz * ax[1]
                across = -dx * ax[1] + dz * ax[0]
                mask = (np.abs(along) <= h / 2) & (np.abs(across) <= rad)
                apply_column(mask, np.full(GX.shape, p[1] + rad), np.full(GX.shape, p[1] - rad), mname)
    except Exception as e:
        print("terrain op ignorée", k, e)

empty = ~np.isfinite(height)
height[empty] = np.nan

# Ombrage (lumière du nord-ouest)
hz = np.nan_to_num(height, nan=np.nanmin(height) if np.isfinite(np.nanmin(height)) else 0)
gy, gx = np.gradient(hz, RES)
light = np.array([-0.5, -0.6, 0.62]); light /= np.linalg.norm(light)
normal = np.dstack([-gx, -gy, np.ones_like(gx)])
normal /= np.linalg.norm(normal, axis=2, keepdims=True)
shade = np.clip((normal * light).sum(axis=2), 0.25, 1.0)
hmin, hmax = np.nanmin(hz), np.nanmax(hz)
hnorm = (hz - hmin) / max(hmax - hmin, 1)
rgb = matcol * (0.55 + 0.45 * shade[..., None]) * (0.75 + 0.35 * hnorm[..., None])
rgb[empty] = (0.05, 0.05, 0.07)
rgb = np.clip(rgb, 0, 1)

# ---------------------------------------------------------------------------------------------
# Parts
# ---------------------------------------------------------------------------------------------
parts = []
for prt in data["parts"]:
    if prt.get("t", 0) >= 0.97:
        continue
    p, r = cf_parse(prt["cf"])
    s = np.array(prt["s"])
    if p[0] < X0 - 60 or p[0] > X1 + 60 or p[2] < Z0 - 60 or p[2] > Z1 + 60:
        continue
    parts.append((p, r, s, prt))

def box_corners(p, r, s, wedge=False):
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                ly = sy * s[1] / 2
                if wedge and sy == 1 and sz == -1:
                    ly = -s[1] / 2  # arête haute à l'arrière (+Z local)
                pts.append(p + r @ np.array([sx * s[0] / 2, ly, sz * s[2] / 2]))
    return np.array(pts)

def hull(points):
    pts = sorted(set(map(tuple, np.round(points, 3))))
    if len(pts) <= 2:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for q in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    for q in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    return lower[:-1] + upper[:-1]

# ---- Vue de dessus
fig_w = 18
fig_h = fig_w * (Z1 - Z0) / (X1 - X0)
fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=110)
ax.imshow(rgb, extent=(X0, X1, Z1, Z0), origin="upper", interpolation="bilinear")
polys, cols, tops = [], [], []
for p, r, s, prt in parts:
    c = box_corners(p, r, s, prt["c"] == "WedgePart")
    top = c[:, 1].max()
    h2 = hull(c[:, [0, 2]])
    if len(h2) < 3:
        continue
    col = np.array(prt["col"]) * (0.7 + 0.3 * np.clip((top - hmin) / max(hmax - hmin + 40, 1), 0, 1))
    if prt.get("m") == "Neon":
        col = np.clip(np.array(prt["col"]) * 1.3, 0, 1)
    polys.append(h2); cols.append(np.append(np.clip(col, 0, 1), 1 - prt.get("t", 0) * 0.8)); tops.append(top)
order = np.argsort(tops)
pc = PolyCollection([polys[i] for i in order], facecolors=[cols[i] for i in order], edgecolors=(0, 0, 0, 0.35), linewidths=0.25)
ax.add_collection(pc)
# Ancres et interactables
for prt in data["parts"]:
    p, _ = cf_parse(prt["cf"])
    if prt.get("a"):
        ax.plot(p[0], p[2], marker="x", color="cyan", ms=4)
        ax.annotate(prt["a"], (p[0], p[2]), fontsize=4.5, color="cyan")
    if prt.get("i"):
        ax.plot(p[0], p[2], marker="o", color="yellow", ms=3)
        ax.annotate(prt["i"], (p[0], p[2]), fontsize=4.5, color="yellow")
ax.set_xlim(X0, X1); ax.set_ylim(Z1, Z0)
ax.set_title(f"Vue de dessus (nord en haut) — {zone}")
ax.grid(color=(1, 1, 1, 0.08), lw=0.4)
fig.tight_layout()
fig.savefig(prefix + "_top.png")
plt.close(fig)

# ---- Vue en perspective (projection orthographique oblique, depuis le sud-est, peintre)
yaw = math.radians(-35)  # caméra au sud-est regardant au nord-ouest
pitch = math.radians(38)
cy, sy_ = math.cos(yaw), math.sin(yaw)
cp, sp = math.cos(pitch), math.sin(pitch)
def project(pts):
    x, y, z = pts[..., 0], pts[..., 1], pts[..., 2]
    xr = x * cy - z * sy_
    zr = x * sy_ + z * cy
    sxp = xr
    syp = y * cp - zr * sp  # z vers le nord = haut de l'écran
    depth = zr * cp + y * sp
    return np.stack([sxp, syp], -1), depth

faces, fcols, depths = [], [], []
STEP = 3
th = hz[::STEP, ::STEP]; tc = rgb[::STEP, ::STEP]; tx = GX[::STEP, ::STEP]; tz = GZ[::STEP, ::STEP]
em = empty[::STEP, ::STEP]
for i in range(th.shape[0] - 1):
    for j in range(th.shape[1] - 1):
        if em[i, j] or em[i + 1, j + 1]:
            continue
        quad = np.array([[tx[i, j], th[i, j], tz[i, j]], [tx[i, j + 1], th[i, j + 1], tz[i, j + 1]],
                         [tx[i + 1, j + 1], th[i + 1, j + 1], tz[i + 1, j + 1]], [tx[i + 1, j], th[i + 1, j], tz[i + 1, j]]])
        pr, d = project(quad)
        faces.append(pr); fcols.append(np.append(tc[i, j], 1)); depths.append(d.mean())
FACE_IDX = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
lightv = np.array([-0.4, 0.8, -0.45]); lightv /= np.linalg.norm(lightv)
for p, r, s, prt in parts:
    c = box_corners(p, r, s, prt["c"] == "WedgePart")
    base = np.array(prt["col"])
    for fi in FACE_IDX:
        quad = c[list(fi)]
        n = np.cross(quad[1] - quad[0], quad[2] - quad[0])
        nn = np.linalg.norm(n)
        if nn < 1e-6:
            continue
        n /= nn
        pr, d = project(quad)
        lum = 0.45 + 0.55 * max(0, abs(n @ lightv))
        col = base * lum if prt.get("m") != "Neon" else np.clip(base * 1.4, 0, 1)
        faces.append(pr); fcols.append(np.append(np.clip(col, 0, 1), 1 - prt.get("t", 0) * 0.8)); depths.append(d.mean())
order = np.argsort(depths)  # du plus lointain au plus proche
allp = np.concatenate([f for f in faces]) if faces else np.zeros((1, 2))
fig, ax = plt.subplots(figsize=(20, 13), dpi=100)
ax.set_facecolor((0.08, 0.08, 0.1))
ax.add_collection(PolyCollection([faces[i] for i in order], facecolors=[fcols[i] for i in order], edgecolors=(0, 0, 0, 0.15), linewidths=0.15))
ax.set_xlim(allp[:, 0].min(), allp[:, 0].max()); ax.set_ylim(allp[:, 1].min(), allp[:, 1].max())
ax.set_aspect("equal"); ax.axis("off")
ax.set_title(f"Perspective depuis le sud-est — {zone}")
fig.tight_layout()
fig.savefig(prefix + "_iso.png")
plt.close(fig)
print("ok", prefix)
