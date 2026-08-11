-- @suite savestate=minecart_entry slow
-- battle_esperstats.lua -- M5 espers-as-sub-jobs, the WHILE-EQUIPPED STAT BOOST
-- (the owner's fork-4 pick) plus a per-esper kit confirmation for the four Zozo
-- espers and the two MRF stones.  Companion to battle_subjob.lua, which proved
-- the additive spell GRANT and its deletions; this proves the stat half.
--
-- THE STAT MOD.  While an esper is worn, Ot6EsperStatMod (ot6.asm) adds that
-- esper's Ot6EsperStatTbl entry to the character's $1100 stat buffer at the top of
-- UpdateEquipBattle, so the copy into the battle-side effective stats
-- ($3b40 stamina, $3b41 mag.pwr, $3b19 speed, $3b2c vigor*2) carries the bump --
-- the values damage/hit/ATB actually read.  It is NEVER written to the persistent
-- $161a-$161d record, so "no esper" is the reverted state: the negative control
-- (scenario BASE) doubles as the unequip-reverts proof.
--
-- =============== THE INPUT-DRIVEN REBUILD (#75) ===========================
-- The previous version of this file POKED char 0's equipped-esper byte $161e
-- and ran on battle_entry -- the Narshe intro, where Terra owns no esper
-- at all, so the menu could never have equipped one and the poke was the only
-- way in.  Issue #75's rule (inputs in, observations out, never write
-- emulated state) retired the poke, and with it the fixture: equipping
-- in normal play requires OWNING the stone, so this file now runs on
-- MINECART_ENTRY -- the first fixture on the chain that owns all six
-- stones under test (the Zozo four from gen_zozo5_ramuh, Ifrit/Shiva from
-- the MRF hand-off; $1A69 reads EF 01 9A 00 here) AND offers a battle:
--
--   * each scenario reloads the fixture and EQUIPS ITS STONE THROUGH THE
--     REAL FIELD MENU -- X -> Skills -> leader -> Espers -> two-column list
--     seek -> detail page -> A on row 0, the page's own equip handler
--     (skills.asm MenuState_4d @5902 "equip esper").  The walk is
--     menu_esperdetail.lua's, plus the equip press that test never makes.
--     Success is read back from the character record before leaving.
--   * the battle is the minecart ride's FIRST scripted fight: the fixture
--     parks the party one A-press from CID, whose event runs `cutscene
--     TRAIN`, and the ride's course throws battle 41 (Mag Roader) ~1240
--     frames in (gen_n128's decode of train_script.asm:615-660).  A real
--     random-encounter walk is not available here -- the tube room's door
--     back to map 273 is one-way (measured: the {10,25} door tile is
--     unreachable from inside) -- and the scripted fight is better anyway:
--     deterministic, frame-cheap, and reached by pad input alone.
--
-- THE FIXTURE CHANGE STRENGTHENS EVERY CONTROL.  The party here is LOCKE,
-- SABIN and EDGAR, and NaturalMagic (field/event.asm) teaches spells only to
-- TERRA and CELES -- Celes left the roster at the tube room, one step before
-- this fixture.  So the party innately knows NOTHING: the BASE union is
-- asserted literally EMPTY, and every grant signature below -- including
-- FIRE and CURE, which the old Narshe fixture could never use because Terra
-- knows both innately -- is a clean absent-at-BASE control.  Ifrit's Fire
-- and Kirin's Cure were "corroboration, not proof" in the old file's own
-- words; here they are proof.  Nothing was demoted: every signature the old
-- BASE could assert absent, this BASE can too.
--
-- THE MEASURED CHARACTER is whoever leads the party (the character menu's
-- slot 0 -- EDGAR on this savestate), FOUND from the live menu RAM and asserted
-- against the field party order, never assumed.  Stat deltas are vs the
-- BASE scenario for the same character, so the change of body from Terra
-- changes nothing about what the numbers prove.  VIGOR is stored DOUBLED
-- ($3b2c, "vigor * 2" -- battle_main.asm:3857), so an authored +6 reads +12.
--
-- THE UNION WINDOW is rows 1..54 of the compacted master Magic list --
-- battle_esperstats_tube6.lua's window, adopted here in place of the old
-- 0..78 sweep: row 0 is the ESPER row (its id byte is the esper INDEX, which
-- collided with spell ids -- Ifrit(1) read as Ice), and rows 55..78 are
-- LORES stored id-$8b (which collided with low spell ids; that file's BASE
-- control actually failed on it once).  Row 0 is instead asserted DIRECTLY:
-- it must hold the equipped esper's index, the positive control that
-- licenses the window.
--
-- #62's assertion shape is kept: `deltas` carries all four stats, a key left
-- out means "expected FLAT", and a negative delta must be seen actually
-- DROPPING (a build whose sign nibble decoded as zero would otherwise pass
-- as "flat").  None of the scenarios is near the 0/255 clamps on this
-- fixture (Edgar's base battle stats here: stam 34, mag 29, spd 30, vig*2
-- 78), so these numbers exercise the arithmetic, not the clamps.
--
-- SCENARIOS (each an independent STATE reload; every esper scenario equips
-- through the menu exactly as a player would):
--   BASE  no esper: assert NOBODY has an esper equipped, record the leader's
--                   four stats + the union; assert the union EMPTY.
--   RAMUH esper 0  stamina +4, mag.pwr +2; grants Bolt/Rasp.
--   SIREN esper 3  speed +4, mag.pwr +2; grants Sleep/Mute/Slow(base).
--   KIRIN esper 17 mag.pwr +4, stamina +2; grants Cure(base)/Regen/Antdot,
--                  and NOT Cure2 (dead pre-folded tier).
--   STRAY esper 8  mag.pwr +4, speed +2; grants Muddle/Imp/Float.
--   IFRIT esper 1  vigor +6 (+12 doubled), stamina +4, MAG.PWR -3; grants
--                  Fire(base)/Drain, and NOT Fire2.  The -3 is the marquee:
--                  the two-sided mod magicite-ifrit-shiva.md's ledger
--                  recorded as unbuildable under the old one-stat encoding.
--   SHIVA esper 2  mag.pwr +6, speed +4, VIGOR -3 (-6 doubled); grants
--                  Ice(base)/Osmose/Shell, and NOT Ice2 and NOT Rasp
--                  (left to Ramuh).  Ifrit's mirror, as §5.2 asked.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/minecart_entry.mss.lua"

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

local LIST0  = 0x208e            -- compacted master Magic list, 4-byte records
local STAM, MAGPWR, SPEED, VIGOR = 0x3b40, 0x3b41, 0x3b19, 0x3b2c

-- field menu plumbing (menu_ram.inc; the menu_esperdetail walk)
local ZMENUSTATE, ZCURSOR, ZSELINDEX, ZLISTTYPE = 0x26, 0x4b, 0x28, 0x2a
local ZCHARID, Z99 = 0x69, 0x99
local SKILLCOLOR = 0x79          -- zSkillsTextColor[0] = the Espers row
local GENJULIST = 0x9d89         -- $7e9d89: list row -> esper index
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local function st() return H.readByte(ZMENUSTATE) end
local function rec(c) return 0x1600 + 37 * c end
local ESPER_OFF = 0x1E           -- equipped esper in the character record

-- the leader: the character the char menu's slot 0 offers (party order 0)
local function leaderOf()
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    if b ~= 0 and (b & 0x07) == cur and ((b >> 3) & 3) == 0 then return c end
  end
  return nil
end
local function partyChars()
  local t, cur = {}, H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    if b ~= 0 and (b & 0x07) == cur then t[#t + 1] = c end
  end
  return t
end

-- rows 1..54 only: the SPELL window (see header)
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
local leader = nil               -- char id of the measured character

-- two-column esper list seek (menu_esperdetail's, verbatim shape)
local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return st() == ST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
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
      if d % 2 ~= 0 then                -- wrong column: fix parity first
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

-- The real equip walk: X -> Skills -> leader -> Espers -> seek -> detail ->
-- A on row 0 (MenuState_4d's equip handler) -> back to the field.
local function equipSteps(tag, esper)
  return {
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu (" .. tag .. ")"),
    H.waitFrames(20),
    H.pressButtons({ "down" }, 2),         -- Items -> Skills
    H.waitFrames(6),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300,
      "character select (" .. tag .. ")", 5),
    H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(ZCHARID + 0), leader,
        "[" .. tag .. "] the char menu's slot 0 is the field party's leader")
    end),
    H.pressButtons({ "a" }, 2),            -- pick the leader (cursor starts at 0)
    H.waitUntil(function() return st() == ST_SKILLS end, 300,
      "skills submenu (" .. tag .. ")", 5),
    H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(ZSELINDEX), 0,
        "[" .. tag .. "] the confirm latched party slot 0")
      H.assertEq(H.readByte(SKILLCOLOR), 0x20,
        "[" .. tag .. "] the Espers row is enabled (the leader carries MAGIC)")
    end),
    H.driveUntil(function()
      return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0
    end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
      "skills cursor to Espers (" .. tag .. ")"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_LIST end, 300,
      "esper list (" .. tag .. ")", 5),
    H.call(function()
      H.assertEq(H.readByte(ZLISTTYPE), 4,
        "[" .. tag .. "] list type GENJU (menu_ram.inc)")
    end),
    listSeek(esper, "cursor to esper " .. esper .. " (" .. tag .. ")"),
    H.waitFrames(20),                      -- let any list scroll finish
    H.driveUntil(function() return st() == ST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "detail (" .. tag .. ")"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.readByte(Z99), esper,
        "[" .. tag .. "] the detail page is the right stone's")
    end),
    -- A on detail row 0 equips; read the record back rather than trust the press
    H.driveUntil(function()
      return H.readByte(rec(leader) + ESPER_OFF) == esper
    end, 600, { H.pressButtons({ "a" }, 3), H.waitFrames(12) },
      "equip lands in the character record (" .. tag .. ")"),
    (function()
      local calm = 0
      return H.driveUntil(function()
        calm = H.hasControl() and calm + 1 or 0
        return calm >= 10
      end, 2000, { H.pressButtons({ "b" }, 3), H.waitFrames(20) },
        "back to the field (" .. tag .. ")")
    end)(),
  }
