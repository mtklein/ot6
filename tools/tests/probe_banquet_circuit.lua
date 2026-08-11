-- probe_banquet_circuit.lua -- I->J step development (issue #31): the ≥90
-- WINDOW CIRCUIT, driven from the staged banquet_window savestate
-- (probe_banquet_stage.lua) so iteration does not replay the world grind.
--
-- The drive is banquet-decode.md §5.2's circuit: talk to all 24 scoring
-- soldiers (banquet-decode §3 census) and win the four fights clean,
-- inside the 14400-frame timer.  Every soldier is a chaseTalk against its
-- OBJECT INDEX (0x10 + npc_prop record position, extracted 2026-07-28 --
-- eleven of the 24 wander), terminated on the soldier's OWN latch switch
-- OR on $013C (the dinner fired = the window expired: fail loudly with
-- the var0/timer measurement, the banquet-decode §8 feasibility ledger's
-- missing number).
--
-- Per-fight asserts (§5.4): formation species at $3F46, clean-win
-- b-switches $1dd1 & $31 == 0, var0 delta +6.
--
-- Ends: var0==44 checkpoint, ride the expiry to the dinner table, stop on
-- the TOAST choice ($056F>=2), generate banquet_dinner.mss for the Q&A probe.
--
--   tools/tests/run.sh tools/tests/probe_banquet_circuit.lua
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function timerCount() return H.readWord(0x1189) end
local function var0() return H.readWord(0x1fc2) end

-- expected var0, running (talk +1, clean fight +6); each step logs
-- timer/var0 so an over-budget run reports its own arithmetic
local expect = 0
local lastName = "start"

local function logCheckpoint(name)
  return H.call(function()
    H.log(string.format("[circuit] %-28s timer=%5d var0=%2d (expect %2d) f%d",
      name, timerCount(), var0(), expect, H.frame))
  end)
end

-- one scoring soldier: chase its object, talk, terminate on its latch
-- (or on $013C = window died -- then fail with the measurement)
local function soldier(objIdx, latch, what)
  expect = expect + 1
  local want = expect
  return {
    H.chaseTalk(objIdx, 12000, what, {
      done = function() return sw(latch) == 1 or sw(0x013C) == 1 end,
    }),
    H.call(function()
      if sw(0x013C) == 1 and sw(latch) == 0 then
        error(string.format(
          "WINDOW EXPIRED during %s: var0=%d of 44, timer=%d, frame %d",
          what, var0(), timerCount(), H.frame), 0)
      end
      H.assertEq(sw(latch), 1, what .. ": latch set")
      H.assertEq(var0(), want, what .. ": var0 (+1 talk)")
    end),
    logCheckpoint(what),
  }
end

-- one FIGHT soldier: same chase; the battle is battle-clear-write cleared by
-- chaseTalk itself; afterwards assert species, clean flags, +6
local function fightSoldier(objIdx, latch, species, what)
  expect = expect + 6
  local want = expect
  return {
    H.chaseTalk(objIdx, 18000, what, {
      done = function() return sw(latch) == 1 or sw(0x013C) == 1 end,
    }),
    H.call(function()
      if sw(0x013C) == 1 and sw(latch) == 0 then
        error(string.format(
          "WINDOW EXPIRED during %s: var0=%d of 44, timer=%d, frame %d",
          what, var0(), timerCount(), H.frame), 0)
      end
      H.assertEq(sw(latch), 1, what .. ": latch set")
      local w, found = H.formationWords(), false
      for i = 1, 6 do if w[i] == species then found = true end end
      H.assertEq(found, true, string.format(
        "%s: species $%03X in the formation words", what, species))
      H.assertEq(H.readByte(0x1dd1) & 0x31, 0,
        what .. ": clean win -- b-switches $40/$44/$45 all clear ($1dd1)")
      H.assertEq(var0(), want, what .. ": var0 (+1 talk, +5 clean)")
    end),
    logCheckpoint(what),
  }
end

-- hop an entrance (door/stair): navTo onto the tile, arrive on pred
local function hop(x, y, pred, what, maxF)
  return {
    H.navTo(x, y, { maxFrames = maxF or 20000, arrive = pred }),
    H.waitUntil(function()
      return pred() and H.tileAligned() and bright() >= 15
         and not H.dialogWaiting() and not H.battleLoadStarted()
    end, 2400, what .. " (landing)", 1),
    H.waitFrames(20),
    logCheckpoint(what),
  }
end

local steps = {
  H.loadState("build/states/banquet_window.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x007C), 1, "boot: window live")
    H.assertEq(sw(0x013C), 0, "boot: dinner not fired")
    H.log(string.format("[boot] map=%d (%d,%d) timer=%d var0=%d",
      map(), H.fieldX(), H.fieldY(), timerCount(), var0()))
  end),

  -- U1: the four in the west hall (21..25, 18..24)
  soldier(0x13, 0x021A, "250 (25,18) talk"),
  soldier(0x12, 0x0219, "250 (21,18) talk"),
  soldier(0x10, 0x0217, "250 (21,24) talk"),
  soldier(0x11, 0x0218, "250 (25,24) talk"),

  -- stairs (15,21) -> (24,52), lower west
  hop(15, 21, function() return H.fieldY() >= 40 end, "stairs -> (24,52)"),
  soldier(0x1F, 0x0227, "250 (9,49) talk [wander]"),

  -- door (9,52) -> 244 (13,21)
  hop(9, 52, function() return map() == 244 end, "door -> 244"),
  soldier(0x24, 0x0220, "244 (11,23) talk"),
  soldier(0x28, 0x0225, "244 (10,17) talk [wander]"),
  soldier(0x26, 0x0222, "244 (16,14) talk"),
  soldier(0x27, 0x0223, "244 (20,14) talk"),
  soldier(0x25, 0x0221, "244 (25,23) talk"),

  -- door (23,19) -> 250 (65,52); battle 27 at (51,50)
  hop(23, 19, function() return map() == 250 end, "door -> 250 (65,52)"),
  fightSoldier(0x1E, 0x0226, 0x0c7, "250 (51,50) BATTLE 27"),

  -- door (51,53) -> 252 (35,50): the six-wanderer room
  hop(51, 53, function() return map() == 252 end, "door -> 252"),
  soldier(0x15, 0x022E, "252 (40,54) talk"),
  soldier(0x10, 0x021B, "252 (40,56) talk [wander]"),
  soldier(0x13, 0x021E, "252 (37,57) talk [wander]"),
  fightSoldier(0x14, 0x022D, 0x0c7, "252 (42,57) BATTLE 27 [wander]"),
  soldier(0x12, 0x021D, "252 (42,56) talk [wander]"),
  soldier(0x11, 0x021C, "252 (42,52) talk [wander]"),

  -- exit (35,48) -> 250 (51,52); east along the lower corridor
  hop(35, 48, function() return map() == 250 end, "252 exit -> 250 (51,52)"),
  soldier(0x19, 0x021F, "250 (98,51) talk [wander]"),
  fightSoldier(0x20, 0x0228, 0x0c7, "250 (110,51) BATTLE 27 [wander]"),

  -- stairs (97,47) -> (115,22), upper east
  hop(97, 47, function() return H.fieldY() <= 30 end, "stairs -> (115,22)"),
  soldier(0x22, 0x022A, "250 (115,16) talk [wander]"),
  soldier(0x21, 0x0229, "250 (120,13) talk [wander]"),

  -- stairs (101,16) -> (37,14), back to the upper west
  hop(101, 16, function() return H.fieldX() <= 60 end, "stairs -> (37,14)"),

  -- down through the hall + corridor, door (22,34) -> 243 (15,10)
  hop(22, 34, function() return map() == 243 end, "door -> 243"),
  fightSoldier(0x17, 0x022B, 0x102, "243 (12,14) BATTLE 26"),
  soldier(0x18, 0x022C, "243 (18,14) talk"),
  soldier(0x16, 0x0224, "243 (8,18) talk"),

  -- ---- checkpoint: 44 before expiry ---------------------------------------
  H.call(function()
    H.assertEq(var0(), 44, "the window maximum: var0 == 44")
    H.assertEq(sw(0x013C), 0, "dinner has NOT fired -- 44 landed in-window")
    H.log(string.format(
      "[circuit COMPLETE] var0=44 timer=%d left, frame %d",
      timerCount(), H.frame))
    H.screenshot("bq_circuit_44")
  end),

  -- ---- ride the expiry to the dinner table --------------------------------
  H.release(),
  (function() local ph = 0
    return H.driveUntil(function()
      return map() == 251 and H.readByte(0x056f) >= 2 and H.dialogWaiting()
    end, 40000, {
      H.call(function()
        ph = (ph + 1) % 8
        -- hands off until the dinner fires; then A through the scene text
        -- (never when a choice is up -- that would answer the toast)
        if sw(0x013C) == 1 and H.dialogWaiting()
           and H.readByte(0x056f) < 2 then
          H.setPad(ph < 4 and { "a" } or {})
        else
          H.setPad({})
        end
      end),
    }, "expiry -> map 5 -> dinner table -> the toast choice")
  end)(),
  H.call(function()
    H.assertEq(map(), 251, "at the dinner table (map 251)")
    H.assertEq(sw(0x013C), 1, "$013C -- the dinner fired")
    H.assertEq(var0(), 44, "var0 carried into dinner")
    H.log(string.format("[dinner] toast choice up at f%d, $056F=%d",
      H.frame, H.readByte(0x056f)))
    H.screenshot("bq_dinner_toast")
  end),
  H.saveState("banquet_dinner.mss"),
  H.logStep(function()
    return string.format("circuit done: var0=44, dinner staged at frame %d",
      H.frame)
  end),
}

-- flatten nested step lists
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 120000 }, flat)
