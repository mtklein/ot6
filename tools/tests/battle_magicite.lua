-- @suite slow savestate=n024_entry
-- battle_magicite.lua -- the Ifrit and Shiva magicite kits, the halves
-- battle_esperstats.lua does not reach: the ability prices their kits are
-- built on, and the summons. battle_esperstats covers which spells and
-- which stat; this file covers what they cost and what the divine does.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/n024_entry.mss.lua"

-- spell ids (const.inc ATTACK enum)
local FIRE, ICE, DRAIN, SHELL, OSMOSE, CURE = 0x00, 0x01, 0x04, 0x25, 0x29, 0x2D
local ANTDOT = 0x32                      -- the 3-MP row the boundary tail steps with
local INFERNO, DDUST = 0x37, 0x38        -- summon attack ids (esper + $36)
local IFRIT, SHIVA = 0x01, 0x02          -- esper indices (GenjuProp order)

-- authored prices (magic_prop_en.dat +$05, spliced in battle_main.asm)
local OSMOSE_MP = 8                      -- vanilla was 1
local FIRE_MP, ICE_MP, DRAIN_MP, SHELL_MP = 4, 5, 15, 15
local INFERNO_MP, DDUST_MP = 26, 27
-- authored Diamond Dust record ($38): power cut, Slow added
local DDUST_POWER, DDUST_STATUS3 = 34, 0x04       -- STATUS3::SLOW = BIT_2
local INFERNO_POWER, INFERNO_STATUS3 = 51, 0x00   -- unchanged (the control)
local MAGIC_PROP_REC = 14
local STATUS3_SLOW = 0x04

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

