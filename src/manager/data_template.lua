local csv = require "utils.csv"
local constants = require "common.constants"
local bit = require "utils.bit_extension"

local meta = {}
local text_loader

function meta:Init()
    csv.Init("res/data/")
    text_loader = require "manager.text_loader"
    self.pre_idx = 1
    self.is_load_complete = false
    self.complete_event = nil
end

-- Apply localized text
local function TranslationText(text_config, key, row)
    key = tostring(key)
    row = row or {}
    local config_list = text_config[key] or {}
    for _, table in pairs(config_list) do
        local field = table["field"]
        local value = table["text"]
        row[field] = value
    end
    return row
end

-- Load item table
local function LoadItemConfig()
    local list = csv.Load("all_item_config")
        local text_config = text_loader["item_config"] or {}

    local item_list = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, tostring(v.ID), v)
        item_list[v.ID] = v
    end
    return item_list
end

-- Load card resolve table
local function LoadCardResolveConfig()
    local list = csv.Load("all_card_resolve_config")
    local card_resolve_config = {}
    for k, v in pairs(list) do
        local card_id = v.card_id
        local item_id = v.item_id
        local item_num = v.item_num

        local item_list = {}
        local config = {}
        config["item_id"] = v.item_id
        config["item_num"] = v.item_num
        table.insert(item_list, config)
        for i = 1, 10 do
            local item_id = v["item_id"..i]
            local item_num = v["item_num"..i]
            if item_id and item_num and item_id ~= 0 and item_num ~= 0 then
                local config = {}
                config["item_id"] = item_id
                config["item_num"] = item_num
                table.insert(item_list, config)
            end
        end

        if card_id == nil or card_id == 0 then
            for kk,vv in pairs(constants["CARD_KIND"]) do
                if bit:GetBitNum(v.kind, vv) == 1 then
                    local key = kk.."_"..v.type.."_"..v.quality.."_"..v.level
                    card_resolve_config[tostring(key)] = item_list
                end
            end
        else
            card_resolve_config[card_id] = item_list
        end
    end
    return card_resolve_config
end

-- Load card upgrade table
local function LoadCardUpgradeConfig()
    local list = csv.Load("all_card_upgrade_config")
    local card_upgrade_config = {}
    for k,v in pairs(list) do
        local config = {}
        config.card_id = v.card_id
        config.next_card_id = v.next_card_id
        config.req_money = v.req_money or 0
        config.req_coin = v.req_coin or 0
        config.req_material_list = {}
        for i = 1, 9 do
            local str = v["req_material_"..i]
            if str and str ~= "" then
                local m_t, m_id, m_num = string.match(str, "(%w+)|(%w+)|(%w+)")
                if m_t and m_id and m_num then
                    table.insert(config.req_material_list, {kind = m_t, attr_id = tonumber(m_id), num = tonumber(m_num)})
                else
                    print("failed to parse config， str = "..str)
                end
            end
        end
        card_upgrade_config[v.card_id] = config
    end

    return card_upgrade_config
end
-- Load card compose table
local function LoadCardComposeConfig()
    local list = csv.Load("all_card_compose_config")
    local card_compose_config = {}
    for k,v in pairs(list) do
        local id =v.ID
        local card_id = v.card_id
        local item_id = v.item_id
        local item_num = v.item_num
        local item_list = {}
        local config = {}
        config["item_id"] = v.item_id
        config["item_num"] =v.item_num
        table.insert(item_list,config)
        for i = 1,10 do
            local item_ids = v["item_id"..i]
            local item_nums = v["item_num"..i]
            if item_ids and item_nums and item_ids ~= 0 and item_nums ~= 0 then --and item_id ~= 0 and item_num ~= 0

                local config ={}
                config["item_id"]  = item_ids
                config["item_num"] = item_nums
                table.insert(item_list,config)
            end
        end
        card_compose_config[card_id] = item_list
    end
    --dump(card_compose_config)
    return card_compose_config
    -- body
end
-- Proficiency config
local function LoadProficiencyConfig()
    local list = csv.Load("all_proficiency_config")
    local proficiency_list = {}
    local text_config = text_loader["proficiency_config"] or {}

    for k,v in pairs(list) do
        v["level"] = v.ID
        v = TranslationText(text_config, tostring(v.ID), v)
        proficiency_list[v.ID] = v
    end
    return proficiency_list
end

--Adventure config
local function LoadAdventureConfig()
    local list = csv.Load("all_adventure_config")
    local adventure_list = {}
    local text_config = text_loader["adventure_config"] or {}

    for k,v in pairs(list) do
        v = TranslationText(text_config, tostring(v.ID), v)
        adventure_list[v.ID] = v
    end

    return adventure_list
