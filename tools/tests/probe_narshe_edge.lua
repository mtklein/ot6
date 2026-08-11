-- probe_narshe_edge.lua -- spike instrument: measures whether the engine
-- allows steps the ported model refuses at the party-region boundary.
-- Kefka's pocket is model-unreachable (probe_narshe_map2: zero crossings),
-- yet raider o25 walked column x=18 through the boundary range and vanilla
-- players descend these cliffs.  Stand at candidate boundary tiles and
-- press into them; log what the engine does.  30-second verdict per edge.
-- Issue #75: playBattles = "tactical" keeps this walk out of the library's
-- monster-dead flag write.  It is intent only -- map 22, the Narshe defense, draws no random battles (map_prop.dat byte +5
-- bit 7 clear, so the field step handler at ff6/src/field/battle.asm:333-347
-- returns before the roll) -- and "tactical" rather than "flee" because the
-- only battle that could reach the option there is an unscripted surprise.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/spike_defense.mss.lua"

local function tryEdge(x, y, dir, n)
  return H.cond(function() return true end, {
    H.navTo(x, y, { maxFrames = 6000, playBattles = "tactical" }),
    H.call(function()
      H.log(string.format("[edge] at (%d,%d) z=$%02X b8=$%02X pushing %s",
        H.fieldX(), H.fieldY(), H.readByte(0x00b2),
        H.readByte(0x7E7600 + H.maptile(H.fieldX(), H.fieldY())), dir))
    end),
    H.hold({ dir }), H.waitFrames(n or 40), H.release(), H.waitFrames(10),
    H.call(function()
      H.log(string.format("[edge] -> now at (%d,%d) z=$%02X canStep said %s",
        H.fieldX(), H.fieldY(), H.readByte(0x00b2),
        tostring(H.canStep(x, y, dir))))
    end),
  })
end

H.run({ maxFrames = 30000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  -- candidate 1: (19,12) down (o25's column crossed at x=18/19)
  tryEdge(19, 12, "down"),
  -- candidate 2: (23,15) down (the z-cut end of the party's east arm)
  tryEdge(23, 15, "down", 60),
  -- candidate 3: (23,13) right (eastward off the arm)
  tryEdge(23, 13, "right"),
  -- candidate 4: (18,11) down
  tryEdge(18, 11, "down"),
  H.call(function() H.screenshot("edge_probe_end") end),
})
