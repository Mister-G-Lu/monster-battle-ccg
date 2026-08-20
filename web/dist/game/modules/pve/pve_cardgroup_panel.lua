local ui_helper = require "manager.ui_helper"
local defines = require "manager.defines"
local pve_logic = require "logic.pve"
local text_loader = require "manager.text_loader"
local data_template = require "manager.data_template"
local TAB_TYPE = defines.DECK_TAB_TYPE
local CARD_CONFIG = data_template.card_config
local deck_logic = require "logic.deck"
local meta = ui_helper:NewPanel("pve_cardgroup_panel", "interface/pve/pve_cardgroup_panel.csb")

function meta:OnInit()
    self.card_group_node = self:getChildByName("node")
    self.close_btn = self.card_group_node:getChildByName("cancel_btn")
    self.card_groupbg = self.card_group_node:getChildByName("card_groupbg")
    self.select_btn = self.card_groupbg:getChildByName("group_selcectbtn")
    self.group_name = self.select_btn:getChildByName("group_name")
    self.open_select = false
    self.small_card_list = {}
    self.small_item_list = {}
    self.render_queue = {}
    self.touch_list = {}
    self.reward_list = {}
    self.need_num = 0
    self.limit_card_num = 0
    self.card_group1 = self.card_group_node:getChildByName("cardgroup_list"):getChildByName("cardgroup_btn1")
    self.card_group2 = self.card_group_node:getChildByName("cardgroup_list"):getChildByName("cardgroup_btn2")
    self.fight_btn =  self.card_group_node:getChildByName("confirm_btn")
    self.pve_count = pve_logic.pve_count
    self.pve_count_value = self.card_group_node:getChildByName("times"):getChildByName("value")
    self.show_card_type = 0
    self.system_card = true
    self:InitInfo()
    self:CheckCard()
    self:RefreshSystemDeckCard(TAB_TYPE.monster, true)
    self:RefreshSystemDeckCard(TAB_TYPE.item, true)
end

function meta:InitInfo()
     --PVE次数
    self.pve_count_value:setString(tostring(self.pve_count))
    local card_small_node = self.card_group_node:getChildByName("monster")
    local card_small_item = self.card_group_node:getChildByName("item")
     --得到日期
    local day = os.date("%w")
    local day_desc = data_template.pve_limit_config[tonumber(day)].desc
    local card_type = data_template.pve_limit_config[tonumber(day)].limit
    self.need_card_type = card_type
    local pve_level_count = 0
    for k,v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == tonumber(pve_logic.play_id) and tonumber(v.difficulty) == tonumber(pve_logic.difficulty) then
            self.limit_card_num = v.limit_card_num
        end
        if tonumber(v.play_id) == tonumber(pve_logic.play_id) then
            pve_level_count = pve_level_count + 1
        end
    end
    self.pve_level_count = pve_level_count
    --设置颜色 字体
    self.limit_color = text_loader:GetText("pve_limit_color_"..card_type)
    --暂时屏蔽的功能
    local day_limit_desc = text_loader:GetText("pve_day_limit_desc",day_desc)
    local day_limit_desc = text_loader:GetText("pve_cardgroup_mission",day_desc)
    local secard_group1_desc = text_loader:GetText("pve_cardgroup_mission",day_desc)
    --暂时屏蔽的功能
    --local pve_cardgroup_limit = text_loader:GetText("pve_cardgroup_limit",day_desc,self.limit_card_num,self.limit_color)
    local pve_cardgroup_limit = text_loader:GetText("pve_no_limit")
    --牌组按钮 文字
    ui_helper:SetText(self.group_name,day_limit_desc)
    ui_helper:SetText(self.card_group1:getChildByName("desc"),secard_group1_desc)
    ui_helper:SetText(self.card_group2:getChildByName("desc"),text_loader:GetText("pve_cardgroup_ourside"))
    ui_helper:SetText(self.card_groupbg:getChildByName("desc1"),pve_cardgroup_limit)
    ui_helper:SetText(self.card_groupbg:getChildByName("cardicon"):getChildByName("value"),tostring(self.limit_card_num))
    --暂时屏蔽的功能
    self.card_groupbg:getChildByName("cardicon"):setVisible(false)
    self.card_groupbg:getChildByName("icon1"):setVisible(false)
    -- self.card_groupbg:getChildByName("desc1"):setVisible(false)

    --是否显示大卡
    self:SetDeckInfo(deck_logic.cur_deck_id)

     --卡牌触摸
    for i = 1, 8 do
        self.touch_list[i] = card_small_node:getChildByName("touch"..i)
        self.touch_list[i]:setTag(i)
    end
    for i = 9, 16 do
        self.touch_list[i] = card_small_item:getChildByName("touch"..i)
        self.touch_list[i]:setTag(i)
    end
    --怪物卡牌
    for i = 1, 8 do
        local card_node = card_small_node:getChildByName("template"..i)
        local sub_panel = require("modules.deck.card_small_item").new(card_node)
        self.small_card_list[i] = sub_panel
    end
    --道具卡牌
    for i = 1, 8 do
        local card_node = card_small_item:getChildByName("template"..i)
        local sub_panel = require("modules.deck.card_small_item").new(card_node)
        self.small_item_list[i] = sub_panel
    end

    --初始化卡牌信息
    self.deck_info = pve_logic.system_card_list
    self.card_detail = ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_detail_panel.csb")
    self.card_group_node:addChild(self.card_detail)
    self.card_detail:setName("card_detail")
    self.card_detail:setPosition(cc.p(0,300))
    self.card_detail:setVisible(false)
    self.hand_card_detail = ui_helper:ExpandUI(self.card_group_node, "card_detail", "modules.pve.pve_card_detail_panel")
    self.hand_card_detail:setVisible(true)
    self.hand_card_detail:setLocalZOrder(10000)
    local level_type = 0
    if pve_logic.play_id == 1001 then
        level_type = 1
    end
    self.level_type = level_type
