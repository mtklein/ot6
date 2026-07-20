-- probe_lete_entrance.lua -- frame-exact instrument over the Lete River
-- forced fight's ENTRANCE (event battle group 8: formation 35 Pterodon x2
-- 3/4, formation 37 Nautiloid+Exocite+Pterodon 1/4 -- the owner's two
-- "white flash at the start of the fight" sightings are the two die rolls
-- of this one event battle).
--
-- WHAT IT MEASURES.  $2105 is fed per-scanline by indirect HDMA #3
-- (btlgfx_main.asm _c2d12e/_c2d11e): the table re-reads the live shadow
-- $7E896F at line 0 AND at line 100.  A main-loop write to $896F before
-- line 100 therefore becomes VISIBLE AT LINE 100 OF THE SAME FRAME --
-- before any nmi (and so before the ot6 hud veil) can react.  This probe
-- reconstructs, for every frame of the entrance, what those two samples
-- actually carried, and holds it against what the hud cells held in vram
-- that frame:
--   * per tick (startFrame): $896F/$8973, $201e shown mask, $3aa8
--     presence, $57be entry veil, $57bf scriptbusy, $64d5 dialog latch,
--     brightness, and each hud shadow line's cur address + vram cell
--     class (glyph / veil $01EE / blank $21FF / other).
--   * write-watch $7E896F..$7E8977 (the three hdma-fed $2105 section
--     shadows): frame, SCANLINE, pc, old->new.
--   * write-watch $7E201E and $7E57BE: the shown-mask and veil edges.
--   * EXPOSURE(F) := (sample@0 or sample@100 of frame F carries bit $40)
--     AND some live hud line held painted glyphs during F's scanout
--     (vram state read at tick F: vram only changes in vblank, so the
--     tick-F read IS the scanout truth for frame F).  Flagged loudly,
--     screenshot taken at tick F+1 (takeScreenshot returns the frame
--     that just completed = frame F, the exposed image itself).
--   * every entrance frame is screenshot anyway (ent_<hwframe>) so the
--     flash, if any, is on disk regardless of what the detector thinks.
--
-- The rapids_start mint's natural draw is the TRIO (37).  To measure the
-- other die roll (35, Pterodon x2), make a one-line variant -- compose is
-- hermetic, so it is a sed, not an env var:
--   sed 's/^local FORCE_MODE = "none"/local FORCE_MODE = "duo"/' \
--     tools/tests/probe_lete_entrance.lua > build/probe_duo.lua \
--   && OT6_WORKER=duo tools/tests/run.sh build/probe_duo.lua
-- ("trio" likewise pins the 1/4 roll explicitly.)  The pin seeds
-- $1fa2/$1fa3 during the ride only; it stops at battle load.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/rapids_start.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom
local CH_MAX = 0x056F

local FORCE_MODE = "none" -- FORCE_MODE_MARK (variant runs sed this line:
-- "duo" pins the group-8 roll to formation 35 Pterodon x2, "trio" to 37)

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function hwframe() return emu.getState()["ppu.frameCount"] or -1 end

-- ------------------------------------------------------- claimed glyphs --
local claimed = nil
local function claimedCharSet()
  local function findSig(sig)
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base + i - 1, ROM) ~= sig[i] then hit = false break end
      end
      if hit then return base end
    end
    return nil
  end
  local bg = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                      0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(bg ~= nil, true, "OT6 bg glyph data found in rom")
  local set = { [0xbf] = true }
  for _, c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do set[c] = true end
  for k = 1, 16 do set[emu.read(bg - 17 + k, ROM)] = true end
  return set
end

-- ------------------------------------------------------- write watchers --
-- Every CPU write to the three hdma-fed $2105 section shadows, with the
-- scanline it landed on.  Kept tiny: append raw, analyze at tick time.
local wr896f = {}          -- { {hwf, sl, cyc, pc, addr, val} ... }
local wrShown = {}         -- $201e writes
local wrVeil  = {}         -- $57be writes
local watching = false

