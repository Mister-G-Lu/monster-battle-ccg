local ui_helper = require "manager.ui_helper"
local ckdye_logic = require "logic.cdkey"
local text_loader = require "manager.text_loader"

local meta = ui_helper:NewPanel("cdkey_panel", "interface/setting/cdkey_panel.csb")

function meta:OnInit()
	local msgbox = self:getChildByName("msgbox")
	self.msgbox = msgbox

	self.close_btn = self.msgbox:getChildByName("close_btn")
	self.confirm_btn = self.msgbox:getChildByName("confirm_btn")

	self.textfield = self.msgbox:getChildByName("textfield")
	self.textfield:setMaxLength(20)
	self.editbox = ui_helper:ReplaceEditBox(self.textfield)
	self.editbox:setInputFlag(cc.EDITBOX_INPUT_FLAG_INITIAL_CAPS_ALL_CHARACTERS)
	self.editbox:setInputMode(cc.EDITBOX_INPUT_MODE_SINGLELINE)
	self.editbox:setPlaceHolder(text_loader:GetText("enter_cdkey_code"))

	self:RegisterWidgetEvent()
end

function meta:OnExit()
end

function meta:Updata()
end

function meta:Show()
	self.editbox:setVisible(true)
	self:setVisible(true)
end

function meta:Hide()
	self.editbox:setVisible(false)
	self:setVisible(false)
end

function meta:RegisterEvent()
	--显示cdk结果
	self:RegisterGraphic("show_cdkey_result", function (result, recv_msg)
		if result == "success" then
			self:DispatchGraphicEvent("pop_world_panel")
			local rewardlist = recv_msg["reward_list"] or {}
			self:DispatchGraphicEvent("show_reward_panel", rewardlist)
		else
			self:DispatchGraphicEvent("show_message", result)
		end
	end)
end

function meta:RegisterWidgetEvent()
	ui_helper:AddClick(self.close_btn, function ()
		self:DispatchGraphicEvent("pop_world_panel")
	end)

	ui_helper:AddClick(self.confirm_btn, function ()
		ckdye_logic:ReqCdkeyAward(self.editbox:getString())
	end)
end


return meta
