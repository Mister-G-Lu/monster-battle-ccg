local graphic_manager
local action_manager
local time_manager
local network
local error_tracer

local meta = {}

local _moudle_list = {
    "login",
    "battle",
}

local director = cc.Director:getInstance()

-- Top-most message overlay
local MESSAGE_TIPS_ZORDER = 9000
local MAX_RECONNECT_NUM = 3

function meta:Init()
    print("[GLOBAL] Init() START")
    if self.initd then
        return true
    end

    require "common.ext.init"

    self.current_scene_name = ""
    self.server_status = {}

    self.reconnect_num = 0
    self.is_reconnect = false
    self.reconnect_time = 0

    -- pre-cache battle scene
    self.battle_scene_cache = nil
    self.is_waring = false
    math.randseed()

    action_manager = require "manager.action_manager"
    action_manager:Init()

    local director = cc.Director:getInstance()
    graphic_manager = require "manager.graphic"
    graphic_manager:Init()

    local audio_manager = require "manager.audio_manager"
    audio_manager:Init()

    local platform_manager = require "manager.platform_manager"
    platform_manager:Init()

    time_manager = require "manager.time"
    time_manager:Init()

    network = require "manager.network"
    network:Init()
    network:RegisterProto()

    local config = require "manager.configuration"
    config:Init()

    local text_loader = require "manager.text_loader"
    text_loader:Init()

    local data_template = require "manager.data_template"
    data_template:Init()

    self:InitAllModules()

    self.tips_layer = require("modules.common.tips_panel").new()
    self.tips_layer:retain()

    local error_tracer = require "manager.error_tracer"
    error_tracer:SetUpdateDelay(3)

    self.defines = require "manager.defines"

    data_template:LoadFromCSV()
    self.schedule_id = director:getScheduler():scheduleScriptFunc(function(elapsed_time)
        -- data tables
        data_template:LoadFromCSV()
        --  update time
        time_manager:Update(elapsed_time)
        --  network
        network:Update(elapsed_time)
        -- actions
        action_manager:Update(elapsed_time)

        error_tracer:Update(elapsed_time)

        -- if connection is lost, return to lobby
        if network:HasLostConnection() then
            if self.resume_network then
                local err = network:Reconnect()
                self.reconnect_time = time_manager:Now()
                if not err then
                    -- after silent reconnect in battle, auto-sync
                    self:SendReconnectGame(function (result)
                        if result == "success" then
                            if self.current_scene_name == "battle" then
                                local battle_logic = require "logic.battle"
                                battle_logic:ReqSyncBattlefield()
                            end
                        else
                            -- silent reconnect failed; prompt the player
                            self:DoNetworkFail()
                        end
                        self.reconnect_num = 0
                        self.reconnect_time = 0
                        self.is_reconnect = false
                    end)
                else
                    network:ResetTryConnection()
                end
                self.resume_network = false
            else
                graphic_manager:DispatchEvent("show_message","lost_connection")
                self:DoNetworkFail()
            end
        else
            local scene = director:getRunningScene()
            if scene then
                if scene.__name == "battle" or scene.__name == "world" then
                    self:CheckReconnect()
                    --warn on poor network
                    self:NetworkWarning(scene, elapsed_time)
                end
                if scene.Update then
                    scene:Update(elapsed_time)
                end
            end
        end



        if self.tips_layer and self.tips_layer["Update"] then
            self.tips_layer:Update(elapsed_time)
        end
    end, 0, false)

    if ThirdHelper and ThirdHelper["registerLuaHandler"] then
        ThirdHelper["registerLuaHandler"](function (event_name, ...)
        end)
    end

    self.initd = true
end

--Warn when the network is poor
function meta:NetworkWarning(scene, elapsed_time)
    local deily_time = network:GetPingTimer()
    local waring_panel = scene.waring_panel
    if waring_panel then        --current ping exceeds max
        if deily_time >= self.defines.NET_WORK_DAILY_TIME and self.is_waring == false then
            waring_panel:Show()
            self.is_waring = true
        elseif deily_time < self.defines.NET_WORK_DAILY_TIME and self.is_waring == true then
            waring_panel:Hide()
            self.is_waring = false
        end
    end
end

-- App backgrounded
function meta:PauseBackground()
    if not self.initd then
        return
    end
    self.pause_time = os.time()
    graphic_manager:DispatchEvent("pause_back_ground")

    if self.current_scene_name == "world" then
        -- schedule local notifications
        local user_logic = require "logic.user"
        user_logic:SetNofiyPlan()

    elseif self.current_scene_name == "battle" then
        -- schedule local notifications
        local user_logic = require "logic.user"
        user_logic:SetNofiyPlan()
    end
