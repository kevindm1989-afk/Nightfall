--!strict
--------------------------------------------------------------------------------
-- OfflineEarningsManager
-- ServerScriptService.OfflineEarningsManager (Script)
--
-- The welcome-back hook. On join:
--   1. Reads the profile's LastLogout stamp (written by DataManager on leave).
--   2. Pays Gold for time away: GoldPerMinuteByZone[best unlocked zone]
--      x (1 + 0.5 x Rebirths), capped at Offline.CapHours.
--   3. Banks the same amount into PendingOfflineBonus and fires OfflineReport
--      so the client shows the "DOUBLE IT" popup — the single highest-margin
--      contextual product in the genre (the player just SAW the money).
--
-- The 2x purchase itself is fulfilled by MonetizationManager's OfflineDouble
-- product handler, which grants PendingOfflineBonus and zeroes it.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()

local function bestUnlockedZone(data: any): number
	local best = 1
	for zoneId in pairs(GameConfig.Zones) do
		local unlocked = data.UnlockedZones[zoneId] or data.UnlockedZones[tostring(zoneId)]
		if unlocked and zoneId > best then
			best = zoneId
		end
	end
	return best
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local data = DataManager.Get(player)
		if not data then
			return
		end

		if data.LastLogout <= 0 then
			return -- first ever session
		end

		local awaySeconds = os.time() - data.LastLogout
		local awayMinutes = awaySeconds / 60
		if awayMinutes < GameConfig.Offline.MinimumMinutes then
			return
		end
		awayMinutes = math.min(awayMinutes, GameConfig.Offline.CapHours * 60)

		local zone = bestUnlockedZone(data)
		local ratePerMinute = GameConfig.Offline.GoldPerMinuteByZone[zone] or 0
		local earned = math.floor(awayMinutes * ratePerMinute * (1 + 0.5 * data.Rebirths))
		if earned <= 0 then
			return
		end

		DataManager.AddGold(player, earned)
		data.PendingOfflineBonus = earned
		DataManager.PushToClient(player)

		Remotes.OfflineReport:FireClient(player, {
			Amount = earned,
			AwayMinutes = math.floor(awayMinutes),
			ProductId = GameConfig.DeveloperProducts.OfflineDouble.Id,
		})
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("[OfflineEarningsManager] Online. Cap: " .. GameConfig.Offline.CapHours .. "h")
