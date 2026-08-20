local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local graphic = require "manager.graphic"
local defines = require "manager.defines"
local audio_manager = require "manager.audio_manager"

local deck_logic = require "logic.deck"

local TAB_TYPE = defines.DECK_TAB_TYPE
local CARD_CONFIG = data_template.card_config
local meta = class("card_page_panel",function (node)
    return node
end)

local CARD_PAGE_MAX = 9

function meta:ctor()

    local page = self:getChildByName("page")
    self.book_page = page
    self.title = page:getChildByName("title")
    ui_helper:SetTextByKey(self.title,"my_card_handbook") --我的卡本


    self.card_node_list = {}
    for i = 1, CARD_PAGE_MAX do
        self.card_node_list[i] = ui_helper:ExpandUI(page, "template"..i, "modules.deck.card_bag_item")
    end

    -- 页数显示
    self.page_num_txt = page:getChildByName("pagenum")
    self.scroll_touch = self:getChildByName("scroll_touch")

    local src_xx, src_yy = page:getPosition()
    self.page_x, self.page_y = src_xx, src_yy

    self.page_panel = page

    self.is_book_flip = false
    -- 延迟渲染队列
    self.render_queue = {}

    self:RegisterWidgetEvent()
    self:RegisterEvent()
    --self:xxx()
end

--每个卡牌的数目都为1
function meta:ComposeCardNum(bool)
     for i = 1, CARD_PAGE_MAX do
        self.card_node_list[i]:TheComposeNum(bool)
    end
end

function meta:ComposeCardPage(bool)
    if bool == true then
        ui_helper:SetTextByKey(self.title,"the_card_handbook") --卡牌图鉴
    else
        ui_helper:SetTextByKey(self.title,"my_card_handbook") --我的卡本
    end
    self:ComposeCardNum(bool)
end

function meta:SetPageSkeleton(skeleton_book)
    self.skeleton_book = skeleton_book

    local cur_page_render_texture = cc.RenderTexture:create(613, 819)
    self:addChild(cur_page_render_texture)
    self.cur_page_render_texture = cur_page_render_texture
    self.cur_page_render_texture:setVisible(false)
    local card_texture = cur_page_render_texture:getSprite():getTexture()
    skeleton_book:pushSlotTexture("cardbook_info", 0, card_texture)

    skeleton_book:registerSpineEventHandler(function (event)

        table.insert(self.render_queue, function ()
            self.is_book_flip = false
            skeleton_book:setVisible(false)
        end)


        if event.animation == "card_book_page_down" then
            self.end_event()
        end
    end, sp.EventType.ANIMATION_END)

    skeleton_book:registerSpineEventHandler(function (event)
        self.is_book_flip = true
    end, sp.EventType.ANIMATION_START)

    skeleton_book:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name

        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "shake" then
            battle_logic:DispatchEvent("effect_screen_shake", float_value, int_value)
        end
    end, sp.EventType.ANIMATION_EVENT)
end

-- 渲染到静态图
function meta:RenderToTexturePage()
    local render_texture = self.cur_page_render_texture
    self.page_panel:setVisible(true)
    self.page_panel:setPosition(0, 8)
    render_texture:beginWithClear(0.0, 0.0, 0.0, 0.0)
    self.page_panel:visit()
    render_texture:endToLua()
    self.page_panel:setVisible(false)
    local card_texture = render_texture:getSprite():getTexture()
    card_texture:setAntiAliasTexParameters()
    return card_texture
end

function meta:Update(elapsed_time)
    local queue = self.render_queue[1]
    if queue then
        queue()
        table.remove(self.render_queue, 1)
    end
end

