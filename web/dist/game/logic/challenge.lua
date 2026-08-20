
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
	--初始化基本数据
	-- self.challenge_command_queue={}
	-- self.challenge_winner = {}
	-- self.challenge_loser = {}

	-- 是否请求过数据
	self.is_full_data = false

	self:RegisterMsgHandler()
end
-- 获取对战信息
function meta:DoReceive()
    network:Send("receive_mail_attachment", mail_id, function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end

        local update_mail = recv_msg.update_mail
        local reward_list = recv_msg.reward_list or {}
        self:SetMailById(update_mail.mail_id, update_mail)
        if #reward_list > 0 then
            graphic:DispatchEvent("push_world_panel", "chest", "open_chest_panel", reward_list)
        end
        if complate_func then
            complate_func()
        end
    end)
end

--设置参加玩家的属性
function meta:SetPlayer()
	-- body
end
function meta:ReconnectRoom()
	-- body
	network:Send("query_reconnect_challenge_info", function (result, recv_msg)
			if result == "success" then
				self.room_number = recv_msg.number
				self.room_list = recv_msg.room_info
				graphic:DispatchEvent("push_world_panel", "challenge", "challenge_create_panel")
				graphic:DispatchEvent("refresh_challenge_panel", self.room_number, self.room_list,true)
			end
   		end)
end
function meta:Query() --参加比赛
	-- body
	if self.is_full_data == false then
		network:Send("query_challenge_info", function (result, recv_msg)
			if result ~= "success" then
				graphic:DispatchEvent("show_message", result)
				return
			end
			for k,v in pairs(recv_msg) do
				self[k] = v
				self.cup_num = v
			end
			self.is_full_data = true
  			graphic:DispatchEvent("push_world_panel", "challenge", "challenge_create_panel")
   		end)
	else
		graphic:DispatchEvent("push_world_panel", "challenge", "challenge_create_panel")
	end

end
function meta:CreateRoom() --创建房间
	-- body
	network:Send("req_create_challenge", { rule = 4 },function (result,recv_msg)
		if result == "success" then
			self.room_number = recv_msg.number
			self.room_list = recv_msg.room_info  --{{user_id=,user_name,status,cup_num},}
			graphic:DispatchEvent("refresh_challenge_panel", self.room_number, self.room_list)
		else
			graphic:DispatchEvent("show_message", result)
		end
		-- body
	end)

end
--加入房间
function meta:JoinRoom(room_number)
	-- body

	network:Send("req_join_challenge",{ number = room_number },function (result,recv_msg)

		if result == "success" then
			self.room_number = recv_msg.number
			self.room_list = recv_msg.room_info
			graphic:DispatchEvent("refresh_challenge_panel", self.room_number, self.room_list)
		else
			graphic:DispatchEvent("show_message", result)
		end
	end)

end
--请求开站
function meta:StartBattle()
	-- body
	network:Send("req_start_battle",function (result,recv_msg)
		if result == "success" then
		end
		-- body
	end)
end
--退出战斗进入等待状态
function meta:BattleWait( )
	-- body
	network:Send("req_wait_battle",function (result,recv_msg)
		if result == "success" then
			graphic:DispatchEvent("back_challenge_panel")
			if recv_msg then
				self.room_number = recv_msg.number
				self.room_list = recv_msg.room_info
				graphic:DispatchEvent("refresh_challenge_panel", self.room_number, self.room_list)

			end
		else
			-- print("等待失败")
		end
		-- body
	end)
end

--退出房间
function meta:ExitRoom(flag)

	if flag ==  false then --还未创建房间
		graphic:DispatchEvent("pop_world_panel")
	elseif  flag == true  then		--创建房间后的退出
		network:Send("req_exit_challenge",function (result,recv_msg)
			if result == "success" then
				self.room_number = nil
				self.room_list = nil
			end
		end)
	end
end

-- 注册网络事件 --自动推送
function meta:RegisterMsgHandler()

	-- 约战信息更新
	network:RegisterCommand("update_challenge_info", function (recv_msg)
		for k,v in pairs(recv_msg) do
			self[k] = v
		end
	end)

    -- 房间信息更新
    network:RegisterCommand("ret_challenge_info", function (recv_msg)  --信息的更新
    	self.room_number = recv_msg.number
		self.room_list = recv_msg.room_info
        graphic:DispatchEvent("refresh_challenge_panel", self.room_number, self.room_list)
    end)
end

return meta
