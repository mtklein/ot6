-- @suite slow
-- battle_relmkit.lua -- RELM's list behind Sketch (#538) in the World of
-- Balance: the list, Sketch from it, Portrait's gift and Tint's colour.
--
-- docs/design/kit-relm.md: Sketch opens a Tools-shell list (w7e6168 = 5) of
-- the rows she has learned, packed down the left column, then the right
-- (Ot6PaintRowTbl: Sketch at join, Portrait by switch $02E8, Tint at level
-- 18, Varnish 24, Still Life by $0240, Underpainting 36, Gesture 42,
-- Masterpiece by $00BA), each priced (Portrait 12, Tint 10 a body).
--
-- Played: Continue ultros-won-v1 (Esper Mountain's save point: TERRA,
-- LOCKE, STRAGO, RELM), step off the save tile and pace into random
-- battles; the plan's turns go through the real menus (H.kitBattle), the
-- others Defend.  Nothing is written.  Stages, one battle each:
--   1. the list, read on the Portrait row: the rows the fixture's level and
--      switches teach, packed in the table's order, at their prices; R
--      twice on Portrait leaves the pending boost where it was (Portrait
--      refuses a boost); then Sketch from the list's first row at a body:
--      vanilla's sketch ran (special effect $55, $11A9 <- $AA);
--   2. Portrait on an ally: the gift's mark, the ally's pending raised to
--      one, 12 MP; then that ally Fights at the one point the gift raised:
--      its bank is what it was (the gift paid the point), the mark is gone,
--      and the Fight swung its two extra times (Ot6FightBoost, $3A70);
--   3. Tint on an ally in a colour a standing body is weak to (and does not
--      absorb or null) that the ally's weapon lacks: four turns, 10 MP;
--      then the ally Fights that body: the swing carried the colour
--      ($11A1) and the weakness chip ran on it (Ot6Chip with the colour
--      matched).
-- A battle where a stage cannot be played (RELM or the ally down, no weak
-- body for stage 3) is fought out and the next taken.
-- Old-ROM red and mutants: build/attempts/wt/v047-relm/suites/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local RELM, CMD, FIGHT = 0x08, 0x0D, 0x00
local SKETCH, PORTRAIT, TINT, VARNISH, STILL, UNDER, GESTURE, MASTER = 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF
local COLOUR = 0xF0
local ROWS = {   -- Ot6PaintRowTbl: id, switch or level, price
  { SKETCH }, { PORTRAIT, sw = 0x02E8, mp = 12 }, { TINT, lv = 18, mp = 10 }, { VARNISH, lv = 24, mp = 14 },
  { STILL, sw = 0x0240, mp = 24 }, { UNDER, lv = 36, mp = 28 }, { GESTURE, lv = 42, mp = 30 },
  { MASTER, sw = 0x00BA, mp = 99 },
}
local GIFT, TINTT, TINTE = 0xEF0E, 0xEEFE, 0xEF06
local BUDGET = 16

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seatOf(ch) for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == ch then return s end end end
local function up(s)
  return s ~= nil and (H.readByte(0x3AA0 + s * 2) & 1) == 1 and H.readWord(0x3BF4 + s * 2) > 0
    and (H.readByte(0x3EE4 + s * 2) & 0xC2) == 0 and (H.readByte(0x3EE5 + s * 2) & 0xB0) == 0
end
local function monUp(s) return (H.readByte(0x3A75) >> s) & 1 == 1 end
local function sw(n) return (H.readByte(0x1E80 + (n >> 3)) >> (n & 7)) & 1 == 1 end
local function knows(r)
  if r.sw then return sw(r.sw) end
  if r.lv then return H.readByte(0x1600 + 37 * RELM + 8) >= r.lv end
  return true
end

local stage, battles, mode, plan = 1, 0, nil, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local rec, seen = {}, nil
local relm, ally, target, colour = nil, nil, nil, nil

