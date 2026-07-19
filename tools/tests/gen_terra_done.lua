-- gen_terra_done.lua -- from terra_clifftop.mss: the last short walk of the
-- TERRA/BANON scenario -- across the ledge into ARVIS'S HOUSE, onto the
-- meeting trigger, and out the far side of the scenario.
-- Mints one state:
--   terra_done.mss  map 9 (8,3), SCENARIO_MOG alone, controllable, with
--                   $0021 SET and the BANON/TERRA/EDGAR hub NPCs gone -- the
--                   TERRA/BANON scenario complete and the hub back on two
--                   choices.  The same beat gen_scenario mints scenario_hub
--                   at, so the two states are directly comparable.
--
-- TWO HOPS.
--
-- 1. THE CLIFFTOP -> ARVIS'S HOUSE.  The party is on map 20 (27,8), the ledge
--    the caves come out on, which is the SAME ledge Terra escaped onto in the
--    intro (gen_mines_chase walks it west, narshe_streets sits on it).  Its
--    door into Arvis's back corridor is (53,9) -> map 30 (67,28)
--    (ShortEntrance::_20, DestX read as SEVEN bits -- see gen_terra_clifftop
--    for why $3F is wrong on this 128-wide map).  ARRIVAL IS BRACKETED: map
--    30 (67,26) is the reciprocal door straight back to the ledge, two tiles
--    north of the (67,28) we land on, so the hop to the meeting is planned
--    clear of it.
--
-- 2. ARVIS'S HOUSE -> _ccb3fa AT (66,35), AND THE SCENARIO ENDS.
--    EventTrigger::_30 puts _ccb3fa on {66,35} (event_trigger.asm:163); it
--    needs $00A4=0, $0019=1 and $0021=0 (event_main.asm:104805-104809), plays
--    the Arvis meeting (dlg $01A5..$01A9), and ends `switch $0021=1 / switch
--    $032B=0 / switch $032C=0 / switch $032D=0 / call _caad4c`
--    (:104954-104959).  That `switch $0021=1` is the ONLY assignment to the
--    scenario-complete flag in the whole event bank (every other $0021 line
--    is an if_any condition), so this trigger is not a way to finish the
--    scenario -- it is the way.
--
-- WHERE IT LANDS.  _caad4c (:26626) tears the party down to SCENARIO_MOG and
-- reloads map 9; with $0021 set but $001E and $0044 still clear it takes the
-- `if_any` at :26665 to _caadb4 and plays dlg $0B8C, "Choose a scenario…
-- kupo!", skipping the first-visit recap $016F.  The mint is the first
-- controllable frame after that.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local CLIFF = "/Users/mtklein/ot6/build/states/terra_clifftop.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

local DD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
             right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
             downleft = { -1, 1 }, downright = { 1, 1 } }
local function planAvoids(tx, ty, bad, what)
  return H.call(function()
    local p = H.bfsPath(tx, ty)
    H.assertEq(p ~= nil, true, what .. ": a path exists")
    local x, y, hx, hy = H.fieldX(), H.fieldY(), nil, nil
    for _, d in ipairs(p) do
      x, y = x + DD[d][1], y + DD[d][2]
      for _, b in ipairs(bad) do
        if x == b[1] and y == b[2] then hx, hy = x, y end
      end
    end
    H.log(string.format("%s: %d steps, clean: %s", what, #p, tostring(hx == nil)))
    H.assertEq(hx == nil, true, what .. ": plan avoids the forbidden tiles" ..
      (hx and string.format(" (hits %d,%d)", hx, hy) or ""))
  end)
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
      H.log(string.format("landed(%d) f%d blocked: map=%d ctl=%s algn=%s " ..
        "bright=%d batt=%s dlg=%s at (%d,%d) ev=%s", m, H.frame, map(),
        tostring(H.hasControl()), tostring(H.tileAligned()), bright(),
        tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
        H.fieldX(), H.fieldY(), tostring(H.eventRunning())))
    end
    return cnt >= (n or 20)
  end
end
local settleHouse, settleHub = landed(30), landed(9)

local function where(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) ctl=%s $0019=%d $0021=%d " ..
    "$001E=%d $0044=%d $00A4=%d", tag, H.frame, map(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), sw(0x0019), sw(0x0021), sw(0x001E), sw(0x0044),
    sw(0x00A4)))
