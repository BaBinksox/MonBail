--!strict
--[[
	Props
	Point d'entrée unique de tous les props paramétrés (façade de PropsBuildings, PropsVillage et
	PropsNature). Les zones peuvent utiliser `context.Props.<nom>` ou requérir les sous-modules.

	Convention commune : `base` est un CFrame LOCAL (repère de RegionConfig.LAYOUT) posé AU SOL,
	LookVector = l'avant du prop. `random` = context.random (même graine, même carte).
	Signatures détaillées : voir l'en-tête de chaque sous-module.
]]

local PropsBuildings = require(script.Parent.PropsBuildings)
local PropsNature = require(script.Parent.PropsNature)
local PropsVillage = require(script.Parent.PropsVillage)

export type HouseOptions = PropsBuildings.HouseOptions
export type HouseResult = PropsBuildings.HouseResult
export type Opening = PropsBuildings.Opening
export type TreeOptions = PropsNature.TreeOptions
export type LanternOptions = PropsVillage.LanternOptions
export type BrazierOptions = PropsVillage.BrazierOptions
export type FenceOptions = PropsVillage.FenceOptions
export type TombVariant = PropsVillage.TombVariant

return table.freeze({
	-- Architecture
	house = PropsBuildings.house, -- maison à colombages intacte / délabrée / effondrée
	gableRoof = PropsBuildings.gableRoof,
	gable = PropsBuildings.gable,
	panelWall = PropsBuildings.panelWall,
	ruinedWall = PropsBuildings.ruinedWall, -- mur écroulé
	archway = PropsBuildings.archway, -- arche plein cintre ou gothique
	stairs = PropsBuildings.stairs, -- marches de 1 stud max
	ramp = PropsBuildings.ramp,
	pillar = PropsBuildings.pillar,
	chimney = PropsBuildings.chimney,

	-- Nature
	deadTree = PropsNature.deadTree, -- arbre mort tordu
	rock = PropsNature.rock,
	rockCluster = PropsNature.rockCluster,
	deadBush = PropsNature.deadBush,
	stump = PropsNature.stump,
	log = PropsNature.log,

	-- Village
	barrel = PropsVillage.barrel,
	crate = PropsVillage.crate,
	chest = PropsVillage.chest, -- retourne (Model, caisse à viser)
	cart = PropsVillage.cart, -- chariot (renversé possible)
	bench = PropsVillage.bench,
	tableSet = PropsVillage.tableSet,
	woodpile = PropsVillage.woodpile,
	sack = PropsVillage.sack,
	anvil = PropsVillage.anvil,
	trough = PropsVillage.trough,
	lanternPost = PropsVillage.lanternPost, -- lanterne sur poteau
	hangingLantern = PropsVillage.hangingLantern,
	brazier = PropsVillage.brazier, -- brasero (allumé ou éteint : état initial des dynamics "light")
	candles = PropsVillage.candles,
	fence = PropsVillage.fence, -- clôture brisée
	palisade = PropsVillage.palisade,
	tomb = PropsVillage.tomb,
	flowers = PropsVillage.flowers,
	brokenPillar = PropsVillage.brokenPillar, -- pilier brisé
	rubble = PropsVillage.rubble,
	charredBeams = PropsVillage.charredBeams, -- poutres calcinées
	ashPile = PropsVillage.ashPile,
	signPost = PropsVillage.signPost, -- panneau avec SurfaceGui
	noticeBoard = PropsVillage.noticeBoard, -- retourne (Model, panneau à viser)
	hangingSign = PropsVillage.hangingSign,
	banner = PropsVillage.banner,
	clock = PropsVillage.clock, -- horloge arrêtée sur 3 h 17 ; retourne (Model, cadran)
	graffiti = PropsVillage.graffiti,
	clawMarks = PropsVillage.clawMarks,
	laundryLine = PropsVillage.laundryLine,
	weaponRack = PropsVillage.weaponRack,
	trainingDummy = PropsVillage.trainingDummy,
})
