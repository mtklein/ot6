-- probe_map19.lua -- the (30,41) cutscene lands the party on map 19 (38,49)
-- with control (crane rooftop screenshot). Map 19 has a column of event
-- triggers climbing north {38,50}/{38,38}/{38,26}/{38,17}. Drive UP through
-- them, ride any events, and log/screenshot where it leads -- is this the
-- Dadaluma tower, or a corrupt warp?
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

H.run({ maxFrames = 40000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/map19_checkpoint.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("[boot] map=%d (%d,%d) z%d ctl=%s", map(), H.fieldX(),
      H.fieldY(), H.readByte(0x00b2) & 3, tostring(H.hasControl())))
    H.screenshot("m19_boot")
  end),
  -- drive NORTH up the trigger column; ride events (A) and log map changes.
  (function()
    local hb, lm = 0, -1
    return H.driveUntil(function()
      return H.battleActive() or (map() ~= 19 and H.hasControl() and H.tileAligned()
             and bright() >= 15) or (H.fieldY() <= 15 and H.hasControl() and H.tileAligned())
    end, 20000, { H.call(function()
      hb = hb + 1
      local m, x, y = map(), H.fieldX(), H.fieldY()
      if (m * 65536 + y * 256 + x) ~= lm or hb % 600 == 0 then lm = m * 65536 + y * 256 + x
        H.log(string.format("[up] f%d map=%d (%d,%d) z%d ctl=%s ev=%s bri=%d batt=%s",
          hb, m, x, y, H.readByte(0x00b2) & 3, tostring(H.hasControl()),
          tostring(H.eventRunning()), bright(), tostring(H.battleLoadStarted()))) end
      if H.battleLoadStarted() then killBitAll(); H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.hasControl() or H.eventRunning() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad({ up = true })   -- climb the column
    end) }, "climb map 19 north")
  end)(),
  H.call(function()
    H.log(string.format("[up-END] map=%d (%d,%d) z%d ctl=%s battle=%s", map(),
      H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3, tostring(H.hasControl()),
      tostring(H.battleActive())))
    if H.battleActive() then
      local w = H.formationWords()
      H.log(string.format("[up-END] formation %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    H.screenshot("m19_end")
  end),
})