local function armWatches()
  emu.addMemoryCallback(function(addr, value)
    if not watching or #wr896f >= 6000 then return end
    local s = emu.getState()
    wr896f[#wr896f + 1] = {
      hwf = s["ppu.frameCount"] or -1,
      sl  = s["ppu.scanline"] or -1,
      cyc = s["ppu.cycle"] or -1,
      pc  = string.format("%02X/%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0),
      addr = addr, val = value,
    }
  end, emu.callbackType.write, 0x7E896F, 0x7E8977)
  emu.addMemoryCallback(function(addr, value)
    if not watching or #wrShown >= 2000 then return end
    local s = emu.getState()
    wrShown[#wrShown + 1] = {
      hwf = s["ppu.frameCount"] or -1, sl = s["ppu.scanline"] or -1,
      pc = string.format("%02X/%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0),
      val = value,
    }
  end, emu.callbackType.write, 0x7E201E, 0x7E201E)
  emu.addMemoryCallback(function(addr, value)
    if not watching or #wrVeil >= 2000 then return end
    local s = emu.getState()
    wrVeil[#wrVeil + 1] = {
      hwf = s["ppu.frameCount"] or -1, sl = s["ppu.scanline"] or -1,
      pc = string.format("%02X/%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0),
      val = value,
    }
  end, emu.callbackType.write, 0x7E57BE, 0x7E57BE)
end

-- --------------------------------------------------------- cell classes --
-- one hud line's 5 vram cells -> compact class string; also reports if any
-- cell is a painted glyph.
local function lineState(s)
  local cur = H.readWord(H.shadowLine(s))
  if cur == 0 then return "off", false end
  local glyph, veil, blank, other = 0, 0, 0, 0
  for k = 0, 4 do
    local lo = emu.read((cur + k) * 2, VR)
    local hi = emu.read((cur + k) * 2 + 1, VR)
    if hi == 0x21 and claimed[lo] then glyph = glyph + 1
    elseif hi == 0x01 and lo == 0xee then veil = veil + 1
    elseif hi == 0x21 and lo == 0xff then blank = blank + 1
    else other = other + 1 end
  end
  local tag = string.format("%04x:g%dv%db%do%d", cur, glyph, veil, blank, other)
  return tag, glyph > 0
end

-- --------------------------------------------------------- the analyzer --
-- Called at tick F+1 with the glyph/896f facts recorded at tick F: decide
-- what frame F's two hdma samples carried.
local lastTick = nil       -- { hwf, v896f, anyGlyph, lines }
local exposures = 0
local function analyzePrevFrame(now896f)
  if lastTick == nil then return end
  local F = lastTick.hwf
  -- writes that landed during frame F, before line 100 / after
  local s0 = lastTick.v896f          -- value at F's start (tick read)
  local s100 = s0
  for _, w in ipairs(wr896f) do
    if w.addr == 0x7E896F and w.hwf == F and w.sl >= 0 and w.sl < 100 then
      s100 = w.val
    end
  end
  local exposed0   = (s0 & 0x40) ~= 0
  local exposed100 = (s100 & 0x40) ~= 0
  if (exposed0 or exposed100) and lastTick.anyGlyph then
    exposures = exposures + 1
    H.log(string.format(
      "EXPOSURE f%d: sample@0=%02x sample@100=%02x glyph-painted lines [%s]"
      .. " (veil57be=%d 201e=%02x)", F, s0, s100, lastTick.lines,
      lastTick.v57be, lastTick.v201e))
    if exposures <= 8 then
      -- we are at tick F+1: takeScreenshot returns the frame that just
      -- completed -- frame F, the exposed image itself.
      H.screenshot(string.format("exposed_f%d", F))
    end
  end
end

-- ------------------------------------------------------------ the ride --
-- gen_rapids' driver, minus the kill-bit: the fight must play its real
-- entrance.  Battle rising edge stops the pad and hands off to the watch.
local function rideStep()
  local phase, dlgN, hb = 0, 0, -900
  return H.driveUntil(function()
    return H.battleLoadStarted()
  end, 25000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("ride f%d map=%d (%d,%d) bright=%d dlg=%s ev=%s",
          H.frame, map(), H.fieldX(), H.fieldY(), bright(),
          tostring(H.dialogWaiting()), tostring(H.eventRunning())))
      end
      if FORCE_MODE ~= "none" then
        -- pin the group-8 roll: UpdateBattleGrpRng returns
        -- RNGTbl[++$1fa2] + $1fa3; with $1fa2=0 the next draw reads
        -- RNGTbl[1] (=$B6, verified below).  $1fa3=$20 lands $D6 >= $C0
        -- -> SECOND word (37, trio); $1fa3=$00 lands $B6 < $C0 -> FIRST
        -- word (35, Pterodon x2).
        H.writeByte(0x1fa2, 0x00)
        H.writeByte(0x1fa3, FORCE_MODE == "trio" and 0x20 or 0x00)
      end
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if H.dialogWaiting() and H.readByte(CH_MAX) >= 2 then
        error("unexpected multiple choice on the river", 0)
      end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}) return end
      H.setPad({})
    end),
  }, "the forced river fight loads")
