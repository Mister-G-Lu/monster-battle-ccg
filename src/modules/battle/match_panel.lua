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
    -- battle_scene calls this every frame.  This is a fallback for the case
    -- where the standby reply never arrives AT ALL: after 3s, drop the
    -- loading screen and clear the deploy lock so the battle cannot hang on
    -- "loading" forever.  In the healthy flow the timer is cancelled as soon
    -- as battle_panel_standby arrives (see RegisterEvent below), so it can
    -- never fire mid-handshake and restart the ready animation.  The primary
    -- safety net for a broken exit/ready-animation chain is battle_logic's
    -- own 4s standby timer, which force-completes the command.
    if not self._standby_advanced then
        self._standby_timer = (self._standby_timer or 0) + elapsed_time
        if self._standby_timer > 3.0 then
            self._standby_advanced = true
            print("[MATCH] WARNING: No standby response in 3s, auto-advancing battle")
            battle_logic.is_play_animation = false
            -- pop the stuck standby command (if any) and leave the match screen
            battle_logic:CommandComplete()
            self:PlayAnimation("exit_battle", false)
        end
    end
end

function meta:Show()
    self:setVisible(true)
    self._standby_timer = 0
    self._standby_advanced = false
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
        -- handshake healthy: stop the 3s fallback timer before it can fire
        -- mid-animation and replay the exit/ready sequence
        self._standby_advanced = true
        self:PlayAnimation("exit_battle", false)
    end)
end

return meta
