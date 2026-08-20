local ui_helper = require "manager.ui_helper"
local configuration = require "manager.configuration"
local text_loader = require "manager.text_loader"

local meta = class("download_scene",function ()
    return cc.Scene:create()
end)

-- 退出游戏
local function DoExit()
    cc.Director:getInstance():endToLua()
end

-- 删除文件
local function DeleteFile()
    local file_util = cc.FileUtils:getInstance()

    local writable_path = file_util:getWritablePath()
    file_util:removeFile(writable_path .. "project.manifest")
    file_util:removeFile(writable_path .. "project.manifest.temp")
end

function meta:ctor()

    local ui_root = ui_helper:LoadCocosUI("interface/download_panel.csb")
    ui_root:PlayAnimation("normal")
    self:addChild(ui_root)
    self.ui_root = ui_root

    self.msgbox = ui_helper:ExpandUI(ui_root, "msgbox_node", "modules.common.confirm_box")

    local loading_bg = ui_root:getChildByName("loading_bg")

    self.loading_bar = loading_bg:getChildByName("loadingbar")
    self.version_txt = loading_bg:getChildByName("ver")
    self.progress_txt = loading_bg:getChildByName("progress")

    self.tip_desc_txt = loading_bg:getChildByName("tip_desc")
    self.desc = loading_bg:getChildByName("desc")
    self.loading_bar:setPercent(0)
    ui_helper:SetText(self.progress_txt, "0%")

    self:registerScriptHandler(function(event)
        if event == "enter" then
            self:OnEnter()
        elseif event == "exit" then
            self:OnExit()
        end
    end)

end

function meta:OnEnter()
    text_loader:Init()
    self.has_decompress_err = false
    self:CreateAssetsManager()
    self.assets_manager:update()
end

function meta:OnExit()
    if self.assets_manager then
        self.assets_manager:release()
        self.assets_manager = nil
    end

    self:removeAllChildren()
end

function meta:Update(elapsed_time)
end


-- 开始下载
function meta:BeginDownload(version)
    ui_helper:SetText(self.version_txt, "Version:"..version)
    ui_helper:SetText(self.desc,text_loader:GetText("loading_desc"))
    self.ui_root:PlayAnimation("enter_download", false, function ()
        self.assets_manager:update()
    end)
end

-- 更新下载进程
function meta:UpdateDownloadProgress(percent)
    self.loading_bar:setPercent(percent)
    ui_helper:SetText(self.progress_txt, percent.."%")
end