end

-- One A-press to CID launches `cutscene TRAIN`; the course throws battle 41
-- ~1240 frames in.  Then measure the leader's battle-side stats + the union.
local function rideAndMeasure(tag)
  return {
    H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(26),
    }, "A to CID -> the ride's first battle (" .. tag .. ")"),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle active (" .. tag .. ")", 30),
    H.waitFrames(240),
    H.call(function()
      local t = nil
      for s = 0, 3 do
        if H.readByte(0x3ed8 + s * 2) == leader then t = s end
      end
      H.assertEq(t ~= nil, true, "[" .. tag .. "] the leader is in the battle")
      R[tag] = {
        slot  = t,
        stam  = H.readByte(STAM + t * 2),
        mag   = H.readByte(MAGPWR + t * 2),
        spd   = H.readByte(SPEED + t * 2),
        vig   = H.readByte(VIGOR + t * 2),
        union = unionSet(),
        row0  = H.readByte(LIST0),
      }
      H.log(string.format("[%s] slot=%d stam=%d mag=%d spd=%d vig*2=%d row0=$%02x union#=%d",
        tag, t, R[tag].stam, R[tag].mag, R[tag].spd, R[tag].vig, R[tag].row0,
        setSize(R[tag].union)))
      H.log(string.format("[%s] granted union: %s", tag, idsOf(R[tag].union)))
    end),
  }
