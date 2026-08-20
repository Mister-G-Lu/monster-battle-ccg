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
    self.normal_node = self:getChildByName("the_normal_node") -- 普通节点
    self.confirm_btn = self:getChildByName("confirm_btn") -- 同意按钮
    self.cancel_btn = self:getChildByName("cancel_btn")
    self:RegisterEvent() 
end
-- 设置好友信息
function meta:SetFriendInfo(info)
    self.info = info
    ui_helper:SetText(self.name, info.user_name)--.."#"..info.user_id
end
--设置状态(是编辑状态还是非编辑状态)
function meta:RegisterEvent()
    graphic:RegisterEvent("the_friend_list",function (user_id)
    end)
    --同意好友邀请
    ui_helper:AddClick(self.confirm_btn,function()
        friend_logic:ReqFriendAddAccept(self.info.user_id)
    end)
    --拒绝好友邀请
    ui_helper:AddClick(self.cancel_btn,function()
        friend_logic:ReqFriendAddRefuse(self.info.user_id)       
    end)
end


return meta
