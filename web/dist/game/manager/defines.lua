-- 客户端定义文件，区别的服务端的constants
local meta = {}

-- 卡组显示类型
meta.DECK_TAB_TYPE = {
    monster = "monster",
    item = "item",
}

-- 单位
meta.UNIT = {
    ["K"] = 1000,
    ["M"] = 1000000,
    ["B"] = 1000000000,
}

--自适应字体 偏移
meta.FONT_OFFSET = {
    ["en-US"] = 1.2,
    ["zh-CN"] = 1,
}

-- 卡牌的颜色
meta["CARD_KIND_COLOR"] = {
    ["war"] = 0xf15536,                       -- 战斗
    ["fortune"] = 0xffb629,                   -- 命运
    ["balance"] = 0x33a1ff,                   -- 平衡
    ["nature"] = 0xc0ff00,                    -- 自然
    ["chaos"] = 0xA665FF,                     -- 混沌
    ["all"] = 0xFFFFFF,                       -- 普通
}
-- 结算界面动画延迟时间
meta["RESULT_DAILY"] = {
    ["exp"] = 0.4,
    ["mvp"] = 0.4,
    ["reward"] = 0.4,
    ["elo"] = 0,
}

meta.NET_WORK_DAILY_TIME = 1.0  --网络延迟时，触发UI提示时间 （单位:秒）
return meta
