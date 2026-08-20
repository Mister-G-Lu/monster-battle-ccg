local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local graphic = require "manager.graphic"
local text_loader = require "manager.text_loader"
local resource_logic = require "logic.resource"
local data_template = require "manager.data_template"
local ComposePanel = require "modules.deck.card_create_panel"
local card_resolve = require "modules.deck.card_resolve_panel"
local deck_logic = require "logic.deck"
local world_panel = require "modules.world.world_panel"
local audio_manager = require "manager.audio_manager"
local font_height = 24
local CARD_CONFIG = data_template.card_config
local POWER_CONFIG_MAP = data_template.power_config
local COMPOSE_CONFIG = data_template.card_compose_config
local ITEM_CONFIG = data_template.item_config
local CENTER_NODE_IDX = 4

local NUM_TIME = 1
local meta = class("card_detail_panel",function (node)
    return ui_helper:LoadCocosUI("interface/deck/card_detail_panel.csb")
end)

local skill_item = class("card_detail_item",function (node)
    return node
end)

function skill_item:ctor()
    self.icon_img = self:getChildByName("icon")
    self.name_txt = self:getChildByName("name")
    self.detail_txt = self:getChildByName("detail")

    self.src_desc_size = self.detail_txt:getContentSize()
    local render = self.detail_txt:getVirtualRenderer()
    render:setDimensions(self.src_desc_size.width, 0)
end

function skill_item:Show(power)
    self.src_desc_size = self.detail_txt:getContentSize()
    local render = self.detail_txt:getVirtualRenderer()
    render:setDimensions(self.src_desc_size.width, 0)
    self:setVisible(true)
    local height = 0
    local config = POWER_CONFIG_MAP[power.name]
    self.icon_img:loadTexture(resource:GetSkillIcon(power.name))

    ui_helper:SetText(self.name_txt, config.name_desc)
    local new_size = self.icon_img:getContentSize()
    height = new_size.height

    local render = self.detail_txt:getVirtualRenderer()

    ui_helper:SetText(self.detail_txt, config.info_desc)

    local new_size = render:getContentSize()
    self.detail_txt:setContentSize(new_size)
    height = height + new_size.height
    return height
end

function skill_item:Hide()
    self:setVisible(false)
end

function skill_item:GetHeight()
    return self.height
end

function meta:ctor()
    local root = self:getChildByName("node")
    self.root = root
    -- 返回
    self.back_btn = root:getChildByName("back_btn")
    -- 升级
    self.upgrade_btn = root:getChildByName("levelup_btn")
    -- 分解
    self.resolve_btn = root:getChildByName("delete_btn")
    --显示卡牌所有技能
    self.levellist_btn = root:getChildByName("levellist_btn")
    --self.levellist_btn:setVisible(false)
    --卡牌节点
    self.srcoll_node = root:getChildByName("srcoll_node")
    -- 上阵
    self.add_btn = root:getChildByName("add_btn")
    self.deck_tips_btn = root:getChildByName("deck_tips_btn")
    --左边按钮
    self.left_btn = root:getChildByName("transform_arrow1")
    --右边按钮
    self.right_btn = root:getChildByName("transform_arrow2")
    --描述区域
    self.skill_info = root:getChildByName("skill_info")
    --制造节点
    self.create_node = root:getChildByName("create_node")
    --制作按钮
    self.create_btn = self.create_node:getChildByName("create_btn")
    --粉末数据
    self.card_value = self.create_node:getChildByName("value")
    --粉末icon
    self.icon = self.create_node:getChildByName("icon")
    --滚动框
    local scroll_view = self.skill_info:getChildByName("scroll_view")
    local power_item_node_list = {}
    for i = 1, 3 do
       local item = skill_item.new(scroll_view:getChildByName("skill_template"..i))
       item:setVisible(false)
       power_item_node_list[i] = item
    end

    self.world_panel = world_panel
    self.scroll_view = scroll_view
    self.power_item_node_list = power_item_node_list
    self.is_create = false
    self.is_show = true -- 卡片是否存在
    -- 初始化滚动卡牌
    self:InitSrcollCard()
    self:PlayAnimation("hide")
    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

--显示正确的粉末icon
function meta:ShowIcon(bool)
    if bool == true then --怪兽粉末
        --GetItemIcon
        self.icon:loadTexture("ui/ui_icon/item/m_monster.png")
    else
        self.icon:loadTexture("ui/ui_icon/item/m_item.png")
    end
