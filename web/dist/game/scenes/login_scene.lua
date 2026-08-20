local function dbg(msg) print("[LOGIN_SCENE] " .. tostring(msg)) end

local ui_helper = require "manager.ui_helper"

local graphic = require "manager.graphic"

local login_logic = require "logic.login"

local data_template = require "manager.data_template"

local text_loader = require "manager.text_loader"

local configuration = require "manager.configuration"

local resource = require "manager.resource"

local platform_manager = require "logic.platform_manager"



local meta = class("login_scene",function ()

    return cc.Scene:create()

end)



-- Stage

local STAGE = login_logic.STAGE

function meta:ctor()

    dbg("login_scene:ctor() START")



    local ui_root = ui_helper:LoadCocosUI("interface/login_panel.csb")

    self:addChild(ui_root)



    self.ui_root = ui_root



    --self.login_btn = ui_root:getChildByName("start_btn")

    --self.login_btn:setVisible(true)



    self.logo = ui_root:getChildByName("logo")

    self.logo_light = self.logo:getChildByName("logo_light")

    self.loading_bar = ui_helper:ExpandUI(ui_root, "npc", "modules/login/loading_panel")

    local bg_node = ui_root:getChildByName("bg")

    self.version_txt = bg_node:getChildByName("version")



    -- Register event handlers BEFORE any code that dispatches events.

    -- mu77_account:SignIn() below synchronously triggers DoEnterGame()

    -- which dispatches "switch_login_stage" -- if handlers aren't ready

    -- yet, the event is silently lost and the game hangs.

    self:RegisterEvent()

    self:RegisterWidgetEvent()

    

    self:SwtichStage(STAGE.init)

    ui_helper:SetText(self.version_txt, configuration:GetVersion())

    self.is_show_exit_view = false



    local lang_now = text_loader.cur_lang

    display.loadSpriteFrames("atlas/login.plist", "atlas/login.png")

    if lang_now == login_logic.locale_list[cc.LANGUAGE_CHINESE] then

        ui_helper:SetImage(self.logo,"ui/login/logo_cn.png" , ccui.TextureResType.plistType)

        ui_helper:SetImage(self.logo_light,"ui/login/logo_cn.png" , ccui.TextureResType.plistType)

    elseif lang_now == "zh-TW" then

        ui_helper:SetImage(self.logo,"ui/login/logo_tw.png" , ccui.TextureResType.plistType)

        ui_helper:SetImage(self.logo_light,"ui/login/logo_tw.png" , ccui.TextureResType.plistType)

    else

        ui_helper:SetImage(self.logo,"ui/login/logo_us.png" , ccui.TextureResType.plistType)

        ui_helper:SetImage(self.logo_light,"ui/login/logo_us.png" , ccui.TextureResType.plistType)

    end



    --hide login buttons by default

    local login_btn = self.ui_root:getChildByName("login_btn")

    local ios_outside = login_btn:getChildByName("ios_outside")

    local android_outside = login_btn:getChildByName("android_outside")

    local inside = login_btn:getChildByName("inside")

    local other = login_btn:getChildByName("other")

    ios_outside:setVisible(false)

    android_outside:setVisible(false)

    inside:setVisible(false)

    other:setVisible(false)



    --full package: go straight into login flow

    login_logic.bandingEntrance = 1

    local has_acct = login_logic:HasAccountSysFlow()

    dbg("HasAccountSysFlow() = " .. tostring(has_acct))

    if has_acct then

        if configuration:GetNeedShowLoginBtn() == 1 then

            self:showFrameByPlatform()

        else

            --iOS auto Game Center login

            if device.platform == "ios" then

                login_logic.autoAuth = true

                ThirdHelper["singIn"](login_logic.singin_type.GAMECENTER)

            end

            local mu77_account = require "logic.account.mu77_account"

            --iOS new users wait for Game Center

            if configuration:GetUserId() or device.platform ~= "ios" then

                dbg("Calling mu77_account:SignIn(GUEST)")

                mu77_account:SignIn("", "", login_logic.singin_type.GUEST)

            end

        end

    else

        -- OFFLINE MODE: no ThirdHelper available, go straight to game

        if OFFLINE_MODE then

            local mu77_account = require "logic.account.mu77_account"

            mu77_account:SignIn("", "", login_logic.singin_type.GUEST)

        else

            if self.cur_stage == STAGE.init then

                self:SwtichStage(STAGE.wait)

            elseif self.cur_stage == STAGE.wait then

                login_logic:DoEnterGame()

            end

        end

    end



    --register login-result handler

    login_logic:RegisterLoginEvent()

    -- RegisterEvent/RegisterWidgetEvent already called above

