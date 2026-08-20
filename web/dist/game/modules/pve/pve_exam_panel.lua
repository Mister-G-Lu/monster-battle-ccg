local ui_helper = require "manager.ui_helper"
local pve_logic = require "logic.pve"
local user_logic = require "logic.user"
local data_template = require "manager.data_template"
local text_loader = require "manager.text_loader"

local meta = ui_helper:NewPanel("pve_exam_panel", "interface/pve/exam/exam_detail_panel.csb")

function meta:OnInit()
	--当前可以玩的最大值
	self.page_max_index = pve_logic:GetCurExamLevel(pve_logic.adv_passid)
	self.page_cur_index = self.page_max_index

	self.up_page_idx = self.page_cur_index
	self.down_pade_idx = self.page_cur_index

	--所有冒险页面数量
	self.page_count = 0
	self.has_adv_config = {}
	for k,v in pairs(data_template.proficiency_config) do
		if v.UnlockRequest == 1 then
			table.insert(self.has_adv_config, v)
			self.page_count = self.page_count + 1
		end
	end

	--标题
	self.title = self:getChildByName("titlebg"):getChildByName("title")
	ui_helper:SetText(self.title, text_loader:GetText("adv_skilled_exam", 1))

	---------------上面的page------------
	self.page_list_up = {}

	local page_viewup = self:getChildByName("pageview_number")
	page_viewup:setContentSize(page_viewup:getContentSize().width + 50, page_viewup:getContentSize().height)
	self.page_viewup = page_viewup

	local page = page_viewup:getChildByName("template_number")
	page:getChildByName("level_bg"):getChildByName("value"):setString("1")
	self:ShowUpPageInfo(page, 1)
	page:setSwallowTouches(false)
	table.insert(self.page_list_up, page)

	local page_count = self.page_count
	for i = 2, page_count do
		local page_1 = page:clone()
		page_1:getChildByName("level_bg"):getChildByName("value"):setString(tostring(i))

		self:ShowUpPageInfo(page_1, i)
		page_viewup:addPage(page_1)
		page_1:setSwallowTouches(false)
		table.insert(self.page_list_up, page_1)
	end
	self.page_viewup:setCurrentPageIndex(self.page_cur_index - 1)
	self.page_viewup:setSwallowTouches(false)

	self.left_arrow_btn = self:getChildByName("page_btn1")
	self.left_arrow_icon = self.left_arrow_btn:getChildByName("icon")

	self.right_arrow_btn = self:getChildByName("page_btn2")
	self.right_arrow_icon = self.right_arrow_btn:getChildByName("icon")

	self:Refresh(self.page_cur_index)


	------------下面的page--------------
	self.page_list_down = {}
	local page_viewdown = self:getChildByName("pageview_content")
	self.page_viewdown = page_viewdown

	local template_content = page_viewdown:getChildByName("template_content")

	-- self.per_page_list = {}
	self.page_t1 = template_content:getChildByName("template_exam")
	-- table.insert(self.per_page_list, self.page_t1)

	if not template_content:getChildByName("template_exam2") then
		self.page_t2 = self.page_t1:clone()
		template_content:addChild(self.page_t2)
		self.page_t2:setName("template_exam2")
		-- table.insert(self.per_page_list, self.page_t2)
	end

	if not template_content:getChildByName("template_exam3") then
		self.page_t3 = self.page_t1:clone()
		template_content:addChild(self.page_t3)
		self.page_t3:setName("template_exam3")
		-- table.insert(self.per_page_list, self.page_t3)
	end

	self:ShowDownPageInfo(template_content, 1)
	template_content:setSwallowTouches(false)
	table.insert(self.page_list_down, template_content)

	for i = 2, page_count do
		local page_1 = template_content:clone()

		page_viewdown:addPage(page_1)
		page_1:setSwallowTouches(false)
		self:ShowDownPageInfo(page_1, i)
		table.insert(self.page_list_down, page_1)
	end
	self.page_viewdown:setCurrentPageIndex(self.page_cur_index - 1)
	self.page_viewdown:setSwallowTouches(false)

	--返回按钮
	self.back_btn = self:getChildByName("back_btn")

	self:RegisterWidgetEvent()
