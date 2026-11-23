-- @suite golden
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- save_golden.lua -- a release's battery save loads, plays and saves on today's ROM (#389).
--
-- One run per golden save (tools/tests/golden-saves/<version>/<key>/, a battery
-- a published release shipped in its saves/ folder).  configure.py gives each
-- fixture its own edge (tools/build/run_golden_save.sh), which hands the
-- battery to run.sh as OT6_SRAM_CHECKPOINT and then has tools/golden_saves.py
-- check this run's log and the battery it leaves against the fixture file.
-- By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/golden-saves/v0.44/wor-cyan-v1 \
--     tools/tests/run.sh tools/tests/save_golden.lua build/lab/golden.log
--
-- Played, all through the real title screen and menus:
--   1. at power-on, before the game touches the battery, the whole 32 KiB is
--      read (B0);
--   2. the title's Continue loads the slot the battery last saved
--      ($307FF0), until the party stands on that slot's saved tile with
--      control;
--   3. the loaded game is read out (the $1600-$1FFF block as the Continue's
--      confirm hands it to the field, the slot's codex page, the live esper
--      page) for golden_saves.py, and asserted here: the block is the
--      slot's bytes, the
--      codex page is the one the battery held, migrated (#566: a page from
--      v0.50 or earlier holds the four weapon classes' revealed bits, and
--      the load rewrites them for the six by the ROM's Ot6ClassSplitTbl and
--      signs the page O9; that rewrite, Ot6CodexSix, ran once), and the live
--      esper page is
--      the slot's (a signed page) or empty (an unsigned one: a save from
--      before v0.44), its row 12 (actor 12) the slot's only for a block of
--      layout version 2 or more and no progress for any older one;
--   4. the game is saved into the same slot through the Save menu (a save
--      point or the world map, where the battery was saved), and the slot's
--      esper page now carries the live page, signed; the saved block is
--      the block the save was handed (read at CopyGameDataToSRAM's entry)
--      but for play time, timers and checksum, and, when that block was
--      unsigned (a save from before v0.45), the signature and the zeroed
--      reserve and tail, or when it was signed at version 1 (v0.45-v0.50),
--      the version raised to 2; the loadouts, junk ones included, are
--      untouched;
--   5. the console's Reset, the title, Continue again: the reload is the
--      saved block, the live esper page is what was saved, and the codex
--      page is as the first load left it (the rewrite has still run once,
--      here and after every save below);
--   6. saved again: a signed block, so only play time, timers and checksum
--      move;
--   7. a golden-saves/junk/ fixture is also saved over slot 1: slot 1's
--      page pads and tails zero, its codex slot 3's, its esper page the
--      live page, and slot 3's pages and $4000-$7FFF untouched.
-- golden_saves.py then holds the readouts to what tools/roster.py reads from
-- the fixture file (party, levels, gear, gil, bag, story position), the
-- codex and esper pages to the file's, and the battery the run leaves to
-- the fixture byte for byte outside the ranges docs/design/save-layout.md
-- says today's ROM writes.
--
-- The one write is the console's Reset (tools/state_write_waivers.txt).
local H = dofile("tools/tests/lib/ot6.lua")

local SLOT_PTR = { [1] = 0x0000, [2] = 0x0A00, [3] = 0x1400 }
local CODEX, ESPER, LIVE = 0x2000, 0x3000, 0x3C00   -- battery offsets
local ESPER_MAGIC, CODEX_MAGIC = 0x3145, 0x394F   -- 'E1'; 'O9', a six-class codex page
local CODEX_FOUR, CODEX_GLOBAL = 0x384F, 0x374F   -- 'O8' (v0.5-v0.50), 'O7' (v0.1-v0.4)
local ELEMS, CLASSES, TABLES_END, SPECIES = 0x010, 0x190, 0x310, 384
local CTR, CTR_END = 0x0010, 0x02B4               -- esper page: 13 actors x 26 words
local LEO = 0x0280                                -- row 12 (actor 12), read from a version-2 block only
-- The loaded block is read where the Continue's confirm hands the game to
-- the field (Ot6EsperContinue, field_menu.asm MenuState_23): the menu has
-- copied the slot into $1600-$1FFF and nothing has run on it yet.  From
-- there the field's own play moves bytes at once (the map's events, the
-- random byte, object and position caches: measured on the first runs,
-- build/attempts/wt/v1-save-freeze/), so a read after control would not be
-- the load.
local loaded, hooked = nil, false
-- And the block a save is about to write, read at CopyGameDataToSRAM's
-- entry, before Ot6SaveSign: what the save may change from it is the play
-- time, the timers, the checksum, and (signing an unsigned block) the
-- signature and the reserve.
local presave = nil
local sixRuns = 0       -- Ot6CodexSix's entries: the four-to-six class rewrite of a codex page
local function hook()
  if hooked then return end
  hooked = true
  local at = H.sym("Ot6EsperContinue")
  emu.addMemoryCallback(function()
    loaded = {}
    for a = 0x1600, 0x1FFF do loaded[a] = H.readByte(a) end
  end, emu.callbackType.exec, at, at)
  local six = H.sym("Ot6CodexSix")
  emu.addMemoryCallback(function() sixRuns = sixRuns + 1 end, emu.callbackType.exec, six, six)
  local sv = H.sym("CopyGameDataToSRAM")
  emu.addMemoryCallback(function()
    presave = {}
    for a = 0x1600, 0x1FFF do presave[a] = H.readByte(a) end
  end, emu.callbackType.exec, sv, sv)
