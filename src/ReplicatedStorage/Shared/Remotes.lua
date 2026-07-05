--!strict
--------------------------------------------------------------------------------
-- Remotes
-- ReplicatedStorage.Shared.Remotes
--
-- One require, both sides. On the server this module CREATES every remote the
-- game uses; on the client it yields until the server has replicated them.
-- Keeping the manifest in one file guarantees the two sides never drift.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_EVENTS = {
	"NodeHit",        -- client -> server : (nodeInstance)  swing at a resource node
	"CombatSwing",    -- client -> server : (enemyInstance) swing at an enemy/boss
	"LootDropped",    -- server -> client : (lootPayload)   3D loot burst to animate
	"DataChanged",    -- server -> client : (dataSnapshot)  currency / stat refresh
	"PetHatched",     -- server -> client : (petInfo)       hatch reveal animation
	"NotifyText",     -- server -> client : (message, color) toast messages
	"ToggleAutoHatch",-- client -> server : (enabled)       auto-hatch preference
}

local REMOTE_FUNCTIONS = {
	"HatchEgg",       -- client -> server : (eggName) -> petInfo | nil, errorMessage
	"EquipWeapon",    -- client -> server : (weaponName) -> success, errorMessage
	"EquipPet",       -- client -> server : (petUUID)    -> success, errorMessage
	"BuyWeapon",      -- client -> server : (weaponName) -> success, errorMessage
	"UnlockZone",     -- client -> server : (zoneId)     -> success, errorMessage
	"Rebirth",        -- client -> server : ()           -> success, errorMessage
	"GetData",        -- client -> server : ()           -> full sanitized snapshot
}

local FOLDER_NAME = "Remotes"

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(REMOTE_EVENTS) do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
		Remotes[name] = folder:FindFirstChild(name)
	end
	for _, name in ipairs(REMOTE_FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
		Remotes[name] = folder:FindFirstChild(name)
	end
else
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	for _, name in ipairs(REMOTE_EVENTS) do
		Remotes[name] = folder:WaitForChild(name)
	end
	for _, name in ipairs(REMOTE_FUNCTIONS) do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
