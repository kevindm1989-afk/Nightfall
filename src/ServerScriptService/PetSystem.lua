--!strict
--------------------------------------------------------------------------------
-- PetSystem
-- ServerScriptService.PetSystem (ModuleScript)
--
-- Weighted random pet hatching across 5 tiers:
--   Common 50% | Uncommon 30% | Rare 15% | Epic 4.5% | Mythic 0.5%
--
-- VIP Luck gamepass (ID 1234567): if owned, Rare / Epic / Mythic weights are
-- multiplied by 1.5 BEFORE the roll (Common/Uncommon absorb the difference
-- because the roll normalizes over the total weight).
--
-- The player's LuckMultiplier (rebirths, events) applies the same way.
-- All rolls, costs and grants are 100% server-authoritative.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local GameSignals = require(script.Parent:WaitForChild("GameSignals"))

local VIP_LUCK_GAMEPASS_ID = 1234567
local VIP_LUCK_RARE_MULTIPLIER = 1.5

local PetSystem = {}

-- [userId] = { [gamepassId] = boolean }  (per-session ownership cache so we
-- don't hammer MarketplaceService on every single hatch)
local gamepassCache: { [number]: { [number]: boolean } } = {}

local rng = Random.new()

--------------------------------------------------------------------------------
-- GAMEPASS OWNERSHIP (cached)
--------------------------------------------------------------------------------
function PetSystem.PlayerOwnsGamepass(player: Player, gamepassId: number): boolean
	-- 1) Persisted profile flag (set by MonetizationManager on purchase/join).
	local data = DataManager.GetLoaded(player)
	if data and data.OwnedGamepasses[tostring(gamepassId)] then
		return true
	end

	-- 2) Session cache.
	local cache = gamepassCache[player.UserId]
	if cache and cache[gamepassId] ~= nil then
		return cache[gamepassId]
	end

	-- 3) Live API check (pcall-guarded; failure = treat as not owned this call).
	local owns = false
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	if ok then
		owns = result
		gamepassCache[player.UserId] = gamepassCache[player.UserId] or {}
		gamepassCache[player.UserId][gamepassId] = owns
	end
	return owns
end

function PetSystem.InvalidateGamepassCache(player: Player)
	gamepassCache[player.UserId] = nil
end

--------------------------------------------------------------------------------
-- WEIGHT TABLE CONSTRUCTION
--------------------------------------------------------------------------------
-- Returns { [tierName] = effectiveWeight } for this player + egg.
local function buildTierWeights(player: Player, eggConfig: any): { [string]: number }
	local weights: { [string]: number } = {}

	if eggConfig.WeightOverride then
		for tier, weight in pairs(eggConfig.WeightOverride) do
			weights[tier] = weight
		end
	else
		for _, tierInfo in ipairs(GameConfig.PetTiers) do
			weights[tierInfo.Tier] = tierInfo.Weight
		end
	end

	-- Composite luck applied to rare tiers only.
	local rareBoost = 1.0

	if PetSystem.PlayerOwnsGamepass(player, VIP_LUCK_GAMEPASS_ID) then
		rareBoost *= VIP_LUCK_RARE_MULTIPLIER
	end

	local data = DataManager.GetLoaded(player)
	if data and data.LuckMultiplier and data.LuckMultiplier > 0 then
		rareBoost *= data.LuckMultiplier
	end

	-- Live-ops event multiplier ("2x Luck Weekend" via config edit).
	rareBoost *= GameConfig.Events.LuckMultiplier

	if rareBoost ~= 1.0 then
		for tier in pairs(GameConfig.RareTierSet) do
			if weights[tier] then
				weights[tier] *= rareBoost
			end
		end
	end

	return weights
end

-- Group an egg's pet pool by tier: { [tierName] = { petName, ... } }
local function poolByTier(eggConfig: any): { [string]: { string } }
	local grouped: { [string]: { string } } = {}
	for _, petName in ipairs(eggConfig.Pool) do
		local petConfig = GameConfig.Pets[petName]
		if petConfig then
			grouped[petConfig.Tier] = grouped[petConfig.Tier] or {}
			table.insert(grouped[petConfig.Tier], petName)
		end
	end
	return grouped
end