end

-- 设置卡组信息
function meta:SetDeckInfo(deck_idx)
    if self.deck_idx == deck_idx then
        return
    end
    self.deck_idx = deck_idx
    -- self:RefreshDeckCard(self.deck_idx, self.cur_tab)
end

--检查使用卡牌是否符合关卡要求
function meta:CheckCard()
    local haveCard = 0

    if self.system_card then
        for k,v in pairs(self.deck_info.monster_list) do
            if CARD_CONFIG[v].kind_list[1] == self.need_card_type then
                haveCard = haveCard + 1
            end
        end
    else
        for i = 1, 8 do
            local monster_id = self.deck_info["monster_pos_"..i]

            if monster_id then
                local config = deck_logic:GetCardConfigByCardId(monster_id)
                if config["kind"] == self.need_card_type then
                    haveCard = haveCard + 1
                end
            end
        end
    end

    self.need_num = self.limit_card_num - haveCard
    --检查PVE次数
    if pve_logic.pve_count > 0 then
        if self.need_num > 0 then   --检查卡牌要求
            ui_helper:SetText(self.card_group_node:getChildByName("confirm_btn"):getChildByName("desc"),text_loader:GetText("pve_startbtn_limit",self.need_num,self.limit_color))
            self.fight_btn:getChildByName("desc"):setColor(ui_helper:GetColor3B(0xE1755B))
        else
            ui_helper:SetText(self.card_group_node:getChildByName("confirm_btn"):getChildByName("desc"),text_loader:GetText("pve_startbtn_normal"))
            self.fight_btn:getChildByName("desc"):setColor(ui_helper:GetColor3B(0xffffff))
        end
    else
        ui_helper:SetText(self.card_group_node:getChildByName("confirm_btn"):getChildByName("desc"),text_loader:GetText("pve_startbtn_times"))
        self.fight_btn:getChildByName("desc"):setColor(ui_helper:GetColor3B(0xE1755B))
    end
end
function meta:SetPveTips(index)
    --index 选择的关卡难度
    local pve_play_id = tonumber(pve_logic.play_id .. index)
    local pve_info = data_template.pve_play_config[pve_play_id]
    if index <= self.pve_level_count and pve_info then

        --更新系统卡牌
        pve_logic:InitSystemCard(index)
        --更新奖励
        if self.system_card then
            self.deck_info = pve_logic.system_card_list
        else
            self.deck_info = deck_logic:GetDeckInfo(1)
        end
        if pve_logic.attack_type == 2 then --是系统卡牌界面
            self:RefreshSystemDeckCard(TAB_TYPE.monster, true)
            self:RefreshSystemDeckCard(TAB_TYPE.item, true)
        else
            self:RefreshDeckCard(self.deck_idx, TAB_TYPE.monster)
            self:RefreshDeckCard(self.deck_idx, TAB_TYPE.item)
        end
        self.fight_btn:setTouchEnabled(true)
        self.fight_btn:setColor(ui_helper:GetColor4B(0xFFFFFF))
        self.select_btn:setTouchEnabled(true)
        self.card_group_node:getChildByName("monster"):setColor(ui_helper:GetColor4B(0xFFFFFF))
        self.card_group_node:getChildByName("item"):setColor(ui_helper:GetColor4B(0xFFFFFF))
        --关卡未开启
        if tonumber(pve_logic.cur_difficulty) < index then
            self.fight_btn:setTouchEnabled(false)
            self.fight_btn:setColor(ui_helper:GetColor4B(0x7F7F7F))
            self.select_btn:setTouchEnabled(false)
            self.card_group_node:getChildByName("monster"):setColor(ui_helper:GetColor4B(0x7F7F7F))
            self.card_group_node:getChildByName("item"):setColor(ui_helper:GetColor4B(0x7F7F7F))
        end
    end
