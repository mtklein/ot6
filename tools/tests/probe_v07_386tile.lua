-- probe_v07_386tile.lua -- measures why held up from (74,54) does not reach
-- the map-386 save point at (74,53).  Not a suite test.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function prop(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function objfree(x, y)
  return (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) ~= 0
end

H.run({ maxFrames = 4000 }, {
  H.loadState("build/states/v07q_386_save.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("[boot] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
    for y = 51, 56 do
      local r = {}
      for x = 71, 77 do
        r[#r + 1] = string.format("%02X%s", prop(x, y),
          objfree(x, y) and " " or "*")
      end
      H.log(string.format("[386 y=%02d x=71..77] %s", y, table.concat(r, " ")))
    end
    H.log(string.format("[386] canStep up from (74,54): %s",
      tostring(H.canStep(74, 54, "up"))))
    -- object scan
    for i = 0x10, 0x30 do
      local off = 0x29 * i
      local ox = H.readWord(0x086a + off) >> 4
      local oy = H.readWord(0x086d + off) >> 4
      if ox > 0 or oy > 0 then
        H.log(string.format("[obj %02X] (%d,%d)", i, ox, oy))
      end
    end
  end),
  (function() local ph, n = 0, 0
    return H.driveUntil(function()
      return sw(0x01BF) == 1 or n > 600
    end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        n = n + 1
        if n % 60 == 0 then
          H.log(string.format("[up] f%d (%d,%d) al=%d ctl=%d $01BF=%d "
            .. "$01B5=%d ev=%02X%02X%02X", H.frame, H.fieldX(), H.fieldY(),
            H.tileAligned() and 1 or 0, H.hasControl() and 1 or 0,
            sw(0x01BF), sw(0x01B5),
            H.readByte(0xe7), H.readByte(0xe6), H.readByte(0xe5)))
        end
        H.setPad({ up = true })
      end),
    }, "held UP watch")
  end)(),
  H.call(function()
    H.log(string.format("[end] (%d,%d) $01BF=%d $01B5=%d",
      H.fieldX(), H.fieldY(), sw(0x01BF), sw(0x01B5)))
    H.screenshot("v07_386_up_end")
  end),
})
