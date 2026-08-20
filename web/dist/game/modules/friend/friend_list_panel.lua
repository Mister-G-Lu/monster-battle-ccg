local ui_helper = require "manager.ui_helper"
local user_logic = require "logic.user"
local text_loader = require "manager.text_loader"
local friend_logic = require "logic.friend"
local rank_logic = require "logic.rank"
local constants = require "common.constants"
local FRIEND_STATUS = constants.FRIEND_STATUS
local MAX_ROW = 8
local SUB_PANEL_HEIGHT = 100
local PANEL_ZORDER = 100
local meta = ui_helper:NewPanel("friend_list_panel", "interface/friend/friend_list_panel.csb")
function meta:Init()
	self.close_btn = self.node:getChildByName("close_btn")
	self.list_node = self.node:getChildByName("list_node")
	self.add_friend_btn = self.list_node:getChildByName("add_btn")
	self.message_btn = self.list_node:getChildByName("message_btn")
	self.setting_btn = self.list_node:getChildByName("setting_btn")
	ui_helper:SetTextByKey(self.setting_btn:getChildByName("desc"), "friend_setting_desc") --编辑
	self.page_btn1 = self.list_node:getChildByName("page_btn1")
	self.template = self.list_node:getChildByName("template")
	self.scroll_view = self.list_node:getChildByName("scroll_view")
	self.template_item = {}
	self.is_setting = false
	self:InitScrollView()
	self:ShowFriendList(friend_logic.friend_list)
	self.player_ladder_info = self.list_node:getChildByName("player_ladder_info")
	ui_helper:SetTextByKey(self.player_ladder_info:getChildByName("arena_value"),"1")
	self.player_ladder_info_btn = self.list_node:getChildByName("player_ladder_info")
	self.message_tip = self.message_btn:getChildByName("tip")
	ui_helper:BindTimeLine(self.message_tip, "interface/world/newtip.csb")
	self.message_tip:setVisible(false)
	if friend_logic.notice ~= nil then
		self.message_tip:setVisible(true)
	end
	self.page_btn1_tip = self.page_btn1:getChildByName("tip")
	self.page_btn1_tip:setVisible(false)
	ui_helper:BindTimeLine(self.page_btn1_tip, "interface/world/newtip.csb")
	self.page_btn1_tip:PlayAnimation("loop", true)

 	ui_helper:SetTextByKey(self.player_ladder_info:getChildByName("name"),user_logic.name.."#"..user_logic.user_id)
 	ui_helper:SetTextByKey(self.player_ladder_info:getChildByName("elo_ladder_value"),text_loader:GetText("friend_title",friend_logic.rank))

end
function meta:OnInit()
	self.node = self:getChildByName("msgbox")
	--添加好友界面
	local friend_panel = require("modules.friend.friend_add_panel").new()
    self:addChild(friend_panel,PANEL_ZORDER)
    --通知界面
    local friend_message_panel = require("modules.friend.friend_message_panel").new()
    self:addChild(friend_message_panel,PANEL_ZORDER)
    self.msgbox = ui_helper:ExpandUI(self.node, "msgbox_node", "modules.common.confirm_box")

	self:Init()
	self:RegisterWidgetEvent()
end

function meta:Show()
	self:setVisible(true)
end

function meta:Hide()
	self:setVisible(false)
end

function meta:InitScrollView()
	local templates = self.list_node:getChildByName("template")
	templates:setVisible(false)
	self.friend_list_node = ui_helper:ExpandUI(self.list_node, "scroll_view", "widget/refine_list_view")
	self.friend_list_node:Init(MAX_ROW,SUB_PANEL_HEIGHT,function()
		local new_friend= require("modules.friend.friend_template").new(templates:clone())
		new_friend:setVisible(true)
		return new_friend
	end)
end

--显示玩家好友List
function meta:ShowFriendList(friend_list)
	self.online_num = 0
	if friend_list then
		for k,v in pairs(friend_list) do
			if v.status ~= FRIEND_STATUS.offline then
				self.online_num = self.online_num + 1
			end
		end
		ui_helper:SetTextByKey(self.page_btn1:getChildByName("desc"), "normal_friend_online", self.online_num) -- 普通(在线 %d)
	end
	local friend_list = friend_list
	local friend_num = #friend_list
	self.friend_list_node:Show(#friend_list,function(cur_row,item_node)
		local friend_info = friend_list[cur_row]
		item_node:SetFriendInfo(friend_info)
		item_node:SetStage(self.is_setting)
		item_node:AddChatClick(friend_info,function()
		end)
		item_node:FightClick(friend_info,function()
		end)
	end)
	local rank = friend_logic:FriendrankSort(friend_list)
	if self.player_ladder_info then
		ui_helper:SetTextByKey(self.player_ladder_info:getChildByName("elo_ladder_value"),text_loader:GetText("friend_title",rank))
	end
