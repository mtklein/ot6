-- @suite slow
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
-- v0.6 adds the two magicite the Magitek Research Facility pays out
-- (docs/design/magicite-ifrit-shiva.md, issue #16).  Ifrit is the first esper to
-- claim VIGOR, so this file reads the fourth stat too: $3b2c, which vanilla
-- stores as vigor*2 (battle_main.asm:3857 "vigor * 2"), so an authored +6 shows
-- up here as +12.
--
-- #62 REBUILT THE TABLE AND THIS FILE'S ASSERTION SHAPE.  Ot6EsperStatTbl used to
-- be one byte per esper, [selector:4][magnitude:4] -- exactly ONE stat, unsigned.
-- It is now TWO bytes in vanilla's own equipment layout (ItemProp+16/+17): four
-- SIGNED nibbles, -7..+7 each, so a stone can move several stats and can move one
-- DOWN.  The old checkEsper() therefore could not express what to assert: it took
-- a single (stat, delta) pair and asserted the other three FLAT.  It now takes a
-- table of all four expected deltas and asserts every one of them, defaulting to
-- 0 -- which is STRICTLY STRONGER than the old form (the old flatness check is
-- the same assertion with three zeros) and is the only way a two-sided mod can be
-- checked at all.  A stone whose downside silently failed to apply would have
-- passed the old shape trivially, because a downside was unrepresentable.
--
-- The clamps are also new and worth stating: the encoding is signed, so
-- Ot6EsperStatMod floors each stat at 0 as well as capping it at 255.  None of
-- the scenarios below is near either bound on this fixture (Terra's base stats
-- are 31/33/28/39, char_prop.asm:151), so these numbers exercise the arithmetic,
-- not the clamps.
--
-- SCENARIOS (each an independent STATE reload; every esper scenario pokes char
-- 0's equipped esper $161e before driving in, exactly as battle_subjob does):
--   BASE  no esper: record Terra's stamina/mag.pwr/speed/vigor + the innate
--                   union; assert all grant signatures + CURE_2 absent (controls).
--   RAMUH esper 0  stamina +4, mag.pwr +2; grants Bolt/Rasp.
--   SIREN esper 3  speed +4, mag.pwr +2; grants Sleep/Mute/Slow(base).
--   KIRIN esper 17 mag.pwr +4, stamina +2; grants Cure(base)/Regen/Antdot, and
--                  NOT Cure2.
--   STRAY esper 8  mag.pwr +4, speed +2; grants Muddle/Imp/Float (none folds).
--   IFRIT esper 1  vigor +6 (+12 doubled), stamina +4, MAG.PWR -3; grants
--                  Fire(base)/Drain, and NOT Fire2 -- the dead pre-folded tier
--                  the vanilla row carried.  The -3 is the marquee: it is the
--                  two-sided mod magicite-ifrit-shiva.md §12.1 recorded as
--                  unbuildable, and it is unrepresentable in the old encoding.
--   SHIVA esper 2  mag.pwr +6, speed +4, VIGOR -3 (-6 doubled); grants
--                  Ice(base)/Osmose/Shell, and NOT Ice2 (dead pre-folded tier)
--                  and NOT Rasp (left to Ramuh).  Ifrit's mirror, as §5.2 asked.
--
-- A NOTE ON WHAT CANNOT BE A CONTROL HERE.  Terra's natural magic is Cure at L1
-- and Fire at L3 (event.asm NaturalMagic), and this fixture is the Narshe intro,
-- so she knows both innately.  "Shiva does not grant Cure" and "Ifrit's Fire is
-- the grant's doing" are therefore NOT assertable on this fixture -- BASE would
-- see them either way.  Both stones' grants are proved by signatures BASE first
-- shows absent (Drain, Ice, Osmose, Shell), and their deletions by the two that
-- are genuinely absent (Fire2, Ice2, Rasp).  Said out loud rather than quietly
-- omitted, per CONTRIBUTING's quiet-test rule.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

-- spell ids (const.inc ATTACK enum)
local BOLT, RASP           = 0x02, 0x1a
local SLEEP, MUTE, SLOW    = 0x1d, 0x1b, 0x19
local MUDDLE, IMP, FLOAT   = 0x1e, 0x23, 0x22
local CURE, CURE2, REGEN, ANTDOT = 0x2d, 0x2e, 0x34, 0x32
local FIRE, FIRE2, DRAIN   = 0x00, 0x05, 0x04
local ICE, ICE2, OSMOSE, SHELL = 0x01, 0x06, 0x29, 0x25

-- esper indices (GenjuProp order)
local RAMUH, SIREN, STRAY, KIRIN = 0x00, 0x03, 0x08, 0x11
local IFRIT, SHIVA = 0x01, 0x02

local ESPER0 = 0x161e            -- char 0 equipped esper (field record offset 0)
local LIST0  = 0x208e            -- compacted master Magic list, 4-byte records
-- battle-side effective stat copies, stride-2 by battle slot (UpdateEquipBattle
-- stores each at base + slot*2; matches battle_subjob's $3c08/$3e9c reads).
-- VIGOR is stored DOUBLED ($3b2c, "vigor * 2" -- battle_main.asm:3857), so a
-- +5 vigor esper reads +10 here.
local STAM, MAGPWR, SPEED, VIGOR = 0x3b40, 0x3b41, 0x3b19, 0x3b2c

local function terraSlot()
  local t = 0
  for s = 0, 3 do if H.readByte(0x3ed8 + s * 2) == 0 then t = s end end
  return t
end
-- CAUTION (the collision battle_subjob names): list record 0 is the ESPER row,
-- and its id byte holds the ESPER INDEX, not a spell id (ValidateSpellList
-- writes it there; UpdateEnabledMagic reads its enable flag at +1).  Sweeping
-- n=0 into the same set therefore injects one bogus "spell id" per scenario --
-- Ifrit(1) looks like Ice, Shiva(2) like Bolt, Kirin(17) like Quartr.  None of
-- those collide with a signature asserted below, which is checked, not lucky:
-- Ifrit asserts Fire/Drain/not-Fire2, Shiva asserts Ice/Osmose/Shell/not-Ice2/
-- not-Rasp.  A future esper whose index equals a signature id must not use this
-- helper for that signature.
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
      vig   = H.readByte(VIGOR + t * 2),
      union = unionSet(),
    }
    H.log(string.format("[%s] slot=%d stam=%d mag=%d spd=%d vig*2=%d union#=%d",
      tag, t, R[tag].stam, R[tag].mag, R[tag].spd, R[tag].vig, setSize(R[tag].union)))
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
      -- v0.6: Ifrit/Shiva signatures + the two pre-folded tiers their rows drop
      { DRAIN, "Drain" }, { ICE, "Ice" }, { OSMOSE, "Osmose" }, { SHELL, "Shell" },
      { FIRE2, "Fire2" }, { ICE2, "Ice2" },
    }) do
      H.assertEq(has(b.union, s[1]), false, "[base] " .. s[2] .. " innately absent (clean control)")
    end
  end)
