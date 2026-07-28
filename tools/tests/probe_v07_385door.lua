-- probe_v07_385door.lua -- what a RANDOM ENCOUNTER does to the map-385
-- timed floor, and how the exit door behaves after it.  NOT a suite test.
--
-- v07q_385_door.mss is the walk probe's park at (13,12) with cycle B
-- running -- and, it turns out, with a Zombone encounter already
-- committed: the first held-DOWN step rolled it ($59=52 was the BATTLE
-- module, not a menu; door_t1.png shows the Zombone HUD).  This instrument
-- rides the battle out with the kill-bit idiom and answers:
--   * do the $01F0-$01FF cycle switches survive the battle round-trip
--     (gen_edgar measured LoadMap zeroing $1EBE/$1EBF -- does a battle
--     return count)?
--   * does the tilemap come back armed or reverted to the unarmed base?
--   * does the (13,13) door then work under a plain held DOWN?
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function prop(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function hpsum()
  return H.readWord(0x1609) + H.readWord(0x1609 + 37)
       + H.readWord(0x1609 + 74) + H.readWord(0x1609 + 111)
end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function dumpSw(tag)
  H.log(string.format("[%s] map=%d (%d,%d) hp=%d $01F0=%d $01F1=%d $01F3=%d "
    .. "$01F4=%d $01F5=%d $01F6=%d p(13,13)=%02X p(11,4)=%02X p(5,2)=%02X",
    tag, map(), H.fieldX(), H.fieldY(), hpsum(), sw(0x01F0), sw(0x01F1),
    sw(0x01F3), sw(0x01F4), sw(0x01F5), sw(0x01F6),
    prop(13, 13), prop(11, 4), prop(5, 2)))
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/v07q_385_door.mss.lua"),
  H.waitFrames(30),
  H.call(function() dumpSw("boot") end),

  -- ride the committed encounter out with the kill-bit idiom
  H.waitUntil(function() return H.battleLoadStarted() end, 1200,
    "the committed encounter comes up", 5),
  (function() local ph = 0
    return H.driveUntil(function()
      return not H.battleLoadStarted() and map() == 385
         and H.tileAligned()
    end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then killBitAll() end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "kill-bit the Zombone and return to the field")
  end)(),
  H.waitFrames(90),
  H.call(function()
    dumpSw("after-battle")
    H.screenshot("door_postbattle")
  end),
  -- watch 400 frames: do the phases still flip?
  (function()
    local n, flips, last = 0, 0, nil
    return H.driveUntil(function() return n >= 400 end, 500, {
      H.call(function()
        n = n + 1
        local cur = sw(0x01F6)
        if last ~= nil and cur ~= last then
          flips = flips + 1
          H.log(string.format("[post] flip at +%d -> $01F5=%d $01F6=%d",
            n, sw(0x01F5), sw(0x01F6)))
        end
        last = cur
        H.setPad({})
      end),
    }, "watch for post-battle flips")
  end)(),
  H.call(function() dumpSw("post-watch") end),

  -- and the door itself
  (function() local ph = 0
    return H.driveUntil(function() return map() == 384 end, 2400, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
        end
        H.setPad({ down = true })
      end),
    }, "held DOWN onto (13,13) -> map 384")
  end)(),
  H.waitFrames(60),
  H.call(function()
    dumpSw("landed")
    H.assertEq(map(), 384, "BASEMENT 3 is map 384")
    H.log(string.format("[384] landed at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("door_384")
  end),
})
