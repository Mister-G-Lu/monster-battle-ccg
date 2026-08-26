local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local configuration = require "manager.configuration"

local mail_logic = require "logic.mail"
local user_logic = require "logic.user"

local meta = class("home_panel",function ()
    return ui_helper:LoadCocosUI("interface/world/main_panel.csb")
end)

function meta:ctor()

    local arena_node = require("modules.world.system.arena_panel").new()
    arena_node:setVisible(false)
    self:addChild(arena_node)
    self.arena_node = arena_node

    -- The Shadow Road is a real world-system module. Do not construct it as
    -- a child of this .csb: a pushed battle scene can then return to a hidden
    -- child while the stock Adventure panel takes focus, producing an empty
    -- screen. OpenCampaign routes through world_scene instead.
    -- Mail entry
    self.mail_btn = self:getChildByName("mailbox")
    -- new mail tips animation
    self.mail_btn_newtip = self.mail_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(self.mail_btn_newtip, "interface/world/newtip.csb")
    self.mail_btn_newtip:PlayAnimation("loop", true)

    -- The stock home bar has two doors to a fight: "Battle" (pvpbtn) and
    -- "Adventure" (pvebtn). The Shadow Road is an adventure campaign, so
    -- Adventure is the visible canonical entry. Battle remains wired as a
    -- compatibility fallback for layouts that do not expose pvebtn.
    self.pvp_btn = self:getChildByName("pvpbtn")
    self.pve_btn = self:getChildByName("pvebtn")
    self.campaign_btn = self.pve_btn or self.pvp_btn
    if self.pve_btn then self.pve_btn:setVisible(true) end
    if self.pvp_btn then self.pvp_btn:setVisible(self.pve_btn == nil) end

    -- Events / challenge rooms need a second player. Hide in single-player.
    self.event_btn = self:getChildByName("event")
    if self.event_btn then self.event_btn:setVisible(false) end

    -- Booster packs
    self.card_chest_btn = self:getChildByName("cardbag")
    -- Card album
    self.card_book_btn = self:getChildByName("cardbook")
    -- Shop has no catalogue offline (IAP / server store). Hide the dead button.
    self.shop_btn = self:getChildByName("shop")
    if self.shop_btn then self.shop_btn:setVisible(false) end
    -- Help
    self.help_btn = self:getChildByName("helpbtn")
    local path = "interface/world/help_btn.csb"
    ui_helper:BindTimeLine(self.help_btn, path)
    ui_helper:SetCocosSetting(self.help_btn, path)
    if configuration:IsShowHelp() then
        self.help_btn:PlayAnimation("normal", true)
    else
        self.help_btn:PlayAnimation("loop", true)
    end

    -- Account binding
    self.setting_btn = self:getChildByName("setting")

    -- Friends / social — empty list offline. Hide the entry.
    self.friend_btn = self:getChildByName("friend")
    if self.friend_btn then
        self.friend_btn:setVisible(false)
        self.friend_btn_newtip = self.friend_btn:getChildByName("newtip")
        if self.friend_btn_newtip then
            self.friend_btn_newtip:setVisible(false)
        end
    end

    -- Rankings — a one-row dummy ladder. Hide; record lives in PVE / arena.
    self.rank_btn = self:getChildByName("ladder")
    if self.rank_btn then self.rank_btn:setVisible(false) end

    -- -- Daily reward
    -- self.reward_tip_node = self:getChildByName("reward_tip")
    -- self.reward_tip_node:setVisible(daily_logic.login_reward > 0)

    -- Tasks
    self.task_btn = self:getChildByName("task")
    local tip = self.task_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(tip, "interface/world/newtip.csb")
    tip:PlayAnimation("loop", true)
    tip:setVisible(user_logic.task_hint)
    self.task_btn.tips_node = tip

    -- Achievements
    self.achievement_btn = self:getChildByName("achievement")
    local tip = self.achievement_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(tip, "interface/world/newtip.csb")
    tip:PlayAnimation("loop", true)
    tip:setVisible(user_logic.achi_hint)
    self.achievement_btn.tips_node = tip

    self:RegisterEvent()
    graphic:DispatchEvent("refresh_new_mail", mail_logic.new_mail_num)
    -- The campaign door is always available in this build — never hide it
    -- behind the old "unlock after first arena match" gate.
    if self.campaign_btn then self.campaign_btn:setVisible(true) end
    self:RegisterWidgetEvent()