-- pos is char-select menu order: 0=EDGAR 1=SABIN 2=LOCKE 3=CELES
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
               -- closes over this table
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
local partyCare = true                    -- false briefly for menu assertions
local castRec = nil                      -- list record to cast in "cast"
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })
-- Where is the machine?  The fight ending, and the party being ground down
-- by a level-24 boss, look identical from outside.
local hbF = -600
local function heartbeat()
  if H.frame - hbF < 600 then return end
  hbF = H.frame
  local hps = {}
  for s = 0, 3 do hps[#hps+1] = tostring(H.readWord(0x3BF4 + s*2)) end
  H.log(string.format("[hb f%d] live=%s menu=%02x actor=%d mstate=%02x "
    .. "mons=%d hp=%s celes=%s locke=%s", H.frame,
    tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
    H.readByte(MSTATE), H.monstersPresent(), table.concat(hps, "/"),
    celesMode, lockeMode))
end
local function decide()
  heartbeat()
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
  if act ~= celes and not partyCare then
    btn = (st == ST_CMD) and "x" or "b"
  elseif act ~= celes then                      -- the medic line

    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 45 then hurt = true end
    end
    local bagHasHeal = bagIdxOf({ TONIC, POTION }) ~= nil
    if st == ST_CMD and not (hurt and bagHasHeal) then btn = "x"
    elseif st == ST_CMD then
      local want = cmdRowOf(act, CMD_ITEM)
      if want == nil then btn = "x"
      else
        local cur = H.readByte(CMDROW + act) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      end
    elseif st == ST_ITEM then
      -- A Tonic's 50 does not cover a round from this boss, so somebody
      -- badly hurt gets the Potion when one exists; Tonics carry the rest.
      local worstPct = 101
      for s2 = 0, 3 do
        local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
        if h > 0 and m > 0 then
          local pct = h * 100 // m
          if pct < worstPct then worstPct = pct end
        end
      end
      local want = (worstPct < 45) and bagIdxOf({ POTION }) or nil
      want = want or bagIdxOf({ TONIC, POTION })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + act) + H.readByte(0x894F + act)
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
      partyCare = true
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
  H.fieldCare({ tag = "before battle 72", threshold = 0.95, magic = false }),
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
  (function()
    local lm0
    return H.repeatN(1, {
      H.call(function()
        R.hpMid = nil
        lm0 = mp(locke)
        celesMode = "summon"
      end),
      driveTo(function()
        return H.readWord(SUMMONED) & mask(celes) ~= 0
           and mp(celes) == R.mp0 - DDUST_MP
      end, 20000, "Celes's Diamond Dust is really queued and paid for"),
      H.call(function()
        celesMode = "defer"
      end),
      driveTo(function() return bossHp() < R.hp0 end, 5000,
        "Diamond Dust resolves against NUMBER 024"),
      H.call(function()
        -- $3410 is a shared numeric ability id: a monster action can also
        -- write $37/$38.  Take the damage baseline only after Celes's latch,
        -- debit and HP change have jointly identified her real summon.
        R.hpMid = bossHp()
        lockeMode = "summon"
      end),
      driveTo(function()
        return H.readWord(SUMMONED) & mask(locke) ~= 0
           and mp(locke) == lm0 - INFERNO_MP
      end, 20000, "Locke's Inferno is really queued and paid for"),
      H.call(function() lockeMode = "medic" end),
      driveTo(function() return bossHp() < R.hpMid end, 5000,
        "Inferno resolves against NUMBER 024"),
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
  H.call(function() partyCare = false; celesMode = "park" end),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her next window's list is open"),
  H.call(function()
    H.setPad({})
    H.assertEq(esperCost(celes), DDUST_MP, "[latch] ...still priced at 27")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[latch] her Ice row stays live after the summon")
  end),

  (function()
    local m0, g0
    return H.repeatN(1, {
      H.call(function()
        m0, g0 = mp(celes), bossMp()
        mpWrites = {}
        celesMode = "cast"; castRec = recOf(celes, OSMOSE)
        H.log(string.format("[osmose] casting at mp=%d, boss pool=%d", m0, g0))
      end),
      driveTo(function()
        local debited = false
        for _, v in ipairs(mpWrites) do
          if (v & 0xff) == ((m0 - OSMOSE_MP) & 0xff) then debited = true end
        end
        return debited and bossMp() < g0
      end, 20000, "Celes's Osmose is really charged and drains the boss"),
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

  -- Now that Osmose has restored her above 27 MP, the spent summon row's
  -- grey cannot be explained by price.  Re-open the same live list and bind
  -- the verdict uniquely to the once-per-battle latch.
  H.call(function() partyCare = false; celesMode = "park" end),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her refilled post-summon list is open"),
  H.call(function()
    H.setPad({})
    H.assertEq(mp(celes) >= DDUST_MP, true,
      "[latch] Osmose restored enough MP to afford another summon")
    H.assertEq(esperEnabled(celes), false,
      "[latch] the affordable spent summon is grey from $3f2e")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[latch] an ordinary affordable spell remains live beside it")
  end),

  -- ============================ boot B: the re-offer and the boundary ==
  H.loadState(STATE),
  H.waitFrames(60),
  equipOn(3, SHIVA, 6, "B/celes-shiva"),
  H.fieldCare({ tag = "before battle 72 (boot B)", threshold = 0.95,
                magic = false }),
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
    -- The fixture no longer ships her full: she arrives at 41 of 106, and
    -- the care stop above is deliberately item-only so that it heals her HP
    -- without topping the pool up.  The boundary walk below rests on this
    -- number: 41 = 1 (mod 5), and Shell (15) and Cure (5) both preserve the
    -- residue, so kit casts alone land on exactly 6.  The maximum is pinned
    -- beside it so a fixture that ships a different pool says which of the
    -- two numbers moved.
    H.assertEq(R.mp0, 41,
      "[drain] her real pool opens at the 41 the fixture carries")
    -- $3BF4 hp, $3C08 mp, $3C1C max hp, $3C30 max mp: one 20-byte stride
    H.assertEq(H.readWord(0x3C30 + celes*2), 106,
      "[drain] and her maximum is 106")
    -- The boundary is only five of her turns from this 41-MP start.  Defer
    -- the bench so an unrelated item-target cursor cannot own the menu while
    -- the MP experiment is running.
    partyCare = false
  end),
  -- 7. the 7-MP boundary, earned by real casts of her own kit: Shells (15)
  -- to bring the pool down in big steps, then a tail that steps onto the
  -- 5..7 window exactly.

  -- So the tail picks its spell from where the pool actually is: Cure (5)
  -- down to 10, then Antdot (3) from 8 or 9, which reaches every value in
  -- 5..7 from any pool of 8 or more.
  H.call(function()
    celesMode = "cast"; castRec = recOf(celes, SHELL)
  end),
  driveTo(function() return mp(celes) < 31 end, 60000,
    "Shell casts walk the pool toward the boundary"),
  (function()
    local function step()
      local m = mp(celes)
      if m >= 10 then return CURE end
      if m >= 8 then return ANTDOT end
      return nil
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
