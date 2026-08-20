local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"

local battle_logic = require "logic.battle"
local user_logic = require "logic.user"
local graphic = require "manager.graphic"
local challenge_logic = require "logic.challenge"
local text_loader = require "manager.text_loader"
local constants = require "common.constants"
local friend_logic = require "logic.friend"
local chat_logic = require "logic.chat"
local FRIEND_STATUS = constants.FRIEND_STATUS
local CHAT_STATUS =constants.CHAT_STATUS

local meta = class("friend_chat_panel",function (node)

    return ui_helper:LoadCocosUI("interface/friend/friend_chat_panel.csb")
end)
function meta:ctor( )

	local root = self:getChildByName("msgbox")
	self.root = root
	self.close_btn = root:getChildByName("close_btn")
	local chat_node = root:getChildByName("chat_node")

	self.name = chat_node:getChildByName("name")
	--滚动容器
	self.scroll_view = chat_node:getChildByName("scroll_view")

	--发送按钮
	self.enter_btn = chat_node:getChildByName("enter_btn")

	--聊天内容
	self.textfield = chat_node:getChildByName("textfield")
	self.editbox = ui_helper:ReplaceEditBox(self.textfield)
    self.editbox:setMaxLength(30)
    self.editbox:setInputFlag(cc.EDITBOX_INPUT_FLAG_INITIAL_CAPS_ALL_CHARACTERS)
	self.editbox:setInputMode(cc.EDITBOX_INPUT_MODE_SINGLELINE)

    print("test test testaaabbbcc")
	-- self.ChatWord = self.textfield:getString()
	-- self.ChatWord = self.editbox:getString()
	--返回按钮
	self.back_btn = chat_node:getChildByName("back_btn")
	--我的聊天
	local my_chat = chat_node:getChildByName("ourside_template")

	self.my_chat = my_chat
	self.my_chat:setVisible(false)
	--他人的聊天
	local friend_chat = chat_node:getChildByName("friend_template")
	self.friend_chat = friend_chat
	self.friend_chat:setVisible(false)

	--b绑定占位符号
    -- local Text = ccui.Text:create()
    -- Text:setPosition(cc.p(display.cx,display.cy))
    -- self:addChild(Text)
    -- Text:setVisible(false)
	-- ui_helper:SetTextByKey(Text, "input_chat_word") --请输入聊天内容占位符
	-- local text = Text:getString()
	-- self.textfield:setPlaceHolder(text)
	-- self.editbox:setPlaceHolder(text)

	self.chat_message = { } --聊天文本存储


	self:ChatWordInit()
	self:RegisterWidgetEvent()
    self:RegisterEvent()
end
function meta:ChatWordInit()
	-- body
	--[[
	local function _text_field_event(sender,eventType)
		if eventType == ccui.TextFiledEventType.attach_with_ime then

		elseif eventType == ccui.TextFiledEventType.detach_with_ime then

		elseif eventType == ccui.TextFiledEventType.insert_text then
			self.ChatWord = self.textfield:getString()
		end
	end

	self.textfield:addEventListener(_text_field_event)
	--]]

	-- local function editboxEventHandler(eventType)
    --     print("eventType = ", eventType)
	-- 	if eventType == "began" then
    --
    -- 	elseif eventType == "ended" then
    --
    -- 	elseif eventType == "changed" then
    -- 	elseif eventType == "return" then
    -- 	end
	-- end
    -- --
	-- self.editbox:registerScriptEditBoxHandler(editboxEventHandler)

end
function meta:RefreshPanel(chat_friend)

	self.user_and_friendid = user_logic.user_id..chat_friend.user_id
	local str = chat_friend.user_name.."#"..chat_friend.user_id
	ui_helper:SetTextByKey(self.name, "friend_chatting_title",str) --确定
	local new_chat_message = {}
	for k,v in pairs(self.chat_message) do
		if v.user_id == self.user_and_friendid or v.user_id ==self.chat_id then
			table.insert(new_chat_message,v)
		end
	end
	self:DealMessage(new_chat_message)

end
--刷新我的聊天列表
function meta:RefreshChatWord(chat_id,chat_word )
	-- body
	self.scroll_view:removeAllChildren()
	local config_message = {}
	config_message["user_id"] = chat_id
	config_message["chat_word"] = chat_word
	table.insert(self.chat_message,config_message)
	local new_chat_message = {}
	for k,v in pairs(self.chat_message) do
		if v.user_id == self.user_and_friendid or v.user_id ==self.chat_id then
			table.insert(new_chat_message,v)
		end
	end
	self:DealMessage(new_chat_message)

