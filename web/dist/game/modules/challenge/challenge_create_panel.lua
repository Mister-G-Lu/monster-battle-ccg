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
local CHALLENGE_STATUS = constants.CHALLENGE_STATUS

local meta = class("challenge_create_panel",function (node)
    return ui_helper:LoadCocosUI("interface/world/friendfight_panel.csb")
end)
local MAX_ITEM_NUM = 4

function meta:ctor( )
    local root = self:getChildByName("msgbox")
    self.root = root

    --返回
    self.back_btn = root:getChildByName("close_btn")
    --房间名bg
    self.titlebg = root:getChildByName("titlebg")
    self.challenge_title = self.titlebg:getChildByName("title") --房间名
    ui_helper:SetTextByKey(self.challenge_title, "challenge_room_name")

    --创建房间界面
    self.step_one = root:getChildByName("step1")
    --获得冠军次数
    self.champion_desc = self.step_one:getChildByName("champion_desc") --文本
    --次数
    self.champion_value = self.step_one:getChildByName("champion_value") --fnt 字体 次数

    --输入房间
    self.room_id_find =self.step_one:getChildByName("textfield")
    self.editbox = ui_helper:ReplaceEditBox(self.room_id_find)
    self.editbox:setInputFlag(cc.EDITBOX_INPUT_FLAG_INITIAL_CAPS_ALL_CHARACTERS)
    self.editbox:setInputMode(cc.EDITBOX_INPUT_MODE_SINGLELINE)

    --加入比赛按钮
    self.enter_btn = self.step_one:getChildByName("enter_btn")
    --创建比赛房间
    self.create_btn = self.step_one:getChildByName("create_btn")

    --b绑定占位符号
    -- local Text = ccui.Text:create()
    -- Text:setPosition(cc.p(display.cx,display.cy))
    -- self:addChild(Text)
    -- Text:setVisible(false)
    -- ui_helper:SetTextByKey(Text, "input_room_num") --请输入房间编号
    -- local text = Text:getString()
    self.editbox:setPlaceHolder(text_loader:GetText("input_room_num"))

    local setp_two = root:getChildByName("step2")
    self.setp_two = setp_two
    --退出比赛房间
    self.exit_btn = setp_two:getChildByName("copy_btn")
    self.item_node_list = {}
    for i=1,MAX_ITEM_NUM do
        local slot = setp_two:getChildByName("slot"..i) --每一栏内容
        local slot_bg = slot:getChildByName("bg")      --背景
        slot_bg:setColor(ui_helper:GetColor4B(0xB39F7E))
        local empty_txt = slot:getChildByName("empty") --等待玩家
        ui_helper:SetTextByKey(empty_txt, "wait_for_people")  --等待玩家
        local enter_node = slot:getChildByName("enter_node") --玩家信息
        local node_name = enter_node:getChildByName("name") --玩家name
        node_name:setVisible(false)
        local node_champion_value = enter_node:getChildByName("champion_value") -- 玩家奖杯数
        node_champion_value:setVisible(false)
        local node_champion_icon = enter_node:getChildByName("champion_icon") --奖杯
        node_champion_icon:setVisible(false)
        local node_fight_desc = enter_node:getChildByName("fight_desc")
        node_fight_desc:setVisible(false)
        local node_icon = enter_node:getChildByName("icon") --准备状态
        node_icon:setVisible(false)
        self.item_node_list[i] = {
            slot = slot,
            slot_bg = slot_bg,
            empty_txt = empty_txt,
            enter_node =enter_node,
            node_name = node_name,
            node_champion_value= node_champion_value,
            node_champion_icon = node_champion_icon,
            node_fight_desc = node_fight_desc,
            node_icon = node_icon
        }
    end

    self.exit_btn:setEnabled(true)
    self.back_btn:setEnabled(true)

    self:CreateRoom()
    self:RegisterWidgetEvent()
    self:RegisterEvent()
