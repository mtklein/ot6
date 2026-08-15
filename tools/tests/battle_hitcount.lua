-- @suite slow savestate=vargas_won
-- battle_hitcount.lua -- #54: a real Pummel strikes twice, and only the
-- abilities in Ot6HitCountTbl strike more than once.
--
-- Why hit count is the thing worth pinning.  In OT6 a landed hit that matches
-- a weakness chips a shield, so hit count is the break-rate dial.  That the
-- chip is per landed hit rather than once per action is measured separately
-- and asserted by tools/tests/probe_multihit.lua: one boosted Fight action
-- swinging eight times chipped four shields off one guard, 6 -> 5 -> 4 -> 3 ->
-- 2 -> 1, at $3a70 = 7, 5, 3, 1, with a class-weak-to-nothing control guard
-- that kept all six.  This file therefore pins the other half, the half #54
-- builds: how many times each ability strikes.
--
-- What the ROM does now.  Ot6HitCountTbl (ff6/src/battle/ot6_hitcount.asm)
-- adds its value to $3a70, "number of attacks (0 = 1 attack)"
-- (battle_main.asm:6428), from a jsl in Cmd_0a (Blitz, battle_main.asm:3438)
-- and Cmd_09 (Tools, :4014).  The dangerous property of any such hook is
-- re-entry: the multi-attack loop at battle_main.asm:8390-8392 pushes
-- ExecAttack again for each remaining count, so a hook that runs inside the
-- loop re-arms $3a70 and the action never ends.  The command handlers cannot
-- be re-entered that way -- the loop returns to ExecAttack, never to Cmd_0a --
-- and ExecCmd clears $3a70 through InitGfxScript (:6428) before dispatching.
-- This test is the measurement of that argument rather than the argument
-- itself: it watches every write to $3a70 inside one real Pummel and requires
-- the hook's write to happen exactly once.
--
-- Honest drive (#75): no state is written.  The fixture is vargas_won, Sabin
-- on the Mt. Kolts ledge just after his own boss fight, the same fixture and
-- the same lane-pacing and menu-walking idioms battle_blitzlist.lua uses.  A
-- natural encounter is paced into, Sabin's real Blitz command is opened, and
-- two of his real learned rows are picked with the d-pad and A.
--
-- Asserted:
--   1. AuraBolt, a Blitz with no row in the table, leaves $3a70 at 0: one
--      attack, one Ot6HitJoin.  This is the keyed-table control, and it runs
--      through the identical Cmd_0a hook, so it separates "the table is
--      consulted" from "every Blitz got a hit".
--   2. Pummel sets $3a70 to 1 -- exactly one such write inside the action --
--      and the action makes two Ot6HitJoin passes.  Two landed hits is two
--      chip opportunities.
--   3. The power split that pays for the extra hit is in the built ROM:
--      MagicProp $5d = 55 (was 110) and $64 = 32 (was 128), with $5f Suplex
--      at its vanilla 180 as the untouched control, and ItemProp $a8 Drill
--      = 96 (was 191) with $a6 Chain Saw at 252 as its control.  These are
--      the byte POSITIONS the splices in battle_main.asm and menu/item.asm
--      cannot assert for themselves.
--   4. Ot6HitCountTbl itself, read out of the ROM, is the three rows the
--      design documents and no others, so the table and multi-hit.md cannot
--      drift apart silently.
--
-- The hit counts are exact rather than lucky.  Both blitzes carry $20 in
-- MagicProp +$04 ($11a4, "can't dodge"), and CheckHit's `bit #$20` arm takes
-- the carry-clear exit with no roll, so neither can whiff and neither count
-- can come back one short on an unlucky run.
--
-- Not asserted here: that the two hits chip two shields.  That needs a
-- bludgeon-weak target, and which formation the ledge draws is random, so
-- asserting it would be a check that passes for the wrong reason on the runs
-- where the draw is unlucky.  Chips seen are logged, not required; the
-- per-hit chip rule is probe_multihit's assertion.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_TGT = 0x05, 0x30, 0x38
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, KNOWN = 0x202E, 0x4005, 0x1D28
local SABIN = 0x05
local PUMMEL, AURABOLT, BLITZ_ATK0 = 0x5D, 0x5E, 0x5D
local SCROLL, CUR_COL, CUR_ROW = 0x895F, 0x8963, 0x8967

-- the ROM tables this test reads back
local MAGICPROP = H.sym("MagicProp") & 0x3FFFFF
local ITEMPROP = H.sym("ItemProp") & 0x3FFFFF
local HITTBL = H.sym("Ot6HitCountTbl") & 0x3FFFFF
local MAGIC_REC, ITEM_REC = 14, 30

-- ------------------------------------------------------------- recording --
-- One timeline, so an action's events can be cut out of it by order rather
-- than by frame: a two-hit volley spans several frames, and keying on frames
-- undercounted probe_multihit's own headline before it was fixed.
local log, refs = {}, {}

local function arm()
  refs.cmd = emu.addMemoryCallback(function()
    log[#log + 1] = { k = "cmd", frame = H.frame, id = H.readByte(0x00B6) }
  end, emu.callbackType.exec, H.sym("Cmd_0a"), H.sym("Cmd_0a"))
  refs.count = emu.addMemoryCallback(function()
    log[#log + 1] = { k = "hook", frame = H.frame,
                      id = emu.getState()["cpu.a"] & 0xFF,
                      n = H.readByte(0x3a70) }
  end, emu.callbackType.exec, H.sym("Ot6HitCount"), H.sym("Ot6HitCount"))
  refs.join = emu.addMemoryCallback(function()
    log[#log + 1] = { k = "hit", frame = H.frame,
                      y = emu.getState()["cpu.y"] & 0xFF }
  end, emu.callbackType.exec, H.sym("Ot6HitJoin"), H.sym("Ot6HitJoin"))
  refs.chip = emu.addMemoryCallback(function()
    log[#log + 1] = { k = "chip", frame = H.frame,
                      y = emu.getState()["cpu.y"] & 0xFF }
  end, emu.callbackType.exec, H.sym("Ot6ClassChip"), H.sym("Ot6ClassChip"))
  refs.n = emu.addMemoryCallback(function(_, v)
    log[#log + 1] = { k = "n", frame = H.frame, v = v }
  end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)
  -- $3410 is "last spell used", written by InitTarget_02 as an action starts.
  -- It is recorded so that "did Sabin's blitz execute" can be answered WITHOUT
  -- consulting Ot6HitCount: on a ROM whose Cmd_0a shim is missing, waiting on
  -- the hook alone just times out, and a timeout reads like a broken drive
  -- rather than a missing feature.  Measured, by building exactly that ROM.
  refs.spell = emu.addMemoryCallback(function(_, v)
    log[#log + 1] = { k = "spell", frame = H.frame, v = v }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
end

local function castsOf(id)
  local n = 0
  for _, e in ipairs(log) do
    if e.k == "spell" and e.v == id then n = n + 1 end
  end
  return n
end

local function playerBlitzesOf(id)
  local n = 0
  for _, e in ipairs(log) do
    if e.k == "cmd" and e.id == id then n = n + 1 end
  end
  return n
end

local function disarm()
  emu.removeMemoryCallback(refs.cmd, emu.callbackType.exec,
    H.sym("Cmd_0a"), H.sym("Cmd_0a"))
  emu.removeMemoryCallback(refs.count, emu.callbackType.exec,
    H.sym("Ot6HitCount"), H.sym("Ot6HitCount"))
  emu.removeMemoryCallback(refs.join, emu.callbackType.exec,
    H.sym("Ot6HitJoin"), H.sym("Ot6HitJoin"))
  emu.removeMemoryCallback(refs.chip, emu.callbackType.exec,
    H.sym("Ot6ClassChip"), H.sym("Ot6ClassChip"))
  emu.removeMemoryCallback(refs.n, emu.callbackType.write, 0x7E3A70, 0x7E3A70)
  emu.removeMemoryCallback(refs.spell, emu.callbackType.write, 0x7E3410, 0x7E3410)
end

-- Cut this ability's actions out of the timeline: each runs from the
-- Ot6HitCount entry carrying its id up to and including the $3a70 write of
-- $ff that ends the multi-attack loop (battle_main.asm:8390-8391,
-- `dec $3a70 / bmi`).  Actions resolve one at a time, so a slice cannot
-- contain another actor's work.
local function actionsFor(id)
  local out = {}
  for start, e0 in ipairs(log) do
    if e0.k == "hook" and e0.id == id then
      local a = { sets = {}, hits = 0, chips = 0, at = e0.frame,
                  before = e0.n, closed = false }
      for i = start + 1, #log do
        local e = log[i]
        if e.k == "hook" then break end      -- next action began: unterminated
        if e.k == "n" then
          if e.v == 0xFF then a.closed = true break end
          a.sets[#a.sets + 1] = e.v
        elseif e.k == "hit" then a.hits = a.hits + 1
        elseif e.k == "chip" then a.chips = a.chips + 1 end
      end
      out[#out + 1] = a
    end
  end
  return out
end

local function firstFor(id) return actionsFor(id)[1] end

-- The best Pummel seen so far.  "Best" is needed rather than "the first"
-- because an ExecAttack pass whose target is already dead never reaches
-- CalcTargetDmg, so a Pummel that kills the ledge trash outright shows one
-- Ot6HitJoin pass even though the engine ran the loop twice (measured: the
-- first run of this test hit exactly that, $3a70 writes [1 0] with one
-- join).  The two-hit case needs a target that survives the first hit, and
-- which formation the ledge draws is random, so the drive casts Pummel every
-- Sabin turn until one lands on a survivor.
local function bestFor(id)
  local best = nil
  for _, a in ipairs(actionsFor(id)) do
    if a.closed and (best == nil or a.hits > best.hits) then best = a end
  end
  return best
end

local function describe(tag, a)
  H.log(string.format("%s: entered with $3a70=%d, writes [%s], "
    .. "%d Ot6HitJoin pass(es), %d class-chip hook entr(ies), closed=%s "
    .. "(frame %d)", tag, a.before, table.concat(a.sets, " "), a.hits,
    a.chips, tostring(a.closed), a.at))
end


-- ---------------------------------------------------------------- driving --
-- One per-frame driver for everything, in battle_blitzgrey.lua's shape: pace
-- the ledge for an encounter when there is no battle, page battle dialogs,
-- let bystanders Defend, and on Sabin's turn walk his real Blitz command and
-- cast whatever `want` currently is.  Every button is toggled on a phase edge,
-- because a held button is not a fresh press and the confirm and the target
-- confirm both need one.
--
-- The Blitz shell is TWO COLUMNS, so entry n sits at row n//2, column n%2.
-- Walking to "row n, column 0" instead parks the cursor on entry 2n: for
-- AuraBolt that is an empty cell, A is refused, and the drive times out having
-- asserted, from wItemList, that the row it never reached held the right
-- ability.  Measured on this file's first run.  The entry is found by scanning
-- wItemList for the id rather than assumed.
local slotOf = {}
local want = nil

local function map() return H.mapId() & 0x1ff end

local function entryOf(id)
  for i = 0, 7 do
    if H.readByte(ITEMLIST + i * 3) == id then return i end
  end
  return nil
end

local ph, hb, lane = 0, -900, nil
local BACK = { left = "right", right = "left", up = "down", down = "up" }

local function pulse()
  ph = ph + 1
  local edge = ph % 10 < 5
  if H.frame - hb >= 900 then
    hb = H.frame
    H.log(string.format("[hb f%d] want=$%02x batt=%s menu=%02x actor=%d "
      .. "mstate=%02x map=%d events=%d", H.frame, want or 0,
      tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
      H.readByte(MSTATE), map(), #log))
  end

  if not H.battleLoadStarted() then
    -- field: page the victory/EXP dialogs, then pace the lane for the next
    -- encounter.  The lane anchor is re-detected on every field return,
    -- because a stale anchor walks the party off the map.
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then
          lane = { ax = x, ay = y, out = d, back = BACK[d] } break
        end
      end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil

  if H.readByte(MENU) == 0 then                      -- page a battle dialog
    H.setPad(edge and { a = true } or {})
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= slotOf[SABIN] then                         -- bystander: Defend
    local step = ph % 40
    if step < 4 then H.setPad({ right = true })
    elseif step >= 20 and step < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local st = H.readByte(MSTATE)
  if st == ST_TGT then
    H.setPad(edge and { a = true } or {})
  elseif st == ST_TOOLS then
    local e = entryOf(want)
    if e == nil then H.setPad({}) return end
    local row, col = e // 2, e % 2
    local cr, cc = H.readByte(CUR_ROW + a), H.readByte(CUR_COL + a)
    if H.readByte(SCROLL + a) ~= 0 then
      H.setPad(edge and { up = true } or {})
    elseif cr ~= row then
      H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
    elseif cc ~= col then
      H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
    else
      H.setPad(edge and { a = true } or {})
    end
  elseif st == ST_CMD then
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_BLITZ then wantCell = i end
    end
    assert(wantCell, "SABIN's real command list carries Blitz")
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then H.setPad(edge and { a = true } or {})
    elseif cur < wantCell then H.setPad(edge and { down = true } or {})
    else H.setPad(edge and { up = true } or {}) end
  else
    H.setPad({})
  end
end

local function drive(pred, maxFrames, what)
  return H.driveUntil(pred, maxFrames, { H.call(pulse), H.waitFrames(1) }, what)
end

local learned = {}

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),

  -- 3 & 4. the built ROM's data, before a single frame of battle.  These are
  -- pure reads of the shipped tables and are asserted first so that a splice
  -- typo fails immediately rather than after a five-minute drive.
  H.call(function()
    local function magicPow(i) return H.readRomByte(MAGICPROP + i * MAGIC_REC + 6) end
    local function itemPow(i) return H.readRomByte(ITEMPROP + i * ITEM_REC + 0x14) end
    H.assertEq(magicPow(PUMMEL), 55,
      "MagicProp $5d Pummel power is the split 55 (vanilla 110, halved for x2)")
    H.assertEq(magicPow(0x64), 32,
      "MagicProp $64 Bum Rush power is the split 32 (vanilla 128, quartered for x4)")
    H.assertEq(magicPow(0x5F), 180,
      "MagicProp $5f Suplex is untouched at 180 -- the splice's control, and "
      .. "the record between the two overridden ones")
    H.assertEq(itemPow(0xA8), 96,
      "ItemProp $a8 Drill power is the split 96 (vanilla 191, halved for x2)")
    H.assertEq(itemPow(0xA6), 252,
      "ItemProp $a6 Chain Saw is untouched at 252 -- the item splice's control")

    local rows, x = {}, 0
    while true do
      local key = H.readRomByte(HITTBL + x)
      if key == 0xFF then break end
      rows[#rows + 1] = string.format("$%02x+%d", key,
        H.readRomByte(HITTBL + x + 1))
      x = x + 2
      assert(x < 64, "Ot6HitCountTbl has no $ff terminator")
    end
    H.log("Ot6HitCountTbl as built: " .. table.concat(rows, " "))
    H.assertEq(table.concat(rows, " "), "$5d+1 $64+3 $a8+1",
      "Ot6HitCountTbl is exactly Pummel x2, Bum Rush x4, Drill x2 -- the "
      .. "three rows docs/design/multi-hit.md documents, and no others")
  end),

  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on map 98"),
  H.call(function()
    H.assertEq(map(), 98, "vargas_won on map 98, the Kolts ledge")
    local mask = H.readByte(KNOWN)
    for i = 0, 7 do
      if (mask >> i) & 1 == 1 then learned[#learned + 1] = BLITZ_ATK0 + i end
    end
    H.assertEq(learned[1], PUMMEL, "row 0 of the save's learned set is Pummel")
    H.assertEq(learned[2], AURABOLT,
      "row 1 is AuraBolt -- the control ability, learned at this fixture")
  end),

  -- pace the auto-detected lane until the first natural encounter fires,
  -- then learn the party layout and arm the recording.  From here on
  -- everything is `pulse`, which paces for further encounters by itself.
  drive(function() return H.battleLoadStarted() end, 12600,
    "the first ledge encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[SABIN], "SABIN present (vargas_won party)")
    arm()
  end),

  -- 1. the control first: AuraBolt, a Blitz with no table row -----------------
  -- Waited on the CAST ($3410) rather than on the hook, so that a ROM whose
  -- Cmd_0a shim is missing fails on the named assertion below instead of
  -- timing out here with nothing to say.
  H.call(function() want = AURABOLT end),
  -- $3410 is shared by player and monster abilities; a ledge monster can
  -- write AuraBolt's numeric id before Sabin acts.  Bind the drive to the
  -- real Blitz command handler instead.
  drive(function() return playerBlitzesOf(AURABOLT) >= 1 end, 20000,
    "Sabin's AuraBolt enters Cmd_0a"),
  -- keep the battle running for the action to resolve, on a fixed budget
  -- rather than a predicate, so the verdict below is an assertion that names
  -- what is wrong instead of a timeout that does not
  H.repeatN(400, { H.call(pulse), H.waitFrames(1) }),
  H.call(function()
    local a = firstFor(AURABOLT)
    assert(a, "AuraBolt reached Ot6HitCount.  If this is the failure, the "
      .. "Cmd_0a shim (battle_main.asm:3438) is gone and no Blitz consults "
      .. "Ot6HitCountTbl at all -- verified by building exactly that ROM")
    H.assertEq(a.closed, true, "the AuraBolt action's attack loop finished "
      .. "inside the 400-frame budget")
  end),

  -- 2. the headline: Pummel, cast every Sabin turn until one lands on a target
  -- that survives its first hit.  A Pummel that kills the ledge trash outright
  -- makes only one Ot6HitJoin pass even though the engine ran the loop twice,
  -- so a single cast would measure the loop but not the second landed hit.
  -- Which formation the ledge draws is random, so this is a bounded ladder
  -- rather than one attempt; if no target in the budget survives a 55-power
  -- hit, the drive times out and that is the finding.
  H.call(function() want = PUMMEL end),
  drive(function()
    local a = bestFor(PUMMEL)
    return a ~= nil and a.hits >= 2
  end, 40000, "a Pummel whose target survives its first hit"),

  H.call(function()
    disarm()
    H.screenshot("hitcount_pummel")

    local ab = firstFor(AURABOLT)
    local pummels = actionsFor(PUMMEL)
    local pu = bestFor(PUMMEL)
    -- The clause that fails when the measurement did not happen: without
    -- these, a run where neither blitz ever reached Cmd_0a would reach the
    -- assertions below with nothing to say and agree with itself.
    assert(ab, "an AuraBolt action reached Ot6HitCount")
    assert(pu, "a Pummel action reached Ot6HitCount")
    describe("AuraBolt", ab)
    for i, a in ipairs(pummels) do describe("Pummel #" .. i, a) end

    -- The once-per-action property is asserted over EVERY Pummel cast, not
    -- just the one that landed twice: a hook that re-armed on some later
    -- action would otherwise hide behind the first clean one.
    for i, a in ipairs(pummels) do
      if a.closed then
        H.assertEq(#a.sets, 2, string.format(
          "Pummel #%d wrote $3a70 twice: the hook's 1 and the loop's dec", i))
        H.assertEq(a.sets[1], 1, string.format(
          "Pummel #%d had the hook set $3a70 = 1, once", i))
        H.assertEq(a.before, 0, string.format(
          "Pummel #%d was handed a cleared $3a70 by ExecCmd", i))
      end
    end
    H.assertEq(ab.closed, true, "the AuraBolt action's attack loop ended")
    H.assertEq(pu.closed, true, "the measured Pummel's attack loop ended")
    H.assertEq(ab.before, 0, "ExecCmd handed AuraBolt a cleared $3a70")
    H.assertEq(#ab.sets, 0,
      "AuraBolt is absent from Ot6HitCountTbl, so nothing wrote $3a70 before "
      .. "the loop's terminating dec: one attack, as vanilla")
    H.assertEq(ab.hits, 1, "AuraBolt made one Ot6HitJoin pass")

    H.assertEq(pu.sets[2], 0, "the loop decremented it once, spending hit two")
    H.assertEq(pu.hits, 2,
      "one Pummel action made two Ot6HitJoin passes -- two landed hits on one "
      .. "body, and therefore two chip opportunities")

    H.log(string.format("%d Pummel(s) cast; chips seen: AuraBolt %d, best "
      .. "Pummel %d (chips are not asserted -- the ledge draw decides whether "
      .. "the target is bludgeon-weak)", #pummels, ab.chips, pu.chips))
    H.log("PASSED: Pummel strikes twice, AuraBolt once, the hook fires once "
      .. "per action, and the power split is in the shipped tables")
  end),
})
