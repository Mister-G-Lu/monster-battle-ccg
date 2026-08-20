local network = require "manager.network"
local graphic = require "manager.graphic"
-- local global = require "manager.global"
local timer = require "manager.time"
-- local constants = require "common.constants"
local analytics_manager = require "manager.analytics"
local analytics = require "manager.analytics"
local data_template = require "manager.data_template"

local meta = {}

meta.STAGE = {
    wait = 1,       -- 等待匹配
    match = 2,      -- 匹配中
}
-- 初始化
function meta:Init()
    self.periphery_config = data_template.periphery_config
    self.cur_stage = self.STAGE.wait
    self.card_config = data_template.card_config
    self.cur_min = 0
    self:RegisterMsgHandler()
end

function meta:Query(compleate_func, error_func)
    network:Send("query_arena_info", function (result, recv_msg)
        if result == "success" then
            self.level = recv_msg.level
            analytics_manager:SetArenaLevel(self.level)
            self.next_refresh_chest = recv_msg.next_refresh_chest
            self.last_reward_chest_num = recv_msg.last_reward_chest_num
            self.elo_value = recv_msg.elo_value
            self.last_elo_value = recv_msg.elo_value
            self.arena_stage = recv_msg.stage
            self.ladder_lv = #self.periphery_config +1 - recv_msg.level
            self.last_ladder_lv = self.ladder_lv
            compleate_func()
        else
            error_func(result)
        end
    end)
end

--获取当前elo
function meta:GetEloValue()
    return self.elo_value
end

--设置elo
function meta:SetEloValue(elo)
    self.elo_value = elo
end


--记录上次ELO
function meta:SetLastEloValue(elo)
    self.last_elo_value = elo
end
--获取上一次ELO
function meta:GetLastEloValue()
    return self.last_elo_value
end

--当前战场阶段
function meta:SetStage(stage)
    self.arena_stage = stage
end

--当前战场等级
function meta:SetLevel(level)
    self.level = level
    self.ladder_lv = #self.periphery_config +1 - level
end

--获得当前战场等级
function meta:GetLevel()
    return self.ladder_lv
end
--获得上一次战场等级
function meta:GetLastLevel()
    return self.last_ladder_lv
end
--设置上一次等级
function meta:SetLastLevel(level)
    self.last_ladder_lv = level
end

function meta:Update(elapsed_time)
    self.cur_min = self.cur_min + elapsed_time
    if self.cur_min >= 1 then
        self.cur_min = 0
        self:ReqRefreshReward()
    end
end

--请求刷新时间
function meta:ReqRefreshReward(func)
    if self.next_refresh_chest > timer:Now() then
        return
    end

    local req_data = {}
    req_data["refresh_time"] = timer:Now()
    network:Send("req_arena_refresh_time", req_data, function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        self.next_refresh_chest = recv_msg.next_refresh_time
        self.last_reward_chest_num = recv_msg.reward_chest_num
        if func then func() end
    end)
end

-- 加入竞技场匹配
function meta:DoJoinMatch()
    network:Send("req_arena_join_match",function (result, _)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        self.cur_stage = self.STAGE.match
        graphic:DispatchEvent("switch_arena_stage", self.cur_stage)
    end)
end

-- 退出竞技场匹配
function meta:DoCancelMatch()
    if self.cur_stage == self.STAGE.wait then
        return false
    end
    network:Send("req_arena_cancel_match",function (result, _)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        graphic:DispatchEvent("switch_arena_stage", self.STAGE.wait)
        self.cur_stage = self.STAGE.wait
    end)
    return true
end

-- 加入竞技场匹配
function meta:DoJoinCasual()
    network:Send("req_arena_join_match",function (result, _)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        analytics:DoCasualMatchStart()
        self.cur_stage = self.STAGE.match
        graphic:DispatchEvent("switch_arena_stage", self.cur_stage)
    end)
end

-- 退出竞技场匹配
function meta:DoCancelCasual()
    if self.cur_stage == self.STAGE.wait then
        return false
    end
    network:Send("req_arena_cancel_match",function (result, _)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end
        analytics:DoCasualMatchOver(false, "normal")
        graphic:DispatchEvent("switch_arena_stage", self.STAGE.wait)
        self.cur_stage = self.STAGE.wait
    end)
    return true
end
-- 注册网络事件
function meta:RegisterMsgHandler()

    network:RegisterCommand("cmd_arena_refresh_time", function (recv_msg)
        self.next_refresh_chest = recv_msg.next_refresh_time
        self.last_reward_chest_num = recv_msg.reward_chest_num
        graphic:DispatchEvent("refresh_reward_num")
    end)
end

return meta
