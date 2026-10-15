-- Test de démarrage du serveur complet dans la simulation (outil, hors Roblox).
-- Exécute Server/Main.server.luau, fait rejoindre un joueur, puis vérifie quelques invariants.
local mock = require("./mock")
local runtime = require("./runtime")(mock)
local loader = require("./bundle_out")
local env = loader(mock)

local failures = 0
local function check(label, cond, detail)
	if cond then
		print("  OK    " .. label)
	else
		failures += 1
		print("  ÉCHEC " .. label .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

print("== Démarrage de Main.server")
task = nil
mock.task.spawn(function()
	env.run("ServerScriptService/Server/Main")
end)
runtime.runUntil(5)
for _, w in ipairs(runtime.warnings) do
	print("    [warn] " .. w:sub(1, 300))
end
for _, e in ipairs(runtime.errors) do
	print("    [ERREUR] " .. e:sub(1, 1500))
end
check("aucune erreur Luau au démarrage", #runtime.errors == 0, #runtime.errors .. " erreur(s)")
local mainWarnings = 0
for _, w in ipairs(runtime.warnings) do
	if w:find("%[Main%]") then
		mainWarnings += 1
	end
end
check("tous les services démarrent (aucun échec de start())", mainWarnings == 0, mainWarnings .. " service(s) en échec")

print("== Un joueur rejoint")
local player = runtime.addPlayer("Testeur")
runtime.spawnCharacter(player)
runtime.runUntil(runtime.now() + 8)
local ProfileStore = env.require("ServerScriptService/Server/Data/ProfileStore")
local profile = ProfileStore.get(player)
check("profil chargé (v2)", profile ~= nil and profile.version == 2)
check("profil sauvegardable (verrou obtenu)", ProfileStore.isSaveable(player))
check("nouveau joueur : le créateur s'ouvre", #runtime.sentTo(player, "OpenCreator") >= 1)
check("rang publié", player:GetAttribute("AdventurerRank") == "E")
for _, e in ipairs(runtime.errors) do
	print("    [ERREUR] " .. e:sub(1, 1500))
end
check("aucune erreur après l'arrivée du joueur", #runtime.errors == 0, #runtime.errors .. " erreur(s)")

local errorsBefore = #runtime.errors
print("== Fermeture du serveur (BindToClose)")
local closed = false
mock.task.spawn(function()
	for _, fn in ipairs(runtime.closeCallbacks or {}) do
		fn()
	end
	closed = true
end)
runtime.runUntil(runtime.now() + 30)
check("BindToClose se termine", closed)
local stored = runtime.cloud["PlayerProfiles_v4"] and runtime.cloud["PlayerProfiles_v4"]["Player_" .. player.UserId]
check("profil écrit et verrou libéré", stored ~= nil and stored.value._session == nil and stored.value.version == 2)
check("aucune erreur à la fermeture", #runtime.errors == errorsBefore)

print(failures == 0 and "\nDÉMARRAGE OK" or ("\n" .. failures .. " ÉCHEC(S)"))
