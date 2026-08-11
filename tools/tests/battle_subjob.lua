-- @suite slow savestate=n024_entry
-- battle_subjob.lua -- M5 espers-as-sub-jobs, the FORK-INDEPENDENT core: an
-- equipped esper GRANTS its spells to the in-battle Magic list (additively), the
-- grant never teaches permanently, and level-up esper stat bonuses are gone.
--
-- Issue #75 conversion.  The old fixture poked char 0's equipped-esper byte
-- ($161e) in the field, rewrote command lists, muddled the caster for
-- menu-less casts, pinned guards, and handed bp/pending/MP.  On
-- n024_entry the inputs are real: RAMUH is genuinely owned ($1A69 bit 0,
-- gifted at Zozo and asserted in the alcove savestate), and it is equipped on
-- CELES through the REAL FIELD MENU (battle_magicite.lua's measured route:
-- X -> Skills -> character -> Espers -> stone -> detail -> A).  Ramuh is
-- authored to base-tier Bolt ($02) + Rasp ($1a); Celes innately knows
-- NEITHER (scenario A reads her real no-esper list as the control), so any
-- Bolt/Rasp in her list is the grant's doing.  The fold cast goes through
-- her LIVE menu -- real R edges for the pending, real cursor walk to the
-- granted Bolt -- against the fixture's own boss, NUMBER 024.
--
-- Two hooks make this work, MEASURED necessary (probe_subjob): the in-battle
-- Magic list is COMPACTED to the union of party-known spells, so a borrowed
-- spell nobody knows has no slot at all -- Ot6UnionEspers (ot6.asm) seeds the
-- union with equipped espers' spells, and Ot6EsperSpellKnown then keeps each
-- one only for its esper's holder.
--
-- SCENARIOS (independent loads; CONTRIBUTING: a quiet test is not a passing
-- test, so every positive carries its negative control):
--   A NEGATIVE  no esper: Celes's list has neither Bolt nor Rasp (== vanilla).
--   B GRANT     Ramuh: Bolt AND Rasp appear; the list is A's list PLUS exactly
--               {summon, Bolt, Rasp} -- additive, innate untouched; Bolt is
--               priced at vanilla MP (no double-charge); the summon slot is
--               registered ($3344,entity).
--   C FOLD      the granted Bolt cast with 2 real BP executes as Bolt3 ($0b)
--               via the fold, and since #64 is charged BOLT3's own 53 MP --
--               which also proves the untaught tier is CASTABLE and now a
--               purchase.  Her real 106-MP pool pays it; the bank is earned
--               (Ot6InitBP's 1 + one real item turn), the pending is two real
--               R edges, the cast a real cursor walk.  The charge is EXACT
--               (== 53): with the muddle apparatus gone there is no
--               trailing-cast noise, so the old >= bound sharpens.
--   D DELETIONS win a level-up with Ramuh: no esper stat bonus (Stamina AND
--               Mag.Pwr both flat in the persistent record -- vanilla Ramuh's
--               STAMINA_1 would bump stamina) and no spell learned (Bolt/Rasp
--               stay unlearned).
--
--               *** LABELED ISOLATION ARM (owner ruling 2026-08-10, the
--               waiver-burndown plan names this exact arm). ***  No fixture
--               sits one real fight short of a level, the n024 maps are
--               measured encounter-free, and winning the boss by play is a whole
--               generator's job (gen_esper_tubes).  So this arm keeps two
--               memory-hack stagings, said loudly: the XP pin (one threshold
--               over, so the next win levels) and the lib's clearBattle win.
--               The ASSERTIONS still read only persistent-record facts the
--               level-up wrote.  Convert organically when a near-threshold
--               fixture exists.
--
-- #62 strengthened D's stat half: Ramuh's while-worn row moves TWO stats
-- (+4 stamina, +2 mag.pwr) and NEITHER may ever reach the $16xx record, so D
-- reads both cells -- two independent windows onto the same rule.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/n024_entry.mss.lua"

local BOLT, BOLT3, RASP = 0x02, 0x0b, 0x1a
local BOLT3_MP = 53
local RAMUH = 0x00                       -- esper index (GenjuProp order)

-- CELES's roster record (roster 6; measured on this fixture)
local CBASE = 0x1600 + 37 * 6
local ESPERB = CBASE + 0x1e              -- equipped esper
local STAMB  = CBASE + 0x1c
local MAGPB  = CBASE + 0x1d
local LEVELB = CBASE + 0x08
local XPB    = CBASE + 0x11
local KNOWNB = 0x1a6e + 54 * 6           -- her learned table ($ff = learned)

-- field menu route (battle_magicite's measured constants)
local ZMENUSTATE, ZCURSOR, GENJULIST = 0x26, 0x4b, 0x9d89
local MST_MAIN, MST_CHAR, MST_SKILLS, MST_LIST, MST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local function mst() return H.readByte(ZMENUSTATE) end

-- battle menu
local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_MAGIC, ST_ESPER, ST_TGT, ST_TRANS =
  0x05, 0x0A, 0x0E, 0x16, 0x38, 0x01
local CMD_MAGIC, CMD_ITEM = 0x02, 0x01
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
local LISTS = { [0] = 0x208e, [1] = 0x21ca, [2] = 0x2306, [3] = 0x2442 }
local TONIC, POTION = 0xE8, 0xE9

local locke, celes
local function mp(slot) return H.readWord(0x3C08 + slot*2) end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
local function bp(slot) return H.readByte(0x3E9C + slot*2) end
local function pend(slot) return H.readByte(0x3E9D + slot*2) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function recOf(slot, id)
  local L = LISTS[slot]
  for n = 1, 78 do
    if H.readByte(L + n*4) == id then return n end
  end
  return nil
end
local function listSet(slot)
  local set = {}
  for n = 0, 78 do
    local id = H.readByte(LISTS[slot] + n * 4)
    if id ~= 0xff then set[#set + 1] = id end
  end
  return set
end
local function has(set, id)
  for _, v in ipairs(set) do if v == id then return true end end
  return false
end
local function fmt(set)
  local s = {}
  for _, v in ipairs(set) do s[#s + 1] = string.format("%02x", v) end
  return table.concat(s, " ")
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end

-- vanilla XP thresholds (battle_levelup): 8*sum(LevelUpExp[0..L-1]) to leave L
local LEVELUP_EXP = { 4,8,14,24,34,48,62,79, 99,120,143,169,195,224,257,289 }
local function neededXp(L)
  local s = 0
  for i = 1, L do s = s + LEVELUP_EXP[i] end
  return 8 * s
end

-- ------------------------------------------------ real field esper equip --
-- battle_magicite.lua's measured drive, verbatim shape
local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return mst() == MST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if ph >= 4 then H.setPad({}); return end
      local target
      for r = 0, 26 do
        if H.readByte(GENJULIST + r) == idx then target = r; break end
      end
      if not target then H.setPad({}); return end
      local row = H.readByte(ZCURSOR)
      local d = target - row
      if d % 2 ~= 0 then
        if row % 2 == 0 then
          H.setPad(row >= 26 and { up = true } or { right = true })
        else
          H.setPad({ left = true })
        end
      else
        H.setPad(d > 0 and { down = true } or { up = true })
      end
    end),
    H.waitFrames(1),
  }, what)
end
local function equipRamuhOnCeles(tag)
  return H.repeatN(1, {
    H.driveUntil(function() return mst() == MST_MAIN end, 1200, {
      H.pressButtons({ "x" }, 4), H.waitFrames(30),
    }, tag .. ": main menu"),
    H.waitFrames(20),
    H.pressButtons({ "down" }, 3), H.waitFrames(12),   -- Item -> Skills
    H.driveUntil(function() return mst() == MST_CHAR end, 600, {
      H.pressButtons({ "a" }, 3), H.waitFrames(16),
    }, tag .. ": char select"),
    H.waitFrames(10),
    -- menu position 3 = CELES (0=EDGAR 1=SABIN 2=LOCKE, measured)
    H.pressButtons({ "down" }, 3), H.waitFrames(12),
    H.pressButtons({ "down" }, 3), H.waitFrames(12),
    H.pressButtons({ "down" }, 3), H.waitFrames(12),
    H.driveUntil(function() return mst() == MST_SKILLS end, 600, {
      H.pressButtons({ "a" }, 3), H.waitFrames(16),
    }, tag .. ": skills"),
    H.driveUntil(function()
      return mst() == MST_SKILLS and H.readByte(ZCURSOR) == 0
    end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
      tag .. ": cursor to Espers"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return mst() == MST_LIST end, 300,
      tag .. ": esper list", 5),
    listSeek(RAMUH, tag .. ": cursor to RAMUH"),
    H.waitFrames(20),
    H.driveUntil(function() return mst() == MST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, tag .. ": detail page"),
    H.waitFrames(20),
    H.pressButtons({ "a" }, 3),
    H.waitFrames(20),
    H.driveUntil(function() return H.hasControl() and not H.dialogWaiting() end,
      1200, { H.pressButtons({ "b" }, 3), H.waitFrames(20) },
      tag .. ": menu closed"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.readByte(ESPERB), RAMUH,
        tag .. ": the REAL equip landed in her roster record")
    end),
  })
