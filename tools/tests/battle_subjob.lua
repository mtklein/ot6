-- @suite
-- battle_subjob.lua -- M5 espers-as-sub-jobs, the FORK-INDEPENDENT core: an
-- equipped esper GRANTS its spells to the in-battle Magic list (additively), the
-- grant never teaches permanently, and level-up esper stat bonuses are gone.
--
-- battle_doorstep is a FIELD state at the guard-fight doorstep; you drive up+A
-- into the fight, so the whole list-build (InitSpellList's union + the
-- per-character ValidateSpellList prune) runs AFTER the state loads.  Poking
-- Terra's equipped esper ($161e, char 0 = record offset 0) in the field before
-- driving in therefore reaches the build.  Ramuh (GenjuProp index 0) is authored
-- to base-tier Bolt ($02) + Rasp ($1a); Terra innately knows NEITHER (the clean
-- negative control), so any Bolt/Rasp in her list is the grant's doing.
--
-- Two hooks make this work, MEASURED necessary (probe_subjob): the in-battle
-- Magic list is COMPACTED to the union of party-known spells, so a borrowed spell
-- nobody knows has no slot at all -- Ot6UnionEspers (ot6.asm) seeds the union with
-- equipped espers' spells, and Ot6EsperSpellKnown then keeps each one only for its
-- esper's holder.
--
-- SCENARIOS (independent loads; CONTRIBUTING: a quiet test is not a passing test,
-- so every positive carries its negative control):
--   A NEGATIVE  no esper: Terra's list has neither Bolt nor Rasp (== vanilla).
--   B GRANT     Ramuh: Bolt AND Rasp appear; the list is A's list PLUS exactly
--               {summon, Bolt, Rasp} -- additive, innate untouched; Bolt is priced
--               at vanilla MP (no double-charge); the summon slot is registered.
--   C FOLD      a granted Bolt cast with 2 BP executes as Bolt3 ($0b) via the fold
--               and is charged base-Bolt MP -- which also proves it is CASTABLE.
--   D DELETIONS win a level-up with Ramuh: no esper stat bonus (Stamina flat --
--               vanilla Ramuh's STAMINA_1 would bump it) and no spell learned
--               (Bolt/Rasp stay unlearned in $1a6e).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local BOLT, BOLT3, RASP = 0x02, 0x0b, 0x1a
local LIST0  = 0x208e           -- slot 0 spell/lore list, 4-byte records
local ESPER0 = 0x161e           -- char 0 equipped esper (field record offset 0)
local KNOWN0 = 0x1a6e           -- char 0 learned table ($ff = learned)
local STAM0  = 0x161c           -- char 0 stamina (record offset 0)
local LEVEL0, XP0 = 0x1608, 0x1611

local function listSet()
  local set = {}
  for n = 0, 78 do
    local id = H.readByte(LIST0 + n * 4)
    if id ~= 0xff then set[#set + 1] = id end
  end
  return set
end
local function has(set, id)
  for _, v in ipairs(set) do if v == id then return true end end
  return false
end
local function boltCost()          -- MP cost stored in the Bolt list record (+3)
  for n = 0, 78 do
    if H.readByte(LIST0 + n * 4) == BOLT then return H.readByte(LIST0 + n * 4 + 3) end
  end
  return nil
end
local function fmt(set)
  local s = {}
  for _, v in ipairs(set) do s[#s + 1] = string.format("%02x", v) end
  return table.concat(s, " ")
end

-- vanilla XP thresholds (battle_levelup): 8*sum(LevelUpExp[0..L-1]) to leave L
local LEVELUP_EXP = { 4,8,14,24,34,48,62,79, 99,120,143,169,195,224,257,289 }
local function neededXp(L)
  local s = 0
  for i = 1, L do s = s + LEVELUP_EXP[i] end
  return 8 * s
end
local function setXp(v)
  H.writeByte(XP0,     v         & 0xff)
  H.writeByte(XP0 + 1, (v >> 8)  & 0xff)
  H.writeByte(XP0 + 2, (v >> 16) & 0xff)
end

local baseSet                    -- scenario A's list, carried into B
local spells = {}                -- attack ids that reached $3410 (last spell used)
local terra, mp0, hp0, stam0, lvl0

H.run({ maxFrames = 120000 }, {
  ----------------------------------------------------------------- A: NEGATIVE --
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(ESPER0), 0xff, "char 0 starts with no esper (control)")
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (A)"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active (A)", 30),
  H.waitFrames(120),
  H.call(function()
    baseSet = listSet()
    H.log("[A] no-esper slot0 list: " .. fmt(baseSet))
    H.assertEq(has(baseSet, BOLT), false, "no esper: Bolt absent (vanilla)")
    H.assertEq(has(baseSet, RASP), false, "no esper: Rasp absent (vanilla)")
  end),

  -------------------------------------------------------------------- B: GRANT --
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function() H.writeByte(ESPER0, 0x00); H.log("[B] char 0 esper := Ramuh") end),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (B)"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active (B)", 30),
  H.waitFrames(120),
  H.call(function()
    local set = listSet()
    H.log("[B] Ramuh slot0 list: " .. fmt(set))
    H.assertEq(has(set, BOLT), true, "Ramuh grants Bolt into the list")
    H.assertEq(has(set, RASP), true, "Ramuh grants Rasp into the list")
    -- MULTISET diff base->Ramuh: additive means no innate entry removed, and the
    -- only additions are Bolt, Rasp, and the esper's SUMMON slot (list-head entry,
    -- id = esper index 0 -- which collides with Fire's 0, hence counting).
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
    -- no double-charge: the granted Bolt is priced at vanilla Bolt MP in the list
    local cost = boltCost()
    H.log("[B] granted Bolt list MP cost = " .. tostring(cost))
    H.assertEq(cost ~= nil and cost >= 3 and cost <= 8, true,
      "granted Bolt priced at vanilla MP (~5), not doubled or Bolt3's")
    -- summon plumbing intact (deletion #5, verify-don't-modify): ValidateSpellList
    -- registered Ramuh's summon at $3344; $3f2e (the once-per-battle "has summoned"
    -- gate) is clear at start, so the summon is available.  None of that path is
    -- touched by M5.
    H.assertEq(H.readByte(0x3344), 0x00, "ValidateSpellList registered Ramuh's summon ($3344)")
    H.assertEq(H.readByte(0x3f2e) & H.readByte(0x3018), 0,
      "summon not yet spent at battle start ($3f2e gate clear)")
  end),

  --------------------------------------------------------------------- C: FOLD --
  -- Menu input on this mint is unreliable (battle_fold), so the cast goes through
  -- the vanilla muddle AUTO-action path: Terra casts a random spell from her LIVE
  -- list -- which now includes the granted Bolt.  With 2 BP pending, a Bolt cast
  -- folds to Bolt3 ($0b) at queue time (Ot6QueueFold); we re-arm until that lands.
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function() H.writeByte(ESPER0, 0x00); H.log("[C] char 0 esper := Ramuh") end),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (C)"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active (C)", 30),
  H.waitFrames(120),
  H.call(function()
    terra = 0
    for slot = 0, 3 do if H.readByte(0x3ed8 + slot * 2) == 0 then terra = slot end end
    H.log("[C] terra is slot " .. terra)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)   -- keep Terra's MP topped
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)         -- stop the guards
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- drive A until the menu belongs to someone ELSE, then muddle Terra
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= terra
  end, 10000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == terra then H.setPad({ "a" }) end
    end),
    H.waitFrames(4), H.call(function() H.setPad({}) end), H.waitFrames(26),
  }, "menu passed beyond terra (C)"),
  H.call(function()
    local st1 = 0x3ee4 + terra * 2
    H.writeByte(st1, H.readByte(st1) & 0xf7)      -- clear magitek
    H.writeByte(0x202e + terra * 12, 0x02)        -- Magic only
    H.writeByte(0x2031 + terra * 12, 0xff)
    H.writeByte(0x2034 + terra * 12, 0xff)
    H.writeByte(0x2037 + terra * 12, 0xff)
    H.writeByte(0x3ee5 + terra * 2, H.readByte(0x3ee5 + terra * 2) | 0x20)  -- muddle
  end),
  -- re-arm 2 BP every time pending clears until a Bolt folds to Bolt3 ($0b)
  H.driveUntil(function()
    for _, v in ipairs(spells) do if v == BOLT3 then return true end end
    return false
  end, 30000, {
    H.call(function()
      if H.readByte(0x3e9d + terra * 2) == 0 then
        mp0 = H.readWord(0x3c08 + terra * 2)
        H.writeByte(0x3e9c + terra * 2, 3)        -- bp
        H.writeByte(0x3e9d + terra * 2, 2)        -- pending boost
      end
    end),
    H.waitFrames(30),
  }, "a granted Bolt folded to Bolt3 (C)"),
  H.call(function()
    H.writeByte(0x3ee5 + terra * 2, H.readByte(0x3ee5 + terra * 2) & 0xdf)  -- un-muddle
  end),
  H.waitUntil(function() return H.readByte(0x3e9d + terra * 2) == 0 end, 1200,
    "folded cast resolves (C)", 10),
  H.waitFrames(40),
  H.call(function()
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("[C] $3410 sequence: " .. table.concat(ids, " "))
    local sawBolt3 = false
    for _, v in ipairs(spells) do if v == BOLT3 then sawBolt3 = true end end
    H.assertEq(sawBolt3, true, "granted Bolt at 2 BP executed as Bolt3 ($0b) via the fold")
    local mp1 = H.readWord(0x3c08 + terra * 2)
    local cost = mp0 - mp1
    H.log(string.format("[C] mp %d -> %d (cost %d)", mp0, mp1, cost))
    -- charged at base Bolt (~5), never Bolt3's (~20).  bound is generous for a
    -- possible trailing muddle cast but still separates base from the tier-3 price.
    H.assertEq(cost >= 1 and cost < 15, true,
      "boosted cast charged base-Bolt MP, not Bolt3's")
  end),

  ---------------------------------------------------------------- D: DELETIONS --
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function() H.writeByte(ESPER0, 0x00); H.log("[D] char 0 esper := Ramuh") end),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (D)"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active (D)", 30),
  H.waitFrames(120),
  H.call(function()
    stam0 = H.readByte(STAM0)
    lvl0 = H.readByte(LEVEL0)
    -- precondition: Terra does not innately know Bolt/Rasp, so "still unlearned"
    -- after the win is meaningful.
    H.assertEq(H.readByte(KNOWN0 + BOLT) ~= 0xff, true, "Bolt unlearned before win (control)")
    H.assertEq(H.readByte(KNOWN0 + RASP) ~= 0xff, true, "Rasp unlearned before win (control)")
    setXp(neededXp(lvl0) + 4)                     -- one threshold over -> a level
    H.log(string.format("[D] L=%d stamina=%d, xp pinned one level over", lvl0, stam0))
  end),
  H.clearBattle(20000),
  H.waitFrames(40),
  H.call(function()
    local lvl1 = H.readByte(LEVEL0)
    local stam1 = H.readByte(STAM0)
    H.log(string.format("[D] after win: L %d->%d  stamina %d->%d", lvl0, lvl1, stam0, stam1))
    H.assertEq(lvl1 > lvl0, true, "leveled up (the mechanism ran)")
    -- deletion #3: vanilla Ramuh's STAMINA_1 would raise stamina on the level; the
    -- stripped ($ff) bonus is bmi-skipped, so stamina is flat.
    H.assertEq(stam1, stam0, "no esper level-up stat bonus (Stamina flat)")
    -- deletion #2: rate-0 learning means the win teaches nothing (IncLearnMagic
    -- returns on 0%); Bolt/Rasp are still granted-only, not written to $1a6e.
    H.assertEq(H.readByte(KNOWN0 + BOLT) ~= 0xff, true, "Bolt not permanently learned")
    H.assertEq(H.readByte(KNOWN0 + RASP) ~= 0xff, true, "Rasp not permanently learned")
    H.log("[subjob] all scenarios passed")
  end),
})
