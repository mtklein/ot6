-- gen_sabin_trench.lua -- step 11, the last of SABIN's scenario: Crescent
-- Mountain, the Serpent Trench, and the Nikeah ferry.  Generates:
--   sabin_done.mss   map 9 (the scenario hub), $0044=1: SABIN's scenario
--                    complete, the hub's "Choose a scenario…kupo!" spoken,
--                    and the party reduced to the hub's MOG cursor
--                    (_caad4c, event_main.asm:26626: every character
--                    char_party 0, SCENARIO_MOG in, the same shape
--                    locke_done ends in).
--
-- The route:
--   world (214,149) -> step onto (214,148) -> map 167 (12,25), Crescent
--   Mountain.  Walking UP crosses (12,22) -> _cbc228, the helmet scene.
--   It and every variant gate on $01AB (GAU in party) and on $0041/$0184
--   being clear (the train's ending cleared $0184).  GAU dives for the
--   breathing helmet, and $0041=1 opens the trench.  Then (25,26) -> 168
--   (8,9); the (8,11)/(9,11) row asks "Jump?" ($0041 gate), option 0,
--   and _cbc866's jump runs _ca8ae3, the dive.
--
--   The trench is a vehicle script on world map 2 (load_map 2 {117,120}
--   AIRSHIP + set_script_mode VEHICLE, :21163).  move_vehicle commands
--   drive the ride; the player has input only at the two show_arrows
--   windows, where $01B7 ($1EB6 bit 7) picks the branch: LEFT sets it
--   (mainline), RIGHT clears it (detour through the mid-cave 175).  There is
--   no neutral default, so LEFT is held through the whole ride.  Battles
--   19/20/21 fire mid-script with no _ca5ea9 tail, and since issue #75
--   they are ended by play with no writes: flee first (hold L+R; no win is
--   needed, since the vehicle script resumes via PopDP either way), and if a
--   formation refuses the run for ~900 frames, fall back to the blind
--   tap-A fighter (SABIN/CYAN/GAU all Fight from row 0; SHADOW is long
--   gone, and GAU has no leave roll, so a win costs nothing).  $ed climbs
--   monotonically per segment (logged as the progress signal).
--
--   Arrival _ca8be3 (:21288): world walk-on, then Nikeah 187 (24,11).
--   The ferry clerk is NPC (17,15); dlg $032A's option 1 ("Hop aboard?")
--   is the arc's single option-1 prompt, and option 0 loops the dialog
--   indefinitely.  _ca8d22 sails the ship, replays 187 {14,16} for the
--   "stone's throw from Narshe" beat, sets $0044=1 and calls _caad4c, the
--   hub.  (The reunion if_all needs $0021+$001E+$0044 in one playthrough;
--   the input-driven chain has only $0044, so the hub speaks and hands
--   control back; the stacked replays are where the reunion fires.)
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/gau_joined.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

local function settle(toMap, what, budget)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, budget or 6000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[trench] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

-- ride driver with choice steering and trench battle handling: flee
-- first, tap-A fight after ~900 stubborn frames (see the header)
-- Set when the ride-scoped wipe canary fires; every ride() pred also
-- exits on it so a lost dive ends the attempt rather than the run.
local rideLost = nil
local rideWipeN = 0

local function ride(dir, pred, what, budget, choiceWant)
  local phase, hb, battN = 0, -900, 0
  return H.driveUntil(function()
    return rideLost ~= nil or pred()
  end, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      -- inBattle() cannot see a wipe in an underwater battle: its loop
      -- skips all-zero HP entries, so a dead party reads b=false and the
      -- driver holds LEFT at the Game Over indefinitely.  That consumed
      -- three 60000-frame budgets.
      -- probe_trench_arrows showed how close even the surviving line
      -- runs: it reached Nikeah at 28/0/0.  The signature is the same
      -- one the gau walk uses: every party slot showing a plausible max
      -- (0 < max < 1000; module garbage reads tens of thousands)
      -- with zero HP, debounced 90 frames, ride map only.
      if mapIdx() == 2 and not rideLost then
        local sane, alive = 0, 0
        for e = 0, 2 do
          local mx = H.readWord(0x3c1c + e * 2)
          if mx > 0 and mx < 1000 then
            sane = sane + 1
            if H.readWord(0x3bf4 + e * 2) > 0 then alive = alive + 1 end
          end
        end
        if sane >= 3 and alive == 0 then
          rideWipeN = rideWipeN + 1
          if rideWipeN >= 90 then
            rideLost = string.format("wiped mid-ride at f%d during %s",
              H.frame, what)
            H.log("[trench] LOST -- " .. rideLost)
            H.setPad({})
            return
          end
        else
          rideWipeN = 0
        end
      end
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "[trench:%s] f%d map=%d (%d,%d) ctl=%s $ed=%04X b=%s dlg=%s "..
          "ch=%d/%d $01B7=%d $0041=%d $0044=%d", what, H.frame, mapIdx(),
          H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          H.readWord(0xed), tostring(inBattle()),
          tostring(H.dialogWaiting()), H.readByte(CH_SEL),
          H.readByte(CH_MAX), (H.readByte(0x1EB6) >> 7) & 1, sw(0x41),
          sw(0x44)))
      end
      if inBattle() or H.battleLoadStarted() then
        battN = battN + 1
        if battN < 900 and H.monstersPresent() > 0 then
          H.setPad({ l = true, r = true })   -- flee, with real input
        else
          if battN == 900 then
            H.log(string.format("[trench:%s] formation would not run for " ..
              "900 frames -- fighting it (tap-A)", what))
          end
          H.setPad(phase < 4 and { "a" } or {})
        end
        return
      end
      battN = 0
      -- On the ride map, hold the direction and read no field-owned
      -- cells.  Five driver variants failed this ride in five different
      -- ways (the record is in dc07c44) before probe_trench_arrows and
      -- the source settled the mechanism:
      --
      --   * show_arrows is non-blocking (VehicleCmd_da,
      --     world/event.asm:589, sets $E8 bits 1|2 and returns); the
      --     script runs `show_arrows / wait N / lock_arrows /
      --     hide_arrows / if_switch $01B7`, which is a timed sample
      --     rather than a modal window (event_main.asm:21212, :21253).
      --   * The sample (world/move.asm:403-425) reads the held pad
      --     cell $05 every arrows-shown frame, level-triggered: LEFT
      --     held -> $1EB6 |= $80, RIGHT held -> &= $7F.  There is no press
      --     edge and no confirm.  Holding LEFT is all that is required.
      --   * probe_trench_arrows rode this same upstream to Nikeah
      --     (map 187 at f15950) holding LEFT with only the battle
      --     branch above; $1EB6 bit 7 stayed set the entire way,
      --     and the one 618-frame $00ED pause ended on its own
      --     (a long scripted beat, not a wait for input).
      --
      -- What broke the five gen runs: this function read
      -- H.dialogWaiting() and CH_MAX/CH_SEL mid-ride.  Those are field
      -- module cells (hazard 1: the value at a module-owned address is
      -- only meaningful while that module owns the RAM), and they read
      -- garbage on the vehicle map.  The heartbeats logged ch=124/0 and
      -- dlg flicker, so the driver sent phantom A-taps into the ride,
      -- which the probe never did.  The choice and dialog branches below
      -- remain for the field maps this driver also serves (the helmet
      -- scene, the ferry clerk); the ride map never reaches them.
      if mapIdx() == 2 and dir then
        H.setPad({ [dir] = true })
        return
      end
      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