end

-- ------------------------------------------------------ the battle drive --
local spells, mpWrites = {}, {}
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end
local mf = 0
local celesMode = "defer"                -- "defer"|"cast"
local wantPend, castRec = 0, nil
local tgtLatch, tgtAge, tgtPress
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  if H.readByte(MSTATE) == ST_TGT then
    local m = H.readByte(0x7B7D)
    if m ~= 0 then
      if m == tgtLatch then tgtAge = (tgtAge or 0) + 1
      else tgtLatch, tgtAge = m, 1 end
    end
  else
    tgtLatch, tgtAge, tgtPress = nil, 0, 0
  end
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act == locke then                          -- threshold medic
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 70 then hurt = true end
    end
    if st == ST_CMD and not hurt then btn = "x"
    elseif st == ST_CMD then
      local want = cmdRowOf(locke, CMD_ITEM)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + locke) + H.readByte(0x894F + locke)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT then
      local worst, wpct = nil, 101
      for s = 0, 3 do
        local h, m = hp(s), H.readWord(0x3C1C + s*2)
        if h > 0 and m > 0 then
          local pct = h * 100 // m
          if pct < wpct then worst, wpct = s, pct end
        end
      end
      if worst == nil or tgtLatch == (1 << worst) and (tgtAge or 0) >= 4 then
        btn = "a"
      else
        local dirs = { "down", "up", "left", "right" }
        if (mf - 1) % 8 == 0 then tgtPress = (tgtPress or 0) + 1 end
        btn = dirs[(((tgtPress or 1) - 1) // 2) % 4 + 1]
      end
    else btn = "b" end
  elseif act == celes then
    if celesMode == "defer" then
      btn = (st == ST_CMD) and "x" or "b"
    elseif celesMode == "item" then              -- one real bank turn
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_ITEM)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_ITEM then
        local want = bagIdxOf({ TONIC, POTION })
        if want == nil then btn = "b"
        else
          local cur = H.readByte(0x8947 + celes) + H.readByte(0x894F + celes)
          if cur < want then btn = "down"
          elseif cur > want then btn = "up"
          else btn = "a" end
        end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    else                                         -- "cast": boost, walk, cast
      if st == ST_CMD then
        if pend(celes) < wantPend then btn = "r"
        else
          local want = cmdRowOf(celes, CMD_MAGIC)
          local cur = H.readByte(CMDROW + celes) & 3
          if cur == want then btn = "a"
          else btn = (cur < want) and "down" or "up" end
        end
      elseif st == ST_MAGIC then
        local idx = castRec - 1
        local wr, wc = idx // 2, idx % 2
        local ar = H.readByte(MSCROLL + celes) + H.readByte(MROW + celes)
        local col = H.readByte(MCOL + celes)
        if ar < wr then btn = "down"
        elseif ar > wr then btn = "up"
        elseif col < wc then btn = "right"
        elseif col > wc then btn = "left"
        else btn = "a" end
      elseif st == ST_ESPER then btn = "b"
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    end
  else
    btn = (st == ST_CMD) and "x" or "b"
  end
  return btn and { [btn] = true } or {}
end
local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(function() H.setPad(decide()) end),
  }, tag)