end

H.run({ maxFrames = 60000 }, {
  H.loadState(CLIFF),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 20, "booted on map 20, the clifftop above Narshe")
    H.assertEq(H.fieldX(), 27, "at the arrival tile x=27")
    H.assertEq(H.fieldY(), 8, "at the arrival tile y=8")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0019), 1, "$0019 set -- the river was run")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    H.assertEq(sw(0x00A4), 0, "$00A4 clear -- _ccb3fa's first guard is open")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON in the party")
    local p = H.bfsPath(53, 9)
    H.assertEq(p ~= nil, true, "(53,9), Arvis's back door, is reachable")
    H.log(string.format("to the door: (%d,%d) -> (53,9), %d steps",
      H.fieldX(), H.fieldY(), #p))
    where("booted")
  end),

  -- ===================================================================== --
  -- 1. INTO ARVIS'S HOUSE.  (53,9) IS ITSELF the door tile (its neighbours
  --    below are solid ledge, so there is no doorstep to stop one short on --
  --    a first cut aimed at (53,10) and BFS answered "no path").  So navTo
  --    walks onto (53,9) directly and terminates on the map change it fires.
  -- ===================================================================== --
  H.navTo(53, 9, { maxFrames = 20000,
    arrive = function() return map() ~= 20 end }),
  H.release(),
  H.advanceStory(settleHouse, 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 30, "on map 30, ARVIS'S HOUSE")
    H.assertEq(H.fieldX(), 67, "arrival tile x=67")
    H.assertEq(H.fieldY(), 28, "arrival tile y=28 (map 20 (53,9) -> map 30 (67,28))")
    H.assertEq(sw(0x00A4), 0, "$00A4 still clear -- _ccb3fa will fire")
    where("in Arvis's house")
    H.screenshot("terra_arvis_house")
  end),

  -- ===================================================================== --
  -- 2. ONTO _ccb3fa AT (66,35), AND THE SCENARIO ENDS.  Arrival is bracketed
  --    by the reciprocal door back to the ledge at (67,26), planned clear.
  -- ===================================================================== --
  planAvoids(66, 35, { { 67, 26 } }, "Arvis's house: (67,28) -> (66,35)"),
  H.navTo(66, 35, { maxFrames = 20000, arrive = function()
    return sw(0x0021) == 1 or H.eventRunning() or H.dialogWaiting()
  end }),
  H.release(),
  H.call(function() where("_ccb3fa running") end),
  H.advanceStory(function()
    return sw(0x0021) == 1 and settleHub()
  end, 60000),
  H.waitFrames(30),

  H.call(function()
    H.assertEq(map(), 9, "back on map 9, the SCENARIO HUB")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x0021), 1,
      "$0021 SET -- TERRA/BANON's scenario is complete (_ccb3fa, :104954)")
    H.assertEq(sw(0x001E), 0, "$001E still clear -- LOCKE's scenario is not")
    H.assertEq(sw(0x0044), 0, "$0044 still clear -- nor SABIN's")
    -- the hub is down to two choices: _ccb3fa cleared all three NPCs that
    -- ran _cb094e (event_main.asm:104956-104958)
    H.assertEq(sw(0x032B), 0, "$032B clear -- BANON's hub NPC is gone")
    H.assertEq(sw(0x032C), 0, "$032C clear -- TERRA's too")
    H.assertEq(sw(0x032D), 0, "$032D clear -- and EDGAR's")
    H.assertEq(sw(0x0329), 1, "$0329 still set -- LOCKE's NPC is still waiting")
    H.assertEq(sw(0x032A), 1, "$032A still set -- and SABIN's")
    -- and the party is Mog alone again
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, true, "SCENARIO_MOG is the party")
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, false, "TERRA out")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, false, "EDGAR out")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, false, "BANON out")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    where("terra_done")
    H.screenshot("terra_done")
  end),
  H.saveState("terra_done.mss"),
  H.logStep(function()
    return string.format("terra_done minted at frame %d", H.frame)
  end),
})
