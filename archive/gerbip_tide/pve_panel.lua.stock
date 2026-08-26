
local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local pve_logic = require "logic.pve"
local user_logic = require "logic.user"
local text_loader = require "manager.text_loader"
local meta = ui_helper:NewPanel("pve_panel", "interface/pve/pve_list.csb")

local PVE_GERBIL_TIDE_ID = "1001"

function meta:OnInit()
    ui_helper:SetText(self:getChildByName("title"), text_loader:GetText("adv_main_title"))

    --鼠潮
    self.pve_gerbil_tide = ui_helper:LoadCocosUI("interface/pve/mission_template.csb")
    self.gerbil_tide_template = self.pve_gerbil_tide:getChildByName("mission_template")
    self:InitGerbilTide()

    --多伦多牌士学院
    self.pve_board_college = ui_helper:LoadCocosUI("interface/pve/exam_template.csb")
    self.board_college_template = self.pve_board_college:getChildByName("exam_template")
    self:InitBoardCollege()
    self.board_college_template:setVisible(false)

    self:RefreshPvePanel()
    self:RegisterWidgetEvent()
end

--鼠潮
function meta:InitGerbilTide()
    ui_helper:SetText(self.gerbil_tide_template:getChildByName("title"), text_loader:GetText("gerbil_tide_title"))
    ui_helper:SetText(self.gerbil_tide_template:getChildByName("schedule"):getChildByName("title"), text_loader:GetText("progress_text"))
    self.mission_tips = self.gerbil_tide_template:getChildByName("tip")
    self.mission_schedule = self.gerbil_tide_template:getChildByName("schedule"):getChildByName("value")
    self.clost_btn = self:getChildByName("back_btn")
    self.scroll_view = self:getChildByName("Scroll_View")
    self.scroll_view:addChild(self.pve_gerbil_tide)
    local pos_x = self.gerbil_tide_template:getContentSize().width/2
    -- local pos_y = self.scroll_view:getContentSize().height / 4 - 12
    local pos_y = self.scroll_view:getContentSize().height / 2
    self.pve_gerbil_tide:setPosition(cc.p(pos_x,pos_y))
    ui_helper:AddClick(self.gerbil_tide_template, function ()
        pve_logic:Query(PVE_GERBIL_TIDE_ID) -- 获取PVE界面信息
    end)
end

--学院
function meta:InitBoardCollege()
    self.college_lock = self.board_college_template:getChildByName("lock")
    self.college_tip = self.board_college_template:getChildByName("tip")
    self.college_decorate = self.board_college_template:getChildByName("decorate")
    self.college_schedule = self.board_college_template:getChildByName("schedule")
    self.college_schedule:setLocalZOrder(self.college_decorate:getLocalZOrder() + 1)
    self.college_schedule_title = self.college_schedule:getChildByName("title")
    self.college_schedule_value = self.college_schedule:getChildByName("value")

    ui_helper:SetText(self.board_college_template:getChildByName("title"), text_loader:GetText("exam_college"))
    ui_helper:SetText(self.college_schedule_title, text_loader:GetText("progress_text"))
    ui_helper:SetText(self.college_lock:getChildByName("desc"), text_loader:GetText("exam_college_skilled"))

    local pos_x = self.board_college_template:getContentSize().width / 2
    local pos_y = self.scroll_view:getContentSize().height / 4 * 3 + 10
    self.pve_board_college:setPosition(pos_x, pos_y)
    self.scroll_view:addChild(self.pve_board_college)

end

