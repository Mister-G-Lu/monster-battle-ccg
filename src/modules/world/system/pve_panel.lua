
local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local pve_logic = require "logic.pve"
local user_logic = require "logic.user"
local text_loader = require "manager.text_loader"
local meta = ui_helper:NewPanel("pve_panel", "interface/pve/pve_list.csb")

-- Gerbip Tide (play_id 1001) is archived: its mission entry, its panel and the
-- mirrored-deck viewer it opened are all gone from this build.  The list below
-- keeps only the exam entry.  See archive/gerbip_tide/README.md.

function meta:OnInit()
    ui_helper:SetText(self:getChildByName("title"), text_loader:GetText("adv_main_title"))

    self.clost_btn = self:getChildByName("back_btn")
    self.scroll_view = self:getChildByName("Scroll_View")

    self.pve_board_college = ui_helper:LoadCocosUI("interface/pve/exam_template.csb")
    self.board_college_template = self.pve_board_college:getChildByName("exam_template")
    self:InitBoardCollege()
    self.board_college_template:setVisible(false)

    self:RefreshPvePanel()
    self:RegisterWidgetEvent()
end

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

function meta:RefreshPvePanel()
    -- (Gerbip Tide progress line removed with the mode; see archive/gerbip_tide)
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
    if self.pve_exam_panel then
        self.pve_exam_panel:Update(elapsed_time)
    end
end

function meta:Hide()
    self:setVisible(false)
end
function meta:RegisterEvent()
    -- "show_gerbil_tide_panel" is deliberately not registered: the panel it
    -- opened is archived, so requiring it would fail.

    self:RegisterGraphic("show_exam_panel", function ()
        if self.pve_exam_panel then
            self.pve_exam_panel:Show()
        else
            self.pve_exam_panel = require("modules.pve.pve_exam_panel").new()
            self:addChild(self.pve_exam_panel)
            self.pve_exam_panel:Show()
        end

        self.board_college_template:setTouchEnabled(false)
    end)

    self:RegisterGraphic("enabled_pve_touch",function(touch)
        self.board_college_template:setTouchEnabled(touch)
    end)

    self:RegisterGraphic("pve_gerbil_over", function ()
        self:RefreshPvePanel()
    end)

end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.clost_btn, function ()
        self:DispatchGraphicEvent("switch_system_module", "home",true)
        self:Hide()
    end)

end

return meta
