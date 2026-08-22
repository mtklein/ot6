-- probe_iaf.lua -- the #121 survey's first probe: the Thamasa stop line and the
-- IAF/Floating-Continent entry.  See docs/design/floating-continent-route.md.
--
-- STATUS (2026-08-22): SCAFFOLD.  This verifies the stop-line entry
-- preconditions live (position + the two gating switches) and documents the
-- verified entry recipe below.  It does NOT yet drive the airship into
-- `battle 126`: that needs three drivers the harness does not have -- world
-- vehicle BOARD, world vehicle LAND, and the deck party-select MENU -- which is
-- its own piece of work (the airship-driver).  Until then the survey's IAF/FC
-- formation identities are "verify-on-arrival" and this probe pins the entry.
--
-- THE VERIFIED ENTRY RECIPE (source-cited in the survey; the drive to build):
--   0. load thamasa_done: WoB world (249,128), party of 4
--      (TERRA LOCKE STRAGO RELM), $009D=1, $009E=0.  Blackjack parked (249,127).
--   1. BOARD: walk up onto the airship at (249,127); confirm.  Free flight, no
--      refusal (the _cb2007 refusal ladder is a dead map-7 NPC).
--   2. LAND on ANY landable tile (confirm/land button) -> AirshipGround
--      (event_main.asm:172-181) sees $009D=1 && $009E=0 (no coord gate) and
--      runs the FC-discovery cutscene.  WATCH $009E: 0 -> 1 confirms it ran.
--      Ends dropping the party on the Blackjack DECK (map 6, world (249,126)).
--   3. DECK MENU: trim the party to exactly 3 (WATCH $01A2 must become 1) then
--      pick dlg $0527 option 0 "Find the Floating Continent".  A 4-party hits
--      dlg $084E "Only 3 allowed" and returns.
--   4. -> IAF ambush -> dlg $084F -> battle 126 (event_main.asm:13406),
--      formations 175/176 (Sky Armor + Spit Fire), the first of the gauntlet.
--
-- Once the drive exists, read H.formationWords() at each battle to settle the
-- IAF/FC formation table (survey §3/§4) against the offline decode.

local H = dofile("tools/tests/lib/ot6.lua")

-- event switch read: bit `id` of the flag block at $1E80 (gen_banquet_done idiom)
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

H.run({ maxFrames = 6000 }, {
  H.loadState("build/states/thamasa_done.mss.lua"),
  H.driveUntil(function() return H.worldHasControl() end, 3000, {}, "world control"),
  H.logStep(function()
    return string.format("stop line: world (%d,%d) map=%d  $009D=%d $009E=%d",
      H.worldX(), H.worldY(), H.mapId(), sw(0x009D), sw(0x009E))
  end),
  H.call(function()
    -- The entry preconditions the survey relies on (thamasa-route.md §0.1,
    -- floating-continent-route.md §1): control returns beside the Blackjack.
    H.assertEq(H.worldX(), 249, "stop-line world X = 249")
    H.assertEq(H.worldY(), 128, "stop-line world Y = 128 (one tile from the airship at 127)")
    H.assertEq(sw(0x009D), 1, "$009D=1 -- post-massacre, control on the WoB map")
    H.assertEq(sw(0x009E), 0, "$009E=0 -- FC not yet discovered (flips 1 on the land-trigger)")
    H.screenshot("iaf_stopline")
  end),
  -- TODO (airship-driver): board -> land (assert sw($009E)==1) -> deck menu
  -- trim to 3 (assert sw($01A2)==1) -> "Find the FC" -> battle 126, then read
  -- H.formationWords() through the gauntlet.  See the recipe above.
})