end
--创建房间
function meta:CreateRoom()
    self.CreateRoom = 1
    self.step_one:setVisible(true)
    self.setp_two:setVisible(false)
    local champion_value = challenge_logic.cup_num
    self.champion_value:setString(champion_value)

    self.editbox:didNotSelectSelf()
    self.editbox:setString("")
    -- local function _text_field_event(sender,eventType)
    --     if eventType == ccui.TextFiledEventType.attach_with_ime then

    --     elseif eventType == ccui.TextFiledEventType.detach_with_ime then

    --     elseif eventType == ccui.TextFiledEventType.insert_text then
    --         self.room_id_num  = self.room_id_find:getString()
    --         local n = tonumber(self.room_id_num)
    --         if n then
    --         else
    --             self.room_id_num = nil
    --             self.room_id_find:setString("")
    --         end
    --     end
    -- end
    -- self.room_id_find:addEventListener(_text_field_event)
    
    --注册键盘事件
    local function _on_key_pressed(keycode,event)
    end
    local keyListener = cc.EventListenerKeyboard:create()
    keyListener:registerScriptHandler(_on_key_pressed, cc.Handler.EVENT_KEYBOARD_PRESSED)
    local eventDispatcher = self:getEventDispatcher()
    eventDispatcher:addEventListenerWithSceneGraphPriority(keyListener, self)
end
--初始化房间
function meta:RoomInit()
    -- body
    for i = 1, 4 do  --初始化到等待玩家状态
        self.item_node_list[i].slot_bg:setColor(ui_helper:GetColor4B(0xB39F7E))
        self.item_node_list[i].empty_txt:setVisible(true) --等待玩家字体隐藏
        ui_helper:SetTextByKey(self.item_node_list[i].empty_txt, "wait_for_people")
        self.item_node_list[i].node_name:setVisible(false)--玩家名字输入
        self.item_node_list[i].node_champion_value:setVisible(false)--玩家奖牌个数
        self.item_node_list[i].node_champion_icon:setVisible(false)
        self.item_node_list[i].node_fight_desc:setVisible(false) --对战中隐藏
        self.item_node_list[i].node_icon:setVisible(false) --准备标志可鉴
    end
end
function meta:RoomShow(number,challenge_list) -- 1 到 4个

    self.CreateRoom = 2
    self.index_num = #challenge_list
    self.step_one:setVisible(false)
    self.setp_two:setVisible(true)

    self:RoomInit()--每次刷新列表
    self.room_number = number
    ui_helper:SetTextByKey(self.challenge_title, "challenge_room_number",self.room_number) --编号 ％d 房间
    -- self.challenge_title:setString("编号"..number.."房间")
    local Text_my = ccui.Text:create()
    Text_my:setPosition(cc.p(0,0))
    self:addChild(Text_my)
    Text_my:setVisible(false)
    ui_helper:SetTextByKey(Text_my, "this_is_me") --这是我
    local text = Text_my:getString()

    for i,v in pairs(challenge_list) do

        local status = tonumber(challenge_list[i].status) --challenge_list[i].status
        if status == CHALLENGE_STATUS.wait then  --准备状态
            self.item_node_list[i].slot_bg:setColor(ui_helper:GetColor4B(0x77A01C))
            self.item_node_list[i].empty_txt:setVisible(false) --等待玩家字体隐藏

            self.item_node_list[i].node_name:setString(challenge_list[i].user_name.."#"..challenge_list[i].user_id) --玩家名字输入
            if user_logic.user_id == challenge_list[i].user_id then
                self.item_node_list[i].node_name:setString(challenge_list[i].user_name.."#"..challenge_list[i].user_id..text) --玩家名字输入
            end
            self.item_node_list[i].node_name:setVisible(true)
            self.item_node_list[i].node_champion_value:setString(challenge_list[i].cup_num) --玩家奖牌个数
            self.item_node_list[i].node_champion_value:setVisible(true)
            self.item_node_list[i].node_champion_icon:setVisible(true)
            self.item_node_list[i].node_fight_desc:setVisible(false) --对战中隐藏
            self.item_node_list[i].node_icon:setVisible(true) --准备标志可鉴
        elseif status == CHALLENGE_STATUS.fight then -- 对战状态
            self.item_node_list[i].slot_bg:setColor(ui_helper:GetColor4B(0x77A01C))
            self.item_node_list[i].empty_txt:setVisible(false) --等待玩家字体显示
            self.item_node_list[i].node_name:setString(challenge_list[i].user_name.."#"..challenge_list[i].user_id) --玩家名字输入
            if user_logic.user_id == challenge_list[i].user_id then
                self.item_node_list[i].node_name:setString(challenge_list[i].user_name.."#"..challenge_list[i].user_id..text) --玩家名字输入
            end
            self.item_node_list[i].node_name:setVisible(true)
            self.item_node_list[i].node_champion_value:setString(challenge_list[i].cup_num) --玩家奖牌个数
            self.item_node_list[i].node_champion_value:setVisible(true)
            self.item_node_list[i].node_champion_icon:setVisible(true)
            self.item_node_list[i].node_fight_desc:setVisible(true) --对战中隐藏
            ui_helper:SetTextByKey(self.item_node_list[i].node_fight_desc, "in_the_battle")  --对战中
            self.item_node_list[i].node_icon:setVisible(false) --准备标志隐藏
        elseif status == CHALLENGE_STATUS.die then --淘汰状态 玩家信息是不显示的
            self.item_node_list[i].slot_bg:setColor(ui_helper:GetColor4B(0xC3482E)) --变成红色
            self.item_node_list[i].empty_txt:setVisible(true) --等待玩家字体隐藏
            ui_helper:SetTextByKey(self.item_node_list[i].empty_txt, "fail_the_battle")  --等待玩家
            self.item_node_list[i].node_name:setString(challenge_list[i].user_name.."#"..challenge_list[i].user_id) --玩家名字输入
            if user_logic.user_id == challenge_list[i].user_id then
                self.item_node_list[i].node_name:setString(challenge_list[i].user_name.."#"..challenge_list[i].user_id..text) --玩家名字输入
            end
            self.item_node_list[i].node_name:setVisible(false)
            self.item_node_list[i].node_champion_value:setString(challenge_list[i].cup_num) --玩家奖牌个数
            self.item_node_list[i].node_champion_value:setVisible(false)
            self.item_node_list[i].node_champion_icon:setVisible(false)
            self.item_node_list[i].node_fight_desc:setVisible(false) --对战中隐藏
            self.item_node_list[i].node_icon:setVisible(false) --准备标志隐藏

        end
    end
