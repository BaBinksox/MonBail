-- Peuples, teints, migration v2 -> v3 et Roulette du Destin (simulation, hors Roblox).
local H = require("./helpers")()
local runtime, mock = H.runtime, H.mock

H.boot()
local RaceConfig = H.shared("Avatar/RaceConfig")
local AvatarConfig = H.shared("Avatar/AvatarConfig")
local MagicConfig = H.shared("Magic/MagicConfig")
local AvatarRemotes = H.shared("Avatar/AvatarRemotes")
local RaceService = H.server("Avatar/RaceService")
local ProfileSchema = H.server("Data/ProfileSchema")

local function findIndex(list, id)
	for index, entry in ipairs(list) do
		if entry.id == id then
			return index
		end
	end
	return nil
end
local function revealed(player)
	local list = {}
	for _, s in ipairs(runtime.sentTo(player, "DestinyRevealed")) do
		table.insert(list, s.args[2]) -- args[1] : le joueur destinataire
	end
	return list
end

print("== Ancien profil (v2) : migration sans perte")
local STORE = "PlayerProfiles_v4"
runtime.cloud[STORE] = runtime.cloud[STORE] or {}
runtime.cloud[STORE]["Player_9301"] = {
	value = {
		version = 2,
		avatar = { base = "woman", face = "serene", mark = "scar_eye", hair = "bun", outfit = "oathbreaker", magic = "ice", height = 1.05, width = 0.95 },
		progression = { xp = 420, rank = "D", reputation = 12, promotions = {} },
		quests = { active = {}, completed = {} },
		missions = { active = {}, completions = {} },
		discoveries = {}, unlocks = {}, inventory = { ember_shard = 3 }, guild = {}, ledger = {},
		settings = { music = 0.5, sfx = 0.8, uiScale = 1, reducedEffects = false },
		stats = { kills = {}, deaths = 2 },
	},
	userIds = { 9301 },
	metadata = {},
}
local veteran = H.join("Vétérane", 9301)
H.advance(2)
local profile = H.profile(veteran)
H.check("profil migré en v" .. ProfileSchema.VERSION, profile.version == ProfileSchema.VERSION, profile.version)
H.check("apparence conservée (base, marque, tenue)", profile.avatar.base == "woman" and profile.avatar.mark == "scar_eye" and profile.avatar.outfit == "oathbreaker")
H.check("peuple par défaut : humain", profile.avatar.race == "human", profile.avatar.race)
H.check("teint par défaut : celui de l'avatar (inchangé)", profile.avatar.skin == "native", profile.avatar.skin)
H.check("pouvoir conservé (Glace)", veteran:GetAttribute("InnateMagic") == "ice")
H.check("progression et inventaire conservés", profile.progression.xp == 420 and profile.inventory.ember_shard == 3)
H.check("réglages conservés + nouveau réglage ambiance à 1", profile.settings.music == 0.5 and profile.settings.ambience == 1)
H.check("le créateur ne se rouvre pas", veteran:GetAttribute("IsCustomizing") == false)
H.check("attribut Race publié", veteran:GetAttribute("Race") == "human")
local stored = runtime.cloud[STORE]["Player_9301"].value
H.check("copie de sauvegarde v2 conservée (_backups)", type(stored._backups) == "table" and stored._backups.v2 ~= nil)

print("== Nouveau joueur : nain au teint ébène")
local dwarfIndex = findIndex(RaceConfig.RACES, "dwarf")
local deepIndex = findIndex(AvatarConfig.SKIN_TONES, "deep")
local smith = runtime.addPlayer("Forgeronne", 9302)
runtime.spawnCharacter(smith)
H.advance(3)
AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(smith, H.selection(2, dwarfIndex, deepIndex))
H.advance(6)
local smithProfile = H.profile(smith)
H.check("peuple et teint enregistrés", smithProfile.avatar.race == "dwarf" and smithProfile.avatar.skin == "deep", tostring(smithProfile.avatar.race) .. "/" .. tostring(smithProfile.avatar.skin))
local humanoid = smith.Character:FindFirstChildOfClass("Humanoid")
H.check("nain : vie maximale +15 %", humanoid.MaxHealth == 115, humanoid.MaxHealth)
H.check("nain : vitesse −7 %", math.abs(humanoid.WalkSpeed - 16 * 0.93) < 1e-6, humanoid.WalkSpeed)
local head = smith.Character:FindFirstChild("Head")
H.check("teint appliqué à la tête", head and head.Color == AvatarConfig.SKIN_TONES[deepIndex].color)
runtime.spawnCharacter(smith)
H.advance(5)
humanoid = smith.Character:FindFirstChildOfClass("Humanoid")
H.check("respawn : bonus réappliqués sans cumul", humanoid.MaxHealth == 115 and math.abs(humanoid.WalkSpeed - 16 * 0.93) < 1e-6, humanoid.MaxHealth)
H.leave(smith)
local smithAgain = H.join("Forgeronne", 9302)
H.advance(3)
humanoid = smithAgain.Character:FindFirstChildOfClass("Humanoid")
H.check("reconnexion : toujours nain", smithAgain:GetAttribute("Race") == "dwarf" and humanoid.MaxHealth == 115)

