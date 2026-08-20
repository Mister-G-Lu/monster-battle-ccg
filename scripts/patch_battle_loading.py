#!/usr/bin/env python3
"""Fix battle loading stuck: offline server must send cmd_battle_standby response,
and battle_logic must handle it properly."""
import os

# =====================================================================
# Fix 1: offline_battle.lua - HandleStandby must emit cmd_battle_standby
# =====================================================================
path1 = os.path.join(os.path.dirname(__file__), 'decrypted', 'src', 'manager', 'offline_battle.lua')
with open(path1, 'r') as f:
    content = f.read()

old1 = 'function offline_battle:HandleStandby()\n    return nil\nend'
new1 = '''function offline_battle:HandleStandby()
    self:PushCommand("cmd_battle_standby", {})
    return nil
end'''

if old1 in content:
    content = content.replace(old1, new1, 1)
    with open(path1, 'w') as f:
        f.write(content)
    print('[1] offline_battle: HandleStandby now emits cmd_battle_standby')
else:
    print('[1] SKIP - already patched or not found')

# =====================================================================
# Fix 2: battle.lua - cmd_battle_standby must NOT block forever.
# Add a timeout safety: if is_play_animation stays true for 5+ seconds,
# force-clear it.
# =====================================================================
path2 = os.path.join(os.path.dirname(__file__), 'decrypted', 'src', 'logic', 'battle.lua')
with open(path2, 'r') as f:
    content2 = f.read()

# In Update(), add a safety timeout for is_play_animation
old2 = '''    if self.is_play_animation then
        -- 如果正在部署，暂停所有的战斗指令的执行
        return
    end'''

new2 = '''    if self.is_play_animation then
        -- safety: if animation has been blocking for 5+ seconds, force-unblock
        self._anim_block_time = (self._anim_block_time or 0) + elapsed_time
        if self._anim_block_time > 5.0 then
            print("[BATTLE] WARNING: is_play_animation stuck for " .. self._anim_block_time .. "s, force-clearing")
            self.is_play_animation = false
            self._anim_block_time = 0
            self:CommandComplete()
        end
        -- 如果正在部署，暂停所有的战斗指令的执行
        return
    else
        self._anim_block_time = 0
    end'''

if old2 in content2:
    content2 = content2.replace(old2, new2, 1)
    with open(path2, 'w') as f:
        f.write(content2)
    print('[2] battle.lua: Added 5s safety timeout for is_play_animation')
else:
    print('[2] SKIP - already patched or not found')

# =====================================================================
# Fix 3: match_panel.lua - Add fallback: if ReqBattleStandby gets no
# response within 3 seconds, auto-advance
# =====================================================================
path3 = os.path.join(os.path.dirname(__file__), 'decrypted', 'src', 'modules', 'battle', 'match_panel.lua')
with open(path3, 'r') as f:
    content3 = f.read()

# After the Show() function's PlayAnimation callback, add a safety timer
old3 = '''function meta:Show()
    self:setVisible(true)
    self:PlayAnimation("enter_battle",false, function ()
        battle_logic:ReqBattleStandby()
        self:PlayAnimation("loop_battle", true)
    end)
end'''

new3 = '''function meta:Show()
    self:setVisible(true)
    self._standby_timer = 0
    self._standby_advanced = false
    self:PlayAnimation("enter_battle",false, function ()
        battle_logic:ReqBattleStandby()
        self:PlayAnimation("loop_battle", true)
    end)
end

function meta:Update(elapsed_time)
    -- safety: if standby response never arrives within 3 seconds, auto-advance
    if not self._standby_advanced then
        self._standby_timer = (self._standby_timer or 0) + elapsed_time
        if self._standby_timer > 3.0 then
            self._standby_advanced = true
            print("[MATCH] WARNING: No standby response in 3s, auto-advancing battle")
            battle_logic.is_play_animation = false
        end
    end
end'''

if old3 in content3:
    content3 = content3.replace(old3, new3, 1)
    with open(path3, 'w') as f:
        f.write(content3)
    print('[3] match_panel.lua: Added 3s safety timeout for standby response')
else:
    print('[3] SKIP - already patched or not found')

print('\nDone! Run build_and_verify.py to rebuild.')
