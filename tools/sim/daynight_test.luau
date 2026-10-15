-- Cycle jour / nuit (simulation, hors Roblox) : durées réelles, continuité de l'heure, nuit jouable.
-- Usage : tools/sim/run.sh daynight_test
local mock = require("./mock")
local env = require("./bundle_out")(mock)
local WorldConfig = env.require("ReplicatedStorage/Shared/World/WorldConfig")
local LightingPresets = env.require("StarterPlayer/StarterPlayerScripts/Client/World/LightingPresets")

local failures = 0
local function check(label, ok, detail)
	print(string.format("  %s  %s%s", if ok then "OK  " else "ÉCHEC", label, if detail ~= nil then " (" .. tostring(detail) .. ")" else ""))
	if not ok then
		failures += 1
	end
end

local cycle = WorldConfig.DAY_REAL_SECONDS + WorldConfig.NIGHT_REAL_SECONDS
print("== Durées")
check("cycle complet entre 35 et 40 min réelles", cycle >= 35 * 60 and cycle <= 40 * 60, cycle / 60 .. " min")
check("le jour dure bien plus longtemps que la nuit", WorldConfig.DAY_REAL_SECONDS >= 2 * WorldConfig.NIGHT_REAL_SECONDS)

print("== Continuité de l'heure (pas de saut)")
local maxStep, step = 0, 1
local previous = WorldConfig.clockTimeAt(0)
local dayTime, nightTime = 0, 0
for t = step, cycle * 2, step do
	local clock = WorldConfig.clockTimeAt(t)
	local delta = (clock - previous) % 24
	maxStep = math.max(maxStep, delta)
	if clock >= WorldConfig.NIGHT_START or clock < WorldConfig.NIGHT_END then
		nightTime += step
	else
		dayTime += step
	end
	previous = clock
end
check("l'heure avance toujours, sans saut (max " .. string.format("%.3f", maxStep) .. " h/s)", maxStep > 0 and maxStep < 0.05)
check("temps réel de jour mesuré ≈ DAY_REAL_SECONDS", math.abs(dayTime / 2 - WorldConfig.DAY_REAL_SECONDS) <= 2, dayTime / 2)
check("temps réel de nuit mesuré ≈ NIGHT_REAL_SECONDS", math.abs(nightTime / 2 - WorldConfig.NIGHT_REAL_SECONDS) <= 2, nightTime / 2)

print("== Nuit jouable (clair de lune)")
local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end
local night = LightingPresets.atClockTime(1)
local day = LightingPresets.atClockTime(12)
local nightOutdoor = luminance(night.Lighting.OutdoorAmbient)
local dayOutdoor = luminance(day.Lighting.OutdoorAmbient)
check("lumière extérieure de nuit ≥ 70 % de celle du jour", nightOutdoor >= 0.7 * dayOutdoor, string.format("%.2f / %.2f", nightOutdoor, dayOutdoor))
check("exposition de nuit positive", night.Lighting.ExposureCompensation > 0)
check("brouillard de nuit pas plus dense que le jour", night.Atmosphere.Density <= day.Atmosphere.Density + 0.01)
local a, b = LightingPresets.atClockTime(1), LightingPresets.atClockTime(1)
a.Lighting.Brightness *= 0.5
check("atClockTime rend une table neuve (aucune correction cumulée d'une image à l'autre)", b.Lighting.Brightness == LightingPresets.atClockTime(1).Lighting.Brightness)

print(if failures == 0 then "\nTOUT OK" else "\n" .. failures .. " ÉCHEC(S)")