end

function meta:SetPowerNum(powder_num)
    ui_helper:SetTextByKey(self.card_value, "the_powder_num", powder_num)
end

function meta:NewShow()
    self.is_show = true
    for k,v in pairs(self.srcoll_parameter_list) do
        self.card_node_list[k]:Relativedisplay(self.is_show)
        -- self.card_node_list[k]:PlayAnimation("normal")
    end
end

function meta:CardHave(group_id)
    local card_num = deck_logic:GetNumByGroupId(group_id)
    if card_num == 0 then
        self.is_show = false
    else
        self.is_show = true
    end

    for k,v in pairs(self.srcoll_parameter_list) do
        self.card_node_list[k]:Relativedisplay(self.is_show)
        if self.is_show == false then
            -- self.card_node_list[k]:PlayAnimation("card_alf",false)
            -- self.card_node_list[k]:setOpacity(100)
        else
            -- self.card_node_list[k]:PlayAnimation("normal")
            -- self.card_node_list[k]:setOpacity(255)
        end
    end
end

-- 合成成功
function meta:ComposeCardSuccess(model_id)
    if self.compose_skin == nil then
        local compose_skin = sp.SkeletonAnimation:create("animation/card_upgrade.json", "animation/card_upgrade.atlas", 0.67)
        self.srcoll_node:addChild(compose_skin, 60)
        compose_skin:setPosition(cc.p(0, 0))
        compose_skin:setToSetupPose()
        self.compose_skin = compose_skin
    end
    local compose_skin = self.compose_skin
    compose_skin:setVisible(true)
    compose_skin:setAnimation(0, "card_compose", false)
    compose_skin:registerSpineEventHandler(function (event)
        local event_name = event.eventData.name
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        if event_name == "change" then
            local config = deck_logic:GetCardConfigByModelId(model_id)
            self:CardHave(config.group_id)
        elseif event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "shake" then
            graphic:DispatchEvent("effect_screen_shake", float_value, int_value)
        end
    end,sp.EventType.ANIMATION_EVENT)

    compose_skin:registerSpineEventHandler(function (event)
        compose_skin:setVisible(false)

    end,sp.EventType.ANIMATION_END)
end

-- 初始化滚动卡牌
function meta:InitSrcollCard()
  -- 初始化7点定点坐标
  local distance = 100
  local height = 0

  local srcoll_parameter_list = {
    { pos_x =  -3 * distance, zorder = 19, c3b = cc.c3b(30, 30, 30), scale = 0.2},
    { pos_x =  -2.5 * distance, zorder = 20, c3b = cc.c3b(70, 70, 70), scale = 0.5},
    { pos_x =  -1.5 * distance, zorder = 21, c3b = cc.c3b(100, 100, 100), scale = 0.7},
    { pos_x = 0,  zorder = 22, c3b = cc.c3b(255, 255, 255), scale = 0.8},
    { pos_x = 1.5 * distance, zorder = 21, c3b = cc.c3b(100, 100, 100), scale = 0.7},
    { pos_x = 2.5 * distance, zorder = 20, c3b = cc.c3b(70, 70, 70), scale = 0.5},
    { pos_x = 3 * distance, zorder = 19, c3b = cc.c3b(30, 30, 30), scale = 0.2},
  }
    self.srcoll_parameter_list = srcoll_parameter_list

    self.card_node_list = {}

    for k,v in pairs(srcoll_parameter_list) do
        local card_node = require("modules.common.card_hand_item").new()
        card_node:setPosition(cc.p(v.pos_x, height))
        card_node:setScale(v.scale)
        card_node:setLocalZOrder(v.zorder)
        card_node:setColor(v.c3b)
        card_node:setVisible(false)

        self.srcoll_node:addChild(card_node)
        self.card_node_list[k] = card_node
    end
end

function meta:SetPowerListDescPanel(power_list)
    if power_list then
        self:setVisible(true)
        local height = 360
        local index = 0
        for i = 1, 3 do
            local power = power_list[i]
            local item = self.power_item_node_list[i]
            if power then
                item:setPositionY(height)
                height = height - item:Show(power)
                index = index + 1
            else
                item:Hide()
            end
        end
    end

