local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local graphic = require "manager.graphic"
local defines = require "manager.defines"

local deck_logic = require "logic.deck"

local reuse_scrollview = require "widget.reuse_scrollview"
local constants = require "common.constants"


local TAB_TYPE = defines.DECK_TAB_TYPE

local DECK_MAX_NUM = 5

local meta = class("deck_select_panel",function (node)
    return node
end)


function meta:ctor()

    -- 绑定动画文件
    ui_helper:BindTimeLine(self, "interface/deck/battlecard_grouplist.csb")

    local group_title_node = self:getChildByName("group_title")
    -- 打开套牌
    self.deck_select_btn = group_title_node:getChildByName("group_selcectbtn")
    --几号套牌
    self.group_num = self.deck_select_btn:getChildByName("group_name")

    local info_node = group_title_node:getChildByName("info_node")

    -- 卡牌强度
    local power_bg = info_node:getChildByName("power_bg")

    self.power_txt = power_bg:getChildByName("value")
    local value_effect = power_bg:getChildByName("value_effect")
    -- 切换类型
    self.type_transform_node = info_node:getChildByName("kind_transform")
    ui_helper:BindTimeLine(self.type_transform_node, "interface/deck/kind_transform_btn.csb")

    -- 卡组列表
    local deck_list_node = group_title_node:getChildByName("cardgroup_list")
    self.deck_node_list = {}
    for i = 1, DECK_MAX_NUM do
        self.deck_node_list[i] = deck_list_node:getChildByName("template"..i)
    end
    --战斗力改变特效
    local skeleton = sp.SkeletonAnimation:create("animation/power_light.json", "animation/power_light.atlas", 0.8)
    skeleton:setToSetupPose()
    skeleton:setPosition({x = 0, y = 0})
    self.skeleton = skeleton
    value_effect:addChild(skeleton,1)
    skeleton:setPosition(cc.p(value_effect:getContentSize().width/2,value_effect:getContentSize().height/2))
    --战斗力改变数值
    self.change_value = power_bg:getChildByName("effect_info")
    self.change_value:setString("")
    -- 卡组选择状态
    self.is_selectd = false
    self:PlayAnimation("list")
    self.last_power_value = 0
    -- 当前显示状态
    self.cur_tab_type = TAB_TYPE.monster
    self:RegisterWidgetEvent()
    self:RegisterEvent()
end
--战斗力特效
function meta:PowerEffect(power_value)
    local change_num = power_value - self.last_power_value
    if change_num == 0 or self.last_power_value == 0 then
        return
    end
    local Symbol = ""
    if change_num < 0 then --下降战斗力
        self.skeleton:setAnimation(0, "power_down", false)
        self.change_value:setColor(ui_helper:GetColor3B(0xFF0000))
    else
        self.skeleton:setAnimation(0, "power_up", false)
        self.change_value:setColor(ui_helper:GetColor3B(0x77FF00))
        Symbol = "+"
    end
    self.change_value:runAction(cc.FadeIn:create(0))
    self.change_value:setScale(0.1)
    self.change_value:setVisible(true)
    self.change_value:runAction(cc.Sequence:create(cc.ScaleTo:create(0.1,1.2),
                                                    cc.ScaleTo:create(0.1,1),
                                                    cc.DelayTime:create(1.7),
                                                    cc.FadeOut:create(0.3)))
    self.change_value:setString(Symbol..tostring(change_num))
end

-- 设置战斗力
function meta:SetPower(power_value)
    self:PowerEffect(power_value)
    ui_helper:SetTextByKey(self.power_txt, "battle_power_desc", power_value)
end
--设置套牌组号
function meta:SetGroupNum(group_num)
    ui_helper:SetTextByKey(self.group_num, "cardgroup_info_num", group_num)
    -- body
end
-- 切换显示类型
function meta:SwtichShowType(new_tab_type)
    if self.cur_tab_type == new_tab_type then
        return
    end
    self.type_transform_node:PlayAnimation(new_tab_type)
    graphic:DispatchEvent("deck_group_tab", new_tab_type)
    self.cur_tab_type = new_tab_type
end

function meta:RegisterWidgetEvent()
    -- 卡组监听接口
    for i = 1, DECK_MAX_NUM do
        ui_helper:AddClick(self.deck_node_list[i], function ()
            graphic:DispatchEvent("deck_select_info", i)
        end)
    end

    -- 多卡组选择
    ui_helper:AddClick(self.deck_select_btn, function ()
        if self.is_selectd then
            self:PlayAnimation("list")
        else
            self:PlayAnimation("detail")
        end
        self.is_selectd = not self.is_selectd
    end)

    -- 卡牌类型状态
    local transform_btn = self.type_transform_node:getChildByName("kind_transform")
    ui_helper:AddClick(transform_btn, function ()
        if self.cur_tab_type == TAB_TYPE.monster then
            self:SwtichShowType(TAB_TYPE.item)
        else
            self:SwtichShowType(TAB_TYPE.monster)
        end
    end)

end

function meta:RegisterEvent()

    local transform_btn = self.type_transform_node:getChildByName("kind_transform")
    graphic:RegisterEvent("show_join_deck_panel",function (card_info, card_config)
        transform_btn:setTouchEnabled(false)
        if card_config.type == constants.CARD_TYPE.monster  then
            self:SwtichShowType(TAB_TYPE.monster)
        else
            self:SwtichShowType(TAB_TYPE.item)
        end
    end)

    graphic:RegisterEvent("hide_join_deck_panel",function ()
        transform_btn:setTouchEnabled(true)
    end)
end

return meta