function meta:Refresh(card_list, new_page_num)

    self.card_list = card_list
    self.max_page_num = math.ceil(#card_list / CARD_PAGE_MAX)
    local cur_page_num = math.min(new_page_num or 1, self.max_page_num)
    self:SetPage(cur_page_num, true)
end

-- 设置页数
function meta:SetPage(cur_page_num, is_refresh)
    if self.cur_page_num == cur_page_num and not is_refresh then
        return
    end
    local min_card_idx = (cur_page_num - 1)  * CARD_PAGE_MAX
    for i = 1, CARD_PAGE_MAX do
        local card_idx = i + min_card_idx
        local card_config = self.card_list[card_idx]
        local card_node = self.card_node_list[i]
        if card_config then
            card_node:setVisible(true)
            card_node:ShowCardGroupInfo(card_idx, card_config,false,true)
            card_node:AddClickEvent(function ()
                if self.is_book_flip then
                    return
                end
                graphic:DispatchEvent("deck_card_detail_show", card_config.uid, self.is_create)

            end)
        else
            card_node:setVisible(false)
        end
    end
    self.cur_page_num = cur_page_num
    self.page_panel:setPosition(self.page_x, self.page_y)

    self.page_panel:setVisible(true)
    ui_helper:SetText(self.page_num_txt, self.cur_page_num.."/"..self.max_page_num)
end
-- 上一页
function meta:PrevPage()
    local cur_page_num = self.cur_page_num - 1
    if cur_page_num < 1 or self.is_book_flip then
        return
    end
    local skeleton_book = self.skeleton_book
    table.insert(self.render_queue, function ()
        self:SetPage(cur_page_num)
    end)

    table.insert(self.render_queue, function ()
        self:RenderToTexturePage()
    end)

    table.insert(self.render_queue, function ()
        self:SetPage(cur_page_num + 1)
    end)

    self.end_event = function ()
        self:SetPage(cur_page_num)
        -- cc.Director:getInstance():purgeCachedData()
    end

    self.is_book_flip = true
    self.skeleton_book:setVisible(true)
    self.skeleton_book:addAnimation(1, "card_book_page_down", false)
end

-- 下一页
function meta:NextPage()
    local cur_page_num = self.cur_page_num + 1
    if cur_page_num > self.max_page_num or self.is_book_flip then
        return
    end

    local skeleton_book = self.skeleton_book

    table.insert(self.render_queue, function ()
        self:RenderToTexturePage()
    end)

    table.insert(self.render_queue, function ()
        self:SetPage(cur_page_num)
    end)
    -- table.insert(self.render_queue, function ()
        -- cc.Director:getInstance():purgeCachedData()
    -- end)

    self.is_book_flip = true
    self.skeleton_book:setVisible(true)
    self.skeleton_book:addAnimation(1, "card_book_page_up", false)
end

function meta:RegisterWidgetEvent()



end

function meta:RegisterEvent()
    graphic:RegisterEvent("card_book_page_visible", function (is_visible)
        self:setVisible(is_visible)
    end)
end

function meta:RegisterTouchEvent()
    local location_node_begin   = 0
    local location_node_spacing =40  --点击距离超过 num才能滑动
    local function onTouchBegan(touch,event)
        location_node_begin = self:convertToNodeSpace(touch:getLocation()).x
        return true
    end
    local function onTouchMoved(touch,event)
    end
    local function onTouchEnded(touch,event)
        if location_node_begin >self:convertToNodeSpace(touch:getLocation()).x then
            if (location_node_begin-location_node_spacing)>self:convertToNodeSpace(touch:getLocation()).x then
                self:NextPage() --下一页
            end
        else
            if (location_node_begin+location_node_spacing) < self:convertToNodeSpace(touch:getLocation()).x then
                self:PrevPage() --上一页
            end
        end
    end
    local listener = cc.EventListenerTouchOneByOne:create()
    self.listener = listener
    listener:registerScriptHandler(onTouchBegan, cc.Handler.EVENT_TOUCH_BEGAN)
    listener:registerScriptHandler(onTouchMoved, cc.Handler.EVENT_TOUCH_MOVED)
    listener:registerScriptHandler(onTouchEnded, cc.Handler.EVENT_TOUCH_ENDED)
    local eventDispatcher = self.scroll_touch:getEventDispatcher()
    eventDispatcher:addEventListenerWithSceneGraphPriority(listener, self.scroll_touch)
end

function meta:RemoveTouchEvent()
    local eventDispatcher = self:getEventDispatcher()
    eventDispatcher:removeEventListener(self.listener)

end

return meta
