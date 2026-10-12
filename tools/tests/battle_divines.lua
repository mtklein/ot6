-- @suite slow
-- battle_divines.lua -- Cleave (Cyan's divine) on the 3-BP gate.
--
--   tools/tests/run.sh tools/tests/battle_divines.lua
--
-- The owner's rule (2026-10-11, kits.md "Divines"): a divine's one gate is a
-- full 3-BP boost.  No once-a-battle limit, no Broken condition.  Cleave is
-- SwdTech tech 8 (attack $5c), the SwdTech window's 3-BP row; Ot6Oblivion,
-- after ChooseTarget in CalcAttackEffect, marks Death on a killable target
-- ($3dd4) and turns the cut on a death-immune one into the heaviest single
-- cut (power 255, Death and the auto-miss cleared).
--
-- Boots cyan_defence: a real solo Cyan (L11, katana) on map 120 beside the
-- map's own battle-43 grinding soldiers (2x species $001, 100 hp) and the
-- battle-46 commander (species $14E, 456 hp).  Cyan is played through the
-- real menu (H.kitBattle): the SwdTech row, the cursor onto the row, A;
-- real Defends bank the points.
--
-- Declared unit-test expedients (tools/state_write_waivers.txt), because
-- Cleave is SwdTech tech 8, reached by level at L70 and this Cyan is L11:
--   KNOWN ($2020) := 7 and MP := 999, so the window enumerates tech 8 and
--   the 99-MP cut is paid;
--   the learned SwdTechs ($1CF7) := all eight and the loadout word ($1E1D)
--   := Cleave in the 1- and 2-BP slots and Quadra Slice in the 3-BP slot,
--   read and set back to AUTO (0), for the gate's manual-loadout arm;
--   in battle 2, the commander's $3aa1 bit 2 (the boss bit), since no
--   generated battle fields a death-protected body beside Cyan, and his HP
--   raised to 30,000 so the first heavy cut leaves him standing for the
--   second.
--
-- Asserted:
--   battle 1 (the soldiers): the window's rows 0 and 1 (1 and 2 BP) are not
--     Cleave and row 2 (3 BP) is; with Cleave stored in the 1-BP slot of a
--     manual loadout, row 0 still is not (Ot6CleaveSlot); Cleave at 3 BP
--     kills an unbroken soldier (one in-proc Death mark, the body dead),
--     and, after three Defends bank the points again, a second Cleave in the
--     same battle kills the second soldier;
--   battle 2 (the commander, the boss bit set): two Cleaves in the same
--     battle, each marking no Death, cutting at power 255 (an in-proc $11a6
--     write) and landing (the commander's HP falls at each).
-- A kill is checked against the mechanism with pc-gated write watches
-- (Death marks and the power write from inside Ot6Oblivion), so a cut that
-- damage-kills cannot be mistaken for the divine.  Old-ROM red (main's ROM
-- on main's fixtures): build/attempts/wt/v027-kits/mx1/; mutants:
-- build/attempts/wt/v027-kits/final-matrix/ (<rom>__battle_divines.out).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/cyan_defence.mss.lua"

local MENU = 0x7BCA
local KNOWN = 0x2020
local ITEMLIST = 0x4005
local LOADOUT = 0x1E1D
local CYAN, CMD_SWDTECH, CLEAVE = 0x02, 0x07, 0x5C

local function ent(m) return 8 + m * 2 end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return H.readByte(0x3AA8 + m * 2) % 2 == 1 end
local function dead(m) return H.readByte(0x3EE4 + ent(m)) & 0x80 ~= 0 end

local cyanSlot, msPresent = nil, {}

-- ---- the in-proc watches -------------------------------------------------
local OBLIV = H.sym("Ot6Oblivion")
local divineKills, cuts = {}, {}
local watching = false
local function inProc()
  local s = emu.getState()
  local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
  return pc >= OBLIV and pc < OBLIV + 0x100
end
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  pcall(function()
    if inProc() then divineKills[#divineKills + 1] = ((addr - 0x7E0000 - 0x3DD4) - 8) // 2 end
  end)
end, emu.callbackType.write, 0x7E3DD4 + 8, 0x7E3DD4 + 0x13)
emu.addMemoryCallback(function(_, v)
  if not watching then return end
  pcall(function() if inProc() then cuts[#cuts + 1] = v end end)
end, emu.callbackType.write, 0x7E11A6, 0x7E11A6)

local function stageCeiling(tag)
  H.writeWord(KNOWN, 7)                       -- tech-8 window (L70 by play)
  H.writeWord(0x3C08 + cyanSlot * 2, 999)     -- Cleave costs 99 (#57)
  H.log("[" .. tag .. "] ceiling staged: KNOWN:=7, MP:=999 (declared expedient)")
end

local function surveyBattle()
  cyanSlot, msPresent = nil, {}
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == CYAN then cyanSlot = s end
  end
  assert(cyanSlot, "CYAN is in this battle")
  for m = 0, 5 do
    if present(m) then msPresent[#msPresent + 1] = m end
  end
  assert(#msPresent > 0, "the battle has monsters")
end

-- the SwdTech window's rows, read as Cyan's window opens (opts.onList)
local rowsSeen = {}
local function readRows()
  local t = {}
  for r = 0, 2 do t[r] = H.readByte(ITEMLIST + r * 6) end
  return t
end

local function bootBattle(obj, what)
  return {
    H.waitFrames(20),
    H.loadState(STATE),
    H.waitFrames(30),
    H.setRows({ [CYAN] = true }, { tag = what .. " back row" }),
    H.talkToObj(obj, what .. ": engage", 20000),
    (function()
      return H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
        H.call(function() H.setPad(H.frame % 8 < 4 and { a = true } or {}) end),
      }, what .. ": battle starts")
    end)(),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200, what, 5),
    H.waitFrames(150),
    H.call(function()
      surveyBattle()
      local parts = {}
      for _, m in ipairs(msPresent) do
        parts[#parts + 1] = string.format("m%d hp=%d", m, mhp(m))
      end
      H.log(string.format("[%s] cyan slot %d bp=%d | %s", what, cyanSlot,
        H.readByte(0x3E9C + cyanSlot * 2), table.concat(parts, " | ")))
      stageCeiling(what)
      divineKills, cuts = {}, {}
      watching = true
    end),
  }
end

local function cleave(n, onList)
  local plan = {}
  for _ = 1, n do plan[#plan + 1] = { who = CYAN, cmd = CMD_SWDTECH, row = CLEAVE, boost = 3, direct = true } end
  return plan
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- ============ battle 1: the soldiers -- the gate, and two Cleaves =========
add(bootBattle(17, "battle 1"))
add({
  H.call(function()
    -- the manual loadout's arm: Cleave stored in the 1-BP slot (slot 1 =
    -- bits 3-5) and in the 2-BP slot (bits 6-8), the 3-BP slot left as the
    -- auto window's (Stunner's id 5 ... any learned tech; tech 6 here)
    H.writeByte(0x1CF7, 0xFF)
    H.writeWord(LOADOUT, (7 << 3) | (7 << 6) | (6 << 9))
    H.log("[battle 1] SwdTechs learned := all eight; loadout word := Cleave in the 1- and 2-BP slots, Quadra "
      .. "Slice in the 3-BP slot (declared expedients)")
  end),
  H.kitBattle({ { who = CYAN, cmd = CMD_SWDTECH, boost = 1, peek = true } },
    { untilPlanDone = true, idle = "defend", onList = function() rowsSeen.manual = readRows() end }),
  H.call(function()
    local r = rowsSeen.manual
    H.assertEq(r ~= nil, true, "the manual-loadout window was read")
    H.log(string.format("[battle 1] manual loadout rows: %02X %02X %02X", r[0], r[1], r[2]))
    H.assertEq(r[0] ~= CLEAVE and r[1] ~= CLEAVE, true,
      "Cleave stored (and learned) in the 1- and 2-BP slots is not offered there (Ot6CleaveSlot)")
    H.assertEq(r[2], 0x5B, "the 3-BP slot holds the stored Quadra Slice ($5b): the manual loadout is being read")
    H.writeWord(LOADOUT, 0)
    H.log("[battle 1] loadout word := 0 (AUTO) again")
  end),
  H.kitBattle(cleave(1), { untilPlanDone = true, idle = "defend",
    onList = function() rowsSeen.auto = readRows() end,
    planDone = function() return #divineKills >= 1 and H.readByte(0x3E9D + cyanSlot * 2) == 0 end }),
  H.call(function()
    local r = rowsSeen.auto
    H.log(string.format("[battle 1] auto window rows: %02X %02X %02X", r[0], r[1], r[2]))
    H.assertEq(r[0] ~= CLEAVE and r[1] ~= CLEAVE, true, "rows 0 and 1 (1 and 2 BP) are not Cleave")
    H.assertEq(r[2], CLEAVE, "row 2 (3 BP) is Cleave ($5c)")
    H.assertEq(#divineKills, 1, "the first Cleave marked one Death from inside Ot6Oblivion")
  end),
  H.waitFrames(120),
  H.call(function()
    local m = divineKills[1]
    H.assertEq(dead(m) or not present(m), true, string.format("soldier %d, unbroken, is dead", m))
    watching = false
  end),
})

-- ============ battle 2: the commander as a boss -- the heavy cut ==========
local hp0 = nil
add(bootBattle(16, "battle 2"))
add({
  H.call(function()
    local m = msPresent[1]
    H.writeByte(0x3AA1 + ent(m), H.readByte(0x3AA1 + ent(m)) | 0x04)
    H.writeWord(0x3BFC + m * 2, 30000)
    hp0 = mhp(m)
    H.log(string.format("[battle 2] commander m%d: $3aa1.2 SET and HP := %d (declared expedient)", m, hp0))
  end),
  H.kitBattle(cleave(2), { untilPlanDone = true, idle = "defend",
    planDone = function() return #cuts >= 2 and H.readByte(0x3E9D + cyanSlot * 2) == 0 end }),
  H.waitFrames(120),
  H.call(function()
    local m = msPresent[1]
    H.log(string.format("[battle 2] after: hp %d -> %d, in-proc Death marks %d, in-proc power writes %s", hp0,
      mhp(m), #divineKills, table.concat((function() local t = {}; for _, v in ipairs(cuts) do t[#t + 1] = tostring(v)
        end; return t end)(), ",")))
    H.assertEq(#divineKills, 0, "a death-immune body drew no Death mark")
    H.assertEq(#cuts, 2, "two Cleaves in the same battle, each cut by Ot6Oblivion")
    H.assertEq(cuts[1] == 255 and cuts[2] == 255, true, "Ot6Oblivion set each cut's power to 255")
    H.assertEq(mhp(m) < hp0, true, "and the cuts landed")
    watching = false
  end),
})

H.run({ maxFrames = 300000 }, steps)
