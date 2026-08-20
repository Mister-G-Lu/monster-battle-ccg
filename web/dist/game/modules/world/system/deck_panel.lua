local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local deck_logic = require "logic.deck"
local data_template = require "manager.data_template"
local reuse_scrollview = require "widget.reuse_scrollview"
local graphic = require "manager.graphic"

local CARD_CONFIG = data_template.card_config
local COMPOSE_CONFIG = data_template.card_compose_config
local meta = class("deck_panel",function ()
    return ui_helper:LoadCocosUI("interface/world/deck_panel.csb")
end)


function meta:ctor()

    -- 战斗卡组界面
    self.deck_group_panel = ui_helper:ExpandUI(self, "battlecard_group", "modules.deck.deck_group_panel")
    self.deck_group_panel:setLocalZOrder(50)

    -- 筛选器
    self.filter_panel = ui_helper:ExpandUI(self, "filter_panel", "modules.deck.card_fileter_panel")

    local cardbook_node = self:getChildByName("cardbook")

    -- book页面
    self.book_panel = ui_helper:ExpandUI(cardbook_node, "book", "modules.deck.card_page_panel")

    local cover_node = self:getChildByName("cover_node")
    local book_skin = sp.SkeletonAnimation:create("animation/card_book_skin.json", "animation/card_book_skin.atlas", 1)
    book_skin:setAnimation(0, "card_book_skin_in", true)
    cover_node:addChild(book_skin)
    cover_node:setLocalZOrder(60)
    self.book_skin = book_skin


    -- 返回主页面
    self.back_btn = self:getChildByName("back_btn")

    -- 上一页
    self.prev_page_btn = self:getChildByName("transform_arrow1")

    -- 下一页
    self.next_page_btn = self:getChildByName("transform_arrow2")

    local create_node = self:getChildByName("create_node")
    self.card_create_panel = ui_helper:ExpandUI(create_node, "node", "modules.deck.card_create_panel")
    create_node:setLocalZOrder(80)

    --我的收藏
    self.cardbook_btn = self:getChildByName("cardbook_btn")

    --制造卡牌按钮
    self.is_create = false
    self.create_card_btn = self:getChildByName("create_btn")

    local book_spine = self:getChildByName("book_spine")
    local skeleton_node = sp.SkeletonAnimation:create("animation/card_book_page.json", "animation/card_book_page.atlas", 1)
    skeleton_node:setAnimation(0, "card_book_page_stop", false)
    book_spine:addChild(skeleton_node)
    book_spine:setLocalZOrder(60)
    self.book_panel:SetPageSkeleton(skeleton_node)
    self.skeleton_node = skeleton_node


    self:PlayAnimation("init")
    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

function meta:Update(elapsed_time)
    self.deck_group_panel:Update(elapsed_time)
    self.book_panel:Update(elapsed_time)
end

function meta:Show()
    self.is_create = false
    self.book_panel:ComposeCardPage(self.is_create)
    deck_logic:SetBookStage(self.is_create)
    self:setVisible(true)
    local book_skin = self.book_skin
    self.book_panel:RegisterTouchEvent()
    self.prev_page_btn:setVisible(false)
    self.next_page_btn:setVisible(false)
    book_skin:setAnimation(0, "card_book_skin_in", true)
    self:PlayAnimation("enter", false, function ()
        book_skin:setVisible(true)
        book_skin:setAnimation(0, "card_book_skin_up", false)
        self.filter_panel:ResetFileter()
        local bag = self.filter_panel:GetFilterList()
        self.book_panel:Refresh(bag)
    end)
end

function meta:Hide()
    self.book_panel:RemoveTouchEvent()
    self:setVisible(false)
end

function meta:RegisterWidgetEvent()

    ui_helper:AddClick(self.back_btn, function ()
        graphic:DispatchEvent("switch_system_module", "home")
        local bag = self.filter_panel:GetFilterList()
        self.book_panel:Refresh(bag)
        self.is_create = false

    end)

    local book_skin = self.book_skin
    book_skin:registerSpineEventHandler(function (event)
        if event.animation == "card_book_skin_up" then
            self.prev_page_btn:setVisible(true)
            self.next_page_btn:setVisible(true)
        end
    end, sp.EventType.ANIMATION_END)

    local skeleton_book = self.skeleton_book
    ui_helper:AddClick(self.prev_page_btn, function ()
        self.book_panel:PrevPage()
    end)

    ui_helper:AddClick(self.next_page_btn, function ()
        self.book_panel:NextPage()
    end)

    ui_helper:AddClick(self.create_card_btn, function ()
        self:CreateCardBtn()
    end)

    ui_helper:AddClick(self.cardbook_btn,function()
        self:Show()
    end)

end
function meta:CreateCardBtn()
    self.is_create = true
    self:PlayAnimation("enter_create")
    self.card_create_panel:PowderShow()
    deck_logic:SetBookStage(self.is_create)

    local bag = self.filter_panel:GetFilterList()
    self.book_panel:Refresh(bag)
    self.book_panel:SetPageSkeleton(self.skeleton_node)
    local book_skin = self.book_skin
    book_skin:setAnimation(0, "card_book_skin_in", true)
    book_skin:setAnimation(0, "card_book_skin_up", false)
    self.book_panel:ComposeCardPage(self.is_create)

end

function meta:RegisterEvent()

    graphic:RegisterEvent("deck_card_detail_show", function (card_model_id, card_id)
        if self.detail_panel == nil then
            self.detail_panel = require("modules.deck.card_detail_panel").new()
            self:addChild(self.detail_panel, 40)
            self.detail_panel:setVisible(false)
        end
        card_model_id = tonumber(card_model_id)
        card_id = tonumber(card_id)
        self.detail_panel:Show(card_model_id, card_id, self.is_create)
    end)

    graphic:RegisterEvent("refresh_card_list", function (bag)
        self.book_panel:Refresh(bag)
    end)

    graphic:RegisterEvent("card_book_refresh", function ()
        local bag = self.filter_panel:GetFilterList()
        self.book_panel:Refresh(bag ,self.book_panel.cur_page_num)
    end)

    graphic:RegisterEvent("card_create_show",function()
       self.create_card_panel:Show()
    end)
        --跳转到 卡牌制作
    graphic:RegisterEvent("jump_create_card",function(card_model_id)
        self:CreateCardBtn()
        if self.detail_panel == nil then
            self.detail_panel = require("modules.deck.card_detail_panel").new()
            self:addChild(self.detail_panel, 40)
            self.detail_panel:setVisible(false)
        end
        card_model_id = tonumber(card_model_id)
        card_id = tonumber(card_id)
        self.detail_panel:Show(card_model_id, card_id, self.is_create)
    end)

    graphic:RegisterEvent("jump_upgrade_card",function(card_model_id)

        -- self:CreateCardBtn()
        if self.detail_panel == nil then
            self.detail_panel = require("modules.deck.card_detail_panel").new()
            self:addChild(self.detail_panel, 40)
            self.detail_panel:setVisible(false)
        end
        card_model_id = tonumber(card_model_id)
        card_id = tonumber(card_id)
        self.detail_panel:Show(card_model_id, card_id, false)
        local card_info = self.detail_panel.cur_card_info["card_info"]
        graphic:DispatchEvent("push_world_panel", "deck", "card_upgrade_panel", card_info)

    end)
    


end

return meta
