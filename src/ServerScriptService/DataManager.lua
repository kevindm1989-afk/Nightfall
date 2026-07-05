--!strict
--------------------------------------------------------------------------------
-- DataManager
-- ServerScriptService.DataManager (ModuleScript)
--
-- Secure, session-locked player data layer built directly on DataStoreService
-- (ProfileService-style semantics, zero external dependencies):
--
--   * Session locking via UpdateAsync  -> a profile can only be active on ONE
--     server at a time, which kills server-hop duplication exploits.
--   * Auto-save every 300 seconds (GameConfig.AutoSaveIntervalSeconds).
--   * Atomic writes: every save goes through UpdateAsync, never SetAsync, so
--     a stale in-flight write can never clobber a newer session's data.
--   * BindToClose flush so shutdowns/updates never lose progress.
--   * Reconciliation: new template fields are merged into old profiles.
--   * Purchase idempotency ledger (receipt ids) for MonetizationManager.
--
-- Data template per player:
--   Gold, Gems, Rebirths
--   CurrentZone (default 1)
--   CoinMultiplier (default 1), LuckMultiplier (default 1)
--   EquippedWeapon, OwnedPets { {UUID, PetName, StatBonus}, ... }
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local GameSignals = require(script.Parent:WaitForChild("GameSignals"))

local DATASTORE_NAME = "PlayerData_V1"
local KEY_PREFIX = "Player_"

local AUTO_SAVE_INTERVAL = GameConfig.AutoSaveIntervalSeconds -- 300s
local LOCK_EXPIRE_SECONDS = 30 * 60 -- a crashed server's lock is considered dead after 30 min
local LOAD_RETRY_ATTEMPTS = 8       -- attempts to steal/wait out a foreign session lock
local LOAD_RETRY_DELAY = 5          -- seconds between lock retries
local CALL_RETRY_ATTEMPTS = 4       -- attempts for a single DataStore call
local CALL_RETRY_DELAY = 2          -- base backoff for DataStore call retries

local DataManager = {}

--------------------------------------------------------------------------------
-- DEFAULT PROFILE TEMPLATE
--------------------------------------------------------------------------------
local DEFAULT_DATA = {
	-- Currencies
	Gold = 0,
	Gems = 0,
	Rebirths = 0,

	-- Progress
	CurrentZone = 1,
	UnlockedZones = { [1] = true },

	-- Multipliers
	CoinMultiplier = 1,
	LuckMultiplier = 1,

	-- Inventory
	EquippedWeapon = GameConfig.DefaultWeapon,
	OwnedWeapons = { [GameConfig.DefaultWeapon] = true },
	OwnedPets = {},   -- array of { UUID = string, PetName = string, StatBonus = number }
	EquippedPets = {},-- array of UUID strings (max GameConfig.Combat.MaxEquippedPets)

	-- Monetization state
	OwnedGamepasses = {},   -- [gamepassIdString] = true
	PurchaseLedger = {},    -- [receiptPurchaseId] = os.time()  (idempotency)
	PendingEggRolls = 0,    -- Mega Egg Rolls bought but not yet consumed
	AutoHatchEnabled = false,
	LastEggHatched = "ForestEgg",
	StarterPackPurchased = false,

	-- Daily reward streak
	LastDailyClaim = 0,
	DailyStreak = 0,

	-- Daily quests: { Key = "YYYY-ddd", Quests = { {Id, Type, Goal, Progress,
	-- Gold?, Gems?, Claimed}, ... } } (rotated by QuestManager)
	DailyQuests = { Key = "", Quests = {} },
	LastGroupGrant = 0,

	-- Bookkeeping
	TotalGoldEarned = 0,
	TotalHatches = 0,
	FirstJoin = 0,
	LastSave = 0,
}

--------------------------------------------------------------------------------
-- INTERNALS
--------------------------------------------------------------------------------
local playerStore = DataStoreService:GetDataStore(DATASTORE_NAME)

-- [Player] = { Data = table, Loaded = bool, Dirty = bool, SessionId = string }
local sessions: { [Player]: any } = {}
local initialized = false

local function deepCopy(source: any): any
	if type(source) ~= "table" then
		return source
	end
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = deepCopy(value)
	end
	return copy
end

-- Fill any missing keys from the template into an existing profile (recursive).
local function reconcile(data: any, template: any)
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
end

