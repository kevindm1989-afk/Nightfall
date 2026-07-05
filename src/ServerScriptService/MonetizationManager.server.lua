--!strict
--------------------------------------------------------------------------------
-- MonetizationManager
-- ServerScriptService.MonetizationManager (Script)
--
-- MarketplaceService integration:
--   * ProcessReceipt for Developer Products:
--       - 100 Coins         (GameConfig.DeveloperProducts.Coins100)
--       - 500 Coins         (GameConfig.DeveloperProducts.Coins500)
--       - Mega Egg Roll     (GameConfig.DeveloperProducts.MegaEggRoll)
--   * Gamepass handling (grant on purchase AND on join):
--       - 2x Coins    -> CoinMultiplier x2 (stacks with rebirth bonus)
--       - VIP Luck    -> LuckMultiplier x2 + PetSystem rare-odds x1.5
--       - Auto-Hatch  -> unlocks the server auto-hatch loop
--
-- Receipt safety rules implemented here:
--   1. Never grant twice: PurchasePId ledger persisted in the profile.
--   2. Never return PurchaseGranted until the reward is IN the profile AND a
--      ForceSave has succeeded — Roblox refunds automatically otherwise.
--   3. If the player's data isn't loaded, return NotProcessedYet so Roblox
--      retries the receipt later (including after a rejoin).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()
local PetSystem = require(script.Parent:WaitForChild("PetSystem")).Init()

--------------------------------------------------------------------------------
-- PRODUCT HANDLER TABLE
-- [productId] = function(player) -> boolean success
--------------------------------------------------------------------------------
-- Every product is defined purely by its Grant table in GameConfig, so adding
-- a new pack is a config edit, not a code change.
local productHandlers: { [number]: (Player) -> boolean } = {}

local function grantProduct(player: Player, productInfo: any): boolean
	local data = DataManager.GetLoaded(player)
	if not data then
		return false
	end

	if productInfo.OneTime and data.StarterPackPurchased then
		-- Bought twice via a race or website: convert to a gem consolation
		-- instead of silently eating the Robux.
		DataManager.AddGems(player, 25)
		Remotes.NotifyText:FireClient(player,
			"Starter Pack already owned — granted 25 Gems instead.",
			Color3.fromRGB(90, 220, 255))
		return true
	end

	local grant = productInfo.Grant
	if grant.Gold then
		DataManager.AddGold(player, grant.Gold)
	end
	if grant.Gems then
		DataManager.AddGems(player, grant.Gems)
	end
	if grant.EggRoll then
		-- Bank the roll first (crash-safe), then consume it immediately. If the
		-- hatch fails (full inventory) the roll stays banked in PendingEggRolls.
		data.PendingEggRolls += 1
		DataManager.PushToClient(player)
		task.spawn(function()
			PetSystem.ConsumePendingEggRoll(player)
		end)
	end
	if productInfo.OneTime then
		data.StarterPackPurchased = true
		DataManager.PushToClient(player)
	end

	Remotes.NotifyText:FireClient(player,
		productInfo.Name .. " purchased!", Color3.fromRGB(255, 220, 90))
	return true
end

for _, productInfo in pairs(GameConfig.DeveloperProducts) do
	productHandlers[productInfo.Id] = function(player)
		return grantProduct(player, productInfo)
	end
end

--------------------------------------------------------------------------------
-- PROCESS RECEIPT (Developer Products)
--------------------------------------------------------------------------------
local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player left; Roblox will re-deliver this receipt on their next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not DataManager.IsLoaded(player) then
		-- Profile not ready; retry later rather than risk losing the grant.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Idempotency: PurchaseId is unique per transaction. If we already granted
	-- this receipt (server crashed after grant but before ack), just ack it.
	local purchaseKey = tostring(receiptInfo.PurchaseId)
	if DataManager.HasProcessedReceipt(player, purchaseKey) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local handler = productHandlers[receiptInfo.ProductId]
	if not handler then
		warn(("[MonetizationManager] No handler for ProductId %d"):format(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, player)
	if not ok or not granted then
		warn(("[MonetizationManager] Handler failed for ProductId %d: %s")
			:format(receiptInfo.ProductId, tostring(granted)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Record the receipt, then hard-save BEFORE acknowledging. If the save
	-- fails we refuse the ack so Roblox retries — the ledger check above makes
	-- the retry harmless.
	DataManager.MarkReceiptProcessed(player, purchaseKey)
	local saved = DataManager.ForceSave(player)
	if not saved then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt

--------------------------------------------------------------------------------
-- GAMEPASS EFFECTS
--------------------------------------------------------------------------------
local function applyGamepassEffects(player: Player, gamepassId: number)
	local data = DataManager.Get(player)
	if not data then
		return
	end

	local idKey = tostring(gamepassId)
	if data.OwnedGamepasses[idKey] then
		return -- effects already applied and persisted
	end
	data.OwnedGamepasses[idKey] = true

	if gamepassId == GameConfig.Gamepasses.DoubleCoins.Id then
		data.CoinMultiplier *= GameConfig.Gamepasses.DoubleCoins.Effect.CoinMultiplier
		Remotes.NotifyText:FireClient(player, "2x Coins active!", Color3.fromRGB(255, 220, 90))

	elseif gamepassId == GameConfig.Gamepasses.VIPLuck.Id then
		-- Rare-odds x1.5 is applied inside PetSystem at roll time; the flat
		-- LuckMultiplier boost below also feeds the same roll.
		data.LuckMultiplier *= 2
		Remotes.NotifyText:FireClient(player, "VIP Luck active!", Color3.fromRGB(170, 60, 255))

	elseif gamepassId == GameConfig.Gamepasses.AutoHatch.Id then
		Remotes.NotifyText:FireClient(player,
			"Auto-Hatch unlocked! Toggle it in the shop.", Color3.fromRGB(120, 200, 255))
	end

	PetSystem.InvalidateGamepassCache(player)
	DataManager.PushToClient(player)
end

-- Grant effects the moment a pass is bought in-game.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
	if wasPurchased then
		applyGamepassEffects(player, gamepassId)
		DataManager.ForceSave(player)
	end
end)

-- Reconcile ownership on join (covers passes bought from the website or
-- purchases finished after a crash).
local function reconcileGamepasses(player: Player)
	local data = DataManager.Get(player)
	if not data then
		return
	end
	for _, passInfo in pairs(GameConfig.Gamepasses) do
		if not data.OwnedGamepasses[tostring(passInfo.Id)] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passInfo.Id)
			end)
			if ok and owns then
				applyGamepassEffects(player, passInfo.Id)
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(reconcileGamepasses, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(reconcileGamepasses, player)
end

print("[MonetizationManager] Online. ProcessReceipt bound.")
