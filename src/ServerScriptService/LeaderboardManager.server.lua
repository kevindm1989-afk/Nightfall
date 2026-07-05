--!strict
--------------------------------------------------------------------------------
-- LeaderboardManager
-- ServerScriptService.LeaderboardManager (Script)
--
-- Global OrderedDataStore leaderboards (Richest Players / Most Rebirths):
--   * Uploads every online player's stats every RefreshSeconds (and once more
--     when they leave).
--   * Pulls the global top-N on the same cadence and caches it; the client
--     RemoteFunction only ever reads the cache, so it can't be used to
--     hammer DataStores.
--
-- Social proof drives spending: seeing a whale at 40B gold on the board is
-- the best advertisement the coin packs will ever get.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()

local REFRESH_SECONDS = GameConfig.Leaderboards.RefreshSeconds
local TOP_N = GameConfig.Leaderboards.TopN

-- [boardKey] = OrderedDataStore
local stores: { [string]: OrderedDataStore } = {}
for _, board in ipairs(GameConfig.Leaderboards.Boards) do
	stores[board.Key] = DataStoreService:GetOrderedDataStore(board.Store)
end

-- [boardKey] = { {Name = string, Value = number}, ... } — served to clients.
local cachedTop: { [string]: { any } } = {}
local nameCache: { [number]: string } = {}

local function usernameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = ok and name or ("User " .. userId)
	nameCache[userId] = resolved
	return resolved
end

local function uploadPlayer(player: Player)
	local data = DataManager.GetLoaded(player)
	if not data then
		return
	end
	for _, board in ipairs(GameConfig.Leaderboards.Boards) do
		local value = data[board.Stat]
		if type(value) == "number" and value > 0 then
			local store = stores[board.Key]
			pcall(function()
				-- OrderedDataStores only take positive integers.
				store:SetAsync(tostring(player.UserId), math.floor(value))
			end)
		end
	end
end

local function refreshTops()
	for _, board in ipairs(GameConfig.Leaderboards.Boards) do
		local store = stores[board.Key]
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, TOP_N)
		end)
		if ok and pages then
			local top = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(top, {
						Name = usernameFor(userId),
						Value = entry.value,
					})
				end
			end
			cachedTop[board.Key] = top
		end
	end
end

Remotes.GetLeaderboard.OnServerInvoke = function(_player: Player)
	local result = {}
	for _, board in ipairs(GameConfig.Leaderboards.Boards) do
		result[board.Key] = {
			Title = board.Title,
			Entries = cachedTop[board.Key] or {},
		}
	end
	return result
end

Players.PlayerRemoving:Connect(function(player)
	task.spawn(uploadPlayer, player)
end)

task.spawn(function()
	task.wait(10) -- let first profiles load before the first upload
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(uploadPlayer, player)
			task.wait(0.5) -- stay well inside OrderedDataStore write budgets
		end
		refreshTops()
		task.wait(REFRESH_SECONDS)
	end
end)

print("[LeaderboardManager] Online.")
