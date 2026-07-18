-- gen_worldmap.lua -- from moogle_cleared.mss (LOCKE leading TERRA on the
-- Narshe streets, map 20): walk out the south gate onto the World of
-- Balance and mint worldmap_narshe.mss at the first controllable world
-- moment.  This is the harness's FIRST world-map state, so the script
-- doubles as the recording instrument for the transition: every mode/
-- position/flag byte the world navigator will build on gets logged.
--
-- THE EXIT (all static, verified against the built ROM):
--   * map 20's south edge is one long entrance: horizontal run y=62,
--     x=0..43, destination map $1FF = "load parent map"
--     (trigger/long_entrance.dat via parse; record semantics
--     field/entrance.asm CheckLongEntrance -> LoadParentMap)
--   * the parent was seeded by the game-start event: `set_parent_map 0,
--     {84, 33}, UP` (event_main.asm:14159) -- the same record entering
--     Narshe from the world would write (its WoB short entrance is
--     src=(84,33) -> map 20 dest=(38,61))
--   * LoadParentMap inverts the saved facing and steps one tile past it
--     (RestoreParentMap, entrance.asm:246-258): UP inverted = DOWN, so
--     the party lands at WoB (84,34) facing DOWN
--   * $1F64 gets `Map & $FE00 | $1F69` (entrance.asm:125-…): the $1FF
--     record's flag byte is $21 (facing DOWN in bits 4-5), so the stored
--     word is predicted $2000 -- "on the world map" is a MASKED test,
--     (word & $3FF) < 3 per the top-level dispatch (field/reset.asm:66),
--     never a raw compare.  The live value is logged and asserted here.
--
-- WORLD-SIDE RAM (world/move.asm MovePlayer, GetPlayerInput; the world
-- module keeps DP=$0000 -- world_start.asm has no phd/pld and its menu
-- path reads $e0 plain -- so these are absolute zero-page):
--   $E0/$E2 tile x/y (the 16-bit position words at $DF/$E1 are
--   tile*256+fraction; $DF/$E1 low bytes are the sub-tile fractions),
--   $E3/$E5 velocity, $F6 facing, $E7 bit0 = world event running,
--   $19 = fade/exit trigger, $E8 bit0 = menu opening.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local CLEARED = "/Users/mtklein/ot6/build/states/moogle_cleared.mss.lua"

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- on the world map iff (mapId & $3FF) < 3 (field/reset.asm:66 masks
-- #$03ff; the doc's 0x1FF claim is the loose one -- bit9 rides along in
-- $1F64 for SET_PARENT loads, and the dispatch masks it IN)
local function worldMode() return (H.readWord(0x1f64) & 0x3FF) < 3 end

local function wx() return H.readByte(0x00e0) end
local function wy() return H.readByte(0x00e2) end
local function wAligned()
  return H.readByte(0x00df) == 0 and H.readByte(0x00e1) == 0
end

H.run({ maxFrames = 20000 }, {
  H.loadState(CLEARED),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "streets control", 5),
  H.call(function()
    H.assertEq(H.mapId(), 20, "boot map is the Narshe streets (map 20)")
    H.assertEq(H.readByte(0x1850) & 0x07, 1, "TERRA in party 1")
    H.assertEq(H.readByte(0x1851) & 0x07, 1, "LOCKE in party 1")
    H.log(string.format("booted at (%d,%d); heading for the south gate",
      H.fieldX(), H.fieldY()))
  end),

  -- ===================================================================== --
  -- To the gate: BFS to (38,61) -- the tile Narshe's world entrance drops
  -- visitors on, one north of the y=62 exit row -- then one deliberate
  -- held step south onto the row.  The exit row itself is left out of the
  -- BFS target so the transition happens on OUR step, not mid-plan.
  -- ===================================================================== --
  H.navTo(38, 61, { maxFrames = 6000 }),
  H.logStep(function()
    return string.format("at the gate (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame)
  end),
  H.driveUntil(function() return worldMode() end, 600, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "world map loads"),
  H.release(),

  -- ===================================================================== --
  -- Settle: the world re-inits through its own fade (LoadWorldMap ->
  -- InitWorld).  Wait for the world event flag to clear, the fade
  -- trigger to be idle, full brightness, and tile alignment, then the
  -- +30 frame margin the field fixtures use after every map load.
  -- ===================================================================== --
  H.waitUntil(function()
    return worldMode() and H.readByte(0x0019) == 0
       and (H.readByte(0x00e7) & 0x01) == 0 and wAligned()
  end, 900, "world control gates", 5),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "world fade-in", 10),
  H.waitFrames(30),

  -- ===================================================================== --
  -- Record the transition (this block feeds world-map-nav.md's live-probe
  -- checklist) and assert the statically-predicted spawn.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[record] $1F64 raw=%04X &1FF=%03X &3FF=%03X &FF=%02X",
      H.readWord(0x1f64), H.readWord(0x1f64) & 0x1FF,
      H.readWord(0x1f64) & 0x3FF, H.readWord(0x1f64) & 0xFF))
    H.log(string.format("[record] tile $E0/$E2=(%d,%d) frac $DF/$E1=(%d,%d)",
      wx(), wy(), H.readByte(0x00df), H.readByte(0x00e1)))
    H.log(string.format("[record] saved $1F60/61=(%d,%d) facing $F6=%d $1F68=%02X",
      H.readByte(0x1f60), H.readByte(0x1f61),
      H.readByte(0x00f6), H.readByte(0x1f68)))
    H.log(string.format("[record] $20=%02X $11FA=%02X $11F3=%02X $E7=%02X $E8=%02X $E9=%02X $19=%02X",
      H.readByte(0x0020), H.readByte(0x11fa), H.readByte(0x11f3),
      H.readByte(0x00e7), H.readByte(0x00e8), H.readByte(0x00e9),
      H.readByte(0x0019)))
    H.assertEq(H.readWord(0x1f64) & 0x3FF, 0, "on the World of Balance")
    H.assertEq(wx() == 84 and wy() == 34, true,
      string.format("world spawn (84,34) predicted from set_parent_map " ..
        "(got %d,%d)", wx(), wy()))
    H.assertEq(H.readByte(0x11fa) & 0x03, 0, "on foot (vehicle bits clear)")
    H.screenshot("worldmap_narshe")
  end),
  H.saveState("worldmap_narshe.mss"),
  H.logStep(function()
    return string.format("worldmap_narshe minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- Positive control (post-mint, so the state stays virgin): prove the
  -- pad drives world movement.  Narshe sits in mountains, so try each
  -- direction until the tile budges; log which ones worked.
  -- ===================================================================== --
  H.call(function()
    local dirs = { "down", "left", "right", "up" }
    H.log("positive control: probing steps " .. table.concat(dirs, ","))
  end),
  H.driveUntil((function()
    local sx, sy = nil, nil
    return function()
      if sx == nil then sx, sy = wx(), wy() end
      return wx() ~= sx or wy() ~= sy
    end
  end)(), 400, {
    H.hold({ "down" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "left" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "right" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "up" }), H.waitFrames(24), H.release(), H.waitFrames(4),
  }, "a world step lands"),
  H.release(),
  H.call(function()
    H.log(string.format("positive control: moved to (%d,%d) facing %d, frame %d",
      wx(), wy(), H.readByte(0x00f6), H.frame))
  end),
})