local function arm()
  emu.addMemoryCallback(function()
    if relm == nil or (emu.getState()["cpu.x"] & 0xFF) ~= relm * 2 then return end
    local e = relm * 2
    rec.exec = { id = H.readByte(0xB6), b8 = H.readByte(0xB8), mp0 = H.readWord(0x3C08 + e),
      bank0 = H.readByte(0x3E9C + e), pend0 = H.readByte(0x3E9D + e), f = H.frame }
  end, emu.callbackType.exec, H.sym("Ot6PaintExec"), H.sym("Ot6PaintExec"))
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if relm ~= nil and x == relm * 2 and rec.exec ~= nil and rec.relmEnd == nil then
      rec.relmEnd = { f = H.frame, pend = H.readByte(0x3E9D + x) }
    elseif ally ~= nil and x == ally * 2 and rec.allyFight ~= nil and rec.allyEnd == nil then
      rec.allyEnd = { f = H.frame, pend = H.readByte(0x3E9D + x), bank = H.readByte(0x3E9C + x) }
    end
  end, emu.callbackType.exec, ae, ae)
  -- the ally's Fight: its command's head (Ot6FightBoost reads the pending
  -- boost and adds two swings a point to $3A70)
  local fb = H.sym("Ot6FightBoost")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if ally == nil or x ~= ally * 2 or rec.allyFight ~= nil or (rec.exec == nil and stage ~= 1) then return end
    rec.allyFight = { f = H.frame, pend = H.readByte(0x3E9D + x), bank = H.readByte(0x3E9C + x),
      gift = H.readByte(GIFT), swings0 = H.readByte(0x3A70) }
  end, emu.callbackType.exec, fb, fb)
  emu.addMemoryCallback(function(_, v)
    local x = emu.getState()["cpu.x"] & 0xFF
    if rec.allyFight ~= nil and rec.allyFight.swings1 == nil and ally ~= nil and x == ally * 2 then
      rec.allyFight.swings1 = v
    end
  end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)
  emu.addMemoryCallback(function(_, v)
    local x = emu.getState()["cpu.x"] & 0xFF
    if ally ~= nil and (x & 0xFE) == ally * 2 and rec.allyFight ~= nil then
      rec.swing = rec.swing or {}
      rec.swing[#rec.swing + 1] = v
    end
  end, emu.callbackType.write, 0x7E11A1, 0x7E11A1)
  emu.addMemoryCallback(function(_, v)
    if relm == nil or (emu.getState()["cpu.x"] & 0xFF) ~= relm * 2 or v ~= 0xAA then return end
    if H.readByte(0x3A7C) == CMD then rec.sketched = H.frame end
  end, emu.callbackType.write, 0x7E11A9, 0x7E11A9)
  local chip = H.sym("Ot6Chip")
  emu.addMemoryCallback(function()
    if target == nil or rec.allyFight == nil then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y ~= 8 + target * 2 then return end
    rec.chips = rec.chips or {}
    rec.chips[#rec.chips + 1] = { m = H.readByte(0x3BE0 + y) & H.readByte(0x11A1), broken = H.readByte(0x3E88 + y),
      sh = H.readByte(0x3E38 + y) }
  end, emu.callbackType.exec, chip, chip)
end

local function onList(p, a)
  if seen ~= nil or a ~= relm then return end
  seen = { mode = H.readByte(0x6168), cells = {} }
  for i = 0, 7 do
    seen.cells[i] = { id = H.readByte(0x4005 + i * 3), qty = H.readByte(0x4006 + i * 3) }
  end
  H.screenshot("relmkit_list")
end

local function decide()
  battles = battles + 1
  H.assertEq(battles <= BUDGET, true, string.format("the three stages within %d battles", BUDGET))
  plan, mode, rec, seen, ally, target, colour = {}, "fightout", {}, nil, nil, nil, nil
  relm = seatOf(RELM)
  if not up(relm) or H.readWord(0x3C08 + relm * 2) < 40 then
    H.log("[relmkit] RELM cannot act here (down, or short of MP): fought out")
    return
  end
  for d = 1, 3 do
    local s = (relm + d) % 4
    if up(s) and H.readByte(0x3ED8 + s * 2) ~= RELM then ally = s; break end
  end
  local mon
  for s = 0, 5 do if monUp(s) then mon = s; break end end
  if ally == nil or mon == nil then H.log("[relmkit] no ally or no body up: fought out"); return end
  if stage == 1 then
    plan = { { who = RELM, cmd = CMD, row = PORTRAIT, listR = 2, peek = true },
             { who = RELM, cmd = CMD, row = SKETCH, slot = mon } }
  elseif stage == 2 then
    plan = { { who = RELM, cmd = CMD, row = PORTRAIT, allySeat = ally },
             { who = H.readByte(0x3ED8 + ally * 2), cmd = FIGHT, boost = 1, slot = mon } }
  else
    -- a colour a standing body is weak to, absorbs and nulls not, that the
    -- ally's weapon (either hand) does not carry already
    local wpn = H.readByte(0x3B90 + ally * 2) | H.readByte(0x3B91 + ally * 2)
    for s = 0, 5 do
      local e = 8 + s * 2
      local ok = H.readByte(0x3BE0 + e) & ~H.readByte(0x3BCC + e) & ~H.readByte(0x3BCD + e) & ~wpn & 0xFF
      if monUp(s) and ok ~= 0 and H.readByte(0x3E88 + e) == 0 and H.readByte(0x3E38 + e) > 0 then
        for b = 0, 7 do if (ok >> b) & 1 == 1 then colour = b; break end end
        target = s
        break
      end
    end
    if target == nil then H.log("[relmkit] no unbroken body weak to a colour the ally lacks: fought out"); return end
    plan = { { who = RELM, cmd = CMD, row = TINT, row2 = COLOUR + colour, allySeat = ally },
             { who = H.readByte(0x3ED8 + ally * 2), cmd = FIGHT, boost = 0, slot = target } }
  end
  mode = "play"
  H.log(string.format("[relmkit] battle %d stage %d: RELM seat %d, ally seat %d, body %s, colour %s", battles,
    stage, relm, ally, tostring(target or mon), tostring(colour)))
end

local function closed()
  if stage == 1 then return rec.relmEnd ~= nil and H.frame > rec.relmEnd.f + 30 end
  return rec.allyEnd ~= nil and H.frame > rec.allyEnd.f + 30
end

local function judge()
  local k = H.vars.kit
  if stage == 1 then
    H.assertEq(seen ~= nil, true, "the list was read")
    H.assertEq(seen.mode, 5, "Sketch opened the painter's list (w7e6168 = 5)")
    local want, n = {}, 0
    for _, r in ipairs(ROWS) do if knows(r) then want[#want + 1] = r end end
    for i, r in ipairs(want) do
      local cell = ((i - 1) % 4) * 2 + (i - 1) // 4
      local c = seen.cells[cell]
      H.log(string.format("[relmkit] cell %d: $%02X at %d MP (row $%02X expected at %d)", cell, c.id, c.qty, r[1],
        r.mp or 0))
      H.assertEq(c.id, r[1], string.format("cell %d holds row $%02X (learned rows packed in table order)", cell, r[1]))
      H.assertEq(c.qty, r.mp or 0, string.format("row $%02X is priced %d", r[1], r.mp or 0))
      n = n + 1
    end
    for cell = 0, 7 do
      local used = false
      for i = 1, n do if ((i - 1) % 4) * 2 + (i - 1) // 4 == cell then used = true end end
      if not used then H.assertEq(seen.cells[cell].id, 0xFF, string.format("cell %d is empty", cell)) end
    end
    local p = plan[1]
    H.assertEq(p ~= nil and p.listR0 ~= nil, true, "R was pressed on the Portrait row")
    H.log(string.format("[relmkit] R twice on Portrait: pending %d -> %d", p.listR0, p.listR1))
    H.assertEq(p.listR1, p.listR0, "R on Portrait leaves the pending boost (it buys nothing)")
    H.assertEq(rec.sketched ~= nil, true, "the list's Sketch row ran vanilla's sketch (special effect $55)")
    return true
  end
  local ex, af, ae = rec.exec, rec.allyFight, rec.allyEnd
  H.assertEq(ex ~= nil, true, "RELM's row ran (Ot6PaintExec)")
  local mp1 = H.readWord(0x3C08 + relm * 2)
  if stage == 2 then
    local bank1 = H.readByte(0x3E9C + ally * 2)
    H.log(string.format("[relmkit] Portrait on seat %d: RELM MP %d -> %d, pending %d at the exec; the ally's Fight "
      .. "at %d pending, bank %d -> %d, gift $%02X -> $%02X, swings %s -> %s", ally, ex.mp0, mp1, ex.pend0, af.pend,
      af.bank, bank1, af.gift, H.readByte(GIFT), tostring(af.swings0), tostring(af.swings1)))
    H.assertEq(ex.id, PORTRAIT, "the row was Portrait")
    H.assertEq(ex.b8, 1 << ally, "it named the ally")
    H.assertEq(ex.mp0 - mp1, 12, "Portrait cost 12 MP")
    H.assertEq(af.gift & (1 << ally) ~= 0, true, "the ally held the gift when its Fight began")
    H.assertEq(af.pend >= 1, true, "the ally's Fight ran boosted")
    H.assertEq(af.bank - bank1, af.pend - 1, string.format("the gift paid a point: %d pending charged %d",
      af.pend, af.pend - 1))
    H.assertEq(H.readByte(GIFT) & (1 << ally), 0, "the gift is spent")
    H.assertEq(af.swings1 ~= nil and af.swings1 - af.swings0 == 2 * af.pend, true,
      "the points bought the Fight's swings, two a point, the gift's among them")
  else
    local c = 1 << colour
    local sws = {}
    for _, v in ipairs(rec.swing or {}) do sws[#sws + 1] = string.format("$%02X", v) end
    H.log(string.format("[relmkit] Tint colour bit $%02X on seat %d: RELM MP %d -> %d; the ally's swings carried "
      .. "%s; chips on slot %d: %d", c, ally, ex.mp0, mp1, table.concat(sws, " "), target, #(rec.chips or {})))
    H.assertEq(ex.id, COLOUR + colour, "the row was the colour picked from the second list")
    H.assertEq(ex.mp0 - mp1, 10, "Tint cost 10 MP")
    local carried = false
    for _, v in ipairs(rec.swing or {}) do if v & c ~= 0 then carried = true end end
    H.assertEq(carried, true, "the ally's swing carried the colour ($11A1)")
    local keyed = false
    for _, ch in ipairs(rec.chips or {}) do if ch.m & c ~= 0 then keyed = true end end
    if not keyed then
      H.log("[relmkit] no swing landed on the body unbroken: not counted")
      return false
    end
    H.assertEq(H.readByte(TINTT + ally * 2), 3, "the ally's Fight counted one of the Tint's four turns")
  end
  return true
end

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("ultros-won-v1"),
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() <= 7 and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "step left off the save tile")
  end)(),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright() >= 15 end, 3000, "settled", 5),
  H.call(function()
    H.assertEq((H.readByte(0x1850 + RELM) & 7) ~= 0, true, "RELM is in the party (she joined at Esper Mountain)")
    H.assertEq(sw(0x02E8), true, "switch $02E8 is set (her recruitment: Portrait)")
    arm()
  end),
  H.driveUntil(function() return stage > 3 end, 1400000, {
    H.cond(function() return not H.battleLoadStarted() end,
      { H.fieldCare({ tag = "relmkit" }), H.paceToEncounter("relmkit", 0, { { 6, 45 }, { 4, 45 } }) }, {}),
    H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
    H.call(decide),
    H.cond(function() return mode == "play" end, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = onList,
        planDone = closed }),
      H.call(function()
        if not closed() then
          H.log("[relmkit] the battle ended before the plan resolved: not counted")
          return
        end
        if judge() then
          H.log(string.format("[relmkit] PASSED stage %d", stage))
          stage = stage + 1
        end
      end),
    }, {}),
    H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    H.waitUntil(function() return not H.battleLoadStarted() and H.hasControl() end, 6000, "back in the field", 5),
  }, "the three stages"),
  H.logStep("[relmkit] done: the list, Sketch from it, Portrait's gift, Tint's colour"),
})