end

--通知动画
function meta:HaveInformation(the_bool)
	if  the_bool then
		self.message_tip:setVisible(true)
		self.message_tip:PlayAnimation("loop", true)
	else
		self.message_tip:setVisible(false)
	end
end

--人在线动画
function meta:HaveChatInformation(the_bool)
	if  the_bool then
		self.page_btn1_tip:setVisible(true)
	else
		self.page_btn1_tip:setVisible(false)
	end
end

function meta:RegisterEvent()
	--删除好友
	self:RegisterGraphic("delete_friend_list",function (user_id)
		local list = {}
		list = friend_logic.friend_list
		for k,v in pairs(list) do
			if v.user_id == user_id then
				table.remove(list,k)
			end
		end
		friend_logic.friend_list = {}
		friend_logic:FriendListSort(list)
		self:ShowFriendList(list)
	end)
	--刷新好友信息
	self:RegisterGraphic("req_friend_list",function (friend_list)
			self:ShowFriendList(friend_list)
	end)
	--通知动画
	self:RegisterGraphic("have_information_word",function (the_bool)
		self:HaveInformation(the_bool)
	end)
	-- 有聊天信息
	self:RegisterGraphic("have_chat_word",function (the_bool)
		self:HaveChatInformation(the_bool)
	end)
	--hide
	self:RegisterGraphic("remove_node_tip",function ()
		self:HaveChatInformation(false)
	end)
	--判断玩家是否在线做出显示更改
	self:RegisterGraphic("change_item_state",function(user_id,result)
		if result == "user_not_online" then
			local list = {}
			list = friend_logic.friend_list
			for k,v in pairs(list) do
				if v.user_id == user_id then
					v.status = FRIEND_STATUS.offline
				end
			end
			self:DispatchGraphicEvent("req_friend_list",list)
		else
			local list = {}
			list = friend_logic.friend_list
			for k,v in pairs(list) do
				if v.user_id == user_id then
					if result == "user_is_fighting" then
						v.status = FRIEND_STATUS.fighting
					elseif result == "friend_is_inviting" then
						v.status = FRIEND_STATUS.inviting
						-- elseif result == ""
					end
				end
			end
			self:ShowFriendList(list)
		end
		self:DispatchGraphicEvent("show_message", result)
	end)

end
function meta:RegisterWidgetEvent()
	--关闭按钮
	ui_helper:AddClick(self.close_btn,function()

		if self.page_btn1_tip:isVisible() == false and self.message_tip:isVisible() == false then
			self:DispatchGraphicEvent("refresh_new_friendtip", false)
		else
			self:DispatchGraphicEvent("refresh_new_friendtip", true)
		end

		self:DispatchGraphicEvent("pop_world_panel")
	end)
	--添加好友按钮
	ui_helper:AddClick(self.add_friend_btn,function()
		self:DispatchGraphicEvent("show_add_friend")
	end)
	--通知按钮
	ui_helper:AddClick(self.message_btn,function()
		friend_logic:ReqFriendAddList()
		self:DispatchGraphicEvent("show_friend_message_panel")
		self:DispatchGraphicEvent("have_information_word",false)
	end)
	--编辑按钮
	ui_helper:AddClick(self.setting_btn,function()
		if self.is_setting ==false then
			ui_helper:SetTextByKey(self.setting_btn:getChildByName("desc"), "battle_exit_confirm") --确定
			self.is_setting = true
			--很多按钮禁用
			self.message_btn:setEnabled(false)
			self.add_friend_btn:setEnabled(false)
		else
			ui_helper:SetTextByKey(self.setting_btn:getChildByName("desc"), "friend_setting_desc") --编辑
			--按钮可点击
			self.is_setting = false
			self.message_btn:setEnabled(true)
			self.add_friend_btn:setEnabled(true)
		end
		self:ShowFriendList(friend_logic.friend_list)
	end)
	--点击自己名字跳转好友排行
	ui_helper:AddClick(self.player_ladder_info_btn, function ()
		rank_logic:SetRankType("friend_elo")
		rank_logic:QueryRank()
	end)

end
return meta
