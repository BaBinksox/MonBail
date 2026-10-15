-- Les six Magies Innées dans le monde (simulation, hors Roblox) : chaque mécanisme ne répond qu'à
-- sa magie, change réellement l'état du monde, et ouvre l'accès à un coffre payé une seule fois.
local H = require("./helpers")()
local WorldAnchors

print("== Démarrage")
H.boot()
WorldAnchors = H.server("World/WorldAnchors")
local MagicConfig = H.shared("Magic/MagicConfig")
local players = {}
for index, magic in ipairs(MagicConfig.MAGICS) do
	players[magic.id] = H.join("Mage_" .. magic.id, 8000 + index, index)
end
H.check("six magies distinctes", #MagicConfig.MAGICS == 6 and MagicConfig.MAGICS[6].id == "gravity", #MagicConfig.MAGICS)
H.noNewErrors("six joueurs créés")

local function xp(player)
	return H.profile(player).progression.xp
end
local function firstPart(dynamicId)
	for _, d in ipairs(WorldAnchors.getDynamic(dynamicId):GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return WorldAnchors.getDynamic(dynamicId)
end
local function lit(dynamicId)
	for _, d in ipairs(WorldAnchors.getDynamic(dynamicId):GetDescendants()) do
		if d:IsA("Fire") then
			return d.Enabled
		end
	end
	return nil
end
local function chestOnce(player, chestId)
	local before = xp(player)
	H.interact(player, chestId)
	local after = xp(player)
	H.advance(1)
	H.interact(player, chestId)
	return after > before and xp(player) == after
end

print("== Pyromancie : trois braseros -> Sanctuaire des Flammes")
H.interact(players.ice, "mech_brazier_1")
H.check("un autre pouvoir n'allume pas le brasero", lit("brazier_1") == false)
for i = 1, 3 do
	H.interact(players.pyromancy, "mech_brazier_" .. i)
end
H.advance(2)
H.check("les trois braseros brûlent", lit("brazier_1") and lit("brazier_2") and lit("brazier_3"))
local door = WorldAnchors.getDynamic("door_flame_sanctum")
H.check("la porte du sanctuaire s'enfonce", (door:GetPivot().Position - H.anchorPosition("door_flame_sanctum_open")).Magnitude < 0.5)
H.check("coffre du sanctuaire : une seule fois", chestOnce(players.pyromancy, "chest_flame_sanctum"))

print("== Antimatière : voile du mausolée")
H.interact(players.shadow, "mech_barrier_cemetery")
H.check("l'Ombre ne dissout pas le voile", firstPart("barrier_cemetery").CanCollide == true)
H.interact(players.antimatter, "mech_barrier_cemetery")
H.check("l'Antimatière dissout le voile", firstPart("barrier_cemetery").CanCollide == false)
H.check("reliquaire du mausolée : une seule fois", chestOnce(players.antimatter, "chest_cemetery"))

print("== Foudre : conduit de la tour")
H.interact(players.lightning, "mech_conduit_forest")
H.advance(2)
local gate = WorldAnchors.getDynamic("door_conduit_gate")
H.check("la herse se lève", (gate:GetPivot().Position - H.anchorPosition("door_conduit_gate_open")).Magnitude < 0.5)
H.check("coffre du guetteur : une seule fois", chestOnce(players.lightning, "chest_conduit"))

print("== Ombre : mur sans ombre + présence")
H.interact(players.shadow, "mech_shadow_wall")
H.check("le mur devient traversable", firstPart("shadow_passage").CanCollide == false)
H.check("alcôve oubliée : une seule fois", chestOnce(players.shadow, "chest_shadow"))
local discoveriesBefore = H.profile(players.ice).discoveries.secret_shadow_presence
H.interact(players.ice, "shadow_presence")
H.check("la présence reste muette pour une autre magie", H.profile(players.ice).discoveries.secret_shadow_presence == discoveriesBefore)
H.interact(players.shadow, "shadow_presence")
H.check("l'Ombre entend la présence (découverte)", H.profile(players.shadow).discoveries.secret_shadow_presence ~= nil)

print("== Glace et Gravité")
H.interact(players.ice, "mech_frozen_pond")
H.check("l'étang gèle", firstPart("pond_ice").CanCollide == true)
H.check("coffre de l'îlot : une seule fois", chestOnce(players.ice, "chest_pond"))
H.interact(players.gravity, "mech_gravity_block")
H.advance(2)
H.check("le bloc glisse", (WorldAnchors.getDynamic("gravity_block"):GetPivot().Position - H.anchorPosition("gravity_block_open")).Magnitude < 0.5)

print("== Retour à l'état initial")
H.advance(130)
H.check("le voile se reforme", firstPart("barrier_cemetery").CanCollide == true)
H.check("la herse retombe", (gate:GetPivot().Position - H.anchorPosition("door_conduit_gate_open")).Magnitude > 3)
H.check("les braseros s'éteignent", lit("brazier_1") == false)
H.noNewErrors("pouvoirs sans erreur")
H.printWarnings()
H.finish()
