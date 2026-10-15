--!strict
--[[
	PlayerData
	Accès des services au profil chargé d'un joueur (au-dessus de ProfileStore).

	Toute modification passe par mutate() : la fonction reçoit le profil, le modifie SANS yield,
	puis le profil est marqué "à sauvegarder" et le signal Changed prévient StateSync (qui pousse
	la tranche concernée au client). On ne garde jamais de référence à une sous-table du profil
	entre deux appels : ProfileStore peut les remplacer (profil relu après une lecture seule).

		PlayerData.mutate(player, "inventory", function(profile)
			profile.inventory.ash_shard = (profile.inventory.ash_shard or 0) + 1
		end)

	Tranches (slice) : "progression", "quests", "missions", "discoveries", "unlocks", "inventory",
	"guild", "settings", "stats", "ledger" (= noms des champs du profil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local ProfileStore = require(script.Parent.ProfileStore)

export type Profile = ProfileStore.Profile

local PlayerData = {}

-- Changed(player, slice) : une tranche du profil vient de changer.
PlayerData.Changed = Signal.new()

-- Profil chargé de `player`, ou nil (pas encore chargé, ou joueur parti).
function PlayerData.get(player: Player): Profile?
	return ProfileStore.get(player)
end

-- Modifie le profil de `player` via `mutator` (sans yield). Retourne false si le profil n'est pas
-- chargé (rien n'est alors modifié). `slice` désigne la tranche modifiée (ou plusieurs).
function PlayerData.mutate(player: Player, slice: string | { string }, mutator: (profile: Profile) -> ()): boolean
	local profile = ProfileStore.get(player)
	if profile == nil then
		return false
	end
	mutator(profile)
	ProfileStore.markDirty(player)
	if type(slice) == "table" then
		for _, name in slice do
			PlayerData.Changed:Fire(player, name)
		end
	else
		PlayerData.Changed:Fire(player, slice)
	end
	return true
end

-- Demande une écriture prochaine (en arrière-plan) : après un événement important (quête terminée,
-- récompense), pour ne pas dépendre de la sauvegarde automatique.
function PlayerData.saveSoon(player: Player)
	task.spawn(ProfileStore.save, player)
end

function PlayerData.isSaveable(player: Player): boolean
	return ProfileStore.isSaveable(player)
end

-- Nombre de découvertes (utilisé par les conditions de rang et de missions).
function PlayerData.countDiscoveries(profile: Profile): number
	local count = 0
	for _ in profile.discoveries do
		count += 1
	end
	return count
end

return PlayerData
