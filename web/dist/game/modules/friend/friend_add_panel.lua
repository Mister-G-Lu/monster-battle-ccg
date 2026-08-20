
local ui_helper = require "manager.ui_helper"
local friend_logic = require "logic.friend"

local meta = ui_helper:NewPanel("friend_add_panel", "interface/friend/friend_add_panel.csb")

function meta:OnInit()
	self.node = self:getChildByName("msgbox")
	self.close_btn = self.node:getChildByName("close_btn")
	self.add_friend_id = 0
	self:setVisible(false)
	self.result_node = self.node:getChildByName("the_bg"):getChildByName("find_node"):getChildByName("result")
	self.find_btn = self.node:getChildByName("the_bg"):getChildByName("find_node"):getChildByName("enter_btn")
	self.textfield = self.node:getChildByName("the_bg"):getChildByName("find_node"):getChildByName("textfield")
	self.invitation_btn = self.result_node:getChildByName("result2"):getChildByName("confirm_btn")
	-- self.editbox = ui_helper:ReplaceEditBox(self.textfield)
	self.result_node:setVisible(false)
	-- 加入遮罩层
    self.mask_node = ccui.Layout:create()
    self.mask_node:setContentSize(display.sizeInPixels.width, display.sizeInPixels.height)
    self.mask_node:setBackGroundColor(ui_helper:GetColor4B(0x303030))
    self.mask_node:setBackGroundColorOpacity(255 * 0.9)
    self.mask_node:setBackGroundColorType(1)
    self.mask_node:setTouchEnabled(true)
    self.mask_node:setVisible(true)
    self:addChild(self.mask_node, -100)

 --    self.editbox:setPlaceHolder(text_loader:GetText("input_friend_num"))
	-- self.editbox:setInputFlag(cc.EDITBOX_INPUT_FLAG_INITIAL_CAPS_ALL_CHARACTERS)
	-- self.editbox:setInputMode(cc.EDITBOX_INPUT_MODE_EMAILADDR)

    self:RegisterWidgetEvent()
end
function meta:Show()

	self.result_node:setVisible(false)
	self.textfield:setString("")
	-- self.editbox:setString("")
	-- self.editbox:setVisible(true)
	self:setVisible(true)
end
function meta:Hide()
	-- self.editbox:setVisible(false)
	self:setVisible(false)
end

function meta:RegisterEvent()
	self:RegisterGraphic("show_add_friend",function (_)
		self:Show()
	end)
	--显示搜索结果
	self:RegisterGraphic("show_search_result",function (result,recv_msg)
		self.result_node:setVisible(true)
		local result1 = self.result_node:getChildByName("result1")
		local result2 = self.result_node:getChildByName("result2")
		result1:setVisible(true)
		result2:setVisible(true)
		if recv_msg ~= nil then
			result2:getChildByName("name"):setString(recv_msg.user_name)
			result2:getChildByName("ladder_value"):setString("1")--暂时固定值 以后改用天梯等级
			-- result2:getChildByName("ladder_icon")--暂时不更改 以后改用天梯头像
			self.result_node:getChildByName("result1"):setVisible(false)
			self.add_friend_id = recv_msg.user_id
		else
			self.result_node:getChildByName("result2"):setVisible(false)
			self:DispatchGraphicEvent("show_message", result)
		end
	end)

	--添加好友结果
	self:RegisterGraphic("refresh_friend_add",function ()
		self:RefreshPanel()
	end)

end
--刷添加好友界面
function meta:RefreshPanel()
	self.textfield:setString("")
	-- self.editbox:setString("")
	self.result_node:getChildByName("result2"):setVisible(false)
	self.result_node:getChildByName("result1"):setVisible(false)
end

function meta:RegisterWidgetEvent()
	--关闭按钮
	ui_helper:AddClick(self.close_btn,function()
		self:Hide()
	end)
	--搜索按钮
	ui_helper:AddClick(self.find_btn,function()
		friend_logic:ReqFriendSearch(self.textfield:getString())
		-- friend_logic:ReqFriendSearch(self.editbox:getString())
	end)
	--好友邀请按钮
	ui_helper:AddClick(self.invitation_btn,function()
		friend_logic:ReqFriendAdd(self.add_friend_id)
	end)
end

return meta
