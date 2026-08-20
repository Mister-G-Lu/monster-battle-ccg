local network = require "manager.network"
local graphic = require "manager.graphic"
local data_manager = require "manager.data_template"

local bit = require "utils.bit_extension"

local user_logic = require "logic.user"
local battle_logic = require "logic.battle"


local attack_target_count

local BATTLE_GUIDE_FUNC = {
    [1] = {
        ["cmd_battle_move_func"] = function(trigger_event, event_info)

            local is_own = user_logic.user_id == event_info.src_user_id
            local card = battle_logic.enemy_player:GetHandCard(event_info.src_hand_pos)

            if not is_own then
                if tonumber(card.uid) == trigger_event.trigger_monster_id then
                    battle_logic:DispatchEvent("update_dialogue", is_own, trigger_event)
                    trigger_event.trigger_command = nil
                end
            end
        end,
        ["battle_slot_emtpy"] = function(trigger_event, _)
            if battle_logic.is_own then
                local battle_slot_num = battle_logic.own_player:GetBattleCardLenght()
                if battle_slot_num == 0 then
                    battle_logic:DispatchEvent("update_dialogue", battle_logic.is_own, trigger_event)
                    trigger_event.trigger_command = nil
                end
            end
        end,
        ["deploy_melee_error_func"] = function(trigger_event, event_info)

            local is_own = user_logic.user_id == event_info.src_user_id
            local card = battle_logic.own_player:GetHandCard(event_info.src_hand_pos)

            if is_own then
                for _, power in pairs(card.power_list) do
                    if power.name == trigger_event.trigger_condition and event_info.desc_slot_pos ~= 1 then
                        battle_logic:DispatchEvent("update_dialogue", is_own, trigger_event)
                        trigger_event.trigger_command = nil
                    end
                end
            end
        end,

        ["deploy_ranged_error_func"] = function(trigger_event, event_info)

            local is_own = user_logic.user_id == event_info.src_user_id
            local card = battle_logic.own_player:GetHandCard(event_info.src_hand_pos)

            if is_own then
                for _, power in pairs(card.power_list) do
                    if power.name == trigger_event.trigger_condition and event_info.desc_slot_pos == 1 then
                        battle_logic:DispatchEvent("update_dialogue", is_own, trigger_event)
                        trigger_event.trigger_command = nil
                    end
                end
            end
        end,

        ["cmd_battle_attack_func"] = function(trigger_event, event)
            if event.power_name == trigger_event.trigger_condition then

                if not battle_logic.is_own then
                    local battle_slot = battle_logic.enemy_player:GetBattleCard(event.src_pos)
                    local card = battle_slot.monster

                    if tonumber(card.uid) == trigger_event.trigger_monster_id then
                        battle_logic:DispatchEvent("update_dialogue", battle_logic.is_own, trigger_event)
                        trigger_event.trigger_command = nil
                    end
                end
            end
        end,

        ["cmd_battle_over_func"] = function(trigger_event, event_info)
            if trigger_event.trigger_condition == event_info.win_user_id then
                battle_logic:DispatchEvent("update_dialogue", false, trigger_event)
                trigger_event.trigger_command = nil
            end
        end,
    },
    [2] = {
        ["cmd_battle_move_func"] = function(trigger_event, event_info)
            if not battle_logic.is_own then
                local battle_slot = battle_logic.enemy_player:GetBattleCard(event_info.desc_slot_pos)
                if battle_slot then
                    local monster_card = battle_slot.monster
                    local hand_card = battle_logic.enemy_player:GetHandCard(event_info.src_hand_pos)

                    local monster_condition = trigger_event.trigger_monster_id == tonumber(monster_card.uid)
                    local item_condition = trigger_event.trigger_item_id == tonumber(hand_card.uid)

                    if monster_condition and item_condition then
                        battle_logic:DispatchEvent("update_dialogue", battle_logic.is_own, trigger_event)
                        trigger_event.trigger_command = nil
                    end
                end
            end
        end,
        ["cmd_battle_prepa_func"] = function(trigger_event, event_info)
            local is_own = user_logic.user_id == event_info.user_id
            if is_own then
                for _, battle_slot in pairs(battle_logic.enemy_player.battle_slot) do
                    if battle_slot then
                        local monster_condition = trigger_event.trigger_monster_id == tonumber(battle_slot.monster.uid)
                        if monster_condition and battle_slot.item then
                            local item_condition = trigger_event.trigger_item_id == tonumber(battle_slot.item.uid)

                            if item_condition then
                                battle_logic:DispatchEvent("update_dialogue", is_own, trigger_event)
                                trigger_event.trigger_command = nil
                            end
                        end
                    end
                end
            end
        end,
        ["physics_attack"] = function(trigger_event, event)
            if event.power_name == "ranged" or event.power_name == "melee" then

                if battle_logic.is_own then
                    local battle_slot = battle_logic.enemy_player:GetBattleCard(event.tar_pos)
                    if battle_slot then
                        local card = battle_slot.monster
                        if attack_target_count ~= tonumber(trigger_event.trigger_condition) then
                            return false
                        end

                        if tonumber(card.uid) == trigger_event.trigger_monster_id then
                            battle_logic:DispatchEvent("update_dialogue", battle_logic.is_own, trigger_event)
                            attack_target_count = attack_target_count + 1
                            trigger_event.trigger_command = nil
                        end
                    end
                end
            end
        end,
        ["magic_attack"] = function(trigger_event, event)
            if event.power_name == trigger_event.trigger_condition then
                if battle_logic.is_own then
                    local battle_slot = battle_logic.enemy_player:GetBattleCard(event.tar_pos)
                    local card = battle_slot.monster

                    if tonumber(card.uid) == trigger_event.trigger_monster_id then
                        battle_logic:DispatchEvent("update_dialogue", false, trigger_event)
                        trigger_event.trigger_command = nil
                    end
                end
            end
        end,
    }
}

