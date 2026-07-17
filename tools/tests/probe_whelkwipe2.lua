-- probe_whelkwipe2.lua -- round 2: scroll-table + map + font-truth
-- instrumentation of the whelk head hide/show transition.
--
-- Round 1 (probe_whelkwipe) established: the BG3 field map and small-font
-- tile regions are bit-identical base-vs-ot6 through both transitions, yet
-- the ot6 image renders a sweeping strip of glyph garbage.  The remaining
-- suspects are the per-scanline BG3 scroll HDMA table (w7e4af5, 224 x
-- [hofs.w vofs.w], channel #2 -> $2111/$2112) and the tile-region STATE at
-- burst start (round 1's drive-phase shadow refresh absorbed pre-burst
-- writes silently).  This probe logs, per transition:
--   * a full BG3 field-map dump ($5400-$57ff) at burst start
--   * a whole-font compare against SmallFontGfx at burst start (which
--     cells differ from the vanilla font; ot6's claimed cells will show
--     as expected diffs, anything else is state)
--   * per-frame RLE of the BG3 scroll table (logged on change)
--   * per-frame $2f48 / $201e / $61ab and the anim thread state
-- plus screenshots every 5th frame (round 1 owns the dense visuals).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local TAG = "wo2"
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local BURST = 150

local TRIP_PC = 0xC2E668
local trips = {}
local tripped = false
local function armTripWire()
  emu.addMemoryCallback(function()
    if tripped then return end
    tripped = true
    local ptr = H.readWord(0x76)
    trips[#trips + 1] = {
      frame = H.frame,
      type = H.readByte(ptr + 1),
      mask = H.readByte(ptr + 2),
    }
  end, emu.callbackType.exec, TRIP_PC, TRIP_PC)
end

local VR = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom
local MAP0 = 0x5400 * 2
local FONT0 = 0x5800 * 2
local SMALLFONT_ROM = 0x047FC0     -- SmallFontGfx C4/7FC0 (file offset)

-- BG3 per-scanline scroll table: 224 entries of [hofs.w vofs.w]
local SCROLL0 = 0x4af5

local function scrollRle()
  local parts, l0, ph, pv = {}, 0, nil, nil
  for l = 0, 223 do
    local hv = H.readWord(SCROLL0 + l * 4)
    local vv = H.readWord(SCROLL0 + l * 4 + 2)
    if hv ~= ph or vv ~= pv then
      if ph ~= nil then
        parts[#parts + 1] = string.format("%d-%d:%04x,%04x", l0, l - 1, ph, pv)
      end
      l0, ph, pv = l, hv, vv
    end
  end
  parts[#parts + 1] = string.format("%d-223:%04x,%04x", l0, ph, pv)
  return table.concat(parts, " ")
end

local function dumpMap(label)
  for row = 0, 31 do
    local words = {}
    for col = 0, 31 do
      words[#words + 1] = string.format("%04x",
        emu.readWord(MAP0 + (row * 32 + col) * 2, VR))
    end
    H.log(string.format("%s maprow %02d %s", label, row,
      table.concat(words, " ")))
  end
end

-- compare every font cell against SmallFontGfx; log the cells that differ
local function fontTruth(label)
  local diff = {}
  for cell = 0, 0xff do
    for i = 0, 15 do
      if emu.read(FONT0 + cell * 16 + i, VR) ~=
         emu.read(SMALLFONT_ROM + cell * 16 + i, ROM) then
        diff[#diff + 1] = string.format("%02x", cell)
        break
      end
    end
  end
  H.log(string.format("%s font-vs-vanilla diff cells (%d): %s",
    label, #diff, table.concat(diff, " ")))
end

-- dump one font cell's 16 bytes (tile forensics)
local function dumpCell(label, cell)
  local b = {}
  for i = 0, 15 do
    b[#b + 1] = string.format("%02x", emu.read(FONT0 + cell * 16 + i, VR))
  end
  H.log(string.format("%s cell %02x: %s", label, cell, table.concat(b, " ")))
end

local MENU = 0x7bca
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local function policyPulse()
  if H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    mSeq, mIdx = { "a", "down", "down", "a", "a" }, 1
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mStall = mStall + 1
  if mStall > 2 then
    mSeq, mStall = nil, 0
    return { "b" }
  end
  return { "a" }
end
local pulseAge = 29
local function pulseTick()
  pulseAge = (pulseAge + 1) % 30
  if pulseAge == 0 then
    H.setPad(policyPulse())
  elseif pulseAge == 6 then
    H.setPad({})
  end
end

local function burst(k)
  local i = 0
  local lastRle = nil
  return {
    tick = function()
      if i == 0 then
        H.setPad({})
        local trip = trips[#trips]
        H.log(string.format(
          "burst %d armed: trip frame=%d type=%02x mask=%02x",
          k, trip.frame, trip.type, trip.mask))
        dumpMap(string.format("%s_t%d", TAG, k))
        fontTruth(string.format("%s_t%d", TAG, k))
        for _, c in ipairs({ 0xee, 0xeb, 0x64, 0x69, 0xbf }) do
          dumpCell(string.format("%s_t%d", TAG, k), c)
        end
      end
      local pre = string.format("%s_t%d_f%03d", TAG, k, i)
      if i % 5 == 0 then H.screenshot(pre) end
      local rle = scrollRle()
      if rle ~= lastRle then
        H.log(pre .. " bg3scroll " .. rle)
        lastRle = rle
      end
      i = i + 1
      if i >= BURST then
        H.log(string.format("%s_t%d burst end", TAG, k))
        fontTruth(string.format("%s_t%d_end", TAG, k))
        tripped = false
        return "done"
      end
      return "frame"
    end,
  }
end

local aPhase = 0
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function()
    return H.battleLoadStarted() and H.monstersPresent() > 0
  end, 2600, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then H.setPad({}); return end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),
  H.call(function()
    armTripWire()
    fontTruth(TAG .. "_settled")
    H.log(TAG .. "_settled bg3scroll " .. scrollRle())
  end),
  H.driveUntil(function() return #trips >= 1 end, 9000, {
    H.call(pulseTick),
  }, "first transition (hide)"),
  burst(1),
  H.driveUntil(function() return #trips >= 2 end, 9000, {
    H.call(pulseTick),
  }, "second transition (show)"),
  burst(2),
  H.call(function()
    for k, t in ipairs(trips) do
      H.log(string.format("trip %d: frame=%d type=%02x mask=%02x",
        k, t.frame, t.type, t.mask))
    end
    H.log("capture complete")
  end),
})
