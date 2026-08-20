local ui_helper = require "manager.ui_helper"
local audio_manager = require "manager.audio_manager"
local global = require "manager.global"
local arena_logic = require "logic.arena"
local analytics = require "manager.analytics"
local ARENA_MATCH_TIMEOUT = 20
local ARENA_STAGE = arena_logic.STAGE
local meta = ui_helper:NewPanel("casual_match_panel", "interface/world/match_panel.csb")

function meta:OnInit()
    self:Init()
    self:setVisible(false)
end

function meta:Init()
    self.match_btn = self:getChildByName("fight_btn")
    self.match_txt = self.match_btn:getChildByName("desc")
    ui_helper:SetTextByKey(self.match_txt, "arena_stage_wait_desc")
    local msgbox_node = self:getChildByName("msgbox")
    local animation_node = msgbox_node:getChildByName("animation")
    local size = animation_node:getContentSize()
    -- Spine动画
    local skeleton_node = sp.SkeletonAnimation:create("animation/match_waiting.json", "animation/match_waiting.atlas", 1)
    skeleton_node:setAnimation(0, "animation", true)
    skeleton_node:setPosition({x = size.width / 2, y = size.height / 2 - 20})
    animation_node:addChild(skeleton_node)
    self.skeleton_node = skeleton_node
    self.msgbox_node = msgbox_node
    self:DispatchGraphicEvent("switch_arena_stage", ARENA_STAGE.wait)
    self.is_match_success = false
    self.match_time = 0
    arena_logic.cur_stage = ARENA_STAGE.wait
    self:registerScriptHandler(function(event)
        if event == "enter" then
            self:PlayAnimation("normal")
        elseif event == "exit" then
        end
    end)
end

function meta:Update(elapsed_time)
    if arena_logic.cur_stage == ARENA_STAGE.match then
        self.match_time = self.match_time + elapsed_time
        if self.match_time >= ARENA_MATCH_TIMEOUT then
            analytics:DoCasualMatchOver(false, "timeout")
            -- 取消匹配
            arena_logic:DoCancelCasual()
            self:DispatchGraphicEvent("switch_arena_stage", ARENA_STAGE.wait)
        end
    end
end

function meta:DoJoinMatch()
    self:setVisible(true)
    arena_logic:DoJoinCasual()
    self.is_match_success = false
    self:PlayAnimation("enter_match", false, function ()
        if not self.is_match_success then
            self:PlayAnimation("loop_match", true)
        end
    end)
end

function meta:RegisterEvent()
    -- 进入后台界面
    self:RegisterGraphic("pause_back_ground", function ()
        -- 如果处于匹配状态，并且还没有匹配成功，就取消匹配
        if arena_logic.cur_stage == ARENA_STAGE.match and not self.is_match_success then
            arena_logic:DoCancelCasual()
        end
    end)
    -- 匹配成功
    self:RegisterGraphic("battle_match_success",function (callback)
        self.is_match_success = true
        global:PreviouslyBattleScene()
        local match_success_animation = "animation_2_over"
        if math.random(100) <= 10 then
            match_success_animation = "animation_2_over_rare"
        end
        self.skeleton_node:setAnimation(0, match_success_animation, false)
        self:PlayAnimation("exit_match_success", false, function ()
            self:DispatchGraphicEvent("switch_arena_stage", ARENA_STAGE.wait)
            callback()
            self:PlayAnimation("normal")
            self.skeleton_node:setToSetupPose()
        end)
    end)
    self:RegisterGraphic("battle_periphery_success",function (callback)
        self.is_match_success = true
        local match_success_animation = "animation_2_over"
        if math.random(100) <= 10 then
            match_success_animation = "animation_2_over_rare"
        end
        self.skeleton_node:setAnimation(0, match_success_animation, false)
        self:PlayAnimation("exit_match_success", false, function ()
            self:DispatchGraphicEvent("switch_arena_stage", ARENA_STAGE.wait)
            callback()
            self:PlayAnimation("normal")
            self.skeleton_node:setToSetupPose()
        end)
    end)
    -- 设置竞技场状态
    self:RegisterGraphic("switch_arena_stage",function (stage)
        if stage == ARENA_STAGE.wait then
            self:setVisible(false)
            self.skeleton_node:setAnimation(0, "animation", true)
            ui_helper:SetTextByKey(self.match_txt, "arena_stage_wait_desc")

            if arena_logic.cur_stage == ARENA_STAGE.match then
                self:PlayAnimation("exit_match_cancel", false, function ()
                    self:PlayAnimation("normal")
                end)
            end
        elseif stage == ARENA_STAGE.match then
            self.match_time = 0
            ui_helper:SetTextByKey(self.match_txt, "arena_stage_match_desc")
        end
        arena_logic.cur_stage = stage
    end)
     --确认 取消按钮
     ui_helper:AddClick(self.match_btn,function ()
        if arena_logic.cur_stage == ARENA_STAGE.wait then
        elseif arena_logic.cur_stage == ARENA_STAGE.match then
            -- self.matching_interface_panel:setVisible(false)
            self:setVisible(false)
            arena_logic:DoCancelCasual()
        end
    end)
    --播放声音
    self.skeleton_node:registerSpineEventHandler(function (event)
        if arena_logic.cur_stage == ARENA_STAGE.wait then
            return
        end
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        end
    end, sp.EventType.ANIMATION_EVENT)
end

return meta
