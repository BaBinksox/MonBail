#!/bin/bash
# Construit la carte dans la simulation, vérifie le contrat et produit les rendus de contrôle.
# Usage : tools/sim/map.sh [zone] [dossier_sortie]
#   zone : all (défaut) | village | forest | north | crypt | x0,z0,x1,z1
# Prérequis : luau, rojo, python3 + matplotlib (voir tools/README.md). Variables : LUAU, ROJO.
set -e
cd "$(dirname "$0")/../.."
S=/tmp/claude-0/-home-user/d721f83b-3ad5-5014-b617-4b6fbd5be7d5/scratchpad
LUAU=${LUAU:-$S/luau/luau}
ROJO=${ROJO:-$S/rojo/rojo}
ZONE=${1:-all}
OUT=${2:-tools/sim/out}
mkdir -p "$OUT"
$ROJO sourcemap default.project.json -o sourcemap.json >/dev/null
python3 tools/sim/bundle.py . tools/sim/bundle_out.luau >/dev/null
cd tools/sim
$LUAU run_builder.luau > "../../$OUT/run.txt" 2>&1 || true
cd ../..
grep "^REPORT" "$OUT/run.txt" | cut -c1-2000
grep -i "erreur\|error" "$OUT/run.txt" | grep -v "^REPORT" | head -5 || true
grep "^JSON " "$OUT/run.txt" | sed 's/^JSON //' > "$OUT/scene.json"
python3 tools/sim/render.py "$OUT/scene.json" "$OUT/$ZONE" "$ZONE"
