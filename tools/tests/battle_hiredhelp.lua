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
--   * the fee: TakeGil takes level x 50 at 0 BP and twice that at 1 BP,
--     and the purse falls by exactly that; no MP; the bank +1 / -1;
--   * one target, and the class: every chip call on it carries the first
--     physical class its row holds (slashing $01, else piercing $02, else
--     bludgeoning $04), or none when the row holds no physical class --
--     the sellsword's weapon fits the target, whatever SETZER holds;
--   * the hit: twice the fee, halved while its shields hold, doubled once
--     Broken (the hire's own chip can break it), never more than the HP;
--   * the target loses one shield exactly when that class exists and it
--     stood shielded and unbroken.
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
  local want = r.level * 50 * (1 << r.boost)
  H.log(string.format("[hiredhelp] hire %d at %d BP, L%d: TakeGil %s, purse %d -> %d, targets $%02X", i,
    r.boost, r.level, tostring(r.cost), r.gil0, r.gil1, r.targets))
  H.assertEq(r.cost, want, string.format("hire %d: the fee is level x 50 x 2^boost", i))
  H.assertEq(r.gil0 - r.gil1, want, string.format("hire %d: the purse falls by that", i))
  H.assertEq(r.mp1, r.mp0, string.format("hire %d: no MP", i))
  local bank = r.boost == 0 and math.min(5, r.bank0 + 1) or r.bank0 - r.boost
  H.assertEq(r.bank1, bank, string.format("hire %d: the bank (%d before, %d BP)", i, r.bank0, r.boost))
  local s = nil
  for b = 0, 5 do if (r.targets >> b) & 1 == 1 then H.assertEq(s, nil, "one target"); s = b end end
  H.assertEq(s ~= nil, true, string.format("hire %d hit a monster", i))
  local o, m = r.mon0[s], r.mon1[s]
  local class = sellsword(o.cls)
  for _, c in ipairs(r.chips) do
    if c.y == 8 + s * 2 then
      H.assertEq(c.class, class, string.format("hire %d: the sellsword's class on slot %d (row $%02X)", i, s, o.cls))
    end
  end
  local chip = class ~= 0 and o.sh > 0 and o.brk == 0
  local sh = chip and o.sh - 1 or o.sh
  local d = 2 * want
  if o.brk == 0 and sh > 0 then d = (d * 8) >> 4
  elseif (o.brk ~= 0 or (chip and sh == 0)) and d < 32768 then d = d * 2 end
  d = math.min(d, 9999, o.hp)
  H.log(string.format("[hiredhelp]   slot %d: HP %d -> %d (want -%d), shields %d -> %d (row $%02X, class $%02X)",
    s, o.hp, m.hp, d, o.sh, m.sh, o.cls, class))
  H.assertEq(o.hp - m.hp, d, string.format("hire %d: the hit on slot %d", i, s))
  if not (chip and sh == 0) then
    H.assertEq(o.sh - m.sh, chip and 1 or 0, string.format("hire %d: slot %d's shields", i, s))
  end
end

local WANT = { { row = HIRE, boost = 1 }, { row = HIRE, boost = 0 } }
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
