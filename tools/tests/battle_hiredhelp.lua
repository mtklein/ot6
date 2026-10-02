-- @suite slow
-- battle_hiredhelp.lua -- SETZER's Hired Help (#319, kits.md "Setzer"): the
-- table's third row, hired twice, at 1 BP and unboosted.
--
-- Played, not staged: Continue the wor-tomb-v1 battery (SETZER back in the
-- World of Ruin), walk Darill's Tomb's east room until the game deals a
-- battle (field group 151), and play SETZER's turns through the real menu
-- (H.setzerBattle), as many battles as the draws take.  Every assertion is
-- derived from the battle's own state, so any formation the room deals is
-- a valid draw; SETZER_SKIP (default 0) battles are fought out first to
-- vary it.
--
-- What it holds, per hire (at Ot6SetzerExec's entry and SETZER's
-- Ot6ActionEnd):
--   * the hires: 1 + boost of them, one a pass of the action, each paying
--     its own fee, level x 50 (TakeGil at every pass), so the purse falls by
--     every fee; no MP; the bank +1 / -1;
--   * one target, and the class: every chip call on it carries the first
--     physical class its row holds (slashing $01, else piercing $02, else
--     bludgeoning $04), or none when the row holds no physical class --
--     the sellsword's weapon fits the target, whatever SETZER holds;
--   * each hit: twice the fee, halved while the body's shields hold,
--     doubled once Broken (a hire's own chip can break it), never more than
--     the HP; one shield off exactly when that class exists and the body
--     stood shielded and unbroken -- replayed hit by hit from the opening
--     state and held against every body's HP and shields at the end.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/
-- (rate, boost, class) fail the named assertion.
--
-- And what the player sees (wt/hire-sprite): each hire is a figure walking
-- in where SETZER walked out, the boost bringing the next one (merchant,
-- Imperial soldier, General Leo, Shadow -- Interceptor while Shadow fights in
-- the party).  Read from the animation's own state, not a flag: at every
-- pass's animation (Ot6CoinAnim) the figure byte it carries; at every strike
-- (FightCmdAnim, or Interceptor's $FC through MagicCmdAnim) the graphics id
-- SETZER's slot shows and its $7F graphics buffer compared byte for byte
-- with that figure's sheet in the ROM (as LoadCharGfx builds it); the slot's
-- x offset each frame (SETZER off screen, OT6_HIRE_OFF past home); and at
-- the action's end SETZER's own sheet back in the buffer, at home.  Every
-- paid hire is one drawn strike.  Negative control: the hire on GP Rain's
-- coin animation (build/attempts/wt/hire-sprite/) fails "every paid hire".

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

SETZER_SKIP = SETZER_SKIP or 0
local HIRE = 0x5A

local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

local function sellsword(row)
  if row & 0x01 ~= 0 then return 0x01 end
  if row & 0x02 ~= 0 then return 0x02 end
  if row & 0x04 ~= 0 then return 0x04 end
  return 0x00
end

local function checkHire(r, i)
  return H.setzerCheckCoins(r, i, 50, sellsword, "hiredhelp")
end

-- ---- the crew on screen ----------------------------------------------------
local SETZER_GFX = 0x09
local FIG_GFX = { [0] = 0x13, [1] = 0x0E, [2] = 0x10, [3] = 0x03 }   -- merchant, soldier, Leo, Shadow
local FIG_NAME = { [0] = "merchant", [1] = "soldier", [2] = "Leo", [3] = "Shadow", [4] = "Interceptor" }
-- the weapon a figure swings by class (none, slashing, piercing, bludgeoning):
-- item ids from the design (kits.md), the Fight animation's number is id + 1
local FIG_WEAPON = {
  [0] = { 0x00, 0x0B, 0x00, 0x34 }, [1] = { 0x0A, 0x0A, 0x1D, 0x46 },
  [2] = { 0x14, 0x14, 0x22, 0x46 }, [3] = { 0x26, 0x2B, 0x26, 0x44 },
}
local function rom(a) return H.readRomByte(a & 0x3FFFFF) end
local sheets = {}
local function sheet(g)          -- a slot's $7F buffer as LoadCharGfx builds it for g
  if sheets[g] then return sheets[g] end
  local p = H.sym("CharGfxPtrs") + 3 * g
  local base = rom(p) | (rom(p + 1) << 8) | (rom(p + 2) << 16)
  local tbl, out = H.sym("_c2c745"), {}
  for t = 0, 255 do
    local off = rom(tbl + 2 * t) | (rom(tbl + 2 * t + 1) << 8)
    for b = 0, 31 do out[t * 32 + b] = (off == 0xFFFF) and 0 or rom(base + off + b) end
  end
  local function rev(v)
    local r = 0
    for i = 0, 7 do if v & (1 << i) ~= 0 then r = r | (1 << (7 - i)) end end
    return r
  end
  for i = 0, 63 do out[0x3C0 + i] = rev(out[0x3C0 + i]); out[0x10C0 + i] = rev(out[0x10C0 + i]) end
  sheets[g] = out
  return out
end
local function bufferOff(slot, g)  -- bytes of the slot's buffer that are not g's sheet
  local want, base, bad = sheet(g), 0x10000 + slot * 0x2000, 0
  for i = 0, 0x1FFF do
    if emu.read(base + i, emu.memType.snesWorkRam) ~= want[i] then bad = bad + 1 end
  end
  return bad
end
local function shadowFielded()
  for s2 = 0, 3 do if H.readByte(0x3ED8 + s2 * 2) == 3 then return true end end
  return false
end
local crew = { passes = {}, strikes = {}, ends = {} }
local function armCrew()
  local cur = nil
  local function script(i) return H.readByte(H.readWord(0x76) + i) end
  local an = H.sym("Ot6CoinAnim")
  emu.addMemoryCallback(function()
    if script(2) ~= HIRE or script(3) & 0x80 == 0 then cur = nil; return end
    local slot = H.readByte(H.readWord(0x78) + 1) & 3
    cur = { f = H.frame, mark = script(3), slot = slot, x0 = H.readWord(0x61D4 + slot * 32), xmax = -32768,
      shadow = shadowFielded() }
    crew.passes[#crew.passes + 1] = cur
  end, emu.callbackType.exec, an, an)
  local function strike(kind)
    return function()
      if not cur then return end
      if kind == "dog" and script(2) ~= 0xFC then return end
      local g = H.readByte(0x7B6C + cur.slot)
      crew.strikes[#crew.strikes + 1] = { f = H.frame, pass = cur, kind = kind, gfx = g, weapon = script(3),
        off = bufferOff(cur.slot, g), x = H.readWord(0x61D4 + cur.slot * 32) }
    end
  end
  local fa, ma = H.sym("FightCmdAnim"), H.sym("MagicCmdAnim")
  emu.addMemoryCallback(strike("fight"), emu.callbackType.exec, fa, fa)
  emu.addMemoryCallback(strike("dog"), emu.callbackType.exec, ma, ma)
  emu.addEventCallback(function()
    if cur then
      local x = H.readWord(0x61D4 + cur.slot * 32)
      if x >= 0x8000 then x = x - 0x10000 end
      if x > cur.xmax then cur.xmax = x end
    end
  end, emu.eventType.endFrame)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xff
    if x < 8 and H.readByte(0x3ED8 + x) == 9 then
      local slot = x // 2
      crew.ends[#crew.ends + 1] = { f = H.frame, slot = slot, gfx = H.readByte(0x7B6C + slot),
        off = bufferOff(slot, SETZER_GFX), x = H.readWord(0x61D4 + slot * 32) }
      cur = nil
    end
  end, emu.callbackType.exec, ae, ae)
end
local function checkCrew(r, i)
  local tag = string.format("hire %d", i)
  local passes, strikes, done = {}, {}, nil
  for _, p in ipairs(crew.passes) do if p.f >= r.f and p.f <= r.ended then passes[#passes + 1] = p end end
  for _, s2 in ipairs(crew.strikes) do if s2.f >= r.f and s2.f <= r.ended then strikes[#strikes + 1] = s2 end end
  for _, e in ipairs(crew.ends) do if e.f == r.ended then done = e end end
  H.assertEq(#passes, 1 + r.boost, tag .. ": one hire animation a pass")
  local home = passes[1] and passes[1].x0 or 0
  for k, p in ipairs(passes) do
    local fig = (p.mark >> 4) & 7
    local want = math.min(k - 1, 3)
    if want == 3 and p.shadow then want = 4 end
    H.log(string.format("[hiredhelp] %s pass %d: mark $%02X -- the %s, class bits %d%s%s; slot %d went to %+d (home %d)",
      tag, k, p.mark, FIG_NAME[fig] or "?", (p.mark >> 2) & 3, p.mark & 1 ~= 0 and ", first" or "",
      p.mark & 2 ~= 0 and ", last" or "", p.slot, p.xmax - (home >= 0x8000 and home - 0x10000 or home), home))
    H.assertEq(fig, want, string.format("%s pass %d: the %s comes", tag, k, FIG_NAME[want]))
    H.assertEq(p.mark & 1 ~= 0, k == 1, string.format("%s pass %d: SETZER steps out on the first pass only", tag, k))
    H.assertEq(p.mark & 2 ~= 0, k == #passes, string.format("%s pass %d: SETZER comes back after the last only", tag, k))
    H.assertEq(p.xmax - (home >= 0x8000 and home - 0x10000 or home) >= 96, true,
      string.format("%s pass %d: SETZER's slot went off screen (96 px past home)", tag, k))
  end
  H.assertEq(#strikes, #r.costs, string.format("%s: every paid hire was drawn as its figure's strike (%d strikes, %d paid)",
    tag, #strikes, #r.costs))
  for j, s2 in ipairs(strikes) do
    local fig = (s2.pass.mark >> 4) & 7
    local cls = (s2.pass.mark >> 2) & 3
    H.log(string.format("[hiredhelp] %s strike %d (%s, f%d): slot shows gfx $%02X, %d of 8192 buffer bytes off its sheet, weapon $%02X, x %d",
      tag, j, s2.kind, s2.f, s2.gfx, s2.off, s2.weapon, s2.x))
    if fig == 4 then
      H.assertEq(s2.kind, "dog", string.format("%s strike %d: Interceptor's own animation", tag, j))
    else
      H.assertEq(s2.kind, "fight", string.format("%s strike %d: a Fight swing", tag, j))
      H.assertEq(s2.gfx, FIG_GFX[fig], string.format("%s strike %d: the slot shows the %s", tag, j, FIG_NAME[fig]))
      H.assertEq(s2.off, 0, string.format("%s strike %d: the slot's graphics buffer is the %s's sheet", tag, j, FIG_NAME[fig]))
      H.assertEq(s2.weapon, FIG_WEAPON[fig][cls + 1] + 1, string.format("%s strike %d: the %s's weapon for class %d", tag, j,
        FIG_NAME[fig], cls))
    end
  end
  H.assertEq(done ~= nil, true, tag .. ": SETZER's slot read at Ot6ActionEnd")
  H.log(string.format("[hiredhelp] %s ends: slot shows gfx $%02X, %d buffer bytes off SETZER's sheet, x %d (home %d)",
    tag, done.gfx, done.off, done.x, home))
  H.assertEq(done.gfx, SETZER_GFX, tag .. ": SETZER's slot shows SETZER again")
  H.assertEq(done.off, 0, tag .. ": SETZER's own sheet is back in the buffer")
  H.assertEq(done.x, home, tag .. ": SETZER stands at home again")
end

local WANT = { { row = HIRE, boost = 1 }, { row = HIRE, boost = 0 } }   -- two hires, then one
local done, battles = {}, 0
local function remaining()
  local t = {}
  for i = #done + 1, #WANT do t[#t + 1] = WANT[i] end
  return t
end

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(armCrew),
  H.repeatN(SETZER_SKIP, { walkToBattle(), H.setzerBattle({}) }),
  H.driveUntil(function() return #done >= #WANT end, 160000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, "both hires within four battles")
    end),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(remaining(), { shot = "hiredhelp_table" })
        local r = step:tick()
        if r == "done" then
          for _, rec in ipairs(H.vars.setzer) do
            done[#done + 1] = rec
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "both hires resolve"),
  H.call(function()
    H.assertEq(#done, #WANT, "two hires resolved")
    for i, r in ipairs(done) do
      H.assertEq(r.row, HIRE, string.format("record %d is a Hired Help", i))
      H.assertEq(r.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
      checkHire(r, i)
      checkCrew(r, i)
    end
    H.log(string.format("[hiredhelp] PASSED: %d hires over %d battle(s)", #done, battles))
  end),
})