end

local function enterBoss(tag)
  return H.repeatN(1, {
    H.hold({ "up" }), H.waitFrames(4), H.release(), H.waitFrames(10),
    H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(20),
    }, tag .. ": battle 72 opens"),
    H.waitUntil(function() return H.battleActive() end, 900,
      tag .. ": battle active", 30),
    H.waitFrames(120),
    H.call(function()
      locke, celes = nil, nil
      for slot = 0, 3 do
        local id = H.readByte(0x3ED8 + slot*2)
        if id == 0x01 then locke = slot end
        if id == 0x06 then celes = slot end
      end
      H.assertEq(locke ~= nil and celes ~= nil, true,
        tag .. ": LOCKE and CELES really fight this")
      spells, mpWrites = {}, {}
    end),
  })
end

local baseSet
local R = {}

H.run({ maxFrames = 150000 }, {
  ----------------------------------------------------------------- A: NEGATIVE --
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(0x1A69) & 0x01, 0x01,
      "RAMUH is genuinely owned ($1A69 bit 0, the Zozo gift)")
    H.assertEq(H.readByte(ESPERB), 0xff, "Celes starts with no esper (control)")
  end),
  enterBoss("A"),
  H.call(function()
    baseSet = listSet(celes)
    H.log("[A] no-esper celes list: " .. fmt(baseSet))
    H.assertEq(has(baseSet, BOLT), false, "no esper: Bolt absent (vanilla)")
    H.assertEq(has(baseSet, RASP), false, "no esper: Rasp absent (vanilla)")
  end),

  ------------------------------------------------------------- B + C: one boot --
  H.loadState(STATE),
  H.waitFrames(60),
  equipRamuhOnCeles("B"),
  enterBoss("B"),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
    emu.addMemoryCallback(function(_, v) mpWrites[#mpWrites + 1] = v end,
      emu.callbackType.write, 0x7e3C08 + celes*2, 0x7e3C08 + celes*2)
    local set = listSet(celes)
    H.log("[B] Ramuh celes list: " .. fmt(set))
    H.assertEq(has(set, BOLT), true, "Ramuh grants Bolt into the list")
    H.assertEq(has(set, RASP), true, "Ramuh grants Rasp into the list")
    -- MULTISET diff base->Ramuh: additive means no innate entry removed, and
    -- the only additions are Bolt, Rasp, and the esper's SUMMON slot (id =
    -- esper index 0 -- which collides with Fire's 0, hence counting).
    local function counts(t)
      local c = {}; for _, v in ipairs(t) do c[v] = (c[v] or 0) + 1 end; return c
    end
    local bc, sc = counts(baseSet), counts(set)
    for id, n in pairs(bc) do
      H.assertEq((sc[id] or 0) >= n, true,
        string.format("innate spell %02x not removed (additive, not replace)", id))
    end
    local adds = {}
    for id, n in pairs(sc) do for _ = 1, n - (bc[id] or 0) do adds[#adds + 1] = id end end
    table.sort(adds)
    H.log("[B] additions over the no-esper list: " .. fmt(adds))
    H.assertEq(#adds, 3, "Ramuh adds exactly three list entries")
    H.assertEq(adds[1], 0x00, "one addition is Ramuh's summon slot (esper index 0)")
    H.assertEq(adds[2], BOLT, "one addition is Bolt")
    H.assertEq(adds[3], RASP, "one addition is Rasp")
    -- no double-charge: the granted Bolt is priced at vanilla Bolt MP
    local cost = H.readByte(LISTS[celes] + recOf(celes, BOLT)*4 + 3)
    H.log("[B] granted Bolt list MP cost = " .. tostring(cost))
    H.assertEq(cost ~= nil and cost >= 3 and cost <= 8, true,
      "granted Bolt priced at vanilla MP (~6), not doubled or Bolt3's")
    -- summon plumbing intact: ValidateSpellList registered Ramuh's summon
    -- ($3344,entity) and the once-per-battle gate is clear at start
    H.assertEq(H.readByte(0x3344 + celes*2), RAMUH,
      "ValidateSpellList registered Ramuh's summon ($3344,entity)")
    H.assertEq(H.readWord(0x3f2e) & H.readWord(0x3018 + celes*2), 0,
      "summon not yet spent at battle start ($3f2e gate clear)")
  end),
  -- C: bank the second bp with one real item turn, then two real R edges
  -- and a real cursor walk cast the granted Bolt as a fold
  H.call(function() celesMode = "item" end),
  driveTo(function() return bp(celes) >= 2 end, 20000,
    "[C] second bp banked by a real item turn"),
  H.call(function()
    R.mp0 = mp(celes)
    H.assertEq(R.mp0 >= BOLT3_MP, true,
      "[C] her real pool pays Bolt3's 53 once")
    celesMode = "cast"; wantPend = 2; castRec = recOf(celes, BOLT)
  end),
  driveTo(function() return sawSpell(BOLT3) end, 30000,
    "[C] the granted Bolt folds to Bolt3 ($0b) at the queue"),
  H.call(function() celesMode = "defer"; wantPend = 0 end),
  H.waitFrames(300),
  H.call(function()
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("[C] $3410 sequence: " .. table.concat(ids, " "))
    local mp1 = mp(celes)
    local seen = {}
    for _, v in ipairs(mpWrites) do seen[v & 0xff] = true end
    H.log(string.format("[C] mp %d -> %d", R.mp0, mp1))
    H.assertEq(sawSpell(BOLT3), true,
      "granted Bolt at 2 real BP executed as Bolt3 ($0b) via the fold")
    H.assertEq(seen[(R.mp0 - BOLT3_MP) & 0xff], true,
      "[C] the pool was debited to exactly mp0-53 (the write watch)")
    -- #64, sharpened to equality: no muddle noise remains, so the delta IS
    -- Bolt3's own price.  This also settles the untaught-tier question in
    -- the affirmative: an esper-GRANTED Bolt still reaches Bolt3, and pays
    -- Bolt3's price for it.
    H.assertEq(R.mp0 - mp1, BOLT3_MP,
      "the folded Bolt3 was charged Bolt3's own 53 MP -- an untaught tier "
      .. "is still reachable by folding, and is now a purchase (#64)")
    H.screenshot("subjob_fold")
  end),

  ---------------------------------------------------------------- D: DELETIONS --
  -- LABELED ISOLATION ARM -- see the header.  The equip is still real; the
  -- XP pin and the lib's clearBattle win are the two memory-hack stagings
  -- the owner ruling keeps for level-up mechanism decodes.
  H.loadState(STATE),
  H.waitFrames(60),
  equipRamuhOnCeles("D"),
  enterBoss("D"),
  H.call(function()
    R.stam0 = H.readByte(STAMB)
    R.magp0 = H.readByte(MAGPB)
    R.lvl0 = H.readByte(LEVELB)
    H.assertEq(H.readByte(KNOWNB + BOLT) ~= 0xff, true,
      "Bolt unlearned before win (control)")
    H.assertEq(H.readByte(KNOWNB + RASP) ~= 0xff, true,
      "Rasp unlearned before win (control)")
    local v = neededXp(R.lvl0) + 4                -- one threshold over
    H.writeByte(XPB,     v         & 0xff)        -- ISOLATION WRITE (waived)
    H.writeByte(XPB + 1, (v >> 8)  & 0xff)
    H.writeByte(XPB + 2, (v >> 16) & 0xff)
    H.log(string.format("[D] L=%d stamina=%d mag.pwr=%d, xp pinned one level over",
      R.lvl0, R.stam0, R.magp0))
  end),
  H.clearBattle(20000),                           -- ISOLATION WIN (lib waiver)
  H.waitFrames(40),
  H.call(function()
    local lvl1 = H.readByte(LEVELB)
    local stam1 = H.readByte(STAMB)
    local magp1 = H.readByte(MAGPB)
    H.log(string.format("[D] after win: L %d->%d  stamina %d->%d  mag.pwr %d->%d",
      R.lvl0, lvl1, R.stam0, stam1, R.magp0, magp1))
    H.assertEq(lvl1 > R.lvl0, true, "leveled up (the mechanism ran)")
    H.assertEq(stam1, R.stam0, "no esper level-up stat bonus (Stamina flat)")
    H.assertEq(magp1, R.magp0,
      "the while-worn mod never reaches the record (Mag.Pwr flat)")
    H.assertEq(H.readByte(KNOWNB + BOLT) ~= 0xff, true, "Bolt not permanently learned")
    H.assertEq(H.readByte(KNOWNB + RASP) ~= 0xff, true, "Rasp not permanently learned")
    H.log("[subjob] all scenarios passed")
  end),
})