end

local function driveSteps(tag, esper)
  local steps = {
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(function() return H.hasControl() end, 600,
      "field control (" .. tag .. ")", 5),
    H.call(function()
      leader = leaderOf()
      H.assertEq(leader ~= nil, true, "[" .. tag .. "] a party leader resolved")
    end),
  }
  if esper == nil then
    steps[#steps + 1] = H.call(function()
      for _, c in ipairs(partyChars()) do
        H.assertEq(H.readByte(rec(c) + ESPER_OFF), 0xff,
          string.format("[%s] char %d wears no esper (control)", tag, c))
      end
    end)
  else
    for _, s in ipairs(equipSteps(tag, esper)) do steps[#steps + 1] = s end
  end
  for _, s in ipairs(rideAndMeasure(tag)) do steps[#steps + 1] = s end
  return steps
end

local function checkBase()
  return H.call(function()
    local b = R.base
    -- LOCKE/SABIN/EDGAR have no natural magic (NaturalMagic teaches only
    -- Terra and Celes, and Celes left at the tube room), so the base union
    -- is EMPTY -- the strongest control this file has ever had, and the one
    -- that makes every signature below proof, Fire and Cure included.
    H.assertEq(setSize(b.union), 0,
      "[base] the spell union is EMPTY -- nobody in LOCKE/SABIN/EDGAR "
      .. "innately knows anything, so every grant below is proof")
    for _, s in ipairs({
      { BOLT, "Bolt" }, { RASP, "Rasp" }, { SLEEP, "Sleep" }, { MUTE, "Mute" },
      { SLOW, "Slow" }, { CURE, "Cure" }, { REGEN, "Regen" }, { ANTDOT, "Antidote" },
      { MUDDLE, "Muddle" }, { IMP, "Imp" }, { FLOAT, "Float" }, { CURE2, "Cure2" },
      { FIRE, "Fire" }, { DRAIN, "Drain" }, { ICE, "Ice" }, { OSMOSE, "Osmose" },
      { SHELL, "Shell" }, { FIRE2, "Fire2" }, { ICE2, "Ice2" },
    }) do
      H.assertEq(has(b.union, s[1]), false,
        "[base] " .. s[2] .. " innately absent (clean control)")
    end
  end)
end

-- #62's shape: all four stats asserted every scenario; a key left out means
-- "expected FLAT"; a negative delta must be seen actually dropping.  vig
-- deltas are given DOUBLED, as $3b2c stores them.
local function checkEsper(tag, esper, deltas, grants, absents)
  return H.call(function()
    local b, r = R.base, R[tag]
    H.assertEq(r.row0, esper,
      "[" .. tag .. "] list record 0 holds the esper index -- the equip is "
      .. "IN the battle, and the rows-1..54 window is licensed")
    local now = { stam = r.stam, mag = r.mag, spd = r.spd, vig = r.vig }
    local was = { stam = b.stam, mag = b.mag, spd = b.spd, vig = b.vig }
    for _, k in ipairs({ "stam", "mag", "spd", "vig" }) do
      local d = deltas[k] or 0
      H.assertEq(now[k], was[k] + d, string.format("[%s] %s %d -> %d (want %+d)",
        tag, k, was[k], now[k], d))
    end
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
      H.assertEq(has(r.union, a[1]), false,
        "[" .. tag .. "] " .. a[2] .. " NOT granted (fold-correct)")
    end
  end)
end

-- ------------------------------------------------------------- compose run --
local all = { H.waitFrames(20) }
local function add(list) for _, s in ipairs(list) do all[#all + 1] = s end end

add(driveSteps("base", nil));  add({ checkBase() })
add(driveSteps("ramuh", RAMUH))
add({ checkEsper("ramuh", RAMUH, { stam = 4, mag = 2 },
  { { BOLT, "Bolt" }, { RASP, "Rasp" } }) })
add(driveSteps("siren", SIREN))
add({ checkEsper("siren", SIREN, { spd = 4, mag = 2 },
  { { SLEEP, "Sleep" }, { MUTE, "Mute" }, { SLOW, "Slow (base tier)" } }) })
add(driveSteps("kirin", KIRIN))
add({ checkEsper("kirin", KIRIN, { mag = 4, stam = 2 },
  { { CURE, "Cure (base tier -- PROOF here, no innate mage in the party)" },
    { REGEN, "Regen" }, { ANTDOT, "Antidote" } },
  { { CURE2, "Cure2 (pre-folded tier)" } }) })
add(driveSteps("stray", STRAY))
add({ checkEsper("stray", STRAY, { mag = 4, spd = 2 },
  { { MUDDLE, "Muddle" }, { IMP, "Imp" }, { FLOAT, "Float" } }) })
-- v0.6 boss stones, on #62's BOSS tier: upside +10 across three stats bought
-- with a -3.  Ifrit's +6 vigor reads as +12 because $3b2c is the doubled
-- copy, and his mag.pwr -3 is the two-sided mod the old encoding could not
-- say.  On this fixture BOTH grants are proof -- the old file had to call
-- Fire "corroboration" because Terra knew it innately.
add(driveSteps("ifrit", IFRIT))
add({ checkEsper("ifrit", IFRIT, { vig = 12, stam = 4, mag = -3 },
  { { FIRE, "Fire (base tier -- PROOF here)" }, { DRAIN, "Drain" } },
  { { FIRE2, "Fire2 (pre-folded tier)" } }) })
add(driveSteps("shiva", SHIVA))
add({ checkEsper("shiva", SHIVA, { mag = 6, spd = 4, vig = -6 },
  { { ICE, "Ice (base tier)" }, { OSMOSE, "Osmose" }, { SHELL, "Shell" } },
  { { ICE2, "Ice2 (pre-folded tier)" }, { RASP, "Rasp (Ramuh's)" } }) })
add({ H.call(function() H.log("[esperstats] all scenarios passed") end) })

H.run({ maxFrames = 90000 }, all)   -- 7 scenarios, each a reload + menu equip + ride-in
