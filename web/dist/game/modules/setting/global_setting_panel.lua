local ui_helper = require "manager.ui_helper"

local meta = ui_helper:NewPanel("global_setting_panel", "interface/setting/global_setting_panel.csb")

function meta:OnInit()
	self.msgbox = self:getChildByName("msgbox")
	self.close_btn = self.msgbox:getChildByName("close_btn")

	self.login_btn = self.msgbox:getChildByName("login_btn")
	self.cdk_code = self.login_btn:getChildByName("btn2")  --兑换码

	self.account_bind = self.login_btn:getChildByName("btn3")  --账号绑定
	if self.account_bind then
        local login_logic = require "logic.login"
        if login_logic:HasAccountSysFlow() == false then     --热更包 隐藏此按钮
            self.account_bind:setVisible(false)
        end
    end

	self:RegisterWidgetEvent()
end

function meta:OnExit()
end

function meta:Update()
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
		self:DispatchGraphicEvent("pop_world_panel")
	end)

	ui_helper:AddClick(self.cdk_code, function ()
		self:DispatchGraphicEvent("push_world_panel", "setting", "cdkey_panel")
	end)

	ui_helper:AddClick(self.account_bind, function ()
		self:DispatchGraphicEvent("push_world_panel", "setting", "account_panel")
	end)
end

return meta
