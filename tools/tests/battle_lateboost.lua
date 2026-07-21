-- @suite
-- battle_lateboost: where the boost window closes.
--
-- v0.2 RC playtest: "you can boost after selecting the ability", "once
-- the list is gone you can still boost", "it looks cosmetic, didn't
-- notice any damage boost or BP being spent".  Measurement split that
-- report in two (probe_lateboost.lua), and only the second half was a
-- bug:
--
--   * DURING target select, boosting is legal and fully effective.
--     DESIGN.md prices boost "when confirming an action", and
--     Ot6QueueFold hangs off CreateAction (battle_main.asm:12978), which
--     runs after target select -- so the tier folds, the points are
--     charged, and tier-3 damage lands.  It only LOOKED cosmetic: the
--     spell-list preview the Narshe school teaches players to watch is
--     closed by then, and the over-character chevrons they were watching
--     instead were rendering as damage numerals (battle_dmgnum.lua).
--
--   * AFTER the target is confirmed it was theft.  CreateAction has
--     already frozen the tier, but Ot6ActionEnd charges whatever pending
--     reads when the action ends.  Pre-fix: two more R presses took
--     pending 2 -> 3, the spell stayed Fire 3, damage was identical
--     (319 both ways), and bp fell 5 -> 2 instead of 5 -> 3.  A third
--     point paid for nothing.
--
-- Ot6Boost now gates on $32cc,y = $ff, the actor's pending-action
-- command-list pointer ($ff = nothing queued; battle_main.asm:254).
-- This test pins BOTH halves: the accepted spend must still pay in full,
-- and the post-commit spend must move neither pending nor bp.  The
-- second is the negative control -- without it the test would pass just
-- as well if boosting had been disabled outright.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local ST = { spell = 0x0e, target = 0x38 }
local SPELL_FIRE, FIRE3 = 0x00, 0x09
local actor, execd, mhp0 = nil, {}, nil
local pendAtTarget, pendAfterCommit, bpAtTarget
local ching, chingRef = 0, nil

local function st() return H.readByte(0x7bc2) end
local function bp(s) return H.readByte(0x3e9c + s*2) end
local function pend(s) return H.readByte(0x3e9d + s*2) end
local function cmdptr(s) return H.readByte(0x32cc + s*2) end

local SPELLBASE = { [0] = 0x0000, [1] = 0x013c, [2] = 0x0278, [3] = 0x03b4 }
local function magicCursor(slot, spellId)
  local base = 0x2092 + SPELLBASE[slot]
  for i = 0, 53 do
    if H.readByte(base + i*4) == spellId then
      local r, c = i // 2, i % 2
      local scroll = (r <= 3) and 0 or math.min(r - 3, 0x17)
      H.writeByte(0x8913 + slot, scroll)
      H.writeByte(0x8917 + slot, c)
      H.writeByte(0x891b + slot, r - scroll)
      return true
    end
  end
  return false
end