end

--上面pageview
function meta:ShowUpPageInfo(page_, index)
	--判断勾号是否显示
	local proficiency_config = data_template.proficiency_config

	local unlock_value = self.has_adv_config[index]["UnlockValue"] --表里面的id(最后一页所有id)
	local config_Id = pve_logic:StrSplit(unlock_value, '|')

	if self.page_max_index == index then
		local isLock = false
		if next(pve_logic.adv_passid) == nil then
			isLock = true
		else
			for _,m in pairs(config_Id) do
				for _,v in pairs(pve_logic.adv_passid) do
					if tonumber(v) == tonumber(m) then  --unlock
						isLock = false
						break
					else
						isLock = true
					end
				end
				if isLock then
					break
				end
			end
		end

		if isLock then
			page_:getChildByName("level_bg"):getChildByName("tip"):setVisible(false)
		else
			page_:getChildByName("level_bg"):getChildByName("tip"):setVisible(true)
		end
	elseif self.page_max_index > index then
		page_:getChildByName("level_bg"):getChildByName("tip"):setVisible(true)
	else
		page_:getChildByName("level_bg"):getChildByName("tip"):setVisible(false)
	end

end

--下面pageview
function meta:ShowDownPageInfo(page_, index)
	--判断勾号是否显示
	local unlock_value = self.has_adv_config[index]["UnlockValue"] --表里面的id(最后一页所有id)

	local config_Id = pve_logic:StrSplit(unlock_value, '|')

	local count = #config_Id

	local pageHeight = page_:getContentSize().height

	if count == 3 then
		local page_list1 = page_:getChildByName("template_exam")
		page_list1:setPositionY(pageHeight / 8 * 7 - 65)
		page_list1:setTag(config_Id[1])
		page_list1:setVisible(true)
		self:DownPageList(page_list1, 1, config_Id[1], index)
		self:PageBattleClick(page_list1, index)

		local page_list2 = page_:getChildByName("template_exam2")
		page_list2:setPositionY(pageHeight / 8 * 5 - 60)
		page_list2:setTag(config_Id[2])
		page_list2:setVisible(true)
		self:DownPageList(page_list2, 2, config_Id[2], index)
		self:PageBattleClick(page_list2, index)

		local page_list3 = page_:getChildByName("template_exam3")
		page_list3:setPositionY(pageHeight / 8 * 3 - 50)
		page_list3:setTag(config_Id[3])
		page_list3:setVisible(true)
		self:DownPageList(page_list3, 3, config_Id[3], index)
		self:PageBattleClick(page_list3, index)

		page_:getChildByName("template_skillunlock"):setPositionY(71)
	elseif count == 2 then
		local page_list1 = page_:getChildByName("template_exam")
		page_list1:setPositionY(pageHeight / 6 * 5 - 100)
		page_list1:setTag(config_Id[1])
		page_list1:setVisible(true)
		self:DownPageList(page_list1, 1, config_Id[1], index)
		self:PageBattleClick(page_list1, index)

		local page_list2 = page_:getChildByName("template_exam2")
		page_list2:setPositionY(pageHeight / 2 - 20)
		page_list2:setTag(config_Id[2])
		page_list2:setVisible(true)
		self:DownPageList(page_list2, 2, config_Id[2], index)
		self:PageBattleClick(page_list2, index)

		page_:getChildByName("template_exam3"):setVisible(false)

		page_:getChildByName("template_skillunlock"):setPositionY(200)
	elseif count == 1 then
		local page_list1 = page_:getChildByName("template_exam")
		page_list1:setPositionY(pageHeight / 4 * 3 - 140)
		page_list1:setTag(config_Id[1])
		page_list1:setVisible(true)
		self:DownPageList(page_list1, 1, config_Id[1], index)
		self:PageBattleClick(page_list1, index)

		page_:getChildByName("template_exam2"):setVisible(false)
		page_:getChildByName("template_exam3"):setVisible(false)

		page_:getChildByName("template_skillunlock"):setPositionY(310)
	elseif count == 0 then
		page_:getChildByName("template_skillunlock"):setPositionY(pageHeight / 2)
	else

	end

	local pass_table = pve_logic.adv_passid or {}

	local is_all_pass = 0
	if self.page_max_index == index then
		if next(pass_table) == nil then
			page_:getChildByName("template_exam"):getChildByName("lock_node"):setVisible(true)
			page_:getChildByName("template_exam"):getChildByName("unlock_node"):setVisible(false)

			page_:getChildByName("template_exam2"):getChildByName("lock_node"):setVisible(true)
			page_:getChildByName("template_exam2"):getChildByName("unlock_node"):setVisible(false)

			page_:getChildByName("template_exam3"):getChildByName("lock_node"):setVisible(true)
			page_:getChildByName("template_exam3"):getChildByName("unlock_node"):setVisible(false)

			page_:getChildByName("template_skillunlock"):getChildByName("lock_node"):setVisible(true)
			page_:getChildByName("template_skillunlock"):getChildByName("unlock_node"):setVisible(false)
		else
			for _,m in pairs(config_Id) do   --3,4
				for _, v in pairs(pass_table) do  --1,2,3
					if tonumber(v) == tonumber(m) then  --unlock
						local list
						if m == config_Id[1] then
							list = page_:getChildByName("template_exam")
						elseif m == config_Id[2] then
							list = page_:getChildByName("template_exam2")
						elseif m == config_Id[3] then
							list = page_:getChildByName("template_exam3")
						else

						end

						is_all_pass = is_all_pass + 1
						list:getChildByName("lock_node"):setVisible(false)
						list:getChildByName("unlock_node"):setVisible(true)

						break
					else
						local list
						if m == config_Id[1] then
							list = page_:getChildByName("template_exam")
						elseif m == config_Id[2] then
							list = page_:getChildByName("template_exam2")
						elseif m == config_Id[3] then
							list = page_:getChildByName("template_exam3")
						else

						end

						list:getChildByName("lock_node"):setVisible(true)
						list:getChildByName("unlock_node"):setVisible(false)
					end
				end
			end
			if is_all_pass < count then  --lock
				page_:getChildByName("template_skillunlock"):getChildByName("lock_node"):setVisible(true)
				page_:getChildByName("template_skillunlock"):getChildByName("unlock_node"):setVisible(false)
			else
				page_:getChildByName("template_skillunlock"):getChildByName("lock_node"):setVisible(false)
				page_:getChildByName("template_skillunlock"):getChildByName("unlock_node"):setVisible(true)
			end
		end

	elseif self.page_max_index > index then
		page_:getChildByName("template_exam"):getChildByName("lock_node"):setVisible(false)
		page_:getChildByName("template_exam"):getChildByName("unlock_node"):setVisible(true)

		page_:getChildByName("template_exam2"):getChildByName("lock_node"):setVisible(false)
		page_:getChildByName("template_exam2"):getChildByName("unlock_node"):setVisible(true)

		page_:getChildByName("template_exam3"):getChildByName("lock_node"):setVisible(false)
		page_:getChildByName("template_exam3"):getChildByName("unlock_node"):setVisible(true)

		page_:getChildByName("template_skillunlock"):getChildByName("lock_node"):setVisible(false)
		page_:getChildByName("template_skillunlock"):getChildByName("unlock_node"):setVisible(true)

	else
		page_:getChildByName("template_exam"):getChildByName("lock_node"):setVisible(true)
		page_:getChildByName("template_exam"):getChildByName("unlock_node"):setVisible(false)

		page_:getChildByName("template_exam2"):getChildByName("lock_node"):setVisible(true)
		page_:getChildByName("template_exam2"):getChildByName("unlock_node"):setVisible(false)

		page_:getChildByName("template_exam3"):getChildByName("lock_node"):setVisible(true)
		page_:getChildByName("template_exam3"):getChildByName("unlock_node"):setVisible(false)

		page_:getChildByName("template_skillunlock"):getChildByName("lock_node"):setVisible(true)
		page_:getChildByName("template_skillunlock"):getChildByName("unlock_node"):setVisible(false)
	end


	--技能解锁提示
	ui_helper:SetText(page_:getChildByName("template_skillunlock"):getChildByName("lock_node"):getChildByName("desc"), text_loader:GetText("adv_skilled_exam", index))
	--守则名称
	local name_node = page_:getChildByName("template_skillunlock"):getChildByName("unlock_node"):getChildByName("title")
	ui_helper:SetText(name_node, text_loader:GetText(self.has_adv_config[index]["UnlockSkillTitle"]))


	self:PageGuideClick(page_:getChildByName("template_skillunlock"), index)
