local meta = class("refine_table")

function meta:ctor()
    self.container_node = nil
end

-- 设置容器
function meta:SetContainer(node)
    self.container_node = node
end

-- 添加tab
function meta:AddTab(tab_node)

end

return meta