end
-- `deltas` is a table keyed stam/mag/spd/vig; a key left out means "expected
-- FLAT", so every scenario still asserts all four stats and an unauthored stat
-- moving is still a failure.  vig deltas are given DOUBLED, as $3b2c stores them.
local function checkEsper(tag, deltas, grants, absents)
  return H.call(function()
    local b, r = R.base, R[tag]
    local now  = { stam = r.stam, mag = r.mag, spd = r.spd, vig = r.vig }
    local was  = { stam = b.stam, mag = b.mag, spd = b.spd, vig = b.vig }
    for _, k in ipairs({ "stam", "mag", "spd", "vig" }) do
      local d = deltas[k] or 0
      H.assertEq(now[k], was[k] + d, string.format("[%s] %s %d -> %d (want %+d)",
        tag, k, was[k], now[k], d))
    end
    -- Positive control on the table shape itself: a scenario that expects a
    -- NEGATIVE delta must actually see the stat go DOWN.  Without this, a build
    -- where the sign nibble decoded as zero would look like a passing "flat".
    for k, d in pairs(deltas) do
      if d < 0 then
        H.assertEq(now[k] < was[k], true,
          string.format("[%s] %s really DROPPED (%d -> %d), the signed nibble "
            .. "decoded as negative", tag, k, was[k], now[k]))
      end
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
add({ checkEsper("ramuh", { stam = 4, mag = 2 },
  { { BOLT, "Bolt" }, { RASP, "Rasp" } }) })
add(driveSteps("siren", SIREN))
add({ checkEsper("siren", { spd = 4, mag = 2 },
  { { SLEEP, "Sleep" }, { MUTE, "Mute" }, { SLOW, "Slow (base tier)" } }) })
add(driveSteps("kirin", KIRIN))
add({ checkEsper("kirin", { mag = 4, stam = 2 },
  { { CURE, "Cure (base tier)" }, { REGEN, "Regen" }, { ANTDOT, "Antidote" } },
  { { CURE2, "Cure2 (pre-folded tier)" } }) })
add(driveSteps("stray", STRAY))
add({ checkEsper("stray", { mag = 4, spd = 2 },
  { { MUDDLE, "Muddle" }, { IMP, "Imp" }, { FLOAT, "Float" } }) })
-- v0.6 boss stones, on #62's BOSS rung: upside +10 across three stats bought
-- with a -3.  Ifrit's +6 vigor reads as +12 because $3b2c is the doubled copy,
-- and his mag.pwr -3 is the two-sided mod the old encoding could not say.
-- Drain is the grant proof (Terra learns it at L12,
-- so BASE has it absent); Fire is asserted present but is innate here, so it is
-- corroboration, not proof.  Fire2 absent is the fold-correctness deletion.
add(driveSteps("ifrit", IFRIT))
add({ checkEsper("ifrit", { vig = 12, stam = 4, mag = -3 },
  { { FIRE, "Fire (base tier)" }, { DRAIN, "Drain" } },
  { { FIRE2, "Fire2 (pre-folded tier)" } }) })
-- Shiva: three grants, all three absent at BASE, so all three are proof.  Ice2
-- is the dead-tier deletion; Rasp absent is the "left to Ramuh" deletion.
add(driveSteps("shiva", SHIVA))
add({ checkEsper("shiva", { mag = 6, spd = 4, vig = -6 },
  { { ICE, "Ice (base tier)" }, { OSMOSE, "Osmose" }, { SHELL, "Shell" } },
  { { ICE2, "Ice2 (pre-folded tier)" }, { RASP, "Rasp (Ramuh's)" } }) })
add({ H.call(function() H.log("[esperstats] all scenarios passed") end) })

H.run({ maxFrames = 320000 }, all)   -- 7 scenarios, each a full state reload + drive-in
