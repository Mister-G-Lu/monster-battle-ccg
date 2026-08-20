
local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local global = require "manager.global"
local login_logic = require "logic.login"
local configuration = require "manager.configuration"

local meta = class("account_panel",function ()
    return ui_helper:LoadCocosUI("interface/setting/account_panel.csb")
end)

function meta:ctor()
	self.msgbox = self:getChildByName("msgbox")
    self.close_btn = self.msgbox:getChildByName("close_btn")
    self:RegisterWidgetEvent()
    self:RegisterEvent()
    self:showFrameByPlatform()
end

function meta:showFrameByPlatform()
	-- todo根据平台显示不同的按钮
	self.login_btn = self.msgbox:getChildByName("login_btn")
	self.btn1 = self.login_btn:getChildByName("btn1")
	self.btn2 = self.login_btn:getChildByName("btn2")
	self.btn3 = self.login_btn:getChildByName("btn3")
	self.transform_btn = self.msgbox:getChildByName("transform_btn")
	
	--初始化显示的按钮文本
	self:setLoginBtnState(1)
end

--status_code 1为初始化状态 根据本地数据显示是否已登入 分别显示已登入 还是 登出 并绑定对应按钮click方法 此时arg2为空  2为去绑定时的状态 此时arg2为去绑定时的平台ID
function meta:setLoginBtnState(status_code, arg2)
	if ThirdHelper == nil or ThirdHelper["singIn"] == nil or ThirdHelper["singOut"] == nil then
		return
	end
	login_logic.bandingEntrance = 2
	self.btn1:setEnabled(true)
	self.btn2:setEnabled(true)
	self.btn3:setEnabled(true)
	self.close_btn:setEnabled(true)
	self.transform_btn:setEnabled(true)
	self.btn3:setVisible(false)		--第三个按钮默认隐藏
	local posY = -200;
    --根据平台和设备的语言 来区分显示的样式
    local desc1 = self.btn1:getChildByName("desc")
    local desc2 = self.btn2:getChildByName("desc")
    local desc3 = self.btn3:getChildByName("desc")
    local target = cc.Application:getInstance():getTargetPlatform()
    local keyName = ""
    local platformName = ""
    local platformNum = 0
    local lang_now = text_loader.cur_lang

    if status_code == 1 then
    	--重置定时器
        if self.schedulerID then
            cc.Director:getInstance():getScheduler():unscheduleScriptEntry(self.schedulerID)
        end
    end

    if device.platform == "ios" then
        if lang_now == login_logic.locale_list[cc.LANGUAGE_CHINESE] then
            self.btn3:setVisible(true)
            posY = -238;
            if status_code == 1 then
            	platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.QQ)
            	if configuration:GetQQIsBanded() == 1 then
            		keyName = "account_bind_state3"
            		platformNum = platformNum + 1
            		ui_helper:AddClick(self.btn1, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.QQ)
			        end)
			        self.btn1:setEnabled(false)
            	else
            		keyName = "account_bind_state1"
            		ui_helper:AddClick(self.btn1, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.QQ)
			            self:gotoSign(login_logic.singin_type.QQ)
			        end)
            	end
            	ui_helper:SetTextByKey(desc1, keyName, platformName)            	

            	platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.WECHAT)
            	if configuration:GetWECHATIsBanded() == 1 then
            		keyName = "account_bind_state3"
            		platformNum = platformNum + 1
			        ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.WECHAT)
			        end)
			        self.btn2:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"
					ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.WECHAT)
			            self:gotoSign(login_logic.singin_type.WECHAT)
			        end)
			    end
			    ui_helper:SetTextByKey(desc2, keyName, platformName)

			    platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.GAMECENTER)
			    if configuration:GetGCIsBanded() == 1 then
			    	keyName = "account_bind_state3"
			    	platformNum = platformNum + 1
			        ui_helper:AddClick(self.btn3, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.GAMECENTER)
			        end)
			        self.btn3:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"
			    	ui_helper:AddClick(self.btn3, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.GAMECENTER)
			            self:gotoSign(login_logic.singin_type.GAMECENTER)
			        end)
			    end
			    ui_helper:SetTextByKey(desc3, keyName, platformName)
            
            elseif status_code == 2 then
            	keyName = "account_bind_state2"
            	local objOne = nil
            	self.btn1:setEnabled(false)
            	self.btn2:setEnabled(false)
            	self.btn3:setEnabled(false)
            	self.close_btn:setEnabled(false)
            	self.transform_btn:setEnabled(false)
            	if arg2 == login_logic.singin_type.QQ then
            		objOne = desc1
            	elseif arg2 == login_logic.singin_type.WECHAT then
            		objOne = desc2
            	elseif arg2 == login_logic.singin_type.GAMECENTER then
            		objOne = desc3
            	end
            	ui_helper:SetTextByKey(objOne, keyName, login_logic:GetPlatformNameByType(arg2))
            end
        else                                                   	--ios海外
            if status_code == 1 then
            	platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.FACEBOOK)
            	if configuration:GetFBIsBanded() == 1 then
            		keyName = "account_bind_state3"
            		platformNum = platformNum + 1            		
	            	ui_helper:AddClick(self.btn1, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.FACEBOOK)
			        end)
			        self.btn1:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"
			    	ui_helper:AddClick(self.btn1, function ()	
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.FACEBOOK)
			            self:gotoSign(login_logic.singin_type.FACEBOOK)
			        end)
			    end
			    ui_helper:SetTextByKey(desc1, keyName, platformName)
			    
			    platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.GAMECENTER)
			    if configuration:GetGCIsBanded() == 1 then
			    	keyName = "account_bind_state3"  
			    	platformNum = platformNum + 1
			    	ui_helper:SetTextByKey(desc2, "battle_result_lose")
			        ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.GAMECENTER)
			        end)
			        self.btn2:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"			    	
			    	ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.GAMECENTER)
			            self:gotoSign(login_logic.singin_type.GAMECENTER)
			        end)
			    end
			    ui_helper:SetTextByKey(desc2, keyName, platformName)
            elseif status_code == 2 then
            	keyName = "account_bind_state2"
            	local objOne = nil
            	self.btn1:setEnabled(false)
            	self.btn2:setEnabled(false)
            	self.close_btn:setEnabled(false)
            	self.transform_btn:setEnabled(false)
            	if arg2 == login_logic.singin_type.FACEBOOK then
	            	objOne = desc1
            	elseif arg2 == login_logic.singin_type.GAMECENTER then
            		objOne = desc2
            	end
            	ui_helper:SetTextByKey(objOne, keyName, login_logic:GetPlatformNameByType(arg2))
            end
        end
    elseif target == cc.PLATFORM_OS_ANDROID then
        if lang_now == login_logic.locale_list[cc.LANGUAGE_CHINESE] then	--android国内
            if status_code == 1 then
            	platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.QQ)
            	if configuration:GetQQIsBanded() == 1 then
            		keyName = "account_bind_state3"  
            		platformNum = platformNum + 1
            		ui_helper:AddClick(self.btn1, function ()
			            if ThirdHelper and ThirdHelper["singOut"] then
			                graphic:DispatchEvent("signin_frame_state_setting", 1)
			                ThirdHelper["singOut"](login_logic.singin_type.QQ)
			            end
			        end)
			        self.btn1:setEnabled(false)
            	else
            		keyName = "account_bind_state1"
            		ui_helper:AddClick(self.btn1, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.QQ)
			            self:gotoSign(login_logic.singin_type.QQ)
			        end)
            	end
            	ui_helper:SetTextByKey(desc1, keyName, platformName)
            	
            	platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.WECHAT)
            	if configuration:GetWECHATIsBanded() == 1 then
            		keyName = "account_bind_state3"  
            		platformNum = platformNum + 1
			        ui_helper:AddClick(self.btn2, function ()
			            if ThirdHelper and ThirdHelper["singOut"] then
			                graphic:DispatchEvent("signin_frame_state_setting", 1)
			                ThirdHelper["singOut"](login_logic.singin_type.WECHAT)
			            end
			        end)
			        self.btn2:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"
					ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.WECHAT)
			            self:gotoSign(login_logic.singin_type.WECHAT)
			        end)
			    end
			    ui_helper:SetTextByKey(desc2, keyName, platformName)
            elseif status_code == 2 then
            	keyName = "account_bind_state2"
            	local objOne = nil
            	self.btn1:setEnabled(false)
            	self.btn2:setEnabled(false)
            	self.close_btn:setEnabled(false)
            	self.transform_btn:setEnabled(false)
            	if arg2 == login_logic.singin_type.QQ then
            		objOne = desc1
            	elseif arg2 == login_logic.singin_type.WECHAT then
            		objOne = desc2
            	end
            	ui_helper:SetTextByKey(objOne, keyName, login_logic:GetPlatformNameByType(arg2))
            end
        else
            if status_code == 1 then
            	platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.FACEBOOK)
            	if configuration:GetFBIsBanded() == 1 then
            		keyName = "account_bind_state3"  
            		platformNum = platformNum + 1
	            	ui_helper:AddClick(self.btn1, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.FACEBOOK)
			        end)
                    self.btn1:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"  
			    	ui_helper:AddClick(self.btn1, function ()	
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.FACEBOOK)
			            self:gotoSign(login_logic.singin_type.FACEBOOK)
			        end)
			    end
			    ui_helper:SetTextByKey(desc1, keyName, platformName)

			    platformName = login_logic:GetPlatformNameByType(login_logic.singin_type.GOOGLE)
			    if configuration:GetGGIsBanded() == 1 then
			    	keyName = "account_bind_state3"
			    	platformNum = platformNum + 1
			        ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 1)
			            ThirdHelper["singOut"](login_logic.singin_type.GOOGLE)
			        end)
			        self.btn2:setEnabled(false)
			    else
			    	keyName = "account_bind_state1"
			    	ui_helper:AddClick(self.btn2, function ()
			            graphic:DispatchEvent("signin_frame_state_setting", 2, login_logic.singin_type.GOOGLE)
			            self:gotoSign(login_logic.singin_type.GOOGLE)
			        end)
			    end
			    self.btn2:setVisible(false)
			    ui_helper:SetTextByKey(desc2, keyName, platformName)
            elseif status_code == 2 then
            	keyName = "account_bind_state2"
            	local objOne = nil
            	self.btn1:setEnabled(false)
            	self.btn2:setEnabled(false)
            	self.close_btn:setEnabled(false)
            	self.transform_btn:setEnabled(false)
            	if arg2 == login_logic.singin_type.FACEBOOK then
	            	objOne = desc1
            	elseif arg2 == login_logic.singin_type.GOOGLE then
            		objOne = desc2
            	end
            	ui_helper:SetTextByKey(objOne, keyName, login_logic:GetPlatformNameByType(arg2))
            end
        end
    end
    if self.login_btn then
    	self.login_btn:setPositionY(posY)
    end

    ui_helper:AddClick(self.transform_btn, function ()
    	--未绑定过账号的玩家提示无法登出
    	if platformNum == 0 then
	        graphic:DispatchEvent("show_message", "account_bind_log_tips1")
	    else
			local platform_manager = require "logic.platform_manager"
        	platform_manager:DispatchEvent("signout_result")
        end
	end)
end

function meta:gotoSign(platformName)
	--跳转到第三方登录
	login_logic.autoAuth = false
    ThirdHelper["singIn"](platformName)
    --生成定时schedule防止客户端卡死
    --if self.schedulerID == nil then
        self.schedulerID = cc.Director:getInstance():getScheduler():scheduleScriptFunc(function()
        	if self.schedulerID then
            	self:setLoginBtnState(1)
            	self.schedulerID = nil
	        end
            end, 20, false)
    --end
end

function meta:Update(elapsed_time)
end

function meta:Show()
    self:setVisible(true)
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.close_btn, function ()
    	login_logic.bandingEntrance = 1
        graphic:DispatchEvent("pop_world_panel")
    end)
    graphic:RegisterEvent("signin_frame_state_setting", function(status_code, arg2)
        self:setLoginBtnState(status_code, arg2)
    end)
end


return meta
