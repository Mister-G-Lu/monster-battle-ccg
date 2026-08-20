local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local configuration = require "manager.configuration"

local chest_logic = require "logic.chest"
local mail_logic = require "logic.mail"
local daily_logic = require "logic.daily"
local challenge_logic =require "logic.challenge"
local rank_logic = require "logic.rank"
local friend_logic = require "logic.friend"
local pve_logic = require"logic.pve"
local user_logic = require "logic.user"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local arena_logic = require "logic.arena"
local CHEST_STAGE = constants.CHEST_STAGE

local meta = class("home_panel",function ()
    return ui_helper:LoadCocosUI("interface/world/main_panel.csb")
end)

function meta:ctor()

    local arena_node = require("modules.world.system.arena_panel").new()
    arena_node:setVisible(false)
    self:addChild(arena_node)
    self.arena_node = arena_node
    -- 邮件入口
    self.mail_btn = self:getChildByName("mailbox")
    -- new mail tips animation
    self.mail_btn_newtip = self.mail_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(self.mail_btn_newtip, "interface/world/newtip.csb")
    self.mail_btn_newtip:PlayAnimation("loop", true)

    -- PVP
    self.pvp_btn = self:getChildByName("pvpbtn")
    -- 事件
    self.event_btn = self:getChildByName("event")
    -- 补充包
    self.card_chest_btn = self:getChildByName("cardbag")
    -- 卡本
    self.card_book_btn = self:getChildByName("cardbook")
    -- 商店
    self.shop_btn = self:getChildByName("shop")
    -- 帮助
    self.help_btn = self:getChildByName("helpbtn")
    local path = "interface/world/help_btn.csb"
    ui_helper:BindTimeLine(self.help_btn, path)
    ui_helper:SetCocosSetting(self.help_btn, path)
    if configuration:IsShowHelp() then
        self.help_btn:PlayAnimation("normal", true)
    else
        self.help_btn:PlayAnimation("loop", true)
    end

    -- 账号绑定
    self.setting_btn = self:getChildByName("setting")

    -- 好友
    self.friend_btn = self:getChildByName("friend")

    self.friend_btn_newtip = self.friend_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(self.friend_btn_newtip, "interface/world/newtip.csb")
    self.friend_btn_newtip:PlayAnimation("loop", true)
    self.friend_btn_newtip:setVisible(false)

    if friend_logic.notice ~= nil then
        self.friend_btn_newtip:setVisible(true)
    end

    -- 社区
    -- self.community_btn = self:getChildByName("community")
    -- PVE
    self.pve_btn = self:getChildByName("pvebtn")
    -- self.pve_touch_panel = self.pve_list:getChildByName("touch_panel")

    -- if ThirdHelper and ThirdHelper["isCommunity"] and ThirdHelper["isCommunity"]() then
    --     self.community_btn:setVisible(true)
    -- else
    --     self.community_btn:setVisible(false)
    -- end

    -- local text_loader = require "manager.text_loader"
    -- if text_loader:IsTraditional() then
        -- self.community_btn:setVisible(false)
    -- end

    -- 排行
    self.rank_btn = self:getChildByName("ladder")

    -- -- 每日奖励
    -- self.reward_tip_node = self:getChildByName("reward_tip")
    -- self.reward_tip_node:setVisible(daily_logic.login_reward > 0)

    -- 任务
    self.task_btn = self:getChildByName("task")
    local tip = self.task_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(tip, "interface/world/newtip.csb")
    tip:PlayAnimation("loop", true)
    tip:setVisible(user_logic.task_hint)
    self.task_btn.tips_node = tip

    -- 成就
    self.achievement_btn = self:getChildByName("achievement")
    local tip = self.achievement_btn:getChildByName("newtip")
    ui_helper:BindTimeLine(tip, "interface/world/newtip.csb")
    tip:PlayAnimation("loop", true)
    tip:setVisible(user_logic.achi_hint)
    self.achievement_btn.tips_node = tip

    self:RegisterEvent()
    graphic:DispatchEvent("refresh_new_mail", mail_logic.new_mail_num)
    graphic:DispatchEvent("refresh_new_friendtip", friend_logic.friendtip_show)
    graphic:DispatchEvent("check_pve_is_turned",arena_logic.arena_stage,arena_logic.level)
    self:RegisterWidgetEvent()
end

function meta:Update(elapsed_time)
    -- self.reward_tip_node:setVisible(daily_logic.login_reward > 0)
    self.arena_node:Update(elapsed_time)
end


-- 注册渲染事件
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

    -- 新邮件
    graphic:RegisterEvent("refresh_new_mail", function(new_mail_num)
        if new_mail_num > 0 then
            self.mail_btn_newtip:setVisible(true)
        else
            self.mail_btn_newtip:setVisible(false)
        end
    end)
    --好友消息提示
    graphic:RegisterEvent("refresh_new_friendtip", function(show)
        if show then
            self.friend_btn_newtip:setVisible(true)
        else
            self.friend_btn_newtip:setVisible(false)
        end
    end)
    --检查是否开放PVE
    graphic:RegisterEvent("check_pve_is_turned", function (stage,level)
        if stage == constants.ARENA_STAGE.casual and level == 1 then
            self.pve_btn:setVisible(false)
        else
            self.pve_btn:setVisible(true)
        end
    end)

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

-- 注册UI事件
function meta:RegisterWidgetEvent()
    -- 邮件
    ui_helper:AddClick(self.mail_btn, function ()
        mail_logic:Query()
    end)
    -- PVP
    ui_helper:AddClick(self.pvp_btn, function ()
        graphic:DispatchEvent("show_arena_panel")
    end)
    -- PVE
    ui_helper:AddClick(self.pve_btn, function ()
        pve_logic:ShowPve()
    end)

    -- 事件 --约战
    ui_helper:AddClick(self.event_btn, function ()
        challenge_logic:Query()
    end)

    -- 任务
    ui_helper:AddClick(self.task_btn, function ()
        local task_logic = require "logic.task"
        task_logic:ShowTaskPanel()
    end)

    -- 补充包
    ui_helper:AddClick(self.card_chest_btn, function ()
        graphic:DispatchEvent("push_world_panel", "chest", "bag_panel")
    end)

    -- 卡本
    ui_helper:AddClick(self.card_book_btn, function ()
        graphic:DispatchEvent("switch_system_module", "deck")
    end)

    -- 商店
    ui_helper:AddClick(self.shop_btn, function ()
    end)

    -- 帮助
    local button = self.help_btn:getChildByName("helpbtn")
    ui_helper:AddClick(button, function ()
        if not configuration:IsShowHelp() then
            configuration:SetShowHelp(true)
            self.help_btn:PlayAnimation("normal", true)
        end
        graphic:DispatchEvent("push_world_panel", "world", "help_panel")
    end)

    --账号绑定
    ui_helper:AddClick(self.setting_btn, function ()
        graphic:DispatchEvent("push_world_panel", "setting", "global_setting_panel")
    end)

    --好友
    ui_helper:AddClick(self.friend_btn, function ()
        friend_logic:Query()
    end)

    -- community_btn removed (ThirdHelper unavailable offline)

    -- 排行
    ui_helper:AddClick(self.rank_btn, function ()
        rank_logic:QueryRank()
    end)

    -- 成就
    ui_helper:AddClick(self.achievement_btn, function ()
        local achievement_logic = require "logic.achievement"
        achievement_logic:Query()
    end)

end

return meta