--创建更新器
function meta:CreateAssetsManager()
    local writable_path = cc.FileUtils:getInstance():getWritablePath()
    local manifest_file_path = "assets.manifest"

    self.assets_manager = cc.AssetsManagerEx:create(manifest_file_path, writable_path)
    self.assets_manager:retain()

    local manifest = self.assets_manager:getLocalManifest()
    if manifest then
        configuration:SetVersion(manifest:getVersion())
    end

    local EVENT_CODE = cc.EventAssetsManagerEx.EventCode
    local OnUpdateEvent = function(event)
        local scene = cc.Director:getInstance():getRunningScene()

        if not self.assets_manager:getLocalManifest():isLoaded() then
            print("Fail to update assets, step skipped.")
        else
            local event_code = event:getEventCode()
            if event_code == EVENT_CODE.ERROR_NO_LOCAL_MANIFEST then
                print("No local manifest file found, skip assets update.")
            elseif event_code == EVENT_CODE.UPDATE_PROGRESSION then
                local assetId = event:getAssetId()
                local percent = event:getPercent()
                -- print("UPDATE_PROGRESSION  assetId = "..assetId..", percent = "..percent)
                if assetId == cc.AssetsManagerExStatic.VERSION_ID then
                elseif assetId == cc.AssetsManagerExStatic.MANIFEST_ID then
                else
                    self:UpdateDownloadProgress(math.floor(percent))
                end
            elseif event_code == EVENT_CODE.NEW_VERSION_FOUND then
                --发现新版本，检测是否需要更新二进制包
                local local_manifest = self.assets_manager:getLocalManifest()
                local remote_manifest = self.assets_manager:getRemoteManifest()

                if remote_manifest:getBuildId() > local_manifest:getBuildId() then
                    --退出游戏
                    local title = text_loader:GetText("package_version_too_low_title")
                    local desc = text_loader:GetText("package_version_too_low")
                    local confirm_txt = text_loader:GetText("common_confirm")
                    local cancel_txt = text_loader:GetText("common_close")
                    print("NEW_VERSION_FOUND， 二进制版本过低，退出游戏吧")

                    self.msgbox:ShowConfirm(title, desc, confirm_txt, cancel_txt, function()
                        --TODO 制定地址下载安装包
                        DeleteFile()
                        DoExit()
                    end,

                    function()
                       DoExit()
                    end)
                else
                    --继续更新
                    self.assets_manager:update()
                end

            elseif event_code == EVENT_CODE.NEW_PATCH_FOUND then
                local size = event:getCURLECode()

                local local_manifest = self.assets_manager:getLocalManifest()
                local remote_manifest = self.assets_manager:getRemoteManifest()

                if size == 0 then
                    --没有更新
                    self.assets_manager:update()
                elseif remote_manifest:getBuildId() > local_manifest:getBuildId() then
                    --退出游戏
                    local title = text_loader:GetText("package_version_too_low_title")
                    local desc = text_loader:GetText("package_version_too_low")
                    local confirm_txt = text_loader:GetText("common_confirm")
                    local cancel_txt = text_loader:GetText("common_close")
                    print("NEW_PATCH_FOUND， 二进制版本过低，退出游戏吧")

                    self.msgbox:ShowConfirm(title, desc, confirm_txt, cancel_txt, function()
                        --TODO 制定地址下载安装包
                        DeleteFile()
                        DoExit()
                    end,

                    function()
                       DoExit()
                    end)

                else
                    --提示更新包
                    print("提示更新包")
                    local title = text_loader:GetText("package_update_title")
                    local desc = text_loader:GetText("package_update",size / 1048576)
                    local confirm_txt = text_loader:GetText("common_confirm")
                    local cancel_txt = text_loader:GetText("common_close")

                    self.msgbox:ShowConfirm(title, desc, confirm_txt, cancel_txt, function()

                        self.msgbox:Hide(function ()
                            local manifest = self.assets_manager:getRemoteManifest()
                            self:BeginDownload(manifest:getVersion())
                        end)

                    end,

                    function()
                        DoExit()
                    end
                    )

                    _G["NEED_RELOAD"] = true
                end

            elseif event_code == EVENT_CODE.ERROR_DOWNLOAD_MANIFEST or event_code == EVENT_CODE.ERROR_PARSE_MANIFEST or
                event_code == EVENT_CODE.UPDATE_FAILED then
                --下载失败
                local title = text_loader:GetText("network_unable_connect_title")
                local desc = text_loader:GetText("network_unable_connect")
                local confirm_txt = text_loader:GetText("network_unable_connect_confirm")
                local cancel_text = text_loader:GetText("network_unable_connect_close")

                print("EVENT_CODE.", event_code, event:getMessage())

                self.msgbox:ShowConfirm(title, desc, confirm_txt, cancel_text, function()
                    if event_code == EVENT_CODE.ERROR_DOWNLOAD_MANIFEST then
                        --manifest文件下载失败，需要提示用户是否重新下载project.manifest
                        self.assets_manager:setState(4)
                        self.assets_manager:update()

                    elseif event_code == EVENT_CODE.UPDATE_FAILED then
                        --部分文件下载成功
                        self.assets_manager:downloadFailedAssets()
                    else
                        DoExit()
                    end
                end,

                function()
                   DoExit()
                end)

            elseif event_code == EVENT_CODE.ERROR_UPDATING then
                print("EVENT_CODE.ERROR_UPDATING", event:getAssetId())

            elseif event_code == EVENT_CODE.ASSET_UPDATED then
                print("EVENT_CODE.ASSET_UPDATED", event:getAssetId())

            elseif event_code == EVENT_CODE.ERROR_DECOMPRESS then
                --解压失败
                self.has_decompress_err = true

            elseif event_code == EVENT_CODE.ALREADY_UP_TO_DATE or event_code == EVENT_CODE.UPDATE_FINISHED then
                --完成更新
                local manifest = self.assets_manager:getLocalManifest()

                _G["HAS_DOWNLOADED_PATCH"] = true

                if _G["NEED_RELOAD"] then

                    --download_scene所依赖的脚本都必须重新加载
                    local module_name_list = {
                        "manager.ui_helper",
                        "manager.configuration",
                        "manager.text_loader",
                        "manager.global",
                        "modules.common.confirm_box",
                        "manager.audio_manager",
                        "manager.network",
                        "manager.defines",
                        "main",
                    }

                    text_loader:Clean()

                    for _, module_name in ipairs(module_name_list) do
                        package.loaded[module_name] = nil
                    end

                    local configuration = require "manager.configuration"
                    configuration:Init()

                    if manifest then
                        configuration:SetVersion(manifest:getVersion())
                    end

                    configuration:Save()


                    cc.SpriteFrameCache:getInstance():removeSpriteFrames()
                    cc.Director:getInstance():getTextureCache():reloadTexture("atlas/login.png")
                    cc.Director:getInstance():getTextureCache():reloadTexture("atlas/ui.png")

                    self.ui_root:PlayAnimation("exit_download", false, function ()
                        require "main"
                    end)
                else
                    if manifest then
                        configuration:SetVersion(manifest:getVersion())
                    end
                    configuration:Save()

                    local global_manager = require "manager.global"
                    global_manager:Init()
                    global_manager:ChangeScene("login")
                end
            end
        end
    end

    local listener = cc.EventListenerAssetsManagerEx:create(self.assets_manager, OnUpdateEvent)
    cc.Director:getInstance():getEventDispatcher():addEventListenerWithFixedPriority(listener, 1)
end



return meta
