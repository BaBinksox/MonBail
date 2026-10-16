--!strict
--[[
	AnimationConfig
	UNE entrée par action animée du jeu (épée, défense, déplacements, magie). Lu par le client
	(CharacterAnimator) ; partagé pour que le serveur cale ses délais sur les mêmes durées.

	Comment une action est jouée, dans cet ordre (la première solution disponible gagne) :
		1. `animationId` : un clip PUBLIÉ ("rbxassetid://...") joué par l'Animator du personnage
		   local, répliqué par Roblox aux autres joueurs. À remplir après publication des
		   séquences dans l'Animation Editor (docs/ANIMATIONS.md) ;
		2. la SÉQUENCE GÉNÉRÉE (Studio seulement) : la pose de PoseLibrary est construite en vraie
		   KeyframeSequence (KeyframeBuilder), enregistrée temporairement par
		   KeyframeSequenceProvider, puis jouée par l'Animator comme un clip. Ces identifiants
		   temporaires ne fonctionnent pas sur un serveur publié : c'est le moyen de juger les
		   mouvements dans Studio avant de les publier ;
		3. `fallbackId` : les clips d'épée utilisés AVANT Combat 2.0 (Roblox, R15 Sword Slash /
		   Lunge), plus un accent procédural du buste et des jambes pour distinguer les coups ;
		4. la pose procédurale seule (calque appliqué sur Motor6D.Transform après l'Animator).
	DEBUG_SOURCES affiche une fois par action, dans la sortie, la solution réellement utilisée.

	Champs : fadeIn / fadeOut (s), speed (1 = normale), fallbackId / fallbackSpeed (repli).
	Les rigs du projet sont R15 ; sur un rig incomplet, une pose s'applique partiellement, sans erreur.
]]

export type Action = {
	animationId: string,
	pose: string,
	fadeIn: number,
	fadeOut: number,
	speed: number,
	fallbackId: string,
	fallbackSpeed: number,
}

local function action(pose: string, fadeIn: number?, fadeOut: number?, speed: number?): Action
	return { animationId = "", pose = pose, fadeIn = fadeIn or 0.06, fadeOut = fadeOut or 0.12, speed = speed or 1, fallbackId = "", fallbackSpeed = 1 }
end

-- Clips d'épée de Roblox utilisés par le jeu avant Combat 2.0 (CombatConfig de l'époque :
-- coups 1 et 2 au Slash x 1,6 / x 1,8, coup 3 au Lunge x 1,2). Chargement à confirmer en jeu :
-- s'ils ne se chargent pas, la séquence générée (Studio) ou la pose prennent le relais.
local ROBLOX_SWORD_SLASH = "rbxassetid://522635514"
local ROBLOX_SWORD_LUNGE = "rbxassetid://522638767"

local function withFallback(entry: Action, fallbackId: string, fallbackSpeed: number): Action
	entry.fallbackId = fallbackId
	entry.fallbackSpeed = fallbackSpeed
	return entry
end

