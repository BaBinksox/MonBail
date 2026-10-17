--!strict
--[[
	AvatarAudit (ModuleScript partagé)
	Vérifie DANS STUDIO les assets du catalogue Roblox dont dépend l'apparence (coiffures, tenues
	historiques, capes) : existence, nom, créateur et type enregistrés chez Roblox. Les tenues et
	ornements fabriqués (GarmentLibrary) n'en ont pas besoin : ils n'utilisent aucun asset.

	Barre de commande de Studio :
		require(game.ReplicatedStorage.Shared.Avatar.AvatarAudit).run()
	Le rapport s'affiche dans la Sortie (quelques secondes). Rien n'est modifié.
]]

local MarketplaceService = game:GetService("MarketplaceService")

local AvatarConfig = require(script.Parent:WaitForChild("AvatarConfig") :: ModuleScript)

-- Types d'asset Roblox attendus (Enum.AssetType : valeurs numériques).
local EXPECTED_TYPE: { [string]: { number } } = {
	hair = { 41, 8 }, -- HairAccessory (ou ancien chapeau)
	shirt = { 11 },
	pants = { 12 },
	back = { 46, 8 }, -- BackAccessory (ou ancien chapeau)
}

local AvatarAudit = {}

type Item = { kind: string, label: string, id: number }

local function items(): { Item }
	local list: { Item } = {}
	for _, hair in AvatarConfig.HAIR_OPTIONS do
		table.insert(list, { kind = "hair", label = `coiffure {hair.id} « {hair.name} »`, id = hair.assetId })
	end
	for _, outfit in AvatarConfig.OUTFIT_OPTIONS do
		if outfit.garment == nil then
			table.insert(list, { kind = "shirt", label = `tenue {outfit.id} (Shirt)`, id = outfit.shirtId })
			table.insert(list, { kind = "pants", label = `tenue {outfit.id} (Pants)`, id = outfit.pantsId })
			if outfit.backAccessoryId > 0 then
				table.insert(list, { kind = "back", label = `tenue {outfit.id} (cape)`, id = outfit.backAccessoryId })
			end
		end
	end
	return list
end

function AvatarAudit.run()
	local list = items()
	print(`==== AvatarAudit : {#list} assets du catalogue ====`)
	task.spawn(function()
		local okCount = 0
		for _, item in list do
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(item.id, Enum.InfoType.Asset)
			end)
			if ok and type(info) == "table" then
				local expected = EXPECTED_TYPE[item.kind] or {}
				local typeOk = table.find(expected, info.AssetTypeId) ~= nil
				local creator = if type(info.Creator) == "table" then info.Creator.Name else "?"
				if typeOk then
					okCount += 1
				end
				print(string.format("[%s] %d : « %s » par %s, type %s%s", item.label, item.id, tostring(info.Name), tostring(creator), tostring(info.AssetTypeId), if typeOk then "" else " (TYPE INATTENDU)"))
			else
				print(string.format("[%s] %d : INTROUVABLE (%s)", item.label, item.id, tostring(info)))
			end
			task.wait(0.05)
		end
		print(`==== Fin : {okCount} / {#list} conformes. Vérifiez aussi l'affichage en jeu (Play). ====`)
	end)
end

return AvatarAudit
