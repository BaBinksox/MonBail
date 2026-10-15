#!/bin/bash
# Lance un test de simulation : tools/sim/run.sh boot_test   (ou quest_test, etc.)
# Prérequis : luau et rojo (voir tools/README.md). Variables : LUAU, ROJO.
set -e
cd "$(dirname "$0")/../.."
S=/tmp/claude-0/-home-user/d721f83b-3ad5-5014-b617-4b6fbd5be7d5/scratchpad
LUAU=${LUAU:-$S/luau/luau}
ROJO=${ROJO:-$S/rojo/rojo}
$ROJO sourcemap default.project.json -o sourcemap.json >/dev/null
python3 tools/sim/bundle.py . tools/sim/bundle_out.luau >/dev/null
cd tools/sim
$LUAU "${1:-boot_test}.luau"
