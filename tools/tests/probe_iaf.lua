-- probe_iaf.lua -- the #121/#131 airship-driver: drive the Thamasa stop line
-- into the IAF / Floating-Continent entry, headless. See
-- docs/design/floating-continent-route.md §2/§9.
--
-- STATUS (2026-08-22): drives the VERIFIED chain from the stop line through the
-- party-select menu opening, asserting each milestone live. The final step --
-- completing FF6's party-formation menu (assign exactly 3) and reaching
-- `battle 126` -- is the one remaining TODO (see PARTY-FORMATION MENU below).
--
-- THE ENTRY CHAIN (all verified live unless noted):
--   1. BOARD: from the stop line (world (249,128), party of 4), nudge UP onto
--      the airship tile (249,127) and press A -> boards, and because
--      $009D=1 && $009E=0 the AirshipGround handler (no coord gate) diverts
--      straight into the FC-discovery cutscene.
--   2. DISCOVERY: a ~6500-frame auto-cutscene (maps 3->10->391->6->395->392->
--      394, incl. cutscene FLOATING_CONT) that ends dropping the party on the
--      Blackjack DECK (map 6, world (249,126)) and sets $009E=1.
--   3. HELM: walk onto the helm step-trigger at deck (14,6)/(15,8) -> dlg $0527
--      "Find the Floating Continent / Lift-off / Not just yet".
--   4. FIND-FC: choice option 0 -> dlg $084D -> _cacb9f `party_menu 1, RESET`.
--
-- PARTY-FORMATION MENU (the remaining TODO): `party_menu 1, RESET` empties the
-- party (menu/party.asm, ZMENUSTATE $26). States: $2c init -> $66/$68 fade ->
-- $2d/$2e/$2f = assign slots 1/2/3. In $2d, A picks the char under the cursor
-- into the party; the cursor must then MOVE to a different, unassigned char
-- before the next A (A on the already-picked char opens that char's STATUS via
-- state $42/$67/$7d -- the trap that stalled the naive drives). START in $2d
-- confirms via _c37296: it needs >=1 member or it shows "No one there!"
-- ($26=$69); the FC then requires EXACTLY 3 ($01A2=1 in _ca5817, else dlg $084E
-- "Only 3 allowed"). So: assign 3 distinct chars (A, move-cursor, A, move, A),
-- then START. The cursor navigation in this multi-party arrangement menu
-- (_c371b9) is the fiddly bit left to work out. Then _ca583a -> IAF ambush ->
-- battle 126 (event_main.asm:13406), where H.formationWords() confirms the
-- survey's offline decode (forms 175/176 Sky Armor + Spit Fire).

local H = dofile("tools/tests/lib/ot6.lua")
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function inSelect() local s = H.readByte(0x26); return s >= 0x2c and s <= 0x2f end

H.run({ maxFrames = 14000 }, {
  H.loadState("build/states/thamasa_done.mss.lua"),
  H.driveUntil(function() return H.worldHasControl() end, 3000, {}, "world control"),
  -- 0. stop-line preconditions (floating-continent-route.md §1)
  H.call(function()
    H.assertEq(H.worldX(), 249, "stop-line world X = 249")
    H.assertEq(H.worldY(), 128, "stop-line world Y = 128")
    H.assertEq(sw(0x009D), 1, "$009D=1 -- control on the WoB map post-massacre")
    H.assertEq(sw(0x009E), 0, "$009E=0 -- FC not yet discovered")
    H.screenshot("iaf_stopline")
  end),
  -- 1. board: up onto the airship tile (249,127), then A
  H.hold({ "up" }), H.waitFrames(12), H.release(), H.waitFrames(6),
  H.pressButtons({ "a" }, 4), H.waitFrames(20),
  -- 2. ride the discovery cutscene until $009E flips (advance any dialogs)
  H.driveUntil(function() return sw(0x009E) == 1 end, 10000, {
    H.call(function()
      H.setPad(H.dialogWaiting() and (H.frame % 24 < 4 and { "a" } or {}) or {})
    end)
  }, "FC discovery ($009E=1)"),
  H.call(function()
    H.assertEq(H.readWord(0x1f64) & 0x3ff, 6, "landed on the Blackjack deck (map 6)")
    H.assertEq(sw(0x009E), 1, "$009E=1 -- discovery ran")
    H.screenshot("iaf_deck")
  end),
  -- 3. helm: walk to the step-trigger -> dlg $0527
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.call(function() H.assertEq(H.dialogWaiting(), true, "helm menu dlg $0527 is up") end),
  -- 4. select "Find the Floating Continent" (cursor defaults to option 0)
  H.pressButtons({ "a" }, 4), H.waitFrames(20),
  -- ride dlg $084D into party_menu; assert the party-select menu opens
  H.driveUntil(function() return inSelect() end, 1200, {
    H.call(function() H.setPad(H.dialogWaiting() and (H.frame % 16 < 4 and { "a" } or {}) or {}) end)
  }, "party-select menu ($26 in 2c..2f)"),
  H.call(function()
    H.log(string.format("party-select open: $26=%02X -- entry chain verified through the menu",
      H.readByte(0x26)))
    H.screenshot("iaf_party_select")
  end),
  -- TODO(#131): drive the party-formation menu (assign 3 + START), then the IAF
  -- ambush -> battle 126, and read H.formationWords() to confirm forms 175/176.
  H.logStep(function() return "entry chain verified to the party-select menu" end),
})
