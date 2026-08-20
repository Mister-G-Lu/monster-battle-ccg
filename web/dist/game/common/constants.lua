local constants = {}

-- 初始ELO
constants["INIT_ELO"] = 1000

constants["ADVENTURE_REQUEST"] = {
    adventure = 1,
    match_count = 2,
    match_win = 3,
}

-- 任务成就信息
constants["TASKACHI_STATUS"] = {
    begin = 0,
    can_award = 1,
    finish = 2,
}

constants["TASK_REFRESH_CLOCK"] = 2
constants["TASK_INTERVAL_TIME"] = 7200
constants["TASK_INIT_COUNT"] = 7
constants["TASK_LIMIT_COUNT"] = 4
constants["TASK_LIMIT_RESET_COUNT"] = 1

constants["TASK_TYPE"] = {
    friend_battle = 1,
    condition_win = 2,
    casual_win = 3,
    kill_monster = 4,
    use_item = 5,
    call_crystal = 6,
    call_skill = 7,
    pve_win = 8,
    call_card = 9,
}

constants["ACHI_STAT_TYPE"] = {
    friend_num = 1,
    casual_win = 2,
    obtain_money = 3,
    obtain_epic = 4,
    obtain_rarity = 5,
    login_day = 6,
    friend_battle = 7,
    challenge_count = 8,
    challenge_cup = 9,
    pve_count = 10,
    casual_win_three_count = 11,
    skill_count = 12,
    match_count = 13,
    consume_money = 14,
    consume_coin = 15,
    close_friend_num = 16,
    friend_win = 17,
    kill_monster_count = 18,
    die_monster_count = 19,
    kill_trigger_count = 20,
}

-- PVE信息
constants["PVE_INFO"] = {
    refresh_clock = 2,
    limit_count = 2,
}

-- 聊天状态
constants["CHAT_STATUS"] = {
    world_chat = "world_chat",
    private_chat = "private_chat",
    friend_private_chat = "friend_private_chat",
    online_chat = "online_chat"
}

-- 好友状态
constants["FRIEND_STATUS"] = {
    online = "online",
    offline = "offline",
    fighting = "fighting",
    matching = "matching",
    inviting = "inviting",

    friend_limit = 100,

    friend_chat_attachment = "friend_chat_attachment",
    add_friend_attachment = "add_friend_attachment"
}

-- 排行榜状态
constants["RANK_STATUS"] = {
    min_pos = 1,
    max_pos = 100,
    interval_time = 3600,

    global_elo = "global_elo",
    friend_elo = "friend_elo"
}

--约战状态
constants["CHALLENGE_STATUS"] = {
    wait = 1,
    fight = 2,
    die = 3
}

-- 素材种类
constants["MATERIAL_KIND"] = {
    item = "item",
    card = "card",
}

-- 每日重置
constants["DAILY_RESET"] = {
    login_reward = 1,          -- 登陆奖励
}

-- 竞技场奖励重置次数
constants["ARENA_REWARD_NUM"] = 3

-- 匹配状态
constants["MATCH_STAGE"] = {
    wait = 1,       -- 等待匹配
    match = 2,      -- 匹配中
}

-- 竞技场状态
constants["ARENA_STAGE"] = {
    casual = 1,                             -- 休闲赛
    periphery = 2,                          -- 外围赛
    ladder = 3,                             -- 排名赛
}

constants["ARENA_STAGE_ALIAS"] = {
    [1] = "casual",
    [2] = "periphery",
    [3] = "ladder",
}

constants["MAIL_TYPE"] = {
    notice = 1,
    item = 2,
}

constants["MAIL_STAGE"] = {
    unread = 1,
    read = 2,
}

constants["MAIL_MAX_NUM"] = 50

-- 附件类型
constants["ATTACHMENT_TYPE"] = {
    record = 1,                         -- 战斗录像
    resource = 2,                         -- 邮件奖励
    chest = 3,                          -- 宝箱

}

-- 宝箱品质
constants["CHEST_QUALITY"] = {
    normal = 1,                         -- 普通->1
    rare = 2,                           -- 罕见->2
    rarity = 3,                         -- 稀有->3
    epic = 4,                           -- 史诗->4
}

