-- probe_clock.lua -- instrument the Zozo clock's three chained choice
-- dialogs: open it, then drive the hour cursor to 2 by watching $056E move
-- one step per d-pad EDGE ($056D latch), logging the menu bytes throughout.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function landed(m, n)
  local c = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.dialogWaiting()
    c = ok and c + 1 or 0
    return c >= n
  end
end
local function bytes()
  return string.format("ba=%d d3=%d 056d=%d 056e=%d 056f=%d 026=%02X",
    H.readByte(0x00ba), H.readByte(0x00d3), H.readByte(0x056d),
    H.readByte(0x056e), H.readByte(0x056f), H.readByte(0x0026))
end

H.run({ maxFrames = 30000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.navTo(42, 29, { maxFrames = 20000 }),
  H.driveUntil(function() return map() == 225 end, 900, {
    H.hold({ "up" }), H.waitFrames(4),
  }, "clock room"),
  H.waitUntil(landed(225, 10), 1500, "clock room up", 1),
  H.waitFrames(150),
  H.navTo(98, 60, { maxFrames = 9000 }),
  H.driveUntil(function() return H.dialogWaiting() end, 900, {
    H.hold({ "up" }), H.waitFrames(6),
    H.hold({ "a", "up" }), H.waitFrames(6),
  }, "hour menu"),
  H.call(function() H.log("[hour up] " .. bytes()) end),

  -- move cursor to 2, one edge at a time, logging each move
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.readByte(0x056e) == 2 and H.readByte(0x0056d or 0x056d) == 0
    end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.readByte(0x056e) >= 2 then H.setPad({}); return end
        H.setPad(ph < 3 and { "down" } or {})    -- 3 on / 5 off: clean edges
        if ph == 0 then H.log("[climb] " .. bytes()) end
      end),
    }, "cursor to 2")
  end)(),
  H.call(function() H.log("[at 2] " .. bytes()) end),
  -- confirm with a clean A edge
  H.hold({ "a" }), H.waitFrames(4), H.release(), H.waitFrames(4),
  H.call(function() H.log("[after A hour] " .. bytes() .. " map=" .. map()) end),
  -- now log the MINUTE menu bytes as it renders in, without touching the pad
  H.waitFrames(4),
  H.call(function() H.log("[min +4]  " .. bytes()) end),
  H.waitFrames(20),
  H.call(function() H.log("[min +24] " .. bytes()) end),
  H.waitFrames(40),
  H.call(function() H.log("[min +64] " .. bytes()) end),
  -- the minute target is index 0 = cursor start.  Press ONE clean A edge.
  H.hold({ "a" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.call(function()
    H.log("[after A min] " .. bytes() .. " map=" .. map())
    local function sw(id) return (H.readByte(0x1E80+(id>>3))>>(id&7))&1 end
    H.log(string.format("$01F1=%d $01F2=%d", sw(0x1F1), sw(0x1F2)))
  end),
  H.waitFrames(60),
  H.call(function() H.log("[sec +60] " .. bytes()) end),
})