end
function meta:DoExit()
    self:PlayAnimation("hide")
    self:setVisible(false)
    local eventDispatcher = self.srcoll_node:getEventDispatcher()
    eventDispatcher:removeEventListener(self.listener)
    graphic:DispatchEvent("card_book_page_visible", true)
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.upgrade_btn, function ()
        local card_info = self.cur_card_info["card_info"]
        graphic:DispatchEvent("push_world_panel", "deck", "card_upgrade_panel", card_info)
    end)

    ui_helper:AddClick(self.resolve_btn, function ()
        local card_config = self.cur_card_info["config"]
        local card_info = self.cur_card_info["card_info"]
        graphic:DispatchEvent("push_world_panel", "deck", "card_resolve_panel", card_info, card_config)
    end)

    ui_helper:AddClick(self.add_btn, function ()
        local card_info = self.cur_card_info["card_info"]
        local card_config = self.cur_card_info["config"]
        graphic:DispatchEvent("show_join_deck_panel", card_info, card_config)
    end)

    ui_helper:AddClick(self.back_btn, function ()
        graphic:DispatchEvent("card_book_refresh")
        self:PlayAnimation("hide")
        self:setVisible(false)
        self:DoExit()
    end)

    ui_helper:AddClick(self.left_btn, function ()
        self:DoLeftCard()
    end)

    ui_helper:AddClick(self.right_btn, function ()
        self:DoRightCard()
    end)

    ui_helper:AddClick(self.create_btn, function ()
        deck_logic:ComposeCard(self.card_model_id)
    end)

    self.levellist_btn:addTouchEventListener(function (sender,eventType)
        local is_show = true
        if eventType == ccui.TouchEventType.ended  or eventType == ccui.TouchEventType.canceled then
            is_show = false
        end
        graphic:DispatchEvent("card_skills_panel_show", is_show)
    end)
end

function meta:ShowGroup(card_group_id, select_card_info)
    local card_detail_list ={}
    self.cur_group_id = card_group_id

    if self.is_create == false then
        card_detail_list = deck_logic:GetCardListByGroupId(card_group_id)
        self:NewShow() -- 刷新显示 把牌本全部设置成true
    else
        card_detail_list = deck_logic:GetComposeCardListByGroupId(card_group_id)
    end
    if #card_detail_list == 0 then
        self:DoExit()
        return
    end
    local _sort_func = function (a,b)
        local a_config = a.config
        local b_config = b.config
        return a_config.level > b_config.level
    end
    table.sort(card_detail_list, _sort_func)

    self.card_detail_list = card_detail_list
    local cur_idx = 1
    if select_card_info then
        for k, v in pairs(card_detail_list) do
            local card_info = v["card_info"]
            if card_info.id == select_card_info then
                cur_idx = k
            end
        end
    end
    self:SetCurCardInfo(cur_idx)
end

-- 显示
function meta:Show(card_model_id, card_id, is_create)
    self.is_create = is_create
    self.card_model_id = card_model_id
    self:PlayAnimation("show", false, function ()
        graphic:DispatchEvent("card_book_page_visible", false)
    end)

    self:setVisible(true)
    self:RegisterTouchEvent()
    if NUM_TIME == 1 then
        self.call_one = 1
        self.call_two = 1
        NUM_TIME = 2
    else
        self.call_one = 2
        self.call_two = 2
    end

    local card_group_id = deck_logic:GetGroupIdByUid(card_model_id)
    self:ShowGroup(card_group_id, card_id)
end

function meta:RegisterEvent()
    -- 刷新
    graphic:RegisterEvent("card_detail_refresh", function (select_card_uid)
        self:ShowGroup(self.cur_group_id, select_card_uid)
    end)

    -- 刷新当前卡组ID
    graphic:RegisterEvent("deck_replace_success",function ()
        self:ShowGroup(self.cur_group_id)
    end)

    --得到合成状态
    graphic:RegisterEvent("card_compose_success",function (model_id)
        self:ComposeCardSuccess(model_id)
    end)

    --展示所有卡牌技能
    graphic:RegisterEvent("card_skills_panel_show",function (is_show)

        if self.skill_panle == nil then
            self.skill_panle = require("modules.deck.card_skills_panle").new()
            self:addChild(self.skill_panle, 60)
        end

        self.skill_panle:setVisible(is_show)
        local card_config = self.cur_card_info["config"]
        if is_show then
            self.skill_panle:UpdateSkills(card_config.uid)
        end
    end)

