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
--      codex page is the one the battery held, and the live esper page is
--      the slot's (a signed page) or empty (an unsigned one: a save from
--      before v0.44);
--   4. the game is saved into the same slot through the Save menu (a save
--      point or the world map, where the battery was saved), and the slot's
--      esper page now carries the live page, signed;
--   5. the console's Reset, the title, Continue again: the reload is the
--      saved block, and the live esper
--      page is what was saved.
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
local ESPER_MAGIC, CODEX_MAGIC = 0x3145, 0x384F
local CTR, CTR_END = 0x0010, 0x0280               -- esper page: 12 actors x 26 words
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
local function hook()
  if hooked then return end
  hooked = true
  local at = H.sym("Ot6EsperContinue")
  emu.addMemoryCallback(function()
    loaded = {}
    for a = 0x1600, 0x1FFF do loaded[a] = H.readByte(a) end
  end, emu.callbackType.exec, at, at)
  local sv = H.sym("CopyGameDataToSRAM")
  emu.addMemoryCallback(function()
    presave = {}
    for a = 0x1600, 0x1FFF do presave[a] = H.readByte(a) end
  end, emu.callbackType.exec, sv, sv)
end
local SIG, SIGWORD, VER = 0x1E2C, 0x5653, 1
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
local function assertLive(tag, B)
  local page = ESPER + (slot - 1) * 0x400
  local signed = bw(B, page) == ESPER_MAGIC
  H.assertEq(sramW(LIVE), ESPER_MAGIC, tag .. ": the live esper page is signed")
  local sum, bad = 0, 0
  for o = CTR, CTR_END - 1 do
    local want = signed and B[page + o] or 0
    local got = sram(LIVE + o)
    sum = sum + got
    if want ~= got then bad = bad + 1 end
  end
  H.log(string.format("[golden] %s: slot %d's esper page is %s; the live page sums %d", tag, slot,
    signed and "signed" or "unsigned (reads as no progress)", sum))
  H.assertEq(bad, 0, tag .. ": the live esper page is " .. (signed and "the slot's page" or "empty"))
end

local function assertCodex(tag, B)
  local page = CODEX + (slot - 1) * 0x400
  local bad, n = 0, 0
  for o = 0, 0x3FF do
    if sram(page + o) ~= B[page + o] then bad = bad + 1 end
    if o >= 0x10 and o < 0x310 and sram(page + o) ~= 0 then n = n + 1 end
  end
  H.log(string.format("[golden] %s: slot %d's codex page holds %d revealed bytes, magic $%04X", tag, slot, n,
    sramW(page)))
  H.assertEq(sramW(page), CODEX_MAGIC, tag .. ": the slot's codex page is signed")
  H.assertEq(bad, 0, tag .. ": the slot's codex page is the one the battery held")
end

-- The block a save wrote against the block it was handed: signed, the
-- reserve zero, and nothing else changed but the save's own bytes (and,
-- the first time an unsigned block is signed, the signature and reserve).
local function assertSaved(tag, B, firstSign)
  H.assertEq(presave ~= nil, true, tag .. ": the save ran CopyGameDataToSRAM")
  H.assertEq(slotByte(B, SIG) | (slotByte(B, SIG + 1) << 8), SIGWORD, tag .. ": the saved block is signed ($5653)")
  H.assertEq(slotByte(B, SIG + 2), VER, tag .. ": ... with layout version 1")
  local bad, junk = 0, 0
  for a = 0x1600, 0x1FFF do
    local was, now = presave[a], slotByte(B, a)
    if inRange(a, 0x1E2F, 0x1E3F) or inRange(a, 0x1FF7, 0x1FFD) then
      if now ~= 0 then junk = junk + 1 end
    end
    if was ~= now and not saveSets(a) and not (firstSign and signSets(a)) then
      bad = bad + 1
      if bad <= 8 then
        H.log(string.format("[golden] %s: $%04X was %02X, the save wrote %02X", tag, a, was, now))
      end
    end
  end
  H.log(string.format("[golden] %s: %s; %d byte(s) changed beyond the save's own", tag,
    firstSign and "the save signed an unsigned block" or "the block was signed already", bad))
  H.assertEq(junk, 0, tag .. ": the reserve $1E2F-$1E3F and the tail $1FF7-$1FFD are zero")
  H.assertEq(bad, 0, tag .. ": the save changed nothing in the block but play time, timers, checksum"
    .. (firstSign and " and the signature and reserve" or ""))
  presave = nil
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
    assertCodex("load1", B0)
    assertLive("load1", B0)
  end),
  H.saveGame({ slot = 3, baseline = false, tag = "the golden save's re-save" }),
  H.call(function()
    B1 = battery()
    assertSaved("save1", B1, slotByte(B0, SIG) | (slotByte(B0, SIG + 1) << 8) ~= SIGWORD)
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
    assertSaved("save2", battery(), false)
    H.log("[golden] PASS: the save loaded, was signed, loaded again and saved again")
  end),
})