--------------------------------------------------------------------------------
-- THE ROLL
--------------------------------------------------------------------------------
-- Rolls a tier first (weighted), then a uniform pet within that tier's pool.
-- Returns petName, tierName.
function PetSystem.RollPet(player: Player, eggName: string): (string?, string?)
	local eggConfig = GameConfig.Eggs[eggName]
	if not eggConfig then
		return nil, nil
	end

	local tierWeights = buildTierWeights(player, eggConfig)
	local grouped = poolByTier(eggConfig)

	-- Only tiers that actually contain pets in this egg can win the roll.
	local totalWeight = 0
	for tier, weight in pairs(tierWeights) do
		if grouped[tier] and #grouped[tier] > 0 and weight > 0 then
			totalWeight += weight
		end
	end
	if totalWeight <= 0 then
		return nil, nil
	end

	local pick = rng:NextNumber() * totalWeight
	local accumulated = 0
	local chosenTier: string? = nil

	for _, tierInfo in ipairs(GameConfig.PetTiers) do
		local tier = tierInfo.Tier
		local weight = tierWeights[tier]
		if weight and weight > 0 and grouped[tier] and #grouped[tier] > 0 then
			accumulated += weight
			if pick <= accumulated then
				chosenTier = tier
				break
			end
		end
	end
	-- Floating point safety: default to the last valid tier.
	if not chosenTier then
		for i = #GameConfig.PetTiers, 1, -1 do
			local tier = GameConfig.PetTiers[i].Tier
			if grouped[tier] and #grouped[tier] > 0 and (tierWeights[tier] or 0) > 0 then
				chosenTier = tier
				break
			end
		end
	end
	if not chosenTier then
		return nil, nil
	end

	local candidates = grouped[chosenTier]
	local petName = candidates[rng:NextInteger(1, #candidates)]
	return petName, chosenTier
end

--------------------------------------------------------------------------------
-- HATCHING (cost + grant + client reveal)
--------------------------------------------------------------------------------
-- free=true skips the currency charge (boss drops, Mega Egg Roll product).
function PetSystem.HatchEgg(player: Player, eggName: string, free: boolean?): (any?, string?)
	local eggConfig = GameConfig.Eggs[eggName]
	if not eggConfig then
		return nil, "Unknown egg."
	end

	local data = DataManager.GetLoaded(player)
	if not data then
		return nil, "Data still loading."
	end

	-- Zone gating: you can only buy eggs from zones you've unlocked.
	if not free and eggConfig.Zone > 0 and not data.UnlockedZones[eggConfig.Zone] then
		return nil, "Unlock " .. GameConfig.Zones[eggConfig.Zone].Name .. " first!"
	end

	-- Robux-only eggs can never be bought with in-game currency.
	if not free and eggConfig.Currency == "Robux" then
		return nil, "This egg is only available in the shop."
	end

	if not free then
		if not DataManager.TrySpend(player, eggConfig.Currency, eggConfig.Cost) then
			return nil, "Not enough " .. eggConfig.Currency .. "!"
		end
	end

	local petName, tier = PetSystem.RollPet(player, eggName)
	if not petName then
		-- Refund on impossible rolls (misconfigured egg) so money is never eaten.
		if not free then
			if eggConfig.Currency == "Gold" then
				DataManager.AddGold(player, eggConfig.Cost)
			else
				DataManager.AddGems(player, eggConfig.Cost)
			end
		end
		return nil, "Hatch failed, refunded."
	end

	local petConfig = GameConfig.Pets[petName]
	local entry = DataManager.GrantPet(player, petName, petConfig.StatBonus)
	if not entry then
		if not free then
			if eggConfig.Currency == "Gold" then
				DataManager.AddGold(player, eggConfig.Cost)
			else
				DataManager.AddGems(player, eggConfig.Cost)
			end
		end
		return nil, "Pet inventory full, refunded."
	end

	data.LastEggHatched = eggName

	local reveal = {
		UUID = entry.UUID,
		PetName = petName,
		Tier = tier,
		StatBonus = petConfig.StatBonus,
		Egg = eggName,
	}
	Remotes.PetHatched:FireClient(player, reveal)
	return reveal, nil
end

-- Consumes one banked Mega Egg Roll (granted by the developer product).
function PetSystem.ConsumePendingEggRoll(player: Player): (any?, string?)
	local data = DataManager.GetLoaded(player)
	if not data then
		return nil, "Data still loading."
	end
	if data.PendingEggRolls <= 0 then
		return nil, "No Mega Egg Rolls available."
	end
	data.PendingEggRolls -= 1
	local reveal, err = PetSystem.HatchEgg(player, "MegaEgg", true)
	if not reveal then
		data.PendingEggRolls += 1 -- restore on failure
	end
	DataManager.PushToClient(player)
	return reveal, err
end

--------------------------------------------------------------------------------
-- EQUIP CAPACITY (base 4, +2 with the Pet Slots gamepass)
--------------------------------------------------------------------------------
function PetSystem.MaxEquippedFor(player: Player): number
	local cap = GameConfig.Combat.MaxEquippedPets
	if PetSystem.PlayerOwnsGamepass(player, GameConfig.Gamepasses.PetSlots.Id) then
		cap += GameConfig.Gamepasses.PetSlots.Effect.ExtraPetSlots
	end
	return cap
end

--------------------------------------------------------------------------------
-- DAMAGE CONTRIBUTION (consumed by CoreEngine)
--------------------------------------------------------------------------------
function PetSystem.GetEquippedStatBonus(player: Player): number
	local data = DataManager.GetLoaded(player)
	if not data then
		return 0
	end
	local byUUID: { [string]: any } = {}
	for _, pet in ipairs(data.OwnedPets) do
		byUUID[pet.UUID] = pet
	end
	local total = 0
	local counted = 0
	local cap = PetSystem.MaxEquippedFor(player)
	for _, uuid in ipairs(data.EquippedPets) do
		local pet = byUUID[uuid]
		if pet then
			total += pet.StatBonus
			counted += 1
			if counted >= cap then
				break
			end
		end
	end
	return total
end

--------------------------------------------------------------------------------
-- FUSION: 5 same-name, same-variant pets + gems -> 1 upgraded variant
--------------------------------------------------------------------------------
function PetSystem.FusePets(player: Player, petName: string, targetVariant: string): (any?, string?)
	local variantConfig = GameConfig.Fusion.Variants[targetVariant]
	if not variantConfig then
		return nil, "Unknown fusion."
	end
	local petConfig = GameConfig.Pets[petName]
	if not petConfig then
		return nil, "Unknown pet."
	end
	local data = DataManager.GetLoaded(player)
	if not data then
		return nil, "Data still loading."
	end

	-- Collect candidates of the source variant.
	local sourceVariant = variantConfig.From
	local candidates = {}
	for index, pet in ipairs(data.OwnedPets) do
		local variant = pet.Variant or "Normal"
		if pet.PetName == petName and variant == sourceVariant then
			table.insert(candidates, { Index = index, Pet = pet })
		end
	end
	if #candidates < GameConfig.Fusion.Required then
		return nil, ("Need %d %s %s (have %d).")
			:format(GameConfig.Fusion.Required, sourceVariant, petName, #candidates)
	end

	if not DataManager.TrySpend(player, "Gems", variantConfig.GemCost) then
		return nil, ("Fusion costs %d Gems."):format(variantConfig.GemCost)
	end

	-- Consume exactly Required copies (highest indices first so table.remove
	-- doesn't shift the pending ones), unequipping as we go. No yields between
	-- the spend, the removal and the grant: the operation is atomic.
	local toConsume = {}
	for i = 1, GameConfig.Fusion.Required do
		table.insert(toConsume, candidates[i])
	end
	table.sort(toConsume, function(a, b)
		return a.Index > b.Index
	end)
	for _, item in ipairs(toConsume) do
		for equippedIndex, uuid in ipairs(data.EquippedPets) do
			if uuid == item.Pet.UUID then
				table.remove(data.EquippedPets, equippedIndex)
				break
			end
		end
		table.remove(data.OwnedPets, item.Index)
	end

	local newStat = math.floor(petConfig.StatBonus * variantConfig.Multiplier)
	local entry = DataManager.GrantPet(player, petName, newStat, targetVariant)
	if not entry then
		-- Inventory can't be full (we just removed 5) — but never eat gems.
		DataManager.AddGems(player, variantConfig.GemCost)
		return nil, "Fusion failed, gems refunded."
	end

	data.TotalFusions += 1
	GameSignals.PetFused:Fire(player, petName, targetVariant)
	DataManager.PushToClient(player)

	local reveal = {
		UUID = entry.UUID,
		PetName = petName,
		Tier = petConfig.Tier,
		StatBonus = newStat,
		Variant = targetVariant,
	}
	Remotes.PetHatched:FireClient(player, reveal) -- reuse the hatch cutscene
	Remotes.NotifyText:FireClient(player,
		("FUSED: %s %s (+%d dmg)!"):format(targetVariant, petName, newStat),
		variantConfig.Color)
	return reveal, nil
end

--------------------------------------------------------------------------------
-- REMOTE WIRING + AUTO-HATCH LOOP
--------------------------------------------------------------------------------
local initialized = false

function PetSystem.Init()
	if initialized then
		return PetSystem
	end
	initialized = true

	Remotes.HatchEgg.OnServerInvoke = function(player: Player, eggName: any)
		if type(eggName) ~= "string" then
			return nil, "Invalid request."
		end
		if eggName == "MegaEgg" then
			return PetSystem.ConsumePendingEggRoll(player)
		end
		return PetSystem.HatchEgg(player, eggName, false)
	end

	Remotes.EquipPet.OnServerInvoke = function(player: Player, petUUID: any)
		if type(petUUID) ~= "string" then
			return false, "Invalid request."
		end
		local data = DataManager.GetLoaded(player)
		if not data then
			return false, "Data still loading."
		end

		-- Toggle: unequip if already equipped.
		for index, uuid in ipairs(data.EquippedPets) do
			if uuid == petUUID then
				table.remove(data.EquippedPets, index)
				DataManager.PushToClient(player)
				return true, "Unequipped."
			end
		end

		-- Must actually own the pet (UUIDs are unforgeable server GUIDs).
		local owns = false
		for _, pet in ipairs(data.OwnedPets) do
			if pet.UUID == petUUID then
				owns = true
				break
			end
		end
		if not owns then
			return false, "You do not own that pet."
		end
		local cap = PetSystem.MaxEquippedFor(player)
		if #data.EquippedPets >= cap then
			return false, "Max " .. cap .. " pets equipped."
		end

		table.insert(data.EquippedPets, petUUID)
		DataManager.PushToClient(player)
		return true, "Equipped."
	end

	Remotes.FusePets.OnServerInvoke = function(player: Player, petName: any, targetVariant: any)
		if type(petName) ~= "string" or type(targetVariant) ~= "string" then
			return nil, "Invalid request."
		end
		return PetSystem.FusePets(player, petName, targetVariant)
	end

	Remotes.DeletePet.OnServerInvoke = function(player: Player, petUUID: any)
		if type(petUUID) ~= "string" then
			return false, "Invalid request."
		end
		local data = DataManager.GetLoaded(player)
		if not data then
			return false, "Data still loading."
		end

		local ownedIndex: number? = nil
		for index, pet in ipairs(data.OwnedPets) do
			if pet.UUID == petUUID then
				ownedIndex = index
				break
			end
		end
		if not ownedIndex then
			return false, "You do not own that pet."
		end

		-- Unequip first so EquippedPets never holds a dangling UUID.
		for index, uuid in ipairs(data.EquippedPets) do
			if uuid == petUUID then
				table.remove(data.EquippedPets, index)
				break
			end
		end
		table.remove(data.OwnedPets, ownedIndex)
		DataManager.PushToClient(player)
		return true, "Pet released."
	end

	Remotes.ToggleAutoHatch.OnServerEvent:Connect(function(player: Player, enabled: any)
		local data = DataManager.GetLoaded(player)
		if not data then
			return
		end
		local autoHatchPass = GameConfig.Gamepasses.AutoHatch
		if not PetSystem.PlayerOwnsGamepass(player, autoHatchPass.Id) then
			Remotes.NotifyText:FireClient(player,
				"Auto-Hatch requires the " .. autoHatchPass.Name .. " gamepass!",
				Color3.fromRGB(255, 90, 90))
			return
		end
		data.AutoHatchEnabled = enabled == true
		DataManager.PushToClient(player)
	end)

	-- Auto-Hatch loop: every 3s, re-hatch the last egg for entitled players.
	task.spawn(function()
		local Players = game:GetService("Players")
		while true do
			task.wait(3)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = DataManager.GetLoaded(player)
				if data and data.AutoHatchEnabled then
					task.spawn(function()
						local eggName = data.LastEggHatched
						if GameConfig.Eggs[eggName] and eggName ~= "MegaEgg" then
							PetSystem.HatchEgg(player, eggName, false)
						end
					end)
				end
			end
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		gamepassCache[player.UserId] = nil
	end)

	print("[PetSystem] Initialized. VIP Luck pass id: " .. VIP_LUCK_GAMEPASS_ID)
	return PetSystem
end

return PetSystem
