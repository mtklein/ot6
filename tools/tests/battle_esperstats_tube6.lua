-- @suite slow
-- battle_esperstats_tube6.lua -- the SIX TUBE-ROOM STONES, in battle
-- (docs/design/magicite-tube-six.md, issue #31): Maduin, Shoat, Phantom,
-- Carbunkl, Bismark and Unicorn now grant their designed spell lists live and
-- carry a while-worn stat mod, where before all six were vanilla placeholder
-- rows with an Ot6EsperStatTbl byte of $00.
--
-- Same instrument and same shape as battle_esperstats.lua (the v0.4/v0.6
-- file): each scenario reloads battle_doorstep, pokes char 0's equipped esper
-- at $161e, drives Terra into the guard fight, and reads the granted union out
-- of the compacted master Magic list plus the four battle-side effective stat
-- copies.  That file is left exactly as it was -- it is the shipped gate for
-- the eight stones it already covers, and a regression there must stay legible
-- as a regression there.  This is the v0.7 append.
--
-- THE THREE BROKEN ROWS.  Three of the six were not merely blank, they were
-- actively wrong, and the absent-assertions below are the fixes made
-- falsifiable:
--   * Maduin carried FIRE_2/ICE_2/BOLT_2 (genju_prop.asm:128 before this
--     change) -- three dead pre-folded tiers at once, the Kirin reason three
--     times over.  Fire2/Ice2/Bolt2 must now be ABSENT and the base tiers
--     present (Ot6FoldTbl rows 0-2, ot6_boost.asm:341-343).
--   * Bismark granted LIFE (:131) against kits.md:262-263's written rule that
--     revival "lives on Terra, Fenix Downs, and Sraphim, and nowhere else".
--     Life must now be ABSENT -- this is that rule asserted, not a taste call.
--   * Shoat granted BIO (:125), the pre-folded CAP of the poison family
--     (Ot6FoldTbl row 3, ot6_boost.asm:344).  Bio must now be ABSENT.
-- Run this file against a ROM built before the genju_prop change and all three
-- absent-checks fail; that is the point of them.
--
-- WHY THIS FILE BUILDS ITS OWN unionSet(), AND WHERE THE WINDOW COMES FROM.
-- battle_esperstats.lua and battle_subjob.lua both sweep all 79 records and
-- take any non-$ff byte at +0 as a known spell id.  Two things ride along in
-- that sweep, and BOTH would have broken this file's marquee assertion:
--
--   * Record 0 is the ESPER row -- its id byte holds the esper INDEX, not a
--     spell id (battle_esperstats.lua names this hazard).  MADUIN is esper 6
--     and ICE_2 is spell $06, so "Maduin does not grant Ice2" would have read
--     FALSE for a reason with nothing to do with the grant.
--   * Records 55..78 are LORES, and ValidateSpellList stores a lore with $8b
--     subtracted (battle_main.asm:14345-14351, `cmp #$8b / sbc #$8b`), which
--     drops it into the same 0..23 numeric range as a low spell id.
--
-- The second one is not hypothetical: the first run of this file failed its
-- own BASE control on "Bolt2 innately absent", with NO esper equipped.
-- probe_tube6_list.lua dumped the records and settled it -- at base, slots
-- 58/62/75 hold ids $03/$07/$14, and $3034 shows those slots carry lores $8e,
-- $92 and $9f.  $07 was never Bolt 2.
--
-- The record layout, read off ValidateSpellList's compaction
-- (battle_main.asm:14319-14356) and confirmed by that probe: slot =
-- master-list position + 1, positions 0..53 are the 54 spells and 54..77 the
-- 24 lores.  So SPELL ids live in slots 1..54 and nothing else, which is the
-- window swept below.
--
-- WHAT CANNOT BE A CONTROL HERE.
--   * The id column is PARTY-WIDE: ValidateSpellList writes each id into all
--     four character lists at once ($208e/$21ca/$2306/$2442, :14351-14354),
--     and only the +1 enable byte is per-character.  So an "absent" assertion
--     here proves no party member knows the spell -- stricter than needed --
--     while a "grants" assertion proves the spell entered the list when the
--     stone went onto char 0 and was not there before.  That is the same
--     inference battle_esperstats.lua draws; it is spelled out here because
--     the party-wide part is easy to misread as per-character.
--   * battle_doorstep is the Narshe intro and Terra knows Fire (L3) and Cure
--     (L1) innately (event.asm NaturalMagic), so "Maduin grants Fire" is
--     corroboration, not proof -- BASE has it too.  Ice and Bolt are the real
--     proof, and both are absent at BASE.  For the same reason "Bismark does
--     not grant Fire" is NOT ASSERTABLE and is deliberately omitted from his
--     absent list; Ice and Bolt carry that deletion instead.
-- Said out loud rather than quietly omitted, per CONTRIBUTING's quiet-test
-- rule and the same note battle_esperstats.lua carries.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

-- spell ids (const.inc ATTACK enum)
local FIRE, ICE, BOLT           = 0x00, 0x01, 0x02
local FIRE2, ICE2, BOLT2, BIO   = 0x05, 0x06, 0x07, 0x08
local BREAK, DOOM, PEARL, DEMI  = 0x0c, 0x0d, 0x0e, 0x10
local SLOW, SAFE, HASTE, BSERK  = 0x19, 0x1c, 0x1f, 0x21
local RFLECT, SHELL, VANISH     = 0x24, 0x25, 0x26
local WARP, DISPEL, CURE2       = 0x2a, 0x2c, 0x2e
local LIFE, REMEDY              = 0x30, 0x33

-- esper indices (GenjuProp order)
local SHOAT, MADUIN, BISMARK    = 0x05, 0x06, 0x07
local CARBUNKL, PHANTOM, UNICORN = 0x13, 0x14, 0x17

local ESPER0 = 0x161e            -- char 0 equipped esper (field record offset 0)
local LIST0  = 0x208e            -- compacted master Magic list, 4-byte records
-- battle-side effective stat copies, stride-2 by battle slot.  VIGOR is stored
-- DOUBLED ($3b2c, "vigor * 2" -- battle_main.asm:3857), so Bismark's authored
-- +4 must read as +8 here.
local STAM, MAGPWR, SPEED, VIGOR = 0x3b40, 0x3b41, 0x3b19, 0x3b2c

local function terraSlot()
  local t = 0
  for s = 0, 3 do if H.readByte(0x3ed8 + s * 2) == 0 then t = s end end
  return t
end

-- Slots 1..54 only: the SPELL window.  Slot 0 is the esper row and slots
-- 55..78 are lores stored as id-$8b -- see the header.
local function unionSet()
  local set = {}
  for n = 1, 54 do
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
local function idsOf(set)
  local t = {}
  for id in pairs(set) do t[#t + 1] = id end
  table.sort(t)
  local s = {}
  for i, id in ipairs(t) do s[i] = string.format("$%02x", id) end
  return table.concat(s, " ")
end

local R = {}                     -- R[tag] = { slot, stam, mag, spd, vig, union, row0 }

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
  steps[#steps + 1] = H.waitUntil(function() return H.battleActive() end, 900,
    "battle active (" .. tag .. ")", 30)
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
      row0  = H.readByte(LIST0),
    }
    -- Log the FULL granted set before any assertion fires.  A run against a
    -- pre-change ROM must leave the evidence in the log, not just a verdict.
    H.log(string.format("[%s] slot=%d stam=%d mag=%d spd=%d vig*2=%d row0=$%02x union#=%d",
      tag, t, R[tag].stam, R[tag].mag, R[tag].spd, R[tag].vig, R[tag].row0,
      setSize(R[tag].union)))
    H.log(string.format("[%s] granted union: %s", tag, idsOf(R[tag].union)))
  end)
  return steps