end

function meta:RegisterTouchEvent()
    -- body
    local location_node_begin   = 0
    local location_node_beginy  = 0
    local location_node_spacing = 40  --点击距离超过 num才能滑动
    local flag
    local visiblehight=cc.Director:getInstance():getVisibleSize().height

    local function on_touch_began(touch,event)
        location_node_beginy = self:convertToNodeSpace(touch:getLocation()).y
        if location_node_beginy < (3/4*visiblehight) and location_node_beginy > (2/5*visiblehight) then
            location_node_begin = self:convertToNodeSpace(touch:getLocation()).x
            flag = 1
        else
            flag = 2
        end
        return true
    end
    local function on_touch_moved(touch,event)
    end
    local function on_touch_ended(touch,event)
        local posx = self:convertToNodeSpace(touch:getLocation()).x
            if location_node_begin > posx then
                if (location_node_begin - location_node_spacing) > posx then --左边翻动
                    if flag == 1  then
                        self:DoLeftCard()
                    end
                end
            else
                if (location_node_begin + location_node_spacing) < posx then  --右边滑动
                    if flag == 1 then
                        self:DoRightCard()
                    end

                end
        end
    end
    local listener = cc.EventListenerTouchOneByOne:create() -- 创建一个事件监听器
    self.listener = listener
    --listener:setSwallowTouches(false)
    listener:registerScriptHandler(on_touch_began, cc.Handler.EVENT_TOUCH_BEGAN)
    listener:registerScriptHandler(on_touch_moved, cc.Handler.EVENT_TOUCH_MOVED)
    listener:registerScriptHandler(on_touch_ended, cc.Handler.EVENT_TOUCH_ENDED)
    local eventDispatcher = self.srcoll_node:getEventDispatcher() -- 得到事件派发器
    eventDispatcher:addEventListenerWithSceneGraphPriority(listener, self.srcoll_node) -- 将监听器注册到派发器中
end

-- 设置当前选择的卡牌信息
function meta:SetCurCardInfo(cur_data_idx)

    local card_detail_list = self.card_detail_list
    -- 设置当前选中的INFO
    local card_detail_info = card_detail_list[cur_data_idx]
    local config = card_detail_info["config"]
    local hand_card_info = card_detail_info["card_info"]
    if self.is_create == false then
        local card_info = card_detail_info["card_info"]

        self.create_node:setVisible(false)
        -- 升级按钮
        self.upgrade_btn:setVisible(deck_logic:CheckCardLevel(card_info.model_id))
        -- 分解按钮
        self.resolve_btn:setVisible(card_info.deck_flag == 0)

        local cur_deck_id = deck_logic.cur_deck_id
        -- 检查卡牌是否在当前卡组
        if deck_logic:CheckInDeck(card_info.id, cur_deck_id) then
            -- 已上阵
            self.deck_tips_btn:setVisible(true)
            -- 上阵按钮
            self.add_btn:setVisible(false)
        else
            -- 已上阵
            self.deck_tips_btn:setVisible(false)
            -- 上阵按钮
            self.add_btn:setVisible(true)
        end
    else
        -- 升级按钮
        self.upgrade_btn:setVisible(false)
        -- 分解按钮
        self.resolve_btn:setVisible(false)
        -- 上阵按钮
        self.add_btn:setVisible(false)
        -- 已上阵
        self.deck_tips_btn:setVisible(false)
        -- 早卡节点打开
        self.create_node:setVisible(true)

        local compose_config = card_detail_info["compose_config"]

        self:CardHave(config.group_id)
        local item_id = compose_config[1]["item_id"]
        local item_num = compose_config[1]["item_num"]
        if item_id == 100001 then  --怪兽卡
            self:ShowIcon(true)
        else
            self:ShowIcon(false)
        end
        --这个是展示粉末数量的
        ui_helper:SetText(self.card_value, item_num)
    end


    self:SetPowerListDescPanel(config.power_list)
    -- 刷新显示列表
    local show_tips = false
    if hand_card_info then
        if hand_card_info.deck_flag == 2 then
            show_tips = true
        end

    end
    self.card_node_list[CENTER_NODE_IDX]:SetCardInfo(config,show_tips)
    self.card_node_list[CENTER_NODE_IDX]:setVisible(true)

    for i = 1, 3 do
      -- 上一张卡牌信息
        local prev_idx = cur_data_idx - i
        local prev_data = card_detail_list[prev_idx]

        local prve_node = self.card_node_list[CENTER_NODE_IDX - i]
        if prev_data then
            local card_info = prev_data["card_info"]
            local prev_config = prev_data["config"]
            prve_node:setVisible(true)
            prve_node:SetCardInfo(prev_config,card_info.deck_flag == 2)
        else
            prve_node:setVisible(false)
        end

        -- 下一张卡牌
        local next_idx = cur_data_idx + i
        local next_data = card_detail_list[next_idx]
        local next_node = self.card_node_list[CENTER_NODE_IDX + i]
        if next_data then
            local card_info = next_data["card_info"]
            local next_config = next_data["config"]
            next_node:setVisible(true)
            next_node:SetCardInfo(next_config,card_info.deck_flag == 2)
        else
            next_node:setVisible(false)
        end
    end

    self.cur_card_info = card_detail_info
    self.cur_data_idx = cur_data_idx

    if cur_data_idx == 1 then
        self.right_btn:setVisible(false)
    else
        self.right_btn:setVisible(true)
    end
    if cur_data_idx == #card_detail_list then
        self.left_btn:setVisible(false)
    else
        self.left_btn:setVisible(true)
    end

