-- @suite slow
-- battle_folddrill.lua -- the Drill's two strikes play one animation, and an
-- Overclocked Drill's four play two: two groups of two (#554).
--
-- docs/design/multi-hit.md 5.3.  Ot6HitCountTbl gives the Drill two strikes,
-- each a whole pass; at three points EDGAR's Overclock fires the Tool twice
-- (ot6_overclock.asm: $3a70 doubled plus one, four passes).  Since #554 a
-- fixed multi-hit animates the first strike of each group of OT6_FOLDN (the
-- Drill's 2) and carries the rest as folded strikes (command $04,
-- Ot6GfxCmdFold), so an Overclocked Drill reads as two Drills.
--
-- Played: Continue fc-alcove-v1 (EDGAR with his Tools and Overclock), rest
-- at the save (a Tent), walk into a random battle and play EDGAR's Tools
-- through the real menu (H.kitBattle; the others Defend while he banks):
-- the Drill unboosted, then the Drill at three points.  DECLARED WRITES
-- (state_write_waivers.txt): no battery on the route holds a Drill (the
-- shop that sells one refuses this party, route-wor-falcon.md), so the bag's
-- Debilitator cell is made a Drill before the walk; and every monster is
-- staged to 60000 HP at the battle's start, so every strike lands on a
-- standing body.  Asserted, per action, from its own events:
--   1. the plain Drill: two passes; its battle script is the name, one Tools
--      animation ($06, command $09) and its numeral, one folded strike and
--      its numeral (01 06 0B 04 0B);
--   2. the Overclocked Drill: three points pending, four passes; its script
--      plays the Tools animation twice, each followed by its numeral, a
--      folded strike and its numeral (01 06 0B 04 0B 06 0B 04 0B).
-- Negative: v0.49's ROM animates every strike and folds none
-- (build/attempts/wt/v050-multihit-anim/foldsuites/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, CMD_TOOLS, DRILL, DEBILITATOR = 0x04, 0x09, 0xA8, 0xA7
local STAGED_HP = 60000

local seat, rec, recs, battles = nil, nil, {}, 0

local function arm()
  local hc = H.sym("Ot6HitCount")
  emu.addMemoryCallback(function()
    if seat == nil or (emu.getState()["cpu.a"] & 0xFF) ~= DRILL then return end
    if rec ~= nil and rec.done == nil then return end
    rec = { f = H.frame, passes = 0, cmds = {}, pend = H.readByte(0x3E9D + seat * 2) }
    recs[#recs + 1] = rec
  end, emu.callbackType.exec, hc, hc)
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if rec == nil or rec.q ~= nil or (emu.getState()["cpu.x"] & 0xFF) ~= seat * 2 then return end
    rec.passes = rec.passes + 1
  end, emu.callbackType.exec, pt, pt)
  local b4 = H.sym("BtlGfx_04")
  emu.addMemoryCallback(function()
    if rec == nil or rec.q ~= nil then return end
    local q = {}
    for i = 0, 63 do
      local c = H.readByte(0x2D6E + i * 4)
      if c == 0xFF then break end
      q[#q + 1] = { c = c, b1 = H.readByte(0x2D6F + i * 4) }
    end
    rec.q = q
  end, emu.callbackType.exec, b4, b4)
  local ud = H.sym("UpdateDead")
  emu.addMemoryCallback(function()
    if rec ~= nil and rec.q ~= nil and not rec.done then rec.done = H.frame end
  end, emu.callbackType.exec, ud, ud)
end

local function codesOf(r)
  local codes, anim = {}, 0
  for _, e in ipairs(r.q or {}) do
    codes[#codes + 1] = string.format("%02X", e.c)
    if e.c == 0x06 and e.b1 == CMD_TOOLS then anim = anim + 1 end
  end
  return table.concat(codes, " "), anim
end

local function closed() return #recs >= 2 and recs[2].done ~= nil end

local function judge()
  for i, r in ipairs(recs) do
    local codes, anim = codesOf(r)
    H.log(string.format("[folddrill] use %d: the Drill at %d BP, %d pass(es); script [%s], %d Tools animation(s)",
      i, r.pend, r.passes, codes, anim))
  end
  local p, o = recs[1], recs[2]
  local pc, pa = codesOf(p)
  H.assertEq(p.pend, 0, "use 1: the Drill unboosted")
  H.assertEq(p.passes, 2, "use 1: two passes (Ot6HitCountTbl's x2)")
  H.assertEq(pa, 1, "use 1: one Tools animation for the two strikes (#554; v0.49 played two)")
  H.assertEq(pc, "01 06 0B 04 0B", "use 1: name, the animation and its numeral, one folded strike and its numeral")
  local oc, oa = codesOf(o)
  H.assertEq(o.pend, 3, "use 2: the Drill at three points (Overclock)")
  H.assertEq(o.passes, 4, "use 2: Overclock fired it twice: four passes")
  H.assertEq(oa, 2, "use 2: two Tools animations, one a firing (v0.49 played four)")
  H.assertEq(oc, "01 06 0B 04 0B 06 0B 04 0B", "use 2: two groups of two, each an animation and a folded strike")
end

local judged = false
local function decide()
  battles = battles + 1
  H.assertEq(battles <= 6, true, "a battle EDGAR can play both Drills in, within 6 battles")
  seat, rec, recs = nil, nil, {}
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == EDGAR then seat = s end end
  H.assertEq(seat ~= nil, true, "EDGAR is seated")
  for m = 0, 5 do
    if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
      H.writeWord(0x3BFC + m * 2, STAGED_HP)
      H.writeWord(0x3C24 + m * 2, STAGED_HP)
    end
  end
  H.log(string.format("[folddrill] battle %d: EDGAR seat %d MP %d; monsters staged to %d HP (declared write)",
    battles, seat, H.readWord(0x3C08 + seat * 2), STAGED_HP))
end

H.run({ maxFrames = 300000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: Overclock learned (the Magitek factory)")
    local cell = nil
    for i = 0, 255 do if H.readByte(0x1869 + i) == DEBILITATOR then cell = i; break end end
    H.assertEq(cell ~= nil, true, "the bag holds a Debilitator (fc-alcove-v1's Tools)")
    H.writeByte(0x1869 + cell, DRILL)
    H.log(string.format("[folddrill] bag cell %d: the Debilitator made a Drill (declared write)", cell))
  end),
  H.driveUntil(function() return judged end, 280000, {
    H.cond(function() return not H.battleActive() end, {
      H.fieldCare({ tag = "folddrill", threshold = 0.95, mpBand = 0.9 }),
      H.cond(function() return battles == 0 end, { H.fcAlcoveToBattle("folddrill") }, { H.fcPace("folddrill") }),
    }, {}),
    H.call(decide),
    H.kitBattle({ { who = EDGAR, cmd = CMD_TOOLS, row = DRILL, boost = 0 },
                  { who = EDGAR, cmd = CMD_TOOLS, row = DRILL, boost = 3 } },
      { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = closed }),
    H.call(function()
      if closed() then judge(); judged = true
      else H.log("[folddrill] the battle ended before both Drills resolved: not counted") end
    end),
  }, "a plain and an Overclocked Drill in one battle"),
  H.call(function()
    H.log("[folddrill] PASS: the Drill animates once for two strikes; Overclocked, twice for four")
  end),
})