-- 宝箱状态
constants["CHEST_STAGE"] = {
    empty = "empty",                    -- 空的
    wait_open = "wait_open",            -- 等待开启
    opening = "opening",                -- 开启中
}

-- 奖励类型
--@不单单服务于奖励表，也是客户端通用奖励协议的显示。
constants["REWARD_TYPE"] = {
    resource = "resource",               -- 资源
    card = "card",                       -- 卡牌
    pool = "pool",                       -- 奖励组ID
    chest = "chest",                     -- 卡包类型
}

-- 资源类型
constants["RESOURCE_TYPE"] = {
    money = "money",                -- 金钱
    coin = "coin",                  -- 代币
}

-- 资源ID
constants["RESOURCE_ID"] = {
    money = 500001,                 -- 金钱
    coin = 500002,                  -- 代币
}

-- 卡牌类型
constants["CARD_TYPE"] = {
   ["monster"] = "monster",         -- 怪兽卡
   ["armor"] =  "armor",            -- 护具卡
   ["equip"] =  "equip",            -- 装备卡
   ["consume"] =  "consume",        -- 消耗卡
}

-- 卡牌品质
constants["CARD_QUALITY"] = {
    ["normal"] = 1,             -- 普通
    ["rare"] = 2,               -- 罕见
    ["rarity"] = 3,             -- 稀有
    ["epic"] = 4,               -- 史诗
}

-- 卡牌种类
constants["CARD_KIND"] = {
    ["war"] = 1,                      -- 战斗
    ["fortune"] = 2,                  -- 命运
    ["balance"] = 3,                  -- 平衡
    ["nature"] = 4,                   -- 自然
    ["chaos"] = 5,                    -- 混沌
    ["all"] = 6,                      -- 普通
}

-- 主要技能
constants["MAIN_POWER"] = {
    ["melee"] = 1,
    ["ranged"] = 1,
    ["magic"] = 1,
    ["chance"] = 1,
    ["heal"] = 1,
    ["heal_all"] = 1,
    ["damage"] = 1,
    ["damage_all"] = 1,
}

-- 技能类型
constants["POWER_TYPE"] = {
    active = "active",              -- 主动
    passive = "passive",            -- 被动
}

-- 技能是否针谁
constants["POWER_TARGET"] = {
    own = "own",
    enemy = "enemy",
}

-- 战斗攻击类型
constants["BATTLE_ATTACK_TYPE"] = {
    melee = 1,
    ranged = 2,
    magic = 3,
}

-- 战斗事件类型
constants["BATTLE_EVENT_TYPE"] = {
    anim = "anim",
    effect = "effect",
    damage = "damage",
    dead = "dead",
    armor_block = "armor_block",
    status = "status",
    heal = "heal",
    armor = "armor",
    swap = "swap",
    crystal = "crystal",
    destroy = "destroy",
    unsummon = "unsummon",
}

constants["BATTLE_OVER_CAUSE"] = {
    SURRENDER = 1,
    DRAW = 2,
    MONSTER_EMPTY = 3,

}

-- 伤害类型
constants["DAMAGE_TYPE"] = {
    melee = 0,
    ranged = 1,
    magic = 2,
    ignores_armor = 3,
    others = 4,
    breaker = 5,
}


-- BUFF效果
constants["STATUS_TYPE"] = {
    -- Debuff
    entangled = "entangled",        -- 混乱
    diseased = "diseased",          -- 疾病
    silenced = "silenced",          -- 沉默
    painted = "painted",            -- 标记
    demoralized = "demoralized",    -- 恫吓
    antimagicd = "antimagicd",       -- 法术抑制
    -- buff
    rallied = "rallied",            -- 鼓舞士气
    charged = "charged",            -- 冲锋
    cautious = "cautious",          -- 警觉
}

-- DEBUFF效果
constants["STATUS_KIND"] = {
        -- Debuff
    entangled = 1,                  -- 混乱
    diseased = 1,                   -- 疾病
    silenced = 1,                   -- 沉默
    painted = 1,                    -- 标记
    demoralized = 1,                -- 恫吓
    antimagicd = 1,                  -- 法术抑制
    -- buff
    rallied = 2,                    -- 鼓舞士气
    charged = 2,                    -- 冲锋
}

