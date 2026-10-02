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
  local fee = r.level * 50
  local paid = r.gil0 - r.gil1
  H.log(string.format("[hiredhelp] hire %d at %d BP, L%d: TakeGil %s, purse %d -> %d, targets $%02X", i,
    r.boost, r.level, table.concat((function() local t = {} for _, c in ipairs(r.costs) do t[#t + 1] = c end
    return t end)(), "/"), r.gil0, r.gil1, r.targets))
  H.assertEq(#r.costs, 1 + r.boost, string.format("hire %d: 1 + boost hires (%d BP)", i, r.boost))
  for k, c in ipairs(r.costs) do
    H.assertEq(c, fee, string.format("hire %d, hit %d: the fee is level x 50, whatever the boost", i, k))
  end
  H.assertEq(paid, fee * (1 + r.boost), string.format("hire %d: the purse falls by every fee", i))
  H.assertEq(r.mp1, r.mp0, string.format("hire %d: no MP", i))
  local bank = r.boost == 0 and math.min(5, r.bank0 + 1) or r.bank0 - r.boost
  H.assertEq(r.bank1, bank, string.format("hire %d: the bank (%d before, %d BP)", i, r.bank0, r.boost))
  H.assertEq(r.targets ~= 0, true, string.format("hire %d was aimed at the monsters", i))
  -- every hire lands on the body its chip call names (the first on the
  -- target; one that outlives its target re-targets), with the class that
  -- body's row names first: replay them in order from the opening state
  local st = {}
  for b = 0, 5 do local o = r.mon0[b]; st[b] = { hp = o.hp, sh = o.sh, brk = o.brk ~= 0, cls = o.cls } end
  local hits = {}
  for _, c in ipairs(r.chips) do if c.y >= 8 then hits[#hits + 1] = c end end
  if #hits < 1 + r.boost then
    -- a hire past the last standing body lands nowhere
    for bb = 0, 5 do
      if r.mon0[bb].present then
        H.assertEq(r.mon1[bb].hp, 0, string.format("hire %d: %d of %d hires landed, so slot %d fell", i, #hits,
          1 + r.boost, bb))
      end
    end
  end
  H.assertEq(#hits >= 1 and #hits <= 1 + r.boost, true, string.format("hire %d: a hit a hire", i))
  -- one body a hire: the first lands on a body the queued mask named (the
  -- single-target ChooseTarget picks within it)
  local s0 = (hits[1].y - 8) // 2
  H.assertEq((r.targets >> s0) & 1, 1, string.format("hire %d: the first lands inside the aimed mask $%02X (slot %d)",
    i, r.targets, s0))
  for k, c in ipairs(hits) do
    local b = (c.y - 8) // 2
    local t = st[b]
    local class = sellsword(t.cls)
    H.assertEq(c.class, class, string.format("hire %d, hit %d: the sellsword's class on slot %d (row $%02X)", i, k, b,
      t.cls))
    local chip = class ~= 0 and t.sh > 0 and not t.brk
    if chip then t.sh = t.sh - 1; if t.sh == 0 then t.brk = true end end
    local d = 2 * fee
    if not t.brk and t.sh > 0 then d = (d * 8) >> 4 elseif t.brk and d < 32768 then d = d * 2 end
    d = math.min(d, 9999, t.hp)
    t.hp = t.hp - d
    H.log(string.format("[hiredhelp]   hit %d on slot %d: -%d (%s), HP now %d, shields %d", k, b, d,
      chip and "chips" or "no chip", t.hp, t.sh))
  end
  for b = 0, 5 do
    if r.mon0[b].present then
      H.assertEq(r.mon1[b].hp, st[b].hp, string.format("hire %d: slot %d's HP after every hit", i, b))
      if r.mon1[b].brk == 0 or r.mon0[b].brk ~= 0 then
        H.assertEq(r.mon1[b].sh, st[b].sh, string.format("hire %d: slot %d's shields after every hit", i, b))
      end
    end
  end
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
          for _, rec in ipairs(H.vars.setzer) do done[#done + 1] = rec end
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
    end
    H.log(string.format("[hiredhelp] PASSED: %d hires over %d battle(s)", #done, battles))
  end),
})
