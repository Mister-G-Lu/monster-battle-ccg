local constants = require "common.constants"


local ATTACHMENT_TYPE = constants.ATTACHMENT_TYPE
local MAIL_STAGE = constants.MAIL_STAGE

-- 邮件
local meta = {}

function meta.New(metadata)
    return table.new(meta, metadata or {})
end

-- 初始化新邮件
function meta:Init(type, title, send_name, desc, now_time)
    self.type = type
    self.stage = MAIL_STAGE.unread
    self.title = title
    self.send_name = send_name
    self.desc = desc
    self.time = now_time
    self.attachment_list = {}
end

-- 添加战斗录像
function meta:AddBattleRecord(battle_record_id)
    local attachment = {}
    attachment.att_type = ATTACHMENT_TYPE.record
    attachment.value = battle_record_id
    table.insert(self.attachment_list, attachment)
end

-- 添加资源
function meta:AddResourceInfo(resource_info)
    if not resource_info then
        return
    end
    local attachment = {}
    attachment.att_type = ATTACHMENT_TYPE.resource
    attachment.attr_id = tonumber(resource_info.attr_id)
    attachment.value = resource_info.value
    table.insert(self.attachment_list, attachment)
end

-- 添加奖励
function meta:AddRewardInfo(reward)
    if not reward then
        return
    end
    local attachment = {}
    attachment.att_type = ATTACHMENT_TYPE.reward
    attachment.sub_type = reward.type
    attachment.attr_id = tonumber(reward.attr_id)
    attachment.value = reward.value
    table.insert(self.attachment_list, attachment)
end

-- 添加卡包
function meta:AddChestInfo(cheat_id, value)
    value = value or 1
    local attachment = {}
    attachment.att_type = ATTACHMENT_TYPE.chest
    attachment.attr_id = tonumber(cheat_id)
    attachment.value = value
    table.insert(self.attachment_list, attachment)
end

return meta