-- 战斗中某些技能仅仅只能用一次就消失
constants["POWER_ONLY_ONE"] = {
    silence = "silence",            -- 沉默释放一次后失效
    swap = "swap",                  -- 恐惧释放一次后失效
    charge = "charge",              -- 冲锋释放一次后失效
    draft = "draft",                -- 征募释放一次后失效
}


-- 卡牌献祭获得水晶
constants["CARD_IMMOLATION_CRYSTAL"] = {
    [constants.CARD_TYPE.monster] = 2,
    [constants.CARD_TYPE.armor] = 1,
    [constants.CARD_TYPE.equip] = 1,
    [constants.CARD_TYPE.consume] = 1,
    ["battle"] = 1,
}

-- 战斗位置
constants["BATTLE_POS"] = {
    center = 1,             -- 中间1号位
    left = 2,               -- 后排2号位
    right = 3,              -- 后排3号位
}


constants["BATTLE_STATUS"] = {
    wait = 1,       -- 等待
    standby = 2,    -- 战斗准备
    game = 3,       -- 等待指令
    fight = 4,      -- 战斗中
    over = 5,       -- 战斗结束
}

-- Power的类型
constants["POWER_NAME"] = {}
do
    local power_name_list = {
    "melee",            -- 近战
    "ranged",           -- 远程
    "magic",            -- 魔法
    "magic_aoe",        -- 魔法 全部
    "shield",           -- 护盾
    "mshield",          -- 魔法护盾
    "rally",            -- 鼓舞士气
    "demoralize",       -- 恫吓
    "antimagic",        -- 法术抑制
    "heal",             -- 治疗
    "heal_all",         -- 治疗全部
    "thrash",           -- 二段击
    "thorns",           -- 荆棘
    "resonate",
    "explode",          -- 爆炸
    "damage",           -- 侵袭
    "damage_all",       -- 侵袭-全部
    "chance",           -- 随机伤害
    "crystal",          -- 额外水晶
    "reach",            -- 长手
    "poison",
    "disease",          -- 疾病
    "disease_all",      -- 疾病全部
    "flying",           -- 飞翔
    "counter",          -- 反击
    "armor",
    "antidote",         -- 闪电
    "disarm",           -- 缴械
    "doom",
    "deathstrike",
    "stoneskin",
    "revive",
    "invincible",
    "breaker",          -- 破甲
    "entangle",         -- 混乱
    "regenerate",       -- 再生
    "reflect",
    "boost",            -- 护甲强化
    "swipe",
    "aggro",
    "stealth",
    "swap",             -- 恐惧
    "paint",
    "trample",
    "charge",           -- 冲锋
    "critical",         -- 暴击
    "berserk",
    "backstab",         -- 背刺
    "regenerate",
    "stun",
    "silence",
    "unsummon",         -- 反召唤
    "decoy",
    "antiair",
    "immunity",     -- 免疫
    "cleave",       --顺劈斩
    "draft",        -- 征募
    "destroy",      -- 毁灭
    "repair",       -- 修复
    "opportunity",  -- 机会
    "cautious",         -- 警觉
    "drain_crystal",   -- 水晶吸取
    }
    for _,v in ipairs(power_name_list) do
        constants["POWER_NAME"][v] = v
    end
end

-- 数值放大的倍数
constants.BATTLE_VALUE_SCALE = 1
-- 战场位置数量
constants.BATTLE_SLOT_MAX = 3

-- 战斗结果
constants.BATTLE_RESULT = {
    win = 1,        -- 1.胜利
    loss = 2,       -- 2.失败
    draw = 3,       -- 3.平局
}

-- 初始卡牌
constants["INIT_CARD_LIST"] = {
    {
        130031,130011,130011,120021,120021,150011,150021,120011,  -- 怪兽卡
        25001,22008,26016,35001,33003,23001,36003,32002,    -- 道具卡
    }, -- 初始卡组一
}

return constants