end

--下面pageview多个挑战  --page_list每一页多个挑战的列表，list_idx列表索引   config_id列表对应的配置文件id index第几页
function meta:DownPageList(page_list, list_idx, config_id, index)

	self:AddRewardItem(page_list, config_id, index)

	if list_idx == 1 then
		page_list:getChildByName("unlock_node"):getChildByName("number"):setString("1")
	elseif list_idx == 2 then
		page_list:getChildByName("unlock_node"):getChildByName("number"):setString("2")
	elseif list_idx == 3 then
		page_list:getChildByName("unlock_node"):getChildByName("number"):setString("3")
	end
end

--添加奖励item/card
function meta:AddRewardItem(page_node, config_id, index)
	local adv_config = data_template.adventure_config[tonumber(config_id)]

	local item = page_node:getChildByName("unlock_node")

	if item:getChildByName("reward_item"):getChildByName("icon") then
		item:getChildByName("reward_item"):getChildByName("icon"):setVisible(false)
	end

	if item:getChildByName("reward_card") then
		item:getChildByName("reward_card"):setVisible(false)
	end

	--胜利条件
	ui_helper:SetText(item:getChildByName("title"), text_loader:GetText(adv_config["win_target"]))
	--描述
	ui_helper:SetText(item:getChildByName("desc"), text_loader:GetText(adv_config["play_desc"]))
	--未通关描述
	ui_helper:SetText(page_node:getChildByName("lock_node"):getChildByName("desc"), text_loader:GetText("adv_skilled_exam", index))

	--获得奖励
	local reward_type = adv_config["reward_type1"]
    local reward_id = adv_config["reward_id1"]
    local reward_num = adv_config["reward_num1"]

    if item:getChildByName("reward1") then
    	item:getChildByName("reward1"):removeFromParent()
    end
	if not item:getChildByName("reward1") then
		local reward = ui_helper:LoadCocosUI("interface/common/itemicon_template.csb")
		reward:setScale(0.72)
		item:addChild(reward)
		reward:setPosition(item:getChildByName("reward_item"):getPositionX(), item:getChildByName("reward_item"):getPositionY())
		reward:setName("reward1")
	end

	local reward_node = ui_helper:ExpandUI(item, "reward1", "modules.common.material_item")
	reward_node:setVisible(true)
	local reward_info = {}
    reward_info.type = reward_type
    reward_info.attr_id = reward_id
    reward_info.value = reward_num
    reward_node:ShowReward(reward_info)

    if reward_type == "resource" then
    	local item_config = data_template.item_config[reward_id]
    	item:getChildByName("reward_desc"):setString(item_config["name"] .. " X" .. tostring(reward_num))
    elseif reward_type == "card" then
    	local item_config = data_template.chest_config[reward_id]
    	item:getChildByName("reward_desc"):setString(item_config["name"] .. " X" .. tostring(reward_num))
    elseif reward_type == "chest" then
    	local item_config = data_template.card_config[reward_id]
    	item:getChildByName("reward_desc"):setString(item_config["name"] .. " X" .. tostring(reward_num))
    else
    	print("no reward_type")
    end
