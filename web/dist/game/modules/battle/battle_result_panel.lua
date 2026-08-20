local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local constants = require "common.constants"
local audio_manager = require "manager.audio_manager"
local resource_logic = require "logic.resource"
local battle_logic = require "logic.battle"
local user_logic = require "logic.user"
local data_template = require "manager.data_template"
local defines = require "manager.defines"
local arena_logic = require"logic.arena"
local spine_manager = require "manager.spine"
local ITEM_CONFIG = data_template.item_config

local meta = ui_helper:NewPanel("pve_panel", "interface/battle/battle_end2/battle_ui_end_panel.csb")

function meta:OnEnter()
    battle_logic:RegisterEvent("show_battle_result", function (result, reward_info)
        self:Init(result, reward_info)
    end)
end

function meta:Init(result,reward_info)

    self:setVisible(true)
    self.node = nil
    self.back_btn = nil
    self.action_node = nil
    self.reward_count = 0
    self.item_height = 60    --资源奖励位置
    self.max_item_count = 0
    self.node_height = 720 - 50 --奖励 总节点 位置
    self.reward_list = {}
    self.have_mvp = false
    self.is_pvp = false
    self.light_skeleton = nil
    self.result_over = false
    self.pvp_elo_over = false
    self.node = self:getChildByName("end_node")
    self.touch_layer = self:getChildByName("shadow")
    self.is_over = false
    self.detail_panel = self.node:getChildByName("detail_panel")
    self.end_animation = self.node:getChildByName("end_animation_node")
    local skeleton = sp.SkeletonAnimation:create("animation/battlefield_effects.json", "animation/battlefield_effects.atlas", 1)
    local skeleton_lingdang = sp.SkeletonAnimation:create("animation/lingdang.json", "animation/lingdang.atlas", 1)
    skeleton:setToSetupPose()
    skeleton:setPosition({x = 0, y = 0})
    self.result_animation_node = skeleton
    self.end_animation:addChild(skeleton,99)
    self:RegisterSpineEvent()
    --铃铛
    self.skeleton_lingdang = skeleton_lingdang
    skeleton_lingdang:setToSetupPose()
    skeleton_lingdang:setPosition({x = 0, y = 0})

    local pos = self.detail_panel:getChildByName("pos")
    local bling_node = pos:getChildByName("bling_node")
    bling_node:addChild(skeleton_lingdang,1)

    local end_desc = self.node:getChildByName("end_desc")
    ui_helper:BindTimeLine(end_desc,"interface/battle/battle_end2/end_desc.csb")
    self.end_desc = end_desc

    local title = self.end_desc:getChildByName("end_desc")
    local desc = self.end_desc:getChildByName("end_desc2")
    self.title = title
    self.desc  = desc
    self:Show()
    local BATTLE_RESULT = constants.BATTLE_RESULT
    local animation = ""
    self.result_info = nil
    if result == BATTLE_RESULT.win then
        ui_helper:SetTextByKey(title,"battle_result_win")
        ui_helper:SetTextByKey(desc,"battle_result_win_desc")
        self.desc:setColor(ui_helper:GetColor3B(0xa95917))
        self.light_skeleton = sp.SkeletonAnimation:create("animation/win_light.json", "animation/win_light.atlas", 1)
        self.light_skeleton:setAnimation(0,"win_light",true)
        animation = "victory"
        self.result_animation_node:setAnimation(0,"victory",false)
        self.result_info = BATTLE_RESULT.win
    else
        ui_helper:SetTextByKey(title,"battle_result_lose")
        ui_helper:SetTextByKey(self.desc,"battle_result_lost_desc")
        self.desc:setColor(ui_helper:GetColor3B(0x244870))
        self.light_skeleton = sp.SkeletonAnimation:create("animation/lose_light.json", "animation/lose_light.atlas", 1)
        self.light_skeleton:setAnimation(0,"lose_light",true)
        animation = "lose"
        self.result_animation_node:setAnimation(0,"lose",false)
        self.result_info = BATTLE_RESULT.lost
    end
    self.node:getChildByName("light_node"):addChild(self.light_skeleton)

    --测试数据***********************************

    self.mvp_info = {}
    -- self.mvp_info.model_id = 110012
    -- self.mvp_info.mvp_value_1 = 100
    -- self.mvp_info.mvp_value_2 = 99
    self.mvp_info = reward_info.mvp_card_info

    if next(self.mvp_info) ~= nil then
        self.have_mvp = true
    end

    self.cur_dexterity = user_logic.exp
    self.last_dexterity = user_logic.last_exp
    self.last_bar_percent = self.last_dexterity

    self.cur_elo =arena_logic:GetEloValue()
    self.last_elo = arena_logic:GetLastEloValue()

    self.last_bar_percent = self.last_elo

    -- local rr = {}
    -- rr.type = "resource"
    -- rr.attr_id = 500001
    -- rr.value = 20
    -- table.insert(self.reward_list, rr)
    -- rr.type = "resource"
    -- rr.attr_id = 500001
    -- rr.value = 20
    -- table.insert(self.reward_list, rr)
    -- rr.type = "resource"
    -- rr.attr_id = 500001
    -- rr.value = 20
    -- table.insert(self.reward_list, rr)
    self.reward_list = reward_info.reward_info

    if self.cur_elo ~= self.last_elo and arena_logic.arena_stage ~= constants.ARENA_STAGE.casual then
        self.is_pvp = true
    end
    --self.is_pvp = true
    --*****************************************
    self:PlayAnimation("enter",false,function()
        self.result_over = true
    end)
    self:RegisterWidgeEvent()
end

