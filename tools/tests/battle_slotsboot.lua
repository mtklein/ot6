-- @suite slow
-- battle_slotsboot.lua -- boost-tiered Slot on a natural boot: cold-Continue
-- the terra-returned-v1 SRAM checkpoint (party LOCKE EDGAR SABIN SETZER,
-- save-point boundary F, lettered in tools/tests/savestate_graph.py; the
-- Continue restores the party on foot at the grounded Blackjack's tile),
-- pace the plain south of Zozo into a world encounter the spins can run in
-- (fleeing the rest, budgeted from the pool's decode below), and drive real Slot
-- spins with real button presses. No pokes on either side: BP accumulates
-- through Ot6ActionEnd's own regen (battle opens at 1, +1 per unboosted
-- turn), boost is spent with real R presses, and the reels are stopped by
-- real A presses. Whatever icons they land on, the tier promises are
-- asserted as invariants of the mechanism's own cells.

-- The three spins:
--   spin 1 (0 bp): nothing is pending, the turn regens +1 bp (1 -> 2), and
--     the spin resolves whatever vanilla dealt.
--   spin 2 (0 bp): bp 2 -> 3.
--   spin 3 (3 bp, three real R presses): the reel is chosen, so whatever icon
--     reel 1 was stopped on, reels 2 and 3 must find it (whole-strip drift
--     budget), the queued result is that icon's triple, and Ot6ActionEnd
--     charges exactly 3 with no regen.  If reel 1 lands the 7 in a battle
--     whose $2f49.2 forbids joker doom, the promise is documented to fold,
--     because the battle gate outranks boost, and it is asserted per that
--     rule instead.

-- The Ot6BoostDmg exemption rides the whole run as a write-watch: the
-- multiplier's $f0-bank OT6_SCR_BIT store must never happen under cmd $0f.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local RIG, HELP1, MARK, DRIFT = 0x6179, 0x617B, 0x617C, 0x617D
local POS  = { 0x7B8C, 0x7B8D, 0x7B8E }
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }
local SLOTTIER, JOKER = 0x57BA, 0x2F49
local SETZER = 0x09

local REEL = {
  { 0,4,5,3,4,5,2,5,1,4,5,3,5,2,3,1 },
  { 0,4,1,5,3,4,1,5,4,3,2,5,4,3,2,5 },
  { 0,1,3,4,2,5,4,3,1,5,4,3,2,5,4,5 },
}
local function icon(r) return REEL[r][(H.readByte(POS[r]) >> 4) + 1] end

local slotOf, msPresent = {}, {}
local actor = nil
local function ent() return actor * 2 end
local function bp()   return H.readByte(0x3E9C + ent()) end
local function pend() return H.readByte(0x3E9D + ent()) end
local results, mulHits = {}, {}

local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end

-- wait for a character's menu; consume any other character's menu with a
-- real Defend (right swaps Fight->Def, then A)
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 30000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

