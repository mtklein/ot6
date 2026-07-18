-- probe_route.lua -- validate H.route, the field/world handoff driver,
-- on the one mode crossing the chain owns: Narshe streets -> world map.
-- From moogle_cleared.mss: leg 1 is field-nav onto the south-edge exit
-- row (38,62) with arrive=worldMode -- the long entrance fires DURING
-- the landing, so the leg's own arrive is what sees the crossing (the
-- driver's contract: a crossing leg declares its arrive; the NEXT leg
-- then finds its mode already up and just settles).  Leg 2 is world-nav
-- four tiles south to (84,38), proving the driver settled the world
-- side and the world walker runs after a field leg in the same script.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local CLEARED = "/Users/mtklein/ot6/build/states/moogle_cleared.mss.lua"

local function P(fmt, ...) print("[probe] " .. string.format(fmt, ...)) end

H.run({ maxFrames = 10000 }, {
  H.loadState(CLEARED),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.mapId(), 20, "boot map is the Narshe streets")
    H.assertEq(H.worldMode(), false, "field mode at boot")
  end),
  H.route({
    { mode = "field", x = 38, y = 62,
      opts = { arrive = H.worldMode, maxFrames = 6000 } },
    { mode = "world", x = 84, y = 38, opts = { maxFrames = 4000 } },
  }),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map after the route")
    H.assertEq(H.worldX() == 84 and H.worldY() == 38, true,
      string.format("route landed (84,38) (got %d,%d)",
        H.worldX(), H.worldY()))
    P("route driver ok: field leg crossed modes, world leg walked; frame %d",
      H.frame)
  end),
})