end



function meta:OnEnter()

    print("[LOGIN_SCENE] OnEnter() called")

end



function meta:OnExit()

end



-- Switch stage

function meta:SwtichStage(new_stage)

    print("[LOGIN_SCENE] SwtichStage: " .. tostring(new_stage))

    if self.cur_stage == new_stage then

        return

    end

    self.cur_stage = new_stage

    if self.cur_stage == STAGE.init then

        self.ui_root:PlayAnimation("enter_login", false, function ()

            if self.cur_stage == STAGE.init then

                self:SwtichStage(STAGE.wait)

            end

        end)

    elseif self.cur_stage == STAGE.wait then

        if login_logic:HasAccountSysFlow() then

            self.ui_root:PlayAnimation("loop_login", true)

        else

            login_logic:DoEnterGame()

        end

    elseif self.cur_stage == STAGE.passprot then

    elseif self.cur_stage == STAGE.loading then

        self.ui_root:PlayAnimation("enter_loading")

        local tips_list = data_template.tips_config

        local config = math.randlist(tips_list)

        if config then

            self.loading_bar:SetRandomDesc(config.desc)

        end

    elseif self.cur_stage == STAGE.complete then

        self.ui_root:PlayAnimation("exit_loading", false, function ()

            login_logic:DoLoadingComplete()

        end)

    end

end



function meta:RegisterEvent()

    print("[LOGIN_SCENE] RegisterEvent() called")

    graphic:RegisterEvent("switch_login_stage",function (new_stage)

        self:SwtichStage(new_stage)

    end)

end



function meta:RegisterWidgetEvent()

    print("[LOGIN_SCENE] RegisterWidgetEvent() called")



    self.ui_root:SetFrameEventCallFunc(function (frame)

       local event_name = frame:getEvent()

       if event_name == "run" then

            login_logic:DoAsyncLoadingProgress(function (percent)

                self.loading_bar:SetPercent(percent)

            end)

        end

    end)



    -- ui_helper:AddClick(self.login_btn, function ()

        -- if self.cur_stage == STAGE.init then

        --     self:SwtichStage(STAGE.wait)

        -- elseif self.cur_stage == STAGE.wait then

        --     login_logic:DoEnterGame()

        -- end

    -- end)





    --listen for back key

    local key_listener = cc.EventListenerKeyboard:create()

    key_listener:registerScriptHandler(function(key, event)

        if key ~= cc.KeyCode.KEY_ESCAPE then

            return

        end

        if self.is_show_exit_view then

            return

        end



        self.is_show_exit_view = true

        local title = text_loader:GetText("game_exit_title")

        local desc = text_loader:GetText("game_exit_desc")

        local confirm_txt = text_loader:GetText("game_exit_confirm")

        local cancel_txt = text_loader:GetText("game_exit_cancel")



        local confirm_box = require("modules.common.confirm_box").new()

        confirm_box:ShowConfirm(title, desc, confirm_txt, cancel_txt,

            function ()

                -- quit

                cc.Director:getInstance():endToLua()

            end,

            function ()

                -- back

                confirm_box:Hide(function ()

                    self.is_show_exit_view = false

                    self:removeChild(confirm_box)

                end)

            end

        )

        self:addChild(confirm_box, 9999)



    end, cc.Handler.EVENT_KEYBOARD_RELEASED)

    local event_dispatcher = self:getEventDispatcher()

    event_dispatcher:addEventListenerWithSceneGraphPriority(key_listener, self)



end



