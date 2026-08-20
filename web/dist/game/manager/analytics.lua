local meta = {}
-- 初始化统计组件
function meta:Init(app_key, channel)
    if TalkingDataGA then
        TalkingDataGA:setVerboseLogDisabled()
        TalkingDataGA:onStart(app_key, channel)
    end
end

-- 设置账户信息
function meta:SetUserId(user_id)
    if TalkingDataGA then
        TDGAAccount:setAccount(user_id)
    end
end

-- 设置账户信息
function meta:SetUserName(user_name)
    if TalkingDataGA then
        TDGAAccount:setAccountName(user_name)
    end
end

-- 设置竞技场段位
function meta:SetArenaLevel(arena_level)
    if TalkingDataGA then
        TDGAAccount:setLevel(arena_level)
    end
end

function meta:DoCasualMatchStart()
    if TalkingDataGA then
        TDGAMission:onBegin("casual")
    end
end

function meta:DoCasualMatchOver(is_match, reason)
    reason = reason or "fail"
    if TalkingDataGA then
        if is_match then
            TDGAMission:onCompleted("casual")
        else
            TDGAMission:onFailed("casual", reason)
        end
    end
end

-- 战斗开始
function meta:DoBattleStart(battle_type)
    if TalkingDataGA then
        TDGAMission:onBegin(battle_type)
    end
end

-- 战斗结束
function meta:DoBattleOver(battle_type, is_win, reason)
    reason = reason or "fail"
    if TalkingDataGA then
        if is_win then
            TDGAMission:onCompleted(battle_type)
        else
            TDGAMission:onFailed(battle_type, reason)
        end
    end
end

return meta