end

-- The Shadow Road is the only offline Adventure. Route through world_scene so
-- its full-screen panel is a sibling of home, survives a pushed battle scene,
-- and can be selected again when the result screen exits. Never fall back to
-- the archived stock PvE list: it has no campaign content to show.
function meta:OpenCampaign()
    graphic:DispatchEvent("switch_system_module", "campaign")
end

function meta:Update(elapsed_time)
    -- self.reward_tip_node:setVisible(daily_logic.login_reward > 0)
    self.arena_node:Update(elapsed_time)
end


-- Register render events
function meta:RegisterEvent()
    graphic:RegisterEvent("refresh_new_task", function (is_show)
        if is_show then
            self.task_btn.tips_node:setVisible(true)
        else
            self.task_btn.tips_node:setVisible(false)
        end
    end)

    graphic:RegisterEvent("refresh_new_achievement", function (is_show)
        if is_show then
            self.achievement_btn.tips_node:setVisible(true)
        else
            self.achievement_btn.tips_node:setVisible(false)
        end
    end)

    -- New mail
    graphic:RegisterEvent("refresh_new_mail", function(new_mail_num)
        if new_mail_num > 0 then
            self.mail_btn_newtip:setVisible(true)
        else
            self.mail_btn_newtip:setVisible(false)
        end
    end)
    -- Friend / PVE-unlock events ignored: those buttons are gone or always on.

end

function meta:Show(callback)
    self:setVisible(true)
    if callback then callback() end
end
function meta:Hide()
    self:setVisible(false)
end
function meta:Refresh()
end

-- Register UI events
function meta:RegisterWidgetEvent()
    -- Mail
    ui_helper:AddClick(self.mail_btn, function ()
        mail_logic:Query()
    end)
    -- Adventure -> The Shadow Road campaign map. Both stock doors are bound
    -- so whichever one this .csb exposes lands in the campaign, not in the
    -- archived stock PvE menu.
    if self.pvp_btn then
        ui_helper:AddClick(self.pvp_btn, function ()
            self:OpenCampaign()
        end)
    end
    if self.pve_btn then
        ui_helper:AddClick(self.pve_btn, function ()
            self:OpenCampaign()
        end)
    end

    -- Tasks
    ui_helper:AddClick(self.task_btn, function ()
        local task_logic = require "logic.task"
        task_logic:ShowTaskPanel()
    end)

    -- Booster packs
    ui_helper:AddClick(self.card_chest_btn, function ()
        graphic:DispatchEvent("push_world_panel", "chest", "bag_panel")
    end)

    -- Card album
    ui_helper:AddClick(self.card_book_btn, function ()
        graphic:DispatchEvent("switch_system_module", "deck")
    end)

    -- Shop hidden (no catalogue)

    -- Help
    local button = self.help_btn:getChildByName("helpbtn")
    ui_helper:AddClick(button, function ()
        if not configuration:IsShowHelp() then
            configuration:SetShowHelp(true)
            self.help_btn:PlayAnimation("normal", true)
        end
        graphic:DispatchEvent("push_world_panel", "world", "help_panel")
    end)

    -- Account binding
    ui_helper:AddClick(self.setting_btn, function ()
        graphic:DispatchEvent("push_world_panel", "setting", "global_setting_panel")
    end)

    -- Achievements
    ui_helper:AddClick(self.achievement_btn, function ()
        local achievement_logic = require "logic.achievement"
        achievement_logic:Query()
    end)

end

return meta
