-- probe_fc_dump394s.lua -- dump 394's tile props from fc_shadow (the
-- crossing lineage), whose mod_bg_tiles history differs from alcove2's.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/fc_shadow.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
    H.log(string.format("m394 masks xm=%02X ym=%02X party=(%d,%d) z=%02X",
      xm, ym, H.fieldX(), H.fieldY(), H.readByte(0xb2)))
    local function tp(base, x, y)
      local tl = H.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
      return H.readByte(base + tl)
    end
    for y = 0, ym do
      local r1, r2 = {}, {}
      for x = 0, xm do
        r1[#r1+1] = string.format("%02x", tp(0x7E7600, x, y))
        r2[#r2+1] = string.format("%02x", tp(0x7E7700, x, y))
      end
      H.log(string.format("p1 y%02d %s", y, table.concat(r1)))
      H.log(string.format("p2 y%02d %s", y, table.concat(r2)))
    end
  end),
  H.logStep(function() return "done" end),
})
