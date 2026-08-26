-- probe_dump22.lua -- blind-descends 23 -> 22 (20,2) from wob_mog_done,
-- then dumps cliff 22's tile props and NPC-block map.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/wob_mog_done.mss.lua"),
  H.waitFrames(30),
  (function()
    local wps = { {10,18},{12,18},{13,19},{13,20},{24,20},{25,21},{25,31},{25,33} }
    local wi, t, wt = 1, 0, 0
    return H.driveUntil(function() return mapIs(22) end, 12000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        local wp = wps[wi]
        if not wp then H.setPad({ down = true }); return end
        local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
        wt = wt + 1
        if (dx == 0 and dy == 0) or wt > 900 then
          wi, wt = wi + 1, 0
          H.setPad({})
          return
        end
        local d = math.abs(dx) >= math.abs(dy)
          and (dx > 0 and "right" or "left")
          or (dy > 0 and "down" or "up")
        H.setPad({ [d] = true })
      end),
    }, "blind descent 23 -> 22")
  end)(),
  H.waitFrames(60),
  H.call(function()
    local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
    H.log(string.format("map %d masks xm=%02X ym=%02X party=(%d,%d) z=%02X",
      H.mapId() & 0x1ff, xm, ym, H.fieldX(), H.fieldY(), H.readByte(0xb2)))
    local function tile(x, y)
      return H.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
    end
    for y = 0, ym do
      local r1, r2, r3 = {}, {}, {}
      for x = 0, xm do
        local t = tile(x, y)
        r1[#r1+1] = string.format("%02x", H.readByte(0x7E7600 + t))
        r2[#r2+1] = string.format("%02x", H.readByte(0x7E7700 + t))
        r3[#r3+1] = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
          and "X" or "."
      end
      H.log(string.format("p1 y%02d %s", y, table.concat(r1)))
      H.log(string.format("p2 y%02d %s", y, table.concat(r2)))
      H.log(string.format("nb y%02d %s", y, table.concat(r3)))
    end
  end),
  H.logStep(function() return "done" end),
})
