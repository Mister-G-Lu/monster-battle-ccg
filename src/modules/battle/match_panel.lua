local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local battle_logic = require "logic.battle"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"
local pve_logic = require "logic.pve"
local BATTLE_STATUS = constants.BATTLE_STATUS

local timer = require "manager.time"

local meta = class("match_panel",function ()
    return ui_helper:LoadCocosUI("interface/battle/battle_ui_match_panel.csb")
end)

function meta:ctor()

    local match_info = self:getChildByName("match_info")

    local ourside_info = match_info:getChildByName("ourside_info")
    self.match_ourside_name_txt = ourside_info:getChildByName("ourside_name")
    self.match_ourside_wait_txt = ourside_info:getChildByName("match_desc")

    -- self.match_ourside_power_txt = ourside_info:getChildByName("ourside_power")
    self.match_ourside_level_txt = ourside_info:getChildByName("level_value")

    ui_helper:SetTextByKey(self.match_ourside_wait_txt, "ourside_match_ready_desc")

    local enemy_info = match_info:getChildByName("enemy_info")
    self.match_enemy_name_txt = enemy_info:getChildByName("ourside_name")
    self.match_enemy_wait_txt = enemy_info:getChildByName("match_desc")
    -- self.match_enemy_power_txt = enemy_info:getChildByName("ourside_power")
    self.match_enemy_level_txt = enemy_info:getChildByName("level_value")

    ui_helper:SetTextByKey(self.match_enemy_wait_txt, "enemy_match_ready_desc")

    self:PlayAnimation("normal")
    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

function meta:Update(elapsed_time)
    -- NOTE: battle_scene calls this every frame, so the method must exist.
    -- The old "3s auto-advance" watchdog lived here and was removed on
    -- purpose: it force-cleared battle_logic.is_play_animation even when the
    -- standby handshake was healthy, which replayed battle_panel_standby
    -- mid-animation and made the ready animation run twice (or never).
    -- The real fix for the "stuck on loading" bug is server-side:
    -- offline_battle:HandleStandby must answer req_battle_standby with
    -- cmd_battle_standby (it now does).  battle_logic's own 5s
    -- is_play_animation safety remains as last-resort recovery for broken
    -- animations.
end

function meta:Show()
    self:setVisible(true)
    self:PlayAnimation("enter_battle", false, function ()
        battle_logic:ReqBattleStandby()
        self:PlayAnimation("loop_battle", true)
    end)
end

function meta:RegisterWidgetEvent()
    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "battlefield_enter" then
            battle_logic:DispatchEvent("battlefield_enter")
        elseif event_name == "handcard_enter" then
            battle_logic:DispatchEvent("handcard_enter")
        elseif event_name == "battlefield_exit" then
        --     self.battlefield_panel:PlayAnimation("exit")
        elseif event_name == "result_enter" then
        --     self.battle_ui_panel:RunResultAnimation()
        elseif event_name == "gold_coin_ready" then
            if battle_logic.start_type ~= "replay" or battle_logic.battle_status == BATTLE_STATUS.standby then
                battle_logic:DispatchEvent("gold_coin_ready")
            else
                battle_logic:DispatchEvent("anim_complete", "gold_coin_ready")
            end
        end
    end)
end


-- 设置主视角的角色
function meta:SetOwnPlayer(actor)
    if not actor then
        return
    end
    ui_helper:SetTextByKey(self.match_ourside_name_txt, actor.user_name)
    -- ui_helper:SetTextByKey(self.match_ourside_power_txt, "battle_power_desc", actor.strength)
    -- self.match_ourside_power_txt:setVisible(false)
    ui_helper:SetTextByKey(self.match_ourside_level_txt, 1)
end

-- 设置对手的角色
function meta:SetEnemyPlayer(actor)
    if not actor then
        return
    end
    ui_helper:SetTextByKey(self.match_enemy_name_txt, actor.user_name)
    ui_helper:SetTextByKey(self.match_enemy_name_txt, actor.user_name)
    -- ui_helper:SetTextByKey(self.match_enemy_power_txt, "battle_power_desc", actor.strength)
    -- self.match_enemy_power_txt:setVisible(false)
    ui_helper:SetTextByKey(self.match_enemy_level_txt, 1)
end

function meta:RegisterEvent()
    -- 战斗初始化
    battle_logic:RegisterEvent("init_player_info",function (own_player, enemy_player)
        self:SetOwnPlayer(own_player)
        -- print("init_player_info", battle_logic.battle_object_type, pve_logic.play_id, tostring(data_template.pve_play_config))
        if battle_logic.battle_type == "daily" then
            local pve_play_id = tonumber(pve_logic.play_id .. pve_logic.difficulty)
            local cur_pve_play_config = data_template.pve_play_config[pve_play_id]

            enemy_player.user_name = cur_pve_play_config.play_name
        elseif battle_logic.battle_type == "guide" then
            local text_loader = require "manager.text_loader"
            enemy_player.user_name = text_loader:GetText(enemy_player.user_name)
        end
        self:SetEnemyPlayer(enemy_player)
    end)

    battle_logic:RegisterEvent("battle_panel_standby", function (recv_msg)
        self:PlayAnimation("exit_battle", false)
    end)
end

return meta