print("== Elfe : oreilles, vitesse, origine non construite")
local elfIndex = findIndex(RaceConfig.RACES, "elf")
local elf = runtime.addPlayer("Sylve", 9303)
runtime.spawnCharacter(elf)
H.advance(3)
AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(elf, H.selection(3, elfIndex, 2))
H.advance(6)
local elfHead = elf.Character:FindFirstChild("Head")
local ears = 0
for _, child in ipairs(elfHead:GetChildren()) do
	if child.Name == "RaceEar" then
		ears += 1
	end
end
H.check("deux oreilles effilées", ears == 2, ears)
H.check("elfe : vitesse +8 %", math.abs(elf.Character:FindFirstChildOfClass("Humanoid").WalkSpeed - 16 * 1.08) < 1e-6)
H.check("origine elfique marquée indisponible", RaceConfig.getById("elf").originAvailable == false)
local arrival = H.anchorPosition("spawn_village")
local root = elf.Character:FindFirstChild("HumanoidRootPart")
H.check("arrivée au Belvédère (jamais dans le vide)", (mock.Vector3.new(root.Position.X, 0, root.Position.Z) - mock.Vector3.new(arrival.X, 0, arrival.Z)).Magnitude < 1)

print("== Enfant de l'Ombre : dégâts selon l'heure")
local shadowIndex = findIndex(RaceConfig.RACES, "shadowborn")
local shade = runtime.addPlayer("Nocturne", 9304)
runtime.spawnCharacter(shade)
H.advance(3)
AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(shade, H.selection(5, shadowIndex, 11))
H.advance(6)
local WorldConfig = H.shared("World/WorldConfig")
local clock = WorldConfig.getClockTime()
local night = clock >= WorldConfig.NIGHT_START or clock < WorldConfig.NIGHT_END
local expected = if night then 0.88 else 1.06
H.check("multiplicateur de dégâts " .. (if night then "de nuit" else "de jour"), RaceService.getDamageTakenMultiplier(shade) == expected, RaceService.getDamageTakenMultiplier(shade))
local veil = shade.Character:FindFirstChild("ShadowVeil", true)
H.check("voile d'ombre discret", veil ~= nil and veil.Rate <= 5)
H.check("humain : +10 % de Tension", RaceService.getTensionGainMultiplier(veteran) == 1.1)

print("== Roulette du Destin")
local gambler = runtime.addPlayer("Joueuse", 9305)
runtime.spawnCharacter(gambler)
H.advance(3)
for _ = 1, 6 do
	AvatarRemotes.RequestDestinySpin.OnServerEvent:Fire(gambler)
end
H.advance(1)
local verdicts = revealed(gambler)
local first = verdicts[1]
local allSame = #verdicts >= 1
for _, v in ipairs(verdicts) do
	allSame = allSame and v == first
end
H.check("le serveur rend un verdict", type(first) == "string" and findIndex(MagicConfig.MAGICS, first) ~= nil, first)
H.check("demandes rapprochées : toujours le même verdict", allSame, table.concat(verdicts, ","))
H.check("verdict enregistré dans le profil", H.profile(gambler).creation.destinyRoll == first)
H.leave(gambler)
local back = runtime.addPlayer("Joueuse", 9305)
runtime.spawnCharacter(back)
H.advance(4)
local afterReconnect = revealed(back)
H.check("reconnexion : le créateur rappelle le MÊME verdict", afterReconnect[#afterReconnect] == first, tostring(afterReconnect[#afterReconnect]))
AvatarRemotes.RequestDestinySpin.OnServerEvent:Fire(back)
H.advance(1)
afterReconnect = revealed(back)
H.check("retourner la roue ne change rien", afterReconnect[#afterReconnect] == first)
local other = 1
if MagicConfig.MAGICS[1].id == first then
	other = 2
end
AvatarRemotes.ApplyAvatar.OnServerEvent:Fire(back, H.selection(other))
H.advance(6)
H.check("validation : la magie scellée l'emporte sur celle envoyée", back:GetAttribute("InnateMagic") == first, back:GetAttribute("InnateMagic"))
H.check("profil : magie = verdict", H.profile(back).avatar.magic == first)

print("== Équité du tirage (100 joueurs)")
local counts = {}
for i = 1, 100 do
	local p = runtime.addPlayer("Tirage" .. i, 9400 + i)
	runtime.spawnCharacter(p)
	H.advance(0.4)
	AvatarRemotes.RequestDestinySpin.OnServerEvent:Fire(p)
	H.advance(0.1)
	local roll = H.profile(p) and H.profile(p).creation.destinyRoll
	if roll then
		counts[roll] = (counts[roll] or 0) + 1
	end
	H.leave(p)
end
local distinct, total = 0, 0
for _, n in pairs(counts) do
	distinct += 1
	total += n
end
H.check("toutes les magies peuvent sortir (" .. distinct .. " / " .. #MagicConfig.MAGICS .. ")", distinct == #MagicConfig.MAGICS)
H.check("100 tirages enregistrés", total == 100, total)

H.noNewErrors("peuples et roulette sans erreur")
H.printWarnings()
H.finish()
