#!/bin/bash
# Exporte le projet en trois modèles Roblox (.rbxmx) à importer dans Roblox Studio :
#   build/Shared.rbxmx -> ReplicatedStorage   (dossier "Shared")
#   build/Server.rbxmx -> ServerScriptService (dossier "Server")
#   build/Client.rbxmx -> StarterPlayer > StarterPlayerScripts (dossier "Client")
# Prérequis : rojo (voir tools/README.md). Variable : ROJO.
set -e
cd "$(dirname "$0")/.."
ROJO=${ROJO:-rojo}
mkdir -p build
for part in shared server client; do
	name=$(echo "$part" | sed 's/./\U&/')
	$ROJO build "tools/export/$part.project.json" -o "build/$name.rbxmx"
	echo "build/$name.rbxmx"
done
