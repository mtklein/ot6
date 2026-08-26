-- gen_zozo3_clock.lua -- v0.4 step 2a: zozo_arrival (map 221 street) -> the
-- cafe building door (42,28) -> the clock room (map 225, landing {98,61})
-- -> the clock at {98,59}, an A+facing-up tile interaction rather than an
-- NPC, solved 6:10:50, which opens the hidden staircase; generate
-- zozo_clock_solved.

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
      -- btl, the event PC and the battle-HP words are here because a
      -- heartbeat without them once read as "a held scene": a random
      -- encounter that nothing was fighting shows exactly ctl=false ev=true,
      -- and only these three separate it from a script (gen_zozo4's hangLine
      -- is the idiom).
      local raw = {}
      for e = 0, 3 do raw[#raw + 1] = string.format("%04X",
        H.readWord(0x3BF4 + e * 2)) end
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s " ..
        "btl=%s evPC=%02X:%02X%02X bhp=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        tostring(H.battleLoadStarted()),
        H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
        table.concat(raw, ","), H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

local function battleHpAllZero()
  for e = 0, 3 do
    if H.readWord(0x3BF4 + e * 2) ~= 0 then return false end
  end
  return true
end
-- A rolled encounter must be FOUGHT, not sat through: map 225 rolls random
-- battles on every step, and an un-fought battle can grind the party down
-- across a wait's whole budget. This is gen_zozo4's `encounters` rider.
local function encounters(what)
  local F = H.newFightDriver(what, { tactical = true, boost = true,
    items = true, healPercent = 55, tool = H.BIO_BLASTER })
  local dead = 0
  return function()
    if battleHpAllZero() and not H.hasControl() and H.eventRunning() then
      dead = dead + 1
      if dead >= 300 then
        error(string.format("%s: THE PARTY IS WIPED -- all four battle-HP " ..
          "words have read 0 with the event running and no control for 300 " ..
          "consecutive frames, at (%d,%d) on map %d.  This is a lost fight, " ..
          "not a stuck walk.", what, H.fieldX(), H.fieldY(), map()), 0)
      end
    else
      dead = 0
    end
    if H.battleLoadStarted() then
      F.frame()
      return true
    end
    F.idle()
    return false
  end
end

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

  -- The press is PULSED, never held: press down only while aligned on the
  -- clock tile, clear it the instant the step is in flight.  A held press
  -- still down at the arrival instant lets the engine latch a second step
  -- before the drive can react (the corridor-chaining hazard gen_zozo4
  -- documents), carrying the party onto (98,61) and rolling a random
  -- encounter that `encounters` above must handle.
  (function()
    local hb = 0
    local fought = encounters("off the clock tile")
    return H.driveUntil(function()
      return H.fieldY() > 59 and H.hasControl() and H.tileAligned()
    end, 9000, {
      H.call(function()
        hb = hb + 1
        if fought() then return end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {})
          return
        end
        -- no hasControl gate on the press: on the trigger tile the event
        -- re-enters every frame, so control FLICKERS, and a press gated on
        -- it can starve.  Pad input during the event frames is ignored, so
        -- pressing through the flicker is what the old hold did too; the
        -- alignment gate alone is what stops the chained second step.
        if H.tileAligned() and H.fieldY() <= 59 then
          H.setPad({ down = true })
        else
          H.setPad({})
        end
      end),
    }, "off the clock tile")
  end)(),
  H.release(),
  -- The calm wait still actively pins the party at (98,60): if a fight or
  -- any residual nudge leaves it south of 60, tap back up (the
  -- stood-on-trigger cure applied continuously), and fight anything the
  -- pacing rolls.  The budget covers one full tactical fight -- this
  -- file's own street fights ran 4000-7000 frames -- where the old 2400
  -- could time out on a fight it was winning.
  (function()
    local hb = 0
    local fought = encounters("calm after the shake")
    return H.driveUntil(landed(225, 20), 12000, {
      H.call(function()
        hb = hb + 1
        if fought() then return end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {})
          return
        end
        if H.hasControl() and H.tileAligned() and H.fieldY() > 60 then
          H.setPad({ up = true })
        else
          H.setPad({})
        end
      end),
    }, "calm after the shake, pinned at (98,60)")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitFrames(30),

  H.fieldCare({ tag = "care after the clock encounters", threshold = 0.85 }),

  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 SET -- clock solved, stairs open")
    H.log(string.format("[zozo_clock_solved] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    -- The casualty contract (see the care stop above): this fixture is what
    -- field_healpolicy.lua, probe_zozo3_chests.lua and probe_zozo_tool.lua
    -- boot from, so a party member down or near fatal here is a loss shipped
    -- downstream, not a state of the story getting somewhere.
    H.assertPartyStanding("zozo_clock_solved")
    H.screenshot("zozo_clock_solved")
  end),
  H.saveState("zozo_clock_solved.mss"),
  H.logStep(function()
    return string.format("zozo_clock_solved generated at frame %d", H.frame)
  end),
})