-- 战斗阶段
local meta = {}

function meta:Init()
    attack_target_count = 1
    self:RegisterMsgHandler()
end

function meta:SetTriggerConfig(play_id)
    local BATTLE_GUIDE_EVENT_CONFIG = data_manager.battle_guide_event_config
    self.guide_trigger_config = table.copy(BATTLE_GUIDE_EVENT_CONFIG[play_id])
    self.battle_guide_id = play_id
end

function meta:Query(compleate_func, error_func)
    network:Send("req_guide_panel", {}, function (result, recv_msg)
        if result ~= "success" then
            if error_func then error_func() end
        end
        self.guide_flag = recv_msg.guide_flag
        -- Skip tutorial: mark all 4 guide steps as complete
        self.guide_flag = bit:SetBitNum(self.guide_flag, 1, true)
        self.guide_flag = bit:SetBitNum(self.guide_flag, 2, true)
        self.guide_flag = bit:SetBitNum(self.guide_flag, 3, true)
        self.guide_flag = bit:SetBitNum(self.guide_flag, 4, true)

        if compleate_func then compleate_func() end
    end)
end


-- 请求指引完成
function meta:ReqGuideComplete()
    network:Send("req_guide_complete", { guide_id = self.cur_guide_id }, function ()
        self:DoGuide()
    end)
end

-- 检查引导是否完成
function meta:CheckGuideComplete(guide_id)
    return bit:GetBitNum(self.guide_flag, guide_id) == 1
end

function meta:SetGuide(guide_id)
    self.cur_guide_id = guide_id
    self.guide_step_idx = 0
    self:DoGuide()
end

function meta:DoGuide()
    if not self.cur_guide_id then
        return
    end
    self.guide_step_idx = self.guide_step_idx + 1
    local guide_key = self.cur_guide_id .. "_" .. self.guide_step_idx
    local step_config = data_manager.guide_step_config[guide_key]
    if not step_config then
        self:CheckNewGuide()
        return
    end

    local step_type = step_config.step_type
    local step_info = step_config.step_info
    if step_type == "show_chat" then
        graphic:DispatchEvent("push_world_panel", "guide", "guide_panel", function ()
            self:DoGuide()
        end)
    elseif step_type == "hide_chat" then
        graphic:DispatchEvent("pop_world_panel", "guide", "guide_panel")
        self:DoGuide()
    elseif step_type == "chat" then
        graphic:DispatchEvent("show_guide_chat", step_info, function ()
            self:DoGuide()
        end)
    elseif step_type == "show_chest" then
        local show_data_list = {}
        local card_list = {}
        local list = string.split(step_info, "|")
        for _, v in pairs(list) do
            local card_info = {}
            card_info.reward_card_id = tonumber(v)
            card_info.is_resolve = false
            table.insert(card_list, card_info)
        end
        local reward_list = {}
        show_data_list.card_list = card_list
        show_data_list.reward_list = reward_list
        graphic:DispatchEvent("push_world_panel", "chest", "open_chest_panel", show_data_list, function ()
            self:DoGuide()
        end)

    elseif step_type == "req_battle_guide" then
        local battle_guide_id = tonumber(step_info)
        self:ReqBattleGuide(battle_guide_id)
    elseif step_type == "guide_complete" then
        self:ReqGuideComplete(step_info)
    end
end

-- 是否开启战斗设置
function meta:IsOpenBattleSetting()
    return self:CheckGuideComplete(1) and self:CheckGuideComplete(3)
end

-- 检查新的引导
function meta:CheckNewGuide()
    local guide_config = data_manager.guide_config
    for _, v in pairs(guide_config) do
        local guide_id = v.ID
        local trigger_cond = v.trigger_cond
        local trigger_value = v.trigger_value
        -- 检查引导是否完成
        if not self:CheckGuideComplete(guide_id) then
            if trigger_cond == "" then
                self:SetGuide(guide_id)
                return true
            end
            -- 检查引导是否完成
            if trigger_cond == "check_guide" and self:CheckGuideComplete(trigger_value) then
                self:SetGuide(guide_id)
                return true
            end
        end
    end
    self.cur_guide_id = nil
    return false
end

function meta:ParseBattleEvent(event_name, event_info)
    for _, v in pairs(self.guide_trigger_config) do
        if event_name == v.trigger_command then
            local func = BATTLE_GUIDE_FUNC[self.battle_guide_id][v.trigger_func]
            if func then
                func(v, event_info)
            end
        end
    end
end

function meta:ReqBattleGuide(battle_guide_id)
    local req_data = {}
    req_data["battle_process"] = battle_guide_id
    network:Send("req_guide_battle",req_data)
end


function meta:Update()
end

function meta:RegisterMsgHandler()
    network:RegisterCommand("cmd_guide_info",function (recv_msg)
        for k,v in pairs(recv_msg) do
            self[k] = v
        end
    end)
end

return meta
