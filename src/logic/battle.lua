local network = require "manager.network"
local graphic = require "manager.graphic"
local timer = require "manager.time"
local global = require "manager.global"
local constants = require "common.constants"

local event_listener = require "utils.event_listener"
local bit = require "utils.bit_extension"
local analytics = require "manager.analytics"

local user_logic = require "logic.user"
local arena_logic = require "logic.arena"
local challenge_logic = require "logic.challenge"
local pve_logic = require "logic.pve"

local guide_logic
local meta = {}

local CARD_TYPE = constants.CARD_TYPE
local CARD_KIND = constants.CARD_KIND
local BATTLE_SLOT_MAX = constants.BATTLE_SLOT_MAX
local BATTLE_RESULT = constants.BATTLE_RESULT
local EVENT_TYPE = constants.BATTLE_EVENT_TYPE
local POWER_NAME = constants.POWER_NAME

-- Offline watchdog budgets (seconds).  Every animation in the battle scene is
-- allowed to take its time; these only fire when a callback never arrives,
-- which on a device with a missing animation resource means "never".
-- First stuck sub-event gets a generous budget; once we know this device does
-- not report animation completion, stop paying the full price per event.
local SUB_EVENT_FIRST_TIMEOUT = 2.0
local SUB_EVENT_RETRY_TIMEOUT = 0.12
-- Hard ceiling on being locked out of the player's own turn.
local OFF_TURN_TIMEOUT = 15.0

-- Battle stage
meta.STAGE = {
    init  = 1,        -- 1.battle init
    own   = 2,        -- 2.own turn
    wait  = 3,        -- 3.waiting for input
    enemy = 4,        -- 4.enemy turn
    over  = 5,        -- 5.battle over
}

function meta:Init()
    self:Clean()
    self:RegisterNetworkEvent()
end

function meta:Clean()
    self.battle_command_queue = {}
    self.own_player = nil
    self.enemy_player = nil
    self.command_handler = event_listener.New("multi")
    self:RegisterCmdHandler()
    self.cur_stage = self.STAGE.init
    self.battle_result = nil
    self.sub_event_complete = true
    -- whether a deploy animation is playing
    self.is_play_animation = false
    -- crystal-sync animation callback
    self.sync_crystal_callback = nil
    -- standby: 0 not ready, 1 client ready, 2 server replied
    self.standby_status = 0
    -- first-player animation toggle
    self.is_first_animation = true
    -- delay between commands
    self.command_interval = 0
    -- delay between events
    self.event_interval = 0
    -- whether the battle is over
    self.is_battle_over = false
    self.is_own = false
    self.pve_win_cur_value = 0
    -- campaign commander HP (defaults; updated by cmd_battle_hero)
    self.own_hero_hp = 0
    self.own_hero_max_hp = 0
    self.enemy_hero_hp = 0
    self.enemy_hero_max_hp = 0
    self._standby_block_time = 0
    self._auto_standby_wait = 0
    self._enemy_think_time = 0
    -- sub-event / off-turn watchdog state (see Update)
    self._sub_event_block_time = 0
    self._sub_event_rescues = 0
    self._off_turn_time = 0
    self._off_turn_progress = nil
end

function meta:PushBattleQueue(name, data)
    local command = {}
    command.name = name
    command.data = data
    table.insert(self.battle_command_queue, command)
end

function meta:PopBattleQueue()
    if #self.battle_command_queue == 0 then
        return nil
    end
    return self.battle_command_queue[1]
end

-- Complete command
function meta:CommandComplete()
    if #self.battle_command_queue == 0 then
        return false
    end
    local command = self.battle_command_queue[1]
    if command.name == "cmd_battle_over" and self.battle_result == nil then
        -- surrender: only clear after fully executed
        return
    end
    table.remove(self.battle_command_queue, 1)
    self.command_interval = 0.5
end

