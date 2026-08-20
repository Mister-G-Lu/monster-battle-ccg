local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"

local user_logic = require "logic.user"
local timer = require "manager.time"
local constants = require "common.constants"

local FLUSH_INTERVAL = 3600

local meta = {}

--排序的算法
local function rank_elo_sort(a,b)
    return a.elo_value > b.elo_value
end

local RANK_LIST_HANDER_FUNC = {
    ["global_elo"] = function(rank_record_list)
        return rank_record_list
    end,

    ["friend_elo"] = function(rank_record_list)
        table.sort(rank_record_list, rank_elo_sort)
        return rank_record_list
    end,
}

-- 初始化
function meta:Init()
    self.start_pos = 1
    self.end_pos = 100
    self.next_flush_time = {}
    self.user_rank = {}
    self.rank_record_list = {}
    self.rank_type = "global_elo"
end

function meta:QueryUserRank()
    local rank_record_list = self.rank_record_list[self.rank_type]
    for k,v in pairs(rank_record_list) do
        if v.user_id == user_logic.user_id then
            self.user_rank[self.rank_type] = k
            break
        end
    end
end

function meta:GetUserRank()
    return self.user_rank[self.rank_type]
end

function meta:SetRankType(rank_type)
    self.rank_type = rank_type
end

function meta:GetRankType(rank_type)
    return self.rank_type
end

function meta:GetRankList()
    return self.rank_record_list[self.rank_type]
end

function meta:QueryRank()

    local cur_time = timer:Now()
    local next_flush_time = self.next_flush_time[self.rank_type] or 0

    if cur_time > next_flush_time then
        local req_msg = {
            rank_type = self.rank_type,
            start_pos = self.start_pos,
            end_pos = self.end_pos,
        }

        network:Send("req_rank_info", req_msg, function (result, recv_msg)
            if result ~= "success" then
                graphic:DispatchEvent("show_message", result)
                return
            end
            self.next_flush_time[self.rank_type] = timer:Now() + FLUSH_INTERVAL
            local rank_record_list = recv_msg.rank_list or {}
            local hander = RANK_LIST_HANDER_FUNC[self.rank_type]

            self.rank_record_list[self.rank_type] = hander(rank_record_list)
            self:QueryUserRank()
            graphic:DispatchEvent("push_world_panel", "rank", "rank_panel")
        end)
    else
        graphic:DispatchEvent("push_world_panel", "rank", "rank_panel")
    end
end

function meta:RegisterMsgHandler()

end

return meta
