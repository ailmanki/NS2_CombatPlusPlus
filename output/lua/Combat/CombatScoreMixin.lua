--[[
 * Natural Selection 2 - Combat++ Mod
 * Authors:
 *          WhiteWizard
 *
 * New mixin to track Combat++ specific values for players.
 *
 * Provides a progression system (xp->rank) and awards skill points when
 * certain criteria is met.
]]

Script.Load("lua/CPPUtilities.lua")

CombatScoreMixin = CreateMixin(CombatScoreMixin)
CombatScoreMixin.type = "CombatScore"

CombatScoreMixin.networkVars =
{
    combatXP = "integer",
    combatRank = "integer",
    combatSkillPoints = "integer"
}

function CombatScoreMixin:__initmixin()

    self:ResetCombatScores()

end

function CombatScoreMixin:GetCombatXP()
    return self.combatXP
end

function CombatScoreMixin:AddXP(xp, source, targetId)

    if Server and xp and xp ~= 0 and not GetGameInfoEntity():GetWarmUpActive() then

        -- Check to see if xp should be scaled
        if CombatPlusPlus_GetIsScalableXPType(source) then
            xp = ScaleXPByDistance(self, xp)
        end

        self.combatXP = Clamp(self.combatXP + xp, 0, kMaxCombatXP)
        local currentRank = CombatPlusPlus_GetRankByXP(self.combatXP)

        -- check for rank change
        local numberOfRanksEarned = currentRank - self.combatRank
        
        -- update current rank
        self.combatRank = currentRank

        if numberOfRanksEarned > 0 then

            --give skill points for number of ranks earned
            self:GiveCombatSkillPoints(kSkillPointSourceType.LevelUp, numberOfRanksEarned)

            if self.UpgradeManager then
                self.UpgradeManager:UpdateUnlocks(true)
            end
            
        end

        -- notify the client so that we can print the xp gain on screen
        Server.SendNetworkMessage(Server.GetOwner(self), "CombatScoreUpdate", { xp = xp, source = source, targetId = targetId }, true)

        if not self.combatXPGainedCurrentLife then
            self.combatXPGainedCurrentLife = 0
        end

        self.combatXPGainedCurrentLife = self.combatXPGainedCurrentLife + xp

    end

end

function CombatScoreMixin:GetCombatRank()
    return self.combatRank
end

function CombatScoreMixin:GiveCombatRank(rank)

    local rankToGive = Clamp(rank, 1, kMaxCombatRank)
    local xpToGive = CombatPlusPlus_GetXPThresholdByRank(rankToGive) - self.combatXP

    self:AddXP(xpToGive, kXPSourceType.Console, Entity.invalidId)

end

function CombatScoreMixin:GetCombatSkillPoints()
    return self.combatSkillPoints
end

function CombatScoreMixin:SetCombatSkillPoints(skillPoints)
    self.combatSkillPoints = Clamp(skillPoints, 0, kMaxCombatSkillPoints)
end

function CombatScoreMixin:GiveCombatSkillPoints(source, points)

    if Server and not GetGameInfoEntity():GetWarmUpActive() then

        if points == nil then
            points = 1
        end

        self.combatSkillPoints = Clamp(self.combatSkillPoints + points, 0, kMaxCombatSkillPoints)

        if source ~= kXPSourceType.Refund then
            -- notify the client about the new skill points
            Server.SendNetworkMessage(Server.GetOwner(self), "CombatSkillPointUpdate", { source = source, kills = self.killsGainedCurrentLife, assists = self.assistsGainedCurrentLife }, true)
        end

    end

end

function CombatScoreMixin:SpendSkillPoints(pointsToSpend)

    if Server and not GetGameInfoEntity():GetWarmUpActive() then

        if (self.combatSkillPoints - pointsToSpend) < 0 then
            Shared.Message("Warning: Skill points spent that were not available.")
        end

        self.combatSkillPoints = Clamp(self.combatSkillPoints - pointsToSpend, 0, kMaxCombatSkillPoints)

    end

end

if Server then

    function CombatScoreMixin:CopyPlayerDataFrom(player)

        self.combatXP = player.combatXP
        self.combatRank = player.combatRank
        self.combatSkillPoints = player.combatSkillPoints

    end

    function CombatScoreMixin:OnKill()

        self.combatXPGainedCurrentLife = 0
        self.killsGainedCurrentLife = 0
        self.assistsGainedCurrentLife = 0
        self.damageDealtCurrentLife = 0
        self.damageDealerAwardReceived = false
        self.armorWeledSinceLastXPAward = 0
        self.healingAmountSinceLastXPAward = 0
        self.damageSinceLastXPAward = 0

    end

end