end

-- App resumed
function meta:ResumeBackground()
    if not self.initd then
        return
    end
    if self.pause_time then
        local diff_time = os.time() - self.pause_time
        time_manager:Update(diff_time)
    end
    self.resume_network = true
    graphic_manager:DispatchEvent("resume_back_ground")
    -- force-sync server time
    network:Send("req_sync_time", { client_time = os.time() }, function (result, recv_msg)
        if not recv_msg then
            return
        end
        local server_time = recv_msg.server_time
        local time_zone = recv_msg.time_zone
        time_manager:SyncTime(server_time, time_zone)
    end)
    if self.current_scene_name == "world" then
    elseif self.current_scene_name == "battle" then
    end
end

-- Show reconnect dialog
function meta:TakeReconnectNetwork(success_callback, fail_callback)
    if self.take_recent_status then
        return
    end
    local cur_scene = cc.Director:getInstance():getRunningScene()
    local text_loader = require "manager.text_loader"
    local confirm_box = require("modules.common.confirm_box").new()
    cur_scene:addChild(confirm_box, MESSAGE_TIPS_ZORDER)
    self.take_recent_status = true

    local cancel_callback = function ()
        self.reconnect_num = 0
        self.reconnect_time = 0
        self.is_reconnect = false
        cur_scene:removeChild(confirm_box)
        network:Clear()
        self:ChangeScene("login")
        self.take_recent_status = false
    end

    local ok_callback = function ()
        self.take_recent_status = false
        local err = network:Reconnect()
        self.reconnect_time = time_manager:Now()
        if not err then
            cur_scene:removeChild(confirm_box)

            self:SendReconnectGame(function (result)
                if result == "success" then
                    if success_callback then success_callback() end
                else
                    if fail_callback then fail_callback() end
                end
                self.reconnect_num = 0
                self.reconnect_time = 0
                self.is_reconnect = false
            end)
        else
            confirm_box:Hide(function ()
                cur_scene:removeChild(confirm_box)
                self:DoNetworkFail()
            end)
        end
    end

    local title_txt = text_loader:GetText("network_unable_connect_title")
    local desc_txt = text_loader:GetText("network_unable_connect")
    local confirm_txt = text_loader:GetText("network_unable_connect_confirm")
    local cancel_txt = text_loader:GetText("network_unable_connect_login")
    confirm_box:ShowConfirm(title_txt, desc_txt, confirm_txt, cancel_txt, ok_callback, cancel_callback)
end

-- Reconnect failed
function meta:DoNetworkFail()
    if self.current_scene_name == "world" then
        -- in world: show reconnect dialog
        local success_callback = function ()
            print("success_callback>>world")
        end
        local fail_callback = function ()
            print("fail_callback")
            network:Clear()
            self:ChangeScene("login")
        end
        self:TakeReconnectNetwork(success_callback, fail_callback)
    elseif self.current_scene_name == "battle" then
        -- in battle: show reconnect dialog
        local success_callback = function ()
            print("success_callback>>battle")
            -- sync battle and replay on the client
            local battle_logic = require "logic.battle"
            battle_logic:ReqSyncBattlefield()
        end
        local fail_callback = function ()
            print("fail_callback")
            network:Clear()
            self:ChangeScene("login")
        end
        self:TakeReconnectNetwork(success_callback, fail_callback)
    else
        network:Clear()
        self:ChangeScene("login")
        graphic_manager:DispatchEvent("switch_login_stage", 1)
    end

end

-- Check connection
function meta:CheckReconnect()
    local cur_time = time_manager:Now()
    if self.is_reconnect then
        --no server response after timeout
        if (cur_time - self.reconnect_time) > MAX_RECONNECT_NUM then
            self:DoNetworkFail()
        end
        return
    end
    network:HeartBeat()
    if not network:HasTryConnection() then
        -- return if still connected
        return
    end

    if self.reconnect_num >= MAX_RECONNECT_NUM then
        self:DoNetworkFail()
        return
    end

    if self.reconnect_time == 0  or cur_time > (self.reconnect_time + 1) then
        --auto reconnect
        self:DoReconnect()
    end
end


