--!strict
--------------------------------------------------------------------------------
-- TradeManager
-- ServerScriptService.TradeManager (Script)
--
-- Secure player-to-player pet trading. Every anti-scam rule the big pet sims
-- learned the hard way is enforced HERE, server-side:
--
--   * Both players must have loaded profiles; one active trade per player.
--   * Offers hold up to Trading.MaxPetsPerSide pet UUIDs; every UUID is
--     re-validated against the CURRENT inventory at every step.
--   * ANY offer change clears BOTH confirmations (no last-second swaps).
--   * After both confirm, a visible 3-second countdown runs; any change,
--     cancel, or disconnect during it aborts the trade.
--   * The final swap re-validates ownership and inventory caps, mutates both
--     inventories with no yields in between (atomic), unequips traded pets,
--     then force-saves BOTH profiles so a server crash can't dupe.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()

local MAX_PER_SIDE = GameConfig.Trading.MaxPetsPerSide
local COUNTDOWN = GameConfig.Trading.ConfirmCountdownSeconds
local REQUEST_TTL = 30 -- seconds an unanswered trade request stays valid

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
-- [target Player] = { [requester Player] = sentAtClock }
local pendingRequests: { [Player]: { [Player]: number } } = {}

-- One session object shared by both participants:
-- { A, B, Offers = {[Player]={uuid,...}}, Confirmed = {[Player]=bool},
--   CountdownToken = number, Executing = bool }
local sessionOf: { [Player]: any } = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function petByUUID(data: any, uuid: string): any?
	for _, pet in ipairs(data.OwnedPets) do
		if pet.UUID == uuid then
			return pet
		end
	end
	return nil
end

local function offerInfoFor(player: Player, uuids: { string }): { any }
	local data = DataManager.GetLoaded(player)
	local info = {}
	if not data then
		return info
	end
	for _, uuid in ipairs(uuids) do
		local pet = petByUUID(data, uuid)
		if pet then
			table.insert(info, {
				UUID = pet.UUID,
				PetName = pet.PetName,
				StatBonus = pet.StatBonus,
				Variant = pet.Variant or "Normal",
			})
		end
	end
	return info
end

local function otherOf(session: any, player: Player): Player
	return if session.A == player then session.B else session.A
end

local function broadcast(session: any)
	for _, participant in ipairs({ session.A, session.B }) do
		local partner = otherOf(session, participant)
		Remotes.TradeUpdated:FireClient(participant, {
			Partner = partner.Name,
			YourOffer = offerInfoFor(participant, session.Offers[participant]),
			TheirOffer = offerInfoFor(partner, session.Offers[partner]),
			YouConfirmed = session.Confirmed[participant],
			TheyConfirmed = session.Confirmed[partner],
			Countdown = session.CountdownToken ~= 0 and COUNTDOWN or nil,
		})
	end
end

local function endSession(session: any, notify: string?)
	session.CountdownToken = 0
	for _, participant in ipairs({ session.A, session.B }) do
		if sessionOf[participant] == session then
			sessionOf[participant] = nil
		end
		Remotes.TradeUpdated:FireClient(participant, nil)
		if notify then
			Remotes.NotifyText:FireClient(participant, notify, Color3.fromRGB(255, 160, 90))
		end
	end
end

-- Any offer/confirm mutation invalidates a running countdown.
local function resetConfirmations(session: any)
	session.Confirmed[session.A] = false
	session.Confirmed[session.B] = false
	session.CountdownToken = 0
end