function meta:showFrameByPlatform()

    print("[LOGIN_SCENE] showFrameByPlatform() called")

    --get widgets



    local login_btn = self.ui_root:getChildByName("login_btn")

    local ios_outside = login_btn:getChildByName("ios_outside")

    local android_outside = login_btn:getChildByName("android_outside")

    local inside = login_btn:getChildByName("inside")

    local other = login_btn:getChildByName("other")

    self.bgBtn = other:getChildByName("bg")

    other:setVisible(false)

    ios_outside:setVisible(false)

    android_outside:setVisible(false)

    inside:setVisible(false)



    local lang_now = text_loader.cur_lang

    --pick login chrome by platform and language

    if device.platform == "ios" then

        other:setVisible(true)

        if lang_now == login_logic.locale_list[cc.LANGUAGE_CHINESE] then    --iOS China

            inside:setVisible(true)

            self.qqBtn = inside:getChildByName("qq_btn")

            self.wechatBtn = inside:getChildByName("wechat_btn")

            self.guestBtn = inside:getChildByName("guest_btn")

        else                                                                --iOS overseas

            ios_outside:setVisible(true)

            self.fbBtn = ios_outside:getChildByName("facebook_btn")

            self.guestBtn = ios_outside:getChildByName("guest_btn")

        end

    elseif device.platform == "android" then

        if lang_now == login_logic.locale_list[cc.LANGUAGE_CHINESE] then     --Android China

            inside:setVisible(true)

            self.qqBtn = inside:getChildByName("qq_btn")

            self.wechatBtn = inside:getChildByName("wechat_btn")

            self.guestBtn = inside:getChildByName("guest_btn")

        else                                                                --Android overseas

            android_outside:setVisible(true)

            self.googleBtn = android_outside:getChildByName("google_btn")

            self.fbBtn = android_outside:getChildByName("facebook_btn")

            self.guestBtn = android_outside:getChildByName("guest_btn")

        end

    end



    --initial button panel state

    self:setLoginBtnState(1)



    --banding all buttons callback

    if self.fbBtn then

        ui_helper:AddClick(self.fbBtn, function ()

            if ThirdHelper and ThirdHelper["singIn"] then

                graphic:DispatchEvent("signin_frame_state", 2, login_logic.singin_type.FACEBOOK)

                self:goToSign(login_logic.singin_type.FACEBOOK)

            end

        end)

    end



    if self.googleBtn then

        ui_helper:AddClick(self.googleBtn, function ()

            if ThirdHelper and ThirdHelper["singIn"] then

                graphic:DispatchEvent("signin_frame_state", 2, login_logic.singin_type.GOOGLE)

                self:goToSign(login_logic.singin_type.GOOGLE)

            end

        end)

    end



    if self.qqBtn then

        ui_helper:AddClick(self.qqBtn, function ()

            if ThirdHelper and ThirdHelper["singIn"] then

                graphic:DispatchEvent("signin_frame_state", 2, login_logic.singin_type.QQ)

                 self:goToSign(login_logic.singin_type.QQ)

            end

        end)

    end



    if self.wechatBtn then

        ui_helper:AddClick(self.wechatBtn, function ()

            if ThirdHelper and ThirdHelper["singIn"] then

                graphic:DispatchEvent("signin_frame_state", 2, login_logic.singin_type.WECHAT)

                self:goToSign(login_logic.singin_type.WECHAT)

            end

        end)

    end



    if self.guestBtn then

        ui_helper:AddClick(self.guestBtn, function ()

            if ThirdHelper and ThirdHelper["singIn"] then

                local mu77_account = require "logic.account.mu77_account"

                mu77_account:SignIn("", "", login_logic.singin_type.GUEST)

            end

        end)

    end



    if self.bgBtn and self.bgBtn:isVisible() then

        ui_helper:AddClick(self.bgBtn, function ()

            if ThirdHelper and ThirdHelper["singIn"] then

                if device.platform == "ios" then

                    graphic:DispatchEvent("signin_frame_state", 2, login_logic.singin_type.GAMECENTER)

                    self:goToSign(login_logic.singin_type.GAMECENTER)

                end

            end

        end)

    end



    --register login-result UI updates

    self:RegisterLoginEvent()



    --hide Game Center on Android

    if device.platform == "android" then

        other:setVisible(false)

    end

end



function meta:goToSign(platformName)

    --jump to third-party login

    login_logic.autoAuth = false

    ThirdHelper["singIn"](platformName)

    --timeout so the client cannot hang

    if self.schedulerID == nil then

        self.schedulerID = cc.Director:getInstance():getScheduler():scheduleScriptFunc(function()

            if self.schedulerID ~= nil then

                self:setLoginBtnState(1)

                self.schedulerID = nil

            end

            end, 20, false)

    end

