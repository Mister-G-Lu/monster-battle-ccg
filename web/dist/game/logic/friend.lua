
local network = require "manager.network"
local ui_helper = require "manager.ui_helper"
local global = require "manager.global"
local graphic = require "manager.graphic"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"
local user_logic = require "logic.user"
local chat_logic = require "logic.chat"
local arena_logic = require "logic.arena"
local constants = require "common.constants"
local text_loader = require "manager.text_loader"
local FRIEND_STATUS = constants.FRIEND_STATUS
local meta = {}

function meta:Init()
	self.friend_list = {}
	self.chat_with_me = {}
	self.have_inform = false
	self.refuse_id = 0
	self.can_be_added = true
	self.not_online_user_id = 0
	self.online_user_id = 0
	self.notice = nil
	self:RegisterMsgHandler()
	self.rank = 0
end

function meta:Query()
	self.friend_list= {}
	network:Send("req_friend_list", function (result, recv_msg)
		if result == "success" then
			local friend_list = recv_msg
			local new_friend_list = {}
			if friend_list  then
				self:FriendListSort(friend_list)
				graphic:DispatchEvent("req_friend_list",self.friend_list)
			else
				local friend_list = {}
				graphic:DispatchEvent("req_friend_list",friend_list)
			end
			graphic:DispatchEvent("push_world_panel", "friend", "friend_list_panel")

		else
			graphic:DispatchEvent("show_message", result)
		end
	end)
end

function meta:FriendListSort(friend_list)
	local fighting_list = {}
	local offline_list = {}
	local online_list = {}
	-- dump("friend_list",friend_list)
	for k,v in pairs (friend_list) do
		if v.status == FRIEND_STATUS.offline then
			table.insert(offline_list,v)
		elseif v.status == FRIEND_STATUS.online then
			table.insert(online_list,v)
		else
			table.insert(fighting_list,v)
		end
	end

	for k,v in pairs(online_list) do
		table.insert(self.friend_list,v)
	end
	for k,v in pairs(fighting_list) do
		table.insert(self.friend_list,v)
	end
	for k,v in pairs(offline_list) do
		table.insert(self.friend_list,v)
	end 
end

function meta:FriendrankSort(friend_list)
	local friend_rank_list = {}
	local user_info = {}
	user_info.user_id = user_logic.user_id
	user_info.elo_value = arena_logic.elo_value
	for k,v in pairs (friend_list) do
		friend_rank_list[k] = v
	end
	table.insert(friend_rank_list,user_info)
	table.sort(friend_rank_list,function (a,b)
		local aElo = tonumber(a.elo_value)
		local bElo = tonumber(b.elo_value)
		return aElo > bElo
	end)
	for k,v in pairs(friend_rank_list) do
		if user_logic.user_id == v.user_id then
			self.rank = k
			return k
		end
	end
end

--搜索好友
function meta:ReqFriendSearch(user_id)
	network:Send("req_friend_search",{ user_id = user_id },function (result,recv_msg)
		graphic:DispatchEvent("show_search_result",result,recv_msg)
	end)
end

--添加好友
function meta:ReqFriendAdd(user_id)
	network:Send("req_friend_add",{ user_id = user_id },function (result,recv_msg)
		if result == "success" then
			graphic:DispatchEvent("show_message", "send_add_friend_success") --发送添加好友成功
			graphic:DispatchEvent("refresh_friend_add")
		else
			graphic:DispatchEvent("show_message", result)
		end
	end)
end
--删除好友
function meta:ReqDeletFriend(user_id) 
	network:Send("ret_friend_be_unfriended",{ user_id = user_id },function (result,recv_msg)
		if result == "success" then
			graphic:DispatchEvent("show_message", "delete_friend_success") --删除好友成功
			graphic:DispatchEvent("delete_friend_list",user_id)
		else
			graphic:DispatchEvent("show_message", result)
		end
	end)
end
--通知界面
function meta:ReqFriendAddList()
	network:Send("req_friend_add_list",function (result, recv_msg)
		if result == "success" then
			if recv_msg.add_list then
				graphic:DispatchEvent("refresh_friend_add_list",recv_msg.add_list,recv_msg.can_be_added)
			end
		else
			graphic:DispatchEvent("show_message", result)
		end
   	end)
end
-- 设置接受或者不接受申请
function meta:ReqFriendAddListOrNo()
	network:Send("req_friend_added_or_not",{state = self.can_be_added},function (result, recv_msg)
   	end)
end
-- 通知 接受好友邀请
function meta:ReqFriendAddAccept(user_id)
	network:Send("req_friend_add_accept",{ user_id = user_id },function (result,recv_msg)
		if result == "success" then
			graphic:DispatchEvent("show_message", "add_friend_success") --添加好友成功
			graphic:DispatchEvent("processing_invitation_message", recv_msg.user_id)
			table.insert(self.friend_list,recv_msg)
			local friend_list = self.friend_list
			self.friend_list = {}
			self:FriendListSort(friend_list)
			graphic:DispatchEvent("req_friend_list",self.friend_list)
		else
			graphic:DispatchEvent("show_message", result)
		end
	end)
