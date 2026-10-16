--!strict
--[[
	AnimationConfig
	UNE entrée par action animée du jeu (déplacements, épée, sorts, réactions). Lu par le client
	(CharacterAnimator) ; partagé pour que le serveur puisse caler ses délais sur les mêmes durées.

	Deux moyens de jouer une action :
		- `animationId` : un CLIP Roblox publié ("rbxassetid://..."), joué par l'Animator du Humanoid
		  (répliqué automatiquement aux autres joueurs). Il doit appartenir au propriétaire de
		  l'expérience (ou être un clip public de Roblox), sinon il ne se charge pas ;
		- `pose` : une POSE PROCÉDURALE de Client/Animation/PoseLibrary (images clés appliquées aux
		  articulations R15 par code), jouée chez chaque client à partir des événements du serveur.
	Si `animationId` est vide, la pose procédurale est utilisée. Les poses procédurales sont
	réellement jouables, mais ce sont des approximations : des clips réalisés dans l'Animation Editor
	de Studio les remplaceront avantageusement (voir docs/COMBAT_2.md, liste des clips à produire).

	Champs :
		priority  priorité d'un clip (Action par défaut pour les actions, Movement pour la locomotion)
		fadeIn / fadeOut  fondus (s)
		speed     vitesse de lecture (1 = normale)
	Les rigs du projet sont tous R15 (joueurs : Humanoid R15 + tête classique ; PNJ et ennemis :
	CreateHumanoidModelFromDescription R15). Une pose procédurale n'agit que sur les articulations
	R15 qu'elle trouve : sur un rig incomplet, elle s'applique partiellement, sans erreur.
]]

export type Action = {
	animationId: string,
	pose: string,
	priority: Enum.AnimationPriority?,
	fadeIn: number,
	fadeOut: number,
	speed: number,
}

local function action(pose: string, fadeIn: number?, fadeOut: number?, speed: number?): Action
	return { animationId = "", pose = pose, fadeIn = fadeIn or 0.06, fadeOut = fadeOut or 0.12, speed = speed or 1 }
end

-- Clips officiels de Roblox déjà utilisés par le projet (publics, jouables partout) : conservés
-- comme solution de repli possible (voir docs), mais les poses procédurales distinctes sont
-- utilisées par défaut pour que les cinq coups du combo ne se ressemblent pas.
local ROBLOX_SWORD_SLASH = "rbxassetid://522635514"
local ROBLOX_SWORD_LUNGE = "rbxassetid://522638767"

local ACTIONS: { [string]: Action } = {
	-- Épée
	sword_1 = action("slash_horizontal", 0.04, 0.1),
	sword_2 = action("slash_diagonal", 0.04, 0.1),
	sword_3 = action("strike_vertical", 0.05, 0.12),
	sword_4 = action("spin_slash", 0.05, 0.12),
	sword_5 = action("finisher_thrust", 0.06, 0.15),
	sword_charge = action("charge_hold", 0.12, 0.08),
	sword_charged = action("charged_release", 0.03, 0.18),
	sword_counter = action("counter_thrust", 0.03, 0.12),
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
}

return table.freeze({
	ACTIONS = ACTIONS,
	ROBLOX_SWORD_SLASH = ROBLOX_SWORD_SLASH,
	ROBLOX_SWORD_LUNGE = ROBLOX_SWORD_LUNGE,
	-- Distance (studs) au-delà de laquelle les poses des AUTRES personnages ne sont plus calculées.
	REMOTE_POSE_RADIUS = 140,
	-- Inclinaison maximale du buste au sprint (degrés) et à l'accélération.
	SPRINT_LEAN = 14,
	-- Respiration au repos : amplitude (degrés) et période (s).
	IDLE_BREATH_ANGLE = 1.6,
	IDLE_BREATH_PERIOD = 3.4,
})
