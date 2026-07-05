--!strict
--------------------------------------------------------------------------------
-- CoreEngine
-- ServerScriptService.CoreEngine (Script)
--
-- The authoritative gameplay loop:
--   * Boots DataManager + PetSystem in the correct order.
--   * Tracks resource-node interactions and combat swings with anti-exploit
--     validation (server cooldown + distance check).
--   * Damage formula: Weapon Base Damage + sum of equipped Pet StatBonuses.
--   * Awards Gold (scaled by CoinMultiplier), rolls boss loot tables, fires
--     the LootDropped event that drives the client-side LootAnimator.
--   * Handles weapon shop, zone unlocking and rebirths.
--
-- WORKSPACE CONVENTIONS (how the map plugs into this engine):
--   Workspace.Zones.Zone<N>.Nodes.<Model>   with attribute NodeType  = config key
--   Workspace.Zones.Zone<N>.Enemies.<Model> with attribute EnemyType = config key
--   Workspace.Zones.Zone<N>.Boss.<Model>    with attribute BossName  = config key
-- Every target model needs a PrimaryPart. The engine stamps MaxHealth /
-- CurrentHealth attributes onto each model so world-space health bars can be
-- driven entirely from replication.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()
local PetSystem = require(script.Parent:WaitForChild("PetSystem")).Init()

local SWING_COOLDOWN = GameConfig.Combat.SwingCooldown
local MAX_HIT_DISTANCE = GameConfig.Combat.MaxHitDistance

--------------------------------------------------------------------------------
-- TARGET REGISTRY
-- [Model] = { Kind = "Node"|"Enemy"|"Boss", ZoneId, ConfigKey, Config,
--             Health, MaxHealth, Alive, LastAttackers = {[Player]=damage} }
--------------------------------------------------------------------------------
local targets: { [Model]: any } = {}
local lastSwing: { [Player]: number } = {}

local rng = Random.new()

local function stampHealth(model: Model, current: number, max: number)
	model:SetAttribute("CurrentHealth", current)
	model:SetAttribute("MaxHealth", max)
end

local function bossHealthFor(bossConfig: any): number
	-- Documented scaling: tuned flat value per zone; formula kept for events
	-- that want dynamic scaling (see GameConfig.BossBaseHP/BossHPGrowth).
	return bossConfig.Health
end

local function registerTarget(model: Model, kind: string, zoneId: number, configKey: string, config: any)
	local maxHealth
	if kind == "Boss" then
		maxHealth = bossHealthFor(config)
	else
		maxHealth = config.Health
	end
	targets[model] = {
		Kind = kind,
		ZoneId = zoneId,
		ConfigKey = configKey,
		Config = config,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Alive = true,
		LastAttackers = {},
	}
	stampHealth(model, maxHealth, maxHealth)
end

local function scanZones()
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		warn("[CoreEngine] Workspace.Zones folder not found; build the map per docs/MapSpecifications.md")
		return
	end
	for zoneId, zoneConfig in pairs(GameConfig.Zones) do
		local zoneFolder = zonesFolder:FindFirstChild("Zone" .. zoneId)
		if zoneFolder then
			local nodesFolder = zoneFolder:FindFirstChild("Nodes")
			if nodesFolder then
				for _, model in ipairs(nodesFolder:GetChildren()) do
					if model:IsA("Model") then
						local nodeType = model:GetAttribute("NodeType")
						local config = nodeType and zoneConfig.Nodes[nodeType]
						if config then
							registerTarget(model, "Node", zoneId, nodeType :: string, config)
						end
					end
				end
			end
			local enemiesFolder = zoneFolder:FindFirstChild("Enemies")
			if enemiesFolder then
				for _, model in ipairs(enemiesFolder:GetChildren()) do
					if model:IsA("Model") then
						local enemyType = model:GetAttribute("EnemyType")
						local config = enemyType and zoneConfig.Enemies[enemyType]
						if config then
							registerTarget(model, "Enemy", zoneId, enemyType :: string, config)
						end
					end
				end
			end
			local bossFolder = zoneFolder:FindFirstChild("Boss")
			if bossFolder then
				for _, model in ipairs(bossFolder:GetChildren()) do
					if model:IsA("Model") then
						local bossName = model:GetAttribute("BossName")
						local config = bossName and GameConfig.Bosses[bossName]
						if config then
							registerTarget(model, "Boss", zoneId, bossName :: string, config)
						end
					end
				end
			end
		end
	end
	local count = 0
	for _ in pairs(targets) do count += 1 end
	print(("[CoreEngine] Registered %d interactive targets."):format(count))
