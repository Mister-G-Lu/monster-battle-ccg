local ui_helper = require "manager.ui_helper"
local friend_logic = require "logic.friend"
-- local meta = class("radio_box",function (node)
--     if node then
--         return node
--     end
--     return ui_helper:LoadCocosUI("interface/common/msgbox_simple.csb")
-- end)
local meta = ui_helper:NewPanel("radio_box", "interface/common/msgbox_simple.csb")
function meta:OnInit()

    local msgbox_node = self:getChildByName("msgbox")
    local size = msgbox_node:getContentSize()
    self.center_x = size.width / 2
    local titlebg_node = msgbox_node:getChildByName("titlebg")
    self.title_txt = titlebg_node:getChildByName("title")
    self.desc_txt = msgbox_node:getChildByName("desc")

    self.cancel_btn = msgbox_node:getChildByName("cancel_btn")
    self.confirm_btn = msgbox_node:getChildByName("confirm_btn")
    self.nofity_btn = msgbox_node:getChildByName("nofity_btn")

    self.src_x = self.confirm_btn:getPositionX()
    self.confirm_desc_txt = self.confirm_btn:getChildByName("desc")
    self:setVisible(false)
    ui_helper:BindTimeLine(self, "interface/common/msgbox_simple.csb")

        -- 加入遮罩层
    self.mask_node = ccui.Layout:create()
    self.mask_node:setContentSize(display.sizeInPixels.width, display.sizeInPixels.height)
    self.mask_node:setBackGroundColor(ui_helper:GetColor4B(0x303030))
    self.mask_node:setBackGroundColorOpacity(255 * 0.9)
    self.mask_node:setBackGroundColorType(1)
    self.mask_node:setTouchEnabled(true)
    self.mask_node:setVisible(true)
    self:addChild(self.mask_node, -100)

end

function meta:HideButton()
    self.confirm_btn:setVisible(false)
    self.cancel_btn:setVisible(false)
    self.nofity_btn:setVisible(false)
end

--发起方消息框
function meta:Show(title, desc, nofity_txt, nofity_func)
    print("show_fight_box")
    self:HideButton()
    self:setVisible(true)
    ui_helper:SetText(self.title_txt, title)
    ui_helper:SetText(self.desc_txt, desc)
    ui_helper:SetText(self.nofity_btn:getChildByName("desc"), nofity_txt)
    self.nofity_btn:setVisible(true)
    self.nofity_btn:setTouchEnabled(true)
    ui_helper:AddClick(self.nofity_btn, nofity_func)
    self:PlayAnimation("enter_msgbox")
end

--接收方消息框
function meta:ShowNofity(title, desc, confirm_txt,confirm_func,cancel_txt,cancel_func)
    self:HideButton()
    self:setVisible(true)

    ui_helper:SetText(self.title_txt, title)
    ui_helper:SetText(self.desc_txt, desc)
    --接受按钮
    ui_helper:SetText(self.confirm_btn:getChildByName("desc"), confirm_txt)
    self.confirm_btn:setVisible(true)
    self.confirm_btn:setTouchEnabled(true)
    ui_helper:AddClick(self.confirm_btn, confirm_func)
    --拒绝按钮
    ui_helper:SetText(self.cancel_btn:getChildByName("desc"), confirm_txt)
    self.cancel_btn:setVisible(true)
    self.cancel_btn:setTouchEnabled(true)
    ui_helper:AddClick(self.cancel_btn, cancel_func)

    self:PlayAnimation("enter_msgbox")
end
function meta:Hide(func)
    self:PlayAnimation("exit_msgbox", false, function ()
        self:setVisible(false)
        if func then
            func()
        end
    end)
end

function meta:RegisterEvent()
    --展示界面
    self:RegisterGraphic("show_fight_box",function (origin)

        if origin then --你发起的
            local function nofity_func()
                friend_logic:ReqRefuseFriendPvp()
            end
            self:Show("等待对方接受","怼起来","肚子疼...",nofity_func)
        else           --接收方显示
            local function confirm_func()
                friend_logic:ReqAcceptFriendPvp()
            end
            local function cancel_func()
                friend_logic:ReqRefuseFriendPvp()
            end
            self:ShowNofity("你的基友要怼你","OOXX","怼死他",confirm_func,"肚子疼...",cancel_func)
        end
    end)
    --隐藏界面
    self:RegisterGraphic("hide_fight_box",function ()
        self:Hide()
    end)
    --拒绝界面
    self:RegisterGraphic("show_Refuse_box",function ()
        local function cancel_func()
            self:Hide()
        end
        self:ShowNofity("你的基友肚子疼","OOXX","基友拒绝了你的搞基",confirm_func,"确定",cancel_func)
    end)
end


return meta
