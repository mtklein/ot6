-- probe_campbag.lua -- one-shot diagnostic: reports what camp_cleared
-- carries.  Party HP/MP per character and the full non-empty inventory,
-- so the escape step's healing budget can be measured.
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/camp_cleared.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    for c = 0, 15 do
      local pb = H.readByte(0x1850 + c)
      local base = 0x1600 + 37 * c
      if (pb & 0x07) ~= 0 then
        H.log(string.format("char %2d party=%d level=%d hp=%d/%d mp=%d/%d",
          c, pb & 7, H.readByte(base + 8), H.readWord(base + 9),
          H.readWord(base + 11), H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    -- chars 3 (SHADOW) and 2 (CYAN) even if out of party right now
    for _, c in ipairs({ 2, 3, 5 }) do
      local base = 0x1600 + 37 * c
      H.log(string.format("char %2d (roster) level=%d hp=%d/%d mp=%d/%d",
        c, H.readByte(base + 8), H.readWord(base + 9),
        H.readWord(base + 11), H.readWord(base + 13), H.readWord(base + 15)))
    end
    local gil = H.readByte(0x1860) + (H.readByte(0x1861) << 8)
              + (H.readByte(0x1862) << 16)
    H.log(string.format("gil=%d", gil))
    for i = 0, 255 do
      local id = H.readByte(0x1869 + i)
      if id ~= 0xFF then
        H.log(string.format("bag[%3d] item=$%02X x%d", i, id,
          H.readByte(0x1969 + i)))
      end
    end
  end),
})
