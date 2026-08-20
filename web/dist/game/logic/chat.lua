
local network = require "manager.network"
local ui_helper = require "manager.ui_helper"
local global = require "manager.global"
local graphic = require "manager.graphic"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"
local user_logic = require "logic.user"
--local battle_logic = require "logic.battle"


local meta = {}

--初始化
function meta:Init()
	
	self.chatdata = {}
	-- 是否请求过数据
	self.is_full_data = false --是否请求过数据
	self.not_online_user_id = 0
	self:RetFriendCancelInvite()
end
--好友列表主界面
function meta:Query(chat_type,friend_table) --请求聊天列表
		self.friend_id =  friend_table.user_id
		local user_id = friend_table.user_id
		self.not_online_user_id = friend_table.user_id
		network:Send("req_chat_info",{ chat_type = chat_type,target_id = user_id }, function (result, recv_msg)
			if result == "success" then
				local chat_type = chat_type							
				if not self.chatdata[user_id] then
					self.chatdata[user_id] = {}
				end
				local such_chat ={}
				if recv_msg then
					such_chat = self.chatdata[user_id]
					for k,v in pairs(recv_msg) do
						v.user_id = user_id
						table.insert(such_chat,v)
					end
				end
				local chat_friend = friend_table
				graphic:DispatchEvent("push_world_panel", "friend", "friend_chat_panel")
				if chat_friend  then
					graphic:DispatchEvent("refresh_chat_panel",chat_friend,chat_type,such_chat)
				end	
			else
				graphic:DispatchEvent("change_item_state",self.not_online_user_id,result)
			end
					
   		end)

end
function meta:ReqChatSay(chat_type,chat_friend,chat_word) --请求说话
	-- body
	local chat_id = chat_friend.user_id
	network:Send("req_chat_say",{ chat_type = chat_type,target_id = chat_id,content = chat_word }, function (result, recv_msg)
			if result == "success" then
				if chat_id then
					local user_id = user_logic.user_id
					local uer_and_friendid = user_id..chat_id
					if not self.chatdata[user_id] then
						self.chatdata[user_id] = {}
					end					
					local such_chat = self.chatdata[user_id]
					table.insert(such_chat,{user_id = user_id,content = chat_word})
					graphic:DispatchEvent("add_chat_word",chat_word,uer_and_friendid)
				end
			else

				graphic:DispatchEvent("show_message", result)
			end		
	end)
end
function meta:ReqChatClose(user_id,chat_type) --关闭聊天
	
	network:Send("req_chat_close",{ chat_type = chat_type,target_id = user_id },function (result,recv_msg)
		if result == "success" then
			graphic:DispatchEvent("pop_world_panel")
		else
			graphic:DispatchEvent("show_message", result)
		end
	end)
end
--推送消息
function meta:RetFriendCancelInvite()
	-- body
	network:RegisterCommand("ret_chat_info", function (recv_msg)  --信息的更新
		if recv_msg  then
			local content = recv_msg.content
			graphic:DispatchEvent("add_friendchat_word",content) --根据推送消息获得好友聊天加到列表中
		end
    end)
end

return meta
