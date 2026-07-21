-- @suite
-- battle_esperstats.lua -- M5 espers-as-sub-jobs, the WHILE-EQUIPPED STAT BOOST
-- (the owner's fork-4 pick) plus a per-esper kit confirmation for the four Zozo
-- espers.  Companion to battle_subjob.lua, which proved the additive spell GRANT
-- and its deletions; this proves the stat half and the three not-yet-Ramuh kits.
--
-- THE STAT MOD.  While an esper is worn, Ot6EsperStatMod (ot6.asm) adds that
-- esper's Ot6EsperStatTbl entry to the character's $1100 stat buffer at the top of
-- UpdateEquipBattle, so the copy into the battle-side effective stats
-- ($3b40 stamina, $3b41 mag.pwr, $3b19 speed, $3b2c vigor*2) carries the bump --
-- the values damage/hit/ATB actually read.  It is NEVER written to the persistent
-- $161a-$161d record, so "no esper" is the reverted state: the negative control
-- (scenario BASE) doubles as the unequip-reverts proof.  Each esper touches ONLY
-- its selector's stat (asserted: the other two stay flat), which proves the
-- selector decode is exact.
--
-- THE KITS.  Each Zozo esper is driven into a fight and its granted spells are
-- read out of the compacted master Magic list ($208e union).  Fold-correctness
-- (the core's Ramuh precedent: grant the BASE tier, let boost do the tiering) is
-- checked two ways: Siren grants base SLOW ($19, a fold base) and Kirin grants
-- base CURE ($2d) while its pre-folded CURE_2 ($2e) is ABSENT -- the one data fix
-- this change made (genju_prop.asm).  Signatures used as grant proof are pure
-- status/utility spells no WoB natural-magic kit teaches, so scenario BASE first
-- asserts every one of them absent (a clean control); any that a party member
-- knew innately would fail there loudly instead of masking a broken grant.
--
-- SCENARIOS (each an independent STATE reload; Ramuh/Siren/Kirin/Stray poke char
-- 0's equipped esper $161e before driving in, exactly as battle_subjob does):
--   BASE  no esper: record Terra's stamina/mag.pwr/speed + the innate union;
--                   assert all grant signatures + CURE_2 absent (controls).
--   RAMUH esper 0  stamina +3; grants Bolt/Rasp.
--   SIREN esper 3  speed  +2; grants Sleep/Mute/Slow(base).
--   KIRIN esper 17 mag.pwr +3; grants Cure(base)/Regen/Antdot, and NOT Cure2.
--   STRAY esper 8  mag.pwr +3; grants Muddle/Imp/Float (none in a fold family).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

-- spell ids (const.inc ATTACK enum)
local BOLT, RASP           = 0x02, 0x1a
local SLEEP, MUTE, SLOW    = 0x1d, 0x1b, 0x19
local MUDDLE, IMP, FLOAT   = 0x1e, 0x23, 0x22
local CURE, CURE2, REGEN, ANTDOT = 0x2d, 0x2e, 0x34, 0x32

-- esper indices (GenjuProp order)
local RAMUH, SIREN, STRAY, KIRIN = 0x00, 0x03, 0x08, 0x11

local ESPER0 = 0x161e            -- char 0 equipped esper (field record offset 0)
local LIST0  = 0x208e            -- compacted master Magic list, 4-byte records
-- battle-side effective stat copies, stride-2 by battle slot (UpdateEquipBattle
-- stores each at base + slot*2; matches battle_subjob's $3c08/$3e9c reads)
local STAM, MAGPWR, SPEED = 0x3b40, 0x3b41, 0x3b19

local function terraSlot()
  local t = 0
  for s = 0, 3 do if H.readByte(0x3ed8 + s * 2) == 0 then t = s end end
  return t
end
local function unionSet()
  local set = {}
  for n = 0, 78 do
    local id = H.readByte(LIST0 + n * 4)
    if id ~= 0xff then set[id] = true end
  end
  return set
end
local function has(set, id) return set[id] == true end
local function setSize(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

local R = {}                     -- R[tag] = { slot, stam, mag, spd, union }

-- Build the step list for one scenario: reload STATE, optionally poke the esper,
-- drive Terra up+A into the guard fight, and record her battle stats + union.
local function driveSteps(tag, esper)
  local steps = {
    H.loadState(STATE),
    H.waitFrames(10),
  }
  if esper == nil then
    steps[#steps + 1] = H.call(function()
      H.assertEq(H.readByte(ESPER0), 0xff, "[" .. tag .. "] char 0 has no esper (control)")
    end)
  else
    steps[#steps + 1] = H.call(function()
      H.writeByte(ESPER0, esper)
      H.log(string.format("[%s] char 0 esper := %d", tag, esper))
    end)
  end
  steps[#steps + 1] = H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (" .. tag .. ")")
  steps[#steps + 1] = H.waitUntil(function() return H.battleActive() end, 900, "battle active (" .. tag .. ")", 30)
  steps[#steps + 1] = H.waitFrames(120)
  steps[#steps + 1] = H.call(function()
    local t = terraSlot()
    R[tag] = {
      slot  = t,
      stam  = H.readByte(STAM + t * 2),
      mag   = H.readByte(MAGPWR + t * 2),
      spd   = H.readByte(SPEED + t * 2),
      union = unionSet(),
    }
    H.log(string.format("[%s] slot=%d stam=%d mag=%d spd=%d union#=%d",
      tag, t, R[tag].stam, R[tag].mag, R[tag].spd, setSize(R[tag].union)))
  end)
  return steps
end

-- The per-scenario assertions, run as a step right after that scenario measured
-- (BASE is measured first, so R.base is available to every esper comparison).
local function checkBase()
  return H.call(function()
    local b = R.base
    -- every grant signature must be innately UNKNOWN here, else it could mask a
    -- broken grant (and CURE_2 must be unknown for the fold-correct absent-check)
    for _, s in ipairs({
      { BOLT, "Bolt" }, { RASP, "Rasp" }, { SLEEP, "Sleep" }, { MUTE, "Mute" },
      { SLOW, "Slow" }, { REGEN, "Regen" }, { ANTDOT, "Antidote" },
      { MUDDLE, "Muddle" }, { IMP, "Imp" }, { FLOAT, "Float" }, { CURE2, "Cure2" },
    }) do
      H.assertEq(has(b.union, s[1]), false, "[base] " .. s[2] .. " innately absent (clean control)")
    end
  end)
end
local function checkEsper(tag, stat, delta, grants, absents)
  return H.call(function()
    local b, r = R.base, R[tag]
    -- the selected stat bumps by exactly delta; the other two stay flat, which
    -- proves the selector decode touched only its target
    local pairs3 = { stam = r.stam, mag = r.mag, spd = r.spd }
    local base3  = { stam = b.stam, mag = b.mag, spd = b.spd }
    for k, v in pairs(pairs3) do
      local want = base3[k] + (k == stat and delta or 0)
      H.assertEq(v, want, string.format("[%s] %s %d -> %d (want %+d on %s)",
        tag, k, base3[k], v, (k == stat and delta or 0), k))
    end
    for _, g in ipairs(grants) do
      H.assertEq(has(r.union, g[1]), true, "[" .. tag .. "] grants " .. g[2])
    end
    for _, a in ipairs(absents or {}) do
      H.assertEq(has(r.union, a[1]), false, "[" .. tag .. "] " .. a[2] .. " NOT granted (fold-correct)")
    end
  end)
end

-- ------------------------------------------------------------- compose run --
local all = { H.waitFrames(20) }
local function add(list) for _, s in ipairs(list) do all[#all + 1] = s end end

add(driveSteps("base", nil));  add({ checkBase() })
add(driveSteps("ramuh", RAMUH))
add({ checkEsper("ramuh", "stam", 3, { { BOLT, "Bolt" }, { RASP, "Rasp" } }) })
add(driveSteps("siren", SIREN))
add({ checkEsper("siren", "spd", 2,
  { { SLEEP, "Sleep" }, { MUTE, "Mute" }, { SLOW, "Slow (base tier)" } }) })
add(driveSteps("kirin", KIRIN))
add({ checkEsper("kirin", "mag", 3,
  { { CURE, "Cure (base tier)" }, { REGEN, "Regen" }, { ANTDOT, "Antidote" } },
  { { CURE2, "Cure2 (pre-folded tier)" } }) })
add(driveSteps("stray", STRAY))
add({ checkEsper("stray", "mag", 3,
  { { MUDDLE, "Muddle" }, { IMP, "Imp" }, { FLOAT, "Float" } }) })
add({ H.call(function() H.log("[esperstats] all scenarios passed") end) })

H.run({ maxFrames = 220000 }, all)
