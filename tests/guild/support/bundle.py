#!/usr/bin/env python3
"""
Assemble les ModuleScripts du projet (src/shared et src/server) dans un seul fichier Luau exécutable
hors de Studio avec la simulation tests/guild/support/roblox.luau.

Correspondance (identique à default.project.json de Rojo) :
    src/shared -> ReplicatedStorage/Shared
    src/server -> ServerScriptService/Server
Les Scripts (*.server.luau) et LocalScripts (*.client.luau) sont ignorés.

Usage : bundle.py <racine_projet> <sortie.luau>
Le fichier produit retourne loader(env, overrides) -> require(cheminOuInstance).
"""
import json
import os
import sys

ROOTS = [("src/shared", "ReplicatedStorage/Shared"), ("src/server", "ServerScriptService/Server")]
ENV = ["script", "require", "game", "workspace", "Instance", "Vector3", "Vector2", "CFrame", "Color3",
       "Enum", "task", "typeof", "warn", "os", "tick", "Random", "DateTime", "UDim", "UDim2",
       "NumberRange", "NumberSequence", "ColorSequence", "TweenInfo", "BrickColor"]


def main():
    root, out = sys.argv[1], sys.argv[2]
    modules = []  # (chemin instance, fichier)
    folders = set()
    for src_dir, instance_root in ROOTS:
        base = os.path.join(root, src_dir)
        folders.add(instance_root)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            rel = os.path.relpath(dirpath, base)
            inst_dir = instance_root if rel == "." else instance_root + "/" + rel.replace(os.sep, "/")
            folders.add(inst_dir)
            for filename in sorted(filenames):
                if not filename.endswith(".luau") or filename.endswith(".server.luau") or filename.endswith(".client.luau"):
                    continue
                name = filename[:-len(".luau")]
                path = inst_dir if name == "init" else inst_dir + "/" + name
                modules.append((path, os.path.join(dirpath, filename)))

    lines = ["-- FICHIER GÉNÉRÉ par tests/guild/support/bundle.py : ne pas modifier.", "local FACTORIES = {}"]
    for path, filepath in modules:
        with open(filepath, encoding="utf-8") as handle:
            source = handle.read()
        lines.append(f"FACTORIES[{json.dumps(path)}] = function({', '.join(ENV)})")
        lines.append(source)
        lines.append("end")
    lines.append("local FOLDERS = {" + ", ".join(json.dumps(f) for f in sorted(folders)) + "}")
    lines.append("local MODULE_PATHS = {" + ", ".join(json.dumps(p) for p, _ in modules) + "}")
    lines.append(r'''
return function(env, overrides)
	local byPath = {}
	local cache = {}
	local function ensure(path, className)
		if byPath[path] then
			return byPath[path]
		end
		local parts = string.split(path, "/")
		local parent = env.game:GetService(parts[1])
		local acc = parts[1]
		for index = 2, #parts do
			acc = acc .. "/" .. parts[index]
			local existing = byPath[acc]
			if existing == nil then
				existing = env.Instance.new(if index == #parts then className else "Folder")
				existing.Name = parts[index]
				existing.Parent = parent
				byPath[acc] = existing
			end
			parent = existing
		end
		return parent
	end
	for _, folder in FOLDERS do
		if string.find(folder, "/") then
			ensure(folder, "Folder")
		end
	end
	local pathOf = {}
	for _, path in MODULE_PATHS do
		pathOf[ensure(path, "ModuleScript")] = path
	end
	local requireFn
	requireFn = function(target)
		local path = if type(target) == "string" then target else pathOf[target]
		if path == nil then
			error("require simulé : instance inconnue " .. tostring(target), 2)
		end
		if cache[path] ~= nil then
			return cache[path]
		end
		if overrides and overrides[path] ~= nil then
			cache[path] = overrides[path]
			return overrides[path]
		end
		local factory = FACTORIES[path]
		if factory == nil then
			error("require simulé : module absent " .. path, 2)
		end
		local result = factory(byPath[path], requireFn, env.game, env.workspace, env.Instance, env.Vector3,
			env.Vector2, env.CFrame, env.Color3, env.Enum, env.task, env.typeof, env.warn, env.os, env.tick,
			env.Random, nil, nil, nil, nil, nil, nil, nil, nil)
		cache[path] = if result == nil then true else result
		return result
	end
	return requireFn
end
''')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    print(f"{len(modules)} modules assemblés -> {out}")


if __name__ == "__main__":
    main()