end



function meta:RegisterLoginEvent()

    graphic:RegisterEvent("signin_frame_state", function(status_code, arg2)

        self:setLoginBtnState(status_code, arg2)

    end)

end



function meta:setLoginBtnState(status_code, arg2)

    if status_code == 1 then        --clickable

        --reset timer

        if self.schedulerID then

            cc.Director:getInstance():getScheduler():unscheduleScriptEntry(self.schedulerID)

        end



        if self.fbBtn then

            self.fbBtn:setEnabled(true)

            local desc = self.fbBtn:getChildByName("desc")

            ui_helper:SetTextByKey(desc, "account_login_state1", login_logic:GetPlatformNameByType(login_logic.singin_type.FACEBOOK))

        end

        if self.googleBtn then

            self.googleBtn:setEnabled(true)

            local desc = self.googleBtn:getChildByName("desc")

            ui_helper:SetTextByKey(desc, "account_login_state1", login_logic:GetPlatformNameByType(login_logic.singin_type.GOOGLE))

        end

        if self.qqBtn then

            self.qqBtn:setEnabled(true)

            local desc = self.qqBtn:getChildByName("desc")

            ui_helper:SetTextByKey(desc, "account_login_state1", login_logic:GetPlatformNameByType(login_logic.singin_type.QQ))

        end

        if self.wechatBtn then

            self.wechatBtn:setEnabled(true)

            local desc = self.wechatBtn:getChildByName("desc")

            ui_helper:SetTextByKey(desc, "account_login_state1", login_logic:GetPlatformNameByType(login_logic.singin_type.WECHAT))

        end

        if self.guestBtn then

            self.guestBtn:setEnabled(true)

            local desc = self.guestBtn:getChildByName("desc")

            ui_helper:SetTextByKey(desc, "account_login_state1", login_logic:GetPlatformNameByType(login_logic.singin_type.GUEST))

        end

        if self.bgBtn and self.bgBtn:isVisible() then

            self.bgBtn:setEnabled(true)

            if device.platform == "ios" then

                ui_helper:SetTextByKey(desc, "account_login_state1", login_logic:GetPlatformNameByType(login_logic.singin_type.GAMECENTER))

            end

        end

    elseif status_code == 2 then    --not clickable

        if self.fbBtn then

            self.fbBtn:setEnabled(false)

            if arg2 == login_logic.singin_type.FACEBOOK then

                local desc = self.fbBtn:getChildByName("desc")

                ui_helper:SetTextByKey(desc, "account_login_state2", login_logic:GetPlatformNameByType(arg2))

            end

        end

        if self.googleBtn then

            self.googleBtn:setEnabled(false)

            if arg2 == login_logic.singin_type.GOOGLE then

                local desc = self.googleBtn:getChildByName("desc")

                ui_helper:SetTextByKey(desc, "account_login_state2", login_logic:GetPlatformNameByType(arg2))

            end

        end

        if self.qqBtn then

            self.qqBtn:setEnabled(false)

            if arg2 == login_logic.singin_type.QQ then

                local desc = self.qqBtn:getChildByName("desc")

                ui_helper:SetTextByKey(desc, "account_login_state2", login_logic:GetPlatformNameByType(arg2))

            end

        end

        if self.wechatBtn then

            self.wechatBtn:setEnabled(false)

            if arg2 == login_logic.singin_type.WECHAT then

                local desc = self.wechatBtn:getChildByName("desc")

                ui_helper:SetTextByKey(desc, "account_login_state2", login_logic:GetPlatformNameByType(arg2))

            end

        end

        if self.guestBtn then

            self.guestBtn:setEnabled(false)

            if arg2 == login_logic.singin_type.GUEST then

                local desc = self.guestBtn:getChildByName("desc")

                ui_helper:SetTextByKey(desc, "account_login_state2", login_logic:GetPlatformNameByType(arg2))

            end

        end

        if self.bgBtn and self.bgBtn:isVisible() then

            self.bgBtn:setEnabled(false)

            if device.platform == "ios" then

                ui_helper:SetTextByKey(desc, "account_login_state2", login_logic:GetPlatformNameByType(arg2))

            end

        end

    end

    if self.googleBtn then

        self.googleBtn:setVisible(false)

    end

end



return meta

