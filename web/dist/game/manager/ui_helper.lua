local text_loader = require "manager.text_loader"
local audio_manager = require "manager.audio_manager"
local defines = require "manager.defines"

local bit = require "bit"
local bit_rshift = bit.rshift
local bit_band = bit.band

local meta = {}

function meta:NewPanel(class_name, class_path)
    -- return class(class_name, function ()
    --     if class_path == nil then
    --         return cc.Node:create()
    --     end
    --     return require("modules.common.base_panel").new(class_path)
    -- end)

    local origin = class(class_name, function ()
        if class_path == nil then
            return cc.Node:create()
        end
        return require("modules.common.base_panel").new(class_path)
    end)

    function origin:ctor(...)
        if self["OnInit"] then
            self:OnInit(...)
        end
        if self["RegisterEvent"] then
            self:RegisterEvent()
        end
    end

    return origin
end

--保留两位小数
function meta:KeepTwoDecimalPlace(unit, value)
    local temp = value / unit

    return math.floor(temp * 100) / 100
end

--单位换算
function meta:ConvertUnit(value, add_minus_sign)
    local unit = ""
    if value < defines["UNIT"]["K"] then

    elseif value < defines["UNIT"]["M"] then
        --千
        value = self:KeepTwoDecimalPlace(defines["UNIT"]["K"], value)
        unit = "K"

    elseif value < defines["UNIT"]["B"] then
        --百万
        value = self:KeepTwoDecimalPlace(defines["UNIT"]["M"], value)
        unit = "M"

    else
        --十亿
        value = self:KeepTwoDecimalPlace(defines["UNIT"]["B"], value)
        unit = "B"

    end

    if add_minus_sign then
        value = "-" .. value
    else
        value = tostring(value)
    end

    value = value .. unit

    return value
end

-- 设置资源
function meta:SetResource(widget, value)
    self:SetText(widget, self:ConvertUnit(value))
end

-- 16进制转颜色数量
function meta:GetColor4B(color, alpha_value)
    local color_4b = {a = 0, r = 0, g = 0, b = 0}
    color_4b.a = alpha_value or 255
    color_4b.r = bit_band(bit_rshift(color, 16), 0xff)
    color_4b.g = bit_band(bit_rshift(color, 8), 0xff)
    color_4b.b = bit_band(color, 0xff)
    return color_4b
end

-- 16进制颜色数量
function meta:GetColor3B(color)
    local color_3b = {r = 0, g = 0, b = 0}
    color_3b.r = bit_band(bit_rshift(color, 16), 0xff)
    color_3b.g = bit_band(bit_rshift(color, 8), 0xff)
    color_3b.b = bit_band(color, 0xff)
    return color_3b
end

-- 加载UI
function meta:LoadCocosUI(path)
    local ui_root = cc.CSLoader:createNode(path)
    self:SetCocosSetting(ui_root, path)
    self:BindTimeLine(ui_root, path)
    return ui_root
end

-- 设置UI配置
function meta:SetCocosSetting(ui_root, path)
    local setting = text_loader:GetEditerSetting(path)
    local pre_path = {}
    for _, item_config in pairs(setting) do
        local key = item_config.field
        local path_level = string.split(key, ".")

        local find_count = 0
        local oper_object = ui_root
        for level, name in pairs(path_level) do
            local pre_config = pre_path[level]
            -- 如果上一次配置层级关系和本次相同就设置否则的话就从上一级目录查找
            if pre_config and pre_config.name == name then
                oper_object = pre_config.object
            else
                if not oper_object then
                    oper_object = nil
                    break
                end
                oper_object = oper_object:getChildByName(name)
                -- 层级对象记录
                pre_path[level] = {}
                pre_path[level]["name"] = name
                pre_path[level]["object"] = oper_object
                for i = level + 1, #path_level do
                    if pre_path[i] ~= nil then
                        pre_path[i] = nil
                    end

                end

                find_count = find_count + 1
            end
        end
        if oper_object then
            if item_config.text then
                self:SetText(oper_object, item_config.text)
            end

            if item_config.pimage then
                self:SetImage(oper_object, item_config.pimage, ccui.TextureResType.plistType)
            end
            if item_config.image then
                self:SetImage(oper_object, item_config.pimage, ccui.TextureResType.localType)
            end
            local font = item_config.font
            local size = item_config.size
            if item_config.size then
                oper_object:setFontSize(item_config.size)
            end
            local node = item_config.node
            -- print("查找对象成功 "..key.."查找次数:"..find_count)
        end
    end
