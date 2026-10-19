-- stall_menu_negative.lua -- run.sh's stall watch, negative control 2: the
-- game is parked in the field menu.  The emulator keeps running, the game
-- clock ticks and the screen keeps changing, but nothing happens: no step
-- completes, no goal is reached, the map, the party, the bag and every HP
-- hold still.  Frames advancing is not progress (owner, 2026-10-19), so
-- run.sh must kill it as a STALL.
-- Needs OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-owzer-v1.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 5000000, retries = 1, watchdog = false }, {
  H.bootCheckpoint("wor-owzer-v1"),
  H.waitFrames(120),
  H.driveUntil(function() return H.mainMenuUp() end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "the field menu opens"),
  H.call(function() H.log("stall_menu_negative: the menu is up; idling") end),
  H.waitFrames(4000000),
})
