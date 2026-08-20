local constants = require "common.constants"

local CARD_TYPE = constants.CARD_TYPE

local meta = {}
meta.__index = meta

function meta.New(metadata)
    return table.new(meta, metadata or {})
end

function meta:IsFull()
    return self:IsMonsterFull() and self:IsItemFull()
end

function meta:IsMonsterFull()
    return #self.monster_list >= 8
end

function meta:IsItemFull()
    return #self.item_list >= 8
end

-- 部署卡牌
function meta:DeployCard(uid, target_pos, card_config_map)
    target_pos = target_pos or -1
    local list = {}
    local config = card_config_map[uid]

    local group_id = config.group_id
    local card_type = config.type
    local deck_limit = config.deck_limit

    if card_type == CARD_TYPE.monster then
        list = self.monster_list
        local len = #list
        if len >= 8 and target_pos == -1 then
            return false, "deck_monster_full"
        end

        local count = 0
        for k,v in pairs(list) do
            local card_config = card_config_map[v]
            if card_config.group_id == group_id then
                count = count + 1
            end
        end

        local old_uid = list[target_pos]
        if old_uid then
            local old_card_config = card_config_map[old_uid]
            if old_card_config.group_id == group_id then
                count = count - 1
            end
        end

        if count >= deck_limit then
            return false, "deck_limit_desc"
        end

        if len < 8 and target_pos == -1 then
            table.insert(list, uid)
        else
            list[target_pos] = uid
        end
        -- 必须这样赋值，否则会出保存上面的问题
        self.monster_list = list
        return true, old_uid

    else
        list = self.item_list
        local len = #list
        if len >= 8 and target_pos == -1 then
            return false, "deck_item_full"
        end

        local count = 0
        for k,v in pairs(list) do
            local card_config = card_config_map[v]
            if card_config.group_id == group_id then
                count = count + 1
            end
        end
        if count >= deck_limit then
            return false, "deck_limit_desc"
        end

        local old_uid = list[target_pos]
        if len < 8 and target_pos == -1 then
            table.insert(list, uid)
        else
            list[target_pos] = uid
        end
        -- 必须这样赋值，否则会出保存上面的问题
        self.item_list = list
        return true, old_uid
    end
end

function meta:GetGroupCardNum(uid,card_config_map)
    local config = card_config_map[uid]
    local group_id = config.group_id
    local card_type = config.type
    local deck_limit = config.deck_limit
    local list
    if card_type == CARD_TYPE.monster then
        list = self.monster_list
    else
        list = self.item_list
    end
    local count = 0
    for k,v in pairs(list) do
        local card_config = card_config_map[v]
        if card_config.group_id == group_id then
            count = count + 1
        end
    end
    return count
end

return meta
