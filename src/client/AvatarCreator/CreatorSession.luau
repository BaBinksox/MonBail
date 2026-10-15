--!strict
--[[
	CreatorSession
	État du créateur de personnage partagé avec les autres scripts du client, pour qu'ils ne se
	marchent pas dessus pendant les passages de relais (caméra, écran noir).
	Un seul écrivain : AvatarCreatorController. Lecteur actuel : World/ArrivalController.

		CreatorSession.isActive()             vrai de l'ouverture du créateur jusqu'à la FIN du nettoyage
		                                      de sa fermeture (caméra rendue, écran noir confié au voile
		                                      partagé de Theme)
		CreatorSession.onClosed(fn)           fn() quand cette fermeture est terminée
		CreatorSession.waitUntilClosed(t)     YIELD jusqu'à la fin de la fermeture (t secondes au plus)
		CreatorSession.setArrivalBusy(bool)   posé par ArrivalController pendant la cinématique d'arrivée
		CreatorSession.isArrivalBusy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local POLL_INTERVAL = 0.05

local CreatorSession = {}

local isCreatorActive = false
local isArrivalPlaying = false
local closed = Signal.new()

function CreatorSession.isActive(): boolean
	return isCreatorActive
end

-- Réservé à AvatarCreatorController.
function CreatorSession.setActive(active: boolean)
	if isCreatorActive == active then
		return
	end
	isCreatorActive = active
	if not active then
		closed:Fire()
	end
end

function CreatorSession.onClosed(callback: () -> ()): Signal.Connection
	return closed:Connect(callback)
end

-- YIELD : attend que le créateur ait fini de se fermer, `timeout` secondes au plus.
-- Retourne true s'il est fermé.
function CreatorSession.waitUntilClosed(timeout: number): boolean
	local deadline = os.clock() + timeout
	while isCreatorActive and os.clock() < deadline do
		task.wait(POLL_INTERVAL)
	end
	return not isCreatorActive
end

-- Réservé à ArrivalController : la cinématique d'arrivée tient l'écran (et la caméra).
function CreatorSession.setArrivalBusy(busy: boolean)
	isArrivalPlaying = busy
end

function CreatorSession.isArrivalBusy(): boolean
	return isArrivalPlaying
end

return CreatorSession