local function keyFor(userId: number): string
	return KEY_PREFIX .. tostring(userId)
end

-- Retry wrapper around a DataStore closure with exponential backoff.
local function withRetries(operation: () -> any): (boolean, any)
	local delayTime = CALL_RETRY_DELAY
	for attempt = 1, CALL_RETRY_ATTEMPTS do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		warn(("[DataManager] DataStore call failed (attempt %d/%d): %s")
			:format(attempt, CALL_RETRY_ATTEMPTS, tostring(result)))
		if attempt < CALL_RETRY_ATTEMPTS then
			task.wait(delayTime)
			delayTime *= 2
		end
	end
	return false, nil
end

--------------------------------------------------------------------------------
-- SESSION-LOCKED LOAD
-- Stored envelope shape:
--   { Data = {...}, Lock = { JobId = string, SessionId = string, Time = number } | nil }
--------------------------------------------------------------------------------
local function tryLoadProfile(userId: number, sessionId: string): (any?, string?)
	local key = keyFor(userId)

	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		local claimed: any = nil
		local blocked = false

		local ok = withRetries(function()
			return playerStore:UpdateAsync(key, function(envelope)
				envelope = envelope or { Data = nil, Lock = nil }

				local lock = envelope.Lock
				if lock ~= nil
					and lock.SessionId ~= sessionId
					and (os.time() - (lock.Time or 0)) < LOCK_EXPIRE_SECONDS then
					-- Another live server owns this profile. Abort the write.
					blocked = true
					return nil -- returning nil from the transform cancels the update
				end

				-- Claim (or re-claim) the lock for this session.
				envelope.Lock = {
					JobId = game.JobId,
					SessionId = sessionId,
					Time = os.time(),
				}
				if envelope.Data == nil then
					envelope.Data = deepCopy(DEFAULT_DATA)
					envelope.Data.FirstJoin = os.time()
				end
				claimed = envelope.Data
				return envelope
			end)
		end)

		if not ok then
			return nil, "DataStoreError"
		end

		if not blocked and claimed ~= nil then
			reconcile(claimed, DEFAULT_DATA)
			return claimed, nil
		end

		-- Profile is session-locked elsewhere; wait for that server to release.
		warn(("[DataManager] Profile %s is locked by another session (attempt %d/%d), retrying...")
			:format(key, attempt, LOAD_RETRY_ATTEMPTS))
		task.wait(LOAD_RETRY_DELAY)
	end

	return nil, "SessionLocked"
end

-- keepLock=true  -> periodic autosave (refresh lock timestamp)
-- keepLock=false -> final save on leave/shutdown (release lock)
local function saveProfile(userId: number, sessionId: string, data: any, keepLock: boolean): boolean
	local key = keyFor(userId)
	data.LastSave = os.time()

	local ok = withRetries(function()
		return playerStore:UpdateAsync(key, function(envelope)
			envelope = envelope or { Data = nil, Lock = nil }

			local lock = envelope.Lock
			if lock ~= nil and lock.SessionId ~= sessionId
				and (os.time() - (lock.Time or 0)) < LOCK_EXPIRE_SECONDS then
				-- We lost the lock (should never happen in normal flow).
				-- NEVER overwrite the newer session's data.
				warn(("[DataManager] Refusing to save %s: lock owned by another session."):format(key))
				return nil
			end

			envelope.Data = data
			if keepLock then
				envelope.Lock = { JobId = game.JobId, SessionId = sessionId, Time = os.time() }
			else
				envelope.Lock = nil
			end
			return envelope
		end)
	end)

	return ok
end

