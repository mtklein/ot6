-- @suite sixcodex
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_sixcodex.lua -- a four-class save's revealed weapon classes, as the
-- six classes show them in battle (#566).
--
-- v0.51 split each of the four weapon classes in two (slash: Sword or
-- Katana; pierce: Dagger or Spear; bludgeon: Fist or Arcane; special: Arcane
-- or Dagger), and each species' four-class weakness became exactly one of
-- its two children (Ot6ClassSplitTbl).  A save from v0.50 or earlier holds
-- the four classes' revealed bits in its codex page (magic O8).  Its first
-- load on this ROM rewrites the page's class table for the six classes and
-- signs it O9 (ot6_codex.asm Ot6CodexSix, docs/design/save-layout.md "The
-- six-class codex"); the seed then shows a body only the revealed classes
-- its row answers to (Ot6SeedShields).
--
-- Boots a Mt. Kolts summit save (a save room; the cliff next door, map 98,
-- deals Trilium in every formation), handed to run.sh as
-- OT6_SRAM_CHECKPOINT.  configure.py runs it on two batteries and on six
-- mutant ROMs:
--   golden-saves/v0.46/kolts-summit-v1, as v0.46 published it: the file's
--     revealed classes hold a weakness that took its FIRST child and one
--     that took its SECOND, among the species the cliff deals;
--   golden-saves/junk/v0.46-kolts-classff, that save with every class byte
--     $FF (tools/golden_saves.py synthetic): every species then also holds a
--     revealed bit its row does not answer to (STALE), and four bits no
--     four-class build wrote, which the rewrite must DROP.
-- By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/golden-saves/v0.46/kolts-summit-v1 \
--     tools/tests/run.sh tools/tests/battle_sixcodex.lua build/lab/sixcodex.log
--
-- Played, through the real title screen, the field and the pad:
--   1. at power-on, before the game touches the battery, the slot's codex
--      page is read (the file's four-class bytes);
--   2. the title's Continue: the page is now signed O9, and the rewrite ran
--      once;
--   3. out of the save room onto the cliff and along it until a random
--      battle opens.  For every body in it, before anyone acts: the species'
--      class byte in the page against the file's byte and the ROM's split
--      byte, and the body's revealed classes ($3EA5 + slot*2) against the
--      page's byte masked by the body's row ($3EA4 + slot*2).  A FIRST
--      child, a SECOND child, a STALE bit and the DROPPED bits are each
--      asserted on the first body that carries one, by name.  The party
--      runs (L+R); nobody acts, so no reveal moves the page.  Battles go on
--      until each kind this battery must show has been seen, within the
--      number of encounters the cliff's pool can need (decoded from the
--      ROM: every formation holding a witness makes that one);
--   4. the console's Reset, the title, Continue again: the rewrite has
--      still run once, and step 3's battle again reads the same;
--   5. the whole page is the file's, migrated: every class byte, the
--      element table untouched.
--
-- Red on: Ot6CodexSix returning at once (the page is not signed O9); its
-- first children dropped (SixFirst); its second children dropped
-- (SixSecond); its four-bit mask gone (SixFour); the seed's row mask gone
-- (SixMask, ot6_break.asm); every load running the rewrite (LoadEnsure).
-- tools/build/mutant_rom.py, configure.py's negative edges.
--
-- The one write is the console's Reset (tools/state_write_waivers.txt).
local H = dofile("tools/tests/lib/ot6.lua")

local SLOT_PTR = { [1] = 0x0000, [2] = 0x0A00, [3] = 0x1400 }
local CODEX = 0x2000                               -- battery offset of slot 1's page
local CODEX_SIX, CODEX_FOUR = 0x394F, 0x384F       -- 'O9', 'O8'
local ELEMS, CLASSES, TABLES_END, SPECIES = 0x010, 0x190, 0x310, 384
local ROW, REVEALED = 0x3EA4, 0x3EA5               -- OT6_BP_CLASS, OT6_BOOST_REVEALED, monster 0
local KOLTS_SAVE, KOLTS_CLIFF = 103, 98            -- the summit's save room, the cliff east of it
local DOOR = { 59, 9 }                             -- the tile west of the room's east exit (60,9)
local CLIFF_DOOR = { 10, 10 }                      -- the cliff's way back into the room: never paced onto
local NAMES = { [0x01] = "Sword", [0x02] = "Dagger", [0x04] = "Fist", [0x08] = "Arcane", [0x10] = "Katana",
                [0x20] = "Spear" }
local OLD = { [0] = "slash", "pierce", "bludgeon", "special" }
local SECOND = { [0] = 0x10, 0x20, 0x08, 0x02 }

-- what this battery must show: the synthetic one every kind, a release's
-- save the two a real page holds
local CLASSFF = (OT6_SRAM_CHECKPOINT or ""):find("classff", 1, true) ~= nil
local WANT = CLASSFF and { "first", "second", "stale", "dropped" } or { "first", "second" }

local function bat(o) return (0x300000 + (o >> 13) * 0x10000) + 0x6000 + (o & 0x1FFF) end
local function sram(o) return emu.read(bat(o), emu.memType.snesMemory) end
local function sramW(o) return sram(o) | (sram(o + 1) << 8) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function classNames(b)
  local t = {}
  for _, bit in ipairs({ 0x01, 0x02, 0x20, 0x10, 0x04, 0x08 }) do
    if b & bit ~= 0 then t[#t + 1] = NAMES[bit] end
  end
  if b & 0xC0 ~= 0 then t[#t + 1] = string.format("+$%02X", b & 0xC0) end
  return #t > 0 and table.concat(t, "|") or "none"
end

-- ROM tables, read from the built ROM (never pinned here: the split may be
-- regenerated, and a row may change)
local function splitOf(sp) return H.readRomByte((H.sym("Ot6ClassSplitTbl") & 0x3FFFFF) + sp) end
local function sixClass(b, sel)
  local n = 0
  for k = 0, 3 do
    if (b >> k) & 1 == 1 then n = n | (((sel >> k) & 1 == 1) and SECOND[k] or (1 << k)) end
  end
  return n
end
-- a species' weak classes as the seed finds them: the first Ot6ShieldTbl
-- record naming it (species word, shields, classes), else the floor's byte
local function romRow(sp)
  local t = H.sym("Ot6ShieldTbl") & 0x3FFFFF
  for i = 0, 4095 do
    local w = H.readRomWord(t + i * 4)
    if w == 0xFFFF then break end
    if w == sp then return H.readRomByte(t + i * 4 + 3) & 0x3F end
  end
  return H.readRomByte((H.sym("OT6_FLOOR_CLASS") & 0x3FFFFF) + sp) & 0x3F
end

local slot, page, target
local F = {}                    -- the file's codex page, before the game touched the battery
local sixRuns = 0               -- Ot6CodexSix's entries
local seen = { first = 0, second = 0, stale = 0, dropped = 0 }
local encounters, budget, bodies = 0, nil, 0

-- which kinds one species carries, from the file's byte, the split and a row
local function kindsOf(sp, row)
  local old, sel = F[CLASSES + sp], splitOf(sp)
  local now = sixClass(old, sel)
  local k = {}
  for b = 0, 3 do
    if (old >> b) & 1 == 1 then
      local second = (sel >> b) & 1 == 1
      local child = second and SECOND[b] or (1 << b)
      if row & child ~= 0 then
        if second then k.second = k.second or { b, child } else k.first = k.first or { b, child } end
      end
    end
  end
  if now & ~row & 0x3F ~= 0 then k.stale = now & ~row & 0x3F end
  if old & 0xF0 ~= 0 then k.dropped = old & 0xF0 end
  return k, old, sel, now
end

local function atTarget()
  return not H.worldMode() and not H.menuRunning() and (H.mapId() & 0x1ff) == target.map
    and H.fieldX() == target.x and H.fieldY() == target.y
end

-- the title's Continue, pressing A until the party stands on the saved tile
local function continue(tag)
  local ph = 0
  return H.seqStep({
    H.waitFrames(350),
    H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
    H.waitFrames(120),
    H.withReset(H.driveUntil(function() return atTarget() and bright() >= 15 end, 2400, {
      H.call(function()
        ph = (ph + 1) % 48
        if atTarget() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, tag .. ": Continue slot -> the saved tile"), function() ph = 0 end),
    H.release(),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright() >= 15 end, 1800,
      tag .. ": control after the load", 1),
    H.waitFrames(30),
  })
end

local function assertLoaded(tag)
  H.log(string.format("[sixcodex] %s: slot %d's codex page: the file held $%04X, the page now $%04X; Ot6CodexSix "
    .. "has run %d time(s)", tag, slot, F[0] | (F[1] << 8), sramW(page), sixRuns))
  H.assertEq(sramW(page), CODEX_SIX, tag .. ": the slot's codex page is signed 'O9' after the load")
  H.assertEq(sixRuns, 1, tag .. ": the four-to-six rewrite has run once (a load of a page already O9 does not run it)")
end

-- the cliff's pool, decoded: how many encounters can pass before every
-- kind this battery must show has been met.  A slot counts for a kind only
-- when every formation it can deal holds a species carrying it.
local function poolBudget()
  local group = H.fieldEncounterGroup(KOLTS_CLIFF)
  local pool = H.encounterPool(group)
  local has = {}
  for s = 1, 4 do
    has[s] = {}
    local line = {}
    for _, kind in ipairs(WANT) do
      local all = true
      for _, fm in ipairs(pool[s].formations) do
        local any = false
        for _, sp in ipairs(fm.species) do
          if sp < SPECIES and kindsOf(sp, romRow(sp))[kind] then any = true end
        end
        all = all and any
      end
      has[s][kind] = all
      line[#line + 1] = kind .. "=" .. tostring(all)
    end
    H.log(string.format("[sixcodex] pool group %d slot %d (word $%04X, %d/256): %s", group, s, pool[s].word,
      pool[s].odds, table.concat(line, " ")))
  end
  local worst = H.worstCaseEncounters(function()
    local got = {}
    return function(s)
      local done = true
      for _, kind in ipairs(WANT) do
        got[kind] = got[kind] or has[s][kind]
        done = done and got[kind]
      end
      return done
    end
  end, 64)
  H.assertEq(worst < 64, true, "the cliff's pool can show every kind this battery must (" .. table.concat(WANT, ", ")
    .. "): the file's revealed classes, the ROM's split and its rows put a witness in reach")
  return worst
end

-- every body of the battle that just opened, before anyone acts
local function checkBattle(tag)
  H.assertEq(sixRuns, 1, tag .. ": the four-to-six rewrite has run once (the battle's own touches of the page do "
    .. "not run it again)")
  local n = 0
  for _, m in ipairs(H.activeSlots()) do
    local sp, s = m.species, m.slot
    if sp < SPECIES then
      n = n + 1
      local row, shown, held = H.readByte(ROW + s * 2) & 0x3F, H.readByte(REVEALED + s * 2), sram(page + CLASSES + sp)
      local k, old, sel, now = kindsOf(sp, row)
      H.log(string.format("[sixcodex] %s: body %d species %d: file $%02X split $%02X -> page $%02X (%s); row $%02X "
        .. "(%s); revealed $%02X (%s)", tag, s, sp, old, sel, held, classNames(held), row, classNames(row), shown,
        classNames(shown)))
      local who = string.format(" (species %d, body %d)", sp, s)
      if k.first then
        local c = k.first[2]
        H.assertEq(held & c, c, string.format("%s: FIRST child: revealed %s became %s in the page%s", tag,
          OLD[k.first[1]], NAMES[c], who))
        H.assertEq(shown & c, c, string.format("%s: FIRST child: %s is revealed in battle%s", tag, NAMES[c], who))
        seen.first = seen.first + 1
      end
      if k.second then
        local c = k.second[2]
        H.assertEq(held & c, c, string.format("%s: SECOND child: revealed %s became %s in the page%s", tag,
          OLD[k.second[1]], NAMES[c], who))
        H.assertEq(shown & c, c, string.format("%s: SECOND child: %s is revealed in battle%s", tag, NAMES[c], who))
        seen.second = seen.second + 1
      end
      H.assertEq(held, now, string.format("%s: DROPPED: the page's class byte is the file's four bits migrated and "
        .. "nothing else%s", tag, who))
      if k.dropped then seen.dropped = seen.dropped + 1 end
      if k.stale then
        H.assertEq(held & k.stale, k.stale, string.format("%s: STALE: the page keeps the revealed %s the row does "
          .. "not answer to%s", tag, classNames(k.stale), who))
        H.assertEq(shown & ~row & 0x3F, 0, string.format("%s: STALE: a revealed class the body's row does not "
          .. "answer to is not drawn%s", tag, who))
        seen.stale = seen.stale + 1
      end
      H.assertEq(shown, held & row, string.format("%s: the body's revealed classes are the page's, masked by its "
        .. "row%s", tag, who))
    end
  end
  H.assertEq(n > 0, true, tag .. ": the battle holds a body to read")
  bodies = bodies + n
end

local function wantMet()
  for _, kind in ipairs(WANT) do
    if seen[kind] == 0 then return false end
  end
  return true
end

-- from the save room onto the cliff, along it into a random battle, the
-- bodies read, and out again by running
local function cliffBattle(tag)
  local t, a, b = 0, nil, nil
  return H.seqStep({
    H.cond(function() return (H.mapId() & 0x1ff) == KOLTS_SAVE end, {
      H.navTo(DOOR[1], DOOR[2], { maxFrames = 3000 }),
      H.driveUntil(function() t = t + 1; return (H.mapId() & 0x1ff) == KOLTS_CLIFF end, 1800, {
        H.call(function()
          if not H.hasControl() then H.setPad({}); return end
          H.setPad({ "right" })
        end),
      }, tag .. ": the save room's east exit -> the cliff (map 98)"),
      H.release(),
      H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900, tag .. ": control on the cliff", 10),
    }, {}),
    H.waitFrames(20),
    -- a lane to pace: from where the party stands to a tile two or three
    -- off that the walk reaches, away from the door back into the room
    H.call(function()
      H.assertEq(H.mapId() & 0x1ff, KOLTS_CLIFF, tag .. ": the party is on the cliff (map 98)")
      local x0, y0 = H.fieldX(), H.fieldY()
      a, b = { x0, y0 }, nil
      for _, d in ipairs({ { 3, 0 }, { 2, 0 }, { 0, 3 }, { 0, -3 }, { 0, 2 }, { 0, -2 }, { 3, -1 }, { 2, -1 },
                           { 3, 1 }, { 2, 1 }, { 4, -1 }, { 4, 0 } }) do
        local x, y = x0 + d[1], y0 + d[2]
        if b == nil and not (x == CLIFF_DOOR[1] and y == CLIFF_DOOR[2]) and H.bfsPath(x, y) then b = { x, y } end
      end
      H.log(string.format("[sixcodex] %s: on the cliff at (%d,%d); pacing to %s", tag, x0, y0,
        b and string.format("(%d,%d)", b[1], b[2]) or "nowhere"))
      H.assertEq(b ~= nil, true, string.format("%s: a tile to pace to from (%d,%d) on the cliff", tag, x0, y0))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.navTo(function() return b[1] end, function() return b[2] end,
        { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() a, b = b, a end),
    }, tag .. ": a random battle on the cliff"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.waitFrames(30),
    H.call(function()
      encounters = encounters + 1
      checkBattle(tag .. " battle " .. encounters)
    end),
    H.fleeBattle(9000),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, tag .. ": control after the run", 5),
  })
end

H.run({ maxFrames = 200000 }, {
  H.call(function()
    local six = H.sym("Ot6CodexSix")
    emu.addMemoryCallback(function() sixRuns = sixRuns + 1 end, emu.callbackType.exec, six, six)
    slot = sram(0x1FF0)
    H.assertEq(slot, 3, "the battery last saved slot 3 ($1FF0), as every release save does")
    page = CODEX + (slot - 1) * 0x400
    for o = 0, 0x3FF do F[o] = sram(page + o) end
    local base = SLOT_PTR[slot]
    local word = sram(base + 0x1F64 - 0x1600) | (sram(base + 0x1F65 - 0x1600) << 8)
    target = { map = word & 0x1ff, x = sram(base + 0x1FC0 - 0x1600), y = sram(base + 0x1FC1 - 0x1600) }
    H.assertEq(target.map, KOLTS_SAVE, "the battery's save stands in the Mt. Kolts summit save room (map 103)")
    H.assertEq(F[0] | (F[1] << 8), CODEX_FOUR, "the battery's codex page is a four-class page ('O8')")
    local n, hi = 0, 0
    for sp = 0, SPECIES - 1 do
      if F[CLASSES + sp] ~= 0 then n = n + 1 end
      if F[CLASSES + sp] & 0xF0 ~= 0 then hi = hi + 1 end
    end
    H.log(string.format("[sixcodex] the file: slot %d on map %d at (%d,%d); %d species with revealed classes, %d "
      .. "with bits past the four; this battery must show: %s", slot, target.map, target.x, target.y, n, hi,
      table.concat(WANT, ", ")))
    H.assertEq(sixRuns, 0, "nothing has run the rewrite before the title")
  end),
  continue("load1"),
  H.call(function()
    assertLoaded("load1")
    budget = poolBudget()
    H.log(string.format("[sixcodex] the cliff's pool shows every kind within %d encounter(s), whatever the counters "
      .. "hold", budget))
  end),
  H.driveUntil(function() return wantMet() end, 180000, {
    H.call(function()
      H.assertEq(encounters < budget, true, string.format("every kind is met within the pool's %d encounter(s) "
        .. "(met so far: first %d, second %d, stale %d, dropped %d)", budget, seen.first, seen.second, seen.stale,
        seen.dropped))
    end),
    cliffBattle("load1"),
  }, "battles until every kind has been seen"),
  H.call(function()
    for _, kind in ipairs(WANT) do
      H.assertEq(seen[kind] > 0, true, "a body carrying a " .. kind .. " case was read in battle")
    end
    H.log(string.format("[sixcodex] load1: %d encounter(s), %d bodies; first %d, second %d, stale %d, dropped %d; "
      .. "the console's Reset", encounters, bodies, seen.first, seen.second, seen.stale, seen.dropped))
    H.expectTitle("battle_sixcodex: the console's Reset before the second load")
    emu.reset()
  end),
  -- the second load: the page is O9 already, so nothing is rewritten
  continue("load2"),
  H.call(function() assertLoaded("load2") end),
  cliffBattle("load2"),
  H.call(function()
    local classes, elems = 0, 0
    for sp = 0, SPECIES - 1 do
      if sram(page + CLASSES + sp) ~= sixClass(F[CLASSES + sp], splitOf(sp)) then classes = classes + 1 end
      if sram(page + ELEMS + sp) ~= F[ELEMS + sp] then elems = elems + 1 end
    end
    H.assertEq(sixRuns, 1, "after the second load and its battle the four-to-six rewrite has still run once")
    H.assertEq(classes, 0, "every class byte of the page is the file's, migrated (no reveal was earned: nobody acted)")
    H.assertEq(elems, 0, "the page's element table is the file's")
    H.assertEq(sramW(page), CODEX_SIX, "the page is still signed 'O9'")
    H.log(string.format("[sixcodex] PASS: %d encounter(s), %d bodies read; first %d, second %d, stale %d, dropped "
      .. "%d; the rewrite ran %d time", encounters, bodies, seen.first, seen.second, seen.stale, seen.dropped,
      sixRuns))
  end),
})
