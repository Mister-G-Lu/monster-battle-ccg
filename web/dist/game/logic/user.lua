local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"
local text_loader = require "manager.text_loader"
local analytics_manager = require "manager.analytics"
local timer = require "manager.time"

local resource_logic
local deck_logic
local arena_logic
local chest_logic
local mail_logic
local daily_logic
local challenge_logic
local friend_logic
local chat_logic
local task_logic
local achievement_logic
local guide_logic
local rank_logic
local pve_logic

local cdkey_logic

local meta = {}

-- 初始化
function meta:Init(user_id, reconnect_token, account_name)

    -- 初始化基本数据
    self.user_id = user_id
    self.reconnect_token = reconnect_token
    self.account_name = account_name

    analytics_manager:SetUserId(user_id)

    self.name = ""
    self.level = 1
    self.exp = 0
    self.create_time = 0
    -- 初始化模块
    resource_logic = require "logic.resource"
    resource_logic:Init()

    -- 初始化卡组模块
    deck_logic = require "logic.deck"
    deck_logic:Init()

    -- 初始化竞技场模块
    arena_logic = require "logic.arena"
    arena_logic:Init()

    -- 初始化宝箱模块
    chest_logic = require "logic.chest"
    chest_logic:Init()

    -- 初始化邮件模块
    mail_logic = require "logic.mail"
    mail_logic:Init()

    -- 初始化日常模块
    daily_logic = require "logic.daily"
    daily_logic:Init()

    --初始化约战模块
    challenge_logic = require "logic.challenge"
    challenge_logic:Init()

    --初始化排行榜模块
    rank_logic = require "logic.rank"
    rank_logic:Init()

    --好友模块
    friend_logic = require "logic.friend"
    friend_logic:Init()

    --初始化聊天模版
    chat_logic = require "logic.chat"
    chat_logic:Init()

    -- 任务
    task_logic = require "logic.task"
    task_logic:Init()

    -- 成就
    achievement_logic = require "logic.achievement"
    achievement_logic:Init()

    --初始化PVE模板
    pve_logic = require "logic.pve"
    pve_logic:Init()

    --初始化兑换礼品码
    cdkey_logic = require "logic.cdkey"
    cdkey_logic:Init()

    --引导系统初始化
    guide_logic = require "logic.guide"
    guide_logic:Init()

    self:RegisterMsgHandler()
end

function meta:Update(elapsed_time)
    daily_logic:Update(elapsed_time)
    task_logic:Update(elapsed_time)
    pve_logic:Update(elapsed_time)
    guide_logic:Update(elapsed_time)
    arena_logic:Update(elapsed_time)
end

function meta:DoLogout()
    network:Clear()
    global:ChangeScene("login")
end

function meta:SetNofiyPlan()

    -- test code
    -- local next_refresh_chest = timer:Now() + 10
    local next_refresh_chest = arena_logic.next_refresh_chest

    local now_time = math.floor(timer:Now())
    local nofiy_time = next_refresh_chest - now_time

    local nofiyContext = text_loader:GetText("nofiy_refresh_time_desc")
    global:PushNofiyMessage(nofiy_time, nofiyContext)

end

function meta:QueryBaseInfo(compleate_func, error_func)
    network:Send("query_base_info", function (result, recv_msg)
        print("query_base_info")
        if result == "success" then
            self.name = recv_msg.name
            analytics_manager:SetUserName(self.name)
            self.level = recv_msg.level
            analytics_manager:SetArenaLevel(self.level)
            self.exp = recv_msg.exp
            self.cup_num = recv_msg.cup_num
            self.create_time = recv_msg.create_time
            self.last_exp = self.exp
            self.last_level = self.level
            compleate_func()
        else
            error_func(result)
        end
    end)
end

function meta:QueryOverviewInfo(compleate_func, error_func)
    network:Send("query_overview_info", function (result, recv_msg)
        print("query_overview_info", tostring(recv_msg))
        recv_msg = recv_msg or {}
        if result == "success" then
            mail_logic:SetNewMailNum(recv_msg.new_mail_num)
            self.battle_replay_id = recv_msg.battle_id
            self.room_number = recv_msg.room_number
            self.task_hint = recv_msg.task_hint
            self.achi_hint = recv_msg.achi_hint
            compleate_func()
        else
            error_func(result)
        end
    end)
end

-- 注册网络事件
function meta:RegisterMsgHandler()

    -- 同步熟练度
    network:RegisterCommand("cmd_update_proficient",function (recv_msg)
        self.last_exp = self.exp
        self.last_level = self.level
        self.level = recv_msg.level
        self.exp = recv_msg.exp
        graphic:DispatchEvent("update_exp_value", self.level, self.exp)
        analytics_manager:SetArenaLevel(self.level)
    end)

    -- 时间同步
    network:RegisterCommand("cmd_sync_time",function (recv_msg)
        timer:SyncTime(recv_msg.server_time, recv_msg.time_zone)
    end)

    -- 服务器状态同步
    network:RegisterCommand("cmd_server_status", function (recv_msg)
        global.server_status = global.server_status or {}
        local online_num = recv_msg.online_num
        if online_num then
            global.server_status.online_num = online_num
            graphic:DispatchEvent("update_online_value", online_num)
        end
    end)
end

return meta
