local time = {}

local SECONDS_PER_DAY = 24 * 3600

local SECONDS_PER_HOUR = 60 * 60
local SECONDS_PER_MIN = 60

--东八区
local TIME_ZONE_OFFSET = 3600 * 8

function time:Init()
    self.time_zone_offset = TIME_ZONE_OFFSET
    self.diff_server_time = 0
end

--返回服务器上的utc时间
function time:Now()
    return os.time() + self.diff_server_time
end

function time:SyncServerTiem(server_time)
    self.diff_server_time = server_time - os.time()
end

-- 同步时间
function time:SyncTime(server_time, time_zone)
    if server_time == nil then
        return
    end
    self.diff_server_time = server_time - os.time()

    if time_zone then
        self.time_zone_offset = time_zone * 3600
    else
        self.time_zone_offset = TIME_ZONE_OFFSET
    end

end

function time:GetDurationToNextDay()
    local current_time = self:Now()

    local utc_8 = os.date("!*t", current_time + self.time_zone_offset)
    local start_time = utc_8.hour * 3600 + utc_8.min * 60 + utc_8.sec

    return SECONDS_PER_DAY - start_time
end

function time:GetDurationToFixedTime(fixed_time)
    local current_time = self:Now()
    return fixed_time - current_time
end

--[[
    获取差值时间为秒
]]
function time:GetDiffSecond(last_time)
    local diff_time = last_time - self:Now()
    if diff_time < 0 then
        diff_time = 0
    end
    return math.floor(diff_time)
end

--[[
    格式化时间
]]
function time:FormatTime(diff_time)
    local hour = math.floor(diff_time / SECONDS_PER_HOUR)
    local min = math.floor((diff_time - SECONDS_PER_HOUR * hour) / SECONDS_PER_MIN)
    local seconds = diff_time - SECONDS_PER_HOUR * hour - SECONDS_PER_MIN * min
    if hour ~= 0 then
        return string.format("%d:%02d:%02d", hour, min, seconds)
    else
        if min~= 0 then
            return string.format("%d:%02d", min, seconds)
        else
            return string.format("%d", seconds)
        end
    end
end

-- 获取最后的时间描述
function time:GetLastTimeStr(diff_time)
    local hour = math.floor(diff_time / SECONDS_PER_HOUR)
    local min = math.floor((diff_time - SECONDS_PER_HOUR * hour) / SECONDS_PER_MIN)
    local seconds = diff_time - SECONDS_PER_HOUR * hour - SECONDS_PER_MIN * min
    if hour ~= 0 then
        return hour.."h"
    else
        if min ~= 0 then
            return min.."m"
        else
            return seconds.."s"
        end
    end
end

--[[
    把天数转化成秒
]]
function time:GetSecondsFromDays(days)
    return days * SECONDS_PER_DAY
end

--[[
    把描述转化成小时
]]
function time:GetHoursFromSeconds(seconds)
    return seconds / SECONDS_PER_HOUR
end

function time:GetDateInfo(time)
    --先转成东八区
    time = time + self.time_zone_offset
    return os.date("!*t", time)
end

function time:GetDateFormat(time)
    local date = self:GetDateInfo(time)
    return string.format("%.4d/%.2d/%.2d %.2d:%.2d:%.2d", date.year, date.month, date.day, date.hour, date.min, date.sec)
end

function time:Update(elapsed_time)
    -- if not self.current_time then
    --     return
    -- end
    -- self.current_time = self.current_time + elapsed_time
end

return time
