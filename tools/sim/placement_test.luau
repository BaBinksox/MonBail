-- Placement des personnages (simulation, hors Roblox) avec un vrai raycast contre les Parts et le
-- relief du terrain : scène du créateur, arrivée au belvédère, respawn sur la place, reconnexion.
-- Vérifie que les PIEDS reposent sur le sol réel, même quand HipHeight a été recalculé de travers.
local H = require("./helpers")()
local runtime, mock = H.runtime, H.mock
local ORIGIN_X = 3000

print("== Démarrage (raycast réel)")
H.boot()
local TerrainSculpt = H.server("WorldBuild/TerrainSculpt")
runtime.realRaycast = true
runtime.terrainHeight = function(x, z)
	return TerrainSculpt.heightAt(x - ORIGIN_X, z)
end
local CharacterPlacement = H.server("Core/CharacterPlacement")

local function feetOf(character)
	local lowest = math.huge
	for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
		local foot = character:FindFirstChild(name)
		lowest = math.min(lowest, foot.Position.Y - foot.Size.Y / 2)
	end
	return lowest
end
local function groundUnder(anchorId)
	local position = H.anchorPosition(anchorId)
	return position and CharacterPlacement.findGround(position, {})
end
local function checkStanding(label, character, ground)
	local root = character:FindFirstChild("HumanoidRootPart")
	local gap = feetOf(character) - ground.Y
	H.check(label .. " : pieds sur le sol (écart " .. string.format("%.2f", gap) .. ")", math.abs(gap) < 0.25)
	H.check(label .. " : tête au-dessus du sol", character.Head.Position.Y > ground.Y + 3)
	H.check(label .. " : vitesse nulle", root.AssemblyLinearVelocity == nil or root.AssemblyLinearVelocity.Magnitude < 1e-3)
end

for _, id in ipairs({ "spawn_creator", "spawn_village", "spawn_plaza" }) do
	local ground = groundUnder(id)
	H.check(id .. " : un sol praticable sous l'ancre", ground ~= nil)
	if ground then
		local height = H.anchorPosition(id).Y - ground.Y
		H.check(id .. " : ancre ≈ 3 studs au-dessus du sol (" .. string.format("%.2f", height) .. ")", height > 2.5 and height < 3.6)
	end
end

print("== Nouveau joueur : scène du créateur")
local player = runtime.addPlayer("Pose", 9101)
runtime.spawnCharacter(player)
H.advance(3)
checkStanding("créateur", player.Character, groundUnder("spawn_creator"))
H.check("créateur : personnage figé pendant la création", player.Character.HumanoidRootPart.Anchored == true)

print("== HipHeight faussé par la reconstruction du rig")
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
humanoid.HipHeight = -1.2 -- ce qu'un BuildRigFromAttachments malheureux peut produire
CharacterPlacement.repairHipHeight(player.Character, nil)
H.check("HipHeight réparé d'après les pieds (" .. string.format("%.2f", humanoid.HipHeight) .. ")", math.abs(humanoid.HipHeight - 2) < 0.05)
humanoid.HipHeight = -1.2
CharacterPlacement.place(player.Character, H.mock.CFrame.new(H.anchorPosition("spawn_creator")))
checkStanding("placement avec HipHeight faux", player.Character, groundUnder("spawn_creator"))
humanoid.HipHeight = 2

print("== Validation : arrivée au belvédère")
local AvatarRemotes = H.shared("Avatar/AvatarRemotes")
AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(player, H.selection(1))
H.advance(4)
checkStanding("arrivée", player.Character, groundUnder("spawn_village"))
H.check("arrivée : libéré (non ancré)", player.Character.HumanoidRootPart.Anchored == false)
local look = player.Character.HumanoidRootPart.CFrame.LookVector
local expected = H.anchorPosition("spawn_village")
local plaza = mock.Vector3.new(ORIGIN_X, expected.Y, 0)
local toPlaza = (plaza - expected).Unit
H.check("arrivée : regard tourné vers le village", look:Dot(toPlaza) > 0.9)
H.check("arrivée : à l'horizontale (pas couché)", math.abs(look.Y) < 0.01)

print("== Respawn et reconnexion")
runtime.spawnCharacter(player)
H.advance(4)
checkStanding("respawn", player.Character, groundUnder("spawn_plaza"))
H.leave(player)
local again = H.join("Pose", 9101)
H.advance(2)
checkStanding("reconnexion", again.Character, groundUnder("spawn_village"))
H.noNewErrors("placement sans erreur")
H.printWarnings()
H.finish()