--刷新
function meta:RefreshPvePanel()
    --鼠潮
    local pve_data = pve_logic.login_pve_data

    if pve_logic.pve_count <= 0 then self.mission_tips:setVisible(false) end

    local ger_count = 0
    for _,v in pairs(data_template.pve_play_config) do
        if v.play_id == PVE_GERBIL_TIDE_ID then
            ger_count = ger_count + 1
        else
        end
    end

    for k,v in pairs(pve_data) do
        if tostring(v.play_id) == PVE_GERBIL_TIDE_ID then
            self.mission_schedule:setString(v.difficulty .. "/" .. ger_count)
        end
    end


    --学院
    local cur_pro = user_logic.exp

    local pro_data = data_template.proficiency_config
    local one_exp = pro_data[1]["exp"]

    if cur_pro >= one_exp or user_logic.level > 1 then
    -- if nil then
        self.college_tip:setVisible(false)

        self.college_lock:setVisible(false)
        self.college_schedule:setVisible(true)

        local cur_level = pve_logic:GetCurExamLevel(pve_logic.adv_passid)
        local all_pro = 0
        for k,v in pairs(data_template.adventure_config) do
            if tonumber(cur_level) == tonumber(v.exam_level) then
                all_pro = all_pro + 1
            elseif cur_level < tonumber(v.exam_level) then
                    break
            end
        end
        local progress = 0
        if next(pve_logic.adv_passid) == nil then
            progress = 0
        else
            for k,v in pairs(pro_data) do
                if cur_level == k then
                    local split_unlock = pve_logic:StrSplit(v["UnlockValue"], '|')
                    for _,n in pairs(split_unlock) do
                        for _,b in pairs(pve_logic.adv_passid) do
                            if tonumber(n) == tonumber(b) then
                                progress = progress + 1
                                break
                            end
                        end
                    end
                    break
                end
            end
        end

        self.college_schedule_value:setString(progress .. "/" .. all_pro)
    else
        self.college_tip:setVisible(true)

        self.college_lock:setVisible(true)
        self.college_schedule:setVisible(false)
    end

    ui_helper:AddClick(self.board_college_template, function ()
        local cur_pro = user_logic.exp
        local one_exp = data_template.proficiency_config[1]["exp"]
        if cur_pro >= one_exp or user_logic.level > 1 then
            pve_logic:QueryExam()
        end
    end)
end

function meta:Show()
    self:RefreshPvePanel()
    self:setVisible(true)
end

function meta:Update(elapsed_time)
    if self.pve_gerbil_tide_panel then
        self.pve_gerbil_tide_panel:Update(elapsed_time)
        self.pve_gerbil_tide_panel.card_group:Update(elapsed_time)
    end

    if self.pve_exam_panel then
        self.pve_exam_panel:Update(elapsed_time)
    end
end

function meta:Hide()
    self:setVisible(false)
end
--界面增加 显示
function meta:RegisterEvent()
    --鼠潮
    self:RegisterGraphic("show_gerbil_tide_panel",function()
        if self.pve_gerbil_tide_panel then
            self.pve_gerbil_tide_panel:Show()
        else
            self.pve_gerbil_tide_panel  = require("modules.pve.pve_gerbil_tide_panel").new()
            self:addChild(self.pve_gerbil_tide_panel)
            self.pve_gerbil_tide_panel:Show()
        end
        self.gerbil_tide_template:setTouchEnabled(false)
        self.board_college_template:setTouchEnabled(false)
    end)

    --考试
    self:RegisterGraphic("show_exam_panel", function ()
        if self.pve_exam_panel then
            self.pve_exam_panel:Show()
        else
            self.pve_exam_panel = require("modules.pve.pve_exam_panel").new()
            self:addChild(self.pve_exam_panel)
            self.pve_exam_panel:Show()
        end

        self.gerbil_tide_template:setTouchEnabled(false)
        self.board_college_template:setTouchEnabled(false)
    end)

    self:RegisterGraphic("enabled_pve_touch",function(touch)
        self.gerbil_tide_template:setTouchEnabled(touch)
        self.board_college_template:setTouchEnabled(touch)
    end)

    --战斗结束时候刷新
    self:RegisterGraphic("pve_gerbil_over", function ()
        self.gerbil_tide_template:setTouchEnabled(true)
        self:RefreshPvePanel()
    end)

end

function meta:RegisterWidgetEvent()
    --关闭按钮
    ui_helper:AddClick(self.clost_btn, function ()
        self:DispatchGraphicEvent("switch_system_module", "home",true)
        self:Hide()
    end)

end

return meta
