#!/usr/bin/env python3
"""
Fix: Tutorial battle (Will vs Player) stuck forever on waiting screen.

Root causes:
1. cmd_battle_standby sets is_play_animation=true but NEVER calls CommandComplete().
   It relies on exit_battle -> gold_coin_ready -> spine anim -> anim_complete chain.
   If ANY link breaks, battle stuck forever.

2. match_panel timer clears is_play_animation but doesn't call CommandComplete(),
   so cmd_battle_standby re-processes in infinite loop.

3. last_oper_time=0 triggers immediate auto-attack before player sees UI.

4. Enemy name is just "Will" instead of "[AI] Will".
"""
import os

SRC = os.path.join(os.path.dirname(__file__), "decrypted", "src")
BATTLE_LUA = os.path.join(SRC, "logic", "battle.lua")
MATCH_LUA = os.path.join(SRC, "modules", "battle", "match_panel.lua")
OFFLINE_BATTLE = os.path.join(SRC, "manager", "offline_battle.lua")
OFFLINE_SERVER = os.path.join(SRC, "manager", "offline_server.lua")

def read(path):
    with open(path, "rb") as f:
        return f.read()

def write(path, content):
    with open(path, "wb") as f:
        f.write(content)

def patch(name, path, old, new):
    content = read(path)
    if old not in content:
        print(f"  WARNING: pattern not found in {name}")
        # Show context around first 80 chars
        snippet = old[:120].replace(b"\r\n", b"\\r\\n").replace(b"\n", b"\\n")
        print(f"    Looking for: {snippet}")
        return False
    content = content.replace(old, new, 1)
    write(path, content)
    print(f"  PATCHED {name}")
    return True

print("=== Patching guide battle stuck fix ===\n")
ok = True

# =====================================================================
# PATCH 1: battle.lua - Clean() - add standby timer init
# =====================================================================
ok &= patch("battle.lua - Clean init", BATTLE_LUA,
    b"    self.is_own = false\r\n    self.pve_win_cur_value = 0\r\nend",
    b"    self.is_own = false\r\n    self.pve_win_cur_value = 0\r\n    self._standby_block_time = 0\r\nend")

# =====================================================================
# PATCH 2: battle.lua - Update() - add standby safety timer
# =====================================================================
ok &= patch("battle.lua - Update standby timer", BATTLE_LUA,
    b'    if self.is_play_animation then\r\n        -- safety: if animation has been blocking for 5+ seconds, force-unblock\r\n        self._anim_block_time = (self._anim_block_time or 0) + elapsed_time\r\n        if self._anim_block_time > 5.0 then\r\n            print("[BATTLE] WARNING: is_play_animation stuck for " .. self._anim_block_time .. "s, force-clearing")\r\n            self.is_play_animation = false\r\n            self._anim_block_time = 0\r\n            self:CommandComplete()\r\n        end\r\n        -- \xe5\xa6\x82\xe6\x9e\x9c\xe6\xad\xa3\xe5\x9c\xa8\xe9\x83\xa8\xe7\xbd\xb2\xef\xbc\x8c\xe6\x9a\x82\xe5\x81\x9c\xe6\x89\x80\xe6\x9c\x89\xe7\x9a\x84\xe6\x88\x98\xe6\x96\x97\xe6\x8c\x87\xe4\xbb\xa4\xe7\x9a\x84\xe6\x89\xa7\xe8\xa1\x8c\r\n        return\r\n    else\r\n        self._anim_block_time = 0\r\n    end',
    b'    if self.is_play_animation then\r\n        -- safety: if animation has been blocking for 5+ seconds, force-unblock\r\n        self._anim_block_time = (self._anim_block_time or 0) + elapsed_time\r\n        if self._anim_block_time > 5.0 then\r\n            print("[BATTLE] WARNING: is_play_animation stuck for " .. self._anim_block_time .. "s, force-clearing")\r\n            self.is_play_animation = false\r\n            self._anim_block_time = 0\r\n            self._standby_block_time = 0\r\n            self:CommandComplete()\r\n        end\r\n        -- standby-specific: if cmd_battle_standby set is_play_animation\r\n        -- but the exit_battle/anim_complete chain broke, force after 4s\r\n        if self._standby_block_time and self._standby_block_time > 0 then\r\n            self._standby_block_time = self._standby_block_time + elapsed_time\r\n            if self._standby_block_time > 4.0 then\r\n                print("[BATTLE] WARNING: standby chain broken, force-advancing")\r\n                self.is_play_animation = false\r\n                self._anim_block_time = 0\r\n                self._standby_block_time = 0\r\n                self:CommandComplete()\r\n            end\r\n        end\r\n        return\r\n    else\r\n        self._anim_block_time = 0\r\n    end')

# =====================================================================
# PATCH 3: battle.lua - cmd_battle_standby handler - start standby timer
# =====================================================================
ok &= patch("battle.lua - cmd_battle_standby", BATTLE_LUA,
    b'    self:RegisterEvent("cmd_battle_standby", function (recv_msg)\r\n        self.is_play_animation = true\r\n        self:DispatchEvent("battle_panel_standby")\r\n    end)',
    b'    self:RegisterEvent("cmd_battle_standby", function (recv_msg)\r\n        self.is_play_animation = true\r\n        self:DispatchEvent("battle_panel_standby")\r\n        -- Start standby safety timer: if anim_complete never fires\r\n        -- within 4 seconds, the Update loop will force-complete\r\n        self._standby_block_time = 0.001\r\n    end)')