--------------------------------------------------------------------------------
-- THE SWAP (called only from the countdown, never directly by a remote)
--------------------------------------------------------------------------------
local function executeTrade(session: any): boolean
	if session.Executing then
		return false
	end
	session.Executing = true

	local playerA, playerB = session.A, session.B
	local dataA = DataManager.GetLoaded(playerA)
	local dataB = DataManager.GetLoaded(playerB)
	if not dataA or not dataB then
		return false
	end

	-- FINAL validation pass: every offered UUID must still be owned, and both
	-- inventories must fit their incoming pets after outgoing ones leave.
	local offerA, offerB = session.Offers[playerA], session.Offers[playerB]
	for _, uuid in ipairs(offerA) do
		if not petByUUID(dataA, uuid) then
			return false
		end
	end
	for _, uuid in ipairs(offerB) do
		if not petByUUID(dataB, uuid) then
			return false
		end
	end
	local maxOwned = GameConfig.Combat.MaxOwnedPets
	if (#dataA.OwnedPets - #offerA + #offerB) > maxOwned then
		return false
	end
	if (#dataB.OwnedPets - #offerB + #offerA) > maxOwned then
		return false
	end

	-- Atomic mutation block: NO yields from here to the end of the swap.
	local function extract(data: any, uuids: { string }): { any }
		local pulled = {}
		for _, uuid in ipairs(uuids) do
			for index, pet in ipairs(data.OwnedPets) do
				if pet.UUID == uuid then
					table.insert(pulled, table.remove(data.OwnedPets, index))
					break
				end
			end
			for equippedIndex, equippedUuid in ipairs(data.EquippedPets) do
				if equippedUuid == uuid then
					table.remove(data.EquippedPets, equippedIndex)
					break
				end
			end
		end
		return pulled
	end

	local pulledA = extract(dataA, offerA)
	local pulledB = extract(dataB, offerB)
	for _, pet in ipairs(pulledA) do
		table.insert(dataB.OwnedPets, pet)
	end
	for _, pet in ipairs(pulledB) do
		table.insert(dataA.OwnedPets, pet)
	end
	-- End of atomic block.

	DataManager.PushToClient(playerA)
	DataManager.PushToClient(playerB)

	-- Persist both sides immediately so a crash cannot roll back one half.
	task.spawn(DataManager.ForceSave, playerA)
	task.spawn(DataManager.ForceSave, playerB)

	Remotes.NotifyText:FireClient(playerA,
		("Trade complete! Received %d pet(s)."):format(#pulledB), Color3.fromRGB(120, 255, 140))
	Remotes.NotifyText:FireClient(playerB,
		("Trade complete! Received %d pet(s)."):format(#pulledA), Color3.fromRGB(120, 255, 140))
	return true
end

--------------------------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------------------------
Remotes.TradeRequest.OnServerInvoke = function(player: Player, targetUserId: any)
	if type(targetUserId) ~= "number" then
		return false, "Invalid request."
	end
	local target = Players:GetPlayerByUserId(math.floor(targetUserId))
	if not target or target == player then
		return false, "Player not found."
	end
	if not DataManager.IsLoaded(player) or not DataManager.IsLoaded(target) then
		return false, "Data still loading."
	end
	if sessionOf[player] then
		return false, "You are already trading."
	end
	if sessionOf[target] then
		return false, target.Name .. " is already trading."
	end

	pendingRequests[target] = pendingRequests[target] or {}
	pendingRequests[target][player] = os.clock()
	Remotes.TradeRequested:FireClient(target, player.Name, player.UserId)
	return true, "Request sent to " .. target.Name .. "."
end

Remotes.TradeRespond.OnServerInvoke = function(player: Player, requesterUserId: any, accept: any)
	if type(requesterUserId) ~= "number" then
		return false, "Invalid request."
	end
	local requester = Players:GetPlayerByUserId(math.floor(requesterUserId))
	local requests = pendingRequests[player]

	if not requester or not requests or not requests[requester] then
		return false, "Request expired."
	end
	if (os.clock() - requests[requester]) > REQUEST_TTL then
		requests[requester] = nil
		return false, "Request expired."
	end
	requests[requester] = nil

	if accept ~= true then
		Remotes.NotifyText:FireClient(requester,
			player.Name .. " declined the trade.", Color3.fromRGB(255, 160, 90))
		return true, "Declined."
	end
	if sessionOf[player] or sessionOf[requester] then
		return false, "One of you is already trading."
	end
	if not DataManager.IsLoaded(player) or not DataManager.IsLoaded(requester) then
		return false, "Data still loading."
	end

	local session = {
		A = requester,
		B = player,
		Offers = { [requester] = {}, [player] = {} },
		Confirmed = { [requester] = false, [player] = false },
		CountdownToken = 0,
		Executing = false,
	}
	sessionOf[requester] = session
	sessionOf[player] = session
	broadcast(session)
	return true, "Trade started."
end

Remotes.TradeSetOffer.OnServerInvoke = function(player: Player, uuids: any)
	local session = sessionOf[player]
	if not session or session.Executing then
		return false, "No active trade."
	end
	if type(uuids) ~= "table" then
		return false, "Invalid offer."
	end

	local data = DataManager.GetLoaded(player)
	if not data then
		return false, "Data still loading."
	end

	-- Sanitize: strings only, deduplicated, owned by the sender, capped.
	local seen: { [string]: boolean } = {}
	local clean = {}
	for _, uuid in ipairs(uuids) do
		if type(uuid) == "string" and not seen[uuid] and petByUUID(data, uuid) then
			seen[uuid] = true
			table.insert(clean, uuid)
			if #clean >= MAX_PER_SIDE then
				break
			end
		end
	end

	session.Offers[player] = clean
	resetConfirmations(session) -- ANY change voids both confirmations
	broadcast(session)
	return true, "Offer updated."
end

Remotes.TradeConfirm.OnServerInvoke = function(player: Player)
	local session = sessionOf[player]
	if not session or session.Executing then
		return false, "No active trade."
	end

	session.Confirmed[player] = true
	local partner = otherOf(session, player)

	if session.Confirmed[partner] then
		-- Both confirmed: start the anti-scam countdown. The token invalidates
		-- this timer if anything changes while it runs.
		local token = os.clock()
		session.CountdownToken = token
		broadcast(session)

		task.delay(COUNTDOWN, function()
			if session.CountdownToken ~= token or session.Executing then
				return
			end
			if not session.A.Parent or not session.B.Parent then
				endSession(session, "Trade cancelled: player left.")
				return
			end
			if executeTrade(session) then
				endSession(session, nil)
			else
				endSession(session, "Trade failed validation and was cancelled.")
			end
		end)
	else
		broadcast(session)
	end
	return true, "Confirmed."
end

Remotes.TradeCancel.OnServerInvoke = function(player: Player)
	local session = sessionOf[player]
	if session and not session.Executing then
		endSession(session, "Trade cancelled.")
	end
	return true
end

--------------------------------------------------------------------------------
-- LIFECYCLE
--------------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	local session = sessionOf[player]
	if session and not session.Executing then
		endSession(session, "Trade cancelled: player left.")
	end
	pendingRequests[player] = nil
	for _, requests in pairs(pendingRequests) do
		requests[player] = nil
	end
end)

print("[TradeManager] Online. Max " .. MAX_PER_SIDE .. " pets per side.")
