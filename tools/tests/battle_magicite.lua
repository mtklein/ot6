-- @suite slow savestate=n024_entry
-- battle_magicite.lua -- the v0.6 Ifrit and Shiva magicite redesigns, the
-- halves battle_esperstats.lua does not reach: the ability prices their kits
-- are built on, and the summons.  Design: docs/design/magicite-ifrit-shiva.md
-- (issue #16).  battle_esperstats covers which spells and which stat; this file
-- covers what they cost and what the divine does.
--
-- Issue #75 conversion.  The old apparatus staged everything on the magitek
-- entry point: char 0's equipped-esper byte and field MP poked before the
-- drive-in, Terra's command list rewritten, allies stopped, guard HP and MP
-- pinned, the Slow-immunity words written both ways, saved-cursor pokes,
-- and $3f2e and $3204 poked for the latch A/B.  On n024_entry every input
-- is real:
--
--   * the stones are in the bag ($1A69 bits, give_genju receipts
--     from the alcove hand-off) and are equipped through the real field
--     menu: X -> Skills -> character -> Espers -> stone -> detail -> A
--     (MenuState_1e/4d, field_menu.asm:2504 and skills.asm:2641).  Ifrit
--     goes on Locke, and an equipped stone grants its kit (genju_prop.asm),
--     so his Magic row appears with Ifrit's spells; Shiva goes on Celes.
--   * the fight is Number 024 (battle 72), the fixture's own one-A-press
--     boss, and it is the species the design chose: its authored
--     allowed-status word blocks Slow (monster_prop +$16; live $3330
--     reads $FFE1, bit 2 clear, read as the experiment's control rather than
--     written), and its real 777-MP pool is the Facility-scale target the
--     Osmose reprice exists for.
--   * the 7-MP boundary is earned: Celes's real 106-MP pool is walked
--     down by real casts of her own kit (Shell 15 and Cure 5) until it reads
--     5..7, and the greys are then read off the live list.  106 = 1 (mod 5)
--     and both prices are multiples of 5, so those two alone land the pool on
--     exactly 6; no third adjuster is needed.
--   * the once-per-battle latch: the summon is offered at battle start,
--     spent during the run, and the row greys at her next real window, from
--     the natural refresh with no $3204 pokes.  The re-offer half is a second
--     battle: the fixture reloads and battle 72 re-enters, and the fresh
--     battle's init offers the row again ($3f2e read clear), which is the
--     plan's "re-summon arms become second battles".
--
-- The one thing lost against the original is the Slow-lands half of the
-- immunity pair.  No Slow-permitting enemy is reachable from this fixture
-- (maps 264/269/271/273 are measured encounter-free by the chain's own steps),
-- and the design's allowing species, Number 128, the Cranes and the blades,
-- live in later set pieces.  The refused half (species-authored immunity
-- consulted on a landed divine) is asserted here; the landing half is
-- follow-up work on a deeper fixture.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/n024_entry.mss.lua"

-- spell ids (const.inc ATTACK enum)
local FIRE, ICE, DRAIN, SHELL, OSMOSE, CURE = 0x00, 0x01, 0x04, 0x25, 0x29, 0x2D
-- There was a seventh name here, `SCAN = 0x32`.  $32 is ATTACK::ANTDOT
-- (const.inc:640); ATTACK::SCAN is $18 (const.inc:614).  It was never used by
-- any assertion, and issue #76 was filed off a development-time observation
-- taken through it.  Removed rather than corrected: Celes learns Scan at
-- level 18 (field/event.asm:1268) and is level 14 at this fixture's
-- checkpoint, so a correct SCAN constant would name a spell she cannot cast.
local INFERNO, DDUST = 0x37, 0x38        -- summon attack ids (esper + $36)
local IFRIT, SHIVA = 0x01, 0x02          -- esper indices (GenjuProp order)

-- authored prices (magic_prop_en.dat +$05, spliced in battle_main.asm)
local OSMOSE_MP = 8                      -- OT6 v0.6; vanilla was 1
local FIRE_MP, ICE_MP, DRAIN_MP, SHELL_MP = 4, 5, 15, 15
local INFERNO_MP, DDUST_MP = 26, 27
-- authored Diamond Dust record ($38): power cut, Slow added
local DDUST_POWER, DDUST_STATUS3 = 34, 0x04       -- STATUS3::SLOW = BIT_2
local INFERNO_POWER, INFERNO_STATUS3 = 51, 0x00   -- unchanged (the control)
local MAGIC_PROP_REC = 14
local STATUS3_SLOW = 0x04

-- field menu route (probe-measured on this fixture 2026-08-10: the menu
-- opens with the command cursor on Item, and $4b is not the command cursor
-- until a press has happened, so the route is one unchecked down then A)
local ZMENUSTATE, ZCURSOR, GENJULIST = 0x26, 0x4b, 0x9d89
local MST_MAIN, MST_CHAR, MST_SKILLS, MST_LIST, MST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local function mst() return H.readByte(ZMENUSTATE) end
local function fieldEsper(c) return H.readByte(0x1600 + 37*c + 0x1e) end

-- battle menu
local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_MAGIC, ST_ESPER, ST_TGT, ST_TRANS =
  0x05, 0x0A, 0x0E, 0x16, 0x38, 0x01
local CMD_MAGIC, CMD_ITEM = 0x02, 0x01
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
local LISTS = { [0] = 0x208e, [1] = 0x21ca, [2] = 0x2306, [3] = 0x2442 }
local SUMMONED = 0x3f2e
local TONIC, POTION = 0xE8, 0xE9

local BOSS = 0                            -- Number 024's monster slot
local function bossHp() return H.readWord(0x3BFC + BOSS*2) end
local function bossMp() return H.readWord(0x3C08 + 8 + BOSS*2) end
local function bossAllow34() return H.readWord(0x3330 + 8 + BOSS*2) end
local function bossSt3() return H.readByte(0x3EF8 + 8 + BOSS*2) end

local locke, celes
local function mp(slot) return H.readWord(0x3C08 + slot*2) end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
local function mask(slot) return H.readWord(0x3018 + slot*2) end
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
local function costOf(slot, id)
  local n = recOf(slot, id)
  return n and H.readByte(LISTS[slot] + n*4 + 3) or nil
end
local function recEnabled(slot, n)
  return H.readByte(LISTS[slot] + n*4 + 1) < 0x80
end
local function esperRow(slot) return H.readByte(LISTS[slot]) end
local function esperCost(slot) return H.readByte(LISTS[slot] + 3) end
local function esperEnabled(slot) return H.readByte(LISTS[slot] + 1) < 0x80 end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end

-- ------------------------------------------------ real field esper equip --
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

-- equip esper `idx` on the character at char-select position `pos`
-- (menu order measured: 0=EDGAR 1=SABIN 2=LOCKE 3=CELES), verify by
-- reading the roster record back
local function equipOn(pos, idx, roster, tag)
  local steps = {
    H.driveUntil(function() return mst() == MST_MAIN end, 1200, {
      H.pressButtons({ "x" }, 4), H.waitFrames(30),
    }, tag .. ": main menu"),
    H.waitFrames(20),
    H.pressButtons({ "down" }, 3), H.waitFrames(12),   -- Item -> Skills
    H.driveUntil(function() return mst() == MST_CHAR end, 600, {
      H.pressButtons({ "a" }, 3), H.waitFrames(16),
    }, tag .. ": char select"),
    H.waitFrames(10),
  }
  for _ = 1, pos do
    steps[#steps+1] = H.pressButtons({ "down" }, 3)
    steps[#steps+1] = H.waitFrames(12)
  end
  local more = {
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
    listSeek(idx, tag .. ": cursor to the stone"),
    H.waitFrames(20),
    H.driveUntil(function() return mst() == MST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, tag .. ": detail page"),
    H.waitFrames(20),
    H.pressButtons({ "a" }, 3),            -- equip (MenuState_4d's A)
    H.waitFrames(20),
    H.driveUntil(function() return H.hasControl() and not H.dialogWaiting() end,
      1200, { H.pressButtons({ "b" }, 3), H.waitFrames(20) },
      tag .. ": menu closed"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(fieldEsper(roster), idx,
        tag .. ": the REAL equip landed in the roster record")
    end),
  }
  for _, s in ipairs(more) do steps[#steps+1] = s end
  return H.repeatN(1, steps)
end

-- ------------------------------------------------------ the battle drive --
local spells, mpWrites = {}, {}
local R = {}   -- results; declared BEFORE enterBoss so its $3410 callback
               -- closes over this table (a later declaration left the
               -- callback holding a nil global, and Mesen discards
               -- callback errors; measured: hpMid was never captured)
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end

-- modes: Locke heals, using item turns aimed at the worst-hp living ally,
-- because a two-man fight against a L24 boss does not survive a deferring
-- bench; Celes runs the arms.
local mf = 0
local celesMode = "defer"                -- "defer"|"summon"|"cast"|"park"
local lockeMode = "medic"                -- "medic"|"summon"
local castRec = nil                      -- list record to cast in "cast"
-- the character-target latch and steer code (measured in battle_steal and
-- moved into the library as H.targetCursor)
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  tc.observe()
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
  if act == locke and lockeMode == "summon" then
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_MAGIC)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_MAGIC then btn = "up"       -- to the top, then the esper window
    elseif st == ST_ESPER then btn = "a"
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
    return btn and { [btn] = true } or {}
  end
  if act == locke then                          -- the medic line
    -- heal only when somebody is hurt; a healthy party defers so
    -- the arms finish before the L24 boss's focus fire adds up (measured:
    -- boot A's always-item healer died before the Inferno arm)
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
      -- steer the heal onto the worst-hp living character
      local worst, wpct = nil, 101
      for s = 0, 3 do
        local h, m = hp(s), H.readWord(0x3C1C + s*2)
        if h > 0 and m > 0 then
          local pct = h * 100 // m
          if pct < wpct then worst, wpct = s, pct end
        end
      end
      btn = tc.steer(worst, mf)
    else btn = "b" end
  elseif act == celes then
    if celesMode == "defer" then
      btn = (st == ST_CMD) and "x" or "b"
    elseif celesMode == "summon" then
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_MAGIC)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then
        -- scroll the list to the top, then up opens the esper window
        if H.readByte(MSCROLL + celes) + H.readByte(MROW + celes) > 0 then
          btn = "up"
        else btn = "up" end
      elseif st == ST_ESPER then btn = "a"
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    elseif celesMode == "cast" then
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_MAGIC)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then
        -- grid cell p = list record p+1 (record 0 is the esper row)
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
      elseif st == ST_TGT then btn = "a"   -- the spell's own default side
      else btn = "b" end
    else                                   -- "park": open her list and hold
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_MAGIC)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then btn = nil
      elseif st == ST_ESPER then btn = "b"
      else btn = "b" end
    end
  else
    btn = (st == ST_CMD) and "x" or "b"   -- the two KO'd slots, if ever up
  end
  return btn and { [btn] = true } or {}
end
local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(function() H.setPad(decide()) end),
  }, tag)
