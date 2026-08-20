local ui_helper = require "manager.ui_helper"
local friend_logic = require "logic.friend"


local MAX_ROW = 8
local SUB_PANEL_HEIGHT = 100

local meta = ui_helper:NewPanel("friend_message_panel", "interface/friend/friend_message_panel.csb")
function meta:Init()
	-- 加入遮罩层
    self.mask_node = ccui.Layout:create()
    self.mask_node:setContentSize(display.sizeInPixels.width, display.sizeInPixels.height)
    self.mask_node:setBackGroundColor(ui_helper:GetColor4B(0x303030))
    self.mask_node:setBackGroundColorOpacity(255 * 0.9)
    self.mask_node:setBackGroundColorType(1)
    self.mask_node:setTouchEnabled(true)
    self.mask_node:setVisible(true)
    self.friend_checkbox = self.node:getChildByName("friend_checkbox")
    self:addChild(self.mask_node, -100)
	self.close_btn = self.node:getChildByName("close_btn")
	self:setVisible(false)
	self.friend_news_list = {}

	self:InitScrollView()
	self:ShowFriendNews(self.friend_news_list,self.can_be_added)
end

function meta:OnInit()
	self.node = self:getChildByName("node")
	self:Init()
	self:RegisterWidgetEvent()
end

function meta:Show()
	self:setVisible(true)
end
function meta:Hide()
	self:setVisible(false)
end
function meta:RegisterEvent()
	--关闭按钮
	ui_helper:AddClick(self.close_btn,function()
		friend_logic:ReqFriendAddListOrNo()
		self:Hide()
	end)
end
function meta:RegisterWidgetEvent()
	--显示好友消息界面
	self:RegisterGraphic("show_friend_message_panel",function()
		self:Show()
	end)
	--是否接受好友邀请
	self.friend_checkbox:addEventListener(function (sender,eventType )
 		if eventType == ccui.CheckBoxEventType.selected then
		        friend_logic.can_be_added = false
	    elseif eventType == ccui.CheckBoxEventType.unselected then
	    		friend_logic.can_be_added = true
		end
 	end)
 	--通知列表
 	self:RegisterGraphic("refresh_friend_add_list",function (friend_add_list,can_be_added)
		if friend_add_list then
			self.friend_news_list = friend_add_list

			if can_be_added == "yes" then
				friend_logic.can_be_added = true
			else
				friend_logic.can_be_added = false
			end
			self:ShowFriendNews(self.friend_news_list,friend_logic.can_be_added)
		end
	end)
	--处理通知消息
	self:RegisterGraphic("processing_invitation_message",function (user_id)
		for k,v in pairs(self.friend_news_list) do
			if v.user_id == user_id then
				table.remove(self.friend_news_list,k)
			end
		end
		self:ShowFriendNews(self.friend_news_list,friend_logic.can_be_added)
	end)
end
--初始化列表控件
function meta:InitScrollView()

	self.scroll_view = self.node:getChildByName("scroll_view")
 	self.friend_list_node = ui_helper:ExpandUI(self.node, "scroll_view", "widget/refine_list_view")
	local templates = self.node:getChildByName("template")
	templates:setVisible(false)
	self.friend_list_node:Init(MAX_ROW,SUB_PANEL_HEIGHT,function()
		local new_friend= require("modules.friend.friend_message_template").new(templates:clone())
		new_friend:setVisible(true)
		return new_friend
	end)
end
--显示通知
function meta:ShowFriendNews(news_list,accept)
	-- self.friend_checkbox:setSelected(accept)
	self.friend_list_node:Show(#news_list,function(cur_row,item_node)
		local friend_add_info = news_list[cur_row]
		item_node:SetFriendInfo(friend_add_info)

	end)
end

return meta