end
function meta:Update(elapsed_time)

     if #self.render_queue > 0 then
        local render = self.render_queue[1]
        render()
        table.remove(self.render_queue,1)
    end
    if self.pve_count ~= pve_logic.pve_count then
        self.pve_count_value:setString(tostring(pve_logic.pve_count))
        self.pve_count = pve_logic.pve_count
    end
end

function meta:Show()
    self:setVisible(true)
    local deck_info = deck_logic:GetDeckInfo(self.deck_idx)
    self.deck_info = deck_info
    ui_helper:SetText(self.group_name,text_loader:GetText("pve_cardgroup_ourside"))
    self:RefreshSystemDeckCard(TAB_TYPE.monster, true)
    self:RefreshSystemDeckCard(TAB_TYPE.item, true)
end

--刷新卡牌
function meta:RefreshDeckCard(deck_idx, tab_type, is_animation)
    if not deck_idx or not tab_type then
        return
    end

    self:CheckCard()
    local deck_info = deck_logic:GetDeckInfo(self.deck_idx)

    if not deck_info then
        return
    end

    local card_list = {}
    local power_value = 0

    for i = 1, 8 do
        local monster_id = deck_info["monster_pos_"..i]
        local item_id = deck_info["item_pos_"..i]

        if monster_id then
            local config = deck_logic:GetCardConfigByCardId(monster_id)
            power_value = power_value + config.score
        end
        if item_id then
            local config = deck_logic:GetCardConfigByCardId(item_id)
            power_value = power_value + config.score
        end

        if tab_type == TAB_TYPE.monster then
            card_list[i] = monster_id
        else
            card_list[i] = item_id
        end

        local card_uid = card_list[i]
        if card_uid then
            local card_group_info = deck_logic:GetCardConfigByCardId(card_uid)
            if not card_group_info then
                card_group_info = {}
                card_group_info["uid"] = card_uid
                card_group_info["num"] = 0
            end

            local small_node = {}
            if tab_type == TAB_TYPE.monster then
                small_node = self.small_card_list[i]
            else
                small_node = self.small_item_list[i]
            end
            small_node:setVisible(false)

            local render = nil
                --渲染
                render = function ()
                    small_node:ShowCardGroupInfo(i, card_group_info, true)
                    local tt = (i-1) % 4 + 1
                    -- 当行渲染
                    local block = cc.CallFunc:create(function ()
                        small_node:setVisible(true)
                        if is_animation == 0 then
                            small_node:PlayAnimation("enter")
                        else
                            small_node:PlayAnimation("normal")
                        end
                    end)
                    small_node:runAction(cc.Sequence:create(cc.DelayTime:create(tt * 0.01), block))
                end
             table.insert(self.render_queue, render)
         else
            local small_node =  card_list_node[i]
            small_node:setVisible(false)
        end
    end
end

--获得卡牌信息
function meta:GetCardInfo(card_uid)
    if not CARD_CONFIG[tostring(card_uid)] then
        return
    end
    return CARD_CONFIG[tostring(card_uid)]
end

--刷新系统卡牌
function meta:RefreshSystemDeckCard(tab_type, is_animation)
    if not tab_type then
        return
    end

    self:CheckCard()

    local deck_info = pve_logic.system_card_list

    if not deck_info then
        return
    end

    local card_list = {}
    local power_value = 0

    for i = 1, 8 do
        local monster_id = deck_info.monster_list[i]
        local item_id = deck_info.item_list[i]

        if tab_type == TAB_TYPE.monster then
            card_list[i] = monster_id
        else
            card_list[i] = item_id
        end

        local card_uid = card_list[i]
        if card_uid then
            local card_group_info = self:GetCardInfo(card_uid)--deck_logic:GetDeckInfo(card_uid)
            if not card_group_info then
                card_group_info = {}
                card_group_info["uid"] = card_uid
                card_group_info["num"] = 0
            end

            local small_node = {}
            if tab_type == TAB_TYPE.monster then
                small_node = self.small_card_list[i]
            else
                small_node = self.small_item_list[i]
            end
            small_node:setVisible(false)

            local render = nil
                --渲染
                render = function ()
                    small_node:ShowCardGroupInfo(i, card_group_info, true)
                    local tt = (i-1) % 4 + 1
                    -- 当行渲染
                    local block = cc.CallFunc:create(function ()
                        small_node:setVisible(true)
                        if is_animation == 0 then
                            small_node:PlayAnimation("enter")
                        else
                            small_node:PlayAnimation("normal")
                        end
                    end)
                    small_node:runAction(cc.Sequence:create(cc.DelayTime:create(tt * 0.01), block))
                end
             table.insert(self.render_queue, render)
         else
            local small_node =  card_list[i]
            small_node:setVisible(false)
        end
    end
