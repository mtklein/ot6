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
-- cut (power 255, Death and the auto-miss cleared); since #388 a death-immune
-- body it strikes also loses four shields before the hit (Ot6CleaveStrip,
-- through Ot6TakeShields, the leaf OT6's Break takes shields with).  The
-- record strikes the whole enemy side (SwdTech has no target select;
-- ChooseTarget's pick for its targeting is every monster), and since #388's
-- second call each body struck is read, not only the primary: every killable
-- one takes the Death mark (Ot6CleaveMark), every death-immune one the strip
-- and the cut, unsplit ($11a2 bit 6).
--
-- Boots cyan_defence: a real solo Cyan (L11, katana) on map 120 beside the
-- map's own battle-43 grinding soldiers (2x species $001, 100 hp) and the
-- battle-46 commander (species $14E, 456 hp).  Cyan is played through the
-- real menu (H.kitBattle): the SwdTech row, the cursor onto the row, A;
-- real Defends bank the points.
--
-- Declared unit-test expedients (tools/state_write_waivers.txt), because
-- Cleave is SwdTech tech 8, learned at the Phantom Train farewell (#379),
-- and this Cyan is the L11 one of the Doma defence, before it (the soldiers
-- and the commander are only here; battle_cleave reads the learned Cleave
-- and its window from the play after the farewell):
--   the learned SwdTechs ($1CF7) := all eight, KNOWN ($2020) := 7 (what
--   InitSkills would have counted from them) and MP := 999, so the window
--   enumerates tech 8 and the 99-MP cut is paid;
--   the loadout word ($1E1D) := Cleave in the 1- and 2-BP slots and Quadra
--   Slice in the 3-BP slot, read and set back to AUTO (0), for the gate's
--   manual-loadout arm;
--   in battle 2, the commander's $3aa1 bit 2 (the boss bit), since no
--   generated battle fields a death-protected body beside Cyan, his HP
--   raised to 30,000 so the first heavy cut leaves him standing for the
--   second, and his shields set to 6 (OT6_SHIELD_CUR) so the first strip's
--   four is seen whole and the second's breaks him.
--
-- Asserted:
--   battle 1 (the soldiers): the window's rows 0 and 1 (1 and 2 BP) are not
--     Cleave and row 2 (3 BP) is; with Cleave stored in the 1-BP slot of a
--     manual loadout, row 0 still is not (Ot6CleaveSlot); one Cleave at 3 BP
--     kills every unbroken soldier standing (one in-proc Death mark on each,
--     the bodies dead); no shield is taken off a killable body (no in-proc
--     OT6_SHIELD_CUR write);
--   battle 2 (the commander, the boss bit set): two Cleaves in the same
--     battle, each marking no Death, cutting at power 255 (an in-proc $11a6
--     write) and landing (the commander's HP falls at each); the first
--     takes exactly four shields (6 -> 2, one in-proc write each), and the
--     second takes what is left, the last one breaking him (an in-proc
--     OT6_BROKEN_TICKS write);
--   battle 3 (the soldiers, the highest slot staged as the boss: the bit, HP
--     30,000, six shields; the primary target is the add): one Cleave marks
--     Death on every add and none on the boss, takes exactly four of the
--     boss's shields, cuts at power 255, and the cut on the boss is whole
--     (at least 3/4 of battle 2's lone first cut through the same shields;
--     a split halves it).
-- #388's second call: build/attempts/wt/v041-divines-2/mx/mx3/ (main's ROM red at run time, battle 1: "Death mark
-- ... on each soldier standing: got 2, want 2,3"; mutants cleave_nomark and cleave_split red; mx1/ is the first
-- build, whose widening of the mask was a no-op: the mask is already the whole side).
-- #388's old-ROM red and mutants: build/attempts/wt/v041-cleave-bumrush/divines/mx/ (main's ROM fails at load,
-- its symbols lacking Ot6TakeShields; the cleave_nostrip mutant is main's behaviour at run time).
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
local TAKE = H.sym("Ot6TakeShields")
local SH_CUR, BRK_TICKS = 0x3E38, 0x3E88      -- OT6_SHIELD_CUR, OT6_BROKEN_TICKS (by entity offset)
local divineKills, cuts, takes, breaks, struck = {}, {}, {}, {}, {}
local watching = false
local function pcNow()
  local s = emu.getState()
  return (s["cpu.k"] << 16) | s["cpu.pc"]
end
local function inProc()
  local pc = pcNow()
  return pc >= OBLIV and pc < OBLIV + 0x100
end
local function inTake()
  local pc = pcNow()
  return pc >= TAKE and pc < TAKE + 0x26   -- Ot6TakeShields's size in ff6-en.dbg
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
-- each Cleave as Ot6Oblivion enters: the living monsters ($3a75, UpdateDead's mask) and each one's HP then
emu.addMemoryCallback(function()
  if not watching or H.readByte(0x3A7D) ~= CLEAVE then return end
  local t = { alive = {}, hp = {} }
  for m = 0, 5 do
    if (H.readByte(0x3A75) >> m) & 1 == 1 then t.alive[#t.alive + 1] = m; t.hp[m] = mhp(m) end
  end
  struck[#struck + 1] = t
end, emu.callbackType.exec, OBLIV, OBLIV)
-- the shields Cleave takes (before its $11a6 write: t.cut counts the cuts before it): every OT6_SHIELD_CUR / OT6_BROKEN_TICKS write a
-- monster's byte takes from inside Ot6TakeShields (nothing else casts Break here)
emu.addMemoryCallback(function(addr, v)
  if not watching then return end
  pcall(function()
    if inTake() then takes[#takes + 1] = { m = ((addr - 0x7E0000 - SH_CUR) - 8) // 2, v = v, cut = #cuts } end
  end)
end, emu.callbackType.write, 0x7E0000 + SH_CUR + 8, 0x7E0000 + SH_CUR + 0x13)
emu.addMemoryCallback(function(addr, v)
  if not watching or v == 0 then return end
  pcall(function()
    if inTake() then breaks[#breaks + 1] = { m = ((addr - 0x7E0000 - BRK_TICKS) - 8) // 2, cut = #cuts } end
  end)
end, emu.callbackType.write, 0x7E0000 + BRK_TICKS + 8, 0x7E0000 + BRK_TICKS + 0x13)

local function stageCeiling(tag)
  H.writeByte(0x1CF7, 0xFF)                   -- all eight learned (Cleave at
  H.writeWord(KNOWN, 7)                       --   the farewell, #379), counted
  H.writeWord(0x3C08 + cyanSlot * 2, 999)     -- Cleave costs 99 (#57)
  H.log("[" .. tag .. "] ceiling staged: $1CF7:=FF, KNOWN:=7, MP:=999 (declared expedient)")
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
      divineKills, cuts, takes, breaks, struck = {}, {}, {}, {}, {}
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
    H.writeWord(LOADOUT, (7 << 3) | (7 << 6) | (6 << 9))
    H.log("[battle 1] loadout word := Cleave in the 1- and 2-BP slots, Quadra "
      .. "Slice in the 3-BP slot (declared expedient)")
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
    H.assertEq(#struck, 1, "one Cleave")
    local alive = struck[1].alive
    H.log(string.format("[battle 1] at the Cleave %d soldier(s) stood (%s); Death marked in-proc on %s", #alive,
      table.concat(alive, ","), table.concat(divineKills, ",")))
    H.assertEq(#alive >= 2, true, "two or more soldiers stood at the Cleave (Cyan only Defended before it)")
    table.sort(divineKills)
    H.assertEq(table.concat(divineKills, ","), table.concat(alive, ","),
      "Cleave struck every enemy: one Death mark from inside Ot6Oblivion on each soldier standing")
  end),
  H.waitFrames(120),
  H.call(function()
    for _, m in ipairs(divineKills) do
      H.assertEq(dead(m) or not present(m), true, string.format("soldier %d, unbroken, is dead", m))
    end
    H.assertEq(#takes + #breaks, 0, "no shield was taken off a killable body (Ot6CleaveStrip skips it)")
    watching = false
  end),
})

-- ============ battle 2: the commander as a boss -- the heavy cut ==========
local hp0, cut1 = nil, nil
add(bootBattle(16, "battle 2"))
add({
  H.call(function()
    local m = msPresent[1]
    H.writeByte(0x3AA1 + ent(m), H.readByte(0x3AA1 + ent(m)) | 0x04)
    H.writeWord(0x3BFC + m * 2, 30000)
    H.writeByte(SH_CUR + ent(m), 6)
    H.writeByte(BRK_TICKS + ent(m), 0)
    hp0 = mhp(m)
    H.log(string.format("[battle 2] commander m%d: $3aa1.2 SET, HP := %d, shields := 6 (declared expedient)", m, hp0))
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
    H.assertEq(#struck, 2, "two Cleaves")
    cut1 = struck[1].hp[m] - struck[2].hp[m]
    H.log(string.format("[battle 2] the first cut, alone on him and through his shields: %d", cut1))
    local t1, t2 = {}, {}
    for _, t in ipairs(takes) do
      H.assertEq(t.m, m, "Ot6TakeShields wrote only the commander's shields")
      if t.cut == 0 then t1[#t1 + 1] = tostring(t.v) else t2[#t2 + 1] = tostring(t.v) end
    end
    H.log(string.format("[battle 2] the strips: first Cleave %s; second %s; in-proc breaks %d",
      table.concat(t1, ","), table.concat(t2, ","), #breaks))
    H.assertEq(table.concat(t1, ","), "5,4,3,2", "the first Cleave took exactly four shields, 6 -> 2")
    H.assertEq(#t2 >= 1 and t2[#t2] == "0", true, "the second took what was left, down to none")
    H.assertEq(#breaks, 1, "and its last shield broke him (OT6_BROKEN_TICKS set by the strip)")
    watching = false
  end),
})

-- ============ battle 3: a boss with an add -- one Cleave strikes both =====
local boss, hp3 = nil, nil
add(bootBattle(17, "battle 3"))
add({
  H.call(function()
    H.assertEq(#msPresent >= 2, true, "battle 3 fields two or more soldiers")
    boss = msPresent[#msPresent]     -- the highest slot: the record's primary target (the lowest) is an add
    H.writeByte(0x3AA1 + ent(boss), H.readByte(0x3AA1 + ent(boss)) | 0x04)
    H.writeWord(0x3BFC + boss * 2, 30000)
    H.writeByte(SH_CUR + ent(boss), 6)
    H.writeByte(BRK_TICKS + ent(boss), 0)
    hp3 = mhp(boss)
    H.log(string.format("[battle 3] soldier m%d as the boss: $3aa1.2 SET, HP := %d, shields := 6 (declared "
      .. "expedient); the other soldier(s) killable", boss, hp3))
  end),
  H.kitBattle(cleave(1), { untilPlanDone = true, idle = "defend",
    planDone = function() return #struck >= 1 and H.readByte(0x3E9D + cyanSlot * 2) == 0 end }),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(#struck, 1, "one Cleave")
    local alive, adds = struck[1].alive, {}
    for _, m in ipairs(alive) do if m ~= boss then adds[#adds + 1] = m end end
    local dmg = struck[1].hp[boss] and (struck[1].hp[boss] - mhp(boss)) or nil
    local t1 = {}
    for _, t in ipairs(takes) do
      H.assertEq(t.m, boss, "Ot6TakeShields wrote only the boss's shields")
      t1[#t1 + 1] = tostring(t.v)
    end
    table.sort(divineKills)
    H.log(string.format("[battle 3] at the Cleave: alive %s; Death marked on %s; the boss's strip %s; cut power %s; "
      .. "the boss's HP %d -> %d (%s), battle 2's lone cut %s", table.concat(alive, ","),
      table.concat(divineKills, ","), table.concat(t1, ","), tostring(cuts[1]), hp3, mhp(boss), tostring(dmg),
      tostring(cut1)))
    H.assertEq(struck[1].hp[boss] ~= nil and #adds >= 1, true, "the boss and an add stood at the Cleave")
    H.assertEq(table.concat(divineKills, ","), table.concat(adds, ","),
      "every killable add took the Death mark, and the boss none")
    for _, m in ipairs(adds) do
      H.assertEq(dead(m) or not present(m), true, string.format("add %d is dead", m))
    end
    H.assertEq(table.concat(t1, ","), "5,4,3,2", "the boss lost exactly four shields, 6 -> 2")
    H.assertEq(cuts[1], 255, "and took the cut at power 255")
    H.assertEq(dmg ~= nil and dmg > 0, true, "the cut landed on the boss")
    H.assertEq(dmg * 4 >= cut1 * 3, true, string.format("the cut beside an add is whole, not split: %d against "
      .. "the lone cut's %d (a split halves it)", dmg, cut1))
    watching = false
  end),
})

H.run({ maxFrames = 400000 }, steps)
