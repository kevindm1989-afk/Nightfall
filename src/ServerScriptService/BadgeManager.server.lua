--!strict
--------------------------------------------------------------------------------
-- BadgeManager
-- ServerScriptService.BadgeManager (Script)
--
-- Milestone badges via BadgeService, driven entirely by GameSignals:
--   FirstRebirth  — complete a rebirth
--   FirstMythic   — hatch/obtain any Mythic-tier pet
--   AbyssWalker   — unlock Zone 4
--   HundredHatch  — reach 100 total hatches
--   FirstFusion   — complete a pet fusion
--
-- Awarded keys persist in the profile (BadgesAwarded) so we never re-hit the
-- BadgeService API for a badge the player already owns. Badge Ids of 0 are
-- treated as "not configured yet" and skipped silently.
--------------------------------------------------------------------------------

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local DataManager = require(script.Parent:WaitForChild("DataManager")).Init()
local GameSignals = require(script.Parent:WaitForChild("GameSignals"))

local function award(player: Player, badgeKey: string)
	local badge = GameConfig.Badges[badgeKey]
	if not badge or badge.Id == 0 then
		return
	end
	local data = DataManager.GetLoaded(player)
	if not data or data.BadgesAwarded[badgeKey] then
		return
	end
	data.BadgesAwarded[badgeKey] = true

	task.spawn(function()
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badge.Id)
		end)
		if ok then
			Remotes.NotifyText:FireClient(player,
				"Badge earned: " .. badge.Name .. "!", Color3.fromRGB(255, 220, 90))
		else
			-- Roll back the flag so a transient API failure retries next time.
			data.BadgesAwarded[badgeKey] = nil
			warn("[BadgeManager] AwardBadge failed: " .. tostring(err))
		end
	end)
end

GameSignals.Rebirthed:Connect(function(player)
	award(player, "FirstRebirth")
end)

GameSignals.ZoneUnlocked:Connect(function(player, zoneId)
	if zoneId == 4 then
		award(player, "AbyssWalker")
	end
end)

GameSignals.PetFused:Connect(function(player)
	award(player, "FirstFusion")
end)

GameSignals.PetObtained:Connect(function(player, petName)
	local petConfig = GameConfig.Pets[petName]
	if petConfig and petConfig.Tier == "Mythic" then
		award(player, "FirstMythic")
	end
	local data = DataManager.GetLoaded(player)
	if data and data.TotalHatches >= 100 then
		award(player, "HundredHatch")
	end
end)

print("[BadgeManager] Online.")
