-- gen_figaro.lua -- from worldmap_narshe.mss (LOCKE + TERRA on foot at
-- WoB (84,34)): world-nav south across the plains to Figaro Castle's
-- gate trigger, ride the entry event into the castle complex, and generate
-- figaro_doorstep.mss at the first controllable interior moment.  The
-- Edgar/Kefka sequence beyond is the NEXT stretch, not this script's.
--
-- THE GATE (read + live-probed, see world-map-nav.md "Warp / teleport levers"):
--   * Figaro is a WORLD EVENT TRIGGER, not a short entrance: tiles
--     (64,76)/(65,76) -> _ca5eb5 (event_main.asm:14184), gated
--     `if_switch $010B=0, WorldReturn` -- $010B was set by the
--     game-start event (:14157), so it is live on this route ($010B ->
--     $1EA1 mask $08, asserted before the walk)
--   * the event body: `load_map 55, {28,42}, UP, {Z_UPPER, SHOW_TITLE,
--     SET_PARENT, STARTUP_EVENT}` -- so the arrival map is 55, the
--     castle-complex exterior; its map-init (_caea1a) just starts two
--     patrol NPC loops.  $1F64 measured $0037 raw on arrival (the
--     SET_PARENT bit is consumed by the load, not stored); compares
--     stay MASKED (& $1FF) anyway -- other loaders DO leave flag bits
--     in the word (the Narshe exit leaves $2000).
--     Map 54 -- which an earlier route note called the interior -- has
--     ZERO entrances and is only used mid-submerge (event_main.asm:
--     14633); the enterable castle is 55, its inner doors lead to the
--     throne wing map 59 (short-entrance table).
--   * the route (84,34) -> (64,77) BFS'd 63 steps over the verified
--     1-bit passability rule and was DRIVEN end to end by probe_world3,
--     random encounter + world reload included, before this script
--     existed.  worldNavTo targets (64,77) -- one tile SOUTH of the
--     trigger -- then takes the deliberate step north, the same
--     entry point discipline every trigger fixture uses.
local H = dofile("tools/tests/lib/ot6.lua")
local WORLD = "build/states/worldmap_narshe.mss.lua"

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

H.run({ maxFrames = 90000 }, {
  H.loadState(WORLD),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot state is on the world map")
    H.assertEq(H.worldId(), 0, "World of Balance")
    H.assertEq(H.worldX() == 84 and H.worldY() == 34, true,
      "at the Narshe spawn (84,34)")
    H.assertEq((H.readByte(0x1ea1) & 0x08) ~= 0, true,
      "Figaro gate switch $010B set (trigger live)")
  end),

  -- ===================================================================== --
  -- The world step: (84,34) -> (64,77), one south of the gate trigger.
  -- Random encounters are FOUGHT inline by worldNavTo (real tap-A play,
  -- issue #75 -- the plains trash dies to a swing or two and the XP is the
  -- XP a walking player banks; the world reloads itself after each fight
  -- and position survives, measured).  An input-driven fight costs real ATB
  -- rounds, so the step budget triples over the battle-clear-write era's.
  -- ===================================================================== --
  H.worldNavTo(64, 77, { maxFrames = 45000, playBattles = true }),
  H.logStep(function()
    return string.format("at the Figaro entry point (%d,%d), frame %d, danger=%04X",
      H.worldX(), H.worldY(), H.frame, H.readWord(0x1f6e))
  end),

  -- ===================================================================== --
  -- The deliberate step onto (64,76): the world event takes over ($E7
  -- bit0), fades, and loads map 55.  A last-tile random encounter is
  -- FOUGHT inline by the same edge-tapped A that pages the victory text
  -- (real play, zero writes -- issue #75); the world reload then puts
  -- the party back on the tile and the step re-presses.  Budget covers a
  -- full input-driven fight plus the entry event.
  -- ===================================================================== --
  H.driveUntil(function() return not H.worldMode() end, 9000, {
    H.call(function()
      if H.battleLoadStarted() then
        H.setPad(H.frame % 8 < 4 and { "a" } or {})
        return
      end
      if not H.worldAligned() then return end
      H.setPad({ up = true })
    end),
  }, "Figaro entry event loads the castle"),
  H.release(),

  -- field-side settle: control + full brightness + margin (the standard
  -- post-map-load discipline)
  H.waitUntil(calm(30), 1200, "castle control", 5),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "castle fade-in", 10),
  H.waitFrames(30),

  -- ===================================================================== --
  -- Assert + generate.  Masked map compare: SET_PARENT rode bit9 into
  -- $1F64 (raw $0237, recorded below).
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[record] castle arrival: $1F64 raw=%04X (masked %d)",
      H.readWord(0x1f64), H.readWord(0x1f64) & 0x1FF))
    H.assertEq(H.readWord(0x1f64) & 0x1FF, 55,
      "on the Figaro Castle complex (map 55)")
    H.assertEq(H.fieldX() == 28 and H.fieldY() == 42, true,
      string.format("at the castle gate (28,42) (got %d,%d)",
        H.fieldX(), H.fieldY()))
    H.assertEq(H.readByte(0x1850) & 0x07, 1, "TERRA in party 1")
    H.assertEq(H.readByte(0x1851) & 0x07, 1, "LOCKE in party 1")
    -- story switches consistent: defense won ($0631 clear), collapse
    -- chain done ($012E set), Figaro position-A flag still set
    H.assertEq((H.readByte(0x1f46) & 0x02), 0, "defense-won switch state")
    H.assertEq((H.readByte(0x1ea5) & 0x40) ~= 0, true, "$012E set")
    H.assertEq((H.readByte(0x1ea1) & 0x08) ~= 0, true, "$010B still set")
    H.log(string.format("figaro entry point: map=%d (%d,%d) frame=%d",
      H.readWord(0x1f64) & 0x1FF, H.fieldX(), H.fieldY(), H.frame))
    H.screenshot("figaro_doorstep")
  end),
  H.saveState("figaro_doorstep.mss"),
  H.logStep(function()
    return string.format("figaro_doorstep generated at frame %d", H.frame)
  end),
})
