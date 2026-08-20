--local account = require "logic.account.prototype"
local configuration = require "manager.configuration"
local graphic = require "manager.graphic"
local platform_manager = require "logic.platform_manager"
local manager = require "manager.platform_manager"
local http_client = require "logic.http_client"
local json = require "utils.json"
local config = require "manager.configuration"
local user_logic = require "logic.user"
local text_loader = require "manager.text_loader"
local md5 = require "md5"

local mu77_account = {}
mu77_account.api_secret = "94fdB9SYWEQqaBA4hC3BhVwRiHs="
mu77_account.authAdd = "http://cm.mu77.com/webservice/auth.php";
mu77_account.bindAdd = "http://cm.mu77.com/webservice/bind.php";

function mu77_account:SignIn(openId, openToken, platform)
    -- OFFLINE MODE: skip HTTP auth, simulate guest login
    print("[MU77_ACCOUNT] SignIn called, OFFLINE_MODE=" .. tostring(OFFLINE_MODE))
    if OFFLINE_MODE then
        print("[MU77_ACCOUNT] OFFLINE PATH — bypassing HTTP auth")
        local config = require "manager.configuration"
        local user_logic = require "logic.user"
        local login_logic = require "logic.login"
        local data_manager = require "manager.data_template"

        -- Generate/load a user ID
        local userId = config:GetUserId()
        if userId == nil then
            userId = math.random(100000, 99999999)
            config:SetUserId(userId)
            config:SetSessionId(1)
            config:SetNeedShowLoginBtn(0)
            config:Save()
        end

        -- Initialize user logic
        user_logic:Init(userId, "offline_token", tostring(userId))

        -- Load data and enter the game
        print("[MU77_ACCOUNT] Setting CompleteEvent, calling DoEnterGame")
        data_manager:SetCompleteEvent(function()
            login_logic:DoEnterGame()
        end)
        return
    end

    local userId = config:GetUserId()
    if userId == nil then
        userId = 0
    end

    if platform == "" or platform == nil then
        platform = 1
    end

    local sessionId = config:GetSessionId()
    if sessionId == nil then
        sessionId = 0
    end

    --local post_data = {passport=openId, nickname="", platform=1, appType=0, channel=0, device_id=1, device_type=1, userId=userId}
    local post_dataStr = string.format("version=%s&passport=%s&platform=%s&user_id=%s&channel=%s&appType=%s&device_id=%s&device_type=%s&sessionId=%s",
        config:GetVersion(), openId, platform, userId, manager:GetChannelName(), platform_manager:getPlatformType(), ThirdHelper["getDeviceId"](), ThirdHelper["getMoblieDeviceName"](), sessionId)
    --http_client:Post(self.account_server, json:encode(post_data), function(status_code, content)
    local md5str = (string.gsub(md5.sum(post_dataStr..mu77_account.api_secret), ".", function (c)
                        return string.format("%02x", string.byte(c))
                    end))
    local post_dataStr_res = post_dataStr.."&md5key="..md5str

    local time = os.time()
    local xhr = cc.XMLHttpRequest:new()
    local reqTimes = 0
    xhr.responseType = cc.XMLHTTPREQUEST_RESPONSE_JSON
    xhr:open("POST", mu77_account.authAdd)
    print("post_dataStr_res = ", post_dataStr_res)
    local function onReadyStateChanged()
        print("xhr.status = ", xhr.status, xhr.readyState)
        if xhr.status ~= 200 then
            if reqTimes < 3 then
                xhr:send(post_dataStr_res)
                reqTimes = reqTimes + 1
                return
            end
            local cur_scene = cc.Director:getInstance():getRunningScene()
            local confirm_box = cur_scene:getChildByName("acc_confirm_box")
            if confirm_box then
                return
            end
            confirm_box = require("modules.common.confirm_box").new()
            local title = text_loader:GetText("network_unable_connect_title")
            local desc = text_loader:GetText("network_unable_connect")
            local confirm_txt = text_loader:GetText("network_unable_connect_confirm")
            local cancel_text = text_loader:GetText("network_unable_connect_close")
            confirm_box:ShowConfirm(title, desc, confirm_txt, cancel_text, 
                function()
                    cur_scene:removeChild(confirm_box)
                    xhr:send(post_dataStr_res)
                end,
                function()
                   cc.Director:getInstance():endToLua()
                end)
            cur_scene:addChild(confirm_box, 99999, "acc_confirm_box")
            return
        else
            local cur_scene = cc.Director:getInstance():getRunningScene()
            local confirm_box = cur_scene:getChildByName("acc_confirm_box")
            if confirm_box then
                cur_scene:removeChild(confirm_box)
            end
            print("time = ", (os.time() - time))
            local response = xhr.response
            local ret_msg = json:decode(response)
            if ret_msg.result ~= 0 or ret_msg.errmsg ~= "" or ret_msg.user_id == nil then
                --TODO: show account request error
                --print("ret_msg.errmsg:"..ret_msg.errmsg)
                return
            end

            --save id locally
            local login_logic = require "logic.login"
            self:SetAllBandedPlatform(ret_msg.binds)
            config:SetUserId(ret_msg.user_id)
            config:SetSessionId(ret_msg.session_id)
            config:SetNeedShowLoginBtn(0)
            config:Save()
            user_logic:Init(ret_msg.user_id, "", "")
            --enter game
            login_logic:DoEnterGame()
        end
        xhr:unregisterScriptHandler()
    end
    xhr:registerScriptHandler(onReadyStateChanged)
    xhr:send(post_dataStr_res)

    -- --print("authAdd"..mu77_account.authAdd..post_dataStr_res)

    -- local callback = function  (status_code, content)
    --     if status_code ~= 200 then
    --         --TODO: network error prompt
    --         --print("errmsg status_code"..status_code)
    --         http_client:Post(mu77_account.authAdd, post_dataStr_res, callback)
    --         return
    --     end
    --     --print("auth--content"..content)
    --     local ret_msg = json:decode(content)
    --     if ret_msg.result ~= 0 or ret_msg.errmsg ~= "" or ret_msg.user_id == nil then
    --         --TODO: show account request error
    --         --print("ret_msg.errmsg:"..ret_msg.errmsg)
    --         return
    --     end
    --
    --     --save id locally
    --     local login_logic = require "logic.login"
    --     self:SetAllBandedPlatform(ret_msg.binds)
    --     config:SetUserId(ret_msg.user_id)
    --     config:SetSessionId(ret_msg.session_id)
    --     config:SetNeedShowLoginBtn(0)
    --     config:Save()
    --     user_logic:Init(ret_msg.user_id, "", "")
    --     --enter game
    --     login_logic:DoEnterGame()
    -- end
    -- http_client:Post(mu77_account.authAdd, post_dataStr_res, callback)
end

function mu77_account:BindAccount(openId, openToken, platform)
    local userId = config:GetUserId()
    if userId == nil then
        return
    end
    local sessionId = config:GetSessionId()
    if sessionId == nil then
        sessionId = 0
    end
    local post_data = {passport = openId, user_id = userId, appType = 0, channel = 0}
    post_dataStr = string.format("passport=%s&user_id=%s&platform=%s&channel=%s&sessionId=%s", openId, userId, platform, manager:GetChannelName(), sessionId)
    local md5str = (string.gsub(md5.sum(post_dataStr..mu77_account.api_secret), ".", function (c)
                        return string.format("%02x", string.byte(c))
                    end))
    local post_dataStr_res = post_dataStr.."&md5key="..md5str
        local time = os.time()
        local xhr = cc.XMLHttpRequest:new()
        local reqTimes = 0
        xhr.responseType = cc.XMLHTTPREQUEST_RESPONSE_JSON
        xhr:open("POST", mu77_account.bindAdd)
        print("post_dataStr_res = ", post_dataStr_res)
        local function onReadyStateChanged()
            print("xhr.status = ", xhr.status, xhr.readyState)
            if xhr.status ~= 200 then
                if reqTimes < 3 then
                    xhr:send(post_dataStr_res)
                    reqTimes = reqTimes + 1
                    return
                end
                local cur_scene = cc.Director:getInstance():getRunningScene()
                local confirm_box = cur_scene:getChildByName("acc_confirm_box")
                if confirm_box then
                    return
                end
                confirm_box = require("modules.common.confirm_box").new()
                local title = text_loader:GetText("network_unable_connect_title")
                local desc = text_loader:GetText("network_unable_connect")
                local confirm_txt = text_loader:GetText("network_unable_connect_confirm")
                local cancel_text = text_loader:GetText("network_unable_connect_close")
                confirm_box:ShowConfirm(title, desc, confirm_txt, cancel_text, 
                    function()
                        cur_scene:removeChild(confirm_box)
                        xhr:send(post_dataStr_res)
                    end,
                    function()
                       cc.Director:getInstance():endToLua()
                    end)
                cur_scene:addChild(confirm_box, 99999, "acc_confirm_box")
                return
            else
                local cur_scene = cc.Director:getInstance():getRunningScene()
                if cur_scene then
                    local confirm_box = cur_scene:getChildByName("acc_confirm_box")
                    if confirm_box then
                        cur_scene:removeChild(confirm_box)
                    end
                end
                print("time = ", (os.time() - time))
                local response = xhr.response
                local ret_msg = json:decode(response)
                if ret_msg.result ~= 0 or ret_msg.errmsg ~= "" then
                    --TODO: show account request error
                    --print("ret_msg.errmsg:"..ret_msg.errmsg)
                    return
                end

                local login_logic = require "logic.login"
                --hide panel
                if cur_scene then
                    local sub_panel = cur_scene:GetSubPanel("setting", "account_panel")
                    if sub_panel and sub_panel.schedulerID then
                        sub_panel:setVisible(false)
                    end
                end

                --print("ret_msg"..content)
                if ret_msg.user_id ~= nil and userId ~= ret_msg.user_id then
                    --platform account already bound; let the player choose
                    local confirm_box = require("modules.common.confirm_box").new()
                    local title_txt = text_loader:GetText("account_bind_name_bd", login_logic:GetPlatformNameByType(platform))
                    local desc_txt = text_loader:GetText("account_bind_alert", login_logic:GetPlatformNameByType(platform))
                    local confirm_txt = text_loader:GetText("common_confirm")
                    local cancel_txt = text_loader:GetText("common_cancel")
                    confirm_box:ShowConfirm(title_txt, desc_txt, confirm_txt, cancel_txt,
                        function ()
                            local login_logic = require "logic.login"
                            self:SetAllBandedPlatform(ret_msg.binds)
                            config:SetUserId(ret_msg.user_id)
                            config:SetSessionId(ret_msg.session_id)
                            config:SetNeedShowLoginBtn(0)
                            config:Save()
                            --reload
                            local global_manager = require "manager.global"
                            global_manager:Init()
                            global_manager:ChangeScene("login")
                        end,
                        function ()
                            graphic:DispatchEvent("signin_frame_state_setting", 1)
                            cur_scene:removeChild(confirm_box)
                            --show panel
                            local sub_panel = cur_scene:GetSubPanel("setting", "account_panel")
                            if sub_panel then
                                sub_panel:setVisible(true)
                            end
                        end
                    )
                    cur_scene:addChild(confirm_box, 99999)
                    return
                end

                self:SetAllBandedPlatform(ret_msg.binds)
                config:SetNeedShowLoginBtn(0)
                config:SetSessionId(ret_msg.session_id)
                config:Save()

                --notify bind success
                local confirm_box = require("modules.common.confirm_box").new()
                local title = text_loader:GetText("account_bind_name_bd", login_logic:GetPlatformNameByType(platform))
                local desc = text_loader:GetText("account_bind_success_t", login_logic:GetPlatformNameByType(platform))
                local confirm_txt = text_loader:GetText("common_confirm")
                confirm_box:ShowNofity(title, desc,confirm_txt, function()
                    graphic:DispatchEvent("signin_frame_state_setting", 1)
                        cur_scene:removeChild(confirm_box)
                        --show panel
                        if cur_scene then
                            local sub_panel = cur_scene:GetSubPanel("setting", "account_panel")
                            if sub_panel then
                                sub_panel:setVisible(true)
                            end
                        end
                end)
                cur_scene:addChild(confirm_box, 99999)
            end
            xhr:unregisterScriptHandler()
        end
        xhr:registerScriptHandler(onReadyStateChanged)
        xhr:send(post_dataStr_res)


    -- --print("bindAdd"..mu77_account.bindAdd..post_dataStr_res)
    -- http_client:Post(mu77_account.bindAdd, post_dataStr_res, function(status_code, content)
    --     --print("bind--content"..content)
    --     local login_logic = require "logic.login"
    --     local cur_scene = cc.Director:getInstance():getRunningScene()
    --     local ret_msg = json:decode(content)
    --      if status_code ~= 200 then
    --         --TODO: network error prompt
    --         --print("errmsg status_code"..status_code)
    --         return
    --     end
    --     if ret_msg.result ~= 0 or ret_msg.errmsg ~= "" then
    --         --TODO: account error prompt
    --         --print("ret_msg.errmsg:"..ret_msg.errmsg)
    --         return
    --     end
    --
    --     --hide panel
    --     if cur_scene then
    --         local sub_panel = cur_scene:GetSubPanel("setting", "account_panel")
    --         if sub_panel and sub_panel.schedulerID then
    --             sub_panel:setVisible(false)
    --         end
    --     end
    --
    --     --print("ret_msg"..content)
    --     if ret_msg.user_id ~= nil and userId ~= ret_msg.user_id then
    --         --platform account already bound; let the player choose
    --         local confirm_box = require("modules.common.confirm_box").new()
    --         local title_txt = text_loader:GetText("account_bind_name_bd", login_logic:GetPlatformNameByType(platform))
    --         local desc_txt = text_loader:GetText("account_bind_alert", login_logic:GetPlatformNameByType(platform))
    --         local confirm_txt = text_loader:GetText("common_confirm")
    --         local cancel_txt = text_loader:GetText("common_cancel")
    --         confirm_box:ShowConfirm(title_txt, desc_txt, confirm_txt, cancel_txt,
    --             function ()
    --                 local login_logic = require "logic.login"
    --                 self:SetAllBandedPlatform(ret_msg.binds)
    --                 config:SetUserId(ret_msg.user_id)
    --                 config:SetSessionId(ret_msg.session_id)
    --                 config:SetNeedShowLoginBtn(0)
    --                 config:Save()
    --                 --reload
    --                 local global_manager = require "manager.global"
    --                 global_manager:Init()
    --                 global_manager:ChangeScene("login")
    --             end,
    --             function ()
    --                 graphic:DispatchEvent("signin_frame_state_setting", 1)
    --                 cur_scene:removeChild(confirm_box)
    --                 --show panel
    --                 local sub_panel = cur_scene:GetSubPanel("setting", "account_panel")
    --                 if sub_panel then
    --                     sub_panel:setVisible(true)
    --                 end
    --             end
    --         )
    --         cur_scene:addChild(confirm_box, 99999)
    --         return
    --     end
    --
    --     self:SetAllBandedPlatform(ret_msg.binds)
    --     config:SetNeedShowLoginBtn(0)
    --     config:SetSessionId(ret_msg.session_id)
    --     config:Save()
    --
    --     --notify bind success
    --     local confirm_box = require("modules.common.confirm_box").new()
    --     local title = text_loader:GetText("account_bind_name_bd", login_logic:GetPlatformNameByType(platform))
    --     local desc = text_loader:GetText("account_bind_success_t", login_logic:GetPlatformNameByType(platform))
    --     local confirm_txt = text_loader:GetText("common_confirm")
    --     confirm_box:ShowNofity(title, desc,confirm_txt, function()
    --         graphic:DispatchEvent("signin_frame_state_setting", 1)
    --             cur_scene:removeChild(confirm_box)
    --             --show panel
    --             if cur_scene then
    --                 local sub_panel = cur_scene:GetSubPanel("setting", "account_panel")
    --                 if sub_panel then
    --                     sub_panel:setVisible(true)
    --                 end
    --             end
    --     end)
    --     cur_scene:addChild(confirm_box, 99999)
    -- end)





end

function mu77_account:SetAllBandedPlatform(bindedList)
    local login_logic = require "logic.login"
    login_logic:ResetAllBandedState()
    if bindedList then
        for k,v in pairs(bindedList) do
            login_logic:SetPlatformBanded(tonumber(v), 1)
        end
    end
end

return mu77_account
