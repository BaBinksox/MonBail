--!strict
--[[
	AvatarSerializer
	Les deux conversions de données du Hub. Fonctions pures : aucune instance, aucun état.

	1. Client -> serveur : sanitizeSelection()
	   Ce que le client envoie n'est jamais fiable. On reconstruit un Selection à partir de ses
	   données en vérifiant chaque index et en bornant chaque échelle.

	2. Serveur <-> sauvegarde : toSaved() / fromSaved()
	   En jeu, un choix est un INDEX dans une liste d'AvatarConfig. Dans la sauvegarde, c'est
	   l'`id` de l'option : ainsi on peut ajouter des coiffures ou réordonner les listes sans
	   fausser les personnages déjà sauvegardés.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AvatarConfig = require(ReplicatedStorage.Shared.Avatar.AvatarConfig)
local MagicConfig = require(ReplicatedStorage.Shared.Magic.MagicConfig)
local RaceConfig = require(ReplicatedStorage.Shared.Avatar.RaceConfig)

type Selection = AvatarConfig.Selection
type ScaleRange = AvatarConfig.ScaleRange

-- Forme du champ `avatar` d'un profil sauvegardé.
export type SavedAvatar = {
	base: string,
	face: string,
	mark: string,
	hair: string,
	outfit: string,
	magic: string,
	height: number,
	width: number,
	race: string, -- ajouté en v3 du profil ; absent = RaceConfig.DEFAULT_RACE_ID
	skin: string, -- ajouté en v3 ; absent = "native" (teint de l'avatar Roblox, comme avant)
}

local AvatarSerializer = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function sanitizeIndex(value: any, optionCount: number): number?
	if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > optionCount then
		return nil
	end
	return value
end

local function sanitizeScale(value: any, range: ScaleRange): number?
	if type(value) ~= "number" or value ~= value then -- value ~= value : NaN
		return nil
	end
	return math.clamp(value, range.min, range.max)
end

-- Index de l'option d'identifiant `id` dans `options`, ou 1 (la première) si elle n'existe plus.
local function findIndexById(options: { any }, id: any): number
	for index, option in options do
		if option.id == id then
			return index
		end
	end
	return 1
end

--------------------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------------------

-- Reconstruit un Selection sûr à partir de ce que le client a envoyé, ou nil si c'est invalide.
function AvatarSerializer.sanitizeSelection(raw: any): Selection?
	if type(raw) ~= "table" then
		return nil
	end

	local baseIndex = sanitizeIndex(raw.baseIndex, #AvatarConfig.BASE_OPTIONS)
	local faceIndex = sanitizeIndex(raw.faceIndex, #AvatarConfig.FACE_OPTIONS)
	local markIndex = sanitizeIndex(raw.markIndex, #AvatarConfig.MARK_OPTIONS)
	local hairIndex = sanitizeIndex(raw.hairIndex, #AvatarConfig.HAIR_OPTIONS)
	local outfitIndex = sanitizeIndex(raw.outfitIndex, #AvatarConfig.OUTFIT_OPTIONS)
	local magicIndex = sanitizeIndex(raw.magicIndex, #MagicConfig.MAGICS)
	local heightScale = sanitizeScale(raw.heightScale, AvatarConfig.HEIGHT_SCALE)
	local widthScale = sanitizeScale(raw.widthScale, AvatarConfig.WIDTH_SCALE)
	local raceIndex = sanitizeIndex(raw.raceIndex, #RaceConfig.RACES)
	local skinIndex = sanitizeIndex(raw.skinIndex, #AvatarConfig.SKIN_TONES)
	if
		baseIndex == nil
		or faceIndex == nil
		or markIndex == nil
		or hairIndex == nil
		or outfitIndex == nil
		or magicIndex == nil
		or heightScale == nil
		or widthScale == nil
		or raceIndex == nil
		or skinIndex == nil
	then
		return nil
	end

	return {
		baseIndex = baseIndex,
		faceIndex = faceIndex,
		markIndex = markIndex,
		hairIndex = hairIndex,
		outfitIndex = outfitIndex,
		magicIndex = magicIndex,
		heightScale = heightScale,
		widthScale = widthScale,
		raceIndex = raceIndex,
		skinIndex = skinIndex,
	}
end

-- Selection (index) -> données à écrire dans le profil (id).
function AvatarSerializer.toSaved(selection: Selection): SavedAvatar
	return {
		base = AvatarConfig.BASE_OPTIONS[selection.baseIndex].id,
		face = AvatarConfig.FACE_OPTIONS[selection.faceIndex].id,
		mark = AvatarConfig.MARK_OPTIONS[selection.markIndex].id,
		hair = AvatarConfig.HAIR_OPTIONS[selection.hairIndex].id,
		outfit = AvatarConfig.OUTFIT_OPTIONS[selection.outfitIndex].id,
		magic = MagicConfig.MAGICS[selection.magicIndex].id,
		height = selection.heightScale,
		width = selection.widthScale,
		race = RaceConfig.RACES[selection.raceIndex].id,
		skin = AvatarConfig.SKIN_TONES[selection.skinIndex].id,
	}
end

-- Données lues dans le profil -> Selection, ou nil si le joueur n'a encore rien sauvegardé.
-- Une option qui n'existe plus dans le catalogue est remplacée par la première de sa liste.
function AvatarSerializer.fromSaved(saved: any): Selection?
	if type(saved) ~= "table" then
		return nil
	end

	return {
		baseIndex = findIndexById(AvatarConfig.BASE_OPTIONS, saved.base),
		faceIndex = findIndexById(AvatarConfig.FACE_OPTIONS, saved.face),
		markIndex = findIndexById(AvatarConfig.MARK_OPTIONS, saved.mark),
		hairIndex = findIndexById(AvatarConfig.HAIR_OPTIONS, saved.hair),
		outfitIndex = findIndexById(AvatarConfig.OUTFIT_OPTIONS, saved.outfit),
		magicIndex = findIndexById(MagicConfig.MAGICS, saved.magic),
		heightScale = sanitizeScale(saved.height, AvatarConfig.HEIGHT_SCALE) or AvatarConfig.HEIGHT_SCALE.default,
		widthScale = sanitizeScale(saved.width, AvatarConfig.WIDTH_SCALE) or AvatarConfig.WIDTH_SCALE.default,
		-- Personnages créés avant les peuples et les teints : humain, teint de l'avatar (inchangés).
		raceIndex = RaceConfig.indexOf(saved.race or RaceConfig.DEFAULT_RACE_ID),
		skinIndex = findIndexById(AvatarConfig.SKIN_TONES, saved.skin or "native"),
	}
end

return AvatarSerializer
