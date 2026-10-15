--!strict
--[[
	DamageService
	Point UNIQUE des dégâts de combat :
		- dealDamage(target, amount, source) : dégâts infligés à un ENNEMI (PNJ taggé TimeLoopEntity, boss) ;
		- damagePlayer(player, amount, source) : dégâts infligés à un JOUEUR (attaques ennemies, PvP).

	Ennemis : enregistre qui a infligé quoi (contributions), détecte la mort UNE fois par apparition et
	émet GameEvents.EnemyDefeated avec la liste des joueurs ÉLIGIBLES aux récompenses :
		- avoir infligé au moins ELIGIBLE_SHARE des PV max, OU avoir touché dans les ASSIST_WINDOW
		  dernières secondes ;
		- ET être à moins de ELIGIBLE_RANGE studs à la mort.
	Les membres d'un même groupe proches d'un joueur éligible le deviennent aussi (extendEligibility,
	enregistré par PartyService). Chaque éligible reçoit la récompense complète : on encourage la
	coopération au lieu de la diviser.

	Unicité : un ennemi porte un identifiant d'apparition (attribut UID_ATTRIBUTE) ; une fois marqué
	"Defeated", plus aucun dégât ni aucune élimination n'est possible sur ce Model, même si un
	rembobinage lui rend des PV. Un ennemi qui réapparaît est un NOUVEAU Model, avec un nouvel uid.

	Joueurs : damagePlayer respecte les immunités (Hub, anomalie, rembobinage, dash), puis consulte
	ParryService (sauf attaque `unblockable`) AVANT d'appliquer les dégâts.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Shared.Boss.BossConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local TimeLoopConfig = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local GameEvents = require(script.Parent.Parent.Core.GameEvents)
local MovementService = require(script.Parent.Parent.Movement.MovementService)
local ParryService = require(script.Parent.ParryService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

export type DamageSource = {
	player: Player?, -- joueur responsable (nil pour un ennemi ou l'environnement)
	model: Model?, -- Model attaquant (personnage du joueur, ennemi, boss)
	kind: string, -- "melee" | "ultimate" | "burn" | "enemy" | "environment"
	unblockable: boolean?, -- attaque de zone : ne se pare pas (elle s'esquive)
	heavy: boolean?, -- coup lourd (dernier coup du combo) : brise les gardes
}

export type HitResult = "hit" | "parried" | "dodged" | "immune"

type Contribution = { damage: number, lastHitClock: number }

type EnemyRecord = {
	uid: string,
	enemyId: string,
	maxHealth: number,
	contributions: { [Player]: Contribution },
	isDefeated: boolean,
	diedConnection: RBXScriptConnection?,
}

local ELIGIBLE_SHARE = 0.1 -- part des PV max à avoir infligée
local ASSIST_WINDOW = 15 -- secondes : un coup récent suffit
local ELIGIBLE_RANGE = 120 -- studs entre le joueur et l'ennemi à sa mort

local ENEMY_ID_ATTRIBUTE = "EnemyId"
local UID_ATTRIBUTE = "EnemyUid"
local DEFEATED_ATTRIBUTE = "Defeated"
local ELITE_ATTRIBUTE = "Elite"

local DamageService = {}

DamageService.ENEMY_ID_ATTRIBUTE = ENEMY_ID_ATTRIBUTE
DamageService.UID_ATTRIBUTE = UID_ATTRIBUTE
DamageService.DEFEATED_ATTRIBUTE = DEFEATED_ATTRIBUTE
DamageService.ELITE_ATTRIBUTE = ELITE_ATTRIBUTE

type Modifier = (target: Model, amount: number, source: DamageSource) -> number
type EligibilityExtender = (eligible: { Player }, position: Vector3) -> { Player }

local records: { [Model]: EnemyRecord } = setmetatable({}, { __mode = "k" }) :: any
local modifiers: { Modifier } = {}
local eligibilityExtender: EligibilityExtender? = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getHumanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function getRootPosition(model: Model): Vector3?
	local humanoid = getHumanoid(model)
	local rootPart = humanoid and humanoid.RootPart
	if rootPart then
		return rootPart.Position
	end
	local primary = model.PrimaryPart
	return primary and primary.Position
end

local function resolveEnemyId(target: Model): string
	local id = target:GetAttribute(ENEMY_ID_ATTRIBUTE)
	if type(id) == "string" and id ~= "" then
		return id
	end
	if CollectionService:HasTag(target, BossConfig.TAG) then
		return "training_boss"
	end
	return target.Name
end

local function computeEligible(record: EnemyRecord, position: Vector3): { Player }
	local now = os.clock()
	local eligible: { Player } = {}
	for player, contribution in record.contributions do
		if player.Parent ~= Players then
			continue
		end
		local share = contribution.damage / math.max(record.maxHealth, 1)
		local isRecent = now - contribution.lastHitClock <= ASSIST_WINDOW
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local isNear = rootPart ~= nil and rootPart:IsA("BasePart") and (rootPart.Position - position).Magnitude <= ELIGIBLE_RANGE
		if (share >= ELIGIBLE_SHARE or isRecent) and isNear then
			table.insert(eligible, player)
		end
	end
	if eligibilityExtender then
		local isExtended, extended = pcall(eligibilityExtender, eligible, position)
		if isExtended and type(extended) == "table" then
			eligible = extended
		end
	end
	return eligible
end

local function finalize(target: Model, record: EnemyRecord, killer: Player?)
	if record.isDefeated then
		return
	end
	record.isDefeated = true
	target:SetAttribute(DEFEATED_ATTRIBUTE, true)
	if record.diedConnection then
		record.diedConnection:Disconnect()
		record.diedConnection = nil
	end

	local position = getRootPosition(target) or Vector3.zero
	local info: GameEvents.DefeatInfo = {
		enemy = target,
		enemyId = record.enemyId,
		uid = record.uid,
		position = position,
		eligible = computeEligible(record, position),
		killer = killer,
		isBoss = CollectionService:HasTag(target, BossConfig.TAG),
		isElite = target:GetAttribute(ELITE_ATTRIBUTE) == true,
	}
	if CombatConfig.DEBUG_LOGS then
		print(`[Damage] {record.enemyId} ({record.uid}) éliminé : {#info.eligible} joueur(s) éligible(s)`)
	end
	GameEvents.EnemyDefeated:Fire(info)
end

local function getRecord(target: Model, humanoid: Humanoid): EnemyRecord
	local record = records[target]
	if record then
		return record
	end
	local uid = target:GetAttribute(UID_ATTRIBUTE)
	if type(uid) ~= "string" then
		uid = HttpService:GenerateGUID(false)
		target:SetAttribute(UID_ATTRIBUTE, uid)
	end
	local newRecord: EnemyRecord = {
		uid = uid :: string,
		enemyId = resolveEnemyId(target),
		maxHealth = humanoid.MaxHealth,
		contributions = {},
		isDefeated = target:GetAttribute(DEFEATED_ATTRIBUTE) == true,
		diedConnection = nil,
	}
	-- Filet de sécurité : une mort qui ne passerait pas par dealDamage (chute, script tiers) compte aussi.
	newRecord.diedConnection = humanoid.Died:Connect(function()
		finalize(target, newRecord, nil)
	end)
	records[target] = newRecord
	return newRecord
end

--------------------------------------------------------------------------------
-- API publique : ennemis
--------------------------------------------------------------------------------

-- true si `target` est un ennemi que les joueurs peuvent blesser (vivant, taggé, pas éliminé, pas invulnérable).
function DamageService.isDamageableEnemy(target: Model): boolean
	local humanoid = getHumanoid(target)
	return humanoid ~= nil
		and humanoid.Health > 0
		and CollectionService:HasTag(target, TimeLoopConfig.ENTITY_TAG)
		and Players:GetPlayerFromCharacter(target) == nil
		and target:GetAttribute(DEFEATED_ATTRIBUTE) ~= true
		and target:GetAttribute(CombatConfig.INVULNERABLE_ATTRIBUTE) ~= true
end

--[[
	Inflige `amount` dégâts à l'ennemi `target`. Retourne les PV réellement retirés (0 si refusé).
	Les modificateurs enregistrés (garde frontale d'un Gardien de Pierre...) peuvent réduire le montant.
	Ne yield pas.
]]
function DamageService.dealDamage(target: Model, amount: number, source: DamageSource): number
	if type(amount) ~= "number" or amount <= 0 or amount ~= amount or not DamageService.isDamageableEnemy(target) then
		return 0
	end
	local humanoid = getHumanoid(target) :: Humanoid
	local record = getRecord(target, humanoid)
	if record.isDefeated then
		return 0
	end

	local finalAmount = amount
	for _, modifier in modifiers do
		local isApplied, modified = pcall(modifier, target, finalAmount, source)
		if isApplied and type(modified) == "number" then
			finalAmount = math.max(0, modified)
		end
	end
	if finalAmount <= 0 then
		return 0
	end

	local before = humanoid.Health
	humanoid.Health = math.max(0, before - finalAmount)
	local applied = before - humanoid.Health

	local player = source.player
	if player and applied > 0 then
		local contribution = record.contributions[player]
		if contribution == nil then
			contribution = { damage = 0, lastHitClock = 0 }
			record.contributions[player] = contribution
		end
		contribution.damage += applied
		contribution.lastHitClock = os.clock()
	end

	if humanoid.Health <= 0 then
		finalize(target, record, player)
	end
	return applied
end

-- Ajoute un modificateur de dégâts infligés aux ennemis (garde, résistance...). Ne doit pas yield.
function DamageService.addModifier(modifier: Modifier)
	table.insert(modifiers, modifier)
end

-- Permet à un système (les groupes) d'élargir la liste des éligibles d'une élimination.
function DamageService.setEligibilityExtender(extender: EligibilityExtender)
	eligibilityExtender = extender
end

-- Identifiant d'apparition d'un ennemi (créé au besoin).
function DamageService.getUid(target: Model): string
	local humanoid = getHumanoid(target)
	if humanoid then
		return getRecord(target, humanoid).uid
	end
	local uid = target:GetAttribute(UID_ATTRIBUTE)
	return if type(uid) == "string" then uid else ""
end

--------------------------------------------------------------------------------
-- API publique : joueurs
--------------------------------------------------------------------------------

-- true si `player` ne peut pas être blessé maintenant (Hub, anomalie, rembobinage de sa rencontre).
function DamageService.isPlayerImmune(player: Player): boolean
	return AvatarService.isCustomizing(player) or TimeLoopService.isInAnomaly(player) or TimeLoopService.isRewindingFor(player)
end

--[[
	Inflige `amount` dégâts au joueur `player`. Peut YIELD (~0,3 s au plus) le temps de laisser une
	parade tardive arriver. Retourne le résultat et les PV réellement retirés :
		"immune"  : le joueur est hors d'atteinte (Hub, anomalie, rembobinage, mort) ;
		"dodged"  : il est en plein dash (i-frames) ;
		"parried" : il a paré (l'attaquant est étourdi, voir ParryService) ;
		"hit"     : les dégâts sont appliqués.
]]
function DamageService.damagePlayer(player: Player, amount: number, source: DamageSource): (HitResult, number)
	local function getHumanoidOf(): Humanoid?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then
			return nil
		end
		return humanoid
	end

	if getHumanoidOf() == nil or DamageService.isPlayerImmune(player) then
		return "immune", 0
	end
	if MovementService.isDashing(player) then
		return "dodged", 0
	end
	if not source.unblockable and ParryService.resolve(player, source.model) then
		return "parried", 0
	end

	-- La parade a pu attendre : on revérifie tout avant d'appliquer.
	local humanoid = getHumanoidOf()
	if humanoid == nil or DamageService.isPlayerImmune(player) then
		return "immune", 0
	end
	if MovementService.isDashing(player) then
		return "dodged", 0
	end
	local before = humanoid.Health
	humanoid:TakeDamage(amount) -- respecte le ForceField d'apparition
	return "hit", before - humanoid.Health
end

return DamageService
