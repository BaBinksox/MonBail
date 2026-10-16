--!strict
--[[
	SpellService
	Les sorts des Magies Innées, résolus ENTIÈREMENT par le serveur (voir SpellConfig) :
		- validation de chaque demande (RequestCast) : le sort appartient à la magie du joueur,
		  joueur vivant et libre (ni Hub, ni anomalie, ni rembobinage, ni charge d'épée), aucune
		  incantation en cours, recharge globale et recharge du sort, Mana suffisant (vérifié ET
		  débité d'un seul geste par ResourceService), point visé ramené dans la portée et derrière
		  le premier mur ; limite de fréquence ;
		- incantation (castTime) : le lanceur est exposé ; une Concentration en cours s'arrête ;
		- résolution côté serveur : projectiles simulés pas à pas (murs, ennemis proches de la
		  trajectoire), zones, champs persistants, rayons, chaînes, effets sur soi ;
		- chaque cible : réaction élémentaire éventuelle (StatusService.tryReaction) AVANT les
		  altérations du coup, dégâts (DamageService : contributions, élimination unique), posture,
		  altérations, éjection, soin du lanceur ; Tension « spellHit » une fois par sort ;
		- les clients reçoivent SpellCast / SpellImpact pour les effets visuels, rien de plus.
	Les sorts ne touchent que les ennemis (pas de PvP magique).
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Combat.CombatConfig)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)
local Remotes = require(ReplicatedStorage.Shared.Magic.SpellRemotes)
local SpellConfig = require(ReplicatedStorage.Shared.Magic.SpellConfig)
local SpatialHitbox = require(ReplicatedStorage.Shared.Combat.SpatialHitbox)
local TimeLoopConfig = require(ReplicatedStorage.Shared.TimeLoop.TimeLoopConfig)

local AvatarService = require(script.Parent.Parent.Avatar.AvatarService)
local CombatService = require(script.Parent.Parent.Combat.CombatService)
local DamageService = require(script.Parent.Parent.Combat.DamageService)
local PostureService = require(script.Parent.Parent.Combat.PostureService)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local ResourceService = require(script.Parent.Parent.Combat.ResourceService)
local StatusService = require(script.Parent.Parent.Combat.StatusService)
local TimeLoopService = require(script.Parent.Parent.TimeLoop.TimeLoopService)

type PlayerState = {
	readyAt: { [string]: number }, -- os.clock() de fin de recharge, par sort
	globalReadyAt: number,
	castingUntil: number,
	projectiles: number,
}

local CAST_HEIGHT = 1.5 -- studs au-dessus du RootPart : départ des projectiles et des rayons
local KNOCKBACK_DURATION = 0.2
local KNOCKBACK_LIFT = 10

local SpellService = {}

local states: { [Player]: PlayerState } = {}
local castLimiter = RateLimiter.new(5, 6)
local nextCastId = 0
local isStarted = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function log(message: string)
	if CombatConfig.DEBUG_LOGS then
		print(`[Sorts] {message}`)
	end
end

local function getState(player: Player): PlayerState
	local state = states[player]
	if state == nil then
		state = { readyAt = {}, globalReadyAt = 0, castingUntil = 0, projectiles = 0 }
		states[player] = state
	end
	return state
end

local function getLivingRoot(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if humanoid == nil or rootPart == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, rootPart
end

local function canAct(player: Player): boolean
	return getLivingRoot(player) ~= nil
		and not AvatarService.isCustomizing(player)
		and not TimeLoopService.isInAnomaly(player)
		and not TimeLoopService.isRewindingFor(player)
end

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3" and value.X == value.X and value.Y == value.Y and value.Z == value.Z
		and math.abs(value.X) < 1e6 and math.abs(value.Y) < 1e6 and math.abs(value.Z) < 1e6
end

local function worldParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

-- Premier élément de DÉCOR entre `from` et `to` (les personnages ne bloquent pas). Retourne la
-- position atteignable (juste avant l'obstacle) et si un obstacle a été rencontré.
local function clipToWorld(from: Vector3, to: Vector3, exclude: { Instance }): (Vector3, boolean)
	local direction = to - from
	if direction.Magnitude < 1e-3 then
		return to, false
	end
	local params = worldParams(exclude)
	local origin = from
	for _ = 1, 4 do
		local result = workspace:Raycast(origin, to - origin, params)
		if result == nil then
			return to, false
		end
		if SpatialHitbox.getCharacterFromPart(result.Instance) == nil then
			return result.Position - direction.Unit * 0.5, true
		end
		origin = result.Position + direction.Unit * 0.1 -- un personnage : on continue derrière lui
	end
	return to, false
end

local function hasLineOfSight(from: Vector3, target: Model, targetRoot: BasePart, exclude: { Instance }): boolean
	local list = table.clone(exclude)
	table.insert(list, target)
	local _, blocked = clipToWorld(from, targetRoot.Position, list)
	return not blocked
end

local function targetRadius(target: Model): number
	local extents = target:GetExtentsSize()
	return math.max(extents.X, extents.Z) / 2
end

-- Ennemis blessables, avec leur RootPart.
local function getEnemies(): { { model: Model, root: BasePart } }
	local list = {}
	for _, instance in CollectionService:GetTagged(TimeLoopConfig.ENTITY_TAG) do
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) and DamageService.isDamageableEnemy(instance) then
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if root then
				table.insert(list, { model = instance, root = root })
			end
		end
	end
	return list
end

-- Ennemis dont le bord est à moins de `radius` de `center`, du plus proche au plus loin.
local function enemiesInRadius(center: Vector3, radius: number, maxTargets: number, exclude: { Instance }): { Model }
	local found = {}
	for _, entry in getEnemies() do
		local distance = (entry.root.Position - center).Magnitude - targetRadius(entry.model)
		if distance <= radius and hasLineOfSight(center + Vector3.new(0, 1, 0), entry.model, entry.root, exclude) then
			table.insert(found, { model = entry.model, distance = distance })
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local result = {}
	for index = 1, math.min(#found, maxTargets) do
		table.insert(result, found[index].model)
	end
	return result
end

-- Distance d'un point à un segment [a, b] et position le long du segment (0..1).
local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return (point - a).Magnitude, 0
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return (point - (a + ab * t)).Magnitude, t
end

-- Premier ennemi le long du segment [from, to] (à `width` près), sinon nil.
local function firstEnemyOnSegment(from: Vector3, to: Vector3, width: number, skip: { [Model]: boolean }?): (Model?, Vector3?)
	local best: Model? = nil
	local bestT = math.huge
	local bestPoint: Vector3? = nil
	for _, entry in getEnemies() do
		if skip == nil or not skip[entry.model] then
			local distance, t = distanceToSegment(entry.root.Position, from, to)
			if distance <= width + targetRadius(entry.model) and t < bestT then
				best, bestT = entry.model, t
				bestPoint = from + (to - from) * t
			end
		end
	end
	return best, bestPoint
end

local function knockbackFrom(center: Vector3, target: Model, speed: number)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if root == nil or root.Anchored or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local direction = (root.Position - center) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SpellKnockbackAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "KnockbackVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = direction.Unit * speed + Vector3.new(0, KNOCKBACK_LIFT, 0)
	velocity.MaxForce = 1e6
	velocity.Parent = root
	Debris:AddItem(velocity, KNOCKBACK_DURATION)
	Debris:AddItem(attachment, KNOCKBACK_DURATION)
end

--------------------------------------------------------------------------------
-- Effet d'un sort sur une cible
--------------------------------------------------------------------------------

type CastContext = {
	player: Player,
	spell: SpellConfig.Spell,
	castId: number,
	exclude: { Instance },
	hitAny: boolean,
}

local function applyHit(context: CastContext, target: Model, scale: number, center: Vector3?)
	local player = context.player
	local spell = context.spell
	if not DamageService.isDamageableEnemy(target) then
		return
	end
	local damage = spell.damage * scale
	-- Réaction AVANT les altérations du coup : c'est l'altération déjà présente qui réagit.
	StatusService.tryReaction(target, spell.magic, damage, player)
	local applied = 0
	if damage > 0 then
		applied = DamageService.dealDamage(target, damage, { player = player, model = player.Character, kind = "spell", element = spell.magic })
	end
	context.hitAny = true
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		if spell.posture > 0 then
			PostureService.damage(target, spell.posture * scale, player)
		end
		for _, application in spell.statuses do
			StatusService.apply(target, application.id, {
				source = player,
				stacks = application.stacks,
				duration = application.duration,
				center = center,
			})
		end
		if spell.knockback > 0 and center then
			knockbackFrom(center, target, spell.knockback)
		end
	end
	if spell.heal > 0 and applied > 0 then
		local casterHumanoid = getLivingRoot(player)
		if casterHumanoid then
			casterHumanoid.Health = math.min(casterHumanoid.MaxHealth, casterHumanoid.Health + applied * spell.heal)
		end
	end
end

local function finishCast(context: CastContext, position: Vector3, targets: { Model })
	Remotes.SpellImpact:FireAllClients(context.castId, context.spell.id, position, targets)
	if context.hitAny then
		context.hitAny = false
		ResourceService.addTension(context.player, "spellHit")
	end
end

--------------------------------------------------------------------------------
-- Résolution par nature de sort
--------------------------------------------------------------------------------

-- Projectile simulé pas à pas : il s'arrête au premier mur ou au premier ennemi proche de sa trajectoire.
local function runProjectile(context: CastContext, origin: Vector3, direction: Vector3)
	local spell = context.spell
	local state = getState(context.player)
	state.projectiles += 1
	local position = origin
	local travelled = 0
	local impact: Vector3 = origin + direction * spell.range
	local directHit: Model? = nil
	while travelled < spell.range do
		local dt = RunService.Heartbeat:Wait()
		local stepLength = math.min(spell.speed * math.max(dt, 1 / 120), spell.range - travelled)
		local nextPosition = position + direction * stepLength
		local clipped, blocked = clipToWorld(position, nextPosition, context.exclude)
		local enemy, point = firstEnemyOnSegment(position, clipped, spell.radius)
		if enemy and point then
			directHit = enemy
			impact = point
			break
		end
		if blocked then
			impact = clipped
			break
		end
		position = nextPosition
		travelled += stepLength
		impact = position
	end
	state.projectiles = math.max(0, state.projectiles - 1)

	local targets: { Model } = {}
	if spell.radius >= 3 then
		targets = enemiesInRadius(impact, spell.radius, spell.maxTargets, context.exclude) -- explosion
	elseif directHit then
		targets = { directHit }
	end
	for _, target in targets do
		applyHit(context, target, 1, impact)
	end
	finishCast(context, impact, targets)
end

local function runZone(context: CastContext, center: Vector3)
	local spell = context.spell
	local targets = enemiesInRadius(center, spell.radius, spell.maxTargets, context.exclude)
	for _, target in targets do
		applyHit(context, target, 1, center)
	end
	finishCast(context, center, targets)
end

local function runField(context: CastContext, center: Vector3)
	local spell = context.spell
	local allTargets: { Model } = {}
	for pulse = 1, spell.pulses do
		if pulse > 1 then
			task.wait(spell.pulseInterval)
		end
		if context.player.Parent ~= Players or TimeLoopService.isRewindingFor(context.player) then
			break
		end
		for _, target in enemiesInRadius(center, spell.radius, spell.maxTargets, context.exclude) do
			applyHit(context, target, 1, nil)
			if not table.find(allTargets, target) then
				table.insert(allTargets, target)
			end
		end
	end
	finishCast(context, center, allTargets)
end

local function runLine(context: CastContext, origin: Vector3, direction: Vector3)
	local spell = context.spell
	local reach = clipToWorld(origin, origin + direction * spell.range, context.exclude)
	local target, point = firstEnemyOnSegment(origin, reach, spell.radius)
	local targets = {}
	if target then
		applyHit(context, target, 1, origin)
		table.insert(targets, target)
	end
	finishCast(context, point or reach, targets)
end

local function runChain(context: CastContext, origin: Vector3, direction: Vector3)
	local spell = context.spell
	local reach = clipToWorld(origin, origin + direction * spell.range, context.exclude)
	local first = firstEnemyOnSegment(origin, reach, spell.radius + 1)
	local targets: { Model } = {}
	local hit: { [Model]: boolean } = {}
	local current = first
	while current and #targets < spell.maxTargets do
		hit[current] = true
		table.insert(targets, current)
		local scale = (1 - spell.chainFalloff) ^ (#targets - 1)
		applyHit(context, current, scale, nil)
		local currentHumanoid = current:FindFirstChildOfClass("Humanoid")
		local currentRoot = currentHumanoid and currentHumanoid.RootPart
		if currentRoot == nil then
			break
		end
		local nextTarget: Model? = nil
		local bestDistance = spell.chainRange
		for _, entry in getEnemies() do
			if not hit[entry.model] then
				local distance = (entry.root.Position - currentRoot.Position).Magnitude - targetRadius(entry.model)
				if distance <= bestDistance and hasLineOfSight(currentRoot.Position, entry.model, entry.root, context.exclude) then
					nextTarget, bestDistance = entry.model, distance
				end
			end
		end
		current = nextTarget
	end
	finishCast(context, if first then first:GetPivot().Position else reach, targets)
end

local function runSelf(context: CastContext)
	local character = context.player.Character
	if character then
		for _, application in context.spell.statuses do
			StatusService.apply(character, application.id, { source = context.player, stacks = application.stacks, duration = application.duration })
		end
		finishCast(context, character:GetPivot().Position, {})
	end
end

--------------------------------------------------------------------------------
-- Demande d'un joueur
--------------------------------------------------------------------------------

local function deny(player: Player, spellId: string, reason: string)
	Remotes.CastDenied:FireClient(player, spellId, reason)
	log(`{player.Name} : {spellId} refusé ({reason})`)
end

-- Point d'effet d'un sort visé : ramené dans la portée, devant le premier mur, posé au sol.
local function resolveAimPoint(spell: SpellConfig.Spell, origin: Vector3, aimPoint: Vector3, exclude: { Instance }): Vector3
	local offset = aimPoint - origin
	local distance = math.min(offset.Magnitude, spell.range)
	local direction = if offset.Magnitude > 1e-3 then offset.Unit else Vector3.zAxis
	local point = clipToWorld(origin, origin + direction * distance, exclude)
	local ground = workspace:Raycast(point + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), worldParams(exclude))
	return if ground then ground.Position else point
end

local function onCastRequested(player: Player, spellId: any, aimPoint: any)
	if not castLimiter:allow(player) then
		return
	end
	local spell = SpellConfig.get(spellId)
	if spell == nil then
		return
	end
	local magicId = MagicConfig.getById(player:GetAttribute(MagicConfig.ATTRIBUTE)).id
	if spell.magic ~= magicId then
		deny(player, spell.id, "magic")
		return
	end
	if spell.kind ~= "self" and not isFiniteVector(aimPoint) then
		return
	end
	if not canAct(player) or CombatService.isCharging(player) then
		deny(player, spell.id, "busy")
		return
	end
	local state = getState(player)
	local now = os.clock()
	if now < state.castingUntil or now < state.globalReadyAt - 0.05 then
		deny(player, spell.id, "busy")
		return
	end
	if now < (state.readyAt[spell.id] or 0) - 0.1 then
		deny(player, spell.id, "cooldown")
		return
	end
	if spell.kind == "projectile" and state.projectiles >= SpellConfig.MAX_PROJECTILES_PER_PLAYER then
		deny(player, spell.id, "busy")
		return
	end
	if not ResourceService.spendMana(player, spell.manaCost) then
		deny(player, spell.id, "mana")
		return
	end

	-- Accepté : recharge, incantation, prévenir tous les clients.
	ResourceService.stopConcentration(player)
	state.readyAt[spell.id] = now + spell.cooldown
	state.globalReadyAt = now + SpellConfig.GLOBAL_COOLDOWN
	state.castingUntil = now + spell.castTime
	player:SetAttribute(SpellConfig.READY_ATTRIBUTE_PREFIX .. spell.id, workspace:GetServerTimeNow() + spell.cooldown)
	player:SetAttribute(SpellConfig.CASTING_ATTRIBUTE, spell.id)
	ResourceService.markCombat(player)

	local character = player.Character :: Model
	local _, rootPart = getLivingRoot(player)
	local root = rootPart :: BasePart
	local exclude: { Instance } = { character }
	local origin = root.Position + Vector3.new(0, CAST_HEIGHT, 0)
	local aim = if isFiniteVector(aimPoint) then aimPoint :: Vector3 else origin + root.CFrame.LookVector * spell.range
	local effectPoint = if spell.kind == "zone" or spell.kind == "field"
		then (if spell.selfCentered then root.Position else resolveAimPoint(spell, origin, aim, exclude))
		else aim
	nextCastId += 1
	local castId = nextCastId
	Remotes.SpellCast:FireAllClients(character, spell.id, castId, origin, effectPoint)
	log(`{player.Name} lance {spell.name} ({spell.manaCost} Mana)`)

	task.delay(spell.castTime, function()
		if player:GetAttribute(SpellConfig.CASTING_ATTRIBUTE) == spell.id then
			player:SetAttribute(SpellConfig.CASTING_ATTRIBUTE, nil)
		end
		if not canAct(player) or player.Character ~= character then
			return -- mort, figé ou rembobiné pendant l'incantation : le sort ne part pas
		end
		local _, currentRoot = getLivingRoot(player)
		if currentRoot == nil then
			return
		end
		local castOrigin = currentRoot.Position + Vector3.new(0, CAST_HEIGHT, 0)
		local flat = aim - castOrigin
		local direction = if flat.Magnitude > 1e-3 then flat.Unit else currentRoot.CFrame.LookVector
		local context: CastContext = { player = player, spell = spell, castId = castId, exclude = exclude, hitAny = false }
		if spell.kind == "projectile" then
			runProjectile(context, castOrigin, direction)
		elseif spell.kind == "zone" then
			runZone(context, if spell.selfCentered then currentRoot.Position else effectPoint)
		elseif spell.kind == "field" then
			runField(context, effectPoint)
		elseif spell.kind == "line" then
			runLine(context, castOrigin, direction)
		elseif spell.kind == "chain" then
			runChain(context, castOrigin, direction)
		elseif spell.kind == "self" then
			runSelf(context)
		end
	end)
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Secondes de recharge restantes d'un sort pour un joueur (0 = prêt). Pour les tests et l'interface.
function SpellService.getCooldownRemaining(player: Player, spellId: string): number
	local state = states[player]
	return if state then math.max(0, (state.readyAt[spellId] or 0) - os.clock()) else 0
end

function SpellService.start()
	if isStarted then
		return
	end
	isStarted = true
	Remotes.RequestCast.OnServerEvent:Connect(onCastRequested)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			local state = getState(player)
			state.castingUntil = 0
			player:SetAttribute(SpellConfig.CASTING_ATTRIBUTE, nil)
		end)
	end)
end

return SpellService