end

function meta:OnExit()

end

function meta:Show()
	self:setVisible(true)
end

function meta:Hide()
	self:setVisible(false)
end

function meta:Update(elapsed_time)
	if self.page_viewup then
		if self.up_page_idx ~= self.page_viewup:getCurrentPageIndex() then
			self.up_page_idx = self.page_viewup:getCurrentPageIndex()
			self.page_viewdown:scrollToPage(self.up_page_idx)

			self.page_cur_index = self.up_page_idx

			self:Refresh(self.page_viewup:getCurrentPageIndex() + 1)
			self:Refresh(self.page_viewdown:getCurrentPageIndex() + 1)
		end
	end

	if self.page_viewdown then
		if self.down_page_idx ~= self.page_viewdown:getCurrentPageIndex() then
			self.down_page_idx = self.page_viewdown:getCurrentPageIndex()
			self.page_viewup:scrollToPage(self.down_page_idx)

			self.page_cur_index = self.down_page_idx

			self:Refresh(self.page_viewup:getCurrentPageIndex() + 1)
			self:Refresh(self.page_viewdown:getCurrentPageIndex() + 1)
		end
	end
end

function meta:Refresh(index)
	self.left_arrow_icon:setVisible(true)
	self.right_arrow_icon:setVisible(true)

	ui_helper:SetText(self.title, text_loader:GetText("adv_skilled_exam", index))

	if self.page_count <= 1 then
		self.left_arrow_icon:setVisible(false)
		self.right_arrow_icon:setVisible(false)
		return
	end

	if index <= 1 then
		self.left_arrow_icon:setVisible(false)
	elseif index >= #self.page_list_up then
		self.right_arrow_icon:setVisible(false)
	end
