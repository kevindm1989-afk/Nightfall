--!strict
--------------------------------------------------------------------------------
-- GameSignals
-- ServerScriptService.GameSignals (ModuleScript)
--
-- Zero-dependency server event bus. Gameplay systems FIRE facts about what
-- happened; interested systems (QuestManager, future badges/analytics) LISTEN.
-- Keeps CoreEngine/DataManager free of any knowledge of quests.
--
--   GameSignals.NodeBroken:Fire(player)
--   GameSignals.EnemyKilled:Fire(player)
--   GameSignals.BossKilled:Fire(player)
--   GameSignals.PetObtained:Fire(player, petName)
--   GameSignals.GoldEarned:Fire(player, amount)
--------------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	table.insert(self._handlers, handler)
	local handlers = self._handlers
	return {
		Disconnect = function()
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
end

function Signal:Fire(...: any)
	for _, handler in ipairs(self._handlers) do
		task.spawn(handler, ...)
	end
end

local GameSignals = {
	NodeBroken = Signal.new(),
	EnemyKilled = Signal.new(),
	BossKilled = Signal.new(),
	PetObtained = Signal.new(),  -- (player, petName)
	GoldEarned = Signal.new(),   -- (player, amount)
	Rebirthed = Signal.new(),    -- (player, rebirthCount)
	ZoneUnlocked = Signal.new(), -- (player, zoneId)
	PetFused = Signal.new(),     -- (player, petName, variant)
}

return GameSignals