end

local function checkBase()
  return H.call(function()
    local b = R.base
    -- Every signature this file uses as grant-proof or as a deletion-proof must
    -- be innately UNKNOWN at BASE, or it could mask a broken grant.  FIRE and
    -- CURE are deliberately absent from this list: Terra knows both (header).
    for _, s in ipairs({
      { ICE, "Ice" }, { BOLT, "Bolt" },
      { FIRE2, "Fire2" }, { ICE2, "Ice2" }, { BOLT2, "Bolt2" }, { BIO, "Bio" },
      { BREAK, "Break" }, { DOOM, "Doom" }, { PEARL, "Pearl" }, { DEMI, "Demi" },
      { SLOW, "Slow" }, { SAFE, "Safe" }, { HASTE, "Haste" }, { BSERK, "Bserk" },
      { RFLECT, "Rflect" }, { SHELL, "Shell" }, { VANISH, "Vanish" },
      { WARP, "Warp" }, { DISPEL, "Dispel" }, { CURE2, "Cure2" },
      { LIFE, "Life" }, { REMEDY, "Remedy" },
    }) do
      H.assertEq(has(b.union, s[1]), false,
        "[base] " .. s[2] .. " innately absent (clean control)")
    end
    H.assertEq(has(b.union, FIRE), true,
      "[base] Fire IS innate here (the stated non-control -- asserted so the "
      .. "note stays true)")
  end)
