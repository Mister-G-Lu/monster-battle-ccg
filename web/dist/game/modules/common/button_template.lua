local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"

local meta = class("button_template",function (node, res_path)
    res_path = res_path or "interface/world/btn_template.csb"
    if not node then
         node = ui_helper:LoadCocosUI(res_path)
    end
    node.res_path = res_path
    return node
end)

function meta:ctor()
    ui_helper:BindTimeLine(self, self.res_path)

    local click_panel = self:getChildByName("btn_template")

    self.icon_img = click_panel:getChildByName("icon")
    self.desc_txt = click_panel:getChildByName("desc")

    self.click_panel = click_panel
end

function meta:SetIcon(path)
    self.icon_img:loadTexture(path, ccui.TextureResType.plistType)
end

function meta:SetDesc(desc)
    ui_helper:SetText(self.desc_txt, desc)
end

-- 设置激活状态
function meta:SetActive(is_active, is_anim)
    if self.cur_active == is_active then
        return
    end
    if is_anim == nil then
        is_anim = true
    end
    if is_anim then
        if is_active then
            self:PlayAnimation("enter_active")
        else
            self:PlayAnimation("enter_inactive")
        end
    else
        if is_active then
            self:PlayAnimation("loop_active")
        else
            self:PlayAnimation("loop_inactive")
        end
    end

    self.cur_active = is_active
end

function meta:AddClick(func)
    ui_helper:AddClick(self.click_panel, func)
end

return meta