end
-- 通知 拒绝好友邀请
function meta:ReqFriendAddRefuse(user_id)
	self.refuse_id = user_id
	network:Send("req_friend_add_refuse",{ user_id = user_id },function (result,recv_msg)
		if result == "success" then
			graphic:DispatchEvent("show_message", "refuse_friend_success") --拒绝添加好友成功
			graphic:DispatchEvent("processing_invitation_message",self.refuse_id)
		else
			graphic:DispatchEvent("show_message", result)
		end
	end)
end
-- 好友排序
function meta:GetNewFriendList(friend_list )
	table.sort(friend_list,function (a,b)
		if a.status == FRIEND_STATUS.offline then
			if b == FRIEND_STATUS.offline then
				return a.status > b.status
			else
				return a.status > b.status
			end
		else
			if b == FRIEND_STATUS.offline then
				return a.status > b.status
			else
				return a.status < b.status
			end
		end
	end)
	return friend_list
end
--好友切磋
function meta:ReqFriendInviteBattle(user_id)
	self.not_online_user_id = user_id
	self.online_user_id = user_id
	network:Send("req_friend_invite_battle",{ user_id = user_id },function (result,recv_msg)
		if result == "success" then
			local function nofity_func()
                self:ReqRefuseFriendPvp()
            end
            for k,v in pairs(self.friend_list) do
				if v.user_id == self.online_user_id then
					v.status = FRIEND_STATUS.online
				end
			end
			graphic:DispatchEvent("req_friend_list",self.friend_list)
			
			local title = text_loader:GetText("invited_fight_msgbox_title")
			local desc = text_loader:GetText("battle_with_friend")
			local button_text = text_loader:GetText("friend_fightbtn_cancel")

			graphic:DispatchEvent("show_nofity_box",title,desc,button_text,nofity_func)
		else
			graphic:DispatchEvent("change_item_state",self.not_online_user_id,result)
		end
	end)
end

--拒绝或取消好友切磋
function meta:ReqRefuseFriendPvp(user_id)
	network:Send("req_friend_cancel_invite",{},function (result, recv_msg)
			if result == "success" then
				graphic:DispatchEvent("pop_world_panel","common", "confirm_box")
			else
				graphic:DispatchEvent("show_message", result)
			end
   	end)
end
--接受 切磋
function meta:ReqAcceptFriendPvp()
	network:Send("ret_friend_accept_invite",{},function (result, recv_msg)
			if result == "success" then

			else
				graphic:DispatchEvent("show_message", result)
			end
   	end)	
end

function meta:friend_attachment()
	network:RegisterCommand("ret_friend_attachment", function (recv_msg)
        if recv_msg then
            self.friendtip_show = true
        else
            self.friendtip_show = false
        end
        graphic:DispatchEvent("refresh_new_friendtip", friend_logic.friendtip_show)
    end)
end

--接受服务端推送
function meta:RegisterMsgHandler()

    network:RegisterCommand("ret_friend_attachment", function (recv_msg)
    	self.notice = recv_msg
    	if recv_msg then
    		self.friendtip_show = true
    	else
    		self.friendtip_show = false
    	end
    	graphic:DispatchEvent("refresh_new_friendtip", self.friendtip_show) --这个是主界面的提示显示
    	if recv_msg.attachment_type ==  FRIEND_STATUS.friend_chat_attachment  then
    		local have_chat = true
    		graphic:DispatchEvent("have_chat_word",have_chat)
    		self.chat_with_me[recv_msg.user_id] =  1
    		graphic:DispatchEvent("refresh_chattip_show",recv_msg.user_id) --这个是好友列表里面的消息显示
    	else
    		self.have_inform = true
    		graphic:DispatchEvent("have_information_word",self.have_inform) --这个是通知消息显示
    	end
    end)

    --推送拒绝或取消切磋
    network:RegisterCommand("ret_friend_cancel_invite", function (recv_msg)  
		if recv_msg  then
			local function confirm_func()
                self:ReqRefuseFriendPvp()
            end
           	local title = text_loader:GetText("invited_fight_msgbox_title")
			local desc = ""

			local button_text = text_loader:GetText("filter_open_desc")

			if recv_msg.is_refuse == true then
				desc = text_loader:GetText("invited_fight_msgbox_response",recv_msg.user_name)
			else
				desc = text_loader:GetText("arena_fight_msgbox_cancel",recv_msg.user_name)
			end

			graphic:DispatchEvent("show_nofity_box",title,desc,button_text,confirm_func)
		end
    end)
    --推送好友切磋
    network:RegisterCommand("ret_friend_invite_battle",function(recv_msg)
    	if recv_msg then
    		local function confirm_func()
                self:ReqAcceptFriendPvp()
            end
            local function cancel_func()
                self:ReqRefuseFriendPvp()
            end
            local title = text_loader:GetText("invited_fight_msgbox_title")
			local desc = text_loader:GetText("invited_battle_with_friend",recv_msg.user_name)
			local confirm_button_text = text_loader:GetText("invited_fight_msgbox_confirm")
			local cancel_button_text = text_loader:GetText("invited_fight_msgbox_cancel")

    		graphic:DispatchEvent("show_confirm_box",title,desc,confirm_button_text,cancel_button_text,confirm_func,cancel_func)
    	end
    end)
end

return meta