-- move the command cursor onto the Slot row (verified against the live
-- cursor cell w7e890f+slot, because an unchecked down-press can miss and put
-- the A taps on Fight), confirm, and wait for the live reel state.
-- Setzer's real command list rows live at $202e+slot*12 (3 bytes per row).
local function openSlotWindow(what)
  local row = nil
  return H.repeatN(1, {
    H.call(function()
      row = nil
      for r = 0, 3 do
        if H.readByte(0x202E + slotOf[SETZER] * 12 + r * 3) == 0x0F then
          row = r
        end
      end
      H.assertEq(row ~= nil, true, "setzer's menu offers Slot")
      H.log(string.format("%s: Slot on row %d", what, row))
    end),
    H.driveUntil(function()
      return H.readByte(0x890F + slotOf[SETZER]) == row
    end, 900, {
      H.call(function()
        local cur = H.readByte(0x890F + slotOf[SETZER])
        if cur < row then H.setPad({ down = true })
        elseif cur > row then H.setPad({ up = true }) end
      end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(10),
    }, what .. ": cursor on the Slot row"),
    H.driveUntil(function()
      return H.readByte(MSTATE) == 0x08 and H.readByte(PRESS[1]) == 0
             and H.readByte(STOP[1]) == 0
    end, 1500, {
      H.call(function() H.setPad({ a = true }) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(20),
    }, what .. ": slot window open"),
    H.waitFrames(12),
  })
end

local function pressAUntilFn(predFn, what)
  return H.driveUntil(predFn, 3000, {
    H.call(function() H.setPad({ a = true }) end),
    H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
  }, what)
end
local function pressAUntil(addr, what)
  return pressAUntilFn(function() return H.readByte(addr) ~= 0 end, what)
end
local function pressCommit(what)
  return H.repeatN(1, {
    H.call(function() results = {} end),
    pressAUntilFn(function() return #results > 0 end, what),
  })
end
local function waitStop(r, what)
  return H.waitUntil(function() return H.readByte(STOP[r]) ~= 0 end, 900, what, 2)
end

-- ---- reaching a formation the spins can run in -------------------------
-- The spins need a fight that outlasts three of them (at least two bodies
-- and 600 max HP between them) and a spinner who stays awake: a sleeping
-- spinner's slot window is torn down mid-spin and the reel presses land
-- in the next ready ally's menu (measured on the v0.23 re-cut: SleepSting
-- put SETZER to sleep in spin 2, aea0cbe5).  Mind Candy's special is
-- SleepSting, so a pack holding one is fled, not fought: the property
-- here is the tier promise across three whole spins, which a slept
-- spinner cannot show.  Sleep is read from each species' special
-- (MonsterProp+31), not from a species list.
--
-- Which pool slot the next encounter deals is fixed by the save's
-- encounter counter ($1fa2/$1fa3, lib/ot6_field.lua above
-- M.worstCaseEncounters), and every re-cut of the chain hands this
-- checkpoint a different one.  On the v0.24 ROM the Blackjack's plain
-- (zone 96, grass) rolls group 10: Vulture + Iron Fist (80/256), Mind
-- Candy x4 (80/256), Iron Fist x2 + Mind Candy x2 (96/256).  Only one
-- slot in 80/256 suits, so the old budget of six draws missed it in 15%
-- of counter states, and the v0.24 re-cut's counter is one of them: its
-- draws 1-6 are slots 3,3,2,4,4,2 and its first suitable one is draw 10
-- (build/attempts/wt/slotsboot-v024/worstcase.txt, runs/new_k0_s0.log.gz).
-- The budget is now the most encounters ANY counter state needs to deal a
-- suitable slot (H.worstCaseEncounters, decoded at run time from the
-- group CheckBattleWorld rolls), and this save's own counter says where
-- in that budget the fight comes (logged; each encounter asserts the
-- word the counter chose, which pins it).
--
-- The budget holds only while every encounter rolls from the one pool.
-- The old walk turned by the clock and drifted south, into the forest
-- (group 11: the v0.24 qual's first draw was its word $0062) and once into
-- a town (runs/new1_mut_oldwalk.log.gz), so the walk now paces a stretch of
-- the disembark row whose every tile rolls one group, whatever the saved
-- position (planPace, as battle_steal's desert), and each battle asserts
-- the group its CheckBattleWorld rolled and the word the counter chose.
local MAXTRIES = 24                -- encounters built; the budget must fit
local PACE = 4                     -- tiles each way from the disembark tile
local MIN_BODIES, MIN_HP = 2, 600
local MONPROP = H.sym("MonsterProp") & 0x3FFFFF
local RNGTBL = H.sym("RNGTbl") & 0x3FFFFF
local worldGroup = nil             -- the group the last CheckBattleWorld rolled
local pace = nil                   -- { y, lo, hi, group, dir }
local draws = { n = 0 }            -- budget, pool, seq, lo, hi; n = met so far

-- MonsterProp+31, the species' special: low six bits below $20 index a
-- status (battle_main.asm @3300-@3345, route_data.special_text), and $0F
-- is status 2 bit 7, Sleep.
local function sleepSpecial(sp)
  return (H.readRomByte(MONPROP + sp * 32 + 31) & 0x3F) == 0x0F
end
local function romMaxHp(sp) return H.readRomWord(MONPROP + sp * 32 + 8) end
local function suits(bodies, hp, sleepy)
  return bodies >= MIN_BODIES and hp >= MIN_HP and not sleepy
end

local function planPace()
  local x0, y0 = H.worldX(), H.worldY()
  local function own(x) return H.worldEncounterGroup(x, y0, x, y0) end
  local g = own(x0)
  local lo, hi = x0, x0
  while lo > x0 - PACE and H.worldPassable(lo - 1, y0) and own(lo - 1) == g do
    lo = lo - 1
  end
  while hi < x0 + PACE and H.worldPassable(hi + 1, y0) and own(hi + 1) == g do
    hi = hi + 1
  end
  local zx, zy = H.worldZonePos()
  local groups = {}
  for x = lo, hi do
    for z = lo, hi do
      local gg = H.worldEncounterGroup(x, y0, z, y0)
      if gg ~= nil then groups[gg] = true end
    end
    local gg = H.worldEncounterGroup(x, y0, zx, zy)
    if gg ~= nil then groups[gg] = true end
  end
  local list = {}
  for gg in pairs(groups) do list[#list + 1] = tostring(gg) end
  table.sort(list)
  H.log(string.format("[test] pace: row %d, x %d..%d (disembark x %d, saved "
    .. "position (%d,%d)); the groups it can roll: %s", y0, lo, hi, x0, zx, zy,
    table.concat(list, ",")))
  H.assertEq(hi - lo >= 2, true, string.format("the disembark row gives a "
    .. "stretch of at least three tiles that roll group %d (x %d..%d)", g, lo, hi))
  H.assertEq(#list == 1 and list[1] == tostring(g), true, string.format(
    "every encounter on the stretch rolls group %d, whatever the saved "
    .. "position (rolls %s)", g, table.concat(list, ",")))
  pace = { y = y0, lo = lo, hi = hi, group = g, dir = "left" }
end

-- The pool's slots judged from the ROM, the budget over every counter
-- state, and this save's own coming slots: lo is the first encounter whose
-- slot CAN deal a suitable formation, hi the first whose every formation
-- suits (equal unless a +rand word mixes them).
local function planDraws()
  local pool = H.encounterPool(pace.group)
  local ok, any, parts = {}, {}, {}
  for slot = 1, 4 do
    ok[slot], any[slot] = true, false
    local names = {}
    for _, f in ipairs(pool[slot].formations) do
      local hp, sleepy = 0, false
      for _, sp in ipairs(f.species) do
        hp = hp + romMaxHp(sp)
        sleepy = sleepy or sleepSpecial(sp)
      end
      f.suits = suits(#f.species, hp, sleepy)
      ok[slot] = ok[slot] and f.suits
      any[slot] = any[slot] or f.suits
      local sp = {}
      for _, s in ipairs(f.species) do sp[#sp + 1] = string.format("%03X", s) end
      names[#names + 1] = string.format("%d [%s] %d HP%s", f.id,
        table.concat(sp, " "), hp, sleepy and " sleep" or "")
    end
    parts[#parts + 1] = string.format("slot %d (%d/256, $%04X) %s%s", slot,
      pool[slot].odds, pool[slot].word, table.concat(names, ", "),
      ok[slot] and " SUITS" or "")
  end
  local worst, hist = H.worstCaseEncounters(function()
    return function(slot) return ok[slot] end
  end)
  H.log(string.format("[test] budget: group %d: %s -- the worst of the 65536 "
    .. "encounter-counter states needs %d encounter(s); %.1f%% need no more "
    .. "than 6", pace.group, table.concat(parts, "; "), worst,
    100 * H.encounterShare(hist, 6)))
  H.assertEq(worst <= MAXTRIES, true, string.format("group %d deals a "
    .. "suitable formation within the %d encounters built (worst state: %d)",
    pace.group, MAXTRIES, worst))
  local a, b = H.readByte(0x1FA2), H.readByte(0x1FA3)
  local seq, lo, hi = {}, nil, nil
  for n = 1, MAXTRIES do
    a = (a + 1) & 0xFF                       -- UpdateBattleGrpRng
    if a == 0 then b = (b + 0x17) & 0xFF end
    seq[n] = H.encounterSlot((H.readRomByte(RNGTBL + a) + b) & 0xFF)
    if lo == nil and any[seq[n]] then lo = n end
    if hi == nil and ok[seq[n]] then hi = n end
  end
  draws = { budget = worst, pool = pool, seq = seq, lo = lo, hi = hi, n = 0 }
  H.log(string.format("[test] this save's counter ($1fa2=$%02X $1fa3=$%02X) "
    .. "deals slots %s: a suitable formation at encounter %s",
    H.readByte(0x1FA2), H.readByte(0x1FA3), table.concat(seq, ","),
    lo == hi and tostring(lo) or (tostring(lo) .. ".." .. tostring(hi))))
end

-- one walk until an encounter opens, pacing the stretch
local function paceWalk(tag)
  return H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then
        H.setPad({}); return
      end
      if H.worldAligned() then
        local x = H.worldX()
        if x <= pace.lo then pace.dir = "right"
        elseif x >= pace.hi then pace.dir = "left" end
      end
      H.setPad({ [pace.dir] = true })
    end),
  }, tag)
end

local surveyStep = H.call(function()
  draws.n = draws.n + 1
  local n, slot = draws.n, draws.seq[draws.n]
  local e = draws.pool[slot]
  H.assertEq(worldGroup, pace.group, string.format("encounter %d was dealt "
    .. "by group %d, the pool its budget was decoded from", n, pace.group))
  H.assertEq(H.readWord(0x11E0), e.word, string.format("encounter %d dealt "
    .. "slot %d's word, as the save's counter said", n, slot))
  msPresent = {}
  for m = 0, 5 do
    if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
      msPresent[#msPresent + 1] = m
    end
  end
  local mhp = 0
  for _, m in ipairs(msPresent) do mhp = mhp + H.readWord(0x3BFC + m * 2) end
  H.vars.mhpTotal = mhp
  local live, sleepy = {}, false
  for _, s in ipairs(H.formationSpecies()) do
    live[#live + 1] = s.species
    sleepy = sleepy or sleepSpecial(s.species)
  end
  table.sort(live)
  H.vars.suitable = suits(#msPresent, mhp, sleepy)
  -- the live formation is one of the slot's, and the ROM judged it the same
  local romSuits = nil
  for _, f in ipairs(e.formations) do
    local sp = {}
    for _, s in ipairs(f.species) do sp[#sp + 1] = s end
    table.sort(sp)
    if table.concat(sp, ",") == table.concat(live, ",") then romSuits = f.suits end
  end
  H.log(string.format("draw %d: slot %d $%04X, %d bodies, %d total max HP%s -> %s",
    n, slot, e.word, #msPresent, mhp, sleepy and " (sleep-capable pack)" or "",
    H.vars.suitable and "FIGHT" or "flee"))
  H.assertEq(romSuits, H.vars.suitable, string.format("encounter %d's live "
    .. "formation is one of slot %d's, judged as the ROM's data judged it", n, slot))
end)

local function attempt(n)
  return H.cond(function() return not H.vars.suitable and n <= draws.budget end, {
    paceWalk("a real world encounter fires (draw " .. n .. ")"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle active (draw " .. n .. ")", 30),
    H.waitFrames(240),
    surveyStep,
    H.cond(function() return not H.vars.suitable end, {
      -- A pack that cannot be run from ($b1 bit 1: a pincer, which this
      -- pool's Mind Candy packs can roll; or the formation's own no-L+R
      -- bit $2f4b bit 0) is fought out through the Fight menu instead:
      -- held L+R there is "Can't run away!!" until the pack wipes the
      -- party (seed shift 1, draw 7's Mind Candy x4 under "$B1=22":
      -- build/attempts/wt/slotsboot-v024/runs/new1_k0_s1.log.gz; the old
      -- suite at K=3: runs/old_k3.log.gz).
      H.cond(function()
        return (H.readByte(0x00B1) & 0x02) ~= 0 or (H.readByte(0x2F4B) & 0x01) ~= 0
      end, {
        H.call(function()
          H.log(string.format("draw %d cannot be run from ($b1=%02X $2f4b=%02X): "
            .. "fighting it out", n, H.readByte(0x00B1), H.readByte(0x2F4B)))
        end),
        H.fightBattleByMenu(30000),
      }, {
        H.fleeBattle(9000),
      }),
      H.waitUntil(function()
        return H.worldMode() and H.worldHasControl()
      end, 3000, "back on the plain after draw " .. n, 10),
      H.waitFrames(30),
      -- field care after every battle, fled or fought, as a player walks
      -- into the next one (docs/guidelines.md, "Heal outside battles")
      H.careStop("care after draw " .. n),
    }, {}),
  }, {})
end

H.run({ maxFrames = 400000 }, {
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3), using the
  -- probe_mp_universal boot unchanged
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("terra-returned-v1") end),

  -- disembark guard
  (function()
    local ph, ph2 = 0, 0
    return H.driveUntil(function()
      ph = ph + 1
      return onFoot() and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),

  H.waitUntil(function() return H.worldSettled() end, 1500,
    "the world map settled", 5),
  H.call(function()
    local check = H.sym("CheckBattleWorld")
    emu.addMemoryCallback(function() worldGroup = H.worldCheckGroup() end,
      emu.callbackType.exec, check, check)
    planPace()
    planDraws()
  end),
  (function()
    local steps = {}
    for n = 1, MAXTRIES do steps[#steps + 1] = attempt(n) end
    steps[#steps + 1] = H.call(function()
      H.assertEq(H.vars.suitable, true, string.format("a formation the "
        .. "spins can run in was dealt within %d encounters, the most any "
        .. "encounter-counter state needs from group %d", draws.budget,
        pace.group))
    end)
    return H.repeatN(1, steps)
  end)(),

  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    H.assertEq(slotOf[SETZER] ~= nil, true, "SETZER present")
    actor = slotOf[SETZER]
    H.log(string.format("setzer slot %d monsters={%s} joker=$%02x",
      actor, table.concat(msPresent, ","), H.readByte(JOKER)))
    -- the C1 commit write of the result index
    emu.addMemoryCallback(function(a, v)
      pcall(function()
        local s = emu.getState()
        if s["cpu.k"] == 0xC1 then results[#results + 1] = { addr = a, v = v } end
      end)
    end, emu.callbackType.write, 0x7E2BB0, 0x7E2BC9)
    -- the exemption watch: Ot6BoostDmg's multiplier parks its counter in
    -- OT6_SCR_BIT ($3ece) before multiplying, so a write from inside the proc
    -- under cmd $0f means the multiplier ran, which the exemption forbids
    -- ($3ece is shared OT6 scratch, so the pc range is load-bearing)
    local BOOSTDMG = H.sym("Ot6BoostDmg")
    emu.addMemoryCallback(function(_, v)
      -- cheap guards first: the same conjunction, reordered.  See the
      -- matching watch in battle_slots.lua for the measurement: emu.getState()
      -- serialises the machine on every call, and $3ece is shared OT6
      -- scratch written tens of thousands of times a run.
      if not (v > 0 and H.readByte(0xB5) == 0x0F) then return end
      pcall(function()
        local s = emu.getState()
        local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
        if pc >= BOOSTDMG and pc < BOOSTDMG + 0xA0 then
          mulHits[#mulHits + 1] = v
        end
      end)
    end, emu.callbackType.write, 0x7E3ECE, 0x7E3ECE)
  end),

  -- ------------------------------- spin 1: 0 bp, no boost bytes written ----
  menuFor(SETZER, "setzer menu (spin 1)"),
  H.call(function()
    H.assertEq(bp(), 1, "battle opens at 1 bp (Ot6InitBP)")
    H.assertEq(pend(), 0, "nothing pending")
  end),
  openSlotWindow("spin1"),
  pressAUntil(PRESS[1], "spin1 press1"),
  H.call(function()
    H.assertEq(H.readByte(SLOTTIER), 0, "spin1: stored tier 0")
    H.log(string.format("spin1: rig=$%02x (vanilla draw, untouched)", H.readByte(RIG)))
  end),
  waitStop(1, "spin1 reel1"), pressAUntil(PRESS[2], "spin1 press2"),
  waitStop(2, "spin1 reel2"), pressAUntil(PRESS[3], "spin1 press3"),
  waitStop(3, "spin1 reel3"),
  pressCommit("spin1 commit"),
  H.call(function()
    local i1, i2, i3 = icon(1), icon(2), icon(3)
    local want = (i1 == i2 and i2 == i3) and i1 + 1
      or ((i1 == 0 and i2 == 0 and i3 == 2) and 0 or 7)
    H.assertEq(results[#results].v, want,
      string.format("spin1: result matches the landed icons (%d,%d,%d)", i1, i2, i3))
    H.assertEq(pend(), 0, "spin1: still nothing pending at commit")
  end),
  H.driveUntil(function() return bp() == 2 end, 9000,
    { H.waitFrames(1) }, "spin1: unboosted turn regens 1 -> 2"),

  -- ------------------------------------------------ spin 2: 0 bp, bank to 3
  menuFor(SETZER, "setzer menu (spin 2)"),
  openSlotWindow("spin2"),
  pressAUntil(PRESS[1], "spin2 press1"),
  waitStop(1, "spin2 reel1"), pressAUntil(PRESS[2], "spin2 press2"),
  waitStop(2, "spin2 reel2"), pressAUntil(PRESS[3], "spin2 press3"),
  waitStop(3, "spin2 reel3"),
  pressCommit("spin2 commit"),
  H.driveUntil(function() return bp() == 3 end, 9000,
    { H.waitFrames(1) }, "spin2: bp 2 -> 3"),

  -- ------------------------------- spin 3: three real R presses, icon chosen
  menuFor(SETZER, "setzer menu (spin 3)"),
  H.waitFrames(20),
  H.repeatN(3, { H.pressButtons({ "r" }, 6), H.waitFrames(20) }),
  H.call(function()
    H.assertEq(pend(), 3, "three R presses banked pending 3 (real input)")
    H.assertEq(bp(), 3, "bp untouched until the action ends")
  end),
  openSlotWindow("spin3"),
  pressAUntil(PRESS[1], "spin3 press1"),
  H.call(function()
    H.assertEq(H.readByte(SLOTTIER), 3, "spin3: stored tier 3 at the first press")
    local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
    H.assertEq(H.readByte(RIG), want, "spin3: rig forced benevolent")
  end),
  waitStop(1, "spin3 reel1"),
  H.call(function()
    H.log(string.format("spin3: reel 1 stopped on icon %d (pos $%02x)",
      icon(1), H.readByte(POS[1])))
  end),
  pressAUntil(PRESS[2], "spin3 press2"),
  H.call(function()
    -- the chosen icon is reel 1's real stop.  In a joker-forbidden battle a
    -- timed 7 is the documented exception: no help and no bought triple.
    local chosen = icon(1)
    local gated = chosen == 0 and (H.readByte(JOKER) & 4) ~= 0
    if gated then
      H.assertEq(H.readByte(HELP1), 0xFF, "spin3: 7s stay gated ($2f49.2)")
    else
      -- (w7e617d is not asserted here: the seek decrements it live; the
      -- whole-strip budget is proven by the icon asserts below and by
      -- battle_slots' write-watch)
      H.assertEq(H.readByte(HELP1), chosen, "spin3: reel 2 seeks the chosen icon")
    end
  end),
  waitStop(2, "spin3 reel2"),
  pressAUntil(PRESS[3], "spin3 press3"),
  waitStop(3, "spin3 reel3"),
  pressCommit("spin3 commit"),
  H.call(function()
    local chosen = icon(1)
    local gated = chosen == 0 and (H.readByte(JOKER) & 4) ~= 0
    if gated then
      H.log("spin3: joker-gated 7 -- triple not bought (documented exception)")
    else
      H.assertEq(icon(2), chosen, "spin3: reel 2 landed the chosen icon")
      H.assertEq(icon(3), chosen, "spin3: reel 3 landed the chosen icon")
      H.assertEq(results[#results].v, chosen + 1,
        string.format("spin3: THE CHOSEN TRIPLE queued (icon %d -> index %d)",
          chosen, chosen + 1))
    end
    H.assertEq(pend(), 3, "spin3: the commit banked the stored tier")
    H.screenshot("slotsboot_chosen")
  end),
  H.driveUntil(function() return pend() == 0 end, 15000,
    { H.waitFrames(1) }, "spin3: the boosted action resolves"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(), 0, "spin3: 3 bp charged in full, no regen on a boosted turn")
    H.assertEq(#mulHits, 0,
      "EXEMPTION: the damage multiplier never ran under cmd $0f (natural run)")
    H.log("battle_slotsboot complete")
  end),
})