end

-- 拓展UI
function meta:ExpandUI(ui_root, node_name, lua_file, anim_file)
    local node = ui_root:getChildByName(node_name)
    if not node then
        print("node_name = "..node_name.." is null")
    end
    return require(lua_file).new(node, anim_file)
end

-- 绑定时间轴
function meta:BindTimeLine(target, path)
    local timeline = cc.CSLoader:createTimeline(path)
    target.timeline = timeline
    target:runAction(timeline)
    target.cur_animation = {}

    -- 播放动画
    function target:PlayAnimation(anim_name, is_loop, last_callback)

        if self.cur_animation.anim_name and not self.cur_animation.is_loop then
            if self.callback_id then
                target:stopAction(self.callback_id)
                self.callback_id = nil
            end
        end

        is_loop = is_loop or false
        local timeline = self.timeline
        timeline:play(anim_name, is_loop)
        local speed = timeline:getTimeSpeed()
        local start_frame = timeline:getStartFrame()
        local end_frame = timeline:getEndFrame()
        local frame_num = end_frame - start_frame
        local duration = 1.0 /(speed * 60.0) * frame_num
        if not is_loop then
            local block = cc.CallFunc:create(function()
                self.cur_animation.anim_name = nil

                if last_callback then
                    last_callback()
                end
            end)
            self.callback_id = target:runAction(cc.Sequence:create(cc.DelayTime:create(duration), block))
        end

        self.cur_animation.anim_name = anim_name
        self.cur_animation.is_loop = is_loop
        return duration
    end

    local stopAllActions = target["stopAllActions"]
    function target:stopAllActions()
        stopAllActions(self)
        local timeline = cc.CSLoader:createTimeline(path)
        self.timeline = timeline
        self:runAction(timeline)
    end

    local event_call_func
    function target:SetFrameEventCallFunc(callback)
        event_call_func = callback
    end


    timeline:setFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        local event_map = {}
        local list = string.split(event_name, "|")
        for i = 1, #list, 2 do
            event_map[list[i]] = list[i+1] or nil
        end

        local sound_value = event_map["sound"]
        local shake_value = event_map["shake"]

        if sound_value then
            audio_manager:PlayEffect(sound_value)
        elseif shake_value then
            local float_value = event_map["float"]
            local int_value = event_map["int"]
            if shake_value == "screen" then
                graphic:DispatchEvent("effect_screen_shake", float_value, int_value)
            end
        else
            if event_call_func then
                event_call_func(frame)
            end
        end
    end)

end

--添加点击事件
function meta:AddClick(widget, callback, ...)
    if not widget then
        print("meta:AddClick widget is null")
        return
    end
    widget:setTouchEnabled(true)
    local extension_data = widget:getComponent("ComExtensionData")
    local user_data = ""
    if extension_data then
        user_data = extension_data:getCustomProperty()
    end

    local event_map = {}
    local list = string.split(user_data, "|")
    for i = 1, #list, 2 do
        event_map[list[i]] = list[i+1] or nil
    end

    -- local src_scale = widget:getScaleX()

    local params = ...
    widget:addTouchEventListener(function(widget, event_type)
        -- 循环缩放
        -- local function scale(parent, init_scale)
        --     local childs = parent:getChildren()
        --     for i,v in ipairs(childs) do
        --         scale(v, v:getScale())
        --     end
        --     if parent["setScale"] then
        --         parent:setScale(init_scale)
        --     end
        -- end
        if event_type == ccui.TouchEventType.began then
            local sound_value = event_map["sound"]
            if sound_value then
                audio_manager:PlayEffect(sound_value)
            end

            -- if widget["getRendererNormal"] then
            --     scale(widget, widget:getRendererNormal():getScale() * src_scale)
            -- end
        end
        if event_type == ccui.TouchEventType.ended then
            callback(widget, params)
            -- widget:setScale(src_scale)
        end
        -- if event_type == ccui.TouchEventType.canceled then
        --     widget:setScale(src_scale)
        -- end



    end)