end 

-- Load chest templates
local function LoadChestConfig()
    local list = csv.Load("all_chest_config")
    local chest_map = {}
    local text_config = text_loader["chest_config"] or {}

    for k, v in pairs(list) do
        -- local
        local reward_money = v["reward_money"]
        v.reward_money = {}
        for w in string.gmatch(reward_money, "%d+") do
            table.insert(v.reward_money, w)
        end
        if #v.reward_money == 1 then
            table.insert(v.reward_money, 1, 0)
        end

        local guarantee = v["guarantee"]
        local reward_card = {}
        for w in string.gmatch(guarantee, "%d+") do
            table.insert(reward_card, w)
        end
        v.guarantee = {}
        for kk,vv in pairs(constants.CARD_QUALITY) do
            v.guarantee[kk] = tonumber(reward_card[vv] or 0)
        end
        v = TranslationText(text_config, tostring(v.ID), v)
        chest_map[v.ID] = v
    end
    return chest_map
end
-- Load card templates
local function LoadCardConfig()
    local list = csv.Load("all_power_config")
    local power_map = {}
    for k,v in pairs(list) do
        local config = {}
        config["type"] = v.type
        config["target_type"] = v.target_type
        power_map[v.name] = config
    end


    local list = csv.Load("all_card_config")
    local card_config_list = {}
    local text_config = text_loader["card_config"] or {}


    for k,v in pairs(list) do
        local config = {}
        config.uid = tostring(k)
        config.level = v["level"]
        config.name = v["name"]
        config.type = v["type"]
        config.group_id = v["group_id"]
        config.deck_limit = v["deck_limit"]
        config.kind = 0
        config.kind_list = {}
        local kind = v["kind"]
        for w in string.gmatch(kind, "%a+") do
            local kind_flag = constants.CARD_KIND[w]
            config.kind = bit:SetBitNum(config.kind, kind_flag, true)
            table.insert(config.kind_list, w)
        end

        config.quality = v["quality"]
        config.hp = v["hp"]
        config.res_path = v["res_path"]
        config.cost = v["cost"]
        config.score = v["score"]
        config.power_list = {}

        if v.p1n and v.p1n ~= "" then
            local power = {}
            power.name = string.lower(v.p1n)
            power.value = v.p1v
            local p_config = power_map[v.p1n]
            if p_config then
                power.target_type = p_config.target_type
                power.type = p_config.type
                table.insert(config.power_list, power)
            else
                print("power1 name = "..v.p1n.." config is null")
            end
        end
        if v.p2n and v.p2n ~= "" then
            local power = {}
            power.name = string.lower(v.p2n)
            power.value = v.p2v
            local p_config = power_map[v.p2n]
            if p_config then
                power.target_type = p_config.target_type
                power.type = p_config.type
                table.insert(config.power_list, power)
            else
                print("power2 name = "..v.p2n.." config is null")
            end
        end
        if v.p3n and v.p3n ~= "" then
            local power = {}
            power.name = string.lower(v.p3n)
            power.value = v.p3v
            local p_config = power_map[v.p3n]
            if p_config then
                power.target_type = p_config.target_type
                power.type = p_config.type
                table.insert(config.power_list, power)
            else
                print("power3 name = "..v.p3n.." config is null")
            end
        end

        config = TranslationText(text_config, k, config)
        card_config_list[tostring(k)] = config
    end

    return card_config_list
end
-- Load power templates
local function LoadPowerConfig()
    local list = csv.Load("all_power_config")
    local text_config = text_loader["power_config"] or {}
    local power_map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.name, v)
        power_map[v.name] = v
    end
    return power_map
end
-- Load status templates
local function LoadStatusConfig()
    local list = csv.Load("all_status_config")
    local text_config = text_loader["status_config"] or {}
    local config_map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.name, v)
        local against_power_list_str = v.against_power_list
        v.against_power_list = string.split(against_power_list_str, ",")
        config_map[v.name] = v
    end
    return config_map