end

--------------------------------------------------------------------------------
-- DAMAGE
--------------------------------------------------------------------------------
local function computeDamage(player: Player): number
	local data = DataManager.GetLoaded(player)
	if not data then
		return 0
	end
	local weapon = GameConfig.Weapons[data.EquippedWeapon] or GameConfig.Weapons[GameConfig.DefaultWeapon]
	local weaponDamage = weapon.BaseDamage
	local petBonus = PetSystem.GetEquippedStatBonus(player)
	return weaponDamage + petBonus
end

local function coinMultiplierFor(player: Player): number
	local data = DataManager.GetLoaded(player)
	if not data then
		return 1
	end
	return math.max(1, data.CoinMultiplier)
end

--------------------------------------------------------------------------------
-- LOOT DELIVERY
--------------------------------------------------------------------------------
local function dropLootVisual(player: Player, worldPosition: Vector3, drops: { any })
	-- Client-side eye candy only; rewards were already granted server-side.
	Remotes.LootDropped:FireClient(player, {
		Origin = worldPosition,
		Drops = drops, -- { {Item, Type, Amount?}, ... }
	})
end

local function grantBossLoot(player: Player, bossConfig: any, origin: Vector3)
	local visualDrops = {}
	local totalWeight = 0
	for _, entry in ipairs(bossConfig.LootTable) do
		totalWeight += entry.Weight
	end

	for _ = 1, bossConfig.RollsPerKill do
		local pick = rng:NextNumber() * totalWeight
		local accumulated = 0
		local chosen = bossConfig.LootTable[#bossConfig.LootTable]
		for _, entry in ipairs(bossConfig.LootTable) do
			accumulated += entry.Weight
			if pick <= accumulated then
				chosen = entry
				break
			end
		end

		if chosen.Type == "Gold" then
			local amount = math.floor(chosen.Amount * coinMultiplierFor(player))
			DataManager.AddGold(player, amount)
			table.insert(visualDrops, { Item = chosen.Item, Type = "Gold", Amount = amount })
		elseif chosen.Type == "Gems" then
			DataManager.AddGems(player, chosen.Amount)
			table.insert(visualDrops, { Item = chosen.Item, Type = "Gems", Amount = chosen.Amount })
		elseif chosen.Type == "Weapon" then
			local data = DataManager.GetLoaded(player)
			if data then
				if data.OwnedWeapons[chosen.Item] then
					-- Duplicate weapon converts to 25% of its shop price in Gold.
					local weaponConfig = GameConfig.Weapons[chosen.Item]
					local refund = math.floor((weaponConfig and weaponConfig.Cost or 0) * 0.25)
					DataManager.AddGold(player, refund)
					table.insert(visualDrops, { Item = chosen.Item, Type = "Gold", Amount = refund })
				else
					data.OwnedWeapons[chosen.Item] = true
					DataManager.PushToClient(player)
					table.insert(visualDrops, { Item = chosen.Item, Type = "Weapon", Amount = 1 })
					Remotes.NotifyText:FireClient(player,
						"Weapon drop: " .. chosen.Item .. "!", Color3.fromRGB(120, 200, 255))
				end
			end
		elseif chosen.Type == "Egg" then
			local reveal = PetSystem.HatchEgg(player, chosen.Egg, true)
			if reveal then
				table.insert(visualDrops, { Item = chosen.Egg, Type = "Egg", Amount = 1 })
			end
		elseif chosen.Type == "Pet" then
			local petConfig = GameConfig.Pets[chosen.Item]
			if petConfig then
				local entry = DataManager.GrantPet(player, chosen.Item, petConfig.StatBonus)
				if entry then
					table.insert(visualDrops, { Item = chosen.Item, Type = "Pet", Amount = 1 })
					Remotes.NotifyText:FireClient(player,
						"BOSS PET DROP: " .. chosen.Item .. "!", Color3.fromRGB(255, 170, 0))
				end
			end
		end
	end

	dropLootVisual(player, origin, visualDrops)
end

--------------------------------------------------------------------------------
-- DEATH / RESPAWN
--------------------------------------------------------------------------------
local function killTarget(model: Model, state: any, killer: Player)
	state.Alive = false
	state.Health = 0
	stampHealth(model, 0, state.MaxHealth)

	local origin = model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero
	local respawnSeconds = state.Config.RespawnSeconds

	if state.Kind == "Boss" then
		-- Every player who tagged the boss gets full gold + a loot roll.
		for attacker in pairs(state.LastAttackers) do
			if attacker.Parent then
				local gold = math.floor(state.Config.GoldReward * coinMultiplierFor(attacker))
				DataManager.AddGold(attacker, gold)
				grantBossLoot(attacker, state.Config, origin)
			end
		end
	else
		local gold = math.floor(state.Config.GoldReward * coinMultiplierFor(killer))
		DataManager.AddGold(killer, gold)
		dropLootVisual(killer, origin, {
			{ Item = "Gold_Burst", Type = "Gold", Amount = gold },
		})
	end
	table.clear(state.LastAttackers)

	-- Hide the model while "dead", restore on respawn.
	local originalTransparencies: { [BasePart]: number } = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			originalTransparencies[part] = part.Transparency
			part.Transparency = 1
			part.CanCollide = false
			part.CanTouch = false
		end
	end

	task.delay(respawnSeconds, function()
		if not model.Parent then
			return
		end
		for part, transparency in pairs(originalTransparencies) do
			if part.Parent then
				part.Transparency = transparency
				part.CanCollide = true
				part.CanTouch = true
			end
		end
		state.Health = state.MaxHealth
		state.Alive = true
		stampHealth(model, state.MaxHealth, state.MaxHealth)
	end)
end

--------------------------------------------------------------------------------
-- SWING VALIDATION + APPLICATION (shared by NodeHit and CombatSwing)
--------------------------------------------------------------------------------
local function handleSwing(player: Player, model: any, expectedKinds: { [string]: boolean })
	-- Type / registry validation: the client can only reference real,
	-- server-registered targets. Anything else is silently dropped.
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local state = targets[model]
	if not state or not state.Alive then
		return
	end
	if not expectedKinds[state.Kind] then
		return
	end

	local data = DataManager.GetLoaded(player)
	if not data then
		return
	end

	-- Zone gating: no hitting content in zones you haven't unlocked.
	if not data.UnlockedZones[state.ZoneId] then
		return
	end

	-- Server-side cooldown (client animation speed is irrelevant).
	local now = os.clock()
	if lastSwing[player] and (now - lastSwing[player]) < SWING_COOLDOWN then
		return
	end

	-- Distance check against the character's real server position.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local primary = model.PrimaryPart
	if not root or not primary then
		return
	end
	if (root.Position - primary.Position).Magnitude > MAX_HIT_DISTANCE then
		return
	end

	lastSwing[player] = now

	local damage = computeDamage(player)
	if damage <= 0 then
		return
	end

	state.Health = math.max(0, state.Health - damage)
	state.LastAttackers[player] = (state.LastAttackers[player] or 0) + damage
	stampHealth(model, state.Health, state.MaxHealth)

	if state.Health <= 0 then
		killTarget(model, state, player)
	end
end

Remotes.NodeHit.OnServerEvent:Connect(function(player, model)
	handleSwing(player, model, { Node = true })
end)

Remotes.CombatSwing.OnServerEvent:Connect(function(player, model)
	handleSwing(player, model, { Enemy = true, Boss = true })
end)

--------------------------------------------------------------------------------
-- WEAPON SHOP / EQUIP
--------------------------------------------------------------------------------
Remotes.BuyWeapon.OnServerInvoke = function(player: Player, weaponName: any)
	if type(weaponName) ~= "string" then
		return false, "Invalid request."
	end
	local weaponConfig = GameConfig.Weapons[weaponName]
	if not weaponConfig then
		return false, "Unknown weapon."
	end
	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end
	if data.OwnedWeapons[weaponName] then
		return false, "Already owned."
	end
	if not data.UnlockedZones[weaponConfig.Zone] then
		return false, "Unlock " .. GameConfig.Zones[weaponConfig.Zone].Name .. " first!"
	end
	if not DataManager.TrySpend(player, "Gold", weaponConfig.Cost) then
		return false, "Not enough Gold."
	end
	data.OwnedWeapons[weaponName] = true
	DataManager.PushToClient(player)
	return true, "Purchased " .. weaponConfig.DisplayName .. "!"
end

Remotes.EquipWeapon.OnServerInvoke = function(player: Player, weaponName: any)
	if type(weaponName) ~= "string" then
		return false, "Invalid request."
	end
	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end
	if not GameConfig.Weapons[weaponName] then
		return false, "Unknown weapon."
	end
	if not data.OwnedWeapons[weaponName] then
		return false, "You do not own that weapon."
	end
	data.EquippedWeapon = weaponName
	DataManager.PushToClient(player)
	return true, "Equipped " .. GameConfig.Weapons[weaponName].DisplayName .. "."
end

--------------------------------------------------------------------------------
-- ZONE UNLOCKING
--------------------------------------------------------------------------------
Remotes.UnlockZone.OnServerInvoke = function(player: Player, zoneId: any)
	if type(zoneId) ~= "number" then
		return false, "Invalid request."
	end
	zoneId = math.floor(zoneId)
	local zoneConfig = GameConfig.Zones[zoneId]
	if not zoneConfig then
		return false, "Unknown zone."
	end
	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end
	if data.UnlockedZones[zoneId] then
		return false, "Already unlocked."
	end
	-- Zones unlock strictly in order.
	if not data.UnlockedZones[zoneId - 1] then
		return false, "Unlock the previous zone first."
	end
	if not DataManager.TrySpend(player, "Gold", zoneConfig.UnlockCost) then
		return false, "Not enough Gold. Need " .. zoneConfig.UnlockCost .. "."
	end
	data.UnlockedZones[zoneId] = true
	data.CurrentZone = zoneId
	DataManager.PushToClient(player)
	Remotes.NotifyText:FireClient(player,
		zoneConfig.Name .. " unlocked!", Color3.fromRGB(120, 255, 140))
	return true, zoneConfig.Name .. " unlocked!"
end

--------------------------------------------------------------------------------
-- REBIRTH
--------------------------------------------------------------------------------
Remotes.Rebirth.OnServerInvoke = function(player: Player)
	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end
	local cost = math.floor(
		GameConfig.Rebirth.BaseCost * (GameConfig.Rebirth.CostGrowth ^ data.Rebirths))
	if data.Gold < cost then
		return false, "Rebirth costs " .. cost .. " Gold."
	end

	-- Rebirth wipes Gold + zone progress, keeps pets/weapons, boosts multipliers.
	data.Gold = 0
	data.CurrentZone = 1
	data.UnlockedZones = { [1] = true }
	data.Rebirths += 1

	-- Recompute multipliers from scratch: base 1 + rebirth bonus, then re-apply
	-- permanent gamepass effects (kept in OwnedGamepasses).
	data.CoinMultiplier = 1 + data.Rebirths * GameConfig.Rebirth.CoinMultiplierPerRebirth
	data.LuckMultiplier = 1 + data.Rebirths * GameConfig.Rebirth.LuckMultiplierPerRebirth
	if data.OwnedGamepasses[tostring(GameConfig.Gamepasses.DoubleCoins.Id)] then
		data.CoinMultiplier *= GameConfig.Gamepasses.DoubleCoins.Effect.CoinMultiplier
	end

	DataManager.PushToClient(player)
	Remotes.NotifyText:FireClient(player,
		("Rebirth %d! Coins x%.1f, Luck x%.1f"):format(
			data.Rebirths, data.CoinMultiplier, data.LuckMultiplier),
		Color3.fromRGB(255, 220, 90))
	return true, "Rebirth complete!"
end

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	lastSwing[player] = nil
	for _, state in pairs(targets) do
		state.LastAttackers[player] = nil
	end
end)

scanZones()
print("[CoreEngine] Online.")