local ACTIONS: { [string]: Action } = {
	-- Épée
	sword_1 = withFallback(action("slash_horizontal", 0.04, 0.1), ROBLOX_SWORD_SLASH, 1.6),
	sword_2 = withFallback(action("slash_diagonal", 0.04, 0.1), ROBLOX_SWORD_SLASH, 1.8),
	sword_3 = withFallback(action("strike_vertical", 0.05, 0.12), ROBLOX_SWORD_LUNGE, 1.2),
	sword_4 = withFallback(action("spin_slash", 0.05, 0.12), ROBLOX_SWORD_SLASH, 1.3),
	sword_5 = withFallback(action("finisher_thrust", 0.06, 0.15), ROBLOX_SWORD_LUNGE, 1),
	sword_charge = action("charge_hold", 0.12, 0.08),
	sword_charged = withFallback(action("charged_release", 0.03, 0.18), ROBLOX_SWORD_LUNGE, 1.1),
	sword_counter = withFallback(action("counter_thrust", 0.03, 0.12), ROBLOX_SWORD_SLASH, 2),
	sword_plunge_fall = action("plunge_dive", 0.05, 0.05), -- maintenue pendant la chute
	sword_plunge = action("plunge_strike", 0.02, 0.15), -- impact à l'atterrissage
	-- Défense, réactions
	parry = action("parry_guard", 0.03, 0.15),
	parry_perfect = action("parry_riposte", 0.02, 0.15),
	hit_react = action("hit_flinch", 0.02, 0.12),
	stagger = action("stagger", 0.05, 0.2),
	-- Déplacements (les marches et courses de base restent celles du script Animate de Roblox)
	dash = action("dash_lean", 0.03, 0.1),
	double_jump = action("double_jump_flip", 0.02, 0.1),
	land = action("land_dip", 0.02, 0.12),
	-- Magie
	concentrate = action("concentrate", 0.25, 0.25),
	cast_pyromancy_base = action("cast_fire_throw"),
	cast_pyromancy_secondary = action("cast_fire_slam"),
	cast_ice_base = action("cast_ice_shard"),
	cast_ice_secondary = action("cast_ice_seal"),
	cast_lightning_base = action("cast_lightning_snap"),
	cast_lightning_secondary = action("cast_lightning_call"),
	cast_shadow_base = action("cast_shadow_sweep"),
	cast_shadow_secondary = action("cast_shadow_veil"),
	cast_antimatter_base = action("cast_void_push"),
	cast_antimatter_secondary = action("cast_void_contract"),
	cast_gravity_base = action("cast_gravity_press"),
	cast_gravity_secondary = action("cast_gravity_field"),
	cast_ultimate = action("cast_ultimate", 0.05, 0.25),
	cast_ultimate_ice = action("cast_ultimate_ice", 0.06, 0.25),
	cast_ultimate_antimatter = action("cast_ultimate_antimatter", 0.06, 0.25),
	cast_ultimate_pyromancy = action("cast_ultimate_pyromancy", 0.06, 0.25),
	cast_ultimate_lightning = action("cast_ultimate_lightning", 0.05, 0.2),
	cast_ultimate_shadow = action("cast_ultimate_shadow", 0.06, 0.25),
	cast_ultimate_gravity = action("cast_ultimate_gravity", 0.06, 0.25),
}

--[[
	>>> IDENTIFIANTS PUBLIÉS : après publication d'une séquence (docs/ANIMATIONS.md), coller ici son
	identifiant ("rbxassetid://123456789"). Vide = séquence générée (Studio), clip de repli ou pose.
]]
local PUBLISHED: { [string]: string } = {
	sword_1 = "",
	sword_2 = "",
	sword_3 = "",
	sword_4 = "",
	sword_5 = "",
	sword_charge = "",
	sword_charged = "",
	sword_counter = "",
	sword_plunge_fall = "",
	sword_plunge = "",
	parry = "",
	parry_perfect = "",
	hit_react = "",
	stagger = "",
	dash = "",
	double_jump = "",
	land = "",
	concentrate = "",
	cast_pyromancy_base = "",
	cast_pyromancy_secondary = "",
	cast_ice_base = "",
	cast_ice_secondary = "",
	cast_lightning_base = "",
	cast_lightning_secondary = "",
	cast_shadow_base = "",
	cast_shadow_secondary = "",
	cast_antimatter_base = "",
	cast_antimatter_secondary = "",
	cast_gravity_base = "",
	cast_gravity_secondary = "",
	cast_ultimate = "",
	cast_ultimate_ice = "",
	cast_ultimate_antimatter = "",
	cast_ultimate_pyromancy = "",
	cast_ultimate_lightning = "",
	cast_ultimate_shadow = "",
	cast_ultimate_gravity = "",
}
for actionName, animationId in PUBLISHED do
	local entry = ACTIONS[actionName]
	if entry and animationId ~= "" then
		entry.animationId = animationId
	end
end

return table.freeze({
	ACTIONS = ACTIONS,
	ROBLOX_SWORD_SLASH = ROBLOX_SWORD_SLASH,
	ROBLOX_SWORD_LUNGE = ROBLOX_SWORD_LUNGE,
	-- Studio : jouer les séquences générées (vraies pistes d'animation) quand aucun clip n'est publié.
	USE_GENERATED_IN_STUDIO = true,
	-- Affiche une fois par action la solution utilisée (publié, généré, repli, pose).
	DEBUG_SOURCES = true,
	-- Distance (studs) au-delà de laquelle les poses des AUTRES personnages ne sont plus calculées.
	REMOTE_POSE_RADIUS = 140,
	-- Inclinaison maximale du buste au sprint (degrés) et à l'accélération.
	SPRINT_LEAN = 14,
	-- Respiration au repos : amplitude (degrés) et période (s).
	IDLE_BREATH_ANGLE = 1.6,
	IDLE_BREATH_PERIOD = 3.4,
})
