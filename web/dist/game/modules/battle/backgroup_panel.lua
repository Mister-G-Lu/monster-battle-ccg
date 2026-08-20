local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local battle_logic = require "logic.battle"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"

local timer = require "manager.time"

local meta = class("backgroup_panel",function ()
    return ui_helper:LoadCocosUI("interface/battle/battlefield_panel.csb")
end)

function meta:ctor()

    local battlemap_empty_node = self:getChildByName("battlemap_empty")
    local battlemap_node = battlemap_empty_node:getChildByName("battlemap")

    self.spine_node = battlemap_empty_node:getChildByName("spine_node")

    local time_node = battlemap_node:getChildByName("time_node")
    self.round_time_txt = time_node:getChildByName("round_time")

    self:PlayAnimation("normal", false, function ()
        self:SetBackgroupAnimation()
    end)

    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

function meta:SetBackgroupAnimation()
    self.spine_node:removeAllChildren()
    local json_data = "animation/battlefield_map_forest.json"
    local atlas_data = "animation/battlefield_map_forest.atlas"
    local skeleton_node = sp.SkeletonAnimation:create(json_data, atlas_data, 1)
    skeleton_node:setAnimation(0, "battlefield_map_normal", true)
    self.spine_node:addChild(skeleton_node)
end

function meta:Update(elapsed_time)
    if battle_logic.cur_stage == battle_logic.STAGE.own then
        local last_oper_time = battle_logic.own_player.last_oper_time
        if last_oper_time then
            local last_time = timer:GetDiffSecond(last_oper_time)
            if last_time == 10 then
                self:PlayAnimation("loop_ten_sec",true)
            end
            ui_helper:SetText(self.round_time_txt, last_time.."s")
            self.round_time_txt:setVisible(true)
            if last_time <= 0 then
                self.round_time_txt:setVisible(false)
            end
        end
    elseif battle_logic.cur_stage == battle_logic.STAGE.wait then
        ui_helper:SetText(self.round_time_txt, "fight")
        self:PlayAnimation("loop_normal")
        self.round_time_txt:setVisible(true)
    elseif battle_logic.cur_stage == battle_logic.STAGE.enemy then
        local last_oper_time = battle_logic.enemy_player.last_oper_time

        if last_oper_time then
            if last_time == 10 then
                self:PlayAnimation("loop_ten_sec",true)
            end
            local last_time = timer:GetDiffSecond(last_oper_time)
            ui_helper:SetText(self.round_time_txt, last_time.."s")
            self.round_time_txt:setVisible(true)
            if last_time <= 0 then
                self.round_time_txt:setVisible(false)
            end
        end
    end
end


function meta:RegisterWidgetEvent()
end

function meta:RegisterEvent()
    -- 进入战场
    battle_logic:RegisterEvent("battlefield_enter", function ()
        self:setVisible(true)
        self:PlayAnimation("enter")
    end)

    battle_logic:RegisterEvent("show_battle_result", function ()
        self:PlayAnimation("exit")
    end)

end

return meta
