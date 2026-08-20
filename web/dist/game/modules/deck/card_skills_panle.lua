local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local graphic = require "manager.graphic"
local text_loader = require "manager.text_loader"
local resource_logic = require "logic.resource"
local data_template = require "manager.data_template"
local ComposePanel = require "modules.deck.card_create_panel"

local deck_logic = require "logic.deck"


local CARD_CONFIG = data_template.card_config
local POWER_CONFIG_MAP = data_template.power_config


local ACARD_LEVEL = 8
local SKILL_NODE = 3
local meta = class("card_skills_panle",function ()
    return ui_helper:LoadCocosUI("interface/deck/levellist_panel.csb")
end)

function meta:ctor()

	local root = self:getChildByName("bg")
    self.root = root
    --头顶上的图标
    self.head = root:getChildByName("head")
    --费用
    self.cost = self.head:getChildByName("cost")
    --血量
    self.hp = self.head:getChildByName("hp_armor")
    self.hp_icon = self.hp:getChildByName("hp_armor_icon")
    self.hp_desc = self.hp:getChildByName("hp_armor_desc")
    --技能一
    self.skill_node = {}
    for i = 1, SKILL_NODE do

    	local skill = self.head:getChildByName("skill"..i)
    	local skill_icon = skill:getChildByName("skill_icon")
    	local skill_desc = skill:getChildByName("skill_desc")
    	self.skill_node[i] = {
    		skill = skill,
    		skill_icon = skill_icon,
    		skill_desc = skill_desc
    	}
    	self.skill_node[i].skill:setVisible(false)

    end
    self.template_list = {}
    for i = 1, ACARD_LEVEL do

    	local template = root:getChildByName("template"..i)
		--底栏 单数是可见 双数不可见

	    local shadow = template:getChildByName("shadow")

	    local level = template:getChildByName("level")

	    local cost = template:getChildByName("cost")

	    local hp = template:getChildByName("hp_armor")

	    local skill1 = template:getChildByName("skill1")

	    local skill2 = template:getChildByName("skill2")

	    local skill3 = template:getChildByName("skill3")
	    self.template_list[i] = {
	    	template = template,
	    	shadow = shadow,
	    	level = level,
	    	cost = cost,
	    	hp = hp,
	    	skill_list = { skill1, skill2, skill3 }
	    	-- skill1 = skill1,
	    	-- skill2 = skill2,
	    	-- skill3 = skill3
		}
		self.template_list[i].template:setVisible(false)
    end
end

--初始化内容
function meta:ShowInit( )

	for k, v in pairs(self.template_list) do
		self.template_list[k].template:setVisible(false)
		for kk, vv in pairs(self.template_list[k].skill_list) do
			vv:setVisible(false)
		end
	end

	for i,j in pairs(self.skill_node) do
		self.skill_node[i].skill:setVisible(false)
		self.skill_node[i].skill_icon:setVisible(false)
		self.skill_node[i].skill_desc:setVisible(false)
	end
end

function meta:UpdateSkills(card_id)
	local group_id = deck_logic:GetGroupIdByUid(card_id)
    local config_list  = deck_logic:GetAllCardGroupList(group_id)
    self:ShowInit()
	self:ShowSkill(config_list)
end

-- 显示技能信息
function meta:ShowSkill(config_list)

	local num = 0
	local card_type
	local skill_level_list = {}
	for k,v in pairs(config_list) do
		num = num + 1
		card_type = v.type
		table.insert(skill_level_list, v.power_list)
	end

	--设置hp 活着护甲防护
	if card_type == "monster" then
		self.hp_icon:loadTexture("ui/pic_card/hp_bg.png")
		ui_helper:SetTextByKey(self.hp_desc, "the_hp_desc")
	else
		--这个是护甲
		self.hp_icon:loadTexture("ui/pic_card/armor_bg.png")
		ui_helper:SetTextByKey(self.hp_desc, "the_armor_desc")
	end

	-- 最高多少级
	local length = #skill_level_list
	-- 最高级有多少个技能
	local max_length = #skill_level_list[length]

	--技能图标
	for k,v in pairs(skill_level_list) do
		local the_config = v
		for i,j in pairs(the_config) do
			self.skill_node[i].skill:setVisible(true)
			local power_config = POWER_CONFIG_MAP[j.name]
			self.skill_node[i].skill_icon:setVisible(true)
			self.skill_node[i].skill_desc:setVisible(true)
			self.skill_node[i].skill_icon:loadTexture(resource:GetSkillIcon(j.name))
			ui_helper:SetText(self.skill_node[i].skill_desc, power_config.name_desc)
		end

		local skill_node_list = self.template_list[k].skill_list
		for i = 1, 3 do
			local skill_node = skill_node_list[i]
			local power_config = the_config[i]
			if i <= max_length then
				skill_node:setVisible(true)
			else
				skill_node:setVisible(false)
			end
			-- print("#the_config ", #the_config, k ,tostring(power_config))
			if i <= #the_config then
				if power_config.value == 0 then
					skill_node:setString("O")
				else
					skill_node:setString(power_config.value)
				end
			else
				skill_node:setString("X")
			end
		end
	end


	local height = 100 + num * 50
	local width = 450
	self.root:setContentSize({width = width,height = height})
	self.head:setPosition(cc.p(40,height - 50))
	local i = 1


	for k,v in pairs(config_list) do
		local list = v
		self.template_list[i].template:setVisible(true)
		self.template_list[i].template:setPosition(cc.p(14,height - 70 - i * 50))
		if i % 2 == 1 then
			self.template_list[i].shadow:setVisible(true)
		else
			self.template_list[i].shadow:setVisible(false)
		end
		self.template_list[i].level:setString("★"..i)
		self.template_list[i].cost:setString(v.cost)
		self.template_list[i].hp:setString(v.hp)
		i = i + 1
	end
end

return meta