--熟练度
function meta:ShowExpBar()

    self.exp_bar_node = require("modules.battle.battle_dexterity_template").new()
    self.exp_bar_node:Init(self.cur_dexterity,self.last_dexterity,self)
    self:addChild(self.exp_bar_node)
end

--MVP
function meta:ShowMvp(mvp_info)
    self.mvp_node = require("modules.battle.battle_result_mvp_panel").new()
    -- local mvp_info = nil
    self.mvp_node:Init(mvp_info)
    self.create_card_id = self.mvp_node.mvp_card_id
    self:addChild(self.mvp_node)
end

--奖励
function meta:ShowReward(reward_list)
    if reward_list and #reward_list > 0 then
        self.reward_node = require("modules.battle.battle_result_reward_panel").new()
        self.reward_node:Init(self.have_mvp,reward_list)
        self:addChild(self.reward_node)
    end
end
--天梯分数
function meta:ShowElo()
    self.elo_bar_panel = require("modules.battle.battle_result_elo_template").new()
    self.elo_bar_panel:Init(self.cur_elo,self.last_elo)
    self:addChild(self.elo_bar_panel)
end
function meta:Update(elapsed_time)
    if self.exp_bar_node then
        self.exp_bar_node:Update(elapsed_time)
    end
    if self.elo_bar_panel then
        self.elo_bar_panel:Update(elapsed_time)
    end
    if self.end_desc_tracker then
        self.end_desc_tracker:Update()
    end
end

function meta:Show()
    self:setVisible(true)
end

function meta:Hide()
    self:setVisible(false)
end

function meta:OnExit()
    self:UnregisterEvent()
end

function meta:RegisterEvent()
    self:RegisterGraphic("exp_over",function()
        if self.have_mvp then
            local block = cc.CallFunc:create(function()
                self:ShowMvp(self.mvp_info)
            end)
            local delay = cc.DelayTime:create(defines["RESULT_DAILY"].mvp)
            local sequence = cc.Sequence:create(delay, block)
            self:runAction(sequence)

        else
            local block = cc.CallFunc:create(function()
                self:ShowReward(self.reward_list)
            end)
            local delay = cc.DelayTime:create(defines["RESULT_DAILY"].reward)
            local sequence = cc.Sequence:create(delay, block)
            self:runAction(sequence)
        end
    end)
    self:RegisterGraphic("mvp_over",function()
        local block = cc.CallFunc:create(function()
            self:ShowReward(self.reward_list)
        end)
        local delay = cc.DelayTime:create(defines["RESULT_DAILY"].reward)
        local sequence = cc.Sequence:create(delay, block)
        self:runAction(sequence)

    end)

    self:RegisterGraphic("elo_over",function()
        self.pvp_elo_over = true
    end)

    self:RegisterGraphic("reward_action_over",function()
        self.reward_action_over =true
    end)

    --合成
    self:RegisterGraphic("card_synthesis", function ()
        self.mvp_node:setVisible(false)
        battle_logic:ExitBattle()
        self:DispatchGraphicEvent("switch_system_module", "deck")
        self:DispatchGraphicEvent("jump_create_card",self.create_card_id)
    end)
    self:RegisterGraphic("card_upgrade", function ()
        self.mvp_node:setVisible(false)
        battle_logic:ExitBattle()
        self:DispatchGraphicEvent("switch_system_module", "deck")
        self:DispatchGraphicEvent("jump_upgrade_card",self.create_card_id)
    end)

    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "bling" then
             if self.result_info == constants.BATTLE_RESULT.win then
                self.skeleton_lingdang:setAnimation(0,"win",false)
            else
                self.skeleton_lingdang:setAnimation(0,"lose",false)
            end
        end
    end)
end

function meta:RegisterSpineEvent()
        self.result_animation_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "font_in" then
            self.end_desc:PlayAnimation("enter")
        end
    end, sp.EventType.ANIMATION_EVENT)

end

function meta:RegisterWidgeEvent()
    --是否是PVP
    ui_helper:AddClick(self.touch_layer,function()

        if self.reward_action_over then
            self.reward_action_over = false
                if self.elo_bar_panel then
                    self.elo_bar_panel:setVisible(false)
                end
                if self.mvp_node then
                    self.mvp_node:setVisible(false)
                end
                if self.reward_node then
                    self.reward_node:setVisible(false)
                end
                if self.exp_bar_node then
                    self.exp_bar_node:setVisible(false)
                end
            self:PlayAnimation("exit",false,function()
                battle_logic:ExitBattle()
            end)
        end

        if self.pvp_elo_over then
            self.pvp_elo_over = false

            self.elo_bar_panel:PlayAnimation("exit",false,function()

                self:PlayAnimation("end", false, function()
                    local block = cc.CallFunc:create(function()
                        self:ShowExpBar()
                    end)
                    local delay = cc.DelayTime:create(defines["RESULT_DAILY"].exp)
                    local sequence = cc.Sequence:create(delay, block)
                    self:runAction(sequence)
                end)
            end)
        end

        if not self.result_over then
                return
            end
        self.result_over = false
        if self.is_pvp == true then
            local block = cc.CallFunc:create(function()
                self:ShowElo()
            end)
                local delay = cc.DelayTime:create(defines["RESULT_DAILY"].elo)
                local sequence = cc.Sequence:create(delay, block)
                self:runAction(sequence)
        else
            self:PlayAnimation("end", false, function()
                    local block = cc.CallFunc:create(function()
                        self:ShowExpBar()
                    end)
                    local delay = cc.DelayTime:create(defines["RESULT_DAILY"].exp)
                    local sequence = cc.Sequence:create(delay, block)
                    self:runAction(sequence)
                end)
        end
    end)

end

return meta
