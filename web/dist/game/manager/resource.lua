local constants = require "common.constants"
local bit = require "utils.bit_extension"

local resource = {}

resource.DEFAULT_FONT = "fonts/general.ttf"

local BATTLE_RESULT = constants.BATTLE_RESULT
local MAIL_TYPE = constants.MAIL_TYPE
local MAIL_STAGE = constants.MAIL_STAGE

-- 邮件资源
local MAIL_ICON_RESOURCE = {
    [MAIL_TYPE.notice] = {
        [MAIL_STAGE.unread] = "ui/ui_icon/mailbox/mail_close.png",
        [MAIL_STAGE.read] = "ui/ui_icon/mailbox/mail_open.png",
     },
     [MAIL_TYPE.item] = {
        [MAIL_STAGE.unread] = "ui/ui_icon/mailbox/reward_close.png",
        [MAIL_STAGE.read] = "ui/ui_icon/mailbox/reward_open.png",
     },
}

-- 引导头像
function resource:GetGuideIcon(path)
    print("path = ", path)
    return "ui/ui_icon/guide/"..path..".png", ccui.TextureResType.localType
end

-- 获取道具图标
function resource:GetItemIcon(item_path)
    return "ui/ui_icon/item/"..item_path..".png", ccui.TextureResType.localType
end

-- 获取邮件图标
function resource:GetMailIcon(type, stage)
    local stage_icon = MAIL_ICON_RESOURCE[type]
    if stage_icon == nil then
        stage_icon = MAIL_ICON_RESOURCE[MAIL_TYPE.notice]
    end

    local path = stage_icon[stage]
    if not path then
        path = stage_icon[MAIL_STAGE.read]
    end
    return path, ccui.TextureResType.plistType
end

-- 获取卡包的外表
function resource:GetChestStyle(quality)
    return "ui/pic_card/cardbag_"..quality..".png", ccui.TextureResType.plistType
end

-- 获取卡包图标
function resource:GetChestIcon(quality)
    return "ui/ui_icon/card/cardbag_"..quality..".png", ccui.TextureResType.plistType
end

-- 获取技能图标
function resource:GetSkillIcon(skill_name)
    return "ui/ui_icon/skill/"..skill_name..".png",ccui.TextureResType.plistType
end

-- 获取主要技能图标
function resource:GetMainPowerImage(power_name)
    return "ui/pic_card/new_card/"..power_name..".png", ccui.TextureResType.plistType
end

-- 获取种类图标
function resource:GetKindIcon(path)
    return "ui/ui_icon/card/coloricon_"..path..".png",ccui.TextureResType.plistType
end

-- 获取品质图标
function resource:GetQualityImage(quality)
    return "ui/pic_card/quality_"..quality..".png",ccui.TextureResType.plistType
end

function resource:GetQualitySmallImage(quality)
    return "ui/ui_icon/card/qualityicon"..quality..".png",ccui.TextureResType.localType
end

function resource:GetKindBgImage(path)
    return "ui/kind_bg/bg_"..path..".png",ccui.TextureResType.localType
end

-- 卡牌类型图标
function resource:GetCardTypeIcon(type)
    return "ui/ui_icon/card/kindicon_"..type..".png", ccui.TextureResType.plistType
end

-- 天梯界面IOCN
function resource:GetLadderTypeIcon(type)
    return "ui/ui_icon/ladder_headicon/"..type..".png",ccui.TextureResType.localType
end

function resource:GetCardImage(type, kind, path)
    if type == constants.CARD_TYPE.monster then
        local king_str, index = "", 0
        for k,v in pairs(constants["CARD_KIND"]) do
            if bit:GetBitNum(kind, v) == 1 then
                king_str = king_str..k
                if index > 0 then
                    king_str = king_str.."_"
                end
            end
        end
        return "ui/pic_card/monster/"..king_str.."/"..path..".png",ccui.TextureResType.localType
    else
        return "ui/pic_card/item/"..path..".png",ccui.TextureResType.localType
    end
end

return resource