function CombatScoreMixin:AddCombatKill(victimRank)

    if GetGameInfoEntity():GetWarmUpActive() then return end

    if not self.combatXP then
        self.combatXP = 0
    end

    if  not self.killsGainedCurrentLife then
        self.killsGainedCurrentLife = 0
    end

    self.killsGainedCurrentLife = self.killsGainedCurrentLife + 1

    if self.killsGainedCurrentLife == kKillsForRampageReward then
        self:GiveCombatSkillPoints(kSkillPointSourceType.KillStreak)
    end

    self:AddXP(CombatPlusPlus_GetBaseKillXP(victimRank), kXPSourceType.Kill, Entity.invalidId)

end

function CombatScoreMixin:AddCombatAssistKill(victimRank)

    if GetGameInfoEntity():GetWarmUpActive() then return end

    if not self.combatXP then
        self.combatXP = 0
    end

    if not self.assistsGainedCurrentLife then
        self.assistsGainedCurrentLife = 0
    end

    self.assistsGainedCurrentLife = self.assistsGainedCurrentLife + 1

    if self.assistsGainedCurrentLife == kAssistsForAssistReward then
        self:GiveCombatSkillPoints(kSkillPointSourceType.AssistStreak)
    end

    local xp = CombatPlusPlus_GetBaseKillXP(victimRank) * kXPAssistModifier
    self:AddXP(xp, kXPSourceType.Assist, Entity.invalidId)

end

function CombatScoreMixin:AddCombatNearbyKill(victimRank)
    if GetGameInfoEntity():GetWarmUpActive() then return end

    if not self.combatXP then
        self.combatXP = 0
    end

    local xp = CombatPlusPlus_GetBaseKillXP(victimRank) * kNearbyKillXPModifier
    self:AddXP(xp, kXPSourceType.Nearby, Entity.invalidId)
end

function CombatScoreMixin:AddCombatDamage(damage)

    if GetGameInfoEntity():GetWarmUpActive() then return end

    if not self.combatXP then
        self.combatXP = 0
    end

    if not self.damageDealtCurrentLife then
        self.damageDealtCurrentLife = 0
    end

    self.damageDealtCurrentLife = self.damageDealtCurrentLife + damage

    if not self.damageDealerAwardReceived and self.damageDealtCurrentLife >= kDamageForDamageDealerAward then
        self:GiveCombatSkillPoints(kSkillPointSourceType.DamageDealer)
        self.damageDealerAwardReceived = true
    end

    self.damageSinceLastXPAward = self.damageSinceLastXPAward + damage

    -- if the current damage amount crosses the threshold required, reward a little xp
    if self.damageSinceLastXPAward >= kDamageRequiredXPReward then

        -- make sure not to let the remaining damage points "leak"
        self.damageSinceLastXPAward = self.damageSinceLastXPAward - kDamageRequiredXPReward

        -- add the xp
        self:AddXP(kDamageRequiredXPReward * kDamageXPModifier, kXPSourceType.Damage)

    end

end

function CombatScoreMixin:AddCombatWeldPoints(weldAmount)

    if GetGameInfoEntity():GetWarmUpActive() then return end

    if not self.combatXP then
        self.combatXP = 0
    end

    if not self.armorWeledSinceLastXPAward then
        self.armorWeledSinceLastXPAward = 0
    end

    self.armorWeledSinceLastXPAward = self.armorWeledSinceLastXPAward + weldAmount

    -- if the current weld amount crosses the threshold required, reward a little xp
    if self.armorWeledSinceLastXPAward >= kWeldingRequiredXPReward then

        -- make sure not to let the remaining weld points "leak"
        self.armorWeledSinceLastXPAward = self.armorWeledSinceLastXPAward - kWeldingRequiredXPReward

        -- add the xp
        self:AddXP(kWeldingRequiredXPReward * kWeldingXPModifier, kXPSourceType.Weld)

    end

end

function CombatScoreMixin:AddCombatHealingPoints(healingAmount)

    if GetGameInfoEntity():GetWarmUpActive() then return end

    if not self.combatXP then
        self.combatXP = 0
    end

    if not self.healingAmountSinceLastXPAward then
        self.healingAmountSinceLastXPAward = 0
    end

    self.healingAmountSinceLastXPAward = self.healingAmountSinceLastXPAward + healingAmount

    -- if the current healing amount crosses the threshold required, reward a little xp
    if self.healingAmountSinceLastXPAward >= kHealingRequiredXPReward then

        -- make sure not to let the remaining healing points "leak"
        self.healingAmountSinceLastXPAward = self.healingAmountSinceLastXPAward - kHealingRequiredXPReward

        -- add the xp
        self:AddXP(kHealingRequiredXPReward * kHealingXPModifier, kXPSourceType.Heal)

    end

end

function CombatScoreMixin:ResetCombatScores()

    self.combatXP = 0
    self.combatRank = 1
    self.combatSkillPoints = kStartPoints
    self.combatXPGainedCurrentLife = 0
    self.killsGainedCurrentLife = 0
    self.assistsGainedCurrentLife = 0
    self.damageDealtCurrentLife = 0
    self.damageDealerAwardReceived = false
    self.armorWeledSinceLastXPAward = 0
    self.healingAmountSinceLastXPAward = 0
    self.damageSinceLastXPAward = 0

end