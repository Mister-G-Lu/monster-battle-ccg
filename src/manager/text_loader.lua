local meta = {}

local locale_list = {
    [cc.LANGUAGE_ENGLISH] = "en-US",
    [cc.LANGUAGE_CHINESE] = "zh-CN",
}
-- 加载语言文件
function meta:Init(lang)
    -- This is the English offline edition.  Do not infer the device locale:
    -- doing so previously loaded Chinese UI text on Chinese-language emulators.
    local language = cc.LANGUAGE_ENGLISH
    lang = "en-US"

    if not locale_list[language] then
        locale_list[language] = locale_list[cc.LANGUAGE_ENGLISH]
    end

    -- 如果是中文区，要检查是否繁体。
    if language == cc.LANGUAGE_CHINESE and  self:IsTraditional() then
        lang = "zh-TW"
    end

    lang = lang or locale_list[language]

    -- 开发中，默认是英文字体
    local TARGET_PLATFORM = cc.Application:getInstance():getTargetPlatform()
    if TARGET_PLATFORM == cc.PLATFORM_OS_WINDOWS or TARGET_PLATFORM == cc.PLATFORM_OS_MAC or TARGET_PLATFORM == cc.PLATFORM_OS_LINUX then
        lang = locale_list[cc.LANGUAGE_ENGLISH] --英文版本
    end

    local temp = self:Load(lang)

    for k, v in pairs(temp) do
        self[k] = v
    end
    self.cur_lang = lang
end

-- 需要提前判定是否中文
function meta:IsTraditional()
    local cur_lang = cc.Application:getInstance():getCurrentLanguage()
    if cur_lang ~= cc.LANGUAGE_CHINESE then
        return false
    end

    local language = nil
    if ThirdHelper and ThirdHelper["getCurrentLanguage"] then
        language = ThirdHelper["getCurrentLanguage"]()
        -- IOS返回是zh-Hans-CN , zh-Hans
        -- Android返回的是zh-CN
        if language == "zh-CN" or language == "zh-Hans-CN" or language == "zh-Hans" then
            return false
        else
            return true
        end
    end

    return false
end

-- 加载文字资源
function meta:Load(lang)

    local function _read_csv_line(line)
        local list = {}
        while(line ~= "") do
            local nn = string.find(line, ",")
            if not nn then
                table.insert(list, line)
                break
            else
                if 1 == nn then
                    table.insert(list, "")
                else
                    table.insert(list, string.sub(line, 1, nn - 1))
                end
                line = string.sub(line,nn + 1)
            end
        end
        return list
    end

    local table_info = {}
    local str = aandm.loadConfig(string.format("res/data/client_lang_%s.csv", lang))
    local line_num = 0
    for line in string.gmatch(str, "[^\n]+") do
        if string.find(line, "\r", -1) then
            line = string.sub(line, 1, -2)
        end

        if line_num > 2 then
            local values = _read_csv_line(line)
            local tbl_type = values[1] or ""
            local key = values[2] or ""
            local object = values[3] or ""
            local value = values[4] or ""

            if tbl_type ~= "" then
                -- 获取该表格位子配置表
                local table = table_info[tbl_type] or {}
                -- print("object = "..object)
                if object == "" then
                    table[key] = value
                else
                    local info = {}
                    info["field"] = object
                    info["text"] = value or ""

                    local value_list = table[key] or {}
                    local index = #value_list + 1
                    value_list[index] = info
                    table[key] = value_list
                end
                table_info[tbl_type] = table
            end
        end
        line_num = line_num + 1
    end
    return table_info
end

-- 清除语言配置
function meta:Clean()
end

-- 读取编辑器设置
function meta:GetEditerSetting(path)
    local editer_setting = self.editer or {}
    return editer_setting[path] or {}
end

-- 获取文本文字
function meta:GetText(str, ...)
    local info = self.text[str] or str
    return string.format(info,...)
end

return meta
