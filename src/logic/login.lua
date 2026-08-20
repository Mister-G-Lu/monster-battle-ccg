local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"
local text_loader = require "manager.text_loader"
local timer = require "manager.time"
local user_logic = require "logic.user"
local resource_logic = require "logic.resource"
local deck_logic = require "logic.deck"
local chest_logic = require "logic.chest"
local arena_logic = require "logic.arena"
local daily_logic = require "logic.daily"
local challenge_logic = require "logic.challenge"
local pve_logic = require"logic.pve"
local platform_manager = require "logic.platform_manager"
local config = require "manager.configuration"
local data_manager = require "manager.data_template"

local meta = {}

-- 状态
meta.STAGE = {
    init     = 1,       -- 初始化界面
    wait     = 2,       -- 等待操作
    passprot = 3,       -- 登陆界面
    loading  = 4,       -- 加载界面
    complete = 5,       -- 加载完毕，进入游戏世界
}

meta.singin_type = {
    GUEST = 1,
    WECHAT = 2,
    QQ =  3,
    FACEBOOK = 4,
    GOOGLE = 5,
    GAMECENTER = 6,
}

meta.locale_list = {
    [cc.LANGUAGE_ENGLISH] = "en-US",
    [cc.LANGUAGE_CHINESE] = "zh-CN",
}

meta.bandingEntrance = 1  -- 1为登录面板 2为设置面板

local IMG_TASK_LIST =
{
    { "atlas/ui.png", "atlas/ui.plist" },
    { "atlas/main.png", "atlas/main.plist" },
    { "atlas/card.png", "atlas/card.plist" },
}

-- 初始化
function meta:Init()
    platform_manager:Init()
    self:InitLoadingProgress()
    self:RegisterMsgHandler()
end

function meta:DoEnterGame()
    print("[LOGIN] DoEnterGame() called")

    local TARGET_PLATFORM = cc.Application:getInstance():getTargetPlatform()

    -- 海外服务器
    local server_ip = "game.mu77.com"

    if TARGET_PLATFORM == cc.PLATFORM_OS_MAC or TARGET_PLATFORM == cc.PLATFORM_OS_WINDOWS then
        -- server_ip = "127.0.0.1"
        -- 内网测试服
        -- server_ip = "106.75.62.40"
        -- server_ip = "192.168.199.97"
    end
    -- 内网服务器
    -- server_ip = "106.75.62.40"

    print("server_ip = "..server_ip)
    local err, status = network:Connect(server_ip, 28800) -- 外网测试
    if err then
        print (err)
    end
    if status == 1 then
        graphic:DispatchEvent("show_message","lost_connection")
        return
    end

    graphic:DispatchEvent("switch_login_stage", self.STAGE.loading)
end

-- 加载完毕进入游戏世界
function meta:DoLoadingComplete()
    print("[LOGIN] DoLoadingComplete() called")
    global:ChangeScene("world")

    if user_logic.room_number then
       challenge_logic:ReconnectRoom()
    end

    local guide_logic = require "logic.guide"
    if not guide_logic:CheckNewGuide() then
        if user_logic.battle_replay_id then
            local battle_logic = require "logic.battle"
            battle_logic:ReqReplay()
            print("有战斗还在进行", user_logic.battle_replay_id, "开始进行重回战局")
        end
    end

end

-- 初始化加载数据信息
function meta:InitLoadingProgress()
    self.loading_progress_func = {}

    local texture_cache = cc.Director:getInstance():getTextureCache()

    -- 加载图片缓存数据
    for i = 1, #IMG_TASK_LIST do
        self:AddAsyncLoadingProgress(function (compleate_callback, _)
            local img = IMG_TASK_LIST[i][1]
            local plist = IMG_TASK_LIST[i][2]
            texture_cache:addImageAsync(img, function(_)
                cc.SpriteFrameCache:getInstance():addSpriteFrames(plist)
                compleate_callback()
            end)
        end)
    end

    -- 加载用户数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        user_logic:QueryBaseInfo(compleate_callback, error_callback)
    end)

    -- 加载资源数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        resource_logic:Query(compleate_callback, error_callback)
    end)

    -- 加载卡组信息
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        deck_logic:QueryDeckInfo(compleate_callback, error_callback)
    end)
    -- 加载卡牌信息
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        deck_logic:QueryCardInfo(compleate_callback, error_callback)
    end)

    -- 加载宝箱数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        chest_logic:Query(compleate_callback, error_callback)
    end)

    -- 加载竞技场数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        arena_logic:Query(compleate_callback, error_callback)
    end)

    -- 加载日常数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        daily_logic:Query(compleate_callback, error_callback)
    end)

    -- 加载用户概况数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        user_logic:QueryOverviewInfo(compleate_callback, error_callback)
    end)

    --加载PVE数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        pve_logic:RefreshCount(compleate_callback, error_callback)
    end)

    --登陆获取pve信息
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback )
        pve_logic:ReqPveInfoOnLogin(compleate_callback, error_callback)
    end)

    -- 加载任务数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        local task_logic = require "logic.task"
        task_logic:Query(compleate_callback, error_callback)
    end)

    -- 引导数据
    self:AddAsyncLoadingProgress(function (compleate_callback, error_callback)
        local guide_logic = require "logic.guide"
        guide_logic:Query(compleate_callback, error_callback)
    end)

