local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local pve_logic = require "logic.pve"
local text_loader = require "manager.text_loader"
local meta = ui_helper:NewPanel("pve_gerbil_tide", "interface/pve/pve_panel.csb")

function meta:OnInit()
    --下面卡牌界面
    self.card_group = require("modules.pve.pve_cardgroup_panel").new()
    self:addChild(self.card_group)
    local level_info = self:getChildByName("level_info")
    self.level_info = level_info
    -- local level_template = level_info:getChildByName("level_list"):getChildByName("level_template")
    self.move_step = 0
    self.arrow1_btn = level_info:getChildByName("arrow1_btn")
    self.arrow2_btn = level_info:getChildByName("arrow2_btn")
    self.arrow1_icon = level_info:getChildByName("arrow1")
    self.arrow2_icon = level_info:getChildByName("arrow2")
    self.reward_node_list = {}
    -- local unfinished_node = level_template:getChildByName("unfinished_node")
    --当前玩法关卡数
    local pve_level_count = 0
    for _, v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == tonumber(pve_logic.play_id) and tonumber(v.difficulty) == tonumber(pve_logic.difficulty) then
            self.limit_card_num = v.limit_card_num
        end
        if tonumber(v.play_id) == tonumber(pve_logic.play_id) then
            pve_level_count = pve_level_count + 1
        end
    end
    local level_type = 0
    if pve_logic.play_id == 1001 then
        level_type = 1
    end
    self.level_type = level_type
    self.pve_level_count = pve_level_count
    self.page_list = {}
    --翻页
    local page_node = level_info:getChildByName("level_list")
    self.page_node = page_node
    local page = page_node:getChildByName("level_template")
    self.page_cur_index = pve_logic.cur_difficulty
    self:ShowLevelInfo(level_type,page,0)
    table.insert(self.page_list,page)
    --添加关卡翻页
    for i = 1 ,pve_level_count-1 do
        local page_ = page:clone()
        self:ShowLevelInfo(level_type,page_,i)
        page_node:addPage(page_)
        table.insert(self.page_list,page_)
    end
    for k, _ in pairs (self.page_list) do
        self.page_list[k]:setSwallowTouches(false)
    end
    self.page_node:setCurrentPageIndex(pve_logic.cur_difficulty - 1)
    self.page_node:setSwallowTouches(false)
    self:RegisterWidgetEvent()
    self:RegisterTouchEvent()
    self:setVisible(false)
end

function meta:OnEnter()

end

--添加 奖励ITEM
function meta:AddRewardItem(node)
    if not node:getChildByName("reward1") then
        local reward1 = ui_helper:LoadCocosUI("interface/common/itemicon_template.csb")
        local reward2 = ui_helper:LoadCocosUI("interface/common/itemicon_template.csb")
        reward1:setScale(0.72)
        reward2:setScale(0.72)
        node:addChild(reward1,100)
        node:addChild(reward2,100)
        reward1:setPosition(node:getChildByName("rewardbg1"):getPosition())
        reward2:setPosition(node:getChildByName("rewardbg2"):getPosition())
        reward1:setName("reward1")
        reward2:setName("reward2")
    end
end

--关卡描述信息 及 奖励
function meta:ShowLevelInfo(_, page_,index)
    local unfinished_node = page_:getChildByName("unfinished_node")
    local reward_list = {}
    reward_list.reward_id = {}
    reward_list.reward_num = {}
    --得到奖励组
    local pve_play_id = tonumber(pve_logic.play_id .. index+1)
    local cur_pve_play_config = data_template.pve_play_config[pve_play_id]
    local reward = {}

    local reward2 = {}
    ui_helper:SetText(unfinished_node:getChildByName("level_desc"),text_loader:GetText("mission_difficulty_desc",index + 1))

    --index 0,1,2,3  dif 1,2,3,4,5...
    if (pve_logic.cur_difficulty - 1 > index) then  --pass
        ui_helper:SetText(unfinished_node:getChildByName("reward_desc"),text_loader:GetText("pve_reward_desc"))

        reward.reward_res = cur_pve_play_config.reward_type1
        reward.reward_id = cur_pve_play_config.reward_id1
        reward.reward_num = cur_pve_play_config.reward_num1
        table.insert(reward_list,reward)

        reward2.reward_res = cur_pve_play_config.reward_type2
        reward2.reward_id = cur_pve_play_config.reward_id2
        reward2.reward_num = cur_pve_play_config.reward_num2
        table.insert(reward_list,reward2)

    else
        ui_helper:SetText(unfinished_node:getChildByName("reward_desc"),text_loader:GetText("pve_first_reward_desc"))
        reward.reward_res = cur_pve_play_config.first_reward_type1
        reward.reward_id = cur_pve_play_config.first_reward_id1
        reward.reward_num = cur_pve_play_config.first_reward_num1
        table.insert(reward_list,reward)

        reward2.reward_res = cur_pve_play_config.first_reward_type2
        reward2.reward_id = cur_pve_play_config.first_reward_id2
        reward2.reward_num = cur_pve_play_config.first_reward_num2
        table.insert(reward_list,reward2)
    end

    --增加奖励 item
    self:AddRewardItem(unfinished_node)
    local reward_node_list = {}
    for i = 1, 2 do
        local reward_node = ui_helper:ExpandUI(unfinished_node, "reward"..i, "modules.common.material_item")
        reward_node:setVisible(false)
        reward_node_list[i] = reward_node
    end
    --显示奖励
    for i = 1, 2 do
        local reward_node = reward_node_list[i]
        if reward_list[i] then
            reward_node:setVisible(true)
            local reward_info = {}
            reward_info.type = reward_list[i].reward_res
            reward_info.attr_id = reward_list[i].reward_id
            reward_info.value = reward_list[i].reward_num
            reward_node:ShowReward(reward_info)
        else
            reward_node:setVisible(false)
        end
    end

