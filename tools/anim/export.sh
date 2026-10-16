#!/bin/bash
# Exporte les séquences d'animation éditables : build/AnimationSequences.rbxmx (voir docs/ANIMATIONS.md).
set -e
cd "$(dirname "$0")/../.."
LUAU=${LUAU:-luau}
ROJO=${ROJO:-rojo}
$ROJO sourcemap default.project.json -o sourcemap.json >/dev/null
python3 tools/sim/bundle.py . tools/sim/bundle_out.luau >/dev/null
mkdir -p build
cd tools/anim
$LUAU export_sequences.luau > ../../build/AnimationSequences.rbxmx
echo build/AnimationSequences.rbxmx