end
--聊天信息处理
function meta:DealMessage(chat_message)
	-- body
	local new_message = {}
	local num = #chat_message
	local row = 10
	local max = num/row
	local remainder = num %row
	local max_num = (max-1) * row + max

	if num <= 10 then
		for k,v in pairs(chat_message) do
			table.insert(new_message,v)
		end
	else
		for k,v in pairs(chat_message) do
			if k > max_num then
				table.insert(new_message,v)
			end
		end
	end
	self.new_message = new_message
	local num_new_message = #new_message
	local the_new_message = {}
	for i = 1,num_new_message do
		local the_table = new_message[num_new_message - i + 1]
		table.insert(the_new_message,the_table)
	end
	self:ShowChatWord(the_new_message)
end
--聊天实现
function meta:ShowChatWord(chat_message)

	self.scroll_view:removeAllChildren()
	local size = self.scroll_view:getContentSize()
	self.my_chatlist = {}
	self.other_chatlist = {}
	self.height = {}
	local num = #chat_message
	self.the_chat_posy = 0
	self.new_scroll_size = size.height
	if self.the_chat_posy > size.height then
		local height = size.height + self.the_chat_posy
		self.new_scroll_size = height
		self.scroll_view:setInnerContainerSize({width = 650 ,height = height})
	end

	for k,v in pairs(chat_message) do
		local chat_id = v.user_id
		if chat_id == self.user_and_friendid then
			if self.my_chatlist[k] then
			else
				self.my_chatlist[k] = self.my_chat:clone()
				self.scroll_view:addChild(self.my_chatlist[k])
			end
			self.my_chatlist[k]:setVisible(true)
			local my_desc_txt = self.my_chatlist[k]:getChildByName("desc")
			local chat_word = v.chat_word
			self.height[k] = self:MyChat(my_desc_txt,chat_word,self.my_chatlist[k])
			local height = self.the_chat_posy - self.height[k]
			self.my_chatlist[k]:setPosition(605,self.the_chat_posy - self.height[k])

		elseif chat_id == self.chat_id  then
			if self.other_chatlist[k] then
			else
				self.other_chatlist[k] = self.friend_chat:clone()
				self.scroll_view:addChild(self.other_chatlist[k])
			end
			self.other_chatlist[k]:setVisible(true)
			local other_desc_txt = self.other_chatlist[k]:getChildByName("desc")
			local chat_word = v.chat_word
			self.height[k] = self:OtherChat(other_desc_txt,chat_word,self.other_chatlist[k])
			local height = self.the_chat_posy - self.height[k]
			self.other_chatlist[k]:setPosition(cc.p(0,self.the_chat_posy - self.height[k]))
		end
	end
end
--得到我的聊天信息
function meta:MyChat(my_desc_txt,chat_word,chat_word_bg)

	local max_width  = 400  --设置一个最大宽度
	local content_size = chat_word_bg:getContentSize()
	local my_desc_posY = my_desc_txt:getPositionY()
	--初始化尺寸
	local my_chat_size = my_desc_txt:getContentSize()
	local my_chat_size_height = my_desc_txt:getContentSize().height
	local render = my_desc_txt:getVirtualRenderer()
	render:setDimensions(0,my_chat_size_height)
	ui_helper:SetText(my_desc_txt, chat_word)
	local render = my_desc_txt:getVirtualRenderer()
	local new_size = render:getContentSize()
	local new_width = new_size.width
	if new_width < max_width then
		my_desc_txt:setContentSize({width = new_size.width,height = my_chat_size_height })
	else
		local new_render = my_desc_txt:getVirtualRenderer()
		new_render:setDimensions(max_width,0)
		ui_helper:SetText(my_desc_txt, chat_word)
		local new_render = my_desc_txt:getVirtualRenderer()
		local the_new_size = new_render:getContentSize()
		my_desc_txt:setContentSize({width = max_width,height = the_new_size.height })
	end
	local new_my_chat_size = my_desc_txt:getContentSize()
	local diff_width
	local diff_height
	diff_height = new_my_chat_size.height - my_chat_size.height + 10
	diff_width = new_my_chat_size.width - my_chat_size.width + 36
	if diff_height < 0 then
        return
    end
    -- 修正背景框尺寸
    local new_content_size = { width = 0, height = 0}
    new_content_size["width"] = diff_width + content_size.width - 80
    new_content_size["height"] = diff_height + content_size.height
    chat_word_bg:setContentSize(new_content_size)
    my_desc_txt:setPosition(cc.p(new_content_size.width - 36, my_desc_posY ))

    self.the_chat_posy = self.the_chat_posy + new_content_size.height
    return new_content_size.height