end

-- --------------------------------------------------- trail + map survey --
-- Cells the flush one-shot-blanked when a line moved/disabled: every vram
-- word address a line's cur span occupied last tick but not this tick.
-- Post-blank those cells hold whatever the flush's blank word is ($21FF on
-- the pre-fix image) until vanilla clears the buffer again -- the probe
-- counts how many read $21FF vs $01EE each 16x16 frame.
local prevSpans = {}       -- line -> cur (last tick)
local abandoned = {}       -- addr -> true (capped)
local nAbandoned = 0
local function trackSpans()
  local live = {}
  for s = 0, 5 do
    local cur = H.readWord(H.shadowLine(s))
    if cur ~= 0 then
      for k = 0, 4 do live[cur + k] = true end
    end
    local old = prevSpans[s]
    if old and old ~= 0 and old ~= cur and nAbandoned < 3000 then
      for k = 0, 4 do
        if not abandoned[old + k] then
          abandoned[old + k] = true
          nAbandoned = nAbandoned + 1
        end
      end
    end
    prevSpans[s] = cur
  end
  -- a live line reclaiming an abandoned addr owns it again
  for a in pairs(live) do abandoned[a] = nil end
  local nTrail, nFill = 0, 0
  for a in pairs(abandoned) do
    local w = emu.readWord(a * 2, VR)
    if w == 0x21FF then nTrail = nTrail + 1
    elseif w == 0x01EE then nFill = nFill + 1 end
  end
  return nTrail, nFill
end

