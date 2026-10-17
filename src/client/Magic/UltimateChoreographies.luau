--!strict
--[[
	UltimateChoreographies (ModuleScript, client)
	Mises en scène des techniques ultimes, enregistrées dans CombatEffects (registerUltimate) par
	CombatController. Magies 3.0 : chaque chorégraphie vit dans le module de sa magie
	(Client/Magic/Vfx/<Magie>.luau), avec les effets de ses deux sorts. Toutes suivent le rythme du
	serveur : préparation de `magic.ultimateWindup` secondes, impact au moment exact des dégâts,
	puis disparition progressive.

		ice        « Hiver Éternel »         Vfx/Ice
		antimatter « Rupture du Néant »      Vfx/Antimatter
		pyromancy  « Brasier du Parjure »    Vfx/Pyromancy
		lightning  « Jugement Céleste »      Vfx/Lightning
		shadow     « Marée d'Ombres »        Vfx/Shadow
		gravity    « Effondrement Stellaire » Vfx/Gravity
]]

local vfxFolder = script.Parent:WaitForChild("Vfx")

local function ultimateOf(moduleName: string): (caster: Model?, origin: Vector3, targets: { Model }, magic: any) -> ()
	local module = require(vfxFolder:WaitForChild(moduleName) :: ModuleScript) :: any
	return module.ultimate
end

local UltimateChoreographies = {
	ice = ultimateOf("Ice"),
	antimatter = ultimateOf("Antimatter"),
	pyromancy = ultimateOf("Pyromancy"),
	lightning = ultimateOf("Lightning"),
	shadow = ultimateOf("Shadow"),
	gravity = ultimateOf("Gravity"),
}

return UltimateChoreographies
