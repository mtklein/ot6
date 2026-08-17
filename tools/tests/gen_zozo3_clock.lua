-- gen_zozo3_clock.lua -- v0.4 step 2a: zozo_arrival (map 221 street) -> the
-- cafe building door (42,28) -> the clock room (map 225, landing {98,61})
-- -> the clock at {98,59}, an A+facing-up tile interaction rather than an
-- NPC, solved 6:10:50, which opens the hidden staircase; generate
-- zozo_clock_solved.
--
-- The clock, from source (event_main.asm _ca96bd:22895 + event_trigger
-- _225 {98,59}):
--  * the trigger runs every frame the party stands on {98,59}; its gate is
--    $01B4 & $01B0 & !$01F0.  $01B0-$01B7 are not story switches; they are
--    the live control-flag bits of $1EB6 (field/event.asm UpdateCtrlFlags:
--    bit0-3 = facing up/right/down/left, bit4 = A held, bit5 = tile
--    latch).  Activating the clock means standing on it, facing up, and
--    holding A.
--  * the time-telling NPCs in town all give the wrong time; the correct
--    answer is hard-coded in the choice graph: hour dlg $041D, only index 2
--    ("6:00"), sets $01F1; minute dlg $041F, only index 0 ("0:10"), sets
--    $01F2; second dlg $0420, only index 4 ("0:00:50"), reaches the
--    `if_all $01F1 & $01F2` success at _ca970e.  The answer is 6:10:50.
--  * $01F1/$01F2 are zeroed on every entry, so a botched menu just retries.
--  * success (_ca9725): 4 mod_bg_tiles calls reveal a staircase at
--    x=101-102, y=45..56 (_cad067/79/8b/9d) and set $01F0 (map-local).
--    The BFS model reads the live tilemap, so the stairs are walkable to
--    it immediately.
--  * dialog choices track in $056E (EventCmd_b6); the driver below moves
--    the cursor by value (edge-presses, re-reading $056E) so the clock's
--    two-per-row layout needs no geometry knowledge.
--
-- Issue #75, playBattles: both walks pass playBattles = "tactical", so
-- neither reaches the library's monster-dead flag write.  Both maps really
-- do draw random battles -- map_prop.dat byte +5 bit 7 is set for 221 and
-- 225 (field/map.asm:143-158, field/battle.asm:333-347) -- and their pools
-- are the Zozo trash: group 78 on the street (Gabbldegak x4, Harvester +
-- Gabbldegaks, HadesGigas, HadesGigas + Harvester) and group 77 in the
-- buildings (SlamDancer, Harvester, and mixes of the two with Gabbldegaks),
-- read out of sub_battle_group.dat and rand_battle_group.dat.
--
-- Both walks name EDGAR's tool, and it is the Bio Blaster rather than the
-- default AutoCrossbow.  Every one of those eight formations is built out
-- of four species that carry an Ot6ShieldTbl row of two shields with NO
-- class byte (ot6_hud.asm:2086-2097), so no weapon and no ability this
-- party owns ever takes a shield off and every hit lands at the shielded
-- halving.  The block comment over those rows names the answer instead --
-- "the answer is the tool rather than the A button" (:2084-2085) -- and it
-- is the vanilla poison weakness all four already have (monster_prop.dat
-- +25 = $08) reached through item $a4 -> attack $7d, element $08, all
-- enemies, 0 MP (ot6_break.asm:203-204, :279-281; battle_main.asm:6577).
-- Fought
-- rather than fled for two reasons: three of those eight formations allow
-- a pincer, which raises run difficulty from 2 to 6 per monster and would
-- often spend the whole flee cap before falling back to fighting anyway;
-- and gen_zozo5_ramuh already beats this same pool on these same maps with
-- nothing but blind A-taps, so the tactical driver is comfortably enough.
-- Budgets grew to match: a battle now costs real ATB rounds mid-walk.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- Drive one clock choice dialog to `idx` and confirm, terminating when the
-- switch `doneId` latches rather than when the dialog closes: the three
-- menus are chained and $BA/$D3 dip both during each menu's text render and
-- in the gap between them, so a dialogWaiting terminator confirms with no
-- menu up (the first measured bug, probe_clock).
--
-- Each menu is a prompt page ("Please reset the minute.") that waits for A,
-- followed by the choice list.  $056F (choice count) reads 0 through the
-- prompt and only grows >=2 once the choices render (measured: the minute
-- prompt sat at $056F=0 / $D3=1 for 60+ frames until an A advanced it, then
-- $056F=5).  The hour menu looked different only because the clock-trigger
-- drive's repeated A+up presses had already advanced its prompt.  The
-- cursor $056E is a linear index, one step per d-pad edge (the $056D latch
-- blocks until release, text.asm:383).  So:
--   * prompt page ($D3=1, $056F<2): edge-A to advance to the choices;
--   * choices up ($056F>=2): edge the cursor to idx, then edge-A to confirm;
--   * anything else (text scrolling): wait.
-- idx 0 is safe under this order: only the minute's target is 0, and
-- confirming choice 0 is the correct pick there; hour(2) and second(4)
-- start below idx, so they step down before any confirm-A and cannot pick
-- the wrong entry.
local function clockPick(idx, doneId, what)
  local ph = 0
  return H.driveUntil(function() return sw(doneId) == 1 end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if sw(doneId) == 1 then H.setPad({}); return end
      local d3, maxc, cur =
        H.readByte(0x00d3), H.readByte(0x056f), H.readByte(0x056e)
      if maxc >= 2 then                       -- choices are up
        if cur < idx then
          H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then
          H.setPad(ph < 3 and { "up" } or {})
        else
          H.setPad(ph < 3 and { "a" } or {})  -- at idx: confirm
        end
      elseif d3 == 1 then                      -- prompt page: advance it
        H.setPad(ph < 3 and { "a" } or {})
      else                                     -- text scrolling: wait
        H.setPad({})
      end
    end),
  }, what)
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
  end),

  -- Top the party up before walking a map that draws encounters.
  -- zozo_arrival ships LOCKE at 69/249 -- 28%, which audit_party_hp passes
  -- because its bar is max/8.  Measured 2026-08-12: the walk below drew a
  -- Zozo street pack at (41,39) on its first screen and the tactical driver
  -- spent the step's whole 30000-frame budget in it without winning, because
  -- a party that starts a fight at 28% and takes ~116 HP a round never gets
  -- clear of the heal threshold and never gets its turns back for attacking.
  -- The fight was not lost -- nobody died -- so nothing reported a fight at
  -- all; the run reported a navigation timeout.
  H.fieldCare({ tag = "care before the Zozo streets", threshold = 0.95 }),

  -- 1. street -> the clock room: door (42,28) -> 225 {98,61}
  H.navTo(42, 29, { maxFrames = 30000, playBattles = "tactical",
                    tool = H.BIO_BLASTER }),
  H.driveUntil(function() return map() == 225 end, 900, {
    H.hold({ "up" }), H.waitFrames(4),
  }, "into the clock room"),
  H.waitUntil(landed(225, 10), 1500, "clock room up", 1),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[225] landed at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- 2. onto the clock tile {98,59} and A+facing-up until the hour menu
  H.navTo(98, 60, { maxFrames = 20000, playBattles = "tactical",
                    tool = H.BIO_BLASTER }),
  H.driveUntil(function() return H.dialogWaiting() end, 900, {
    H.hold({ "up" }), H.waitFrames(6),      -- face/step up onto {98,59}
    H.hold({ "a", "up" }), H.waitFrames(6), -- A+up: $01B4|$01B0 both set
  }, "the clock answers"),
  H.call(function()
    H.log(string.format("[clock] hour menu up at (%d,%d), $056E=%d",
      H.fieldX(), H.fieldY(), H.readByte(0x056e)))
  end),

  -- 3. 6:10:50.  Each pick confirms its own $01F* latch: hour idx 2 sets
  --    $01F1 (_ca96e2), minute idx 0 sets $01F2 (_ca96f8), second idx 4
  --    reaches the if_all success at _ca970e which sets $01F0 (_ca9725).
  --    Confirming the hour also opens the minute dialog, so the next
  --    clockPick's own ready-gate handles the handoff.
  clockPick(2, 0x01F1, "hour = 6:00"),
  clockPick(0, 0x01F2, "minute = 0:10"),
  clockPick(4, 0x01F0, "second = 0:00:50 -> the staircase"),

  -- 4. the success shake runs ~2s; $01F0 is already latched by clockPick
  H.waitUntil(function() return sw(0x01F0) == 1 end, 900,
    "$01F0 -- the staircase revealed", 5),
  -- step off the clock tile {98,59}: its trigger _ca96bd re-fires every
  -- frame the party stands on it.  It is a no-op now, because $01F0=1 hits
  -- its early EventReturn, but the event PC still enters, so eventRunning
  -- flickers and hasControl never holds.  This is the same stood-on-trigger
  -- hazard gen_mines_chase documents; walk one tile south to leave it.
  H.driveUntil(function()
    return H.fieldY() > 59 and H.hasControl() and H.tileAligned()
  end, 900, { H.hold({ "down" }), H.waitFrames(4) }, "off the clock tile"),
  H.release(),
  -- Pin the wait to (98,60) exactly.  The held press can carry one extra
  -- step onto (98,61) -- the revealed staircase's own trigger tile -- and
  -- standing there flickers eventRunning the same way the clock tile does,
  -- so the calm wait below can never hold (the enumeration regen after the
  -- #84 wave measured exactly that: ev=true at (98,61), 1200-frame
  -- timeout).  One tap back up is the same stood-on-trigger cure the step
  -- above documents.
  H.driveUntil(function()
    return H.fieldY() == 60 and H.tileAligned()
  end, 600, {
    H.call(function()
      H.setPad(H.fieldY() > 60 and { up = true } or {})
    end),
  }, "pinned off the staircase trigger"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(landed(225, 20), 1200, "calm after the shake", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 SET -- clock solved, stairs open")
    H.log(string.format("[zozo_clock_solved] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("zozo_clock_solved")
  end),
  H.saveState("zozo_clock_solved.mss"),
  H.logStep(function()
    return string.format("zozo_clock_solved generated at frame %d", H.frame)
  end),
})
