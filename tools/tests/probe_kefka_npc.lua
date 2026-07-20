-- probe_kefka_npc.lua -- SPIKE instrument: why does A at (19,36) not
-- activate KEFKA (NPC_1, object 16)?  CheckNPCs (player.asm:142) has
-- three vetoes before the event dispatch: the collision bit ($087c bit6),
-- the already-activated check ($087c low nibble == 4), and the z-level
-- match ($b8&7 vs the object's $0888).  Read them all off
-- spike_doorstep.mss, then try the A press while watching them.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/spike_doorstep.mss.lua"

local KO = 16 * 0x29                    -- KEFKA = object 16's record offset

local function dump(tag)
  local po = H.readWord(0x0803)
  H.log(string.format(
    "[%s] party(%d,%d) b2=$%02X b8=$%02X face=%d | kefka mv=$%02X z=$%02X " ..
    "ev=%02X%02X%02X pos=(%d,%d) | objmap@(19,37)=%02X",
    tag, H.fieldX(), H.fieldY(), H.readByte(0x00b2),
    H.readByte(0x7E7600 + H.maptile(H.fieldX(), H.fieldY())),
    H.readByte(0x087f + po),
    H.readByte(0x087c + KO), H.readByte(0x0888 + KO),
    H.readByte(0x088b + KO), H.readByte(0x088a + KO), H.readByte(0x0889 + KO),
    H.readWord(0x086a + KO) >> 4, H.readWord(0x086d + KO) >> 4,
    H.readByte(0x7E2000 + 37 * 256 + 19)))
end

H.run({ maxFrames = 4000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function() dump("boot") end),
  -- face down, then clean edge-A presses, 8 on / 8 off, ten of them
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.call(function() dump("faced") end),
  H.repeatN(10, {
    H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
  }),
  H.call(function() dump("after-A") end),
  H.waitFrames(60),
  H.call(function()
    dump("end")
    H.log("eventRunning=" .. tostring(H.eventRunning()) ..
      " battle=" .. tostring(H.battleLoadStarted()))
  end),
})