end

function meta:AddAsyncLoadingProgress(executer)
    table.insert(self.loading_progress_func, executer)
end

-- 执行滚动条时间
function meta:DoAsyncLoadingProgress(callback)
    if self:HasAccountSysFlow() then     --账号整包进入游戏
        self:SendLoginReq(true, callback)
    else                                 --热更包 进入游戏
        self:SendLoginReq(false, callback)
    end
end

function meta:SendLoginReq(newPKGBool, callback)
    local req = {}
    local max_progress = #self.loading_progress_func
    local cur_progress = 1
    -- 失败回调
    local _error_callback = function ()
        graphic:DispatchEvent("switch_login_stage", self.STAGE.wait)
    end

    -- 重置会话状态
    if network["ResetSession"] then
        network:ResetSession()
    end

    -- 成功回调
    local _completa_callback = function ()
        cur_progress = cur_progress + 1
        callback((cur_progress - 1) / max_progress * 100)
    end

    local defalut_version = "1.4"

    if newPKGBool then
        --print("new account flow")
        req.name = config:GetUserId()
        req.token = config:GetSessionId()
        req.type = "mu77"
        req.channel = "debug"
        req.language = text_loader.cur_lang

        local client_version = config:GetVersion()
        if client_version then
            local major_ver, minor_ver, _ = string.match(client_version, "(%w+).(%w+).(%w+)")
            req.version = major_ver.."."..minor_ver
        else
            req.version = defalut_version
        end

        network:Send("req_login_game", req, function (result, recv_msg)
            if recv_msg then
                result = recv_msg.result or result
            end
            if result == "success" then
                config:SetUserId(recv_msg.user_id)
                config:Save()
                local server_time = recv_msg.server_time
                local time_zone = recv_msg.time_zone
                timer:SyncTime(server_time, time_zone)
                data_manager:SetCompleteEvent(function ()
                    user_logic:Init(recv_msg.user_id, recv_msg.reconnect_token, recv_msg.user_id)
                    for i = 1, max_progress do
                        local async_executer = self.loading_progress_func[i]
                        async_executer(_completa_callback, _error_callback)
                    end
                end)
            else
                graphic:DispatchEvent("show_message", result)
                graphic:DispatchEvent("switch_login_stage", self.STAGE.wait)
            end
        end)
    else
        --print("old account flow")
        local account_name, account_passwd
        if not config:HasAccount() then
            account_name = math.random(99999999)
            account_passwd = math.random(99999999)
            if TalkingDataGA then
                account_name = TalkingDataGA:getDeviceId()
                --print("getDeviceId = "..account_name)
            else
                config:SetAccountAndPwd(account_name, account_passwd)
            end
        else
            account_name, account_passwd = config:GetAccountAndPwd()
            --print("account_name>>>"..account_name)
        end

        req.name = account_name
        req.token = account_passwd
        req.type = "debug"
        req.channel = "debug"
        req.language = text_loader.cur_lang
        local client_version = config:GetVersion()
        if client_version then
            local major_ver, minor_ver, _ = string.match(client_version, "(%w+).(%w+).(%w+)")
            req.version = major_ver.."."..minor_ver
        else
            req.version = defalut_version
        end

        network:Send("req_login_game", req, function (result, recv_msg)
            if recv_msg then
                result = recv_msg.result or result
            end
            if result == "success" then
                config:SetUserId(recv_msg.user_id)
                config:Save()
                local server_time = recv_msg.server_time
                local time_zone = recv_msg.time_zone
                timer:SyncTime(server_time, time_zone)
                data_manager:SetCompleteEvent(function ()
                    user_logic:Init(recv_msg.user_id, recv_msg.reconnect_token, account_name)
                    for i = 1, max_progress do
                        local async_executer = self.loading_progress_func[i]
                        async_executer(_completa_callback, _error_callback)
                    end
                end)
            else
                graphic:DispatchEvent("show_message", result)
                graphic:DispatchEvent("switch_login_stage", self.STAGE.wait)
            end
        end)
    end
end

-- 注册网络事件
function meta:RegisterMsgHandler()
    network:RegisterCommand("cmd_player_logout",function (_)
        network:Clear()
        config:SetNeedShowLoginBtn(1)
        config:Save()
        global:ChangeScene("login")
    end)
end