end

--获取子节点
--没有循环查找，可以优化
function meta:SeekChildByName(widget, name, isFind)
    if widget == nil then
        return nil
    end
    local node = widget:getChildByName(name)
    if node then
        return node
    end
    return nil
end

-- 设置文本内容根据key
function meta:SetTextByKey(widget, key, ...)
    if not key then
        return
    end
    local message = text_loader:GetText(key,...)
    self:SetText(widget, message)
end

--设置文本内容，兼容text,button
function meta:SetText(widget, text)
    text = text or ""
    if not widget then
        print("widget is null")
        return
    end
    if type(text) == "number" then
        text = tostring(text)
    end
    if type(widget["setString"]) == "function" then
        text = string.gsub(text, "\\n", "\n")
        widget:setString(tostring(text))


        local extension_data = widget:getComponent("ComExtensionData")
        local user_data = ""
        if extension_data then
            user_data = extension_data:getCustomProperty()
        end

        local event_map = {}
        local list = string.split(user_data, "|")
        for i = 1, #list, 2 do
            event_map[list[i]] = list[i+1] or nil
        end

        local over_flow = event_map["overflow"]
        if over_flow then
            local label = widget:getVirtualRenderer()
            label:setOverflow(cc.LabelOverflow[over_flow])
        end

    elseif type(widget["setTitleText"]) == "function" then
        widget:setTitleText(text)
    elseif type(widget["setText"]) == "function" then
        widget:setText(text)
    end
end

-- 替换EditBox
function meta:ReplaceEditBox(textfield)
    local size = textfield:getContentSize()
    local pos_x, pos_y = textfield:getPosition()
    local anchor = textfield:getAnchorPoint()
    local place_holder = textfield:getPlaceHolder()
    local txt_color = textfield:getTextColor()
    local font_size = textfield:getFontSize()
    local font_name = textfield:getFontName()
    local max_length = textfield:getMaxLength()
    local is_password = textfield:isPasswordEnabled()

    local edit_box = ccui.EditBox:create(size, ccui.Scale9Sprite:create("atlas/transparent.png"))
    edit_box:setPosition(pos_x, pos_y)
    edit_box:setAnchorPoint(anchor)
    -- edit_box:setPlaceHolder(place_holder)
    edit_box:setPlaceholderFont(font_name, font_size)

    edit_box:setPlaceholderFontColor(self:GetColor3B(0x624F2B))
    edit_box:setFont(font_name, font_size)
    edit_box:setFontColor(txt_color)
    edit_box:setMaxLength(max_length)
    if is_password then
        edit_box:setInputFlag(cc.EDITBOX_INPUT_FLAG_PASSWORD)
    end


    local parent = textfield:getParent()
    parent:addChild(edit_box)
    textfield:removeFromParent()

    function edit_box:didNotSelectSelf()
    end

    function edit_box:setString(str)
        self:setText(str)
    end

    function edit_box:getString()
        return self:getText()
    end

    return edit_box
end

-- 设置图片
function meta:SetImage(widget, path, ptype)
    if widget == nil then
        return
    end
    if type(widget["setTexture"]) == "function" then
        local texture2d = nil
        if ptype == ccui.TextureResType.plistType then
            local spriteframe_cache = cc.SpriteFrameCache:getInstance()
            local sprite_frame = spriteframe_cache:getSpriteFrame(path)
            widget:setSpriteFrame(sprite_frame)
        else
            local texture_cache = cc.Director:getInstance():getTextureCache()
            texture2d = texture_cache:addImage(path)
            widget:setTexture(texture2d)

        end
    elseif type(widget["loadTexture"]) == "function" then
        if ptype == nil then
            widget:loadTexture(path, ccui.TextureResType.localType)
        else
            widget:loadTexture(path, ptype)
        end
    end
end

