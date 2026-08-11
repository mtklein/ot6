-- shot_battle_items.lua -- SCREENSHOT EVIDENCE for weapon-class icons in the
-- battle Item list.
--
-- ISSUE #75 CONVERSION.  This script used to poke one weapon per break class
-- into the magitek entry point's empty bag and shoot the forged list.  It now
-- boots vector_entry -- the class-richest REAL bag on the chain (see
-- shot_field_items.lua's header for the recon; PIERCE + SLASH is everything
-- any v0.6 save owns in normal play) -- walks one step south out of Vector onto the
-- world map (the fixture stands on the long entrance at map 242 (32,61);
-- measured: a held DOWN reaches the world in ~30 frames), walks the
-- random-battle area into a REAL world encounter, and shoots the Item list
-- the battle menu builds from the save's own $1869 bag.
--
-- The weapon rows in the measured bag order (battle list order = bag order):
--   row  9 Dirk PIERCE, row 19 ThunderBlade SLASH, row 23 MithrilKnife
--   PIERCE, row 26 Ashura SLASH -- with TOOL/RELIC/consumable rows around
--   them for the no-class face.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_entry.mss.lua"

local MENU = 0x7BCA

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 242, "vector_entry stands in Vector")
  end),

  -- south out of the town onto the world map
  H.driveUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, { H.call(function() H.setPad({ down = true }) end) },
    "walk south out of Vector to the world"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(30),

  -- the random-battle area right outside the trigger: pace until the world's
  -- own encounter roll wins (battle_gaufight's Veldt-grind pacing, no danger
  -- poke)
  (function()
    local flip = false
    return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, "a real world encounter fires")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  -- input during the first window-open animation wedges the battle menu
  H.waitFrames(240),

  H.waitUntil(function() return H.readByte(MENU) ~= 0 end, 1200,
    "command window ready", 10),
  H.call(function()
    -- battle command table: 4 x [cmd, ?, targeting] per slot -- logged so the
    -- shot is self-describing (real kits now, not installs)
    for slot = 0, 3 do
      local base = 0x202e + 12 * slot
      H.log(string.format("cmds slot %d: %02X %02X %02X %02X", slot,
        H.readByte(base), H.readByte(base + 3),
        H.readByte(base + 6), H.readByte(base + 9)))
    end
  end),

  -- Item is the LAST command row for this real party (FIGHT/kit/MAGIC/ITEM);
  -- up from the top wraps straight to it
  H.pressButtons({ "up" }, 4), H.waitFrames(12),
  H.pressButtons({ "a" }, 4),
  H.waitFrames(180),
  H.call(function() H.screenshot("battle_items_top") end),

  -- scroll to the first weapon block (Dirk, bag row 9)
  H.repeatN(9, { H.pressButtons({ "down" }, 4), H.waitFrames(12) }),
  H.waitFrames(30),
  H.call(function() H.screenshot("battle_items_pierce") end),

  -- and to the SLASH rows (ThunderBlade row 19 .. Ashura row 26)
  H.repeatN(12, { H.pressButtons({ "down" }, 4), H.waitFrames(12) }),
  H.waitFrames(30),
  H.call(function() H.screenshot("battle_items_slash") end),
  H.repeatN(6, { H.pressButtons({ "down" }, 4), H.waitFrames(12) }),
  H.waitFrames(30),
  H.call(function() H.screenshot("battle_items_scrolled") end),
})
