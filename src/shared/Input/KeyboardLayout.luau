--!strict
--[[
	KeyboardLayout
	Désigner une touche par la LETTRE imprimée dessus, quelle que soit la disposition du clavier.
	À n'appeler que depuis un client (il lit le clavier du joueur).

	Pourquoi : un Enum.KeyCode de Roblox ne désigne pas une lettre mais un EMPLACEMENT physique,
	nommé d'après le clavier américain (QWERTY). Sur un clavier AZERTY :
		- la touche marquée "M" est à l'emplacement du ";" américain : elle envoie KeyCode.Semicolon ;
		- KeyCode.M, lui, correspond à la touche marquée "," ;
		- même décalage pour A/Q et Z/W. (R, E, F ou Maj sont au même endroit partout : aucun souci.)
	Tester `input.KeyCode == Enum.KeyCode.M` ne réagit donc jamais à la touche M d'un clavier français.
]]

local UserInputService = game:GetService("UserInputService")

local KeyboardLayout = {}

-- Ce qui est imprimé sur la touche `keyCode` du clavier de ce joueur, en majuscules.
-- "" si Roblox ne sait pas le dire (touche sans caractère, manette...).
function KeyboardLayout.getLabel(keyCode: Enum.KeyCode): string
	local isKnown, label = pcall(function()
		return UserInputService:GetStringForKeyCode(keyCode)
	end)
	return if isKnown and type(label) == "string" then string.upper(label) else ""
end

-- Vrai si `keyCode` (la touche qui vient d'être pressée) est celle marquée `letter`.
-- `fallback` : KeyCode utilisé à la place si la disposition du clavier est illisible.
function KeyboardLayout.isLetter(keyCode: Enum.KeyCode, letter: string, fallback: Enum.KeyCode): boolean
	local label = KeyboardLayout.getLabel(keyCode)
	if label == "" then
		return keyCode == fallback
	end
	return label == string.upper(letter)
end

-- KeyCode de la touche marquée `letter` sur ce clavier (pour un BindAction, par exemple).
-- Retourne `fallback` si aucune touche ne porte cette lettre.
function KeyboardLayout.findKeyCode(letter: string, fallback: Enum.KeyCode): Enum.KeyCode
	local target = string.upper(letter)
	for _, keyCode in Enum.KeyCode:GetEnumItems() do
		if KeyboardLayout.getLabel(keyCode) == target then
			return keyCode
		end
	end
	return fallback
end

return KeyboardLayout