function meta:RegisterLoginEvent()
    platform_manager:RegisterEvent("signin_result", function(status_code, arg2)
        if status_code == 0 then  -- start
            -- start
            -- TODO: 开始行为
        elseif status_code == 1 then    --success
            local platform = arg2.platform
            local openid = arg2.openid
            local access_token = arg2.access_token
            --发送给登录服  获取userId
            if self.bandingEntrance == 1 then
                --过期验证 不再接受
                local rScene = cc.Director:getInstance():getRunningScene()
                if rScene.schedulerID or config:GetUserId() == nil then
                    local mu77_account = require "logic.account.mu77_account"
                    mu77_account:SignIn(openid, access_token, platform)
                end
            else
                local rScene = cc.Director:getInstance():getRunningScene()
                if rScene then
                    local sub_panel = rScene:GetSubPanel("setting", "account_panel")
                    if sub_panel and sub_panel.schedulerID then
                        local mu77_account = require "logic.account.mu77_account"
                        mu77_account:BindAccount(openid, access_token, platform)
                    end
                end
            end
        elseif status_code == 2 then    -- failure
            if config:GetUserId() == nil then
                local mu77_account = require "logic.account.mu77_account"
                mu77_account:SignIn("", "", self.singin_type.GUEST)
                return
            end
            --还原面板按钮状态
            if self.bandingEntrance == 1 then
                graphic:DispatchEvent("signin_frame_state", 1)
            else
                graphic:DispatchEvent("signin_frame_state_setting", 1)
            end
            if arg2 and arg2 == self.singin_type.GAMECENTER and self.autoAuth == false then
                graphic:DispatchEvent("show_message", "account_bind_log_tips")
            end
        elseif status_code == 3 then    -- cancel
            if config:GetUserId() == nil then
                local mu77_account = require "logic.account.mu77_account"
                mu77_account:SignIn("", "", self.singin_type.GUEST)
                return
            end
            --还原面板按钮状态
            if self.bandingEntrance == 1 then
                graphic:DispatchEvent("signin_frame_state", 1)
            else
                graphic:DispatchEvent("signin_frame_state_setting", 1)
            end
            if arg2 and arg2 == self.singin_type.GAMECENTER and self.autoAuth == false then
                graphic:DispatchEvent("show_message", "account_bind_log_tips")
            end
        elseif status_code == 4 then    -- inprogress
            -- TODO: 改变文字  锁屏  显示 绑定中
        elseif status_code == 5 then    -- bind--error
            -- TODO: 绑定失败
        elseif status_code == 6 then    -- bind--success
            -- TODO: 绑定成功
        elseif status_code == 7 then    -- 请先安装
            -- TODO: 请先安装
            --print("请先安装")
            -- local platform = arg2.platform
            -- todo 提示玩家请先安装 对应平台
            if self.bandingEntrance == 1 then
                graphic:DispatchEvent("signin_frame_state", 1)
            else
                graphic:DispatchEvent("signin_frame_state_setting", 1)
            end
        end
    end)

    platform_manager:RegisterEvent("signout_result", function(status_code, arg2)
        --设置是否在登录面板显示多个按钮
        config:SetNeedShowLoginBtn(1)
        config:Save()
        local global_manager = require "manager.global"
        global_manager:Init()
        global_manager:ChangeScene("login")
    end)
end

function meta:GetPlatformNameByType(platform)
    local platformName = ""
    if platform == self.singin_type.GUEST then
        platformName = text_loader:GetText("account_bind_name_yk")
    elseif platform == self.singin_type.WECHAT then
        platformName = text_loader:GetText("account_bind_name_wc")
    elseif platform == self.singin_type.QQ then
        platformName = "QQ"
    elseif platform == self.singin_type.FACEBOOK then
        platformName = "Facebook"
    elseif platform == self.singin_type.GOOGLE then
        platformName = "Google Play"
    elseif platform == self.singin_type.GAMECENTER then
        platformName = "GameCenter"
    end
    return platformName
end

function meta:ResetAllBandedState()
    self:SetPlatformBanded(self.singin_type.WECHAT, 0)
    self:SetPlatformBanded(self.singin_type.QQ, 0)
    self:SetPlatformBanded(self.singin_type.FACEBOOK, 0)
    self:SetPlatformBanded(self.singin_type.GOOGLE, 0)
    self:SetPlatformBanded(self.singin_type.GAMECENTER, 0)
end

function meta:SetPlatformBanded(platform, banded)
    if platform == nil then
        platform = self.singin_type.GUEST
    end
    if platform == self.singin_type.WECHAT then
        config:SetWECHATIsBanded(banded)
    elseif platform == self.singin_type.QQ then
        config:SetQQIsBanded(banded)
    elseif platform == self.singin_type.FACEBOOK then
        config:SetFBIsBanded(banded)
    elseif platform == self.singin_type.GOOGLE then
        config:SetGGIsBanded(banded)
    elseif platform == self.singin_type.GAMECENTER then
        config:SetGCIsBanded(banded)
    end
end

function meta:HasAccountSysFlow()
    if ThirdHelper == nil or ThirdHelper["singIn"] == nil or ThirdHelper["singOut"] == nil then
        return false
    else
        return true
    end
end

return meta
