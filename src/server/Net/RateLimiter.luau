--!strict
--[[
	RateLimiter
	Limite de fréquence des requêtes client sensibles (seau à jetons, par joueur et par clé).

		local limiter = RateLimiter.new(2, 4) -- 2 requêtes / s en moyenne, rafale de 4 au plus
		if not limiter:allow(player) then return end           -- un seul compteur par joueur
		if not limiter:allow(player, "accept") then return end -- ou un compteur par action

	Un client qui inonde le serveur voit ses requêtes excédentaires ignorées (sans message : un client
	honnête n'atteint jamais la limite). Les joueurs partis sont oubliés automatiquement (clés faibles).
]]

type Bucket = {
	tokens: number,
	updatedAt: number, -- os.clock()
}

local DEFAULT_KEY = "_"

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type LimiterData = {
	_rate: number, -- jetons regagnés par seconde
	_burst: number, -- jetons maximum
	_buckets: { [Player]: { [string]: Bucket } },
}

export type RateLimiter = typeof(setmetatable({} :: LimiterData, RateLimiter))

function RateLimiter.new(ratePerSecond: number, burst: number): RateLimiter
	local data: LimiterData = {
		_rate = ratePerSecond,
		_burst = burst,
		_buckets = setmetatable({}, { __mode = "k" }) :: any,
	}
	return setmetatable(data, RateLimiter)
end

-- true si `player` peut faire une requête maintenant (et consomme un jeton).
function RateLimiter.allow(self: RateLimiter, player: Player, key: string?): boolean
	local perPlayer = self._buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		self._buckets[player] = perPlayer
	end
	local bucketKey = key or DEFAULT_KEY
	local now = os.clock()
	local bucket = perPlayer[bucketKey]
	if bucket == nil then
		bucket = { tokens = self._burst, updatedAt = now }
		perPlayer[bucketKey] = bucket
	end

	bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.updatedAt) * self._rate)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

return RateLimiter
