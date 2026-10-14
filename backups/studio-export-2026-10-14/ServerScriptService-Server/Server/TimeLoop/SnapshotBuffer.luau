--!strict
--[[
	SnapshotBuffer
	Buffer circulaire de taille fixe : quand il est plein, le snapshot le plus ancien est écrasé.
	Mémoire bornée et push/pop en O(1), contrairement à table.insert/table.remove(t, 1).

	Les offsets comptent depuis le plus récent : peek(0) = dernier snapshot, peek(1) = l'avant-dernier.
]]

local EntitySnapshot = require(script.Parent.EntitySnapshot)

type Snapshot = EntitySnapshot.Snapshot

local SnapshotBuffer = {}
SnapshotBuffer.__index = SnapshotBuffer

type BufferData = {
	_slots: { Snapshot? },
	_capacity: number,
	_newestSlot: number, -- index (1..capacity) du snapshot le plus récent
	_count: number,
}

export type SnapshotBuffer = typeof(setmetatable({} :: BufferData, SnapshotBuffer))

function SnapshotBuffer.new(capacity: number): SnapshotBuffer
	assert(capacity >= 1, "SnapshotBuffer: la capacité doit être >= 1")

	local data: BufferData = {
		_slots = table.create(capacity),
		_capacity = capacity,
		_newestSlot = 0,
		_count = 0,
	}
	return setmetatable(data, SnapshotBuffer)
end

function SnapshotBuffer.push(self: SnapshotBuffer, snapshot: Snapshot)
	self._newestSlot = self._newestSlot % self._capacity + 1
	self._slots[self._newestSlot] = snapshot
	self._count = math.min(self._count + 1, self._capacity)
end

function SnapshotBuffer.peek(self: SnapshotBuffer, offset: number): Snapshot?
	if offset < 0 or offset >= self._count then
		return nil
	end
	local slot = (self._newestSlot - 1 - offset) % self._capacity + 1
	return self._slots[slot]
end

function SnapshotBuffer.peekOldest(self: SnapshotBuffer): Snapshot?
	return self:peek(self._count - 1)
end

-- Retire et retourne le snapshot le plus récent (c'est ce qui "consomme" l'historique pendant un rewind).
function SnapshotBuffer.popNewest(self: SnapshotBuffer): Snapshot?
	if self._count == 0 then
		return nil
	end
	local snapshot = self._slots[self._newestSlot]
	self._slots[self._newestSlot] = nil
	self._newestSlot = (self._newestSlot - 2) % self._capacity + 1
	self._count -= 1
	return snapshot
end

return SnapshotBuffer
