local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"

local mail_logic = require "logic.mail"

local constants = require "common.constants"
local data_template = require "manager.data_template"

local MAIL_STAGE = constants["MAIL_STAGE"]
local MAIL_TYPE = constants["MAIL_TYPE"]

local ATTACHMENT_TYPE = constants["ATTACHMENT_TYPE"]

local meta = class("mail_detail_panel",function (node)
    return node
end)

function meta:ctor()

    -- 邮件标题
    self.title_txt = self:getChildByName("name")

    -- 寄件人
    self.send_name_txt = self:getChildByName("desc")

    -- 邮件图标
    self.icon_img = self:getChildByName("icon")

    -- 邮件内容
    local temp = self:getChildByName("desc_scrollview")
    self.scroll_veiw = temp
    self.desc_txt = temp:getChildByName("desc2")
    temp:setBounceEnabled(true)


    -- 邮件时间
    self.time_txt = self:getChildByName("time")

    -- 奖励附件
    self.reward_group_node = self:getChildByName("reward_group")
    self.reward_node_list = {}
    for i = 1, 6 do
        local reward_node = ui_helper:ExpandUI(self.reward_group_node, "reward"..i.."_item", "modules.common.material_item")
        reward_node:setVisible(false)
        self.reward_node_list[i] = reward_node
    end

    -- 已读图标
    self.read_icon = self:getChildByName("read_icon")

    -- 返回按钮
    self.back_btn = self:getChildByName("back_btn")

    -- 确认(领取)按钮
    self.confirm_btn = self:getChildByName("confirm_btn")
    self.confirm_txt = self.confirm_btn:getChildByName("desc")

    self:RegisterWidgetEvent()
end

function meta:Show(info, back_func)
    self.info = info
    self.mail_id = info.mail_id
    self.back_func = back_func

    self:setVisible(true)
    ui_helper:SetText(self.title_txt, info.title)
    ui_helper:SetText(self.desc_txt, info.desc)
    ui_helper:SetTextByKey(self.send_name_txt, "mail_send_user_name", info.send_name)
    ui_helper:SetText(self.time_txt, timer:GetDateFormat(info.time))

    --上一次高度
    local before_height = self.desc_txt:getTextAreaSize().height
    
    --当前高度
    local inner_size = self.desc_txt:getAutoRenderSize()
    local innerWidth = inner_size.width
    local innerHeight = inner_size.height
    
    self.desc_txt:setContentSize(cc.size(self.scroll_veiw:getContentSize().width, innerHeight))
    self.scroll_veiw:setInnerContainerSize(cc.size(innerWidth, innerHeight))

    --235是scrollview节点高度
    if innerHeight <= 235 then
        self.desc_txt:setPositionY(self.scroll_veiw:getContentSize().height)
    else
        self.desc_txt:setPositionY(self.scroll_veiw:getContentSize().height + innerHeight - 235)
    end
    

    self:SetStage(info.stage)

    local attachment_list = info.attachment_list or {}

    self.reward_group_node:setVisible(false)
    self.confirm_btn:setVisible(false)

    if info.type == MAIL_TYPE["notice"] then

    elseif info.type == MAIL_TYPE["item"] then
        if #attachment_list == 0 then
            self.reward_group_node:setVisible(false)
        else
            self.confirm_btn:setVisible(true)
            self.reward_group_node:setVisible(true)
        end
        for i = 1, 6 do
            local attachment = attachment_list[i]
            local reward_node = self.reward_node_list[i]
            if attachment then
                reward_node:setVisible(true)
                -- 转换奖励显示协议
                local reward_info = {}
                if attachment["att_type"] == ATTACHMENT_TYPE.resource then
                    reward_info.type = "resource"
                elseif attachment["att_type"] == ATTACHMENT_TYPE.chest then
                    reward_info.type = "chest"
                end
                reward_info.attr_id = attachment["attr_id"]
                reward_info.value = attachment["value"]
                reward_node:ShowReward(reward_info)
            else
                reward_node:setVisible(false)
            end
        end
    end



    if #attachment_list == 0 then
        self.confirm_btn:setVisible(false)
    else
        self.confirm_btn:setVisible(true)
    end

end

function meta:SetStage(stage)
    self.read_icon:setVisible(stage == MAIL_STAGE["read"])

    local mail_type = self.info.type
    local path = resource:GetMailIcon(mail_type, stage)
    self.icon_img:loadTexture(resource:GetMailIcon(mail_type, stage))

end

function meta:Hide()
    self:setVisible(false)
    if self.back_func then
        self.back_func()
    end
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.back_btn, function ()
        self:Hide()
    end)

    ui_helper:AddClick(self.confirm_btn, function ()
        mail_logic:DoReceive(self.mail_id, function ()
            self:SetStage(MAIL_STAGE["read"])
            self.confirm_btn:setVisible(false)
            self.reward_group_node:setVisible(false)
        end)
    end)
end

return meta