local function monsterHp()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3bfc + s*2) end
  return t
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  -- the menu has to belong to a caster who owns a foldable spell; Terra
  -- is char index 0 (battle_fold.lua finds her the same way)
  H.driveUntil(function()
    if H.readByte(0x7bca) == 0 then return false end
    return H.readByte(0x3ed8 + (H.readByte(0x62ca) & 3)*2) == 0
  end, 8000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "terra holds the menu"),
  H.call(function()
    actor = H.readByte(0x62ca) & 3
    H.writeByte(0x3e9c + actor*2, 5)              -- bp to spend
    H.writeByte(0x3e9d + actor*2, 0)
    H.writeWord(0x3c08 + actor*2, 99)             -- mp
    for s = 0, 5 do
      if H.readWord(0x3bfc + s*2) > 0 then H.writeWord(0x3bfc + s*2, 3000) end
    end
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)   -- quiet the guards
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    local s1 = 0x3ee4 + actor*2                   -- clear magitek
    H.writeByte(s1, H.readByte(s1) & 0xf7)
    for i = 0, 3 do H.writeByte(0x202e + actor*12 + i*3, 0x02) end  -- Magic
    emu.addMemoryCallback(function(_, v) execd[#execd+1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
    -- $6281 is the "ching" sfx request Ot6Boost fires on a committed
    -- boost; a refused press must stay silent
    chingRef = emu.addMemoryCallback(function(_, v)
      if v ~= 0 then ching = ching + 1 end
    end, emu.callbackType.write, 0x7e6281, 0x7e6281)
  end),
  H.driveUntil(function() return st() == ST.spell end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "spell list open"),
  H.call(function()
    H.assertEq(magicCursor(actor, SPELL_FIRE), true, "cursor parked on Fire")
  end),
  H.waitFrames(20),
  H.driveUntil(function() return st() == ST.target end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "target select up"),
  H.call(function()
    H.assertEq(pend(actor), 0, "no boost pending on entering target select")
    H.assertEq(cmdptr(actor), 0xff,
      "action still uncommitted at the target cursor ($32cc = $ff)")
  end),
  -- ACCEPTED: boosting at the target cursor is legal and must pay
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    pendAtTarget, bpAtTarget = pend(actor), bp(actor)
    mhp0 = monsterHp()
    H.log(string.format("at target cursor: pend=%d bp=%d ching=%d",
      pendAtTarget, bpAtTarget, ching))
    H.assertEq(pendAtTarget, 2, "R at the target cursor still raises pending")
    H.assertEq(ching, 2, "...and each accepted boost chings")
  end),
  H.driveUntil(function() return st() ~= ST.target end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "target confirmed"),
  H.call(function()
    H.assertEq(cmdptr(actor) ~= 0xff, true,
      "positive control: the action really did commit ($32cc left $ff)")
    H.assertEq(H.readByte(0x7bca) ~= 0, true,
      "positive control: the menu is still open, so input still reaches us")
  end),
  -- REFUSED: the tier is frozen; these presses must buy and cost nothing
  H.pressButtons({ "r" }, 6), H.waitFrames(12),
  H.pressButtons({ "r" }, 6), H.waitFrames(12),
  H.call(function()
    pendAfterCommit = pend(actor)
    H.log(string.format("after post-confirm R x2: pend=%d bp=%d ching=%d",
      pendAfterCommit, bp(actor), ching))
    H.assertEq(pendAfterCommit, pendAtTarget,
      "NEGATIVE CONTROL: post-commit R does not raise pending")
    H.assertEq(bp(actor), bpAtTarget,
      "NEGATIVE CONTROL: post-commit R does not touch bp")
    H.assertEq(ching, 2, "NEGATIVE CONTROL: a refused boost makes no sound")
  end),
  H.waitUntil(function() return #execd > 0 end, 1200, "an action executed", 5),
  H.waitUntilSoft(function() return pend(actor) == 0 end, 1800,
    "pending consumed", 10),
  H.waitFrames(60),
  H.call(function()
    emu.removeMemoryCallback(chingRef, emu.callbackType.write, 0x7e6281, 0x7e6281)
    local ids = {}
    for _, v in ipairs(execd) do ids[#ids+1] = string.format("%02x", v) end
    H.log("executed attack ids: " .. table.concat(ids, " "))
    H.log(string.format("bp %d -> %d, damage dealt %d",
      bpAtTarget, bp(actor), mhp0 - monsterHp()))
    local folded = false
    for _, v in ipairs(execd) do if v == FIRE3 then folded = true end end
    H.assertEq(folded, true,
      "the target-select spend DID fold the spell (Fire -> Fire 3)")
    -- charged for two points, which is what was actually delivered.
    -- pre-fix this read 2 (5 - 3): a third point taken for no tier.
    H.assertEq(bp(actor), bpAtTarget - 2,
      "charged exactly the 2 points the fold used, not the post-commit 3")
    H.assertEq(pend(actor), 0, "pending cleared after the action")
    H.screenshot("lateboost")
  end),
})
