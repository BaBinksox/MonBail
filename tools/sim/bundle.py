#!/usr/bin/env python3
"""
Assemble les ModuleScripts du projet (d'après sourcemap.json de Rojo) dans un seul fichier Luau
exécutable hors de Studio avec mock.luau.

Usage : bundle.py <racine_projet> <sortie.luau>
Le fichier produit exporte : loader(mock) -> { require = fn(cheminInstance), root = instanceMock }
où cheminInstance est du type "ServerScriptService/Server/WorldBuild/WorldBuilder".
"""
import json, os, sys
# Usage : bundle.py <racine_projet> <sortie.luau>

root, out = sys.argv[1], sys.argv[2]
sm = json.load(open(os.path.join(root, "sourcemap.json")))

modules = []  # (chemin instance, classe, fichier)
folders = set()

def walk(node, path):
    for child in node.get("children", []):
        p = path + [child["name"]]
        cls = child["className"]
        fps = [f for f in child.get("filePaths", []) if f.endswith(".luau") or f.endswith(".lua")]
        if cls in ("ModuleScript", "Script", "LocalScript") and fps:
            modules.append(("/".join(p), cls, fps[0]))
        elif cls in ("Folder",) or not fps:
            folders.add("/".join(p))
        walk(child, p)

walk(sm, [])

ENV = ["script", "require", "game", "workspace", "Instance", "Vector3", "Vector2", "CFrame", "Color3", "Enum",
       "Random", "task", "typeof", "NumberSequence", "ColorSequence", "NumberSequenceKeypoint",
       "ColorSequenceKeypoint", "NumberRange", "PhysicalProperties", "TweenInfo", "Font", "UDim", "UDim2",
       "BrickColor", "Rect", "Faces", "Axes", "warn", "tick", "os", "print", "RaycastParams", "OverlapParams"]

lines = ["-- FICHIER GÉNÉRÉ par bundle.py : ne pas modifier.", "local FACTORIES = {}"]
for path, cls, fp in modules:
    src = open(os.path.join(root, fp), encoding="utf-8").read()
    lines.append(f"FACTORIES[{json.dumps(path)}] = function({', '.join(ENV)})")
    lines.append(src)
    lines.append("end")

lines.append("local FOLDERS = " + "{" + ", ".join(json.dumps(f) for f in sorted(folders)) + "}")
lines.append("local MODULE_PATHS = {" + ", ".join(json.dumps(p) for p, _, _ in modules) + "}")
lines.append("local MODULE_CLASSES = {" + ", ".join("[" + json.dumps(p) + "]=" + json.dumps(c) for p, c, _ in modules) + "}")
lines.append(r'''
return function(mock)
	local game = mock.game
	local cache = {}
	local byPath = {}
	local function ensure(path, className)
		if byPath[path] then return byPath[path] end
		local parts = string.split(path, "/")
		local parent
		local service = parts[1]
		parent = game:GetService(service)
		local acc = service
		for i = 2, #parts do
			acc = acc .. "/" .. parts[i]
			local existing = byPath[acc]
			if existing == nil then
				local cls = if i == #parts then className else "Folder"
				existing = mock.Instance.new(cls)
				existing.Name = parts[i]
				existing.Parent = parent
				byPath[acc] = existing
			end
			parent = existing
		end
		return parent
	end
	for _, f in ipairs(FOLDERS) do
		if string.find(f, "/") then ensure(f, "Folder") end
	end
	for _, p in ipairs(MODULE_PATHS) do
		local inst = ensure(p, MODULE_CLASSES[p] or "ModuleScript")
		inst:SetAttribute("_path", p)
	end
	local requireFn
	local loading = {}
	requireFn = function(target)
		local path
		if type(target) == "string" then
			path = target
		else
			local ok, value = pcall(function() return target:GetAttribute("_path") end)
			if not ok then
				local name = if type(target) == "table" then tostring(rawget(target, "Name")) else type(target)
				error("require mock : cible non-Instance (" .. name .. ") depuis " .. tostring(loading[#loading]), 2)
			end
			path = value
		end
		if path == nil then error("require mock : instance inconnue " .. tostring(target) .. " depuis " .. tostring(loading[#loading])) end
		if cache[path] ~= nil then return cache[path] end
		local factory = FACTORIES[path]
		if factory == nil then error("require mock : module absent " .. path) end
		local script = byPath[path]
		local warnFn = function(...) print("[warn]", ...) end
		table.insert(loading, path)
		local result = factory(script, requireFn, game, mock.workspace, mock.Instance, mock.Vector3, mock.Vector2,
			mock.CFrame, mock.Color3, mock.Enum, mock.Random, mock.task, mock.typeof, mock.NumberSequence,
			mock.ColorSequence, mock.NumberSequenceKeypoint, mock.ColorSequenceKeypoint, mock.NumberRange,
			mock.PhysicalProperties, mock.TweenInfo, mock.Font, mock.UDim, mock.UDim2, mock.BrickColor, mock.Rect,
			mock.Faces, mock.Axes, mock.warn or warnFn, function() return 0 end, mock.os or os, mock.print or print, mock.RaycastParams, mock.OverlapParams)
		table.remove(loading)
		cache[path] = if result == nil then true else result
		return result
	end
	-- Exécute un Script / LocalScript (même mécanisme que require, sans cache de valeur utile).
	local function runScript(path)
		return requireFn(path)
	end
	-- Remplace un module par une valeur de test (doublure) avant qu'il ne soit chargé.
	local function inject(path, value)
		cache[path] = value
	end
	return { require = requireFn, run = runScript, inject = inject, instances = byPath }
end
''')
open(out, "w", encoding="utf-8").write("\n".join(lines))
print(f"{len(modules)} modules assemblés -> {out}")