--------------------------------------------------------------------------------
-- LEADERSTATS + CLIENT REPLICATION
--------------------------------------------------------------------------------
local function buildLeaderstats(player: Player, data: any)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local gold = Instance.new("NumberValue")
	gold.Name = "Gold"
	gold.Value = data.Gold
	gold.Parent = leaderstats

	local gems = Instance.new("NumberValue")
	gems.Name = "Gems"
	gems.Value = data.Gems
	gems.Parent = leaderstats

	local rebirths = Instance.new("NumberValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths
	rebirths.Parent = leaderstats

	leaderstats.Parent = player
end

-- Sanitized snapshot pushed to the owning client (never includes the ledger).
local function snapshotFor(data: any): any
	return {
		Gold = data.Gold,
		Gems = data.Gems,
		Rebirths = data.Rebirths,
		CurrentZone = data.CurrentZone,
		UnlockedZones = deepCopy(data.UnlockedZones),
		CoinMultiplier = data.CoinMultiplier,
		LuckMultiplier = data.LuckMultiplier,
		EquippedWeapon = data.EquippedWeapon,
		OwnedWeapons = deepCopy(data.OwnedWeapons),
		OwnedPets = deepCopy(data.OwnedPets),
		EquippedPets = deepCopy(data.EquippedPets),
		OwnedGamepasses = deepCopy(data.OwnedGamepasses),
		AutoHatchEnabled = data.AutoHatchEnabled,
		PendingEggRolls = data.PendingEggRolls,
		TotalHatches = data.TotalHatches,
		StarterPackPurchased = data.StarterPackPurchased,
		LastDailyClaim = data.LastDailyClaim,
		DailyStreak = data.DailyStreak,
		DailyQuests = deepCopy(data.DailyQuests),
	}
end

-- Publishes the equipped pet names as a replicated Player attribute so EVERY
-- client (not just the owner) can render pet followers locally.
local function publishEquippedPets(player: Player, data: any)
	local byUUID: { [string]: any } = {}
	for _, pet in ipairs(data.OwnedPets) do
		byUUID[pet.UUID] = pet
	end
	local names = {}
	for _, uuid in ipairs(data.EquippedPets) do
		local pet = byUUID[uuid]
		if pet then
			table.insert(names, pet.PetName)
		end
	end
	player:SetAttribute("EquippedPetNames", table.concat(names, ","))
	-- WeaponVisualizer reads this to render the held weapon on every client.
	player:SetAttribute("EquippedWeaponName", data.EquippedWeapon)
end

function DataManager.PushToClient(player: Player)
	local session = sessions[player]
	if session and session.Loaded then
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			(leaderstats :: any).Gold.Value = session.Data.Gold;
			(leaderstats :: any).Gems.Value = session.Data.Gems;
			(leaderstats :: any).Rebirths.Value = session.Data.Rebirths;
		end
		publishEquippedPets(player, session.Data)
		Remotes.DataChanged:FireClient(player, snapshotFor(session.Data))
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

-- Yields until the player's profile is loaded (or the player leaves).
function DataManager.Get(player: Player): any?
	local start = os.clock()
	while true do
		local session = sessions[player]
		if session and session.Loaded then
			return session.Data
		end
		if not player.Parent then
			return nil
		end
		if os.clock() - start > 60 then
			return nil
		end
		task.wait(0.1)
	end
end

-- Non-yielding accessor for hot paths (returns nil if not loaded yet).
function DataManager.GetLoaded(player: Player): any?
	local session = sessions[player]
	if session and session.Loaded then
		return session.Data
	end
	return nil
end

function DataManager.IsLoaded(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Loaded == true
end

function DataManager.AddGold(player: Player, amount: number)
	local data = DataManager.GetLoaded(player)
	if not data or amount == 0 then return end
	data.Gold = math.max(0, math.floor(data.Gold + amount))
	if amount > 0 then
		data.TotalGoldEarned += math.floor(amount)
		GameSignals.GoldEarned:Fire(player, math.floor(amount))
	end
	DataManager.PushToClient(player)
end

function DataManager.AddGems(player: Player, amount: number)
	local data = DataManager.GetLoaded(player)
	if not data or amount == 0 then return end
	data.Gems = math.max(0, math.floor(data.Gems + amount))
	DataManager.PushToClient(player)
end

-- Atomic spend: returns false (and deducts nothing) if the player can't afford it.
function DataManager.TrySpend(player: Player, currency: string, amount: number): boolean
	local data = DataManager.GetLoaded(player)
	if not data then return false end
	if amount < 0 then return false end
	if currency ~= "Gold" and currency ~= "Gems" then return false end
	if data[currency] < amount then
		return false
	end
	data[currency] -= amount
	DataManager.PushToClient(player)
	return true
end

-- Grants a pet entry with a collision-proof UUID. Returns the entry or nil if full.
function DataManager.GrantPet(player: Player, petName: string, statBonus: number): any?
	local data = DataManager.GetLoaded(player)
	if not data then return nil end
	if #data.OwnedPets >= GameConfig.Combat.MaxOwnedPets then
		Remotes.NotifyText:FireClient(player, "Pet inventory full!", Color3.fromRGB(255, 90, 90))
		return nil
	end
	local entry = {
		UUID = HttpService:GenerateGUID(false),
		PetName = petName,
		StatBonus = statBonus,
	}
	table.insert(data.OwnedPets, entry)
	data.TotalHatches += 1
	GameSignals.PetObtained:Fire(player, petName)
	DataManager.PushToClient(player)
	return entry
end

-- Idempotency helpers for MonetizationManager --------------------------------
function DataManager.HasProcessedReceipt(player: Player, purchaseId: string): boolean
	local data = DataManager.GetLoaded(player)
	return data ~= nil and data.PurchaseLedger[purchaseId] ~= nil
end

function DataManager.MarkReceiptProcessed(player: Player, purchaseId: string)
	local data = DataManager.GetLoaded(player)
	if data then
		data.PurchaseLedger[purchaseId] = os.time()
		-- Keep the ledger bounded: drop entries older than 30 days.
		local cutoff = os.time() - (30 * 24 * 60 * 60)
		for id, stamp in pairs(data.PurchaseLedger) do
			if stamp < cutoff then
				data.PurchaseLedger[id] = nil
			end
		end
	end
end

-- Immediately persists a player's profile (used after Robux transactions so a
-- crash can never eat a paid purchase). Yields.
function DataManager.ForceSave(player: Player): boolean
	local session = sessions[player]
	if not (session and session.Loaded) then
		return false
	end
	return saveProfile(player.UserId, session.SessionId, session.Data, true)
end

--------------------------------------------------------------------------------
-- LIFECYCLE
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local sessionId = HttpService:GenerateGUID(false)
	sessions[player] = { Data = nil, Loaded = false, SessionId = sessionId }

	local data, err = tryLoadProfile(player.UserId, sessionId)

	if not player.Parent then
		-- Player left mid-load; release the lock we may have just claimed.
		if data then
			saveProfile(player.UserId, sessionId, data, false)
		end
		sessions[player] = nil
		return
	end

	if not data then
		warn(("[DataManager] Could not load data for %s (%s). Kicking to protect the profile.")
			:format(player.Name, tostring(err)))
		sessions[player] = nil
		player:Kick("Your data could not be loaded safely. Please rejoin in a moment.")
		return
	end

	local session = sessions[player]
	session.Data = data
	session.Loaded = true

	buildLeaderstats(player, data)
	DataManager.PushToClient(player)
	print(("[DataManager] Loaded profile for %s (session %s)"):format(player.Name, sessionId))
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session and session.Loaded then
		local ok = saveProfile(player.UserId, session.SessionId, session.Data, false)
		print(("[DataManager] Released profile for %s (saved=%s)"):format(player.Name, tostring(ok)))
	end
end

function DataManager.Init()
	if initialized then
		return DataManager
	end
	initialized = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- GetData RemoteFunction: full sanitized snapshot on demand.
	Remotes.GetData.OnServerInvoke = function(player: Player)
		local data = DataManager.Get(player)
		if data then
			return snapshotFor(data)
		end
		return nil
	end

	-- Auto-save loop: every profile, every AUTO_SAVE_INTERVAL seconds,
	-- staggered so a full server doesn't burst its DataStore budget.
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			local players = Players:GetPlayers()
			for index, player in ipairs(players) do
				local session = sessions[player]
				if session and session.Loaded then
					task.spawn(function()
						saveProfile(player.UserId, session.SessionId, session.Data, true)
					end)
					task.wait(math.min(1, AUTO_SAVE_INTERVAL / math.max(#players, 1) / 4))
				end
			end
		end
	end)

	-- Flush every live profile on shutdown / soft update.
	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(2) -- give Studio sessions a moment to flush
		end
		local pending = 0
		for player, session in pairs(sessions) do
			if session.Loaded then
				pending += 1
				task.spawn(function()
					saveProfile(player.UserId, session.SessionId, session.Data, false)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	print("[DataManager] Initialized. Auto-save interval: " .. AUTO_SAVE_INTERVAL .. "s")
	return DataManager
end

return DataManager
