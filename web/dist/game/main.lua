-- OFFLINE DEBUG LOGGING
local debug_log_path = nil
local function dbg(msg)
    print("[OFFLINE] " .. tostring(msg))
    if debug_log_path then
        local f = io.open(debug_log_path, "a")
        if f then
            f:write(os.date("%H:%M:%S") .. " " .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

require "config"
require "cocos.init"

-- Release APK: no FPS overlay / GL stats. Desktop/dev can set this true.
_G["DEV_MODE"] = false
local json = require "utils.json"

local error_tracer = require "manager.error_tracer"
error_tracer:Init()

function __G__TRACKBACK__(msg)
    dbg("CRASH: " .. tostring(msg))
    if debug.traceback then dbg(debug.traceback()) end
    print("----------------------------------------")
    print("LUA ERROR: " .. tostring(msg) .. "\n")
    print(debug.traceback())
    print("----------------------------------------")

    local str = "----------------------------------------\n"
    str = str .. "LUA ERROR: " .. tostring(msg) .. "\n"
    str = str .. debug.traceback()

    if error_tracer then
        error_tracer:PushErrorInfo(str)
        if error_tracer:GetUpdateDelay() == 0 then
            pcall(function() error_tracer:UploadCrash() end)
        end
    end

    return msg
end

function main()
    -- OFFLINE MODE: ensure flag is set before any decompression
    _G["OFFLINE_MODE"] = true
    dbg("=== main() START ===")
    local cc_app = cc.Application:getInstance()
    dbg("Platform: " .. tostring(cc_app and cc_app:getTargetPlatform() or "nil"))
    local file_util = cc.FileUtils:getInstance()
    dbg("Writable path: " .. tostring(file_util:getWritablePath()))

    -- Set up log file on device
    debug_log_path = file_util:getWritablePath() .. "offline_debug.log"
    dbg("Log file: " .. debug_log_path)

    local TARGET_PLATFORM = cc.Application:getInstance():getTargetPlatform()

    local function entry_scenes()
        dbg("entry_scenes() called, HAS_DOWNLOADED_PATCH=" .. tostring(_G["HAS_DOWNLOADED_PATCH"]))
        if _G["HAS_DOWNLOADED_PATCH"] then

            -- Try to update project.manifest (non-critical, wrapped in pcall)
            pcall(function()
                local writable_path = cc.FileUtils:getInstance():getWritablePath()
                local project_str = cc.FileUtils:getInstance():getStringFromFile(writable_path.."project.manifest")
                local version_str = cc.FileUtils:getInstance():getStringFromFile("version.manifest")

                local project_mamifest = json:decode(project_str)
                local version_mamifest = json:decode(version_str)
                if project_mamifest and version_mamifest then
                    project_mamifest["build"] = version_mamifest["build"]
                    local new_json = json:encode(project_mamifest)
                    local file = io.open(writable_path .. "project.manifest", "w+")
                    file:write(new_json)
                    file:close()
                end
            end)

            dbg("Loading global_manager and changing to login scene")
            local global_manager = require "manager.global"
            global_manager:Init()
            global_manager:ChangeScene("login")
        else
            dbg("HAS_DOWNLOADED_PATCH is false, showing download scene")
            local scene = require("scenes.download_scene").new()
            cc.Director:getInstance():replaceScene(scene)
        end
    end

    local configuration = require "manager.configuration"
    configuration:Init()

    if _G["NEED_RELOAD"] then
        entry_scenes()
    else
        collectgarbage("setpause", 100)
        collectgarbage("setstepmul", 5000)

        local scene = cc.Scene:create()

        local CheckDecompress = function()
            dbg("CheckDecompress() START")
            local file_util = cc.FileUtils:getInstance()
            if TARGET_PLATFORM == cc.PLATFORM_OS_WINDOWS or TARGET_PLATFORM == cc.PLATFORM_OS_MAC or TARGET_PLATFORM == cc.PLATFORM_OS_LINUX then
                file_util:setPopupNotify(false)
                file_util:addSearchPath("src/")
                file_util:addSearchPath("res/")
            end
            -- FPS / GL "time" overlay is a debug HUD. Never show it on a
            -- player APK; only when DEV_MODE is explicitly on.
            cc.Director:getInstance():setDisplayStats(_G["DEV_MODE"] == true)
                local writable_path = file_util:getWritablePath()

                local do_decompress = false
                pcall(function() do_decompress = aandm.needDecompress() end)
                -- OFFLINE MODE: always decompress to ensure CSVs are extracted from data.mu
                do_decompress = true
                dbg("needDecompress = " .. tostring(do_decompress))
                if do_decompress then
                    local file_list = {
                        "monster_balance.zip",
                        "monster_chaos.zip",
                        "monster_fortune.zip",
                        "monster_nature.zip",
                        "monster_war.zip",
                        "pic_card_item.zip",
                        "pic_bg_battlemap.zip",
                        "pic_bg_chest.zip",
                        "pic_bg_deck.zip",
                        "pic_bg_help.zip",
                        "pic_bg_login.zip",
                        "pic_bg_pve.zip",
                        "pic_bg_pvp.zip",
                        "pic_bg_world.zip",
                        "kind_bg.zip",
                        "ui_bg_pve.zip",
                        "ui_bg_challenge.zip",
                        "ui_button.zip",
                        "ui_icon_achievement.zip",
                        "ui_icon_guide.zip",
                        "ui_icon_item.zip",
                        "ui_icon_ladder_headicon.zip",
                        "ui_icon_ladder_reward.zip",
                        "ui_icon_pve.zip",
                        "sound.zip",
                        "particle.zip",
                        "interface.zip",
                        "fonts.zip",
                        "Default.zip",
                        "atlas_card.zip",
                        "atlas_login.zip",
                        "atlas_main.zip",
                        "atlas_ui.zip",
                        "animation.zip",
                        "common.mu",
                        "src.mu",
                        "data.mu",
                    }
                    for _, file_name in ipairs(file_list) do
                        if not aandm.decompress(file_name, writable_path) then
                            print("decompress err", file_name)
                            pcall(function() error_tracer:PushErrorInfo("decompress err :" .. file_name) end)
                        end
                    end

                    pcall(function() error_tracer:UploadCrash() end)

                    pcall(function()
                        local str = cc.FileUtils:getInstance():getStringFromFile("assets.manifest")
                        local file = io.open(writable_path .. "project.manifest", "w")
                        if file then
                            file:write(str)
                            file:close()
                        end
                    end)

                    pcall(function()
                        local str = cc.FileUtils:getInstance():getStringFromFile("version.manifest")
                        local file = io.open(writable_path .. "version.manifest", "w")
                        if file then
                            file:write(str)
                            file:close()
                        end
                    end)
                end

                file_util:addSearchPath(writable_path)
                file_util:addSearchPath(writable_path .. "res")
                file_util:addSearchPath(writable_path .. "src")
            end

            -- OFFLINE MODE: always mark patch as downloaded after decompression step
            dbg("Setting HAS_DOWNLOADED_PATCH=true")
            _G["HAS_DOWNLOADED_PATCH"] = true
        end

        scene:registerScriptHandler(function(event)
            if event == "enter" then
                if TARGET_PLATFORM     == cc.PLATFORM_OS_IPHONE or TARGET_PLATFORM == cc.PLATFORM_OS_IPAD then
                    CheckDecompress()
                elseif TARGET_PLATFORM == cc.PLATFORM_OS_WINDOWS or TARGET_PLATFORM == cc.PLATFORM_OS_MAC or TARGET_PLATFORM == cc.PLATFORM_OS_LINUX then
                    _G["HAS_DOWNLOADED_PATCH"] = true
                    CheckDecompress()
                elseif TARGET_PLATFORM == cc.PLATFORM_OS_ANDROID then
                    CheckDecompress()
                end

                entry_scenes()

            elseif event == "exit" then
                scene:removeAllChildren()
            end
        end)

        cc.Director:getInstance():replaceScene(scene)
    end
end

dbg("=== Lua runtime started ===")

-- SPLASH SCREEN: show immediately so user sees something while loading
pcall(function()
    local scene = cc.Scene:create()
    local layer = cc.LayerColor:create(cc.Color(20, 20, 30, 255))
    scene:addChild(layer)
    -- Try to add loading text (may fail if font system not ready)
    pcall(function()
        local size = cc.Director:getInstance():getWinSize()
        local label = cc.Label:createWithSystemFont("Loading...", "Helvetica", 24)
        if label then
            label:setPosition(cc.p(size.width / 2, size.height / 2))
            label:setColor(cc.Color(200, 200, 200, 255))
            scene:addChild(label)
        end
    end)
    cc.Director:getInstance():replaceScene(scene)
end)

local status, msg = xpcall(main, __G__TRACKBACK__)
if not status then
    print(msg)
end
