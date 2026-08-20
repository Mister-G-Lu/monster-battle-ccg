local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"
local timer = require "manager.time"
local data_template = require "manager.data_template"

local resource_logic = require "logic.resource"

local constants = require "common.constants"


local CHEST_STAGE = constants.CHEST_STAGE
local ARENA_MAX_CHEST = 4

local meta = {}
function meta:Init()
    self.cur_min = 0
    self.req_refresh = false
    self:RegisterMsgHandler()
end


function meta:Update(elapsed_time)
    if self.req_refresh then
        return
    end
    self.cur_min = self.cur_min + elapsed_time
    local diff_time = self.next_refresh_time - timer:Now()
    if self.cur_min >= 1 and diff_time <= 0 then
        self.cur_min = 0
        self.req_refresh = true
        self:Query(
        function ()
            -- 通知日常刷新了
            graphic:DispatchEvent("refresh_daily_info")
            self.req_refresh = false
        end,
        function ()
            self.req_refresh = false
        end
        )
    end
end

function meta:Query(compleate_func, error_func)
    local req_data = {}
    req_data["refresh_time"] = timer:Now()
    network:Send("req_refresh_daily", req_data, function (result, recv_msg)
        if result == "success" then
            recv_msg = recv_msg or {}
            for k,v in pairs(recv_msg) do
                self[k] = v
            end
            if compleate_func then compleate_func() end
        else
            if error_func then error_func(result) end
        end
    end)
end

-- 请求登陆奖励
function meta:ReqLoginReward()
    if self.login_reward == 0 then
        return
    end
    network:Send("req_login_reward", function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end

        local reward_list = recv_msg.reward_list or {}

        if #reward_list >0 then
            graphic:DispatchEvent("show_reward_panel", reward_list)
        end

    end)
end

-- 注册网络请求
function meta:RegisterMsgHandler()
    network:RegisterCommand("update_daily_info", function (recv_msg)
        for k,v in pairs(recv_msg) do
            self[k] = v
        end
        print("recv_msg = ", tostring(recv_msg))
        -- 更新喽
    end)
end

return meta
