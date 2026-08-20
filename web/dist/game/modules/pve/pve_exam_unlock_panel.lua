local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"
local resource = require "manager.resource"
local data_template = require "manager.data_template"
local pve_logic = require "logic.pve"
local POWER_CONFIG_MAP = data_template.power_config

local meta = ui_helper:NewPanel("pve_exam_unlock_panel", "interface/pve/exam/skillunlock_list.csb")

function meta:OnInit()
	--当前可以玩的最大值
	self.page_max_index = pve_logic:GetCurExamLevel(pve_logic.adv_passid)
	self.page_cur_index = self.page_max_index

	--所有冒险页面数量
	self.page_count = 0
	self.has_adv_config = {}
	for k,v in pairs(data_template.proficiency_config) do
		if v.UnlockRequest == 1 then
			table.insert(self.has_adv_config, v)
			self.page_count = self.page_count + 1
		end
	end

	self.page_list = {}

	local page_view = self:getChildByName("pageview")
	self.page_view = page_view
	self.page_view:setDirection(ccui.PageViewDirection.VERTICAL)

	local page = page_view:getChildByName("template")

	--其他页面复制这个，不会复制多余技能图片,只有原来的一个技能图片
	local page_t = page:clone()
	-- page_t:getChildByName("skill_template"):setVisible(false)
	page_t:setVisible(false)

	self:ShowPage(page, 1)
	page:getChildByName("level_bg"):getChildByName("value"):setString("1")
	page:setSwallowTouches(false)
	table.insert(self.page_list, page)


	for i = 2, self.page_count do
		local page1 = page_t:clone()
		page1:getChildByName("level_bg"):getChildByName("value"):setString(tostring(i))

		self:ShowPage(page1, i)
		page_view:addPage(page1)
		page1:setVisible(true)
		page1:setSwallowTouches(false)
		table.insert(self.page_list, page1)
	end
	self.page_view:setCurrentPageIndex(0)
	self.page_view:setSwallowTouches(false)

	self.back_btn = self:getChildByName("back_btn")

	self:RegisterWidgetEvent()
end

function meta:ShowPage(page_, index)
	if index < self.page_max_index then
		page_:getChildByName("unlock_node1"):setVisible(true)
		page_:getChildByName("unlock_node2"):setVisible(true)
		page_:getChildByName("lock_node"):setVisible(false)
	elseif index > self.page_max_index then
		page_:getChildByName("unlock_node1"):setVisible(false)
		page_:getChildByName("unlock_node2"):setVisible(false)
		page_:getChildByName("lock_node"):setVisible(true)
	else
		local pass_count = 0
		local all_count = 0
		for k,v in pairs(self.has_adv_config) do
			if index == k then
				local unlock_value = self.has_adv_config[index]["UnlockValue"] --表里面的id(最后一页所有id)
				local config_Id = pve_logic:StrSplit(unlock_value, '|')
				all_count = #config_Id
				for m,n in pairs(config_Id) do
					for a,b in pairs(pve_logic.adv_passid) do
						if n == b then
							pass_count = pass_count + 1
						end
					end
				end
				break
			end
		end
		if pass_count < all_count then
			page_:getChildByName("unlock_node1"):setVisible(false)
			page_:getChildByName("unlock_node2"):setVisible(false)
			page_:getChildByName("lock_node"):setVisible(true)
		else
			page_:getChildByName("unlock_node1"):setVisible(true)
			page_:getChildByName("unlock_node2"):setVisible(true)
			page_:getChildByName("lock_node"):setVisible(false)
		end
	end


	local name_title = page_:getChildByName("unlock_node2"):getChildByName("title")
	ui_helper:SetText(name_title, text_loader:GetText(self.has_adv_config[index]["UnlockSkillTitle"]))

	local name_desc = page_:getChildByName("unlock_node2"):getChildByName("desc")
	ui_helper:SetText(name_desc, text_loader:GetText(self.has_adv_config[index]["UnlockSkillTitle"]))


	ui_helper:SetText(page_:getChildByName("lock_node"):getChildByName("desc"), text_loader:GetText("adv_skilled_exam", index))

	--技能
	local skill_bg = page_:getChildByName("skill_template"):getChildByName("bg")
	skill_bg:setVisible(false)

	local skill_icon = page_:getChildByName("skill_template"):getChildByName("icon")
	skill_icon:setVisible(false)

	local skill_id = pve_logic:StrSplit(self.has_adv_config[index]["UnlockSkill"], '|')

	if skill_id ~= nil and skill_id ~= '' then
		local count = #skill_id

		local bg_width = skill_bg:getContentSize().width
		local bg_x = skill_bg:getPositionX()
		local pt_list = {}

		if count == 1 then
			table.insert(pt_list, skill_bg:getPositionX())
		else
			local odd_even = count % 2
			if odd_even == 0 then
				for i = 1, count do
					if i % 2 == 0 then
						table.insert(pt_list, bg_x + bg_width / 2 * i - 17)
					else
						table.insert(pt_list, bg_x - bg_width / 2 * i + 17)
					end
				end
			else
				for i = 1, count do
					if i == 1 then
						table.insert(pt_list, skill_bg:getPositionX() + 10)
					elseif i % 2 == 0 then
						table.insert(pt_list, bg_x - bg_width / 2 * i + 10)
					else
						table.insert(pt_list, bg_x + bg_width / 2 * (i - 1) + 10)
					end
				end
			end
		end

		local name = {}
		for i = 1, count do
			for k,v in pairs(POWER_CONFIG_MAP) do
				if tostring(v.ID) == tostring(skill_id[i]) then
					table.insert(name, k)
					break
				end
			end
		end

		for i = 1, count do
			local bg = skill_bg:clone()
			bg:setPosition(pt_list[i], skill_bg:getPositionY())
			bg:setVisible(true)
			skill_bg:getParent():addChild(bg)

			local icon = skill_icon:clone()
			icon:setVisible(true)
			icon:setPosition(pt_list[i], skill_bg:getPositionY())
			skill_bg:getParent():addChild(icon)

			icon:loadTexture(resource:GetSkillIcon(name[i]))

			-- local equip_card_node = ui_helper:ExpandUI(self, "equip_card", "modules.common.card_hand_item")
			-- equip_card_node:setPosition(pt_list[i], skill_bg:getPositionY())
		end
	end
end

function meta:OnExit()

end

function meta:Updata()
end

function meta:Show(index)
	self.page_view:scrollToPage(index)

	self:setVisible(true)
end

function meta:Hide()
	self:setVisible(false)
end

function meta:RegisterEvent()

end

function meta:RegisterWidgetEvent()
	ui_helper:AddClick(self.back_btn, function ()
		self:DispatchGraphicEvent("pop_world_panel")
	end)
end

return meta
