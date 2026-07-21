-- gen_zozo2_arrival.lua -- v0.4 leg 1b: figaro_submerged (engine room, map
-- 61 {6,34}, castle parked WEST at ~world {30,48}) -> up and out of the
-- castle -> the western WoB -> Zozo's world tiles {21..22,92} -> mint
-- zozo_arrival.mss on map 221 at the street landing {61,44}.
--
-- ROUTE ANCHORS (source, not survey):
--  * 61 door (11,32) -> 59 {10,48}; 59 door (12,41) -> 55 {28,31}
--    (short_entrance.dat _61/_59)
--  * map 55's row y=43 is the world-exit long entrance (gen_kolts's rule:
--    keep it off every route EXCEPT when leaving on purpose) -- here it IS
--    the exit: navTo(28,42), hold down
--  * the world landing is MEASURED by this run's log (parent record vs the
--    long-entrance dest {65,77} was statically ambiguous; the ride's
--    SET_PARENT points at the west parking ~{30,48})
--  * world {30,48}/{31,48} are the WEST castle trigger tiles (_ca5ec2,
--    gated $010C=1 -- LIVE for us): triggers fire on STEP, so the exit
--    placement is safe, and the Zozo leg heads SW away from them
--  * Zozo: world {21,92}/{22,92}/{22,93} -> map 221 {61,44}
--    (short_entrance.dat _0)
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

local function door(nx, ny, dir, m, what)
  return H.cond(function() return true end, {
    H.navTo(nx, ny, { maxFrames = 12000 }),
    H.driveUntil(function() return map() == m end, 900, {
      H.hold({ dir }), H.waitFrames(4),
    }, what .. ": through the door"),
    -- ride any arrival scene out (the west castle greets with one:
    -- measured, an event walks the party to (28,28) and parks a dialog)
    H.advanceStory(landed(m, 10), 2400),
    -- door loads finalize the decompressed prop table LATE: ~150 frames
    -- after control+brightness the engine still walked (and modelled) on
    -- the PREVIOUS map's props (measured, probe_n20c on map 30->20: a
    -- legal step refused at +40f, accepted at +80f; the census flipped
    -- from all-walls to sane at ~+150f).  Settle long before any BFS.
    H.waitFrames(150),
  })
end

H.run({ maxFrames = 90000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/figaro_submerged.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 61, "booted in the engine room (map 61)")
    H.assertEq(sw(0x010C), 1, "$010C SET -- castle parked WEST")
  end),

  -- 1. engine room -> keep hall -> the gate map.  (11,32) is a WALK-IN
  --    doorway (directly reachable, probe_eng61) landing at 59 {10,48};
  --    the keep->gate door (28,32)-side needs the held press.
  H.navTo(11, 32, { arrive = function() return map() == 59 end,
                    maxFrames = 9000 }),
  H.waitUntil(landed(59, 10), 1500, "keep hall", 1),
  H.waitFrames(150),
  door(12, 42, "up", 55, "keep -> the gate map"),

  -- 2. the arrival scene parks the party on the FRONT TERRACE at (28,28),
  --    which is walled from the gate: drop through door (28,32) -> 59
  --    {12,43}, then door (12,50) -> 55 {28,40}, the lower gate yard.
  door(28, 31, "down", 59, "terrace -> vestibule"),
  door(12, 49, "down", 55, "vestibule -> gate yard"),

  -- 3. off the castle onto the world: row y=43 is the exit
  H.navTo(28, 42, { maxFrames = 12000 }),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "off the castle to the world"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 1500, "world control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] west landing at (%d,%d)",
      H.worldX(), H.worldY()))
  end),

  -- 3. south-west to Zozo: park one tile above the {22,92} entrance, then
  --    step onto it.  arrive bails if a step lands the entrance early.
  H.worldNavTo(22, 91, { maxFrames = 40000,
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() and map() == 221 end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "onto Zozo's entrance tile"),
  H.waitUntil(landed(221, 10), 1500, "Zozo street up", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 221, "on the Zozo exterior (map 221)")
    H.log(string.format("[zozo_arrival] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("zozo_arrival")
  end),
  H.saveState("zozo_arrival.mss"),
  H.logStep(function()
    return string.format("zozo_arrival minted at frame %d", H.frame)
  end),
})
