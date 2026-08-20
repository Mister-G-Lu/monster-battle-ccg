local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"

local timer = require "manager.time"

local constants = require "common.constants"
local MAIL_STAGE = constants["MAIL_STAGE"]
local MAIL_TYPE = constants["MAIL_TYPE"]

local meta = {}
-- 初始化
function meta:Init()
    self.new_mail_num = 0
    self.mail_list = {}
    self.is_full_data = false
    self:RegisterMsgHandler()
end

-- 设置新邮件数量
function meta:SetNewMailNum(new_num)
    self.new_mail_num = new_num or 0
    if self.new_mail_num < 0 then
        self.new_mail_num = 0
    end
    graphic:DispatchEvent("refresh_new_mail", self.new_mail_num)
end

function meta:DelMail(mail_id)
    for k, v in pairs(self.mail_list) do
        if mail_id == v.mail_id then
            table.remove(self.mail_list, k)
        end
    end
end

function meta:AddMail(mail)
    self:SetNewMailNum(self.new_mail_num + 1)
    table.insert(self.mail_list, mail)
end

function meta:Query()
    if self.is_full_data then
        graphic:DispatchEvent("push_world_panel", "mail", "inbox_panel")
    else
        network:Send("query_mail_info", function (result, recv_msg)
            if result ~= "success" then
                graphic:DispatchEvent("show_message", result)
            else
                self.is_full_data = true
                self.mail_list = recv_msg.mail_list or {}
                graphic:DispatchEvent("push_world_panel", "mail", "inbox_panel")
            end
        end)
    end
end

-- 查看邮件
function meta:LookMail(mail)
    if mail.stage == MAIL_STAGE["unread"] and mail.type == MAIL_TYPE["notice"] then
        local req_data = {}
        req_data.mail_id = mail.mail_id
        network:Send("look_over_mail", mail.mail_id, function()
            mail.stage = MAIL_STAGE["read"]
            self:SetNewMailNum(self.new_mail_num - 1)
        end)
        return true
    end
    return false
end

-- 排序依次
function meta:GetMailList()
    local function sort_func(a, b)
        if a.stage == b.stage then
            return a.time > b.time
        else
            return a.stage < b.stage
        end
    end
    table.sort(self.mail_list, sort_func)
    return self.mail_list
end


function meta:SetMailById(mail_id, mail)
    local index = 0
    for k,v in pairs(self.mail_list) do
        if mail_id == v.mail_id then
            index = k
            break
        end
    end
    if index ~= 0 then
        self.mail_list[index] = mail
    end
end

-- 领取奖励
function meta:DoReceive(mail_id, complate_func)
    network:Send("receive_mail_attachment", mail_id, function (result, recv_msg)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result)
            return
        end

        self:SetNewMailNum(self.new_mail_num - 1)

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


-- 注册推送的协议包
function meta:RegisterMsgHandler()

    network:RegisterCommand("cmd_new_mail", function (recv_msg)
        local new_mail = recv_msg.new_mail
        local del_mail_id = recv_msg.del_mail_id
        if new_mail then
            if del_mail_id then
                self:DelMail(del_mail_id)
            end
            self:AddMail(new_mail)
            -- graphic:DispatchEvent("push_world_panel", "mail", "inbox_panel")
        end
    end)

end

return meta
