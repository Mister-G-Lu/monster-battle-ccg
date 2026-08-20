local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local audio_manager = require "manager.audio_manager"
local timer = require "manager.time"
local global = require "manager.global"
local analytics = require "manager.analytics"
local arena_logic = require "logic.arena"
local deck_logic = require "logic.deck"
local defines = require "manager.defines"
local constants = require "common.constants"
local ARENA_STAGE = arena_logic.STAGE
local meta = class("arena_panel",function ()
    return cc.Layer:create()
end)
function meta:ctor()
    --匹配界面
    self.casula_match_panel = require("modules.pvp.casual_match_panel").new()
    self.btn_desc = self.casula_match_panel:getChildByName("fight_btn"):getChildByName("desc")
    ui_helper:SetTextByKey(self.btn_desc,"pvp_confirm_btn_value")
    --天梯界面
    self.periphery_match_panel = require("modules.pvp.periphery_match_panel").new()
    self:addChild(self.periphery_match_panel)
    self:addChild(self.casula_match_panel)
    self.periphery_match_panel:setVisible(false)
    self:RegisterEvent()
end

function meta:Show()
    --查看玩家处于哪个阶段 显示不同界面
    self:setVisible(true)
    if arena_logic.arena_stage == constants.ARENA_STAGE.periphery then
        self.periphery_match_panel:setVisible(true)
        self.casula_match_panel:setVisible(false)
        self.periphery_match_panel:Show()
        graphic:DispatchEvent("switch_world_status",false)
    elseif arena_logic.arena_stage == constants.ARENA_STAGE.casual then
        self.casula_match_panel:DoJoinMatch()
        ui_helper:SetTextByKey(self.btn_desc,"arena_stage_match_desc")
    end
end

function meta:Hide()
     self:setVisible(false)
     graphic:DispatchEvent("switch_world_status",true)
end
--更新
function meta:Update(elapsed_time)
    self.casula_match_panel:Update(elapsed_time)
    self.periphery_match_panel:Update(elapsed_time)
end

-- 注册渲染事件
function meta:RegisterEvent()
    --开始战斗
    graphic:RegisterEvent("do_join_match", function ()
        self.casula_match_panel:DoJoinMatch()
    end)
    --显示战斗界面
    graphic:RegisterEvent("show_arena_panel",function ()
        self:Show()
    end)
    --刷新天梯界面
    graphic:RegisterEvent("refresh_staircase_panel",function ()
        self.periphery_match_panel:ShowEloBar()
    end)
    --隐藏寻找比赛界面
    graphic:RegisterEvent("hide_match_panel",function()
        self.casula_match_panel:setVisible(false)
    end)
end

return meta