-- 向左移动消失
function meta:RunLeftAnimationToHide(panel)
    local old_x, old_y = panel:getPosition()
    panel:setPosition({x = 0, y = 0})

    local act_move = cc.MoveBy:create(0.2, cc.p(-display.width, 0))
    local act_func = cc.CallFunc:create(function ()
        --panel:setVisible(false)
        panel:Hide()
    end)
    panel:runAction(cc.Sequence:create(act_move, act_func))
end

-- 向左移动出现
function meta:RunLeftAnimationToShow(panel)
    local old_x, old_y = panel:getPosition()
    panel:setPosition({x = display.width, y = 0})
    --panel:setVisible(true)
    panel:Show()

    local act_move = cc.MoveBy:create(0.2, cc.p(-display.width, 0))
    panel:runAction(act_move)
end

-- 向右移动消失
function meta:RunRightAnimationToHide(panel)
    local old_x, old_y = panel:getPosition()
    panel:setPosition({x = 0, y = 0})

    local act_move = cc.MoveBy:create(0.2, cc.p(display.width, 0))
    local act_func = cc.CallFunc:create(function ()
        --panel:setVisible(false)
        panel:Hide()
    end)
    panel:runAction(cc.Sequence:create(act_move, act_func))
end

-- 向右移动出现
function meta:RunRightAnimationToShow(panel)
    local old_x, old_y = panel:getPosition()
    panel:setPosition({x = -display.width, y = 0})
    --panel:setVisible(true)
    panel:Show()

    local act_move = cc.MoveBy:create(0.2, cc.p(display.width, 0))
    panel:runAction(act_move)
end

-- demo的手牌常驻内存不要清空掉
local demo_hand_card = nil
function meta:GetDemoHandCard(uid)
    if not demo_hand_card then
        demo_hand_card = require("modules.common.card_hand_item").new()
        demo_hand_card:retain()
    end
    demo_hand_card.SetScale = function (scale)
        local tt = demo_hand_card:getScale()
        if tt ~= scale then
            demo_hand_card:setPosition(0, 0)
            local rect = meta:GetNodeRect(demo_hand_card)

        end
    end
    if uid then
        demo_hand_card:SetCardId(uid)
    end
    return demo_hand_card
end

function meta:GetNodeRect(src_node)
    local scale = src_node:getScale()
    scale = 0.43
    -- print("scale = "..scale)
    -- 检查node边界
    local function clacRect(node)
        local children = node:getChildren()
        local min_x = 0
        local min_y = 0
        local max_x = 0
        local max_y = 0
        for k,v in pairs(children) do
            local rect = v:getBoundingBox()
            rect.width = rect.width * scale
            rect.height = rect.height * scale
            local p = node:convertToWorldSpace({x = rect.x, y = rect.y})
            p.x = p.x
            p.y = p.y
            if p.x < min_x then
                min_x = p.x
            end
            if p.y < min_y then
                min_y = p.y
            end
            if max_x < (p.x + rect.width) then
                max_x = p.x + rect.width
            end

            if max_y < (p.y + rect.height) then
                max_y = p.y + rect.height
            end
            local n_min_x, n_min_y, n_max_x, n_max_y = clacRect(v)
            if n_min_x < min_x then
                min_x = n_min_x
            end
            if n_min_y < min_y then
                min_y = n_min_y
            end
            if max_x < n_max_x then
                max_x = n_max_x
            end

            if max_y < n_max_y then
                max_y = n_max_y
            end

        end
        return min_x, min_y, max_x, max_y
    end
    local min_x, min_y, max_x, max_y = clacRect(src_node)

    local rect = {}
    rect.x = min_x
    rect.y = min_y
    rect.width = (max_x - min_x)
    rect.height = (max_y - min_y)
    return rect
end

-- src_node 缓冲到texture——chace的方案
function meta:NodeToTextureCache(src_node, renderTexture)
    if not renderTexture then
        local rect = meta:GetNodeRect(src_node)
        renderTexture = cc.RenderTexture:create(rect.width, rect.height)
    end
    renderTexture:beginWithClear(0.0, 0.0, 0.0, 0.0);
    src_node:visit()
    renderTexture:endToLua()
    return renderTexture
end

return meta
