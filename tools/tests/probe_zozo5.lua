-- probe_zozo5.lua -- push through the clock chokepoint {98,59} with a
-- held direction (the re-firing trigger cannot stop a latched pad), then
-- census the far side.  Modeled on probe_zozo4 (which read position fine).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 20000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_clock_solved.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[boot] map %d at (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
    -- walkability around the chokepoint
    for y = 55, 62 do
      local row = {}
      for x = 95, 112 do
        local t = H.maptile(x, y)
        row[#row + 1] = (H.readByte(0x7E7600 + t) & 0x07) == 0x07 and "#" or "."
      end
      H.log(string.format("  y=%2d x95+ %s", y, table.concat(row)))
    end
  end),
  H.navTo(98, 60, { maxFrames = 6000 }),
  H.call(function() H.log(string.format("below clock at (%d,%d)",
    H.fieldX(), H.fieldY())) end),
  -- cross the clock tile: up onto {98,59}, then EAST off it (north is a
  -- wall).  The re-firing trigger cannot stop a latched pad; alternate
  -- up/right so whichever axis is free advances.
  (function()
    local last = ""
    return H.driveUntil(function()
      return H.fieldX() >= 101 and H.hasControl() and H.tileAligned()
    end, 2000, {
      H.call(function()
        local pos = H.fieldX() .. "," .. H.fieldY()
        if pos ~= last and H.tileAligned() then
          last = pos
          H.log(string.format("  push: at (%s) ctl=%s ev=%s", pos,
            tostring(H.hasControl()), tostring(H.eventRunning())))
        end
        -- get to y=59 first, then drive east
        if H.fieldY() > 59 then H.setPad({ up = true })
        else H.setPad({ right = true }) end
      end),
    }, "cross the clock eastward")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[far side] at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- through door (110,54) -> 221 (43,25); census the upper city
  H.navTo(110, 54, { arrive = function() return map() == 221 end,
                     maxFrames = 9000 }),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned()
       and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 1500, "on 221", 5),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[u221] map %d at (%d,%d); upper-city census:",
      map(), H.fieldX(), H.fieldY()))
    for _, t in ipairs({
        { 30, 14, "DADALUMA" }, { 30, 15, "his S" }, { 31, 14, "his E" },
        { 29, 14, "his W" }, { 33, 9, "tower door" }, { 33, 10, "tower S" },
        { 35, 41, "crane 35,41" }, { 43, 24, "back door" },
        { 35, 15, "d->225(35,13)" }, { 30, 21, "d->225(30,33)" },
        { 44, 41, "d->225(11,16)" }, { 49, 38, "d->225(21,14)" },
        { 19, 39, "jump lo W" }, { 21, 39, "jump lo E" },
        { 25, 39, "jump hi W" }, { 28, 39, "jump hi E" },
        { 28, 33, "jump33 hiW" }, { 25, 33, "jump33 hiE" },
        { 41, 32, "TERRA-npc" }, { 57, 41, "arrival" },
        { 40, 20, "mid" }, { 30, 30, "midlow" },
      }) do
      local p = H.bfsPath(t[1], t[2])
      if p then H.log(string.format("  (%d,%d) %-14s ok %d", t[1], t[2], t[3], #p)) end
    end
  end),
})
