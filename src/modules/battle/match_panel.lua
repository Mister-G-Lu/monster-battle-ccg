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

local ENTER_ANIMATION_TIMEOUT = 1.5
local STANDBY_RESPONSE_TIMEOUT = 4.0
local EXIT_ANIMATION_TIMEOUT = 6.0

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

function meta:_RequestStandby(reason)
    if self._standby_requested then
        return
    end
    self._standby_requested = true
    print("[MATCH] Requesting battle standby" .. (reason and (" (" .. reason .. ")") or ""))
    battle_logic:ReqBattleStandby()
    self:PlayAnimation("loop_battle", true)
end

function meta:_CompleteStandby(reason)
    if self._standby_complete then
        return
    end
    self._standby_complete = true
    self._standby_advanced = true
    self:setVisible(false)
    battle_logic:DispatchEvent("anim_complete", reason or "battle_panel_standby")
end

function meta:_ExitMatchPanel(reason)
    if self._exit_requested then
        return
    end
    self._exit_requested = true
    self._exit_timer = 0
    print("[MATCH] Exiting match panel" .. (reason and (" (" .. reason .. ")") or ""))
    self:PlayAnimation("exit_battle", false, function ()
        self:_CompleteStandby("battle_panel_standby")
    end)
end

function meta:Show()
    self:setVisible(true)
    self._standby_timer = 0
    self._exit_timer = 0
    self._standby_requested = false
    self._exit_requested = false
    self._standby_advanced = false
    self._standby_complete = false
    self:PlayAnimation("enter_battle", false, function ()
        self:_RequestStandby("enter_animation_complete")
    end)
end

function meta:Update(elapsed_time)
    if self._standby_complete then
        return
    end

    self._standby_timer = (self._standby_timer or 0) + elapsed_time

    -- Some APK/resource builds do not fire the enter_battle completion callback.
    -- Without this fallback the first offline battle can sit on the opponent
    -- placeholder forever because req_battle_standby is never sent.
    if not self._standby_requested and self._standby_timer > ENTER_ANIMATION_TIMEOUT then
        print("[MATCH] WARNING: enter_battle callback missing; sending standby request")
        self:_RequestStandby("enter_timeout")
        return
    end

    if self._exit_requested then
        self._exit_timer = (self._exit_timer or 0) + elapsed_time
        if self._exit_timer > EXIT_ANIMATION_TIMEOUT then
            print("[MATCH] WARNING: exit_battle callback missing; completing standby")
            self:_CompleteStandby("battle_panel_standby_timeout")
        end
        return
    end

    -- If the in-process server response or command dispatch gets swallowed,
    -- leave the match screen rather than hanging forever.
    if self._standby_requested and self._standby_timer > STANDBY_RESPONSE_TIMEOUT then
        print("[MATCH] WARNING: No standby response; auto-advancing battle")
        battle_logic.is_play_animation = false
        self:_ExitMatchPanel("standby_response_timeout")
    end
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
                self:_CompleteStandby("battle_panel_standby")
            else
                battle_logic:DispatchEvent("anim_complete", "gold_coin_ready")
            end
        end
    end)
end

-- Set own player
function meta:SetOwnPlayer(actor)
    if not actor then
        return
    end
    ui_helper:SetTextByKey(self.match_ourside_name_txt, actor.user_name)
    -- ui_helper:SetTextByKey(self.match_ourside_power_txt, "battle_power_desc", actor.strength)
    -- self.match_ourside_power_txt:setVisible(false)
    ui_helper:SetTextByKey(self.match_ourside_level_txt, 1)
end

-- Set enemy player
function meta:SetEnemyPlayer(actor)
    if not actor then
        return
    end
    ui_helper:SetTextByKey(self.match_enemy_name_txt, actor.user_name)
    -- ui_helper:SetTextByKey(self.match_enemy_power_txt, "battle_power_desc", actor.strength)
    -- self.match_enemy_power_txt:setVisible(false)
    ui_helper:SetTextByKey(self.match_enemy_level_txt, 1)
end

function meta:RegisterEvent()
    -- battle init
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
        self:_ExitMatchPanel("server_standby")
    end)
end

return meta