-- The dive ladder (see the call-site comment): checkpoint before the
-- (25,18) helmet talk, an attempt is helmet scene -> dive -> Nikeah,
-- a wipe (or a ride that never lands) reloads with the house 17-frame
-- stagger for a different underwater-battle timeline.
local diveBlob, diveDone = nil, false
local function diveCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "dive checkpoint")
      diveBlob = ckReq.blob
      H.log(string.format("[trench] dive checkpoint captured (%d bytes) f%d",
        #diveBlob, H.frame))
    end),
  }, {})
end
local function diveAttempt(n)
  local ldReq
  return H.cond(function() return not diveDone end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[trench] dive ATTEMPT %d -- reloading (%s)",
          n, tostring(rideLost))
      end),
      H.call(function() ldReq = H.requestLoadState(diveBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "dive attempt " .. n) end),
      H.waitFrames(60 + (n - 1) * 17),
    }, {}),
    H.call(function() rideLost, rideWipeN = nil, 0 end),
    H.navTo(25, 18, { maxFrames = 12000, playBattles = "flee", arrive = function()
      return sw(0x41) == 1 or (H.fieldX() == 25 and H.fieldY() == 18
         and H.hasControl() and H.tileAligned()) end }),
    ride("up", function()
      return sw(0x41) == 1 and H.hasControl() and H.tileAligned()
    end, "helmet scene a" .. n, 25000),
    H.call(function()
      H.assertEq(sw(0x41), 1, "$0041 -- the trench is open")
      H.log(string.format("[trench] post-helmet a%d: map=%d (%d,%d)", n,
        mapIdx(), H.fieldX(), H.fieldY()))
    end),
    (function()
      -- raising the budget would abort the ladder; a ride that neither
      -- lands nor wipes inside 55000 frames is a loss for this
      -- timeline, named as such so the stagger gets its turn
      local frames = 0
      return ride("left", function()
        frames = frames + 1
        if frames > 55000 and rideLost == nil then
          rideLost = string.format("dive attempt %d deadline " ..
            "(55000 frames, map=%d)", n, mapIdx())
          H.log("[trench] LOST -- " .. rideLost)
        end
        return mapIdx() == 187
      end, "the trench ride a" .. n, 60000)
    end)(),
    H.call(function()
      if rideLost == nil and mapIdx() == 187 then
        diveDone = true
        H.log(string.format("[trench] dive attempt %d LANDED at Nikeah f%d",
          n, H.frame))
      elseif rideLost == nil then
        rideLost = string.format("dive attempt %d ended off-Nikeah " ..
          "(map=%d) f%d", n, mapIdx(), H.frame)
        H.log("[trench] " .. rideLost)
      end
    end),
  }, {})
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the world at Crescent's door")
    H.assertEq(inParty(11), true, "GAU aboard -- the helmet scene's gate")
    H.assertEq(sw(0x41), 0, "$0041 clear -- trench not yet open")
  end),

  -- step into Crescent Mountain
  H.worldNavTo(214, 148, { maxFrames = 4000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  settle(167, "Crescent 167"),

  -- up into (12,22): the helmet scene (GAU + the diving helmet, $0041)
  H.call(function()
    H.log(string.format("[trench] gates: $0184=%d $01AB(par)=%s", sw(0x184),
      tostring(inParty(11))))
    local MOVES = { "up", "down", "left", "right" }
    local DELTA = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0} }
    local sx, sy = H.fieldX(), H.fieldY()
    local seen = { [sy * 256 + sx] = true }
    local q, qi = { { sx, sy } }, 1
    while qi <= #q and qi <= 2000 do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for _, dir in ipairs(MOVES) do
        if H.canStep(x, y, dir) then
          local d = DELTA[dir]
          local k = (y + d[2]) * 256 + (x + d[1])
          if not seen[k] then seen[k] = true; q[#q+1] = { x+d[1], y+d[2] } end
        end
      end
    end
    local rows = {}
    for k in pairs(seen) do
      local y, x = k >> 8, k & 0xFF
      rows[y] = rows[y] or {}
      rows[y][#rows[y]+1] = x
    end
    local ys = {}
    for y in pairs(rows) do ys[#ys+1] = y end
    table.sort(ys)
    for _, y in ipairs(ys) do
      table.sort(rows[y])
      H.log(string.format("  167 y=%d x=%s", y,
        table.concat(rows[y], ",")))
    end
  end),
  H.navTo(12, 23, { maxFrames = 8000, playBattles = "flee" }),
  -- (12,22) runs a preliminary beat (GAU runs ahead and the party is
  -- re-parked at (12,17)); the $0041 helmet scene itself is _cbc5fb's
  -- tail, triggered at (25,17)
  (function()
    local sceneSeen = false
    return ride("up", function()
      if not H.hasControl() then sceneSeen = true end
      return sceneSeen and H.hasControl() and H.tileAligned()
         and mapIdx() == 167
    end, "the (12,22) beat", 15000)
  end)(),
  -- Top up before the dive.  The ride's three underwater battles are the
  -- step's HP constraint: probe_trench_arrows reached Nikeah at
  -- 28/0/0, and the losing timelines wipe.  The party arrives
  -- from gau_joined carrying ~20 Tonics and the field menu works here;
  -- one care stop is the difference between diving at half HP and
  -- diving at full.
  H.fieldCare({ tag = "pre-dive care", threshold = 0.95 }),

  -- The dive uses the house ladder.  The helmet scene's tail is the
  -- dive (its `if_switch $0127=0, _ca8ae3` runs straight into the
  -- vehicle script), so the checkpoint is cut before the (25,18) talk
  -- and an attempt is helmet -> dive -> Nikeah.  Hold LEFT the whole
  -- ride (mainline at both arrow windows; the level-sampled behavior is
  -- described in ride()); battles 19/20/21 are fled or fought with real
  -- input; a mid-ride wipe is named by the canary and reloads on a
  -- 17-frame stagger, giving a different battle timeline.
  diveCheckpoint(),
  diveAttempt(1),
  diveAttempt(2),
  diveAttempt(3),
  H.call(function()
    if not diveDone then
      error(string.format("trench: the dive did not reach Nikeah on any " ..
        "of 3 staggered attempts -- last: %s", tostring(rideLost)), 0)
    end
  end),
  settle(187, "Nikeah", 8000),
  H.call(function()
    H.assertEq(mapIdx(), 187, "landed in Nikeah")
    H.log(string.format("[trench] Nikeah at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("trench_nikeah")
  end),

  -- the ferry clerk at (17,15): option 1 boards
  H.navTo(17, 16, { maxFrames = 8000, playBattles = "flee" }),
  (function()
    local phase = 0
    return H.driveUntil(function()
      return H.readByte(CH_MAX) >= 2 and H.dialogWaiting()
    end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { "up", "a" } or { "up" })
      end),
    }, "ferry prompt open")
  end)(),
  ride(nil, function()
    return sw(0x44) == 1 and mapIdx() == 9 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, "board + sail + the hub", 40000, 1),

  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 9, "back at the scenario hub, map 9")
    H.assertEq(sw(0x44), 1, "$0044 -- SABIN's scenario is COMPLETE")
    H.assertEq(sw(0x3A), 1, "$003A still set (the train fought)")
    H.assertEq(inParty(5), false, "SABIN dissolved into the hub pool")
    H.log(string.format("[sabin_done] f%d map=%d (%d,%d)", H.frame,
      mapIdx(), H.fieldX(), H.fieldY()))
    H.screenshot("sabin_done")
  end),
  H.saveState("sabin_done.mss"),
  H.logStep(function()
    return string.format("sabin_done generated at frame %d -- the scenario arc "..
      "closes at the hub", H.frame)
  end),
})
