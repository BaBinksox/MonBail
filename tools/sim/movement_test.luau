-- Mobilité et animations (simulation, hors Roblox) : sprint progressif, double saut, garde du
-- serveur, portée des sauts face à la carte, poses procédurales et commandes.
local H = require("./helpers")()
local runtime, mock, env = H.runtime, H.mock, H.env
local Enum = mock.Enum
local V3 = mock.Vector3

H.boot()
local MovementConfig = H.shared("Movement/MovementConfig")
local MovementModel = H.shared("Movement/MovementModel")
local MovementRemotes = H.shared("Movement/MovementRemotes")
local KeyBindings = H.shared("Input/KeyBindings")
local MovementService = H.server("Movement/MovementService")

print("== Commandes")
local conflicts = KeyBindings.findConflicts()
H.check("aucune touche ni bouton attribué à deux actions", #conflicts == 0, table.concat(conflicts, ", "))
H.check("Maj = sprint, C = dash", KeyBindings.BINDINGS.Sprint.keyCode == Enum.KeyCode.LeftShift and KeyBindings.BINDINGS.Dash.keyCode == Enum.KeyCode.C)
for name, binding in pairs(KeyBindings.BINDINGS) do
	if name ~= "Grimoire" and name ~= "Interact" and name ~= "Parry" and name ~= "Rewind" then
		H.check(name .. " : jouable à la manette", binding.gamepad ~= nil)
	end
end

print("== Sprint : modèle")
local ramp, elapsed = 0, 0
while ramp < 1 and elapsed < 2 do
	ramp = MovementModel.stepSprint(ramp, 1 / 60, true, true)
	elapsed += 1 / 60
end
H.check(string.format("accélération progressive : sprint maximal en %.2f s (0,5 à 0,8 voulu)", elapsed), elapsed >= 0.5 and elapsed <= 0.8)
H.check("vitesse maximale = course x 1,5", math.abs(MovementModel.sprintFactor(1) - 1.5) < 1e-6)
H.check("à mi-montée, l'élan est déjà fort (courbe adoucie)", MovementModel.sprintFactor(0.5) > 1.3)
local down, downTime = 1, 0
while down > 0 do
	down = MovementModel.stepSprint(down, 1 / 60, false, true)
	downTime += 1 / 60
end
H.check(string.format("décélération plus rapide (%.2f s)", downTime), downTime < elapsed)
H.check("pas de sprint à l'arrêt", MovementModel.stepSprint(0.5, 0.1, true, false) < 0.5)

print("== Portée des sauts face aux énigmes de la carte")
-- Valeurs de Server/WorldBuild/Forest.luau : ravin de 26 studs (RAVINE ±13) ; étang de rayon 24,
-- îlot de rayon 4 dont le sommet est 6 studs au-dessus du bord.
local RAVINE_GAP, ISLET_GAP, ISLET_RISE = 26, 20, 6
local fastest = 16 * 1.08 * MovementConfig.SPRINT_MULTIPLIER -- Elfe au sprint
local flat, apex = MovementModel.jumpReach(fastest, 0, true)
H.check(string.format("double saut : %.1f studs de haut (modéré)", apex), apex > 9 and apex < 12)
H.check(string.format("Elfe au sprint + double saut : %.1f studs à plat < ravin de %d", flat, RAVINE_GAP), flat < RAVINE_GAP - 3)
local toIslet = MovementModel.jumpReach(fastest, ISLET_RISE, true)
H.check(string.format("îlot de l'étang : %.1f studs < %d (la Glace reste nécessaire)", toIslet, ISLET_GAP), toIslet < ISLET_GAP - 1)
H.check("hauteur maximale tolérée par le serveur au-dessus du double saut", MovementConfig.MAX_RISE_HEIGHT > apex)

print("== Serveur : vitesse, sprint, ralentissement, immobilisation")
local RaceConfig = H.shared("Avatar/RaceConfig")
local dwarfIndex = RaceConfig.indexOf("dwarf")
local player = runtime.addPlayer("Coureuse", 9601)
runtime.spawnCharacter(player)
H.advance(3)
H.shared("Avatar/AvatarRemotes").ApplyAvatar.OnServerEvent:Fire(player, H.selection(1, dwarfIndex, 1))
H.advance(6)
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
local base = humanoid:GetAttribute(MovementConfig.MOVE_SPEED_ATTRIBUTE)
H.check(string.format("vitesse de base publiée avec le bonus racial du Nain (%.2f)", base or -1), base and math.abs(base - 16 * 0.93) < 1e-6)
MovementRemotes.RequestSprint.OnServerEvent:Fire(player, true)
H.advance(0.2)
H.check("sprint accepté par le serveur", player:GetAttribute(MovementConfig.SPRINT_ATTRIBUTE) == true)
H.check("vitesse maximale contrôlée = base x 1,5", math.abs(MovementService.getMaxSpeed(player) - 16 * 0.93 * 1.5) < 1e-6)
local slow = 1
MovementService.addSpeedProvider(function(p)
	return if p == player then slow else 1
end)
slow = 0.5
MovementService.refreshSpeed(player)
H.check("ralentissement : il s'applique aussi au sprint", math.abs(MovementService.getMaxSpeed(player) - 16 * 0.93 * 0.5 * 1.5) < 1e-6)
slow = 0
MovementService.refreshSpeed(player)
H.check("immobilisé : vitesse et saut nuls, sprint coupé", humanoid.WalkSpeed == 0 and humanoid.JumpHeight == 0 and player:GetAttribute(MovementConfig.SPRINT_ATTRIBUTE) == false)
MovementRemotes.RequestSprint.OnServerEvent:Fire(player, true)
H.advance(0.2)
H.check("immobilisé : sprint refusé", player:GetAttribute(MovementConfig.SPRINT_ATTRIBUTE) == false)
slow = 1
MovementService.refreshSpeed(player)
H.check(string.format("fin de l'effet : retour exact à la vitesse normale (%.2f)", humanoid.WalkSpeed), math.abs(humanoid.WalkSpeed - 16 * 0.93) < 1e-6 and humanoid.JumpHeight > 7)

print("== Serveur : double saut")
local TerrainSculpt = H.server("WorldBuild/TerrainSculpt")
runtime.realRaycast = true
runtime.terrainHeight = function(x, z)
	return TerrainSculpt.heightAt(x - 3000, z)
end
local root = player.Character:FindFirstChild("HumanoidRootPart")
local function countSentDoubleJumps()
	local n = 0
	for _, s in ipairs(runtime.sent) do
		if s.remote == "DoubleJumped" then
			n += 1
		end
	end
	return n
end
-- Le joueur est seul : le serveur n'a personne à prévenir. On ajoute un spectateur.
local watcher = H.join("Spectatrice", 9602)
H.advance(1)
H.advance(6)
for _, part in ipairs(watcher.Character:GetDescendants()) do
	if part:IsA("BasePart") then
		part.CFrame = part.CFrame + V3.new(40, 0, 0) -- pas sous les pieds de la coureuse
	end
end
H.advance(0.5)
local before = countSentDoubleJumps()
H.advance(1) -- vu au sol par le contrôle périodique
root.CFrame = root.CFrame + V3.new(0, 6, 0) -- en l'air (premier saut)
MovementRemotes.RequestDoubleJump.OnServerEvent:Fire(player)
H.advance(0.3)
H.check("premier double saut accepté (relayé aux autres joueurs)", countSentDoubleJumps() == before + 1)
H.advance(0.6) -- toujours en l'air pendant un contrôle
MovementRemotes.RequestDoubleJump.OnServerEvent:Fire(player)
H.advance(0.3)
H.check("pas de second double saut sans retour au sol (pas de saut infini)", countSentDoubleJumps() == before + 1)
root.CFrame = root.CFrame - V3.new(0, 6, 0)
H.advance(1.2) -- le contrôle périodique voit le personnage au sol
root.CFrame = root.CFrame + V3.new(0, 6, 0)
MovementRemotes.RequestDoubleJump.OnServerEvent:Fire(player)
H.advance(0.3)
H.check("au sol de nouveau : double saut rendu", countSentDoubleJumps() == before + 2)
root.CFrame = root.CFrame - V3.new(0, 6, 0)
H.advance(1)
print("== Serveur : montée au-delà du double saut")
local groundY = root.Position.Y
root.AssemblyLinearVelocity = V3.new(0, 30, 0)
root.CFrame = root.CFrame + V3.new(0, MovementConfig.MAX_RISE_HEIGHT + 5, 0) -- « vol » (exploit)
H.advance(0.6)
H.check("montée anormale : ramené à sa dernière position valide", root.Position.Y < groundY + 1, string.format("%.1f", root.Position.Y - groundY))
root.AssemblyLinearVelocity = V3.new(0, 0, 0)

print("== Serveur : vitesse anormale corrigée")
H.advance(1.5)
local start = root.Position
for _ = 1, 5 do
	root.CFrame = root.CFrame + V3.new(40, 0, 0) -- 80 studs/s, bien au-delà du sprint
	H.advance(MovementConfig.SPEED_CHECK_INTERVAL)
end
H.check("déplacement hors limite : position ramenée en arrière", (root.Position - start).Magnitude < 200 - 1, string.format("%.0f studs", (root.Position - start).Magnitude))
runtime.realRaycast = false
H.leave(watcher)

print("== Client : sprint progressif et double saut")
local C = require("./client")(mock, runtime, player)
for _, path in ipairs({ "Movement/MovementController", "Animation/AnimationDirector" }) do
	mock.task.spawn(function()
		env.run("StarterPlayer/StarterPlayerScripts/Client/" .. path)
	end)
end
H.advance(1)
local MovementState = env.require("StarterPlayer/StarterPlayerScripts/Client/Movement/MovementState")
humanoid.MoveDirection = V3.new(0, 0, -1)
local sprintAction = C.actions.Sprint
H.check("action Sprint liée", sprintAction ~= nil)
local keyInput = { KeyCode = Enum.KeyCode.LeftShift, UserInputType = Enum.UserInputType.Keyboard }
sprintAction.fn("Sprint", Enum.UserInputState.Begin, keyInput)
C.frames(12) -- 0,2 s
local early = humanoid.WalkSpeed
C.frames(40)
local full = humanoid.WalkSpeed
H.check(string.format("montée progressive : %.1f studs/s à 0,2 s, %.1f à 0,87 s", early, full), early > 16 * 0.93 + 0.5 and early < full)
H.check("sprint plein = base serveur x 1,5", math.abs(full - 16 * 0.93 * 1.5) < 0.05, full)
H.check("champ de vision élargi au sprint", C.camera.FieldOfView > 72)
sprintAction.fn("Sprint", Enum.UserInputState.End, keyInput)
C.frames(20)
H.check("relâché : retour rapide à la course", math.abs(humanoid.WalkSpeed - 16 * 0.93) < 0.05, humanoid.WalkSpeed)
C.frames(60)
H.check("champ de vision rendu à sa valeur normale", math.abs(C.camera.FieldOfView - 70) < 0.05, C.camera.FieldOfView)

local UserInputService = mock.game:GetService("UserInputService")
humanoid.StateChanged:Fire(Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Freefall)
C.frames(12)
local requestsBefore = 0
for _, s in ipairs(runtime.sent) do
	if s.remote == "RequestDoubleJump" then
		requestsBefore += 1
	end
end
UserInputService.JumpRequest:Fire()
C.frames(2)
H.check("double saut : impulsion verticale", math.abs(root.AssemblyLinearVelocity.Y - MovementConfig.DOUBLE_JUMP_VELOCITY) < 1e-6)
C.frames(15)
UserInputService.JumpRequest:Fire()
C.frames(2)
local requestsAfter = 0
for _, s in ipairs(runtime.sent) do
	if s.remote == "RequestDoubleJump" then
		requestsAfter += 1
	end
end
H.check("un seul double saut par passage en l'air (client)", requestsAfter == requestsBefore + 1 and MovementState.jumpsUsed == 1)
humanoid.StateChanged:Fire(Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Landed)
H.check("au sol : double saut rendu", MovementState.jumpsUsed == 0 and not MovementState.airborne)

print("== Poses procédurales")
local CharacterAnimator = env.require("StarterPlayer/StarterPlayerScripts/Client/Animation/CharacterAnimator")
local waist = player.Character:FindFirstChild("Waist", true)
local baseC0 = waist.C0
local animator = CharacterAnimator.get(player.Character, true)
local impact = false
local duration = animator:play("sword_1", { onImpact = function()
	impact = true
end })
H.check("coup 1 : pose jouée (" .. string.format("%.2f", duration) .. " s)", duration > 0.2)
animator:update(duration * 0.5)
H.check("en plein coup : buste tourné", waist.C0 ~= baseC0)
animator:update(duration)
H.check("instant d'impact signalé (synchronisation des effets)", impact)
H.check("fin du coup : articulation rendue exactement", waist.C0 == baseC0)
local different = {}
for i = 1, 5 do
	animator:play("sword_" .. i)
	animator:update(0.15)
	different[i] = waist.C0
	animator:update(2)
end
local distinct = true
for i = 1, 5 do
	for j = i + 1, 5 do
		if different[i] == different[j] then
			distinct = false
		end
	end
end
H.check("les cinq coups du combo ont des poses distinctes", distinct)
animator:play("concentrate")
animator:update(0.5)
local rebuilt = baseC0 * mock.CFrame.new(0, 0.1, 0)
waist.C0 = rebuilt -- reconstruction du rig pendant une pose (changement d'apparence)
animator:update(0.1)
animator:stop("hold")
animator:update(1)
H.check("rig reconstruit pendant une pose : le nouveau C0 est conservé", waist.C0 == rebuilt)
animator:destroy()

H.noNewErrors("mobilité sans erreur")
H.printWarnings()
H.finish()
