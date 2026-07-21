-- gen_zozo3_clock.lua -- v0.4 leg 2a: zozo_arrival (map 221 street) -> the
-- CAFE building door (42,28) -> the clock room (map 225, landing {98,61})
-- -> THE CLOCK at {98,59}: an A+facing-up tile interaction (NOT an NPC),
-- solved 6:10:50 -> the hidden staircase opens -> mint zozo_clock_solved.
--
-- THE CLOCK, from source (event_main.asm _ca96bd:22895 + event_trigger
-- _225 {98,59}):
--  * the trigger runs EVERY frame the party stands on {98,59}; its gate is
--    $01B4 & $01B0 & !$01F0 -- and $01B0-$01B7 are NOT story switches but
--    the LIVE control-flag bits of $1EB6 (field/event.asm UpdateCtrlFlags:
--    bit0-3 = facing up/right/down/left, bit4 = A held, bit5 = tile
--    latch).  So "activate the clock" = stand on it, face up, hold A.
--  * every time-telling NPC in town LIES; the truth is authored straight
--    into the choice graph: hour dlg $041D -- ONLY index 2 ("6:00") sets
--    $01F1; minute dlg $041F -- ONLY index 0 ("0:10") sets $01F2; second
--    dlg $0420 -- ONLY index 4 ("0:00:50") reaches the `if_all $01F1 &
--    $01F2` success at _ca970e.  6:10:50, hard-coded.
--  * $01F1/$01F2 are zeroed on every entry, so a botched menu just retries.
--  * success (_ca9725): 4 mod_bg_tiles calls reveal a staircase at
--    x=101-102, y=45..56 (_cad067/79/8b/9d) and set $01F0 (map-local) --
--    the BFS model reads the live tilemap, so the stairs are walkable to
--    it immediately.
--  * dialog choices track in $056E (EventCmd_b6); the driver below moves
--    the cursor by VALUE (edge-presses, re-reading $056E) so the clock's
--    two-per-row layout needs no geometry knowledge.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

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
-- switch `doneId` latches (NOT on "dialog closed": the three menus are
-- CHAINED and $BA/$D3 dip both during each menu's text render and in the
-- gap between them, so a dialogWaiting terminator confirms into the void --
-- the first measured bug, probe_clock).
--
-- Each menu is a PROMPT PAGE ("Please reset the minute.") that waits for A,
-- THEN the choice list.  $056F (choice count) reads 0 through the prompt
-- and only grows >=2 once the choices render (measured: the minute prompt
-- sat at $056F=0 / $D3=1 for 60+ frames until an A advanced it, then
-- $056F=5).  The hour menu looked different only because the clock-trigger
-- drive's repeated A+up presses had already advanced its prompt.  The
-- cursor $056E is a LINEAR index, one step per d-pad EDGE (the $056D latch
-- blocks until release, text.asm:383).  So:
--   * prompt page ($D3=1, $056F<2): edge-A to advance to the choices;
--   * choices up ($056F>=2): edge the cursor to idx, then edge-A to confirm;
--   * anything else (text scrolling): wait.
-- idx 0 is safe under this order -- only the minute's target is 0, and
-- confirming choice 0 is exactly right; hour(2)/second(4) start below idx
-- so they step DOWN before any confirm-A, never a stray pick.
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

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
  end),

  -- 1. street -> the clock room: door (42,28) -> 225 {98,61}
  H.navTo(42, 29, { maxFrames = 20000 }),
  H.driveUntil(function() return map() == 225 end, 900, {
    H.hold({ "up" }), H.waitFrames(4),
  }, "into the clock room"),
  H.waitUntil(landed(225, 10), 1500, "clock room up", 1),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[225] landed at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- 2. onto the clock tile {98,59} and A+facing-up until the hour menu
  H.navTo(98, 60, { maxFrames = 9000 }),
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
  -- step OFF the clock tile {98,59}: its trigger _ca96bd re-fires every
  -- frame the party stands on it (now a no-op -- $01F0=1 hits its early
  -- EventReturn -- but the event PC still bounces in, so eventRunning
  -- flickers and hasControl never holds).  The same stood-on-trigger trap
  -- gen_mines_chase documents; walk one tile south to escape it.
  H.driveUntil(function()
    return H.fieldY() > 59 and H.hasControl() and H.tileAligned()
  end, 900, { H.hold({ "down" }), H.waitFrames(4) }, "off the clock tile"),
  H.release(),
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
    return string.format("zozo_clock_solved minted at frame %d", H.frame)
  end),
})