-- classify the whole bg3 field map (32x32 words from the $897b base):
-- '.' 01EE fill, 'T' 21FF trail-blank, 'G' priority-set claimed glyph,
-- 'p' other priority-set page-1, 'o' anything else.
local mapDumps = 0
local function dumpMap(tag)
  local reg = H.readByte(0x897b)
  local base = ((reg - (reg % 4)) * 256) * 2
  for row = 0, 15 do
    local line = {}
    for col = 0, 31 do
      local off = base + (row * 32 + col) * 2
      local lo, hi = emu.read(off, VR), emu.read(off + 1, VR)
      local c = "o"
      if hi == 0x01 and lo == 0xee then c = "."
      elseif hi == 0x21 and lo == 0xff then c = "T"
      elseif hi == 0x21 and claimed[lo] then c = "G"
      elseif hi == 0x21 then c = "p"
      elseif hi == 0 and lo == 0 then c = "0" end
      line[#line + 1] = c
    end
    H.log(string.format("[map %s r%02d] %s", tag, row, table.concat(line)))
  end
end

-- ------------------------------------------------------------ the watch --
local WATCH_FRAMES = 900
local shots = 0
local function watchStep()
  local n = 0
  return H.driveUntil(function()
    n = n + 1
    return n >= WATCH_FRAMES
  end, WATCH_FRAMES + 60, {
    H.call(function()
      H.setPad({})
      -- screenshot anything queued from last tick's analyzer, then the
      -- rolling entrance record (the shot taken NOW is the frame that
      -- just completed).
      local hwf = hwframe()
      if n >= 2 and shots < 450 then
        shots = shots + 1
        H.screenshot(string.format("ent_%06d", hwf - 1))
      end
      -- analyze the frame that just completed (recorded at last tick)
      local v896f = H.readByte(0x896f)
      analyzePrevFrame(v896f)
      -- record THIS frame's facts for the next tick's analyzer
      local lines, anyGlyph = {}, false
      for s = 0, 5 do
        local tag, g = lineState(s)
        lines[#lines + 1] = tag
        anyGlyph = anyGlyph or g
      end
      lastTick = {
        hwf = hwf, v896f = v896f, anyGlyph = anyGlyph,
        lines = table.concat(lines, " "),
        v57be = H.readByte(0x57be), v201e = H.readByte(0x201e),
      }
      -- trail survey + per-frame choreography line
      local nTrail, nFill = trackSpans()
      local v896f = H.readByte(0x896f)
      if (v896f & 0x40) ~= 0 and nTrail > 0 and mapDumps < 10 then
        mapDumps = mapDumps + 1
        dumpMap(string.format("f%d", hwf))
      end
      local pres = 0
      for i = 0, 5 do
        if H.readByte(0x3aa8 + i * 2) % 2 == 1 then pres = pres | (1 << i) end
      end
      H.log(string.format(
        "f%d 2105=%02x/%02x 201e=%02x pres=%02x veil=%d busy=%d dlg=%d "
        .. "br=%d trail=%d/%d | %s", hwf, v896f, H.readByte(0x8973),
        H.readByte(0x201e), pres, H.readByte(0x57be), H.readByte(0x57bf),
        H.readByte(0x64d5), bright(), nTrail, nFill,
        table.concat(lines, " ")))
    end),
  }, "entrance watched")
end

H.run({ maxFrames = 45000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(map(), 113, "rapids_start boots on map 113, the Lete River")
    H.assertEq(H.readRomByte(0xFD01), 0xB6,
      "RNGTbl[1] is $B6 (c0/fd01) -- the trio-forcing arithmetic holds")
    claimed = claimedCharSet()
    armWatches()
    H.log(string.format("[entrance] armed at f%d hwf=%d 896f=%02x force=%s",
      H.frame, hwframe(), H.readByte(0x896f), FORCE_MODE))
  end),
  rideStep(),
  H.call(function()
    H.setPad({})
    watching = true
    local w = H.formationWords()
    H.log(string.format("[entrance] battle up at f%d hwf=%d formation words "
      .. "%04X %04X %04X %04X %04X %04X", H.frame, hwframe(),
      w[1], w[2], w[3], w[4], w[5], w[6]))
  end),
  watchStep(),
  H.call(function()
    H.setPad({})
    -- dump the write logs, bounded
    H.log(string.format("[entrance] %d shadow writes, %d shown writes, "
      .. "%d veil writes, exposures=%d", #wr896f, #wrShown, #wrVeil,
      exposures))
    if wr896f[1] and wr896f[1].sl == -1 then
      local keys = {}
      for k in pairs(emu.getState()) do
        if k:find("^ppu") then keys[#keys + 1] = k end
      end
      table.sort(keys)
      H.log("[entrance] NO ppu.scanline? state keys: "
        .. table.concat(keys, ","))
    end
    local shown = 0
    for i, w in ipairs(wr896f) do
      if i <= 400 then
        H.log(string.format("  [896f] f%d sl%d cyc%d %s %04X=%02x", w.hwf,
          w.sl, w.cyc, w.pc, w.addr & 0xFFFF, w.val))
        shown = i
      end
    end
    if #wr896f > shown then
      H.log(string.format("  [896f] ... %d more", #wr896f - shown))
    end
    for i, w in ipairs(wrShown) do
      if i <= 60 then
        H.log(string.format("  [201e] f%d sl%d %s =%02x", w.hwf, w.sl, w.pc,
          w.val))
      end
    end
    for i, w in ipairs(wrVeil) do
      if i <= 60 then
        H.log(string.format("  [57be] f%d sl%d %s =%02x", w.hwf, w.sl, w.pc,
          w.val))
      end
    end
    H.screenshot("entrance_settled")
    H.log(string.format("[entrance] done: exposures=%d formation drawn as "
      .. "logged above", exposures))
  end),
})
