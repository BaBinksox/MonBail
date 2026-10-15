#!/bin/bash
# Lance un test de simulation : tools/sim/run.sh boot_test   (ou quest_test, etc.)
# Prérequis : luau et rojo (voir tools/README.md). Variables : LUAU, ROJO.
set -e
cd "$(dirname "$0")/../.."
LUAU=${LUAU:-luau}
ROJO=${ROJO:-rojo}
$ROJO sourcemap default.project.json -o sourcemap.json >/dev/null
python3 tools/sim/bundle.py . tools/sim/bundle_out.luau >/dev/null
cd tools/sim
$LUAU "${1:-boot_test}.luau"