end
local SIG, SIGWORD, VER = 0x1E2C, 0x5653, 2
local function inRange(a, lo, hi) return a >= lo and a <= hi end
local function saveSets(a) -- what CopyGameDataToSRAM itself writes into the block
  return inRange(a, 0x1863, 0x1865) or inRange(a, 0x1FA8, 0x1FBF) or inRange(a, 0x1FFE, 0x1FFF)
end
local function signSets(a) -- what the first signing writes
  return inRange(a, 0x1E2C, 0x1E3F) or inRange(a, 0x1FF7, 0x1FFD)
end

-- battery offset -> SNES address: four 8 KiB windows at $6000 of banks $30-$33
local function bat(o) return (0x300000 + (o >> 13) * 0x10000) + 0x6000 + (o & 0x1FFF) end
local function sram(o) return emu.read(bat(o), emu.memType.snesMemory) end
local function sramW(o) return sram(o) | (sram(o + 1) << 8) end
local function battery()
  local t = {}
  for o = 0, 0x7FFF do t[o] = sram(o) end
  return t
end
local function hex(get, lo, n)
  local s = {}
  for i = 0, n - 1 do s[#s + 1] = string.format("%02X", get(lo + i)) end
  return table.concat(s)
end
-- print a range as [golden] dump lines, 64 bytes each, for golden_saves.py
local function dump(tag, what, get, lo, n)
  for a = lo, lo + n - 1, 64 do
    local k = math.min(64, lo + n - a)
    print(string.format("[golden] dump %s %s %04X %s", tag, what, a, hex(get, a, k)))
  end
end

local B0, B1, slot, target
local function slotByte(B, a) return B[SLOT_PTR[slot] + (a - 0x1600)] end
local function bw(B, o) return B[o] | (B[o + 1] << 8) end

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function atTarget()
  if target.world then
    return H.worldMode() and H.worldX() == target.x and H.worldY() == target.y
  end
  return not H.worldMode() and not H.menuRunning() and (H.mapId() & 0x1ff) == target.map
    and H.fieldX() == target.x and H.fieldY() == target.y
end
local function control()
  if H.worldMode() then return H.worldHasControl() end
  return H.hasControl() and H.tileAligned()
end

-- the title's Continue, pressing A until the party stands on the saved tile
-- (the load menu's cursor starts on the last saved slot)
local function continue(tag)
  local ph, n = 0, 0
  return H.seqStep({
    H.waitFrames(350),
    H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
    H.waitFrames(120),
    H.withReset(H.driveUntil(function()
      n = n + 1
      return atTarget() and bright() >= 15
    end, 2400, {
      H.call(function()
        ph = (ph + 1) % 48
        if atTarget() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, tag .. ": Continue slot -> the saved tile"), function() ph, n = 0, 0 end),
    H.release(),
    H.waitUntil(function() return control() and bright() >= 15 end, 1800, tag .. ": control after the load", 1),
    H.waitFrames(30),
  })
end

-- the loaded block against a battery's slot
local function assertBlock(tag, B)
  H.assertEq(loaded ~= nil, true, tag .. ": the Continue's confirm ran Ot6EsperContinue")
  local bad = 0
  for a = 0x1600, 0x1FFF do
    local want, got = slotByte(B, a), loaded[a]
    if want ~= got then
      bad = bad + 1
      if bad <= 12 then
        H.log(string.format("[golden] %s: $%04X loaded %02X, the slot holds %02X", tag, a, got, want))
      end
    end
  end
  H.assertEq(bad, 0, tag .. ": the loaded $1600-$1FFF block is the slot's, byte for byte")
end

local function esperPage(B, base)
  local t = {}
  for o = CTR, CTR_END - 1 do t[o] = B and B[base + o] or sram(base + o) end
  return t
end
-- Row 12 (actor 12, Gogo's slot revealed as Leo; #552 piece F) is the slot's only when the slot's block is
-- signed with layout version 2 or more (Ot6EsperLeoRow); an older block's page held reserve there (junk in a
-- junk/ fixture), which must load as no progress.
local function blockVer(B)
  local function g(a) return slotByte(B, a) end
  if (g(SIG) | (g(SIG + 1) << 8)) ~= SIGWORD or g(SIG + 2) < 1 or g(SIG + 2) > VER then return 0 end
  return g(SIG + 2)
end
local function assertLive(tag, B)
  local page = ESPER + (slot - 1) * 0x400
  local signed = bw(B, page) == ESPER_MAGIC
  local leoHeld = signed and blockVer(B) >= 2
  H.assertEq(sramW(LIVE), ESPER_MAGIC, tag .. ": the live esper page is signed")
  local sum, bad, leoSum, leoPage, leoBad = 0, 0, 0, 0, 0
  for o = CTR, CTR_END - 1 do
    local held = o < LEO and signed or o >= LEO and leoHeld
    local want = held and B[page + o] or 0
    local got = sram(LIVE + o)
    sum = sum + got
    if o >= LEO then
      leoSum, leoPage = leoSum + got, leoPage + B[page + o]
      if want ~= got then leoBad = leoBad + 1 end
    elseif want ~= got then bad = bad + 1 end
  end
  H.log(string.format("[golden] %s: slot %d's esper page is %s; the live page sums %d", tag, slot,
    signed and "signed" or "unsigned (reads as no progress)", sum))
  H.log(string.format("[golden] %s: the block is layout version %d, so row 12 is %s: the slot's row sums %d, the "
    .. "live row %d", tag, blockVer(B), leoHeld and "the slot's" or "no progress", leoPage, leoSum))
  H.assertEq(bad, 0, tag .. ": the live esper page is " .. (signed and "the slot's page" or "empty"))
  H.assertEq(leoBad, 0, tag .. ": the live row 12 is " .. (leoHeld and "the slot's row 12" or
    "no progress (a block older than version 2)"))
end

-- A four-class revealed byte as the six classes hold it (#566,
-- ot6_codex.asm Ot6CodexSix): each of bits 0-3 becomes its second child
-- (Katana, Spear, Arcane, Dagger) where the species' Ot6ClassSplitTbl byte
-- has that bit, its first (Sword, Dagger, Fist, Arcane: the same bit)
-- otherwise; every other bit is dropped.  The table is the built ROM's.
local SECOND = { [0] = 0x10, 0x20, 0x08, 0x02 }
local function sixClass(b, sel)
  local n = 0
  for k = 0, 3 do
    if (b >> k) & 1 == 1 then n = n | (((sel >> k) & 1 == 1) and SECOND[k] or (1 << k)) end
  end
  return n
end
local function splitOf(sp) return H.readRomByte((H.sym("Ot6ClassSplitTbl") & 0x3FFFFF) + sp) end

-- The slot's codex page as the load must leave it, from battery B (the
-- file's, before the game touched it): an O9 page as it is; an O8 page with
-- its class table rewritten; anything else zeroed (no golden save holds an
-- O7 cartridge-wide codex, asserted).  The pad and the tail are B's: a save
-- zeroes them, not a load.  Returns the page and what kind it was.
local function codexLoaded(B)
  local page = CODEX + (slot - 1) * 0x400
  local magic = bw(B, page)
  H.assertEq(bw(B, CODEX) ~= CODEX_GLOBAL, true, "the battery holds no O7 cartridge-wide codex at page 1")
  local t = {}
  for o = 0, 0x3FF do t[o] = B[page + o] end
  local kind = "six"
  if magic == CODEX_FOUR then
    kind = "four"
    for sp = 0, SPECIES - 1 do t[CLASSES + sp] = sixClass(B[page + CLASSES + sp], splitOf(sp)) end
  elseif magic ~= CODEX_MAGIC then
    kind = "unsigned"
    for o = ELEMS, TABLES_END - 1 do t[o] = 0 end
  end
  t[0], t[1] = CODEX_MAGIC & 0xFF, CODEX_MAGIC >> 8
  return t, kind
end

-- load1: the page is the file's, migrated (the title's Continue ensures
-- the slot's page: Ot6EsperContinue -> Ot6CodexLoaded), and the rewrite ran
-- once for a four-class page and not at all for any other.
local wantSix = 0
local function assertCodexLoaded(tag, B)
  local page = CODEX + (slot - 1) * 0x400
  local want, kind = codexLoaded(B)
  wantSix = (kind == "four") and 1 or 0
  local n, first, second, lost, kept = 0, 0, 0, 0, 0
  for o = ELEMS, TABLES_END - 1 do if sram(page + o) ~= 0 then n = n + 1 end end
  H.log(string.format("[golden] %s: slot %d's codex page was a %s-class page ($%04X in the file); it holds %d "
    .. "revealed bytes, magic $%04X; Ot6CodexSix ran %d time(s)", tag, slot, kind, bw(B, page), n, sramW(page),
    sixRuns))
  H.assertEq(sramW(page), CODEX_MAGIC, tag .. ": the slot's codex page is signed 'O9'")
  H.assertEq(sixRuns, wantSix, tag .. ": the four-to-six rewrite ran once for a four-class page (never for another)")
  local elems, classes, rest = 0, 0, 0
  for o = 2, 0x3FF do
    local got = sram(page + o)
    if got ~= want[o] then
      if o >= CLASSES and o < TABLES_END then
        classes = classes + 1
        if classes <= 6 then
          H.log(string.format("[golden] %s: species %d's classes: the file holds %02X (split %02X), expected %02X, "
            .. "the page holds %02X", tag, o - CLASSES, B[page + o], splitOf(o - CLASSES), want[o], got))
        end
      elseif o >= ELEMS and o < CLASSES then elems = elems + 1
      else rest = rest + 1 end
    end
    if o >= CLASSES and o < TABLES_END and kind == "four" then
      local old, sel = B[page + o] & 0x0F, splitOf(o - CLASSES)
      if old & ~sel & 0x0F ~= 0 then first = first + 1 end
      if old & sel ~= 0 then second = second + 1 end
    end
  end
  H.log(string.format("[golden] %s: of the file's revealed classes, %d species hold a first child and %d a second",
    tag, first, second))
  H.assertEq(classes, 0, tag .. ": the slot's revealed classes are the file's, migrated to the six classes")
  H.assertEq(elems, 0, tag .. ": the slot's revealed elements are the file's")
  H.assertEq(rest, 0, tag .. ": the load left the codex page's pad and tail as the battery held them")
end

-- load2, and after each save: the page is what battery B held (already
-- six-class), and no later touch ran the rewrite again.
local function assertCodex(tag, B)
  local page = CODEX + (slot - 1) * 0x400
  local bad, n = 0, 0
  for o = 0, 0x3FF do
    if sram(page + o) ~= B[page + o] then bad = bad + 1 end
    if o >= 0x10 and o < 0x310 and sram(page + o) ~= 0 then n = n + 1 end
  end
  H.log(string.format("[golden] %s: slot %d's codex page holds %d revealed bytes, magic $%04X; Ot6CodexSix has run "
    .. "%d time(s)", tag, slot, n, sramW(page), sixRuns))
  H.assertEq(sramW(page), CODEX_MAGIC, tag .. ": the slot's codex page is signed 'O9'")
  H.assertEq(sixRuns, wantSix, tag .. ": the four-to-six rewrite has run once, at the first load, and not again")
  H.assertEq(bad, 0, tag .. ": the slot's codex page is the one the battery held")
end

-- after a save: the slot's codex magic and tables are the ones the load
-- left (a save zeroes only the page's pad and tail), and the save's own
-- touch (Ot6CodexSaveAs -> Ot6CodexEnsure) did not run the rewrite again
local loadedPage
local function snapCodex()
  loadedPage = {}
  local page = CODEX + (slot - 1) * 0x400
  for o = 0, 0x3FF do loadedPage[o] = sram(page + o) end
end
local function assertCodexKept(tag, B)
  local page = CODEX + (slot - 1) * 0x400
  local bad = 0
  for o = 0, TABLES_END - 1 do
    if (o < 2 or o >= ELEMS) and B[page + o] ~= loadedPage[o] then bad = bad + 1 end
  end
  H.assertEq(sixRuns, wantSix, tag .. ": the four-to-six rewrite has run once, at the first load, and not again")
  H.assertEq(bad, 0, tag .. ": the slot's codex magic and tables are the ones the first load left")
end

-- Signed, as Ot6SaveSign decides it: the signature and a version 1..VER.
local function signedBlock(get)
  return (get(SIG) | (get(SIG + 1) << 8)) == SIGWORD and get(SIG + 2) >= 1 and get(SIG + 2) <= VER
end

-- The block a save wrote, against the block it was handed (read at
-- CopyGameDataToSRAM's entry): byte for byte what Ot6SaveSign makes of it,
-- but for what the save itself writes (play time, timers, checksum).  A
-- first signing sets the signature and version and zeroes the reserve and
-- the tail; a signed block keeps all of them but a lower version, which the
-- save raises to VER (#552: version 1 -> 2).  The loadouts are never edited
-- (owner, 2026-11-15: no repair by inference), junk ones included.
local function assertSaved(tag, B, firstSign, s)
  s = s or slot
  local function sb(a) return B[SLOT_PTR[s] + (a - 0x1600)] end
  H.assertEq(presave ~= nil, true, tag .. ": the save ran CopyGameDataToSRAM")
  H.assertEq(sb(SIG) | (sb(SIG + 1) << 8), SIGWORD, tag .. ": the saved block is signed ($5653)")
  H.assertEq(sb(SIG + 2), VER, tag .. ": ... with layout version " .. VER)
  local want = {}
  for a = 0x1600, 0x1FFF do want[a] = presave[a] end
  local raise = not firstSign and presave[SIG + 2] < VER
  if raise then want[SIG + 2] = VER end
  if firstSign then
    want[SIG], want[SIG + 1], want[SIG + 2] = SIGWORD & 0xFF, SIGWORD >> 8, VER
    for a = 0x1E2F, 0x1E3F do want[a] = 0 end
    for a = 0x1FF7, 0x1FFD do want[a] = 0 end
  end
  local junk, loadout, bad = 0, 0, 0
  for a = 0x1600, 0x1FFF do
    local now = sb(a)
    if (inRange(a, 0x1E2F, 0x1E3F) or inRange(a, 0x1FF7, 0x1FFD)) and now ~= 0 then junk = junk + 1 end
    if not saveSets(a) and now ~= want[a] then
      if inRange(a, 0x1E1D, 0x1E2B) then loadout = loadout + 1 end
      bad = bad + 1
      if bad <= 8 then
        H.log(string.format("[golden] %s: $%04X was %02X, the save wrote %02X, expected %02X", tag, a,
          presave[a], now, want[a]))
      end
    end
  end
  H.log(string.format("[golden] %s: %s; %d byte(s) changed beyond the save's own and the documented zeroing", tag,
    firstSign and "the save signed an unsigned block" or raise and string.format("the block was signed at "
      .. "version %d and the save raised it to %d", presave[SIG + 2], VER) or "the block was signed already", bad))
  H.assertEq(junk, 0, tag .. ": the reserve $1E2F-$1E3F and the tail $1FF7-$1FFD are zero")
  H.assertEq(loadout, 0, tag .. ": the loadouts are as they were")
  H.assertEq(bad, 0, tag .. ": the save changed nothing in the block but play time, timers, checksum"
    .. (firstSign and ", the signature, the reserve and the tail" or raise and ", the version" or ""))
  presave = nil
end

-- A junk fixture is also saved over slot 1 (Save over another slot): the
-- destination's page reserves zeroed, its codex payload the source's, and
-- the source's pages and $4000-$7FFF untouched.
local JUNK = (OT6_SRAM_CHECKPOINT or ""):find("/junk/") ~= nil
local B2
local function pageReserve(page, esper)
  local r = {}
  for o = 2, 0xF do r[#r + 1] = page + o end
  for o = esper and CTR_END or 0x310, 0x3FF do r[#r + 1] = page + o end
  return r
end
local function assertSaveAs(B3)
  local c1, c3, e1, e3 = CODEX, CODEX + 0x800, ESPER, ESPER + 0x800
  local nz = 0
  for _, o in ipairs(pageReserve(c1, false)) do if B3[o] ~= 0 then nz = nz + 1 end end
  for _, o in ipairs(pageReserve(e1, true)) do if B3[o] ~= 0 then nz = nz + 1 end end
  H.assertEq(nz, 0, "saveas: slot 1's codex and esper page pads and tails are zero")
  local diff = 0
  for o = 0, 0x30F do
    if (o < 2 or o >= 0x10) and B3[c1 + o] ~= B3[c3 + o] then diff = diff + 1 end
  end
  H.assertEq(diff, 0, "saveas: slot 1's codex magic and tables are slot 3's")
  H.assertEq(bw(B3, e1), ESPER_MAGIC, "saveas: slot 1's esper page is signed")
  for o = CTR, CTR_END - 1 do
    if B3[e1 + o] ~= sram(LIVE + o) then diff = diff + 1 end
  end
  H.assertEq(diff, 0, "saveas: slot 1's esper counters are the live page's")
  local moved = 0
  for o = c3, c3 + 0x3FF do if B3[o] ~= B2[o] then moved = moved + 1 end end
  for o = e3, e3 + 0x3FF do if B3[o] ~= B2[o] then moved = moved + 1 end end
  H.assertEq(moved, 0, "saveas: slot 3's codex and esper pages are as they were")
  for o = 0x4000, 0x7FFF do if B3[o] ~= B2[o] then moved = moved + 1 end end
  H.assertEq(moved, 0, "saveas: $4000-$7FFF is as it was")
  H.log("[golden] saveas: slot 3 saved over slot 1: slot 1's reserves zero, its codex slot 3's; slot 3's pages "
    .. "and $4000-$7FFF untouched")
end

local function readout(tag)
  return H.call(function()
    print(string.format("[golden] at %s slot %d map %d field (%d,%d) world (%d,%d) worldmode %s", tag, slot,
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY(), H.worldX(), H.worldY(), tostring(H.worldMode())))
    dump(tag, "wram", function(a) return loaded[a] end, 0x1600, 0x0A00)
    dump(tag, "codex", function(o) return sram(o) end, CODEX + (slot - 1) * 0x400, 0x0400)
    dump(tag, "live", function(o) return sram(o) end, LIVE, 0x0400)
  end)
end

H.run({ maxFrames = 40000 }, {
  H.call(function()
    hook()
    B0 = battery()
    slot = B0[0x1FF0]
    H.assertEq(slot, 3, "the battery last saved slot 3 ($1FF0), as every release save does")
    local word = slotByte(B0, 0x1F64) | (slotByte(B0, 0x1F65) << 8)
    local map = word & 0x1ff
    if map <= 1 then
      target = { world = true, map = map, x = slotByte(B0, 0x1F60), y = slotByte(B0, 0x1F61) }
    else
      target = { map = map, x = slotByte(B0, 0x1FC0), y = slotByte(B0, 0x1FC1) }
    end
    H.log(string.format("[golden] the battery's slot %d was saved on %s %d at (%d,%d)", slot,
      target.world and "world" or "map", map, target.x, target.y))
  end),
  continue("load1"),
  readout("load1"),
  H.call(function()
    assertBlock("load1", B0)
    assertCodexLoaded("load1", B0)
    snapCodex()
    assertLive("load1", B0)
  end),
  H.saveGame({ slot = 3, baseline = false, tag = "the golden save's re-save" }),
  H.call(function()
    B1 = battery()
    assertSaved("save1", B1, not signedBlock(function(a) return slotByte(B0, a) end))
    assertCodexKept("save1", B1)
    dump("save1", "slot", function(a) return slotByte(B1, a) end, 0x1600, 0x0A00)
    local page = ESPER + (slot - 1) * 0x400
    H.assertEq(bw(B1, page), ESPER_MAGIC, "after the save, slot " .. slot .. "'s esper page is signed")
    for o = CTR, CTR_END - 1 do
      H.assertEq(B1[page + o], sram(LIVE + o), string.format("after the save, esper page byte +$%03X is the live page's", o))
    end
    H.log("[golden] the save wrote the slot and its esper page; the console's Reset")
    loaded = nil
    H.expectTitle("save_golden: the console's Reset before the reload")
    emu.reset()
  end),
  continue("load2"),
  readout("load2"),
  H.call(function()
    assertBlock("load2", B1)
    assertCodex("load2", B1)
    assertLive("load2", B1)
  end),
  -- a signed save, saved again: nothing but the save's own bytes move
  H.saveGame({ slot = 3, baseline = false, tag = "the signed save's re-save" }),
  H.call(function()
    B2 = battery()
    assertSaved("save2", B2, false)
    assertCodexKept("save2", B2)
  end),
  H.cond(function() return JUNK end, {
    H.saveGame({ slot = 1, baseline = false, tag = "the junk save over slot 1" }),
    H.call(function()
      local B3 = battery()
      assertSaved("saveas", B3, false, 1)
      assertSaveAs(B3)
      assertCodexKept("saveas", B3)
    end),
  }, {}),
  H.call(function()
    H.log("[golden] PASS: the save loaded, was signed, loaded again and saved again")
  end),
})