-- Logic update
function meta:Update(elapsed_time)
    local now_time = timer:Now()
    self.elapsed_time = elapsed_time

    -- Offline single-player: never auto-end the player's turn on a timer.
    -- The original PvP countdown HUD is a debug leftover; only honor it
    -- when DEV_MODE is on.
    if _G["DEV_MODE"] and self.cur_stage == self.STAGE.own and self.own_player and not self.own_player.is_sacrifice then
        local last_oper_time = self.own_player.last_oper_time
        if last_oper_time then
            local last_time = timer:GetDiffSecond(last_oper_time)
            if last_time <= 0 then
                self:ReqBattleAttack("auto")
            end
        end
    end

    -- If the match-panel enter animation never fires, request standby ourselves.
    if self.standby_status == 0 and self.own_player then
        self._auto_standby_wait = (self._auto_standby_wait or 0) + elapsed_time
        if self._auto_standby_wait > 0.8 then
            print("[BATTLE] auto-requesting standby (match panel silent)")
            self:ReqBattleStandby()
        end
    end

    -- Sub-event watchdog.  cmd_battle_attack clears sub_event_complete and
    -- only the animation callback sets it again.  On a device whose battle
    -- animations never report completion that callback never arrives, the
    -- head of battle_command_queue is re-dispatched every frame and returns
    -- immediately, and the battle freezes mid-combat.  The player cannot
    -- break out either: cur_stage is wait/enemy, so ReqBattleAttack() is a
    -- no-op.  Bound the wait and let the queue move on.
    if not self.sub_event_complete then
        self._sub_event_block_time = (self._sub_event_block_time or 0) + elapsed_time
        local sub_limit = (self._sub_event_rescues or 0) > 0
            and SUB_EVENT_RETRY_TIMEOUT or SUB_EVENT_FIRST_TIMEOUT
        if self._sub_event_block_time > sub_limit then
            self._sub_event_rescues = (self._sub_event_rescues or 0) + 1
            print("[BATTLE] WARNING: sub-event animation never completed after "
                .. string.format("%.2f", sub_limit) .. "s, forcing the queue on (rescue #"
                .. self._sub_event_rescues .. ")")
            self._sub_event_block_time = 0
            self.sub_event_complete = true
        end
    else
        self._sub_event_block_time = 0
    end

    -- Enemy think bubble: if the queue is frozen on a missing animation
    -- during their turn (or during the combat phase that follows it), drop
    -- the deploy lock so AI commands can run.
    --
    -- Exception: while the standby handshake is in flight, clearing the lock
    -- here would only make cmd_battle_standby re-dispatch and reset its own
    -- timer, starving the standby watchdog below.  Let that one finish it.
    local head_command = self.battle_command_queue[1]
    local standby_in_flight = (self._standby_block_time or 0) > 0
        or (head_command and head_command.name == "cmd_battle_standby")
    if (self.cur_stage == self.STAGE.enemy or self.cur_stage == self.STAGE.wait)
        and self.is_play_animation and not standby_in_flight then
        self._enemy_think_time = (self._enemy_think_time or 0) + elapsed_time
        if self._enemy_think_time > 3.0 then
            print("[BATTLE] enemy think stall; clearing animation lock")
            self.is_play_animation = false
            self._anim_block_time = 0
            self._enemy_think_time = 0
        end
    else
        self._enemy_think_time = 0
    end

    -- Last-resort guard: never stay locked out of the player's turn.  The
    -- watchdogs above keep the queue draining, but if the server's own-prep
    -- command is somehow lost the battle scene would sit on the enemy's turn
    -- with no way back.  Hand control to the player instead.
    --
    -- Measured against playback *progress*, not wall clock: a long boss fight
    -- legitimately keeps the player off-turn for many seconds while commands
    -- replay, so only a queue that is not moving at all counts as stuck.
    if self.cur_stage == self.STAGE.enemy or self.cur_stage == self.STAGE.wait then
        local pending = self.battle_command_queue[1]
        local pending_events = pending and pending.data and pending.data.event_list
        local progress = string.format("%d|%s|%d",
            #self.battle_command_queue,
            tostring(pending and pending.name),
            pending_events and #pending_events or 0)
        if progress == self._off_turn_progress then
            self._off_turn_time = (self._off_turn_time or 0) + elapsed_time
        else
            self._off_turn_progress = progress
            self._off_turn_time = 0
        end
        if self._off_turn_time > OFF_TURN_TIMEOUT then
            self._off_turn_time = 0
            print("[BATTLE] WARNING: battle queue made no progress for "
                .. OFF_TURN_TIMEOUT .. "s, clearing battle locks")
            self.is_play_animation = false
            self._anim_block_time = 0
            self._standby_block_time = 0
            self.sub_event_complete = true
            if #self.battle_command_queue == 0 then
                -- nothing left to play back: give the turn back
                self:SetBattleStage(self.STAGE.own)
            end
        end
    else
        self._off_turn_time = 0
        self._off_turn_progress = nil
    end

    if self.is_play_animation then
        -- safety: if animation has been blocking for 5+ seconds, force-unblock
        self._anim_block_time = (self._anim_block_time or 0) + elapsed_time
        if self._anim_block_time > 5.0 then
            print("[BATTLE] WARNING: is_play_animation stuck for " .. self._anim_block_time .. "s, force-clearing")
            self.is_play_animation = false
            self._anim_block_time = 0
            self._standby_block_time = 0
            self:CommandComplete()
        end
        -- standby-specific: if cmd_battle_standby set is_play_animation
        -- but the exit_battle/anim_complete chain broke, force after 4s
        if self._standby_block_time and self._standby_block_time > 0 then
            self._standby_block_time = self._standby_block_time + elapsed_time
            if self._standby_block_time > 4.0 then
                print("[BATTLE] WARNING: standby chain broken, force-advancing")
                self.is_play_animation = false
                self._anim_block_time = 0
                self._standby_block_time = 0
                self:CommandComplete()
            end
        end
        return
    else
        self._anim_block_time = 0
    end

    local command = self:PopBattleQueue()
    if not command or self.command_interval > 0 then
        self.command_interval = self.command_interval - elapsed_time
        return
    end
    self.command_handler:Dispatch(command.name, command.data)
end

-- Whether the card can be played
function meta:IsOperation(card)
    if not card then
        return false
    end

    local battle_card_list = self.own_player.battle_slot
    -- 1.check crystal cost
    if self.own_player.cur_crystal < card.cost then
        return false
    end

    if card.type == CARD_TYPE.monster then
        -- monster card: is there a free slot
        if not battle_card_list[BATTLE_SLOT_MAX] then
            return true
        end
    elseif card.type == CARD_TYPE.consume then
        -- consume card: first power decides enemy vs ally target
        if not card.power_list or #card.power_list == 0 then
            return false
        end
        local power = card.power_list[1]
        if not power then
            return false
        end

        for _,v in pairs(self.enemy_player.battle_slot) do
            if v and v.monster then
                return true
            end
        end

        for _,v in pairs(self.own_player.battle_slot) do
            if v and v.monster then
                return true
            end
        end
    else
        -- equip card
        local first_slot = battle_card_list[1]

        if bit:GetBitNum(card.kind, CARD_KIND.all) == 1 and first_slot and first_slot.monster then
            return true
        else
            for _,m in pairs(battle_card_list) do
                if m and m.monster then
                    if bit:CheckBitValue(m.monster.kind, card.kind) then
                        return true
                    end
                end
            end
        end

    end
    return false
end

-- Play a hand card
function meta:DoHandCard(select_pos, is_enemy, target_pos)
    local own_player = self.own_player
    local select_card = own_player:GetHandCard(select_pos)
    if not select_card then
        return false
    end

    -- 1. not enough crystal
    if own_player.cur_crystal < select_card.cost then
        graphic:DispatchEvent("show_message", "battle_crystal_not_enough")
        return false
    end

    if select_card.type == constants.CARD_TYPE.monster then
        -- 2. monster: check slot
        local allow_pos = own_player:GetCurMonsterSlotPos()
        -- print("allow_pos = "..allow_pos..",target_pos = "..target_pos)
        if allow_pos == 0 or target_pos > allow_pos  or is_enemy then
            -- graphic:DispatchEvent("show_message", "battle_crystal_not_enough")
            return false
        end
        return true
    elseif select_card.type == constants.CARD_TYPE.consume then
        -- 3. consume: check there is a monster
        local is_target_enemy = false
        local power_count = 0
        local is_crystal_power = false

        local target_actor_is_enemy = is_enemy
        local can_use = false
        local power_list = select_card.power_list or {}
        for k, power in pairs(power_list) do
            power_count = power_count + 1
            if power.name == "crystal" then
                is_crystal_power = true
            end

            print("use consume", power.name, power.target_type, target_actor_is_enemy)
            if power.target_type == "enemy" and target_actor_is_enemy then
                can_use = true
                break
            elseif power.target_type == "own" and not target_actor_is_enemy then
                can_use = true
                break
            elseif power.target_type == "all" then
                can_use = true
                break
            end
        end

        if is_crystal_power and power_count == 1 then
            graphic:DispatchEvent("show_message", "extra_crystal_use_desc")
            return false
        end

        -- validate target
        if not can_use then
            graphic:DispatchEvent("show_message", "battle_consume_deploy_target_fail")
            return false
        end

        local cur_player = self:GetPlayerByOwn(not is_enemy)
        local target_slot = cur_player:GetBattleCard(target_pos)

        if target_slot then
            local immunity_power = target_slot:GetPower(POWER_NAME.immunity)
            if immunity_power then
                graphic:DispatchEvent("show_message", "battle_immunity_consume_card")
                return false
            end
            return true
        else
            return false
        end

        return false
    else
        -- 4. equip: check there is a monster
        if is_enemy then
            return false
        end
        local target_slot = own_player:GetBattleCard(target_pos)
        if not target_slot then
            graphic:DispatchEvent("show_message", "equip_target_card_is_null")
            return false
        end

        if bit:GetBitNum(select_card.kind, CARD_KIND.all) == 1 then
            return true
        else

            if bit:CheckBitValue(target_slot.monster.kind, select_card.kind) then
                return true
            else
                graphic:DispatchEvent("show_message", "battle_monster_kind_not_match")
                return false
            end
        end
    end
end

-- Check insufficient cost
function meta:CheckCardCost(idx)
    local hand_card = self.own_player.hand_card[idx]
    if not hand_card then
        return false
    end

    if self.own_player.cur_crystal < hand_card.cost then
        return false
    end

    return true
end

-- Get playable hand indices
function meta:GetOperationCardIdx()
    local hand_card_list = self.own_player.hand_card
    local idxs = {}
    for i = 1, 4 do
        idxs[i] = self:IsOperation(hand_card_list[i])
    end
    return idxs
end

-- Get legal placement slots
function meta:GetPlaceSlotPos(hand_slot_pos)
    local cur_card = self.own_player.hand_card[hand_slot_pos]
    if not cur_card then
        return
    end

    if not self:IsOperation(cur_card) then
        return
    end
    local own_tips = {}
    local enemy_tips = {}

    local own_slot_list = self.own_player.battle_slot
    local enemy_slot_list = self.enemy_player.battle_slot

    if cur_card.type == CARD_TYPE.monster then
        -- monster card
        for i = 1, BATTLE_SLOT_MAX  do
            own_tips[i] = true
            if own_slot_list[i] == nil then
                return own_tips, enemy_tips
            end
        end
    elseif cur_card.type == CARD_TYPE.consume then
        -- consume card

        -- consume card: first power decides enemy vs ally target
        if not cur_card.power_list or #cur_card.power_list == 0 then
            return
        end
        local power = cur_card.power_list[1]
        if not power then
            return
        end
        local target_player = nil

        if power.target_type == "enemy" then
            -- if targeting the enemy
            local slot_list = self.enemy_player.battle_slot
            for i = 1, BATTLE_SLOT_MAX do
                if slot_list[i] and slot_list[i].monster then
                    enemy_tips[i] = true
                end
            end
        elseif power.target_type == "own" then
            -- if targeting allies
            local slot_list = self.own_player.battle_slot
            for i = 1, BATTLE_SLOT_MAX do
                if slot_list[i] and slot_list[i].monster then
                    own_tips[i] = true
                end
            end
        elseif power.target_type == "all" then
            local slot_list = self.enemy_player.battle_slot
            for i = 1, BATTLE_SLOT_MAX do
                if slot_list[i] and slot_list[i].monster then
                    enemy_tips[i] = true
                end
            end

            local slot_list = self.own_player.battle_slot
            for i = 1, BATTLE_SLOT_MAX do
                if slot_list[i] and slot_list[i].monster then
                    own_tips[i] = true
                end
            end
        end


    else
        -- equip card
        for idx, m in pairs(own_slot_list) do
            if m and m.monster then
                if bit:GetBitNum(cur_card.kind, CARD_KIND.all) == 1 then
                    own_tips[idx] = true
                elseif bit:CheckBitValue(m.monster.kind, cur_card.kind) then
                    own_tips[idx] = true
                else
                    -- print(">>>><<<<<<<>>>>>>><<<<<<<<"..idx)
                end
            end
        end
    end

    return own_tips, enemy_tips
end

-- Leave battle
function meta:ExitBattle()
    local return_to_campaign = self.battle_type == "campaign"
    global:PopScene()

    -- A campaign battle starts from the Adventure world-system panel. Make
    -- that destination explicit when the result screen closes; relying on a
    -- hidden child of the home .csb was what could leave players staring at
    -- the empty legacy Adventure panel after a battle.
    if return_to_campaign then
        graphic:DispatchEvent("switch_system_module", "campaign")
    end

    if self.battle_type == "challenge" then
        challenge_logic:BattleWait()
    end

    if self.battle_type == "guide" then
        if self.battle_result == BATTLE_RESULT.win then
            guide_logic:ReqGuideComplete()
        else
            guide_logic:DoGuide()
        end
    end

end

function meta:SendBattle(msg_name, msg_data, callback)
    if self.is_battle_over then
        return
    end
    msg_data = msg_data or {}
    local req_data = {}
    req_data[msg_name] = msg_data

    local nofiy_handler = function (result, recv_msg)
        if result == "battle_is_null" then
            self:DispatchEvent("show_battle_null")
            print("msg_name = "..msg_name, "msg_data = "..tostring(msg_data))
            return
        end
        recv_msg = recv_msg or {}
        if callback then
            local ret_data = {}
            for k,v in pairs(recv_msg) do
                ret_data = v
            end
            callback(result, ret_data)
        end
    end
    local req_key = msg_name
    if callback then
        network:Send("req_battle", req_data, nofiy_handler, req_key)
    else
        network:Send("req_battle", req_data, nil, req_key)
    end
end

-- Replay / reconnect battle
function meta:ReqReplay()
    -- reconnect battle
    print("reconnect battle")
    self:SendBattle("req_battle_replay", {}, function (result, recv_msg)
    end)
end

-- Surrender
function meta:ReqBattleSurrender()
    if self.is_battle_over then
        -- if already over, exit battle immediately
        self:ExitBattle()
    else
        self:SendBattle("req_battle_surrender", {}, function (result, recv_msg)
            self:CommandComplete()
            self:DispatchEvent("pop_battle_panel","battle_setting_panel")
        end)
    end
end

-- Set battle stage
function meta:SetBattleStage(stage)
    if self.cur_stage == stage then
        return
    end
    self.cur_stage = stage

    if stage == self.STAGE.own then
        self.is_own = true
    elseif stage == self.STAGE.enemy then
        self.is_own = false
    end

    self:DispatchEvent("update_battle_stage", self.cur_stage)
end

-- Battle attack / end turn
function meta:ReqBattleAttack(req_type)
    if self.cur_stage ~= self.STAGE.own then
        return
    end
    local old_stage = self.cur_stage
    self:SetBattleStage(self.STAGE.wait)

    local req_data = {}
    req_data.req_type = req_type
    req_data.client_attack_time = timer:Now()
    req_data.server_attack_time = self.own_player.last_oper_time
    -- print(req_data.client_attack_time, req_data.server_attack_time)
    self:SendBattle("req_battle_attack", req_data, function (result, recv_msg)
        if result ~= "success" and result ~= "battle_did_not_operate_fail" then
            self:SetBattleStage(old_stage)
        end
    end)
end

-- Play card / move
function meta:ReqBattleMove(src_pos, is_enemy, desc_slot_pos, callback)
    -- deploy animation playing
    self.is_play_animation = true
    local oper_player = self.own_player
    local hand_card = oper_player:GetHandCard(src_pos)
    local is_deploy = false -- deployed locally; roll back if the server rejects
    local is_req_deploy = false -- request failed; do not finish deploy
    local req_data = {src_pos = src_pos, is_enemy = is_enemy, target_pos = desc_slot_pos}
    self:SendBattle("req_battle_move", req_data, function (result, recv_msg)
        if result ~= "success" then
            is_req_deploy = true
            self.is_play_animation = false
            if hand_card.type == CARD_TYPE.monster then
                if is_deploy then
                    -- 1. clear slot data
                    oper_player.battle_slot[desc_slot_pos] = nil
                    -- 2. undo battlefield deploy
                    self:DispatchEvent("deploy_monster_card",true, desc_slot_pos, nil)
                    self:DoUnDeployBattleSlot(oper_player.user_id, desc_slot_pos)
                end
            elseif hand_card.type == CARD_TYPE.equip or hand_card.type == CARD_TYPE.armor then

            elseif hand_card.type == CARD_TYPE.consume then
            end
        end
        callback(result, recv_msg)
    end)

    if hand_card.type == CARD_TYPE.monster then
        local function hand_card_callback()
            is_deploy = true
            if is_req_deploy then
                -- restore hand card
                self:DispatchEvent("update_hand_card", true, src_pos, hand_card)
                return
            end
            self:DoDeployBattleSlot(oper_player.user_id, desc_slot_pos)
            -- * deploy monster immediately
            local slot = require("common.entity.slot").New()
            slot:Init(oper_player.user_id, desc_slot_pos)
            slot:SetMonster(hand_card)
            oper_player.battle_slot[desc_slot_pos] = slot
            self:DispatchEvent("deploy_monster_card",true, desc_slot_pos, hand_card)
        end
        -- play drop animation
        self:DispatchEvent("drop_hand_monster_card", src_pos, desc_slot_pos, hand_card_callback)
    elseif hand_card.type == CARD_TYPE.consume then
        self:DispatchEvent("consume_hand_card", src_pos, desc_slot_pos, function ()
            is_deploy = true
            self.is_play_animation = false
            if is_req_deploy then
                -- restore hand card
                self:DispatchEvent("update_hand_card", true, src_pos, hand_card)
                return
            end
        end)
    elseif hand_card.type == CARD_TYPE.equip or hand_card.type == CARD_TYPE.armor then
        self:DispatchEvent("item_hand_card", src_pos, desc_slot_pos, function ()
            is_deploy = true
            self.is_play_animation = false
            if is_req_deploy then
                -- restore hand card
                self:DispatchEvent("update_hand_card", true, src_pos, hand_card)
                return
            end
        end)
    else
        self.is_play_animation = false
    end
end

-- Battle standby request
function meta:ReqBattleStandby()
    if self.standby_status ~= 0 then
        return
    end
    self.standby_status = 1
    self:SendBattle("req_battle_standby", {}, function ()
        self.standby_status = 2
    end)
end

-- Sacrifice a card
function meta:ReqSacrificeCard(is_hand, pos, callback)
    if self.cur_stage ~= self.STAGE.own then
        return false
    end
    if not self.own_player.is_sacrifice then
        graphic:DispatchEvent("show_message","sacrifice_error")
        return false
    end

    self:DispatchEvent("update_sacrifice_stage", false)
    self.own_player.is_sacrifice = false

    self:SendBattle("req_battle_immolation",{is_hand = is_hand, pos = pos},function (result, recv_msg)
        local is_success = true
        if result ~= "success" then
            self.own_player.is_sacrifice = true
            self:DispatchEvent("update_sacrifice_stage", true)
            is_success = false
        end
        callback(is_success)
        self:DispatchEvent("update_operate_card")
    end)
    return true
end

function meta:ParseBattleEvent(event_name, ...)
    if self.battle_type == "guide" then
        local guide_logic = require "logic.guide"
        guide_logic:ParseBattleEvent(event_name, ...)
    end
end

-- Register battle command
function meta:RegisterEvent(command_name, callback)
    self.command_handler:Register(command_name, callback)
end

-- Dispatch command
function meta:DispatchEvent(event_name, ...)
    self.command_handler:Dispatch(event_name, ...)
end

-- Get player by user id
function meta:GetPlayer(user_id)
    if self.own_player.user_id == user_id then
        return self.own_player
    else
        return self.enemy_player
    end
end

-- Get player by is_own
function meta:GetPlayerByOwn(is_own)
    if is_own then
        return self.own_player
    else
        return self.enemy_player
    end
end

-- Get enemy player
function meta:GetEnemy(is_own)
    if is_own then
        return self.enemy_player
    else
        return self.own_player
    end
end

-- Can sacrifice
function meta:IsSacrifice()
    return self.own_player.is_sacrifice
end

-- Shift slots on deploy
function meta:DoDeployBattleSlot(deploy_user_id, deploy_pos)
    local is_own = deploy_user_id == self.own_player.user_id
    local oper_player = self:GetPlayer(deploy_user_id)
    -- * Deploy monster card
    local slot = oper_player.battle_slot[deploy_pos]
    if slot then
        -- * Occupied slot: shift existing monsters right
        for i = BATTLE_SLOT_MAX - 1 , deploy_pos, -1 do
            if oper_player.battle_slot[i] then
                oper_player.battle_slot[i].pos = i + 1
                oper_player.battle_slot[i + 1] = oper_player.battle_slot[i]
                print("deploy shift src = "..i..", dest = "..(i+1))
                self:DispatchEvent("move_battle_card",is_own, i, i + 1)
            end
        end
    end
end

-- Undo slot deploy
function meta:DoUnDeployBattleSlot(deploy_user_id, deploy_pos)
    local is_own = deploy_user_id == self.own_player.user_id
    local oper_player = self:GetPlayer(deploy_user_id)
    oper_player.battle_slot[deploy_pos] = nil
    for i = deploy_pos, 2 do
        local tar_slot = oper_player.battle_slot[i]
        local src_slot = oper_player.battle_slot[i + 1]
        oper_player.battle_slot[i] = src_slot
        if src_slot then
            src_slot.pos = i
        end
        print("undeploy shift src = "..(i+1)..", dest = "..i)
        self:DispatchEvent("move_battle_card",is_own, i, i + 1)
    end
end

-- Register command handlers
function meta:RegisterCmdHandler()

    -- Play power animation
    local DoAnimEvent = function (tar_user_id, tar_pos, tar_pos_list, power_name, src_user_id, src_pos, value)
        local callback = function ()

        end
        self:DispatchEvent("do_power_animation", tar_user_id, tar_pos, tar_pos_list, power_name, src_user_id, src_pos, value, callback)
    end

    -- Play damage animation
    local DoDamageEvent = function (tar_user_id, tar_pos, value)
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            print("target actor not found = "..tar_user_id)
            self.sub_event_complete = true
            return
        end
        local tar_slot = target_actor:GetBattleCard(tar_pos)
        if not tar_slot then
            print("battle slot not found = "..tar_pos)
            self.sub_event_complete = true
            return
        end
        local is_own = tar_user_id == self.user_id

        tar_slot.cur_hp = tar_slot.cur_hp - value

        self:DispatchEvent("do_hurt_effect", value, is_own, tar_pos)
        self:DispatchEvent("update_slot_hp", is_own, tar_pos, -value)
        self:DispatchEvent("do_hit_animation", is_own, tar_pos, function ()
            self.sub_event_complete = true
        end)
    end

    -- Play death event
    local DoDeadEvent = function (tar_user_id, tar_pos)
        local is_own = tar_user_id == self.user_id
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            print("target actor not found = "..tar_user_id)
            self.sub_event_complete = true
            return
        end

        -- after-death callback
        local function callback()
            target_actor.battle_slot[tar_pos] = nil
            self:DispatchEvent("update_monster_num",is_own, target_actor:GetAllMonsterLenght())
            self.sub_event_complete = true

            if self.battle_object_type == "pve" and not is_own then
                self.pve_win_cur_value = self.pve_win_cur_value + 1
                self:DispatchEvent("update_pve_win_cur_value")
            end

            self.sync_crystal_callback = function ()
                local actor = self:GetPlayerByOwn(is_own)
                local diff_crystal = 1
                actor.cur_crystal = actor.cur_crystal + diff_crystal
                self:DispatchEvent("update_crystal_num", is_own, actor.cur_crystal, diff_crystal)
                self:DispatchEvent("update_operate_card")
            end
            self:DispatchEvent("show_crystal_animation")
        end
        self:DispatchEvent("do_dead_animation", is_own, tar_pos, callback)
    end

    -- Play status event
    local DoStatusEvent = function (tar_user_id, tar_pos, name, round, value)
        local is_own = tar_user_id == self.user_id
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            print("target actor not found = "..tar_user_id)
            self.sub_event_complete = true
            return
        end

        local tar_slot = target_actor:GetBattleCard(tar_pos)
        if not tar_slot then
            print("battle slot not found = "..tar_pos)
            self.sub_event_complete = true
            return
        end

        if round == 0 then
            -- remove status
            value = tar_slot:DelStatus(name)
        else
            -- add status
            value = tar_slot:PushStatus(name, round, value)
        end

        self:DispatchEvent("do_status_animation", is_own, tar_pos, name, round, value, function ()
            self.sub_event_complete = true
        end)
    end

    -- Heal event
    local DoHealEvent = function (tar_user_id, tar_pos, value)
        local is_own = tar_user_id == self.user_id
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            print("target actor not found = "..tar_user_id)
            self.sub_event_complete = true
            return
        end

        local tar_slot = target_actor:GetBattleCard(tar_pos)
        if not tar_slot then
            print("battle slot not found = "..tar_pos)
            self.sub_event_complete = true
            return
        end
        self.sub_event_complete = true
        tar_slot.cur_hp = tar_slot.cur_hp + value
        self:DispatchEvent("update_slot_hp", is_own, tar_pos, value)
    end

    -- Armor event
    local DoArmorEvent = function (tar_user_id, tar_pos, value)
        local is_own = tar_user_id == self.user_id
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            print("target actor not found = "..tar_user_id)
            self.sub_event_complete = true
            return
        end

        local tar_slot = target_actor:GetBattleCard(tar_pos)
        if not tar_slot then
            print("battle slot not found = "..tar_pos)
            self.sub_event_complete = true
            return
        end

        tar_slot.cur_ad = tar_slot.cur_ad + value
        if value < 0 then
            self:DispatchEvent("do_hurt_effect", math.abs(value), is_own, tar_pos)
        end
        self:DispatchEvent("do_hit_animation", is_own, tar_pos, function ()
            self:DispatchEvent("update_slot_define", is_own, tar_pos, value)

            if tar_slot.cur_ad <= 0 then
                tar_slot:CleanItem()
                self:DispatchEvent("deploy_item_card",is_own, tar_pos, nil)
            end

            self.sub_event_complete = true
        end)
    end

    -- Destroy event
    local DoDestroyEvent = function ( tar_user_id, tar_pos )
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            print("target actor not found = "..tar_user_id)
            self.sub_event_complete = true
            return
        end
        local tar_slot = target_actor:GetBattleCard(tar_pos)
        if not tar_slot then
            print("battle slot not found = "..tar_pos)
            self.sub_event_complete = true
            return
        end
        local is_own = tar_user_id == self.user_id
        tar_slot:CleanItem()
        print("destroy event", tostring(is_own), tostring(tar_pos))

        self:DispatchEvent("destroy_slot_item", is_own, tar_pos)
        self.sub_event_complete = true
    end

    local DoUnsummonEvent = function(tar_user_id, tar_pos, new_card, random_pos)
        local is_own = tar_user_id == self.user_id
        local target_actor = self:GetPlayer(tar_user_id)
        if not target_actor then
            self.sub_event_complete = true
            return
        end
        local tar_slot = target_actor:GetBattleCard(tar_pos)
        if not tar_slot then
            self.sub_event_complete = true
            return
        end
        tar_slot:CleanItem()

        target_actor.battle_slot[tar_pos] = nil

        if new_card then
            target_actor:SetHandCard(new_card.hand_pos, new_card)
            self:DispatchEvent("update_hand_card", is_own, new_card.hand_pos, new_card, true)
        else
            target_actor.monster_len = target_actor.monster_len + 1
        end

        self.sub_event_complete = true
    end

    -- sub-event complete
    self:RegisterEvent("sub_event_complete", function ()
        self.sub_event_complete = true
    end)

    self:RegisterEvent("cmd_battle_init",function (recv_msg)
        self.own_player = require("common.entity.actor").New()
        self.enemy_player = require("common.entity.actor").New()

        local player1 = recv_msg.player1
        local player2 = recv_msg.player2
        local first_actor = recv_msg.first_actor
        self.is_first = first_actor == self.user_id

        if player1.user_id == self.user_id then
            table.merge(self.own_player, player1)
            table.merge(self.enemy_player, player2)
        else
            table.merge(self.enemy_player, player1)
            table.merge(self.own_player, player2)
        end

        -- init player info
        self:DispatchEvent("init_player_info", self.own_player, self.enemy_player)

        -- command complete
        self:CommandComplete()
    end)

    self:RegisterEvent("cmd_battle_standby", function (recv_msg)
        self.is_play_animation = true
        self:DispatchEvent("battle_panel_standby")
        -- Start standby safety timer: if anim_complete never fires
        -- within 4 seconds, the Update loop will force-complete
        self._standby_block_time = 0.001
    end)

    self:RegisterEvent("cmd_battle_prepa",function (recv_msg)
        self:ParseBattleEvent("cmd_battle_prepa", recv_msg)
        -- whose turn
        local user_id = recv_msg.user_id
        -- sync crystal
        local sync_crystal = recv_msg.sync_crystal
        -- last operate time
        local last_oper_time = recv_msg.last_oper_time
        local is_sacrifice = recv_msg.is_sacrifice
        local is_own = self.own_player.user_id == user_id

        local diff_crystal = 0
        local new_stage = nil
        if is_own then
            diff_crystal = sync_crystal - self.own_player.cur_crystal
            self.own_player.cur_crystal = sync_crystal
            self.own_player.last_oper_time = last_oper_time
            self.own_player.is_sacrifice = is_sacrifice
            new_stage = self.STAGE.own
            self:DispatchEvent("update_sacrifice_stage", is_sacrifice)
        else
            diff_crystal = sync_crystal - self.own_player.cur_crystal
            self.enemy_player.cur_crystal = sync_crystal
            self.enemy_player.last_oper_time = last_oper_time
            new_stage = self.STAGE.enemy
            self:DispatchEvent("update_sacrifice_stage", false)
        end



        self:DispatchEvent("update_crystal_num", is_own, sync_crystal, diff_crystal)
        self:SetBattleStage(new_stage)

        self:CommandComplete()
    end)

    self:RegisterEvent("cmd_battle_round",function (recv_msg)
        self.round = recv_msg.round
        -- init player info
        self:DispatchEvent("update_battle_round", self.round)
        -- command complete
        self:CommandComplete()
    end)

    -- Campaign commander-HP sync (The Shadow Road). The offline server pushes
    -- the current commander totals; forward them to the battle UI and keep
    -- the flow moving. Any UI can subscribe to "update_hero_hp".
    self:RegisterEvent("cmd_battle_hero", function (recv_msg)
        local is_own = self.own_player and (recv_msg.own_user_id == self.own_player.user_id)
        if is_own then
            self.own_hero_hp = recv_msg.own_hp
            self.own_hero_max_hp = recv_msg.own_max_hp
            self.enemy_hero_hp = recv_msg.enemy_hp
            self.enemy_hero_max_hp = recv_msg.enemy_max_hp
        else
            self.own_hero_hp = recv_msg.enemy_hp
            self.own_hero_max_hp = recv_msg.enemy_max_hp
            self.enemy_hero_hp = recv_msg.own_hp
            self.enemy_hero_max_hp = recv_msg.own_max_hp
        end
        self:DispatchEvent("update_hero_hp", self.own_hero_hp, self.own_hero_max_hp, self.enemy_hero_hp, self.enemy_hero_max_hp)
        self:CommandComplete()
    end)

    self:RegisterEvent("cmd_battle_move",function (recv_msg)
        self:ParseBattleEvent("cmd_battle_move", recv_msg)
        local src_user_id = recv_msg.src_user_id
        local src_hand_pos = recv_msg.src_hand_pos

        local desc_user_id = recv_msg.desc_user_id
        local desc_slot_pos = recv_msg.desc_slot_pos

        local sync_crystal = recv_msg.sync_crystal
        local new_card = recv_msg.new_card

        -- Whether this is the local player
        local is_own = self.own_player.user_id == src_user_id

        local oper_player = self:GetPlayer(src_user_id)
        -- 1. Sync crystal count
        local diff_crystal = sync_crystal - oper_player.cur_crystal
        oper_player.cur_crystal = sync_crystal
        self:DispatchEvent("update_crystal_num",is_own, sync_crystal, diff_crystal)
        self:DispatchEvent("update_operate_card")

        local card = oper_player:GetHandCard(src_hand_pos)
        if not card then
            self:CommandComplete()
            print("card is null src_hand_pos = "..src_hand_pos)
            return
        end

        -- 2.apply card effect
        if card.type == CARD_TYPE.monster then
            if not is_own then
                self:DoDeployBattleSlot(src_user_id ,desc_slot_pos)
                -- * deploy monster immediately
                local slot = require("common.entity.slot").New()
                slot:Init(src_user_id, desc_slot_pos)
                slot:SetMonster(card)
                oper_player.battle_slot[desc_slot_pos] = slot
                self:DispatchEvent("deploy_monster_card",is_own, desc_slot_pos, card)
            end
        elseif card.type == CARD_TYPE.equip or card.type == CARD_TYPE.armor then
            local slot = oper_player.battle_slot[desc_slot_pos]
            -- * check monster exists
            if not slot or not slot.monster then
                self:CommandComplete()
                print("slot or monster is full")
                return
            end
            slot:SetItem(card)
            self:DispatchEvent("deploy_item_card",is_own, desc_slot_pos, card)
        elseif card.type == CARD_TYPE.consume then

        end

        -- 3.set replacement hand card
        oper_player:SetHandCard(src_hand_pos, new_card)
        -- show in own hand
        self:DispatchEvent("update_hand_card", is_own, src_hand_pos, new_card, true)

        if new_card then
            -- 4.update card counts
            if card.type == CARD_TYPE.monster then
                oper_player.monster_len = oper_player.monster_len - 1
            else
                oper_player.item_len = oper_player.item_len - 1
            end
        end


        self:DispatchEvent("update_monster_num",is_own, oper_player:GetAllMonsterLenght())
        self:DispatchEvent("update_item_num",is_own, oper_player:GetAllItemLenght())

        -- 5.mark command complete
        self:CommandComplete()
    end)

    self:RegisterEvent("cmd_battle_attack",function (recv_msg)
        local event_list = recv_msg.event_list or {}
        if not self.sub_event_complete then
            return
        end
        if self.cur_stage ~= self.STAGE.wait and recv_msg.is_fight_stage then
            self:SetBattleStage(self.STAGE.wait)
        end



        if #event_list == 0 and self.sub_event_complete then
            self:ParseBattleEvent("cmd_battle_attack", event_list)
            self:CommandComplete()
            if self.cur_stage == self.STAGE.wait then
                self:ReqFightOver()
            end
            return
        end

        local cur_event = event_list[1]
        table.remove(event_list, 1)
        self.sub_event_complete = false

        self:ParseBattleEvent("cmd_battle_attack", cur_event)

        if cur_event.type == EVENT_TYPE.anim then
            -- skill animation
            DoAnimEvent(cur_event.tar_user_id, cur_event.tar_pos, cur_event.tar_pos_list, cur_event.power_name, cur_event.src_user_id, cur_event.src_pos, cur_event.value)
        elseif cur_event.type == EVENT_TYPE.damage then
            -- damage
            DoDamageEvent(cur_event.tar_user_id, cur_event.tar_pos, cur_event.value)
        elseif cur_event.type == EVENT_TYPE.dead then
            -- death
            DoDeadEvent(cur_event.tar_user_id, cur_event.tar_pos)
        elseif cur_event.type == EVENT_TYPE.status then
            DoStatusEvent(cur_event.tar_user_id, cur_event.tar_pos, cur_event.power_name, cur_event.round, cur_event.value)
        elseif cur_event.type == EVENT_TYPE.armor_block then
            -- armor block animation
            local tar_user_id = cur_event.tar_user_id
            local tar_pos = cur_event.tar_pos
            self:DispatchEvent("do_armor_block", tar_user_id, tar_pos)
        elseif cur_event.type == EVENT_TYPE.heal then
            -- heal
            DoHealEvent(cur_event.tar_user_id, cur_event.tar_pos, cur_event.value)
        elseif cur_event.type == EVENT_TYPE.armor then
            -- armor value
            DoArmorEvent(cur_event.tar_user_id, cur_event.tar_pos, cur_event.value)
        elseif cur_event.type == EVENT_TYPE.crystal then
            -- crystal event
            local target_actor = self:GetPlayer(cur_event.tar_user_id)
            if not target_actor then
                print("target actor not found = "..cur_event.tar_user_id)
                return
            end
            target_actor.cur_crystal = target_actor.cur_crystal + cur_event.value
            local is_own = cur_event.tar_user_id == self.user_id
            self:DispatchEvent("update_crystal_num", is_own, target_actor.cur_crystal, cur_event.value)
            self:DispatchEvent("update_operate_card")
            self.sub_event_complete = true
        elseif cur_event.type == EVENT_TYPE.swap then
            -- swap event
            local target_actor = self:GetPlayer(cur_event.tar_user_id)
            if not target_actor then
                print("target actor not found = "..cur_event.tar_user_id)
                return
            end
            local is_own = cur_event.tar_user_id == self.user_id
            local src_pos = cur_event.src_pos
            local tar_pos = cur_event.tar_pos
            target_actor:SwapSlotPos(src_pos, tar_pos)
            self:DispatchEvent("move_battle_card", is_own, src_pos, tar_pos, function ()
                self.sub_event_complete = true
            end)
        elseif cur_event.type == EVENT_TYPE.destroy then
            DoDestroyEvent(cur_event.tar_user_id, cur_event.tar_pos)
        elseif cur_event.type == EVENT_TYPE.unsummon then
            DoUnsummonEvent(cur_event.tar_user_id, cur_event.tar_pos, cur_event.new_card, cur_event.random_pos)
        end
    end)

    -- battle sacrifice
    self:RegisterEvent("cmd_battle_discard", function (recv_msg)
        local src_user_id = recv_msg.src_user_id
        local is_own = self.own_player.user_id == src_user_id
        local cur_actor = self:GetPlayer(src_user_id)
        local sync_crystal = recv_msg.sync_crystal
        local is_sacrifice = recv_msg.is_sacrifice
        local discard_info_list = recv_msg.discard_info_list


        if #discard_info_list == 4 then
            cur_actor.monster_len = 8
            cur_actor.item_len = 8
        end

        if sync_crystal then
            -- sync crystal callback
            local diff_crystal = sync_crystal - cur_actor.cur_crystal
            cur_actor.cur_crystal = sync_crystal
            self.command_handler:Dispatch("update_crystal_num", is_own, sync_crystal, diff_crystal)
            self:DispatchEvent("update_operate_card")
        end

        for k, discard_info in pairs(discard_info_list) do
            local pos = discard_info.pos
            local is_hand = discard_info.is_hand
            local new_card = discard_info.new_card

            if is_hand then
                if new_card then
                    if new_card.type == CARD_TYPE.monster then
                        cur_actor.monster_len = cur_actor.monster_len - 1
                    else
                        cur_actor.item_len = cur_actor.item_len - 1
                    end
                    self:DispatchEvent("update_monster_num",is_own, cur_actor:GetAllMonsterLenght())
                    self:DispatchEvent("update_item_num",is_own, cur_actor:GetAllItemLenght())
                end

                -- discard from hand
                local function callback()
                    cur_actor.hand_card[pos] = new_card
                    self:DispatchEvent("update_hand_card", is_own, pos, cur_actor.hand_card[pos], true)
                end
                if pos > 0 then
                    cur_actor.hand_card[pos] = nil
                    self:DispatchEvent("discard_hand_card", is_own, pos, is_sacrifice, callback)
                else
                    self:DispatchEvent("discard_deck_card", is_own, new_card)
                end
            else
                -- discard from board
                cur_actor.battle_slot[pos] = nil
                local function callback()
                    cur_actor:CheckSlotDead(function (src, dest)
                        -- print("sacrifice shift src = "..src..", dest = "..dest)
                        self:DispatchEvent("move_battle_card", is_own, src, dest)
                    end)
                end

                self:DispatchEvent("sacrifice_slot", is_own, pos, is_sacrifice, callback)
            end
        end

        self:CommandComplete()
    end)

    -- battle over command
    self:RegisterEvent("cmd_battle_over", function (recv_msg)
        -- battle result arrives immediately
        local result = nil
        local win_user_id = recv_msg.win_user_id

        self:ParseBattleEvent("cmd_battle_over", recv_msg)

        if self.own_player.user_id == win_user_id then
            result = BATTLE_RESULT.win
        elseif self.enemy_player.user_id == win_user_id then
            result = BATTLE_RESULT.loss
        else
            result = BATTLE_RESULT.draw
        end
        analytics:DoBattleOver(self.battle_type, result == BATTLE_RESULT.win)
        local reward_info = recv_msg.reward_info
        self.battle_result = result
        
        -- arena updates
        if recv_msg.arena_info then
            arena_logic:SetLastEloValue(arena_logic:GetEloValue())
            arena_logic:SetLastLevel(arena_logic:GetLevel())
            arena_logic:SetEloValue(recv_msg.arena_info.elo_value)
            arena_logic:SetLevel(recv_msg.arena_info.level)
            arena_logic:SetStage(recv_msg.arena_info.stage)
            graphic:DispatchEvent("check_pve_is_turned",recv_msg.arena_info.stage,recv_msg.arena_info.level)
            graphic:DispatchEvent("refresh_staircase_panel")
        end
        -- PvE gerbil updates
        if recv_msg.pve_info then
            dump("recv_msg11", recv_msg.pve_info)
            local pve_info = recv_msg.pve_info
            pve_logic.cur_difficulty = pve_info.difficulty
            pve_logic.login_pve_data[1]["difficulty"] = pve_info.difficulty
        end
        graphic:DispatchEvent("pve_gerbil_over")
        graphic:DispatchEvent("pve_gerbil_panel_fresh")

        -- adventure mode updates
        if recv_msg.adventure_info then
            local adventure_info = recv_msg.adventure_info
            if adventure_info["pass_id"] then
                table.insert(pve_logic.adv_passid, adventure_info["pass_id"])
            end
            if adventure_info["progress"] then
                pve_logic.adv_progress = adventure_info["progress"]
            end
        end
        graphic:DispatchEvent("pve_exam_update", result, recv_msg.adventure_info)

        -- campaign battle over: tell the campaign map to refresh its nodes
        -- (and surface any first-clear recruit draft)
        if self.battle_type == "campaign" then
            graphic:DispatchEvent("refresh_campaign", recv_msg.campaign_info)
        end

        self:DispatchEvent("show_battle_result", result, recv_msg)
        
        graphic:DispatchEvent("hide_match_panel")
        arena_logic.arena_stage = recv_msg.arena_stage or arena_logic.arena_stage

        self:CommandComplete()
    end)

    -- operation focus
    self:RegisterEvent("cmd_battle_focus", function (recv_msg)
        -- print("cmd_battle_focus = ", tostring(recv_msg))
    end)

    -- battlefield sync
    self:RegisterEvent("cmd_battle_sync", function (recv_msg)
        local cur_oper_user_id = recv_msg.cur_oper_user_id
        local last_oper_time = recv_msg.last_oper_time
        self.own_player.is_sacrifice = recv_msg.is_sacrifice
        self:DispatchEvent("update_sacrifice_stage", self.own_player.is_sacrifice)

        local is_own = self.own_player.user_id == cur_oper_user_id
        local new_stage = nil
        if is_own then
            self:SetBattleStage(self.STAGE.own)
            self.own_player.last_oper_time = last_oper_time
        else
            self:SetBattleStage(self.STAGE.enemy)
            self.enemy_player.last_oper_time = last_oper_time
        end

        local sync_actor_list = recv_msg.sync_actor_list or {}
        for _, info in pairs(sync_actor_list) do
            local actor = self:GetPlayer(info.user_id)
            local is_own = self.own_player.user_id == info.user_id
            actor.cur_crystal = info.crystal
            actor.monster_len = info.monster_size
            actor.item_len = info.item_size
            self:DispatchEvent("update_monster_num", is_own, actor:GetAllMonsterLenght())
            self:DispatchEvent("update_crystal_num", is_own, actor.cur_crystal)


            local is_hand_empty = {true, true, true, true}
            for _, hand_info in pairs(info.hand_card_list) do
                actor:SetHandCard(hand_info.hand_pos, hand_info)
                self:DispatchEvent("update_hand_card", is_own, hand_info.hand_pos, hand_info)
                is_hand_empty[hand_info.hand_pos] = false
            end

            for k,v in pairs(is_hand_empty) do
                if v then
                    self:DispatchEvent("update_hand_card", is_own, k, nil)
                end
            end

            local is_slot_empty = {true, true, true}
            local battle_slot_list = info.battle_slot_list or {}
            for _, slot_info in pairs(battle_slot_list) do
                local tar_pos = slot_info.pos
                is_slot_empty[tar_pos] = false
                local battle_slot = actor:GetBattleCard(tar_pos)
                if not battle_slot then
                    battle_slot = require("common.entity.slot").New()
                    battle_slot:Init(actor.user_id, tar_pos)
                end
                actor.battle_slot[tar_pos] = battle_slot

-- Reset card data
                battle_slot.pos = tar_pos
                battle_slot:SetMonster(slot_info.monster)
                battle_slot:SetItem(slot_info.item)
                battle_slot.cur_hp = slot_info.cur_hp
                battle_slot.cur_ad = slot_info.cur_ad
-- Refresh UI
                self:DispatchEvent("deploy_monster_card",is_own, tar_pos, slot_info.monster)
                self:DispatchEvent("deploy_item_card",is_own, tar_pos, slot_info.item)
                local diff_hp = slot_info.cur_hp - battle_slot.init_hp
                if diff_hp ~= 0 then
                    self:DispatchEvent("set_slot_hp", is_own, tar_pos, slot_info.cur_hp)
                end
                local diff_ad = slot_info.cur_ad - battle_slot.init_ad
                if diff_ad ~= 0 then
                    self:DispatchEvent("set_slot_define", is_own, tar_pos, slot_info.cur_ad)
                end
            end

            for k,v in pairs(is_slot_empty) do
                if v then
                    self:DispatchEvent("deploy_monster_card", is_own, k, nil)
                end
            end
        end
        self:CommandComplete()
    end)


    -- show crystal animation
    self:RegisterEvent("show_crystal_animation",function ()
        if self.sync_crystal_callback then
            self.sync_crystal_callback()
            self.sync_crystal_callback = nil
        end
    end)

    self:RegisterEvent("anim_complete",function (anim_name)
        self.is_play_animation = false
        self._standby_block_time = 0

        -- The match panel has multiple safety paths (animation frame,
        -- animation callback, and timeout). Late duplicate standby completions
        -- must not pop the next battle command from the queue.
        if anim_name == "battle_panel_standby" or anim_name == "battle_panel_standby_timeout" then
            local command = self:PopBattleQueue()
            if not command or command.name ~= "cmd_battle_standby" then
                print("[BATTLE] Ignoring duplicate standby anim_complete: " .. tostring(anim_name))
                return
            end
        end

        self:CommandComplete()
    end)


end

-- sync battlefield
function meta:ReqSyncBattlefield()
    if self.standby_status == 1 then
        self:ReqBattleStandby()
        return
    end
    -- self:SendBattle("req_battle_sync",{ round = self.round},function (result, recv_msg)
    --     self.battle_command_queue = {}
    --     local cur_oper_user_id = recv_msg.cur_oper_user_id
    --     local last_oper_time = recv_msg.last_oper_time

    --     local is_own = self.own_player.user_id == cur_oper_user_id
    --     local new_stage = nil
    --     if is_own then
    --         self:SetBattleStage(self.STAGE.own)
    --         self.own_player.last_oper_time = last_oper_time
    --     else
    --         self:SetBattleStage(self.STAGE.enemy)
    --         self.enemy_player.last_oper_time = last_oper_time
    --     end

    --     local sync_actor_list = recv_msg.sync_actor_list or {}
    --     for _, info in pairs(sync_actor_list) do
    --         local actor = self:GetPlayer(info.user_id)
    --         local is_own = self.own_player.user_id == info.user_id
    --         actor.cur_crystal = info.crystal
    --         actor.monster_len = info.monster_size
    --         actor.item_len = info.item_size
    --         self:DispatchEvent("update_monster_num", is_own, actor:GetAllMonsterLenght())
    --         self:DispatchEvent("update_crystal_num", is_own, actor.cur_crystal)


    --         local is_hand_empty = {true, true, true, true}
    --         for _, hand_info in pairs(info.hand_card_list) do
    --             actor:SetHandCard(hand_info.hand_pos, hand_info)
    --             self:DispatchEvent("update_hand_card", is_own, hand_info.hand_pos, hand_info)
    --             is_hand_empty[hand_info.hand_pos] = false
    --         end

    --         for k,v in pairs(is_hand_empty) do
    --             if v then
    --                 self:DispatchEvent("update_hand_card", is_own, k, nil)
    --             end
    --         end

    --         local is_slot_empty = {true, true, true}
    --         local battle_slot_list = info.battle_slot_list or {}
    --         for _, slot_info in pairs(battle_slot_list) do
    --             local tar_pos = slot_info.pos
    --             is_slot_empty[tar_pos] = false
    --             local battle_slot = actor:GetBattleCard(tar_pos)
    --             if not battle_slot then
    --                 battle_slot = require("common.entity.slot").New()
    --                 battle_slot:Init(actor.user_id, tar_pos)
    --             end
    --             actor.battle_slot[tar_pos] = battle_slot

    --             -- Reset card data
    --             battle_slot.pos = tar_pos
    --             battle_slot:SetMonster(slot_info.monster)
    --             battle_slot:SetItem(slot_info.item)
    --             battle_slot.cur_hp = slot_info.cur_hp
    --             battle_slot.cur_ad = slot_info.cur_ad
    --             -- Refresh UI
    --             self:DispatchEvent("deploy_item_card",is_own, tar_pos, slot_info.item)
    --             self:DispatchEvent("deploy_monster_card",is_own, tar_pos, slot_info.monster)
    --             local diff_hp = slot_info.cur_hp - battle_slot.init_hp
    --             if diff_hp ~= 0 then
    --                 self:DispatchEvent("set_slot_hp", is_own, tar_pos, slot_info.cur_hp)
    --             end
    --             local diff_ad = slot_info.cur_ad - battle_slot.init_ad
    --             if diff_ad ~= 0 then
    --                 self:DispatchEvent("set_slot_define", is_own, tar_pos, slot_info.cur_ad)
    --             end
    --         end

    --         for k,v in pairs(is_slot_empty) do
    --             if v then
    --                 self:DispatchEvent("deploy_monster_card", is_own, k, nil)
    --             end
    --         end

    --     end
    -- end)
end

-- operation focus
function meta:ReqOperationFoucs(is_hand, is_own, pos)
    -- self:SendBattle("req_battle_focus", { is_hand = is_hand, pos = pos, is_own = is_own })
end

-- fight over
function meta:ReqFightOver()
    -- self:SendBattle("req_battle_stage", {}, function (result, recv_msg)
        -- print("req_battle_stage>req_battle_stage>req_battle_stage")
    -- end)
end

-- Register network events; queue battle commands and run them one by one
function meta:RegisterNetworkEvent()
    -- battlefield init
    network:RegisterCommand("cmd_battle",function (recv_msg)
        for k,v in pairs(recv_msg) do
            if k == "cmd_battle_start" then
                self:Clean()
                self.battle_id = v["battle_id"]
                self.start_type = v["start_type"]
                self.battle_type = v["battle_type"]
                self.battle_object_type = v["battle_object_type"]
                self.battle_status = v["battle_status"]
                self.pve_battle_info = v["pve_battle_info"]
                analytics:DoBattleStart(self.battle_type)
                local _enter = function ()
                    self.user_id = user_logic.user_id
                    self.is_play_animation = false
                    global:PushScene("battle")
                    self.is_enter_battle = false
                end

                if self.battle_type == "daily" then
                    pve_logic.play_id = self.pve_battle_info.play_id
                    pve_logic.difficulty = self.pve_battle_info.difficulty
                    self.pve_win_cur_value = self.pve_battle_info.pve_win_cur_value
                end

                if self.battle_type == "guide" then
                    guide_logic = require "logic.guide"
                    guide_logic:SetTriggerConfig(self.pve_battle_info.play_id)
                end

                if self.start_type == "replay" then
                    self.is_prepa = true
                    _enter()
                else
                    if self.battle_type == "casual" then
                        analytics:DoCasualMatchOver(true)
                        graphic:DispatchEvent("battle_match_success", _enter)
                    elseif self.battle_type == "periphery" then
                        graphic:DispatchEvent("battle_periphery_success", _enter)
                    elseif self.battle_type == "challenge" then
                        graphic:DispatchEvent("challenge_match_success", _enter)
                    elseif self.battle_type == "friend" then
                        graphic:DispatchEvent("friend_match_success", _enter)
                    else
                        _enter()
                    end

                end

            elseif k == "cmd_battle_focus" then
                self:DispatchEvent(k, v)
            else
                if k == "cmd_battle_over" then
                    self.is_battle_over = true
                end
                self:PushBattleQueue(k,v)
            end
        end
    end)
end

return meta