end

--进入战斗  --index第几页
function meta:PageBattleClick(page_list, index)
	ui_helper:AddClick(page_list, function ()
		local adv_level = 0
		for k,v in pairs(self.has_adv_config) do
			if k == index then
				for m,n in pairs(data_template.adventure_config) do
					if v.ID == n["level"] then
						adv_level = n["level"]
						break
					end
				end
				break
			end
		end

		if user_logic.level <= adv_level then
			-- TODO: 怎么这里面还是写死的中文呢。。
			self:DispatchGraphicEvent("show_message", "熟练度等级不足")
			return
		elseif index == self.page_max_index and page_list then
			local tag_id = page_list:getTag()
			for m,n in pairs(self.has_adv_config) do
				if m == index then
					local unlock_value = self.has_adv_config[index]["UnlockValue"] --表里面的id(最后一页所有id)
					local config_Id = pve_logic:StrSplit(unlock_value, '|')
					local count = #config_Id

					if tostring(tag_id) == config_Id[1] then
						pve_logic:StartExam(page_list:getTag())
					else
						local before_pass = false
						for k,v in pairs(config_Id) do
							if tostring(tag_id) == v then
								for a,b in pairs(pve_logic.adv_passid) do
									if config_Id[k-1] == tostring(b) then
										before_pass = true
										pve_logic:StartExam(page_list:getTag())
										break
									end
								end
								break
							end
						end
						if not before_pass then
							-- TODO: 怎么还有固定中文呢
							self:DispatchGraphicEvent("show_message", "请先打完上一个等级")
						end
					end
				end
			end
		else
			if page_list then
				pve_logic:StartExam(page_list:getTag())
			end
		end
	end)
end

--守则
function meta:PageGuideClick(page_, index)
	ui_helper:AddClick(page_, function ()
		self:DispatchGraphicEvent("push_world_panel", "pve", "pve_exam_unlock_panel", index - 1)
	end)
end

function meta:RegisterEvent()
	self:RegisterGraphic("pve_exam_update", function (_, _)
		self.page_max_index = pve_logic:GetCurExamLevel(pve_logic.adv_passid)
		self.page_cur_index = self.page_max_index

		--上面刷新
		for k,v in pairs(self.page_list_up) do
			self:ShowUpPageInfo(v, k)
		end

		--下面刷新
		for k,v in pairs(self.page_list_down) do
			self:ShowDownPageInfo(v, k)
		end
	end)
end

function meta:RegisterWidgetEvent()
	ui_helper:AddClick(self.left_arrow_btn, function ()
		local nexts = self.page_viewup:getCurrentPageIndex()
		self.page_viewup:scrollToPage(nexts - 1)
		self.page_viewdown:scrollToPage(nexts - 1)
	end)

	ui_helper:AddClick(self.right_arrow_btn, function ()
		local nexts = self.page_viewup:getCurrentPageIndex()
		self.page_viewup:scrollToPage(nexts + 1)
		self.page_viewdown:scrollToPage(nexts + 1)
	end)

	ui_helper:AddClick(self.back_btn, function ()
		self:Hide()
        self:DispatchGraphicEvent("enabled_pve_touch",true)
	end)
end

return meta