end

function meta:Show()
    self:setVisible(true)
    self.card_group:setVisible(true)
    if pve_logic.attack_type == 1 then
        self.card_group:Show()
    end
    for k,v in pairs (self.page_list) do
        if k ~= self.page_node:getCurrentPageIndex()+1 then
            v:setVisible(false)
        end
    end
    self:PlayAnimation("enter", false, function ()
         for _, v in pairs (self.page_list) do
            v:setVisible(true)
        end
    end)
    self.card_group:PlayAnimation("enter", false, function ()
    end)
end
function meta:Update(_)

    if self.page_node  and self.page_cur_index ~= self.page_node:getCurrentPageIndex()+1 then
        self.card_group:SetPveTips(self.page_node:getCurrentPageIndex()+1)
        self:SetInfo(self.page_node:getCurrentPageIndex()+1)
        self.page_cur_index = self.page_node:getCurrentPageIndex()+1
        pve_logic.difficulty = self.page_cur_index
    end
end
function meta:Hide()
     self:setVisible(false)
end

function meta:SetInfo(index)
    self.arrow1_icon:setVisible(true)
    self.arrow2_icon:setVisible(true)
    if index <= 1 then
        self.arrow1_icon:setVisible(false)
    elseif index >= #self.page_list then
        self.arrow2_icon:setVisible(false)
    end
    local pve_play_id = tonumber(pve_logic.play_id .. index)
    local pve_info = data_template.pve_play_config[pve_play_id]

    if index <= self.pve_level_count and pve_info then
        local page_node = self.page_list[index]
        local unfinished_node = page_node:getChildByName("unfinished_node")
        local level_info = self.level_info
        local pve_desc = "pve_misson"..tostring(self.level_type)
        local pve_play_id = tonumber(pve_logic.play_id .. index)
        local pve_info = data_template.pve_play_config[pve_play_id]
        ui_helper:SetText(level_info:getChildByName("title"),text_loader:GetText(pve_info.play_name))
        ui_helper:SetText(level_info:getChildByName("desc"),text_loader:GetText(pve_info.play_desc))
        ui_helper:SetText(level_info:getChildByName("tip_desc"),text_loader:GetText(pve_info.tips))
        ui_helper:SetText(page_node:getChildByName("finished_node"):getChildByName("desc"),text_loader:GetText("pve_finished_desc",index))
        --是否已通关
        unfinished_node:setVisible(true)
        page_node:getChildByName("monster"):setColor(ui_helper:GetColor4B(0xFFFFFF))
        page_node:getChildByName("lock_node"):setVisible(false)
        --关卡未开启
        if tonumber(pve_logic.cur_difficulty) < index then
            page_node:getChildByName("lock_node"):setVisible(true)
            page_node:getChildByName("monster"):setColor(ui_helper:GetColor4B(0x7F7F7F))
        end
    end
end

function meta:RegisterEvent()
    self:RegisterGraphic("pve_gerbil_panel_fresh", function ()
        for k,v in pairs(self.page_list) do
            self:ShowLevelInfo(self.level_type, v, k - 1)
        end
    end)
end

function meta:RegisterWidgetEvent()
    --左滚动按钮
    ui_helper:AddClick(self.arrow1_btn,function()
        -- local nexts = pve_logic.difficulty - 1
        local nexts = self.page_node:getCurrentPageIndex()
        self.page_node:scrollToPage(nexts-1)
    end)
    --右滚动按钮
    ui_helper:AddClick(self.arrow2_btn,function()
        -- local nexts = pve_logic.difficulty - 1
        local nexts = self.page_node:getCurrentPageIndex()
        self.page_node:scrollToPage(nexts+1)
    end)
end
-- 注册触摸事件
function meta:RegisterTouchEvent()
    self:RegisterGraphic("start_fight_pve",function()
        local difficulty = self.page_node:getCurrentPageIndex()+1
        pve_logic:StartFight(pve_logic.play_id,difficulty,pve_logic.attack_type)
    end)

    self:RegisterGraphic("hide_gerbil_tide_panel",function()
        self:Hide()
    end)

    local function onTouchBegin(_, _)
        if not self:isVisible() then
            return
        end
        if self.open_select == true then
            self.open_select = false
            self.card_group:PlayAnimation("exit_select", false, function ()

            end)
        end
    end
    local listener = cc.EventListenerTouchOneByOne:create();
    listener:setSwallowTouches(false)
    listener:registerScriptHandler(onTouchBegin,cc.Handler.EVENT_TOUCH_BEGAN);
    local event_dispatcher = cc.Director:getInstance():getEventDispatcher()
    event_dispatcher:addEventListenerWithSceneGraphPriority(listener, self);
end
return meta