end

-- enter battle 72 from the entry-point park (face up, one A)
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
      emu.addMemoryCallback(function(_, v)
        spells[#spells + 1] = v
        -- actions serialize, so the boss HP at Inferno's own queue write is
        -- the value after DDust fully resolved, which is the per-summon
        -- damage baseline
        if v == INFERNO and R.hpMid == nil then R.hpMid = bossHp() end
      end, emu.callbackType.write, 0x7e3410, 0x7e3410)
      emu.addMemoryCallback(function(_, v) mpWrites[#mpWrites + 1] = v end,
        emu.callbackType.write, 0x7e3C08 + celes*2, 0x7e3C08 + celes*2)
      H.log(string.format("%s: locke slot %d mp=%d, celes slot %d mp=%d, "
        .. "boss hp=%d mp=%d allow34=%04x", tag, locke, mp(locke), celes,
        mp(celes), bossHp(), bossMp(), bossAllow34()))
    end),
  })
end

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),

  -- ------------------------------------------------- 0. the records, in ROM --
  H.call(function()
    local base = H.sym("MagicProp") & 0x3fffff
    local function fld(rec, off) return H.readRomByte(base + rec * MAGIC_PROP_REC + off) end
    H.log(string.format("MagicProp @ file $%06x", base))
    H.assertEq(fld(DDUST, 6), DDUST_POWER, "Diamond Dust ($38) power re-authored to 34")
    H.assertEq(fld(DDUST, 12), DDUST_STATUS3, "Diamond Dust carries STATUS3::SLOW")
    H.assertEq(fld(DDUST, 5), DDUST_MP, "Diamond Dust still costs 27 MP (unchanged)")
    H.assertEq(fld(DDUST, 1), 0x02, "Diamond Dust still ice (unchanged)")
    H.assertEq(fld(INFERNO, 6), INFERNO_POWER, "control: Inferno ($37) power untouched")
    H.assertEq(fld(INFERNO, 12), INFERNO_STATUS3, "control: Inferno carries no status rider")
    H.assertEq(fld(INFERNO, 5), INFERNO_MP, "control: Inferno still costs 26 MP")
    H.assertEq(fld(OSMOSE, 5), OSMOSE_MP, "Osmose ($29) repriced to 8 MP in the record")
  end),

  -- ============================= boot A: the kits, the divine, the latch ==
  H.loadState(STATE),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(0x1A69) & 0x06, 0x06,
      "IFRIT and SHIVA really in the bag ($1A69 give_genju receipts)")
  end),
  equipOn(3, SHIVA, 6, "A/celes-shiva"),
  equipOn(2, IFRIT, 1, "A/locke-ifrit"),
  enterBoss("bootA"),
  H.call(function()
    -- 1. Ifrit: the Furnace's prices, on Locke's real granted list
    H.assertEq(esperRow(locke), IFRIT, "[ifrit] list record 0 is Ifrit's summon row")
    H.assertEq(esperCost(locke), INFERNO_MP, "[ifrit] Inferno priced at 26 MP")
    H.assertEq(esperEnabled(locke), true, "[ifrit] the summon is offered at battle start")
    H.assertEq(costOf(locke, FIRE), FIRE_MP, "[ifrit] granted Fire costs 4 MP (base tier)")
    H.assertEq(costOf(locke, DRAIN), DRAIN_MP, "[ifrit] granted Drain costs 15 MP")
    -- 2. Shiva's kit on Celes's real list
    H.assertEq(esperRow(celes), SHIVA, "[shiva] list record 0 is Shiva's summon row")
    H.assertEq(esperCost(celes), DDUST_MP, "[shiva] Diamond Dust published at 27 MP")
    H.assertEq(esperEnabled(celes), true,
      "[shiva] the summon is OFFERED before it is spent (the positive control)")
    H.assertEq(costOf(celes, ICE), ICE_MP, "[shiva] Ice published at 5 MP")
    H.assertEq(costOf(celes, OSMOSE), OSMOSE_MP, "[shiva] Osmose published at 8 MP")
    H.assertEq(costOf(celes, SHELL), SHELL_MP, "[shiva] Shell published at 15 MP")
    H.assertEq(H.readWord(SUMMONED) & (mask(locke) | mask(celes)), 0,
      "[latch] $3f2e clear: nobody has summoned yet")
    -- 3. the species facts the divine arm depends on, read not written
    H.assertEq(bossAllow34() & STATUS3_SLOW, 0,
      "[ddust] NUMBER 024's own authored status word BLOCKS Slow "
      .. "(monster_prop +$16 -- the species choice, read live)")
    H.assertEq(bossSt3() & STATUS3_SLOW, 0, "[ddust] and it starts un-Slowed")
    H.assertEq(bossMp() >= 447, true,
      "[osmose] the real Facility-scale MP pool the reprice exists for")
    R.hp0, R.mp0 = bossHp(), mp(celes)
  end),
  -- 4. both divines, driven through the real menus one after the other; the
  -- boss's focus fire is real, so the arms run before the attrition builds up
  -- (measured: an always-healing party died before a late Inferno arm).
  (function()
    local lm0
    return H.repeatN(1, {
      H.call(function()
        R.hpMid = nil
        lm0 = mp(locke)
        celesMode = "summon"
      end),
      driveTo(function() return sawSpell(DDUST) end, 20000,
        "Diamond Dust ($38) reaches $3410"),
      H.call(function()
        celesMode = "defer"
        lockeMode = "summon"
      end),
      driveTo(function() return sawSpell(INFERNO) end, 20000,
        "Inferno ($37) reaches $3410"),
      H.call(function() lockeMode = "medic" end),
      H.waitFrames(300),
      H.call(function()
        H.log(string.format("[divines] boss hp %d->%d->%d st3=%02x | celes "
          .. "mp %d->%d | locke mp %d->%d | $3f2e=%04x", R.hp0, R.hpMid or -1,
          bossHp(), bossSt3(), R.mp0, mp(celes), lm0, mp(locke),
          H.readWord(SUMMONED)))
        H.assertEq(R.hpMid ~= nil and R.hpMid < R.hp0, true,
          "[ddust] the divine HIT (positive control for the status result)")
        H.assertEq(bossHp() < R.hpMid, true, "[inferno] the control divine hit too")
        H.assertEq(bossSt3() & STATUS3_SLOW, 0,
          "[ddust] the Slow rider was REFUSED where the species' authored "
          .. "immunity blocks it -- per-monster immunity is still consulted; "
          .. "[inferno] and Inferno carries no rider of its own")
        H.assertEq(R.mp0 - mp(celes), DDUST_MP, "[ddust] the summon charged its 27 MP")
        H.assertEq(lm0 - mp(locke), INFERNO_MP, "[inferno] charged its 26 MP")
        H.assertEq(H.readWord(SUMMONED) & mask(celes) ~= 0, true,
          "[latch] the engine set Celes's once-per-battle bit in $3f2e")
        H.assertEq(H.readWord(SUMMONED) & mask(locke) ~= 0, true,
          "[latch] ...and Locke's, for his own summon")
        H.screenshot("magicite_ddust")
      end),
    })
  end)(),
  -- 5. the spent summon greys at her next real window (natural refresh)
  H.call(function() celesMode = "park" end),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her next window's list is open"),
  H.call(function()
    H.setPad({})
    H.assertEq(esperEnabled(celes), false,
      "[latch] a spent summon greys the esper row (MP 79 >= 27, so the "
      .. "grey can only be the $3f2e latch)")
    H.assertEq(esperCost(celes), DDUST_MP, "[latch] ...still priced at 27")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[latch] her Ice row stays live -- the grey is the summon row's own")
  end),

  -- ==================== boot B: the re-offer, Osmose, and the boundary ==
  H.loadState(STATE),
  H.waitFrames(60),
  equipOn(3, SHIVA, 6, "B/celes-shiva"),
  enterBoss("bootB"),
  H.call(function()
    -- 7. the re-offer half of once-per-battle: a fresh battle offers the
    -- summon again (boot A's was spent and greyed when its battle ended)
    H.assertEq(esperEnabled(celes), true,
      "[latch] a NEW battle offers the summon again -- the latch is "
      .. "per-battle, not forever")
    H.assertEq(H.readWord(SUMMONED) & mask(celes), 0,
      "[latch] ...because battle init cleared $3f2e")
    R.mp0 = mp(celes)
    H.assertEq(R.mp0, 106, "[drain] her real pool opens full (106)")
  end),
  -- 8. drain by real casts to a low pool, then Osmose the boss
  H.call(function()
    celesMode = "cast"; castRec = recOf(celes, SHELL)
  end),
  driveTo(function() return mp(celes) < 35 end, 60000,
    "real Shell casts walk the pool down"),
  (function()
    local m0, g0
    return H.repeatN(1, {
      H.call(function()
        m0, g0 = mp(celes), bossMp()
        mpWrites = {}
        celesMode = "cast"; castRec = recOf(celes, OSMOSE)
        H.log(string.format("[osmose] casting at mp=%d, boss pool=%d", m0, g0))
      end),
      driveTo(function() return sawSpell(OSMOSE) end, 20000,
        "Osmose ($29) reaches $3410"),
      H.call(function() celesMode = "defer" end),
      H.waitFrames(240),
      H.call(function()
        local seen = {}
        for _, v in ipairs(mpWrites) do seen[v & 0xff] = true end
        H.log(string.format("[osmose] mp %d->%d, boss pool %d->%d",
          m0, mp(celes), g0, bossMp()))
        H.assertEq(seen[(m0 - OSMOSE_MP) & 0xff], true,
          "[osmose] the caster's MP was debited to exactly mp0-8 (the charge)")
        H.assertEq(bossMp() < g0, true, "[osmose] the boss's real pool dropped")
        H.assertEq(mp(celes) > m0, true,
          "[osmose] and the caster ended NET POSITIVE -- 8 MP is still a refill")
        H.screenshot("magicite_osmose")
      end),
    })
  end)(),
  -- 9. the 7-MP boundary, earned.  The Osmose refill clamped her to the
  -- full 106, and 106 = 1 (mod 5): Shell (15) and Cure (5) both preserve
  -- that residue, so kit casts alone land the pool at exactly 6, inside
  -- the 5..7 window with no finer adjustment needed.  (A 3-MP adjuster was
  -- tried first and abandoned when the pool did not move across repeated
  -- casts.  It was labelled Scan and filed as issue #76, "publishes 3 and
  -- charges 0"; the id behind the label was $32, Antdot, and Celes cannot cast
  -- Scan at this level at all.  Whatever stalled that drive, it was not a
  -- price that lies: battle_costtable pins all 54 published magic prices, and
  -- the charge is that same byte.  See the constant block above.)  The residue
  -- invariant is asserted so a future wallet change fails here instead of
  -- wedging the drive.
  H.call(function()
    H.assertEq(mp(celes) % 5, 1,
      "[boundary] the pool's mod-5 residue makes a pure Shell/Cure walk "
      .. "land on exactly 6")
    celesMode = "cast"; castRec = recOf(celes, SHELL)
  end),
  driveTo(function() return mp(celes) < 31 end, 60000,
    "Shell casts again (the Osmose refilled her)"),
  (function()
    local function step()
      local m = mp(celes)
      if m > 7 then return CURE else return nil end
    end
    local n = 0
    return H.repeatN(1, {
      driveTo(function()
        n = n + 1
        local nxt = step()
        if nxt == nil then return true end
        if celesMode ~= "cast" or castRec ~= recOf(celes, nxt) then
          celesMode = "cast"; castRec = recOf(celes, nxt)
        end
        if n % 300 == 0 then
          H.log(string.format("tail: mp=%d rec=%s st=%02x act=%d chp=%d lhp=%d",
            mp(celes), tostring(castRec), H.readByte(MSTATE),
            H.readByte(ACTOR) & 3, hp(celes), hp(locke)))
        end
        return false
      end, 60000, "Cure casts land the pool in 5..7"),
      H.call(function() celesMode = "park" end),
    })
  end)(),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her list open on the earned boundary"),
  H.call(function()
    H.setPad({})
    local m = mp(celes)
    H.log(string.format("[boundary] mp=%d", m))
    H.assertEq(m >= 5 and m <= 7, true,
      "[boundary] the pool really reads 5..7, walked there by real casts")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[boundary] Ice (5) is castable -- the control")
    H.assertEq(recEnabled(celes, recOf(celes, OSMOSE)), false,
      "[boundary] Osmose (8) is GREYED -- vanilla's 1 MP would not be")
    H.assertEq(recEnabled(celes, recOf(celes, SHELL)), false,
      "[boundary] Shell (15) is greyed")
    -- no summon was spent this battle, so this grey comes only from the MP gate
    H.assertEq(esperEnabled(celes), false,
      "[boundary] and the 27 MP summon is greyed too (no latch spent in "
      .. "this battle -- the grey is the price alone)")
    H.screenshot("magicite_boundary")
    H.log("[magicite] all scenarios passed")
  end),
})