end
--得到他人的聊天信息
function meta:OtherChat(other_desc,chat_word,chat_word_bg)
	local max_width  = 400  --设置一个最大宽度
	local content_size = chat_word_bg:getContentSize()
	local my_desc_posY = other_desc:getPositionY()
	--初始化尺寸
	local my_chat_size = other_desc:getContentSize()
	local my_chat_size_height = other_desc:getContentSize().height
	--print("当前的高度。。"..my_chat_size_height) --36
	local render = other_desc:getVirtualRenderer()
	render:setDimensions(0,my_chat_size_height)
	ui_helper:SetText(other_desc, chat_word)
	local render = other_desc:getVirtualRenderer()
	local new_size = render:getContentSize()
	local new_width = new_size.width
	if new_width < max_width then
		other_desc:setContentSize({width = new_size.width,height = my_chat_size_height })
	else
		local new_render = other_desc:getVirtualRenderer()
		new_render:setDimensions(max_width,0)
		ui_helper:SetText(other_desc, chat_word)
		local new_render = other_desc:getVirtualRenderer()
		local the_new_size = new_render:getContentSize()
		other_desc:setContentSize({width = max_width,height = the_new_size.height })
	end
	local new_my_chat_size = other_desc:getContentSize()
	local diff_width
	local diff_height
	diff_height = new_my_chat_size.height - my_chat_size.height + 10
	diff_width = new_my_chat_size.width - my_chat_size.width + 36
	if diff_height < 0 then
        return
    end
    -- 修正背景框尺寸
    local new_content_size = { width = 0, height = 0}
    new_content_size["width"] = diff_width + content_size.width - 80
    new_content_size["height"] = diff_height + content_size.height
    chat_word_bg:setContentSize(new_content_size)
    other_desc:setPosition(cc.p(new_content_size.width - 36, my_desc_posY))
    self.the_chat_posy = self.the_chat_posy + new_content_size.height
    return new_content_size.height
end
function meta:Show()
	self.editbox:setVisible(true)
	self:setVisible(true)
	friend_logic:ReqFriendAddList()

end
function meta:Hide()
	self.editbox:setVisible(false)
	self:setVisible(false)
end
function meta:RegisterEvent()

	graphic:RegisterEvent("refresh_chat_panel",function (chat_friend,chat_type,chat_content)
		self.chat_type = chat_type
		self.chat_friend = chat_friend
		self.chat_id = chat_friend.user_id
		if chat_friend then
			self:RefreshPanel(chat_friend)
			if chat_content then
				for k,v in pairs(chat_content) do
					local chat_word = v.content
					if chat_word then
						self:RefreshChatWord(self.chat_id,chat_word)
					end
				end

			end
		end

	end)
	graphic:RegisterEvent("add_chat_word",function (chat_word,uer_and_friendid)
		local chat_id = uer_and_friendid
		self:RefreshChatWord(chat_id,chat_word)
	end)
	--	好友消息
	graphic:RegisterEvent("add_friendchat_word",function (chat_word)
		local chat_id = self.chat_id
		if chat_word  then
			self:RefreshChatWord(chat_id,chat_word)
		end
	end)

end
function meta:RegisterWidgetEvent( )
	-- body
	ui_helper:AddClick(self.close_btn, function ()
		chat_logic:ReqChatClose(self.chat_id,self.chat_type)
	end)
	ui_helper:AddClick(self.enter_btn, function ()
		-- local chat_word = self.ChatWord

        local chat_word = self.editbox:getString()
		my_id = user_logic.user_id
		if chat_word == "" then
			graphic:DispatchEvent("show_message", "friend_chatting_emptytext") -- 请输入聊天内容
		else
			chat_logic:ReqChatSay(self.chat_type,self.chat_friend,chat_word)
			-- self.textfield:setString("")
			self.editbox:setString("")

		end
		-- self.ChatWord = ""
		--初始化聊天
	end)
	ui_helper:AddClick(self.back_btn, function ()
		chat_logic:ReqChatClose(self.chat_id,self.chat_type)
		-- graphic:DispatchEvent("pop_world_panel")
	end)


end
return meta