end

-- 向左移动卡牌
function meta:DoLeftCard()
    if self.cur_data_idx >= #self.card_detail_list or self.is_scrolling then
        return
    end
    self.is_scrolling = true
    local srcoll_parameter_list = self.srcoll_parameter_list
    local card_node_list = self.card_node_list
    local time = 0.15
    for i = 2, 7 do
        local card_node = card_node_list[i]
        local new_info = srcoll_parameter_list[i - 1]
        local scale_act = cc.ScaleTo:create(time, new_info.scale)
        local move_act = cc.MoveTo:create(time, { x = new_info.pos_x, y = 0})
        local sqw = cc.Spawn:create(move_act, scale_act)
        -- 播放移动动画，播放完毕后，重置动画位置。重置位置上的卡牌信息
        card_node:setLocalZOrder(new_info.zorder)
        card_node:runAction(cc.Sequence:create(sqw, cc.CallFunc:create(function ()
            local src_info = srcoll_parameter_list[i]
            card_node:setPosition(cc.p(src_info.pos_x, 0))
            card_node:setScale(src_info.scale)
            card_node:setLocalZOrder(src_info.zorder)
            card_node:setColor(src_info.c3b)
        end)))
    end

      local block = cc.CallFunc:create(function ()
          self:SetCurCardInfo(self.cur_data_idx + 1)
          self.is_scrolling = false
      end)
      self:runAction(cc.Sequence:create(cc.DelayTime:create(time), block))
end

-- 向右移动卡牌
function meta:DoRightCard()
    if self.cur_data_idx <= 1 or self.is_scrolling then
        return
    end
    self.is_scrolling = true
    local srcoll_parameter_list = self.srcoll_parameter_list
    local card_node_list = self.card_node_list
    local time = 0.15
    for i = 1, 6 do
        local card_node = card_node_list[i]
        local new_info = srcoll_parameter_list[i + 1]
        local scale_act = cc.ScaleTo:create(time, new_info.scale)
        local move_act = cc.MoveTo:create(time, { x = new_info.pos_x, y = 0})
        local sqw = cc.Spawn:create(move_act, scale_act)
        -- 播放移动动画，播放完毕后，重置动画位置。重置位置上的卡牌信息
        card_node:setLocalZOrder(new_info.zorder)
        card_node:runAction(cc.Sequence:create(sqw, cc.CallFunc:create(function ()
            local src_info = srcoll_parameter_list[i]
            card_node:setPosition(cc.p(src_info.pos_x, 0))
            card_node:setScale(src_info.scale)
            card_node:setLocalZOrder(src_info.zorder)
            card_node:setColor(src_info.c3b)
        end)))
    end

    local block = cc.CallFunc:create(function ()
        self:SetCurCardInfo(self.cur_data_idx - 1)
        self.is_scrolling = false
    end)
    self:runAction(cc.Sequence:create(cc.DelayTime:create(time), block))
end

return meta
