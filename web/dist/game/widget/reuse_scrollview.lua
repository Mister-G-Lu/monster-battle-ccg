local reuse_scrollview = {}
reuse_scrollview.__index = reuse_scrollview

function reuse_scrollview.New(parent_panel, raw_widget, sub_panels, sub_panel_height)
    local new_scrollview = setmetatable({
        head_sub_panel_y = 0,
        head_sub_panel_index = 0,
        data_offset = 0,
        cur_pos_y = 0,
    }, reuse_scrollview)

    new_scrollview.parent_panel = parent_panel
    new_scrollview.raw_widget = raw_widget
    new_scrollview.sub_panels = sub_panels
    new_scrollview.sub_panel_height = sub_panel_height

    local size = raw_widget:getContentSize()
    new_scrollview.sview_height = size.height
    new_scrollview.sview_width = size.width

    new_scrollview:RegisterWidgetEvent()

    return new_scrollview
end

function reuse_scrollview:GetRawWidget()
    return self.raw_widget
end

function reuse_scrollview:Show(height, data_offset)
    self.sub_panel_num = #self.sub_panels

    self.data_offset = data_offset
    self:SetHeadSubPanel(1)

    self.is_resize = true

    self.container_height = height

    --setInnerContainerSize会触发scrolling事件
    self.raw_widget:setInnerContainerSize(cc.size(self.sview_width, height))

    self.raw_widget:getInnerContainer():setPositionY(self.sview_height - height + data_offset * self.sub_panel_height)

    self.is_resize = false
end

function reuse_scrollview:SetHeadSubPanel(index)
    if index > self.sub_panel_num then
        self.head_sub_panel_index = 1

    elseif index < 1 then
        self.head_sub_panel_index = self.sub_panel_num

    else
        self.head_sub_panel_index = index
    end

    if self.sub_panel_num == 0 then
        return
    end

    --[[
    head_sub_panel_index 是从上往下增加
    sub_panel_a 1
    sub_panel_b 2
    sub_panel_c 3
    ...
    --]]

    self.head_sub_panel_y = self.sview_height - self.sub_panels[self.head_sub_panel_index].root_node:getPositionY()
end


function reuse_scrollview:GetMaxDataOffset()

end

function reuse_scrollview:LoadSubPanel(sub_panel, is_)
    if is_ then
        sub_panel:Show(self.data_offset + self.sub_panel_num)
    else
        sub_panel:Show(self.data_offset + 1)
    end
end

function reuse_scrollview:OnScrolling(sview, event_type)
    if self.is_resize then
        return
    end

    local cur_y = sview:getInnerContainer():getPositionY()

    if cur_y >= self.head_sub_panel_y + self.sub_panel_height * 0.5 then
        if (self.data_offset + self.sub_panel_num) < self:GetMaxDataOffset() then

            local sub_panel = self.sub_panels[self.head_sub_panel_index]

            local last_sub_panel_index = self.sub_panel_num
            if self.head_sub_panel_index ~= 1 then
                last_sub_panel_index = self.head_sub_panel_index - 1
            end

            sub_panel.root_node:setPositionY(self.sub_panels[last_sub_panel_index].root_node:getPositionY() - self.sub_panel_height)
            self:SetHeadSubPanel(self.head_sub_panel_index + 1)

            self.data_offset = self.data_offset + 1

            self:LoadSubPanel(sub_panel, true)
        end

    elseif cur_y <= (self.head_sub_panel_y - self.sub_panel_height * 0.5) then

        if self.data_offset ~= 0 then
            local last_sub_panel_index = self.sub_panel_num
            if self.head_sub_panel_index ~= 1 then
                last_sub_panel_index = self.head_sub_panel_index - 1
            end

            local sub_panel = self.sub_panels[last_sub_panel_index]
            sub_panel.root_node:setPositionY(self.sub_panels[self.head_sub_panel_index].root_node:getPositionY() + self.sub_panel_height)
            self:SetHeadSubPanel(self.head_sub_panel_index - 1)

            self.data_offset = self.data_offset - 1
            self:LoadSubPanel(sub_panel, false)
        end
    end
end

function reuse_scrollview:RegisterMethod(get_max_data_method, load_method)
    self.GetMaxDataOffset = get_max_data_method
    self.LoadSubPanel = load_method
end

--从界面索引转换成数据层索引
function reuse_scrollview:GetDataIndex(i)
    local data_index
    if i < self.head_sub_panel_index then
        data_index = self.data_offset + (self.sub_panel_num - self.head_sub_panel_index) + i + 1
    else
        data_index = self.data_offset + i - self.head_sub_panel_index + 1
    end

    return data_index
end

function reuse_scrollview:RegisterWidgetEvent()
    self.raw_widget:addEventListener(function(widget, event_type)
        if event_type == ccui.ScrollViewEventType.containerMove then
            self:OnScrolling(widget, event_type)
        else

        end
    end)
end

return reuse_scrollview
