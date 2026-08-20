local network    = require "manager.network"
local graphic    = require "manager.graphic"

local resource_logic = require "logic.resource"

local constants  = require "common.constants"
local REWARD_TYPE = constants["REWARD_TYPE"]

local meta = {}

function meta:Init()
    -- 是否正在开启卡包中
    self.is_open_chesting = false
    -- 卡包背包列表
    self.chest_bag = {}
    self:RegisterMsgHandler()
end


function meta:GetChestInfo(chest_id)
    return self.chest_bag[chest_id]
end

-- 查询宝箱系统状态
function meta:Query(compleate_func, error_func)
    network:Send("query_chest_info",function (result, recv_msg)
        if result == "success" then
            compleate_func()
            self.chest_bag = {}
            local list = recv_msg.chest_list or {}
            for _, v in pairs(list) do
                self.chest_bag[v.chest_id] = v
            end
        else
            error_func(result)
        end
    end)
end

-- 开启宝箱
function meta:OpenChest(chest_id)
    local chest_info =  self.chest_bag[chest_id]
    if not chest_info or chest_info.chest_num <= 0 then
        graphic:DispatchEvent("show_message", "chest_is_empty")
    else
        if self.is_open_chesting then
            return
        end
        -- 开启卡包，确保动画播放完毕后。才能再次发开发请求
        self.is_open_chesting = true
        network:Send("req_open_chest", { chest_id = chest_id }, function (result, recv_msg)
            if result ~= "success" then
                graphic:DispatchEvent("show_message", result)
                return
            end


            local harvert_list = recv_msg.harvert_list or {}

            local show_data_list = {}
            local card_list = {}
            local new_item_list = {}

            for _, v in pairs(harvert_list) do
                local card_info = {}
                card_info.reward_card_id = v.reward_card_id
                card_info.is_resolve = v.is_resolve
                table.insert(card_list, card_info)

                local item_list = v.item_list or {}
                for _, item in pairs(item_list) do
                    local num = new_item_list[item.uid] or 0
                    new_item_list[item.uid] = math.max(num, item.num)
                end
            end

            local reward_list = {}
            for k,v in pairs(new_item_list) do
                local old_num = resource_logic:GetItemNum(k)
                table.insert(reward_list, { type = REWARD_TYPE["resource"], attr_id = k, value = v - old_num })
                resource_logic:AddItem({ uid = k, num = v})
            end

            show_data_list.card_list = card_list
            show_data_list.reward_list = reward_list

            -- 弹出抽卡动画
            if harvert_list then
                graphic:DispatchEvent("push_world_panel", "chest", "open_chest_panel", show_data_list)
            else
                self.is_open_chesting = false
            end
            chest_info.chest_num = chest_info.chest_num - 1
            graphic:DispatchEvent("refresh_chest_info", chest_info)
        end)
    end
end

-- 添加卡包信息
function meta:UpdateChestInfo(chest_info)
    self.chest_bag[chest_info.chest_id] = chest_info
    graphic:DispatchEvent("refresh_chest_info", chest_info)
end

-- 注册网络请求
function meta:RegisterMsgHandler()
    network:RegisterCommand("cmd_update_chest",function (recv_msg)
        local chest_info = recv_msg.chest_info
        self:UpdateChestInfo(chest_info)
    end)
end

return meta
