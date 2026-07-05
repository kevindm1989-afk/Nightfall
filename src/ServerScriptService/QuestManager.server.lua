--!strict
--------------------------------------------------------------------------------
-- QuestManager
-- ServerScriptService.QuestManager (Script)
--
-- Three session-shaping systems in one manager:
--
--   1. DAILY QUESTS — 3 per UTC day from GameConfig.QuestPool, chosen with a
--      deterministic seed (UserId + day key) so rejoining can never reroll
--      them. Progress is driven entirely by GameSignals (NodeBroken,
--      EnemyKilled, BossKilled, PetObtained, GoldEarned); rewards claim
--      through Remotes.ClaimQuest with gold scaled x(1 + Rebirths).
--
--   2. PLAYTIME CHESTS — a per-session reward track (5→60 minutes) claimed
--      through Remotes.ClaimPlaytime; elapsed time is validated server-side.
--
--   3. GROUP REWARD — members of GameConfig.Group.GroupId receive DailyGems
--      once per 24h automatically on join (the +10% coin bonus lives in
--      CoreEngine's payout path).
--
-- Progress pushes to the client are debounced to at most one snapshot per
-- second per player, so gold-quest spam can't flood the network.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()
local PetSystem = require(script.Parent:WaitForChild("PetSystem")).Init()
local GameSignals = require(script.Parent:WaitForChild("GameSignals"))

--------------------------------------------------------------------------------
-- DAILY QUESTS
--------------------------------------------------------------------------------
local function todayKey(): string
	local now = os.date("!*t") -- UTC so every player rotates at the same moment
	return ("%d-%03d"):format(now.year, now.yday)
end

local function rollQuestsFor(player: Player, data: any)
	local key = todayKey()
	if data.DailyQuests.Key == key and #data.DailyQuests.Quests > 0 then
		return -- today's quests already rolled
	end

	-- Deterministic pick: same player + same day = same quests, always.
	local seed = player.UserId + tonumber((todayKey():gsub("%-", ""))) :: number
	local rng = Random.new(seed)

	local pool = table.clone(GameConfig.QuestPool)
	local quests = {}
	for _ = 1, math.min(GameConfig.QuestsPerDay, #pool) do
		local index = rng:NextInteger(1, #pool)
		local template = table.remove(pool, index)
		table.insert(quests, {
			Id = template.Id,
			Type = template.Type,
			Goal = template.Goal,
			Text = template.Text:format(template.Goal),
			Gold = template.Gold,
			Gems = template.Gems,
			Progress = 0,
			Claimed = false,
		})
	end

	data.DailyQuests = { Key = key, Quests = quests }
end

-- Debounced snapshot pushes: progress events can arrive many times a second.
local pushPending: { [Player]: boolean } = {}

local function schedulePush(player: Player)
	if pushPending[player] then
		return
	end
	pushPending[player] = true
	task.delay(1, function()
		pushPending[player] = nil
		if player.Parent then
			DataManager.PushToClient(player)
		end
	end)
end

local function addProgress(player: Player, questType: string, amount: number)
	local data = DataManager.GetLoaded(player)
	if not data then
		return
	end
	rollQuestsFor(player, data)

	local changed = false
	for _, quest in ipairs(data.DailyQuests.Quests) do
		if quest.Type == questType and not quest.Claimed and quest.Progress < quest.Goal then
			local before = quest.Progress
			quest.Progress = math.min(quest.Goal, quest.Progress + amount)
			changed = true
			if before < quest.Goal and quest.Progress >= quest.Goal then
				Remotes.NotifyText:FireClient(player,
					"Quest complete: " .. quest.Text .. "!", Color3.fromRGB(120, 255, 140))
			end
		end
	end
	if changed then
		schedulePush(player)
	end
end

GameSignals.NodeBroken:Connect(function(player)
	addProgress(player, "BreakNodes", 1)
end)
GameSignals.EnemyKilled:Connect(function(player)
	addProgress(player, "KillEnemies", 1)
end)
GameSignals.BossKilled:Connect(function(player)
	addProgress(player, "KillBosses", 1)
end)
GameSignals.PetObtained:Connect(function(player)
	addProgress(player, "HatchEggs", 1)
end)
GameSignals.GoldEarned:Connect(function(player, amount)
	addProgress(player, "EarnGold", amount)
end)

Remotes.ClaimQuest.OnServerInvoke = function(player: Player, questIndex: any)
	if type(questIndex) ~= "number" then
		return false, "Invalid request."
	end
	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end
	rollQuestsFor(player, data)

	local quest = data.DailyQuests.Quests[math.floor(questIndex)]
	if not quest then
		return false, "Unknown quest."
	end
	if quest.Claimed then
		return false, "Already claimed."
	end
	if quest.Progress < quest.Goal then
		return false, "Quest not complete yet."
	end

	quest.Claimed = true
	if quest.Gold then
		DataManager.AddGold(player, math.floor(quest.Gold * (1 + data.Rebirths)))
	end
	if quest.Gems then
		DataManager.AddGems(player, quest.Gems)
	end
	DataManager.PushToClient(player)
	return true, "Reward claimed!"
end

--------------------------------------------------------------------------------
-- PLAYTIME CHESTS (session-scoped)
--------------------------------------------------------------------------------
local sessionStart: { [Player]: number } = {}
local chestsClaimed: { [Player]: { [number]: boolean } } = {}

Remotes.ClaimPlaytime.OnServerInvoke = function(player: Player, chestIndex: any)
	if type(chestIndex) ~= "number" then
		return false, "Invalid request."
	end
	chestIndex = math.floor(chestIndex)

	local chest = GameConfig.PlaytimeRewards[chestIndex]
	if not chest then
		return false, "Unknown chest."
	end
	local startedAt = sessionStart[player]
	if not startedAt then
		return false, "Session not tracked."
	end
	local claimed = chestsClaimed[player]
	if claimed[chestIndex] then
		return false, "Already claimed."
	end
	if (os.clock() - startedAt) < chest.Minutes * 60 then
		return false, "Not unlocked yet."
	end

	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end

	claimed[chestIndex] = true
	if chest.Gold then
		DataManager.AddGold(player, math.floor(chest.Gold * (1 + data.Rebirths)))
	end
	if chest.Gems then
		DataManager.AddGems(player, chest.Gems)
	end
	if chest.EggRoll then
		task.spawn(function()
			PetSystem.HatchEgg(player, chest.EggRoll, true)
		end)
	end
	Remotes.NotifyText:FireClient(player,
		("Playtime chest %d claimed!"):format(chestIndex), Color3.fromRGB(255, 210, 70))
	return true, "Claimed!"
end

--------------------------------------------------------------------------------
-- GROUP DAILY GEMS + LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	sessionStart[player] = os.clock()
	chestsClaimed[player] = {}
	-- Clients time their own chest bar from this replicated attribute.
	player:SetAttribute("SessionStartServerTime", workspace:GetServerTimeNow())

	task.spawn(function()
		local data = DataManager.Get(player)
		if not data then
			return
		end
		rollQuestsFor(player, data)
		DataManager.PushToClient(player)

		-- Live-ops event banner.
		if GameConfig.Events.Name ~= "" then
			Remotes.NotifyText:FireClient(player,
				GameConfig.Events.Name, Color3.fromRGB(255, 220, 90))
		end

		-- Group membership daily gems.
		if (os.time() - data.LastGroupGrant) >= 24 * 60 * 60 then
			local ok, isMember = pcall(function()
				return player:IsInGroup(GameConfig.Group.GroupId)
			end)
			if ok and isMember then
				data.LastGroupGrant = os.time()
				DataManager.AddGems(player, GameConfig.Group.DailyGems)
				Remotes.NotifyText:FireClient(player,
					("Group bonus: +%d Gems! (+%d%% coins always on)")
						:format(GameConfig.Group.DailyGems,
							math.floor((GameConfig.Group.CoinBonus - 1) * 100)),
					Color3.fromRGB(90, 220, 255))
			end
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	sessionStart[player] = nil
	chestsClaimed[player] = nil
	pushPending[player] = nil
end)

print("[QuestManager] Online. Daily key: " .. todayKey())
