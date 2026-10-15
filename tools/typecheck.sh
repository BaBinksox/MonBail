#!/bin/bash
# Vérification de types stricte de tout le projet : luau-lsp + définitions Roblox + sourcemap Rojo.
# Usage : tools/typecheck.sh [dossiers...]   (défaut : src)
# Variables : LUAU_LSP (binaire luau-lsp), ROBLOX_DEFS (globalTypes.d.luau), ROJO.
cd "$(dirname "$0")/.."
LUAU_LSP=${LUAU_LSP:-luau-lsp}
ROBLOX_DEFS=${ROBLOX_DEFS:-globalTypes.d.luau}
ROJO=${ROJO:-rojo}
$ROJO sourcemap default.project.json -o sourcemap.json >/dev/null 2>&1
# Les "Unknown require" viennent des require(...:WaitForChild(...)) côté client : luau-lsp ne les
# résout pas ; ils ne signalent pas une erreur du jeu.
$LUAU_LSP analyze --definitions="$ROBLOX_DEFS" --sourcemap=sourcemap.json --flag:LuauSolverV2=false "${@:-src}" 2>&1 \
	| grep -v "^\[INFO\]" | grep -v "Unknown require"