end
function meta:Show()
    self.CreateRoom = 1
    self.champion_value:setString(challenge_logic.cup_num)
    ui_helper:SetTextByKey(self.challenge_title, "challenge_room_name")
    self.step_one:setVisible(true)
    self.setp_two:setVisible(false)
    self:setVisible(true)
    self.editbox:setString("")  --初始化查找区域
end
function meta:Hide()
    self:setVisible(false)
end
function meta:RegisterEvent()

    graphic:RegisterEvent("Reconnect_the_room",function (number_number,room_list)
        -- body
        ui_helper:LoadCocosUI("interface/world/friendfight_panel.csb")
        graphic:DispatchEvent("refresh_challenge_panel", room_number, room_list)


    end)
    graphic:RegisterEvent("refresh_challenge_panel", function (number,list,is_reconnect)

        self.exit_btn:setEnabled(true)
        self.back_btn:setEnabled(true)
        local wait  = 0
        local die = 0
        local mystatus,mycupnum
        for i=1,#list do
            local status = tonumber(list[i].status)
            if status == CHALLENGE_STATUS.wait then
                wait = wait + 1  -- 参赛人数
            end
            if list[i].user_id == user_logic.user_id then
                mystatus = status
                mycupnum = list[i].cup_num
            end
            if status ==  CHALLENGE_STATUS.die then
                die = die + 1
            end
        end
        if mystatus == CHALLENGE_STATUS.die then

            challenge_logic:ExitRoom(true)
            self:Show()
            self.is_paozi =  0 --失败
            return
        elseif mystatus ==CHALLENGE_STATUS.wait then
            self.is_paozi =  1  --赢啦半决赛
            if die == 3 then
                self.is_paozi =  2  --冠军

            end

        end
        if wait == 1 and mycupnum ~= challenge_logic.cup_num then
            challenge_logic.cup_num = mycupnum
        end
        if self.is_paozi == 2 then

            if is_reconnect then
                graphic:DispatchEvent("back_challenge_panel")
            end
            return

        end
        self:RoomShow(number,list)


        if wait == 4 or (#list==4 and wait==2) then
            local start_id
            for i=1,#list do
                local status = tonumber(list[i].status)
                if status == CHALLENGE_STATUS.wait then
                    start_id = list[i].user_id
                    break
                end
            end
            -- if user_logic.user_id == start_id then
            --  challenge_logic:StartBattle()
            -- end
            self.exit_btn:setEnabled(false)
            self.back_btn:setEnabled(false)
        end
    end)


    graphic:RegisterEvent("challenge_match_success",function (callback)
        -- body
        local delaytime = cc.DelayTime:create(1)
        local func = cc.CallFunc:create(function ()
            graphic:DispatchEvent("show_message", "the_countdown_began")  -- 倒计时开始

        end)
        local delaytime1 = cc.DelayTime:create(1)
        local func1 = cc.CallFunc:create(function ()
            graphic:DispatchEvent("show_message", "the_countdown_numer3")  -- 倒计时开始
        end)
        local delaytime2 =cc.DelayTime:create(1)
        local func2 = cc.CallFunc:create(function( )
            -- body
            graphic:DispatchEvent("show_message", "the_countdown_numer2")  -- 倒计时开始
        end)
        local delaytime3 = cc.DelayTime:create(1)
        local func3 = cc.CallFunc:create(function()
            -- body
            graphic:DispatchEvent("show_message", "the_countdown_numer1")  -- 倒计时开始


        end)
        local delaytime4 = cc.DelayTime:create(0.5)
        local func4 = cc.CallFunc:create(function()
            callback()

        end)

        local seq = cc.Sequence:create(delaytime,func,delaytime1,func1,delaytime2,func2,delaytime3,func3,delaytime4,func4)
        self:runAction(seq)


    end)

    graphic:RegisterEvent("back_challenge_panel", function ()
        if self.is_paozi == 1 then
            --此处飘胜利的字
            local delaytime1 = cc.DelayTime:create(1)
            local func1 = cc.CallFunc:create(function ()
                graphic:DispatchEvent("show_message", "win_the_semifinals")  --恭喜您赢得半决赛
            end)
            local seq = cc.Sequence:create(delaytime1,func1)
            self:runAction(seq)

        elseif self.is_paozi == 0 then

            local delaytime1 = cc.DelayTime:create(1)
            local func1 = cc.CallFunc:create(function ()
                graphic:DispatchEvent("show_message", "you_are_lose")  --       抱歉您失败啦
            end)
            local seq = cc.Sequence:create(delaytime1,func1)
            self:runAction(seq)
        else
            self:Show()
            challenge_logic:ExitRoom(true)

            local delaytime1 = cc.DelayTime:create(1)
            local func1 = cc.CallFunc:create(function ()
                graphic:DispatchEvent("show_message", "you_are_win")  --    恭喜您获得胜利
            end)
            local seq = cc.Sequence:create(delaytime1,func1)
            self:runAction(seq)

        end
        self.is_paozi = nil
    end)
end
function meta:RegisterWidgetEvent()
    -- body
    ui_helper:AddClick(self.create_btn, function () --print("创建比赛房间")

        challenge_logic:CreateRoom()
    end)
    ui_helper:AddClick(self.back_btn, function ()--print("退出比赛")

        if self.CreateRoom == 2  then
            -- 弹出窗口。。。。
            local title = text_loader:GetText("challenge_prompt") --约战退出提示框？
            local desc = text_loader :GetText("challenge_prompt_txt")  --确定推出约战吗？
            local confirm_txt = text_loader:GetText("common_confirm")  --确定
            local cancel_txt =text_loader:GetText("common_cancel")    --取消
            graphic:DispatchEvent("show_confirm_box", title, desc, confirm_txt, cancel_txt, function ()
                graphic:DispatchEvent("pop_world_panel")
                --有弹窗啊啊啊创建
                challenge_logic:ExitRoom(true)  --创建房间啦
                graphic:DispatchEvent("pop_world_panel")
            end, function ()
                graphic:DispatchEvent("pop_world_panel")
            end)
        elseif  self.CreateRoom == 1 then
            challenge_logic:ExitRoom(false)
        end

    end)
    ui_helper:AddClick(self.exit_btn, function ()--print("退出比赛房间")

        local title = text_loader:GetText("challenge_prompt") --约战退出提示框？
        local desc = text_loader :GetText("challenge_prompt_txt")  --确定推出约战吗？
        local confirm_txt = text_loader:GetText("common_confirm")  --确定
        local cancel_txt =text_loader:GetText("common_cancel")    --取消
        graphic:DispatchEvent("show_confirm_box", title, desc, confirm_txt, cancel_txt, function ()
            graphic:DispatchEvent("pop_world_panel")
            -- 确定
            challenge_logic:ExitRoom(true)  --创建啦房间，没打
            graphic:DispatchEvent("pop_world_panel")
        end, function ()
            graphic:DispatchEvent("pop_world_panel")
        end)
    end)
    ui_helper:AddClick(self.enter_btn, function ()

        local room_number = self.editbox:getString()

        local u = tonumber(room_number)
        if u then

            challenge_logic:JoinRoom(room_number)  --number
        else
            graphic:DispatchEvent("show_message", "please_input_room")  --请输入房间号
        end
    end)
end

return meta
