#!/usr/bin/env python3
"""
Analyse statique des require() du projet (d'après sourcemap.json de Rojo) :
- résout require(script.Parent...X), require(ReplicatedStorage.Shared...X) et les chaînes :WaitForChild("X") ;
- signale les modules introuvables et les CYCLES de require (erreur fatale dans Roblox).
Usage : python3 tools/require_graph.py   (depuis la racine du projet, sourcemap.json à jour)
"""
import json, re, sys, os
sm = json.load(open("sourcemap.json"))
nodes = {}  # chemin instance -> fichier
def walk(n, path):
    for c in n.get("children", []):
        p = path + [c["name"]]
        fps = [f for f in c.get("filePaths", []) if f.endswith(".luau")]
        if fps: nodes["/".join(p)] = fps[0]
        walk(c, p)
walk(sm, [])
byfile = {v: k for k, v in nodes.items()}

SERVICES = {"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer"}
def resolve(module_path, expr, aliases):
    # expr ex: script.Parent.Parent.Data.ProfileStore  |  ReplicatedStorage.Shared.Util.Signal | alias.X
    expr = re.sub(r':WaitForChild\("([^"]+)"\)', r'.\1', expr)
    expr = re.sub(r'\s*::\s*ModuleScript', '', expr).strip()
    parts = expr.split(".")
    if parts[0] == "script":
        cur = module_path.split("/")
        for p in parts[1:]:
            if p == "Parent": cur = cur[:-1]
            else: cur = cur + [p]
        return "/".join(cur)
    if parts[0] in SERVICES:
        return "/".join(parts)
    if parts[0] in aliases:
        base = aliases[parts[0]]
        return resolve(module_path, base + ("." + ".".join(parts[1:]) if len(parts) > 1 else ""), aliases)
    return None

edges = {}
unresolved = []
for path, f in nodes.items():
    src = open(f, encoding="utf-8").read()
    aliases = {}
    for m in re.finditer(r'local\s+(\w+)\s*=\s*((?:script|ReplicatedStorage|ServerScriptService|ServerStorage|\w+)(?:\.\w+|:WaitForChild\("[^"]+"\))*)\s*(?:::\s*\w+)?\s*$', src, re.M):
        name, expr = m.group(1), m.group(2)
        if "require" in expr: continue
        if expr.startswith(("script", "ReplicatedStorage", "ServerScriptService")) or expr.split(".")[0].split(":")[0] in aliases:
            aliases[name] = re.sub(r':WaitForChild\("([^"]+)"\)', r'.\1', expr)
    for m in re.finditer(r'require\(\s*([^()]+?(?:\([^()]*\))*[^()]*?)\s*\)', src):
        expr = m.group(1)
        target = resolve(path, expr, aliases)
        if target is None:
            unresolved.append((path, expr)); continue
        if target not in nodes:
            unresolved.append((path, expr + " -> " + target)); continue
        edges.setdefault(path, set()).add(target)

# cycles (Tarjan)
index, low, stack, onstack, sccs, idx = {}, {}, [], set(), [], [0]
sys.setrecursionlimit(10000)
def strong(v):
    index[v] = low[v] = idx[0]; idx[0] += 1; stack.append(v); onstack.add(v)
    for w in edges.get(v, ()):
        if w not in index: strong(w); low[v] = min(low[v], low[w])
        elif w in onstack: low[v] = min(low[v], index[w])
    if low[v] == index[v]:
        comp = []
        while True:
            w = stack.pop(); onstack.discard(w); comp.append(w)
            if w == v: break
        if len(comp) > 1 or v in edges.get(v, ()): sccs.append(comp)
for v in nodes:
    if v not in index: strong(v)
print(f"{len(nodes)} modules, {sum(len(e) for e in edges.values())} require résolus")
for p, e in unresolved:
    print("NON RÉSOLU :", p, "->", e)
if sccs:
    for c in sccs: print("CYCLE :", " <-> ".join(c))
else:
    print("Aucun cycle de require.")
