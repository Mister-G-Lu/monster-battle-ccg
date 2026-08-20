local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local global = require "manager.global"

local user_logic = require "logic.user"
local resource_logic = require "logic.resource"
local data_template = require "manager.data_template"
local resource = require "manager.resource"
local PROFICIENCY_CONFIG = data_template.proficiency_config
local friend_logic = require "logic.friend"

local ITEM_CONFIG = data_template.item_config
local meta = class("world_panel",function ()
    return ui_helper:LoadCocosUI("interface/world_panel.csb")
end)

local SYSTEM_STATE = {
    home = "home",
    deck = "deck",
}


function meta:ctor()

    -- 顶部条状态
    local top_node = self:getChildByName("topbg")
    -- 姓名
    self.name_txt = top_node:getChildByName("name")
    -- 金钱
    self.money_txt = top_node:getChildByName("gold_value")
    ui_helper:SetResource(self.money_txt, resource_logic.money)
    -- 代币
    self.coin_txt = top_node:getChildByName("diamond_valeu")
    ui_helper:SetResource(self.coin_txt, resource_logic.coin)
    -- 等级
    self.level_txt = top_node:getChildByName("level")
    -- 称号
    self.level_name_txt = top_node:getChildByName("levelname")
    -- 经验池子
    self.exp_value_txt = top_node:getChildByName("exp_value")
    -- 经验loadingbar
    self.exp_bar = top_node:getChildByName("expbar")

    self.top_node = top_node

    self.is_top_visible = true

    self.cur_system = SYSTEM_STATE.home

    ui_helper:SetText(self.name_txt, user_logic.name.."#"..user_logic.user_id)

    local config = PROFICIENCY_CONFIG[user_logic.level]
    ui_helper:SetText(self.exp_value_txt, user_logic.exp.."/"..config.exp)
    ui_helper:SetText(self.level_txt, user_logic.level)
    self.exp_bar:setPercent(user_logic.exp / config.exp * 100)

    self:RegisterWidgetEvent()
    self:RegisterEvent()
end


function meta:SetTopVisible(is_visible)
    self.is_top_visible = is_visible
    self.top_node:setVisible(is_visible)
end

function meta:Update(elapsed_time)
end

function meta:RegisterEvent()

    graphic:RegisterEvent("update_money_value", function (value)
        ui_helper:SetResource(self.money_txt, value)
    end)

    graphic:RegisterEvent("update_coin_value", function (value)
        ui_helper:SetResource(self.coin_txt, value)
    end)

    graphic:RegisterEvent("update_exp_value", function (level, exp)
        local config = PROFICIENCY_CONFIG[user_logic.level]
        ui_helper:SetText(self.exp_value_txt, user_logic.exp.."/"..config.exp)
        ui_helper:SetText(self.level_txt, user_logic.level)
        self.exp_bar:setPercent(user_logic.exp / config.exp * 100)
    end)



    graphic:RegisterEvent("update_name_value", function (value)
        ui_helper:SetText(self.name_txt, value.."#"..user_logic.user_id)
    end)


    graphic:RegisterEvent("switch_world_status", function (is_visible)
        self:setVisible(is_visible)
    end)

    -- 切换主界面，子模块
    graphic:RegisterEvent("switch_system_module",function (func_name)
        if self.cur_system == func_name then
            return
        end

        if func_name == SYSTEM_STATE.home then
            self:setVisible(true)
        elseif func_name == SYSTEM_STATE.deck then
            self:setVisible(false)
        end

        self.cur_system = func_name
    end)

    --有邀请事件
    graphic:RegisterEvent("you_have_battle", function (infomation)
        local title = text_loader:GetText("invite_battle_prompt") --切磋提示框？
        local desc = text_loader :GetText("battle_with_friend")  --确定和好友切磋吗？
        local confirm_txt = text_loader:GetText("common_confirm")  --确定
        local cancel_txt =text_loader:GetText("common_cancel")    --取消
        graphic:DispatchEvent("show_confirm_box", title, desc, confirm_txt, cancel_txt, function ()
            graphic:DispatchEvent("pop_world_panel")
            --有弹窗啊啊啊创建
            --graphic:DispatchEvent("pop_world_panel")
            local id = infomation.id
            friend_logic:RetFriendAcceptInvite(id)
            end, function ()
            print("拒绝好友切磋")
            local id = infomation.id
            friend_logic:ReqFriendCancelInvite(id)
            graphic:DispatchEvent("pop_world_panel")
            end)
        end)
end


function meta:RegisterWidgetEvent()

    local anim_name = "interface/world/btn_template.csb"

    -- 显示加入卡组
    graphic:RegisterEvent("show_join_deck_panel",function (card_uid)
        -- self:PlayAnimation("enter_replace")
    end)

    -- 隐藏加入卡组
    graphic:RegisterEvent("hide_join_deck_panel",function ()
        self:PlayAnimation("exit_replace")
    end)

    --显示reward_panel界面
    graphic:RegisterEvent("show_reward_panel", function (reward_list, title, desc)
        graphic:DispatchEvent("push_world_panel", "common", "reward_panel", reward_list, title, desc)
    end)

end


return meta