-- Send reconnect request
function meta:SendReconnectGame(callback)
    self.is_reconnect = true
    local user_logic = require "logic.user"

    local req_data = {}
    req_data["user_id"] = user_logic.user_id
    req_data["token"] = user_logic.reconnect_token
    req_data["name"] = user_logic.user_id

    local configuration = require "manager.configuration"
    local client_version = configuration:GetVersion()
    if client_version then
        local major_ver, minor_ver, fix_ver = string.match(client_version, "(%w+).(%w+).(%w+)")
        req_data["version"] = major_ver.."."..minor_ver
    else
        req_data["version"] = "dev"
    end

    network:Send("req_reconnect_game", req_data, function (result, recv_msg)
        if result == "success" then
            self.reconnect_num = 0
            self.reconnect_time = 0
            user_logic.reconnect_token = recv_msg.reconnect_token
            time_manager:SyncServerTiem(recv_msg.server_time)
            network:SendRecordMsg()
        end
        self.is_reconnect = false
        if callback then
            callback(result)
        end
    end)
end

-- Perform reconnect
function meta:DoReconnect()
    local cur_time = time_manager:Now()
    self.reconnect_num = self.reconnect_num + 1

    local err = network:Reconnect()
    self.reconnect_time = cur_time
    if not err then
        self:SendReconnectGame()
    else
        if self.reconnect_num >= MAX_RECONNECT_NUM then
            self:DoNetworkFail()
        else
            self.is_reconnect = false
            network:ResetTryConnection()
        end
    end
end


--Init all modules
function meta:InitAllModules()
    for key, var in pairs(_moudle_list) do
        local logic = require("logic."..var)
        if logic then
            logic:Init()
        end
    end
end
function meta:CleanAllModules()
    for key, var in pairs(_moudle_list) do
        package.loaded["logic."..var] = nil
    end
end

function meta:ChangeScene(scene_name, ...)
    if self.current_scene_name == scene_name then
        return
    end

    if scene_name ~= "battle" and network["SetHeartBeatDelay"] then
        network:SetHeartBeatDelay(15)
    end

    graphic_manager:BindEventListener()

    local scene = require("scenes." .. scene_name .. "_scene").new(...)
    scene.__name = scene_name
    self.current_scene_name = scene_name

    scene:registerScriptHandler(function(event)
        if event == "enter" then
            scene.__name = scene_name
            self.current_scene_name = scene_name
            self.tips_layer:removeFromParent()
            scene:addChild(self.tips_layer, MESSAGE_TIPS_ZORDER)
            if scene["OnEnter"] then
                scene:OnEnter()
            end
        elseif event == "exit" then
            if scene["OnExit"] then
                scene:OnExit()
            end
        end
    end)

    director:popToRootScene()
    director:getOpenGLView():setIMEKeyboardState(false)
    director:replaceScene(scene)

    if self.battle_scene_cache then
        self.battle_scene_cache:release()
        self.battle_scene_cache = nil
    end
    return scene
end

function meta:GetCurrentSceneName()
    return self.current_scene_name
end

-- Preload battle scene
function meta:PreviouslyBattleScene()
    -- self.battle_scene_cache = require("scenes.battle_scene").new()
    -- self.battle_scene_cache:retain()
end

function meta:PushScene(scene_name)
    local scene = nil
    if scene_name == "battle" then
        -- scene = self.battle_scene_cache
        if network["SetHeartBeatDelay"] then
            network:SetHeartBeatDelay(2)
        end
    end
    if scene == nil then
        scene = require("scenes." .. scene_name .. "_scene").new()
        scene:registerScriptHandler(function(event)
            if event == "enter" then
                scene.__name = scene_name
                self.current_scene_name = scene_name
                self.tips_layer:removeFromParent()
                scene:addChild(self.tips_layer, MESSAGE_TIPS_ZORDER)
                if scene["OnEnter"] then
                    scene:OnEnter()
                end
            elseif event == "exit" then
                if scene["OnExit"] then
                    scene:OnExit()
                end
            end
        end)
    end



    -- director:purgeCachedData()
    director:pushScene(scene)
end

function meta:PopScene()
    if self.current_scene_name == "battle" and self.battle_scene_cache then
        self.battle_scene_cache:release()
        self.battle_scene_cache = nil
    end
    director:popScene()
    -- director:purgeCachedData()
end

function meta:Clear()
    self:CleanAllModules()
    if self.schedule_id then
        cc.Director:getInstance():getScheduler():unscheduleScriptEntry(self.schedule_id)
    end
end

function meta:PushNofiyMessage(time, text)
    if aandm.pushNofiyMessage then
        aandm.pushNofiyMessage(math.floor(time), text)
    end
end


return meta