end

-- #62: `deltas` is a table keyed stam/mag/spd/vig, replacing the old single
-- (stat, delta) pair, because Ot6EsperStatTbl now carries four SIGNED nibbles per
-- esper instead of one unsigned selector+magnitude.  A key left out means
-- "expected FLAT", so all four stats are still asserted on every scenario -- the
-- old flatness check is this same assertion with three zeros, and this form can
-- additionally say "this stat must go DOWN", which the old one could not express
-- at all.  vig deltas are given DOUBLED, as $3b2c stores them.
local function checkEsper(tag, esper, deltas, grants, absents)
  return H.call(function()
    local b, r = R.base, R[tag]
    -- Positive control: list record 0 really is the esper row (its id byte is
    -- the esper INDEX).  This is what licenses the union starting at record 1.
    H.assertEq(r.row0, esper, "[" .. tag .. "] list record 0 holds the esper index")
    local now = { stam = r.stam, mag = r.mag, spd = r.spd, vig = r.vig }
    local was = { stam = b.stam, mag = b.mag, spd = b.spd, vig = b.vig }
    for _, k in ipairs({ "stam", "mag", "spd", "vig" }) do
      local d = deltas[k] or 0
      H.assertEq(now[k], was[k] + d, string.format("[%s] %s %d -> %d (want %+d)",
        tag, k, was[k], now[k], d))
    end
    -- A scenario expecting a NEGATIVE delta must see the stat actually drop: a
    -- build whose sign nibble decoded as zero would otherwise pass as "flat".
    for k, d in pairs(deltas) do
      if d < 0 then
        H.assertEq(now[k] < was[k], true,
          string.format("[%s] %s really DROPPED (%d -> %d)", tag, k, was[k], now[k]))
      end
    end
    for _, g in ipairs(grants) do
      H.assertEq(has(r.union, g[1]), true, "[" .. tag .. "] grants " .. g[2])
    end
    for _, a in ipairs(absents or {}) do
      H.assertEq(has(r.union, a[1]), false, "[" .. tag .. "] " .. a[2] .. " NOT granted")
    end
  end)
end

-- ------------------------------------------------------------- compose run --
local all = { H.waitFrames(20) }
local function add(list) for _, s in ipairs(list) do all[#all + 1] = s end end

add(driveSteps("base", nil));  add({ checkBase() })

-- MADUIN -- "the Trinity", THE CROWN, on #62's BOSS rung: +7 mag.pwr (the
-- encoding's ceiling AND vanilla's own per-stat ceiling), +3 stamina, -3 vigor
-- (-6 doubled) because Terra's inheritance is a mage's.  All three grants are
-- fold BASE tiers; the three pre-folded tiers the vanilla row carried are the
-- broken-row fix.  Fire is present but innate here, so Ice and Bolt are proof.
add(driveSteps("maduin", MADUIN))
add({ checkEsper("maduin", MADUIN, { mag = 7, stam = 3, vig = -6 },
  { { FIRE, "Fire (base tier; innate here, corroboration)" },
    { ICE, "Ice (base tier)" }, { BOLT, "Bolt (base tier)" } },
  { { FIRE2, "Fire2 (dead pre-folded tier -- BROKEN ROW FIX)" },
    { ICE2, "Ice2 (dead pre-folded tier -- BROKEN ROW FIX)" },
    { BOLT2, "Bolt2 (dead pre-folded tier -- BROKEN ROW FIX)" } }) })

