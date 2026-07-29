-- probe_v07_385walk.lua -- THE PHASE-AWARE CROSSING of BASEMENT 2 (map
-- 385), the v0.7 band's first genuinely new driving idiom (issue #31,
-- recon §5 hazard 2).  NOT a suite test.  Drives the room entry (1,2) ->
-- exit (13,13) -> BASEMENT 3 (map 384) and mints v07q_384_entry.mss.
--
-- HISTORY.  Draft 1's walker moved correctly inside a phase and could
-- never cross between phases (it waited, hasControl-gated, on the
-- boundary tile and ate the swap).  probe_v07_385win.lua measured the
-- actual mechanism -- the REWRITE WINDOW (each swap callback rewrites the
-- tilemap ~13 frames before it flips the phase switches), unconditional
-- holds (hurt tiles are re-entering trigger tiles that kill hasControl),
-- and mid-step immunity to the stood-on hurt trigger -- and draft 2
-- implemented union-graph planning over (x,y,phase) nodes with move /
-- flip / window edges.  That walker is now lib/ot6_field.lua's
-- M.phaseWalk (promoted 2026-07-28); this probe carries the map-385 spec
-- and is the crossing's regression instrument.
--
-- THE ROOM, as measured (probe_v07_385, probe_v07_385win, probe_v07_385door,
-- addenda §1.5):
--   * two complementary tilemaps swapping every 158 frames once a cycle
--     is armed: `wait 144` / `start_timer ..,144,..` chains plus ~14
--     frames of ASYNC mod_bg_tiles + wait_bg in each callback, which
--     flips $01F5/$01F6 only AFTER the rewrite (_cb2bb2
--     event_main.asm:44700, _cb2c57 :44735, _cb2d1e :44812, _cb2d97
--     :44853);
--   * reachable sets inside a phase are dead ends (17 tiles in $01F5, 12
--     in $01F6, from the entry);
--   * hurt tiles (_cb2dbb while $01F5 / _cb2dd2 while $01F6 / (15,10)
--     always; event_trigger.asm:1849-1883) cost HP/8 to all four,
--     teleport SLOT_1 to (2,6) and wipe $01F0-$01FF;
--   * (3,2)/(10,2) arm cycle A (west half swaps); (11,3)/(13,11) arm
--     cycle B (east half swaps, west half FREEZES and $01F0 drops --
--     _cb2c6e stops every timer first).  With $01F0=0 the A triggers
--     would RE-ARM A and freeze the east half, so the post-B leg lists
--     them in `avoid`;
--   * random encounters fire here (a Zombone on the door step, run 3)
--     and the battle round-trip PRESERVES the cycle switches and timers
--     (probe_v07_385door) -- M.phaseWalk kill-bits and re-plans.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

-- the map-385 phaseWalk spec: hurt lists transcribed from
-- event_trigger.asm:1849-1884 (verified against source 2026-07-28)
local function spec385(over)
  local s = {
    switches = { a = 0x01F5, b = 0x01F6 },
    period = 158,
    region = { w = 17, h = 16 },
    hurt = {
      a = { {7,2},{9,2},{9,4},{5,5},{6,5},{9,5},{13,5},{13,6},{5,7},
            {11,7},{13,7},{14,7},{5,8},{12,9},{6,10},{14,10},{10,11} },
      b = { {4,2},{5,2},{6,2},{5,3},{7,3},{8,3},{9,3},{11,4},{11,5},
            {3,7},{10,8},{11,8},{12,8},{13,8},{14,8},{7,9},{10,9},{9,11} },
      always = { {15,10} },
    },
  }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

-- unconditional held walk with arrival-release (trigger tiles fire a few
-- frames AFTER entry; releasing on arrival keeps the hold from carrying
-- the party onto the next -- possibly hurt -- tile during the arming
-- event); random encounters kill-bitted through
local function holdWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
            H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
          end
        end
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/v07q_385_entry.mss.lua"),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 385, "booted on BASEMENT 2 (map 385)")
    H.assertEq(H.fieldX(), 1, "boot x")
    H.assertEq(H.fieldY(), 2, "boot y")
  end),

  -- arm cycle A: the (3,2) trigger (_cb2aca, event_main.asm:44634).
  -- Release on ARRIVAL: $01F0 sets a few frames later, and a hold still up
  -- would walk the party onto (4,2) -- hurt-$01F6 -- right as timer 0
  -- fires the first swap callback.
  holdWalk("right", function() return H.fieldX() >= 3 end, 1800,
    "held RIGHT onto the cycle-A arming trigger (3,2)"),
  H.waitUntil(function() return sw(0x01F0) == 1 end, 900,
    "cycle A armed ($01F0)", 2),
  H.call(function()
    H.log(string.format("[385] cycle A armed at (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),

  -- west half: (3,2) -> the (6,2)->(7,2) window -> row 2 east -> (11,3),
  -- whose arrival arms cycle B (and freezes the west in its live phase)
  H.phaseWalk(11, 3, spec385({ maxFrames = 20000,
    what = "phaseWalk across row 2 to the cycle-B trigger (11,3)" })),
  H.waitUntil(function() return sw(0x01F1) == 1 end, 900,
    "cycle B armed ($01F1)", 2),
  H.call(function()
    H.assertEq(sw(0x01F0), 0,
      "$01F0 dropped -- arming B stopped cycle A (_cb2c6e -> _cb2b06)")
    H.log(string.format("[385] cycle B armed at (%d,%d)",
      H.fieldX(), H.fieldY()))
    H.screenshot("v07_385_armedB")
  end),

  -- east half: measured plan is (11,3) -> (11,6) in $01F5, then THREE
  -- window steps -- (11,6)->(11,7), (11,7)->(11,8), (12,8)->(12,9) --
  -- then $01F6 moves to (13,12)
  H.phaseWalk(13, 12, spec385({ maxFrames = 30000,
    avoid = { { 3, 2 }, { 10, 2 } },
    what = "phaseWalk down the east half to (13,12)" })),
  H.call(function()
    H.log(string.format("[385] at (%d,%d) -- one step above the 384 door",
      H.fieldX(), H.fieldY()))
    H.screenshot("v07_385_door")
  end),
  H.saveState("v07q_385_door.mss"),

  -- the exit door (13,13) -> BASEMENT 3 (map 384) (26,8)
  holdWalk("down", function() return map() == 384 end, 2400,
    "held DOWN onto (13,13) -> BASEMENT 3 (map 384)"),
  H.waitUntil(function()
    return map() == 384 and H.hasControl() and H.tileAligned()
      and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 2400, "384 control", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(map(), 384, "BASEMENT 3 is map 384")
    H.assertEq(H.fieldX(), 26, "384 landing x (short entrance 385 (13,13))")
    H.assertEq(H.fieldY(), 8, "384 landing y")
    H.screenshot("v07_384_entry")
  end),
  H.saveState("v07q_384_entry.mss"),
  H.logStep(function()
    return string.format("385 crossed at frame %d; parked at the 384 entry",
      H.frame)
  end),
})
