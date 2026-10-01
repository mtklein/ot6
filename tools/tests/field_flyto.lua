-- @suite savestate=wor_flight
-- field_flyto.lua -- #263: flying and landing the airship (H.flyTo).
--
-- The fixture is wor_flight, gen_wor_falcon's frame of the pilot's first
-- control after the Falcon's rising: aboard ($11FA = 1), the rising's own
-- scripted flight done, over world (68,187), heading 316.  From that one
-- frame the suite flies to two targets on different bearings, one per
-- branch (the fixture is loaded again for the second), each through
-- H.flyTo -- Left/Right toward the bearing, A while it is ahead, a coast to
-- a stop, A nudges for what is left, B over the target -- and asserts what
-- the game recorded: the party on foot ($11FA = 0) on the target tile, not
-- aboard ($1F64 bit 13 clear), the airship parked on that tile
-- ($1F62/$1F63, the save cells LandAirship writes).  Both targets are
-- asserted landable from the ROM's tile properties first (bit 1 of the
-- property word clear), so a failure here is the verb's and not the map's.
-- Nothing is written: every press is a pilot's.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_flight.mss.lua"
-- the route's landing (gen_wor_falcon), a turn to the left, and a wasteland
-- tile east of the start, a turn to the right (both $44: landable)
local TARGETS = { { 25, 160 }, { 128, 171 } }

local function branch(t)
  return {
    H.loadState(STATE),
    H.waitFrames(5),
    H.call(function()
      H.assertEq(H.aboardAirship(), true, "the fixture is aboard the airship ($11FA = 1)")
      local x, y = H.airshipTile()
      H.log(string.format("[flyto] from (%d,%d) heading %d to (%d,%d)", x, y, H.readWord(0x73), t[1], t[2]))
    end),
    H.flyTo(t[1], t[2], { what = string.format("fly to (%d,%d)", t[1], t[2]) }),
    H.call(function()
      H.assertEq(H.readByte(0x11FA), 0, string.format("(%d,%d): on foot ($11FA)", t[1], t[2]))
      H.assertEq(H.worldX() == t[1] and H.worldY() == t[2], true,
        string.format("(%d,%d): the party stands on the target (on (%d,%d))", t[1], t[2], H.worldX(), H.worldY()))
      H.assertEq(H.readByte(0x1F62) == t[1] and H.readByte(0x1F63) == t[2], true,
        string.format("(%d,%d): the airship is parked on it ($1F62,$1F63 = %d,%d)", t[1], t[2],
          H.readByte(0x1F62), H.readByte(0x1F63)))
      H.assertEq(H.readByte(0x1F65) & 0x20, 0, string.format("(%d,%d): not aboard ($1F64 bit 13)", t[1], t[2]))
      H.log(string.format("[flyto] PASSED (%d,%d): on foot there at f%d, the airship parked there", t[1], t[2], H.frame))
    end),
  }
end

local steps = {}
for _, t in ipairs(TARGETS) do
  for _, s in ipairs(branch(t)) do steps[#steps + 1] = s end
end
H.run({ maxFrames = 12000 }, steps)
