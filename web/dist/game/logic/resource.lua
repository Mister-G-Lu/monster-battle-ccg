local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"
local timer = require "manager.time"
local constants = require "common.constants"

local meta = {}
-- 初始化
function meta:Init()

    self.resource_list = {}
    for k, v in pairs(constants["RESOURCE_TYPE"]) do
        self[k] = 0
    end
    self.item_bag = {}

    self:RegisterMsgHandler()
end

function meta:Query(compleate_func, error_func)
    network:Send("query_resource_info",function (result, recv_msg)
        if result == "success" then
            for k, v in pairs(constants["RESOURCE_TYPE"]) do
                self[k] = recv_msg[k]
            end
            local list = recv_msg["item_list"] or {}
            for k,v in pairs(list) do
                self.item_bag[v.uid] = v
            end
            compleate_func()
        else
            error_func(result)
        end
    end)
end

-- 添加道具,从服务端的过来的数据都是更新。
function meta:AddItem(v)
    local uid = v.uid
    self.item_bag[uid] = v
end

-- 添加道具列表
function meta:AddItemList(item_list)
    item_list = item_list or {}
    for k,v in pairs(item_list) do
        self:AddItem(v)
    end
end

-- 获取道具数量
function meta:GetItemNum(item_id)
    local item = self.item_bag[item_id]
    if not item then return 0 end
    return item.num
end

-- 注册网络事件
function meta:RegisterMsgHandler()
    -- 更新道具
    network:RegisterCommand("update_item_list", function (recv_msg)
        local item_list = recv_msg.item_list or {}
        self:AddItemList(item_list)
    end)

    -- 更新金钱
    network:RegisterCommand("update_resource_money", function (money)
        self.money = money or self.money
        graphic:DispatchEvent("update_money_value", self.money)
    end)

    -- 更新钻石
    network:RegisterCommand("update_resource_coin", function (coin)
        self.coin = coin or self.coin
        graphic:DispatchEvent("update_coin_value", self.coin)
    end)

end

return meta