# =====================================================================
# PATCH 4: battle.lua - anim_complete clears standby timer
# =====================================================================
ok &= patch("battle.lua - anim_complete", BATTLE_LUA,
    b'    self:RegisterEvent("anim_complete",function (anim_name)\r\n        self.is_play_animation = false\r\n        self:CommandComplete()\r\n    end)',
    b'    self:RegisterEvent("anim_complete",function (anim_name)\r\n        self.is_play_animation = false\r\n        self._standby_block_time = 0\r\n        self:CommandComplete()\r\n    end)')

# =====================================================================
# PATCH 5: battle.lua - Don't auto-attack during sacrifice phase
# =====================================================================
ok &= patch("battle.lua - no auto during sacrifice", BATTLE_LUA,
    b'    if self.cur_stage == self.STAGE.own then\r\n        local last_oper_time = self.own_player.last_oper_time\r\n        if last_oper_time then\r\n            local last_time = timer:GetDiffSecond(last_oper_time)\r\n            if last_time <= 0 then\r\n                -- \xe8\x87\xaa\xe5\x8a\xa8\xe6\x88\x98\xe6\x96\x97\r\n                self:ReqBattleAttack("auto")\r\n            end\r\n        end\r\n    end',
    b'    if self.cur_stage == self.STAGE.own and not self.own_player.is_sacrifice then\r\n        local last_oper_time = self.own_player.last_oper_time\r\n        if last_oper_time then\r\n            local last_time = timer:GetDiffSecond(last_oper_time)\r\n            if last_time <= 0 then\r\n                -- \xe8\x87\xaa\xe5\x8a\xa8\xe6\x88\x98\xe6\x96\x97\r\n                self:ReqBattleAttack("auto")\r\n            end\r\n        end\r\n    end')

# =====================================================================
# PATCH 6: offline_battle.lua - Fix last_oper_time in BeginPrep
# =====================================================================
# BeginPrep is in offline_battle.lua, not offline_server.lua
ok &= patch("offline_battle.lua - BeginPrep", OFFLINE_BATTLE,
    b'function offline_battle:BeginPrep(user_id)\r\n    local actor = user_id == self.own.user_id and self.own or self.enemy\r\n    actor.is_sacrifice = true\r\n    self:PushCommand("cmd_battle_prepa", {\r\n        user_id = actor.user_id,\r\n        sync_crystal = actor.cur_crystal,\r\n        last_oper_time = 0,\r\n        is_sacrifice = true,\r\n    })\r\nend',
    b'function offline_battle:BeginPrep(user_id)\r\n    local actor = user_id == self.own.user_id and self.own or self.enemy\r\n    actor.is_sacrifice = true\r\n    -- Far-future timestamp: prevents auto-attack during sacrifice phase.\r\n    -- Player must manually sacrifice/deploy/end turn.\r\n    self:PushCommand("cmd_battle_prepa", {\r\n        user_id = actor.user_id,\r\n        sync_crystal = actor.cur_crystal,\r\n        last_oper_time = os.time() + 3600,\r\n        is_sacrifice = true,\r\n    })\r\nend')

# =====================================================================
# PATCH 7: match_panel.lua - Fix the timer to also play exit_battle
# =====================================================================
ok &= patch("match_panel.lua - timer", MATCH_LUA,
    b'function meta:Update(elapsed_time)\r\n    -- safety: if standby response never arrives within 3 seconds, auto-advance\r\n    if not self._standby_advanced then\r\n        self._standby_timer = (self._standby_timer or 0) + elapsed_time\r\n        if self._standby_timer > 3.0 then\r\n            self._standby_advanced = true\r\n            print("[MATCH] WARNING: No standby response in 3s, auto-advancing battle")\r\n            battle_logic.is_play_animation = false\r\n        end\r\n    end\r\nend',
    b'function meta:Update(elapsed_time)\r\n    -- safety: if standby response never arrives within 3 seconds, auto-advance\r\n    if not self._standby_advanced then\r\n        self._standby_timer = (self._standby_timer or 0) + elapsed_time\r\n        if self._standby_timer > 3.0 then\r\n            self._standby_advanced = true\r\n            print("[MATCH] WARNING: No standby response in 3s, auto-advancing battle")\r\n            battle_logic.is_play_animation = false\r\n            -- Also transition out of match screen\r\n            self:PlayAnimation("exit_battle", false)\r\n        end\r\n    end\r\nend')

# =====================================================================
# PATCH 8: offline_server.lua - Add [AI] prefix to enemy names
# =====================================================================
ok &= patch("offline_server.lua - guide enemy name", OFFLINE_SERVER,
    b'        enemy_name = "Will",',
    b'        enemy_name = "[AI] Will",')

ok &= patch("offline_server.lua - pve enemy name", OFFLINE_SERVER,
    b'        enemy_name = pcfg and pcfg.play_name or "Enemy",',
    b'        enemy_name = "[AI] " .. (pcfg and pcfg.play_name or "Enemy"),')

# =====================================================================
# Summary
# =====================================================================
if ok:
    print("\n=== All patches applied successfully ===")
else:
    print("\n=== SOME PATCHES FAILED - check warnings above ===")