end
-- Tips text config
local function LoadTipsConfig()
    local list = csv.Load("client_tips_config")
    local text_config = text_loader["tips_config"] or {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
    end
    return list
end

-- Load task table
local function LoadTaskConfig()
    local list = csv.Load("all_task_config")
    local text_config = text_loader["task_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        local reward_list = {}
        for i = 1, 2 do
            local rr = {}
            rr.type = v["reward_type"..i]
            rr.attr_id = v["reward_id"..i]
            rr.value = v["reward_num"..i]
            if rr.attr_id ~= 0 then
                table.insert(reward_list, rr)
            end
        end
        local info = {}
        info["task_type"] = v.task_type
        info["desc"] = v.desc
        info["reward_list"] = reward_list
        info["value"] = v.value
        map[v.ID] = info
    end
    return map
end

-- Load achievement table
local function LoadAchievementConfig()
    local list = csv.Load("all_achievement_config")
    local text_config = text_loader["achievement_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        local reward_list = {}
        for i = 1, 1 do
            local rr = {}
            rr.type = v["reward_type"..i]
            rr.attr_id = v["reward_id"..i]
            rr.value = v["reward_num"..i]
            if rr.attr_id ~= 0 then
                table.insert(reward_list, rr)
            end
        end
        local info = {}
        info["achievement_type"] = v.achievement_type
        info["reward_points"] = v.reward_points
        info["reward_list"] = reward_list
        info["value"] = v.value
        map[v.ID] = info
    end
    return map
end

-- Load statistic table
local function LoadStatisticConfig()
    local list = csv.Load("all_statistic_config")
    local text_config = text_loader["statistic_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        local info = {}
        info["statistic_type"] = v.statistic_type
        info["desc"] = v.desc
        map[v.ID] = info
    end
    return map
end

local function LoadPvePlay()
    local list = csv.Load("all_pve_play_config")
    local text_config = text_loader["pve_play_config"] or {}
    local pve_map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        local pve_play_id = tonumber(v.play_id .. v.difficulty)
        pve_map[pve_play_id] = v
    end
    return pve_map
end

local function LoadPveLimitPlay()
    local list = csv.Load("all_pve_limit_config")
    local text_config = text_loader["pve_limit_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        map[v.ID] = v
    end

    return map
end
--Ladder
local function LoadPeripheryConfig()
    local list = csv.Load("all_periphery_config")
    local text_config = text_loader["periphery_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        map[v.ID] = v
    end
    return map
end

--MVP damage stats table
local function LoadCardStateConfig()
    local list = csv.Load("all_card_stat_config")
    local text_config = text_loader["card_stat_config"] or {}
    local state_list = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, tostring(v.ID), v)
        -- v["stat_name"] = v.ID
        state_list[v.ID] = v
    end
    return state_list
end
local function LoadBattleGuideEventConfig()
    local list = csv.Load("client_battle_guide_event_config")
    local text_config = text_loader["battle_guide_event_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)

        if not map[v.battle_guide_id] then
            map[v.battle_guide_id] = {}
        end
        table.insert(map[v.battle_guide_id], v)
    end
    return map
end

-- Guide table
local function LoadGuideConfig()
    local list = csv.Load("all_guide_config")
    local text_config = text_loader["guide_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        v = TranslationText(text_config, v.ID, v)
        map[v.ID] = v
    end
    return map
end

-- Guide step table
local function LoadGuideStepConfig()
    local list = csv.Load("client_guide_step_config")
    local text_config = text_loader["guide_step_config"] or {}
    local map = {}
    for k,v in pairs(list) do
        local key = v.guide_id.."_"..v.step_id
        v = TranslationText(text_config, key, v)
        map[key] = v
    end
    return map
end

function meta:SetCompleteEvent(func)
    if self.is_load_complete then
        func()
    else
        self.complete_event = func
    end
end

function meta:LoadFromCSV()
    if self.is_load_complete then
        return
    end
    -- Load all configs in one shot (was: 1 per frame over 21 frames)
    self.tips_config = LoadTipsConfig()
    self.pve_limit_config = LoadPveLimitPlay()
    self.card_upgrade_config = LoadCardUpgradeConfig()
    self.item_config = LoadItemConfig()
    self.chest_config = LoadChestConfig()
    self.power_config = LoadPowerConfig()
    self.status_config = LoadStatusConfig()
    self.card_resolve_config = LoadCardResolveConfig()
    self.proficiency_config = LoadProficiencyConfig()
    self.card_compose_config = LoadCardComposeConfig()
    self.task_config = LoadTaskConfig()
    self.achievement_config = LoadAchievementConfig()
    self.statistic_config = LoadStatisticConfig()
    self.pve_play_config = LoadPvePlay()
    self.card_config = LoadCardConfig()
    self.periphery_config = LoadPeripheryConfig()
    self.battle_guide_event_config = LoadBattleGuideEventConfig()
    self.guide_config = LoadGuideConfig()
    self.guide_step_config = LoadGuideStepConfig()
    self.adventure_config = LoadAdventureConfig()
    self.card_state_config = LoadCardStateConfig()
    self.is_load_complete = true
    if self.complete_event then
        self.complete_event()
        self.complete_event = nil
    end

end

return meta
