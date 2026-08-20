local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"
local friend_logic = require "logic.friend"

local constants = require "common.constants"
local data_template = require "manager.data_template"
local FRIEND_STATUS = constants.FRIEND_STATUS
local CHAT_STATUS =constants.CHAT_STATUS
local chat_logic = require "logic.chat"

local meta = class("friend_template",function (node)
    return node
end)

function meta:ctor()

    self.icon = self:getChildByName("icon")  --头像
    self.arena_value = self:getChildByName("arena_value") -- 积分
    self.name = self:getChildByName("name") --好友名字
    self.ladder_desc = self:getChildByName("ladder_desc") --Elo 排名
    self.normal_node = self:getChildByName("the_normal_node") -- 普通节点
    self.chat_btn = self.normal_node:getChildByName("chat_btn") --聊天按钮
    self.fight_btn = self.normal_node:getChildByName("fight_btn") --切磋按钮
    self.fight_btn:setVisible(false)
    self.setting_node = self:getChildByName("the_setting_node") --设置节点
    self.delete_btn = self.setting_node:getChildByName("delete_btn") --删除节点
    self.tipnode = ui_helper:LoadCocosUI("interface/world/newtip.csb")
    self.tipnode:setVisible(false)    
    self.tipnode:setPosition({ x = 55, y = 35})
    self.setting_node:setVisible(false)
    self.arena_value:setString("1")--暂时写死
    self.chat_btn:addChild(self.tipnode)
    self:RegisterEvent()
end
function meta:TipShow(chat_have)
    if chat_have == 1  then
        self.tipnode:setVisible(true)
        self.tipnode:PlayAnimation("loop",true)        
        graphic:DispatchEvent("have_chat_word",true)
    else
        self.tipnode:PlayAnimation("loop",false)
        self.tipnode:setVisible(false)
        graphic:DispatchEvent("have_chat_word",false)
    end
end
-- 设置好友信息
function meta:SetFriendInfo(info)
    self.info = info
    -- 好友消息
    graphic:RegisterEvent("refresh_chattip_show",function (user_id)
        if user_id == self.info.user_id then
            self:TipShow(1)
        end
    end)

    ui_helper:SetText(self.name, info.user_name)--
    
    self.tip_show = friend_logic.chat_with_me[info.user_id] --消息为1 有信息
    self:TipShow(self.tip_show)
    if info.status == FRIEND_STATUS.online then
        ui_helper:SetTextByKey(self.ladder_desc, "people_is_online") -- 在线
    elseif info.status == FRIEND_STATUS.offline then
        ui_helper:SetTextByKey(self.ladder_desc, "people_is_offline") --离线
    elseif info.status == FRIEND_STATUS.fighting then
        ui_helper:SetTextByKey(self.ladder_desc, "people_is_fighting") --战斗中
    elseif info.status == FRIEND_STATUS.matching then
        ui_helper:SetTextByKey(self.ladder_desc, "people_is_matching") -- 匹配中
    elseif info.status == FRIEND_STATUS.inviting then
        ui_helper:SetTextByKey(self.ladder_desc, "people_is_inviting") --邀请中
    end

    if info.status == FRIEND_STATUS.offline then
        self.normal_node:setVisible(false)
        self:setColor(ui_helper:GetColor4B(0x7F7F7F))
        self.fight_btn:setVisible(false)        
    else     
        self.fight_btn:setVisible(true)
        self.normal_node:setVisible(true)
        self:setColor(ui_helper:GetColor4B(0xFFFFFF))
    end 
end
--设置信息状态
function meta:SetStage(stage)
    self.setting_node:setVisible(false)
    self.normal_node:setVisible(false)
    if stage == true then  -- 如果这个状态是编辑状态
        self.setting_node:setVisible(true)
        self.chat_btn:setVisible(false)
    else       
        self.normal_node:setVisible(true)
        self.chat_btn:setVisible(true)
    end

    if self.info.status == FRIEND_STATUS.offline then
        self.normal_node:setVisible(false)
        self:setColor(ui_helper:GetColor4B(0x7F7F7F))
        self.fight_btn:setVisible(false)        
    else     
        self.fight_btn:setVisible(true)
        self.normal_node:setVisible(true)
        self:setColor(ui_helper:GetColor4B(0xFFFFFF))
    end 

end
function meta:RegisterEvent()

    -- 删除好友
    ui_helper:AddClick(self.delete_btn,function ()
        local user_id = self.info.user_id     
        friend_logic:ReqDeletFriend(self.info.user_id)
    end)
end
--好友聊天
function meta:AddChatClick(info,func)
    ui_helper:AddClick(self.chat_btn,function()
        self:TipShow(2)
        if self.tip_show == 1 then
            graphic:DispatchEvent("remove_node_tip") --如果这边点击普通好友处消息提示框消息
        end
        friend_logic.chat_with_me[info.user_id] = 2
        local type_chat = CHAT_STATUS.friend_private_chat
        local friend_table = info
        chat_logic:Query(type_chat,friend_table)        
    end)
end
--好友对战
function meta:FightClick(info)
    ui_helper:AddClick(self.fight_btn,function ()
            local user_id = info.user_id  
            friend_logic:ReqFriendInviteBattle(user_id)    
    end)
end


return meta