-- SHOAT -- "the Gorgon Eye", STORY rung: +6 speed, +2 stamina, -2 vigor
-- (-4 doubled) -- the Eye is a stare, not a strike.  Bio absent is the
-- broken-row fix.
add(driveSteps("shoat", SHOAT))
add({ checkEsper("shoat", SHOAT, { spd = 6, stam = 2, vig = -4 },
  { { BREAK, "Break" }, { DOOM, "Doom" } },
  { { BIO, "Bio (pre-folded poison cap -- BROKEN ROW FIX)" } }) })

-- BISMARK -- "the Tide", STORY rung: +5 vigor (+10 doubled), +3 stamina, and
-- -2 SPEED -- the leviathan is mass, and -2 speed on a heavy thing is Iron
-- Armor's own shape (the only non-curse negative in all 256 vanilla item
-- records).  Life absent is the kits.md:262-263 revival rule, asserted.  Fire
-- is NOT in the absent list -- see the header; Ice and Bolt carry the "Maduin's
-- job" deletion.
add(driveSteps("bismark", BISMARK))
add({ checkEsper("bismark", BISMARK, { vig = 10, stam = 3, spd = -2 },
  { { HASTE, "Haste (fold base)" }, { SLOW, "Slow (fold base)" } },
  { { LIFE, "Life (kits.md revival rule -- BROKEN ROW FIX)" },
    { ICE, "Ice (Maduin's job)" }, { BOLT, "Bolt (Maduin's job)" } }) })

-- CARBUNKL -- "the Facet", STORY rung: +6 stamina (the wall stone's stat),
-- +2 mag.pwr, -2 speed because a gem is inert.
add(driveSteps("carbunkl", CARBUNKL))
add({ checkEsper("carbunkl", CARBUNKL, { stam = 6, mag = 2, spd = -2 },
  { { RFLECT, "Rflect" }, { SAFE, "Safe" } },
  { { WARP, "Warp (field furniture)" }, { SHELL, "Shell (Shiva's)" },
    { HASTE, "Haste (moved to Bismark)" } }) })

-- PHANTOM -- "the Ghostwalk", STORY rung: +6 speed, +2 mag.pwr, -2 stamina
-- because a ghost has no body.  Shares Shoat's +6 speed LEAD deliberately and
-- separates on the second stat and the downside -- six stones need six reasons
-- to swap, not six distinct leads (magicite-tube-six.md §3).
add(driveSteps("phantom", PHANTOM))
add({ checkEsper("phantom", PHANTOM, { spd = 6, mag = 2, stam = -2 },
  { { VANISH, "Vanish" }, { DEMI, "Demi" } },
  { { BSERK, "Bserk (removes player control -- the Ifrit reason)" } }) })

-- UNICORN -- "the Purity", STORY rung and deliberately its SMALLEST package
-- with NO downside: +5 stamina, +2 mag.pwr.  The Pearl grant is where his power
-- is, and the protector does not ask for a sacrifice.  Pearl is BRANCH A of the cross-doc
-- holy decision, DECIDED by the dispatcher (magicite-tube-six.md §9): if this
-- row is ever reverted to branch B, this assertion is the thing that has to be
-- consciously edited.
add(driveSteps("unicorn", UNICORN))
add({ checkEsper("unicorn", UNICORN, { stam = 5, mag = 2 },
  { { PEARL, "Pearl (branch A -- the paladin's smite)" }, { REMEDY, "Remedy" } },
  { { CURE2, "Cure2 (dead pre-folded tier)" }, { SAFE, "Safe (-> Carbunkl)" },
    { SHELL, "Shell (Shiva's)" }, { DISPEL, "Dispel (branch B's row)" } }) })

add({ H.call(function()
  H.log("[esperstats-tube6] all six tube-room stones grant their designed "
    .. "lists and carry their designed stat mods")
end) })

H.run({ maxFrames = 320000 }, all)   -- 7 scenarios, each a full state reload + drive-in
