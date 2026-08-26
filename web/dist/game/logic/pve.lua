local network = require "manager.network"
local graphic = require "manager.graphic"
local global = require "manager.global"

local user_logic = require "logic.user"
local timer = require "manager.time"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local deck_logic = require "logic.deck"
local defines = require "manager.defines"
local TAB_TYPE = defines.DECK_TAB_TYPE

local meta = {}
function meta:Init()
    self.pve_id = 0
    self.attack_type = 2
    self.image = {}
    self.difficulty = 0
    self.cur_difficulty = 0
    self.play_id = 0
    self.system_card_list = {}
    self.system_card_list.item_list = {}
    self.system_card_list.monster_list = {}
    self.pve_count = 2
    self:RegisterMsgHandler()
    self.req_refresh = false
    self.next_refresh_time = 0
    self.cur_min = 0

    self.login_pve_data = {}
    self.adv_progress = 1
    self.adv_passid = {}
end
function meta:CheckUserRankInfo()

end

function meta:StartFight(palyid,difficultys,aatcktype)

    network:Send("req_pve_battle_start",{play_id = palyid, difficulty=difficultys,attack_type = aatcktype },function(result,recv_msg)
        if result == "success" then
            print("entering battle")
        end

    end)
end

function meta:StartExam(idex)
    network:Send("req_adventure_battle_start", {id = idex}, function (result, recv_msg)
        if result == "success" then
            
        else
            
        end
    end)
end

function meta:ShowPve()
    graphic:DispatchEvent("switch_system_module", "pve")
end

function meta:Update(elapsed_time)
    if self.req_refresh then
        return
    end
    self.cur_min = self.cur_min + elapsed_time
    local diff_time = self.next_refresh_time - timer:Now()
    if self.cur_min >= 1 and diff_time <= 0 then
        self.cur_min = 0
        self.req_refresh = true
        self:RefreshCount(
        function ()
            graphic:DispatchEvent("refresh_pve_time")
            self.req_refresh = false
        end,
        function ()
            self.req_refresh = false
        end
        )
    end
end

function meta:RefreshCount(compleate_func, error_func)
    local req_data = {}
    req_data["refresh_time"] = timer:Now()
    network:Send("req_refresh_pve", req_data, function (result, recv_msg)
        if result == "success" then
            recv_msg = recv_msg or {}
            self.next_refresh_time = recv_msg.next_refresh_time
            self.pve_count = constants["PVE_INFO"].limit_count-recv_msg.pve_count
           if compleate_func then compleate_func() end
        else
            if error_func then error_func(result) end
        end
    end)
end

-- Gerbip Tide is archived: modules/pve/pve_gerbil_tide_panel.lua no longer
-- ships, so this must not dispatch "show_gerbil_tide_panel" (nothing listens,
-- and the panel it used to require is gone).  The entry point that called it
-- is gone too; this stays as a safe no-op so a stale caller cannot crash the
-- world scene.  See archive/gerbip_tide/README.md.
function meta:Query(play_ids)
    print("[PVE] Gerbip Tide is archived; ignoring play_id " .. tostring(play_ids))
end

function meta:QueryExam()
    graphic:DispatchEvent("show_exam_panel")
    graphic:DispatchEvent("switch_world_status", false)
end

function meta:InitSystemCard(difficulty)
	self.system_card_list.monster_list = {}
	self.system_card_list.item_list = {}
    for k,v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == tonumber(self.play_id) and tonumber(v.difficulty) == tonumber(difficulty) then
            for w in string.gmatch(v.employee_monster_list, "%d+") do
                table.insert(self.system_card_list.monster_list, w)
            end
        end
    end

    for k,v in pairs(data_template.pve_play_config) do
        if tonumber(v.play_id) == tonumber(self.play_id) and tonumber(v.difficulty) == tonumber(difficulty) then
            for w in string.gmatch(v.employee_item_list, "%d+") do
                table.insert(self.system_card_list.item_list, w)
            end
        end
    end

end

function meta:StrSplit(str, reps)
    local resultStrList = {}
    string.gsub(str,'[^'..reps..']+',function ( w )
        table.insert(resultStrList,w)
    end)
    return resultStrList
end

function meta:GetCurExamLevel(pass_ids)
    local pro_config = data_template.proficiency_config

    if pass_ids == nil then
        return 1
    end
    -- pass_ids = {1}

    local adv_config = data_template.adventure_config

    local cur_level = 1
    local hasLevel = false

    local all_count = 0
    for k,v in pairs(pro_config) do
        all_count = all_count + 1
        if v.UnlockRequest == 1 then
            local unlock_value = v.UnlockValue
            local un_v = self:StrSplit(unlock_value, '|')
            
            for a,b in pairs(adv_config) do
                for _,d in pairs(un_v) do
                    if tonumber(a) == tonumber(d) then
                        local hasLevel1 = false
                        for _,n in pairs(pass_ids) do
                            if tonumber(n) == tonumber(a) then
                                cur_level = b.exam_level
                                hasLevel1 = true
                                break
                            end
                        end
                        if hasLevel1 then
                            break
                        end
                    end
                end
                -- if hasLevel then
                --     hasLevel = false
                --     break
                -- end
            end
        end
    end

    if cur_level == all_count then
        return cur_level
    else
        local focus_level = 0
        local pass_all = false
        for k,v in pairs(pro_config) do
            if v.UnlockRequest == 1 then
                focus_level = focus_level + 1
                if focus_level == cur_level then
                    local un_v = self:StrSplit(v.UnlockValue, '|')
                    local pass_cnt = 0
                    
                    for a,b in pairs(un_v) do
                        for m,n in pairs(pass_ids) do
                             if tonumber(b) == tonumber(n) then
                                pass_cnt = pass_cnt + 1
                                break
                             end
                        end
                    end
                    if pass_cnt == #un_v then
                        pass_all = true
                    end

                    break
                end
            end
        end
        if pass_all then
            return (cur_level + 1)
        else
            return cur_level
        end
    end
    
    return cur_level
end

function meta:RegisterMsgHandler()
    network:RegisterCommand("update_pve_info", function (recv_msg)
	    if recv_msg.pve_count then
	    	self.pve_count = constants["PVE_INFO"].limit_count - recv_msg.pve_count
	    	graphic:DispatchEvent("refresh_pve_time")
	    end
    end)
end

function meta:ReqPveInfoOnLogin(compleate_func, error_func)
    network:Send("req_pve_play_info", function (result, recv_msg)
        if result == "success" then
            self.login_pve_data = recv_msg
            if compleate_func then compleate_func() end
        else
            if error_func then error_func(result) end
        end
    end)

    network:Send("req_adventure_info", function (result, recv_msg)
        if result == "success" then
            if recv_msg then 
                self.adv_progress = recv_msg.progress
                self.adv_passid = recv_msg.pass_ids or {}

                self:GetCurExamLevel(recv_msg.pass_ids)
            end

            if compleate_func then compleate_func() end
        else
            if error_func then error_func(result) end
        end
    end)
end

return meta
