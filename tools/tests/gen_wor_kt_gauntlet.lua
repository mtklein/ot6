-- gen_wor_kt_gauntlet.lua -- Kefka's Tower, a branch: the Gauntlet and the Nutkin Suit (docs/design/
-- route-wor-kefka-tower.md section 5): Continue the `wor-kt-inferno-v1` battery (party 3 on the factory's save point
-- after Inferno, 410 (37,17)), then party 3 out of the factory's hall by its tile (43,23) to the west column, back
-- through 339 to 334's east side, into 339's foot (334 (48,36)), through 339 (37,44) to 296, the dead end that holds
-- the factory hall's two chests, and opens both: the Nutkin Suit (296 (38,12), bit $0E1) and the Gauntlet (296
-- (49,12), bit $0EB).
-- The middle path leaves them (the line's play goes on from the factory to the sparkle); this branch fetches them,
-- and nothing boots it.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local MACHINES = { [0x0FD] = true, [0x0D9] = true, [0x0EA] = true, [0x0ED] = true, [0x0F6] = true, [0x105] = true,
  [0x0FC] = true, [0x0A1] = true }
local VECTAUR, BRONTAUR, OSCAR = 0x080, 0x084, 0x0B7
local FIRE, ICE, BOLT = 0x00, 0x01, 0x02
local FIGHT = {}
FIGHT.nuke = function()
  if H.formationHas({ [OSCAR] = true }) then return { FIRE } end
  if H.formationHas(MACHINES) then return { BOLT } end
  if H.formationHas({ [VECTAUR] = true, [BRONTAUR] = true }) then return { ICE } end
  return nil
end
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door, chest = T.walk, T.door, T.chest
local NUTKIN, GAUNTLET = 0x0E1, 0x0EB
-- an exit to another part of the same map (T.door judges arrival by the map): from the tile above it, down until
-- landed() reads true
local function hop(x, y, what, landed)
  return H.seqStep({
    walk(x, y - 1, what .. ": the tile above it"),
    H.driveUntil(function() return map() == 410 and landed() and settled() end, 600,
      { H.hold({ "down" }), H.waitFrames(2) }, what .. ": pressing down"),
    H.release(),
    H.call(function() say("route", what) end),
  })
end

H.run({ maxFrames = 1200000 }, {
  H.bootCheckpoint("wor-kt-inferno-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (Inferno beaten, party 3 walking on the factory's save point).  Asserted
  -- here: the two chests still shut (nothing upstream opens them: the factory's own walk does not reach 296).
  H.call(function()
    say("tower", "boot")
    H.assertEq(H.activeParty(), 3, "party 3 walks (gen_wor_kt_inferno left it on the factory's save point)")
    H.assertEq(H.chestOpen(NUTKIN) or H.chestOpen(GAUNTLET), false, "296's two chests still shut")
  end),
  -- @@setup-end

  -- @@stage walk
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 1 } }),
  -- the hall's tile (43,23) (_cc13c6) carries the party back to the factory's west column (410 (6,17)), the one
  -- that 339 reaches: stepped onto from the tile above
  hop(43, 23, "party 3: the hall's tile 410 (43,23) -> the west column (6,17)",
    function() return H.fieldX() < 20 end),
  door(12, 19, 339, "party 3: 410 (12,19) -> 339 (31,12)"),
  door(36, 15, 334, "party 3: 339's top door (36,15) -> 334 (52,49)"),
  door(48, 36, 339, "party 3: 334 (48,36) -> 339's foot (39,57)"),
  door(37, 44, 296, "party 3: 339 (37,44) -> 296 (37,23)"),

  -- @@stage chests
  chest(38, 12, NUTKIN, "Nutkin Suit (296 (38,12))", true),
  chest(49, 12, GAUNTLET, "Gauntlet (296 (49,12))", true),
  H.call(function()
    H.assertEq(H.chestOpen(NUTKIN) and H.chestOpen(GAUNTLET), true, "both of 296's chests open")
    say("tower", "the Nutkin Suit and the Gauntlet in the bag")
  end),
  H.splitEnd(),
  H.saveState("wor_kt_gauntlet.mss"),
  H.logStep(function()
    return string.format("wor_kt_gauntlet generated: %s", H.partiesLine())
  end),
})