end

--显示卡牌详细信息
function meta:ShowCardDetail(idx)
    if self.system_card then
        if idx <= 8 then --怪兽卡牌
            local card_uid = self.deck_info.monster_list[idx]
            local card_group_info = CARD_CONFIG[card_uid]--deck_logic:GetCardByUid(card_uid)
            if not card_group_info then
                return
            end
            card_group_info.uid = card_uid
            self:DispatchGraphicEvent("show_hand_card_detail", card_group_info, idx)
        else --道具卡牌
            local card_uid = self.deck_info.item_list[idx-8]
            local card_group_info = CARD_CONFIG[card_uid]
            if not card_group_info then
                return
            end
            self:DispatchGraphicEvent("show_hand_card_detail", card_group_info, idx - 8)
        end
    else
        if idx <= 8 then --怪兽卡牌
            local card_uid = self.deck_info["monster_pos_"..idx]
            local card_group_info = deck_logic:GetCardConfigByCardId(card_uid)
            if not card_group_info then
                return
            end
            card_group_info.uid = card_uid
            self:DispatchGraphicEvent("show_hand_card_detail", card_group_info, idx)
        else --道具卡牌
            local item_id = self.deck_info["item_pos_"..(idx-8)]
            local card_group_info = deck_logic:GetCardConfigByCardId(item_id)
            if not card_group_info then
                return
            end
            self:DispatchGraphicEvent("show_hand_card_detail", card_group_info, idx - 8)
        end
    end

end

function meta:RegisterEvent()
    self:RegisterGraphic("refresh_pve_time", function ()
       self.pve_count_value:setString(tostring(pve_logic.pve_count))
    end)

    --关闭
    ui_helper:AddClick(self.close_btn, function ()
        self.open_select = false
        self:DispatchGraphicEvent("hide_gerbil_tide_panel")
        self:setVisible(false)
        self:DispatchGraphicEvent("enabled_pve_touch", true)
        self:DispatchGraphicEvent("switch_world_status", true)
        -- self:DispatchGraphicEvent("switch_system_module", "home")
    end)
    ui_helper:AddClick(self.select_btn, function ()
        if self.open_select then
            return
        end
        self.open_select = true
        self:PlayAnimation("enter_select", false, function ()
        end)
    end)
    --选择系统卡组
    ui_helper:AddClick(self.card_group1, function()
        if not self.open_select then
            return
        end
        self.system_card = true
        self.open_select = false
        self.deck_info = pve_logic.system_card_list
        local day = os.date("%w")
        local day_desc = data_template.pve_limit_config[tonumber(day)].desc
        ui_helper:SetText(self.group_name,text_loader:GetText("pve_cardgroup_mission",day_desc))
        self:RefreshSystemDeckCard(TAB_TYPE.monster, true)
        self:RefreshSystemDeckCard(TAB_TYPE.item, true)
        self:PlayAnimation("exit_select", false, function ()end)
        pve_logic.attack_type = 2
    end)
    --选择自己卡组
    ui_helper:AddClick(self.card_group2, function()
        if not self.open_select then
            return
        end
        self.system_card = false
        self.open_select = false
        -- self.deck_info = {}
        local deck_info = deck_logic:GetDeckInfo(1)
        self.deck_info = deck_info
        ui_helper:SetText(self.group_name,text_loader:GetText("pve_cardgroup_ourside"))
        self:RefreshDeckCard(self.deck_idx, TAB_TYPE.monster, true)
        self:RefreshDeckCard(self.deck_idx, TAB_TYPE.item, true)
        self:PlayAnimation("exit_select", false, function ()end)
        pve_logic.attack_type = 1
    end)
    --添加卡牌触摸
    local function item_touch(sender,event_type)
        if event_type == ccui.TouchEventType.began then
            self:ShowCardDetail(sender:getTag())
        end
        if event_type == ccui.TouchEventType.canceled  or event_type == ccui.TouchEventType.ended then
            self:DispatchGraphicEvent("hide_hand_card_detail")
        end
    end
    for i = 1, 16 do
        self.touch_list[i]:addTouchEventListener(item_touch)
    end
    --战斗按钮
    ui_helper:AddClick(self.fight_btn,function()
        if pve_logic.pve_count > 0 then       --pve次数
            if self.need_num <= 0 then        --卡牌条件
                --发送战斗请求
                self:DispatchGraphicEvent("start_fight_pve")
            else
                self:DispatchGraphicEvent("show_message", "pve_startbtn_limit",self.need_num,self.limit_color)
            end
        else
            self:DispatchGraphicEvent("show_message", "pve_startbtn_times")
        end
    end)
end

return meta
