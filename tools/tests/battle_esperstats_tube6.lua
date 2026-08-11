-- @suite savestate=minecart_entry slow
-- battle_esperstats_tube6.lua -- the six tube-room stones, in battle
-- (docs/design/magicite-tube-six.md, issue #31): Maduin, Shoat, Phantom,
-- Carbunkl, Bismark and Unicorn grant their designed spell lists live and
-- carry a while-worn stat mod, where before all six were vanilla placeholder
-- rows with an Ot6EsperStatTbl byte of $00.
--
-- Same instrument and same shape as battle_esperstats.lua: each scenario
-- reloads the fixture, equips its stone through the real field menu on the
-- party leader, rides the minecart into the first scripted fight, and reads
-- the granted union out of the compacted master Magic list plus the four
-- battle-side effective stat copies.  That file is the shipped test for the
-- eight stones it already covers; this is the v0.7 append for the six the
-- tube room grants.
--
-- =============== the input-driven rebuild (#75) ===========================
-- The previous version poked char 0's equipped-esper byte $161e on
-- battle_entry, the Narshe intro, three chapters before these stones
-- exist, where the menu could never have equipped one.  The poke is gone,
-- and the fixture is now minecart_entry, the first state on the chain where
-- this file's scenario is real play: it sits one step after the tube-room
-- set piece that grants all six stones at once ($1A69 = EF 01 9A 00 here),
-- and one A-press at CID starts the minecart ride whose scripted first fight
-- (battle 41, ~1240 frames in) is the measuring ground.  The tube room's
-- own door back to map 273 is one-way (measured), so no random-encounter
-- map is reachable past the grant; the scripted fight is the battle a
-- player reaches, and it is deterministic and input-only.
--
-- The controls are stronger on this fixture, and one sign flipped.  The
-- party is LOCKE, SABIN and EDGAR: NaturalMagic teaches only TERRA and
-- CELES, and Celes was taken by the tube-room scene one step earlier.  So
-- the BASE union is asserted empty, and:
--   * "Maduin grants Fire" was corroboration on the old fixture, since Terra
--     knows Fire innately at Narshe; here it is proof, as his Ice
--     and Bolt already were.  The old file's `Fire IS innate here` positive
--     assert is therefore gone, replaced by Fire in the base absent-controls:
--     the note it kept true is no longer true, and that is intended.
--   * "Bismark does not grant Fire" was not assertable before and was
--     documented as omitted; it is assertable here and is now asserted
--     (genju_prop.asm:150-151, "FIRE/ICE/BOLT dropped: Maduin's job").
-- Nothing was weakened: every absent-control the old BASE could make, this
-- BASE makes too.
--
-- The union window stays rows 1..54 (this file's own approach, adopted
-- back into battle_esperstats.lua by #75): row 0 is the esper row, whose
-- id byte holds the esper index, and MADUIN is esper 6 while ICE_2 is
-- spell $06, which is the collision that motivated the window; rows 55..78
-- are lores stored id-$8b.  Row 0 is asserted directly to hold the
-- equipped esper's index, which is the positive control for the window.
--
-- The measured character is whoever leads the party (EDGAR on this savestate),
-- found from live menu RAM rather than assumed; stat deltas are against the
-- BASE scenario for the same character.  Vigor is stored doubled ($3b2c,
-- "vigor * 2", battle_main.asm:3857), so Bismark's authored +5 reads +10
-- and the -2 and -3 downsides read -4 and -6.
--
-- The three broken rows this file exists to catch are unchanged:
--   * Maduin carried FIRE_2/ICE_2/BOLT_2, three dead pre-folded tiers at
--     once; all three must be absent and the base tiers present.
--   * Bismark granted LIFE against kits.md's revival rule
--     ("Terra, Fenix Downs, and Sraphim, and nowhere else"), so Life is
--     asserted absent.
--   * Shoat granted BIO, the pre-folded cap of the poison family, also absent.
-- Run this file against a ROM built before the genju_prop change and the
-- absent-checks fail; that is what they are for.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/minecart_entry.mss.lua"

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

local LIST0  = 0x208e            -- compacted master Magic list, 4-byte records
local STAM, MAGPWR, SPEED, VIGOR = 0x3b40, 0x3b41, 0x3b19, 0x3b2c

-- field menu plumbing (menu_ram.inc; the menu_esperdetail walk)
local ZMENUSTATE, ZCURSOR, ZSELINDEX, ZLISTTYPE = 0x26, 0x4b, 0x28, 0x2a
local ZCHARID, Z99 = 0x69, 0x99
local SKILLCOLOR = 0x79
local GENJULIST = 0x9d89
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local function st() return H.readByte(ZMENUSTATE) end
local function rec(c) return 0x1600 + 37 * c end
local ESPER_OFF = 0x1E

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

-- rows 1..54 only: the spell window (see header)
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
local leader = nil

-- two-column esper list seek (menu_esperdetail's idiom)
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

local function equipSteps(tag, esper)
  return {
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu (" .. tag .. ")"),
    H.waitFrames(20),
    H.pressButtons({ "down" }, 2),
    H.waitFrames(6),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300,
      "character select (" .. tag .. ")", 5),
    H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(ZCHARID + 0), leader,
        "[" .. tag .. "] the char menu's slot 0 is the field party's leader")
    end),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300,
      "skills submenu (" .. tag .. ")", 5),
    H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(ZSELINDEX), 0,
        "[" .. tag .. "] the confirm latched party slot 0")
      H.assertEq(H.readByte(SKILLCOLOR), 0x20,
        "[" .. tag .. "] the Espers row is enabled")
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
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "detail (" .. tag .. ")"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.readByte(Z99), esper,
        "[" .. tag .. "] the detail page is the right stone's")
    end),
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
      -- Log the full granted set before any assertion fires.  A run against
      -- a pre-change ROM must leave the evidence in the log, not only a
      -- verdict.
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
    -- LOCKE, SABIN and EDGAR know no natural magic (NaturalMagic covers only
    -- Terra and Celes, and the tube room took Celes), so the union is empty.
    -- The old fixture's "Fire IS innate here" note does not apply here: on
    -- this party Fire is a clean control like everything else.
    H.assertEq(setSize(b.union), 0,
      "[base] the spell union is EMPTY -- no innate mage in the party, "
      .. "so every grant below including Fire is proof")
    for _, s in ipairs({
      { FIRE, "Fire" }, { ICE, "Ice" }, { BOLT, "Bolt" },
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
  end)
end

-- #62's shape: all four stats asserted every scenario; a key left out means
-- the stat is expected flat; a negative delta must be seen dropping.  vig
-- deltas are given doubled, as $3b2c stores them.
local function checkEsper(tag, esper, deltas, grants, absents)
  return H.call(function()
    local b, r = R.base, R[tag]
    -- Positive control: list record 0 is the esper row, whose id byte
    -- is the esper index.  That is why the union starts at row 1.
    H.assertEq(r.row0, esper, "[" .. tag .. "] list record 0 holds the esper index")
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

-- Maduin -- "the Trinity", the largest package, on #62's boss tier: +7 mag.pwr
-- (the encoding's ceiling and vanilla's own per-stat ceiling), +3 stamina, -3
-- vigor (-6 doubled) because Terra's inheritance is a mage's.  All three
-- grants are fold base tiers and all three are assertable on this fixture; the
-- three pre-folded tiers the vanilla row carried are the broken-row fix.
add(driveSteps("maduin", MADUIN))
add({ checkEsper("maduin", MADUIN, { mag = 7, stam = 3, vig = -6 },
  { { FIRE, "Fire (base tier -- PROOF here, no innate mage)" },
    { ICE, "Ice (base tier)" }, { BOLT, "Bolt (base tier)" } },
  { { FIRE2, "Fire2 (dead pre-folded tier -- BROKEN ROW FIX)" },
    { ICE2, "Ice2 (dead pre-folded tier -- BROKEN ROW FIX)" },
    { BOLT2, "Bolt2 (dead pre-folded tier -- BROKEN ROW FIX)" } }) })

-- Shoat -- "the Gorgon Eye", story tier: +6 speed, +2 stamina, -2 vigor
-- (-4 doubled), since the Eye is a stare rather than a strike.  Bio absent is
-- the broken-row fix.
add(driveSteps("shoat", SHOAT))
add({ checkEsper("shoat", SHOAT, { spd = 6, stam = 2, vig = -4 },
  { { BREAK, "Break" }, { DOOM, "Doom" } },
  { { BIO, "Bio (pre-folded poison cap -- BROKEN ROW FIX)" } }) })

-- Bismark -- "the Tide", story tier: +5 vigor (+10 doubled), +3 stamina, and
-- -2 speed, since the leviathan is mass.  Life absent is the kits.md
-- revival rule, asserted.  Fire/Ice/Bolt are all "Maduin's job"
-- (genju_prop.asm:150-151) and on this fixture all three are assertable;
-- the old file had to omit Fire because Terra knew it innately.
add(driveSteps("bismark", BISMARK))
add({ checkEsper("bismark", BISMARK, { vig = 10, stam = 3, spd = -2 },
  { { HASTE, "Haste (fold base)" }, { SLOW, "Slow (fold base)" } },
  { { LIFE, "Life (kits.md revival rule -- BROKEN ROW FIX)" },
    { FIRE, "Fire (Maduin's job -- newly assertable on this party)" },
    { ICE, "Ice (Maduin's job)" }, { BOLT, "Bolt (Maduin's job)" } }) })

-- Carbunkl -- "the Facet", story tier: +6 stamina (the wall stone's stat),
-- +2 mag.pwr, -2 speed because a gem is inert.
add(driveSteps("carbunkl", CARBUNKL))
add({ checkEsper("carbunkl", CARBUNKL, { stam = 6, mag = 2, spd = -2 },
  { { RFLECT, "Rflect" }, { SAFE, "Safe" } },
  { { WARP, "Warp (field furniture)" }, { SHELL, "Shell (Shiva's)" },
    { HASTE, "Haste (moved to Bismark)" } }) })

-- Phantom -- "the Ghostwalk", story tier: +6 speed, +2 mag.pwr, -2 stamina.
-- It shares Shoat's +6 speed lead deliberately
-- and separates on the second stat and the downside (magicite-tube-six.md §3).
add(driveSteps("phantom", PHANTOM))
add({ checkEsper("phantom", PHANTOM, { spd = 6, mag = 2, stam = -2 },
  { { VANISH, "Vanish" }, { DEMI, "Demi" } },
  { { BSERK, "Bserk (removes player control -- the Ifrit reason)" } }) })

-- Unicorn -- "the Purity", story tier and deliberately its smallest package
-- with no downside: +5 stamina, +2 mag.pwr.  Pearl is branch A of the
-- cross-doc holy decision, decided by the dispatcher (magicite-tube-six.md
-- §9): if this row is ever reverted to branch B, this assertion is the
-- thing that has to be deliberately edited.
add(driveSteps("unicorn", UNICORN))
add({ checkEsper("unicorn", UNICORN, { stam = 5, mag = 2 },
  { { PEARL, "Pearl (branch A -- the paladin's smite)" }, { REMEDY, "Remedy" } },
  { { CURE2, "Cure2 (dead pre-folded tier)" }, { SAFE, "Safe (-> Carbunkl)" },
    { SHELL, "Shell (Shiva's)" }, { DISPEL, "Dispel (branch B's row)" } }) })

add({ H.call(function()
  H.log("[esperstats-tube6] all six tube-room stones grant their designed "
    .. "lists and carry their designed stat mods")
end) })

H.run({ maxFrames = 90000 }, all)   -- 7 scenarios, each a reload + menu equip + ride-in
