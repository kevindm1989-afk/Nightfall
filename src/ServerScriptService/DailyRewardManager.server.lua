--!strict
--------------------------------------------------------------------------------
-- DailyRewardManager
-- ServerScriptService.DailyRewardManager (Script)
--
-- 7-day login streak (GameConfig.DailyRewards):
--   * Claimable every 20 hours (a friendly "daily" that tolerates schedule
--     drift instead of punishing it).
--   * Streak resets if the player stays away longer than 48 hours.
--   * Gold rewards scale x(1 + Rebirths) so the streak matters at every
--     progression stage; day 7 pays out a free Royal Egg hatch.
--
-- Retention is the cheapest monetization lever in the game: players who come
-- back daily are the ones who eventually buy gamepasses.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()
local PetSystem = require(script.Parent:WaitForChild("PetSystem")).Init()

local COOLDOWN = GameConfig.DailyRewardCooldown
local STREAK_BREAK = GameConfig.DailyRewardStreakBreak
local MAX_DAY = #GameConfig.DailyRewards

Remotes.ClaimDaily.OnServerInvoke = function(player: Player)
	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end

	local now = os.time()
	local sinceLast = now - data.LastDailyClaim

	if data.LastDailyClaim > 0 and sinceLast < COOLDOWN then
		local remaining = COOLDOWN - sinceLast
		local hours = math.floor(remaining / 3600)
		local minutes = math.floor((remaining % 3600) / 60)
		return false, ("Next reward in %dh %dm."):format(hours, minutes)
	end

	-- Advance or reset the streak, cycling back to day 1 after day 7.
	if data.LastDailyClaim > 0 and sinceLast <= STREAK_BREAK then
		data.DailyStreak = (data.DailyStreak % MAX_DAY) + 1
	else
		data.DailyStreak = 1
	end
	data.LastDailyClaim = now

	local reward = GameConfig.DailyRewards[data.DailyStreak]
	local payload = { Day = data.DailyStreak, Gold = 0, Gems = 0, EggRoll = nil }

	if reward.Gold then
		local scaled = math.floor(reward.Gold * (1 + data.Rebirths))
		DataManager.AddGold(player, scaled)
		payload.Gold = scaled
	end
	if reward.Gems then
		DataManager.AddGems(player, reward.Gems)
		payload.Gems = reward.Gems
	end
	if reward.EggRoll then
		payload.EggRoll = reward.EggRoll
		task.spawn(function()
			PetSystem.HatchEgg(player, reward.EggRoll, true)
		end)
	end

	DataManager.PushToClient(player)
	Remotes.NotifyText:FireClient(player,
		("Day %d streak reward claimed!"):format(data.DailyStreak),
		Color3.fromRGB(120, 255, 140))
	return true, payload
end

print("[DailyRewardManager] Online. " .. MAX_DAY .. "-day streak cycle.")
