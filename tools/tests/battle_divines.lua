-- @suite slow
-- battle_divines.lua -- the kit-8 divines whose gates are read at resolution.
--
--   tools/tests/run.sh tools/tests/battle_divines.lua
--
-- These finishers cannot be gated at command-select time (their command is in
-- RetargetCmdTbl, so the target is cleared and re-chosen at resolution), so OT6
-- gates them where the attack lands.  Each is once-per-battle via
-- OT6_DIVINE_USED ($3ECB, per-character bit).
--
-- OBLIVION (Cyan, Bushido tech 8, attack $5C).  Ot6Oblivion (hooked right
-- after ChooseTarget in CalcAttackEffect) reads the target's broken timer:
--   * Broken and killable   -> marks Death in the target's $3dd4 directly and
--     sets the once-per-battle latch.
--   * unbroken or Broken boss -> rewrites the loaded props to a Tempest hit in
--     place (power 70, Death cleared): the reduced fallback, with the latch
--     left clear.
--
-- Issue #75 conversion: everything reachable converts, and the ceiling stays.
-- The old file installed a triple-CYAN party on the magitek entry point, pinned
-- HP, MP, bp and pending, wrote Broken, boss and stop states onto guards, and
-- poked the latch and both cursors.  It now boots cyan_defence, the
-- input-driven Doma interlude savestate: a real solo Cyan (L11, katana, his
-- own record) on map 120, surrounded by the map's own battle-43 grinding
-- soldiers (2x species $001, 100 hp, 2 shields, weak $03, which his slash
-- chips) and the battle-46 commander (species $14E, 456 hp, 3 shields, weak
-- $01, also chippable).
-- Measured 2026-08-10, this file's recon:
--   * CYAN is battle slot 1, opens at 1 bp, real MP 67, real techs 2
--     ($1cf7=03; submenu rows enumerate $55/$56 and row 2 is EMPTY);
--   * his front-row Fight would kill a 100-hp soldier before its 2-shield
--     gauge breaks, so Cyan fights from the back row (H.setRows through the
--     real Order screen), the same weaker-weapon play battle_assassinate
--     uses;
--   * every bank is earned: battle opens at 1 bp, each unboosted Fight
--     regens +1 (Ot6ActionEnd), and picking submenu row 2 spends the banked
--     3, with no pend or bp pins anywhere;
--   * targets break by real chipping (each landed slash removes 1 shield).  The
--     commander hosts every resolution arm: his 456 hp survives the 3-chip
--     break (~50 per back-row slash, measured) where a 100-hp soldier dies
--     exactly on its breaking hit (measured: both soldiers hit 0 hp with
--     brk finally nonzero, ending the battle before any cast), and his
--     solo formation leaves the resolution-time retarget only one body;
--   * the engine's own latch edges are asserted where play can reach them:
--     the kill sets the latch (battle 2) and the next battle's fresh open
--     enumerates Oblivion again (battle 3); no poke produces those
--     two readings;
--   * kills are checked against the mechanism: a pc-gated write watch counts
--     Death marks written from inside Ot6Oblivion (battle_assassinate's
--     idiom), so a fallback that damage-kills cannot be mistaken for a divine.
--
-- Labeled isolation arm (issue #75, owner learn-ceiling ruling
-- 2026-08-10): the ceiling writes stay.
-- Oblivion is Bushido tech 8: L68 Cyan, 99 MP (#57).  The input-driven chain's
-- Cyan is L11 with 67 max MP, and the ruling keeps it that way, with no
-- leveled-fixture grind tier.  So every battle below stages the ceiling in
-- one labeled block: KNOWN ($2020) := 7 so the window can enumerate the
-- divine, and MP := 999 so the 99-MP cast is not refused.  The boss-gate
-- negative additionally sets the target's $3aa1 bit 2, the bit a boss
-- carries, because no generated battle fields a death-protected body beside
-- Cyan (the commander reads aa1=$01, measured).  And the latch-driven
-- enumeration (row 2 falls to Tempest $5b while the latch is set) keeps the
-- old latch pokes, inside battle 1's staging: the only setter in normal play
-- is the kill, the kill can only land on the commander, and killing the solo
-- commander ends the battle before the window could reopen, so the
-- set-side reading cannot be produced by play at this fixture.  These writes
-- may never produce fixtures; they convert organically as the project's
-- areas reach the levels where tech 8 is real play.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/cyan_defence.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT, ST_SUB = 0x05, 0x38, 0x30
local KNOWN = 0x2020
local ITEMLIST = 0x4005
local DIVINE_USED = 0x3ECB
local CYAN = 0x02

local function ent(m) return 8 + m * 2 end
local function sh(m) return H.readByte(0x3E38 + ent(m)) end
local function brk(m) return H.readByte(0x3E88 + ent(m)) end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return H.readByte(0x3AA8 + m * 2) % 2 == 1 end
local function dead(m) return H.readByte(0x3EE4 + ent(m)) & 0x80 ~= 0 end

local cyanSlot, msPresent = nil, {}
local function bp() return H.readByte(0x3E9C + cyanSlot * 2) end
local function pend() return H.readByte(0x3E9D + cyanSlot * 2) end
local function latchSet() return (H.readByte(DIVINE_USED) & (1 << cyanSlot)) ~= 0 end
local function inWindow() return H.readByte(MSTATE) == ST_SUB end
local function rowId(r) return H.readByte(ITEMLIST + r * 6) end

-- ---- the in-proc kill watch (battle_assassinate's idiom) ----------------
local OBLIV = H.sym("Ot6Oblivion")
local divineKills = {}
local watching = false
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  pcall(function()
    local s = emu.getState()
    local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
    if pc >= OBLIV and pc < OBLIV + 0x100 then
      divineKills[#divineKills + 1] = ((addr - 0x7E0000 - 0x3DD4) - 8) // 2
    end
  end)
end, emu.callbackType.write, 0x7E3DD4 + 8, 0x7E3DD4 + 0x13)

-- the labeled isolation arm's ceiling block (see header)
local function stageCeiling(tag)
  H.writeWord(KNOWN, 7)                       -- tech-8 window (L68 by play)
  H.writeWord(0x3C08 + cyanSlot * 2, 999)     -- Oblivion costs 99 (#57)
  H.writeWord(0x3C30 + cyanSlot * 2, 999)
  H.log("[" .. tag .. "] ceiling staged: KNOWN:=7, MP:=999 (labeled arm)")
end

-- ---- shared drive helpers ----------------------------------------------
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

-- one real Fight per call window; wantTarget(m) picks the body to steer the
-- target cursor onto (nil = confirm whatever is up)
local function fightPulse(wantTarget)
  if H.readByte(MENU) == 0 then
    H.setPad(H.frame % 8 < 4 and { a = true } or {})
    return
  end
  local st = H.readByte(MSTATE)
  local btn
  if st == ST_CMD then
    local cur = H.readByte(0x890F + cyanSlot) & 3
    btn = (cur == 0) and "a" or "up"
  elseif st == ST_TGT then
    local want = wantTarget and wantTarget()
    local mask = H.readByte(0x7B7E)
    if want == nil or mask == (1 << want) then btn = "a"
    elseif mask == 0 then btn = "left"
    else btn = "down" end
  elseif st == ST_SUB then
    btn = "b"                     -- not casting in a bank phase
  else
    btn = nil
  end
  H.setPad(btn and { [btn] = true } or {})
end

-- drive real Fights until pred; steer per wantTarget
local function bankUntil(pred, wantTarget, budget, what)
  local ph = 0
  return H.driveUntil(pred, budget, {
    H.call(function()
      ph = ph + 1
      if ph % 8 < 4 then fightPulse(wantTarget) else H.setPad({}) end
    end),
    H.waitFrames(2),
  }, what)
end

-- open the swdtech submenu from the command window
local function openWindow(what)
  local ph = 0
  return H.driveUntil(inWindow, 3000, {
    H.call(function()
      ph = ph + 1
      if ph % 8 >= 4 then H.setPad({}); return end
      if H.readByte(MENU) == 0 then H.setPad({ a = true }); return end
      local st = H.readByte(MSTATE)
      if st == ST_CMD then
        local cur = H.readByte(0x890F + cyanSlot) & 3
        H.setPad(cur == 1 and { a = true } or
                 { [cur < 1 and "down" or "up"] = true })
      else
        H.setPad({ b = true })
      end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(9),
  }, what)
end
local function closeWindow(what)
  return H.driveUntil(function() return not inWindow() end, 500, {
    H.call(function() H.setPad({ b = true }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, what or "the submenu closes")
end

-- steer the submenu cursor to row 2 (boost 3) with the d-pad; the cells
-- are read, never written (scroll $895f, col $8963, row $8967)
local function castRow2(what)
  return {
    H.driveUntil(function()
      return inWindow()
         and H.readByte(0x895F + cyanSlot) + H.readByte(0x8967 + cyanSlot) == 2
         and H.readByte(0x8963 + cyanSlot) == 0
    end, 1500, {
      H.call(function()
        if not inWindow() then H.setPad({}); return end
        local row = H.readByte(0x895F + cyanSlot) + H.readByte(0x8967 + cyanSlot)
        if H.readByte(0x8963 + cyanSlot) > 0 then H.setPad({ left = true })
        elseif row < 2 then H.setPad({ down = true })
        elseif row > 2 then H.setPad({ up = true })
        else H.setPad({}) end
      end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(8),
    }, what .. ": cursor steered to row 2 (d-pad, no pokes)"),
    H.driveUntil(function() return not inWindow() end, 900, {
      H.call(function() H.setPad({ a = true }) end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(14),
    }, what .. ": Oblivion latched from row 2"),
  }
end

-- ride the queued cast to resolution: A on any non-window menu
local function resolveCast(what)
  local ph = 0
  return H.driveUntil(function() return pend() == 0 end, 12000, {
    H.call(function()
      ph = ph + 1
      if ph % 8 >= 4 then H.setPad({}); return end
      if H.readByte(MENU) ~= 0 and not inWindow() then
        local st = H.readByte(MSTATE)
        -- #90: was `st == ST_TGT and {a} or {a}` -- A in EVERY state,
        -- the battle_levelup race.  A only where it means "confirm the
        -- target"; nothing in transitional $01; B elsewhere.
        H.setPad(st == ST_TGT and { a = true }
                 or (st == 0x01 and {} or { b = true }))
      else
        H.setPad({})
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, what)
end

-- boot one fresh commander/soldier battle from the fixture; obj 16 is the
-- commander (battle 46), objs 17+ the battle-43 soldiers (gen_sabin_camp's
-- object survey; positions logged by the recon)
local function bootBattle(obj, what)
  return {
    H.waitFrames(20),
    H.loadState(STATE),
    H.waitFrames(30),
    -- CYAN to the back row through the real Order screen; see the header
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
        parts[#parts + 1] = string.format("m%d hp=%d sh=%d brk=%02x", m,
          mhp(m), sh(m), brk(m))
      end
      H.log(string.format("[%s] cyan slot %d bp=%d latch=%02x | %s", what,
        cyanSlot, bp(), H.readByte(DIVINE_USED), table.concat(parts, " | ")))
      H.assertEq(latchSet(), false, what .. ": divine latch clear at start")
      divineKills = {}
      watching = true
    end),
  }
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- ============ battle 1: selection and the unbroken fallback (commander) ====
add(bootBattle(16, "battle 1"))
add({
  -- bank 3 bp with two real Fights; each chips one shield, 3 -> 1, so the
  -- commander stays unbroken
  bankUntil(function() return bp() >= 3 end, nil, 20000,
    "battle 1: two real Fights bank 3 bp (and leave the gauge unbroken)"),
  H.call(function()
    local m = msPresent[1]
    H.assertEq(brk(m), 0, "the commander is still UNBROKEN after the bank")
    H.assertEq(sh(m) > 0, true, "shields remain on the gauge")
    stageCeiling("battle 1")
  end),
  openWindow("battle 1: swdtech submenu opens"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(rowId(2), 0x5C,
      "latch CLEAR: row 2 (boost 3) enumerates Oblivion ($5c)")
    H.screenshot("divine_oblivion_selectable")
  end),
  -- labeled arm: the latch-driven enumeration (see header).  The set
  -- side cannot be produced by play here, because the only setter in normal
  -- play kills the solo commander and ends the battle, so the latch bit is
  -- poked set, read, and poked clear again; the poke never leaves this block.
  closeWindow("battle 1: close, then set the latch and reopen"),
  H.call(function()
    H.writeByte(DIVINE_USED, H.readByte(DIVINE_USED) | (1 << cyanSlot))
  end),
  openWindow("battle 1: reopen with the latch SET (labeled poke)"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(rowId(2), 0x5B, "latch SET: row 2 falls back to Tempest ($5b)")
  end),
  closeWindow("battle 1: close, then clear the latch and reopen"),
  H.call(function()
    H.writeByte(DIVINE_USED,
      H.readByte(DIVINE_USED) & (~(1 << cyanSlot) & 0xFF))
  end),
  openWindow("battle 1: reopen with the latch CLEAR again"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(rowId(2), 0x5C, "latch cleared: Oblivion ($5c) returns")
    H.assertEq(latchSet(), false, "latch left clear for the fallback cast")
  end),
})
add(castRow2("battle 1"))
add({
  resolveCast("battle 1: the unbroken action resolves"),
  H.waitFrames(50),
  H.call(function()
    local m = msPresent[1]
    H.log(string.format("[battle 1] after: hp=%d dead=%s present=%s "
      .. "inProcKills=%d latch=%02x", mhp(m), tostring(dead(m)),
      tostring(present(m)), #divineKills, H.readByte(DIVINE_USED)))
    H.assertEq(#divineKills, 0,
      "the UNBROKEN target drew NO in-proc Death mark -- the gate "
      .. "surgeried the hit to Tempest")
    H.assertEq(dead(m), false, "the unbroken commander took no Death")
    H.assertEq(present(m), true, "and is still present")
    H.assertEq(latchSet(), false, "the divine latch stays CLEAR on a fallback")
    watching = false
    H.screenshot("divine_oblivion_fallback")
  end),
})

-- ============ battle 2: the broken kill (the commander, broken by play) ====
add(bootBattle(16, "battle 2"))
add({
  -- break the commander by real chipping: 3 shields, ~50 per back-row
  -- slash, 456 hp, so he is Broken at ~300 hp and still alive.  The three
  -- unboosted Fights also bank 1+3 = 4 bp.
  bankUntil(function()
    local m = msPresent[1]
    return brk(m) ~= 0 and bp() >= 3
  end, nil, 30000,
    "battle 2: the commander broken by real chips, 3+ bp banked"),
  H.call(function()
    local m = msPresent[1]
    H.log(string.format("[battle 2] body %d hp=%d sh=%d brk=%02x", m,
      mhp(m), sh(m), brk(m)))
    H.assertEq(mhp(m) > 0, true, "and he is alive to be assassinated")
    stageCeiling("battle 2")
  end),
  openWindow("battle 2: swdtech submenu opens"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(rowId(2), 0x5C, "Oblivion ($5c) on row 2 (latch clear)")
  end),
})
add(castRow2("battle 2"))
add({
  resolveCast("battle 2: the broken-target action resolves"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[battle 2] after: inProcKills=%d latch=%02x",
      #divineKills, H.readByte(DIVINE_USED)))
    H.assertEq(#divineKills, 1,
      "Oblivion inflicted its guaranteed Death on the Broken commander -- "
      .. "one in-proc mark, no more")
    H.assertEq(dead(divineKills[1]), true,
      "and that body is dead (the engine's own resolution)")
    H.assertEq(latchSet(), true,
      "the engine SET the divine latch on the kill -- the set-side "
      .. "latch edge (battle 1's poked pair covers only the enumeration)")
    watching = false
    H.screenshot("divine_oblivion_kill")
  end),
})

-- ==== battle 3: the boss refusal, broken by play, with the one written bit =
add(bootBattle(16, "battle 3"))
add({
  -- chip the commander to Broken for real: 3 shields, back-row slashes
  bankUntil(function()
    local m = msPresent[1]
    return brk(m) ~= 0 and bp() >= 3
  end, nil, 30000,
    "battle 3: the commander broken by real chips, 3+ bp banked"),
  H.call(function()
    local m = msPresent[1]
    H.assertEq(brk(m) ~= 0, true, "commander Broken by play")
    -- the labeled arm's boss bit (see header): no generated battle fields
    -- a death-protected body beside Cyan, so the one bit is written on the
    -- commander that real play broke
    H.writeByte(0x3AA1 + ent(m), H.readByte(0x3AA1 + ent(m)) | 0x04)
    stageCeiling("battle 3")
    H.log(string.format("[battle 3] body %d broken (brk=%02x), $3aa1.2 SET",
      m, brk(m)))
  end),
  openWindow("battle 3: swdtech submenu opens"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(rowId(2), 0x5C,
      "fresh battle: the latch is battle-scoped, Oblivion ($5c) returns "
      .. "with no poke ever having touched $3ecb")
  end),
})
add(castRow2("battle 3"))
add({
  resolveCast("battle 3: the broken-boss action resolves"),
  H.waitFrames(50),
  H.call(function()
    local m = msPresent[1]
    H.log(string.format("[battle 3] after: hp=%d dead=%s inProcKills=%d "
      .. "latch=%02x", mhp(m), tostring(dead(m)), #divineKills,
      H.readByte(DIVINE_USED)))
    H.assertEq(#divineKills, 0,
      "a Broken BOSS drew NO in-proc Death mark -- the gate withholds the "
      .. "kill from a death-protected body")
    H.assertEq(dead(m), false, "the boss took no Death")
    H.assertEq(latchSet(), false, "and no divine was spent on it")
    watching = false
    H.screenshot("divine_oblivion_boss")
  end),
})

H.run({ maxFrames = 300000 }, steps)
