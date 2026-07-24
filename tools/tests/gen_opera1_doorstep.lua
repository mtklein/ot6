-- gen_opera1_doorstep.lua -- v0.5 Beat A leg 1: zozo_done (map 221 Zozo
-- street {57,45}) -> the world -> JIDOOR (map 198) -> its north door {16,12}
-- -> map 209 (the opera-plot room) -> parked at {117,20} facing UP, one
-- A-press below the IMPRESARIO ({117,19}, _ca9337).  Mints opera_doorstep.mss.
--
-- WHY HERE, NOT THE OPERA-HOUSE FOYER (the survey's guess).  Measured: the
-- opera house is map 237 (world {45,154}, "far to the south" of Jidoor), and
-- ITS impresario ({60,48}, _caae15 -- the performance trigger) is HIDDEN
-- behind switch $0340, showing only a "The Opera House's closed" sign
-- (_caadf1, $0341).  $0340 is set to 1 ONLY by the opera-open cutscene, which
-- BEGINS by talking the IMPRESARIO on map 209 (_ca9337: "Maria!?" -> CELES's
-- resemblance -> the letter NPC appears, $0331=1 -> reading it -> the Setzer
-- intro/name-menu -> $0340=1).  Map 209 is reached from JIDOOR's north door,
-- not the opera house.  So the true "one A-press from the performance
-- sequence" is here, at the map-209 impresario -- the whole opera cutscene
-- chain hangs off this single talk.
--
-- ROUTE ANCHORS (source + measured, probe_opera_route/jidoor_door):
--  * Zozo world-exit: VERTICAL long-entrance column x=63, y=32..63 -> world
--    {23,92}.  navTo {62,45}, step RIGHT.
--  * world {~22,91} -> Jidoor approach {27,129}; step DOWN onto {27,130}
--    (short_entrance _0) -> map 198 {15,61}.  worldNavTo BFS'd it clean.
--  * Jidoor: the {16,12}->209 door is a BUMP entrance -- {16,12} is a $F7
--    wall flanked by $F7, triggered by walking UP into it from {16,13} (the
--    reachable approach, 51 steps from the entrance).  Landing map 209 {118,28}.
--  * map 209: the IMPRESARIO stands at {117,19} (faces LEFT).  navTo {117,20},
--    face UP.  The doorstep VERIFIES (after the mint) that one A-press fires
--    _ca9337 -- so the banked state can never be a dead one A-press short.
--
-- ROSTER (measured): active party = LOCKE (leader) + CELES only; the Zozo
-- leave-cutscene's forced party_menu {LOCKE,CELES} set exactly these two.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

-- Robust world walk to (tx,ty).  worldNavTo's verified-step BLOCKLIST breaks
-- on the Zozo->Jidoor route: the band around (34,103) is a dense random-battle
-- zone (world tile prop bit6 $40), and every encounter snapshots+restores the
-- party to the same tile, so worldNavTo reads "the press never moved us",
-- condemns all four edges and loops forever (measured, probe_opera_world.lua).
-- This grinds through instead: re-plan a worldBfs each time the plan runs out,
-- press the next step, kill-bit any encounter -- no edge is ever condemned, so
-- a battle-restored tile just gets retried until a step lands.  Arrives at
-- (tx,ty) or when the party leaves the world (an entrance fired).
local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX()==tx and H.worldY()==ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then      -- kill-bit AND A-mash the victory/EXP
        killBitAll(); plan=nil; H.setPad(ph<4 and {"a"} or {}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan=nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

H.run({ maxFrames = 120000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_done.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 221, "booted on Zozo street (map 221)")
    H.assertEq(sw(0x0053), 1, "$0053 SET -- the Ramuh scene ran")
    H.assertEq(sw(0x0054), 1, "$0054 SET -- the Zozo stop line")
    H.assertEq(sw(0x0340), 0, "$0340 CLEAR -- the opera is not yet open")
    H.assertEq((H.readByte(0x1850+1)&0x40), 0x40, "LOCKE available")
    H.assertEq((H.readByte(0x1850+6)&0x40), 0x40, "CELES available")
    H.log(string.format("[boot] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  -- 1. off the street to the world (approach {62,45}, step RIGHT onto x=63)
  H.navTo(62, 45, { maxFrames = 12000 }),
  (function() local hb=0
    return H.driveUntil(function() return H.worldMode() end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({ right=true }) end) }, "onto the world-exit column x=63") end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() and bright()>=15 end,
    2000, "world control", 5),
  H.waitFrames(30),
  H.call(function() H.log(string.format("[world] landed at (%d,%d)", H.worldX(), H.worldY()))
    H.screenshot("opera_world_landing") end),

  -- 2. world walk to Jidoor entrance {27,129}, step DOWN -> map 198 {15,61}
  -- (worldGrind, not worldNavTo -- the (34,103) battle-zone blocklist trap)
  worldGrind(27, 129, "world walk -> Jidoor approach (27,129)"),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end,
    2000, "at Jidoor approach", 5),
  (function() local hb=0
    return H.driveUntil(function() return not H.worldMode() and map()==198 end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({ down=true }) end) }, "into Jidoor (map 198)") end)(),
  H.waitUntil(function() return map()==198 and settled() end, 2400, "Jidoor control", 5),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 198, "in Jidoor (map 198)")
    H.log(string.format("[jidoor] landed at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- 3. Jidoor -> the north door: navTo the approach {16,13}, BUMP up into
  --    the {16,12}->209 archway (a $F7 wall entrance).
  H.navTo(16, 13, { maxFrames=15000, arrive=function() return map()==209 end }),
  (function() local hb=0
    return H.driveUntil(function() return map()==209 end, 3000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        if hb%16<8 then H.setPad({up=true}) elseif hb%16<12 then H.setPad({"a"}) else H.setPad({}) end
      end) }, "bump up into the (16,12) door -> map 209") end)(),
  H.waitUntil(function() return map()==209 and settled() end, 2400, "map 209 control", 5),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 209, "in the opera-plot room (map 209)")
    H.log(string.format("[map209] landed at (%d,%d) $0331=%d $0340=%d",
      H.fieldX(), H.fieldY(), sw(0x0331), sw(0x0340)))
  end),

  -- 4. up to {117,20}, directly below the IMPRESARIO ({117,19}); face UP.
  H.navTo(117, 20, { maxFrames=9000 }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(6),
  (function() local calm=0
    return H.driveUntil(function()
      local ok = H.fieldX()==117 and H.fieldY()==20 and settled() and facing()==0
      calm = ok and calm+1 or 0
      if calm>=20 then H.setPad({}); return true end
      return false
    end, 3000, {
      H.call(function()
        if H.battleLoadStarted() then killBitAll(); H.setPad({"a"}); return end
        H.setPad({}) end) }, "twenty settled frames below the IMPRESARIO")
  end)(),
  H.call(function()
    H.assertEq(map(), 209, "on map 209")
    H.assertEq(H.fieldX()==117 and H.fieldY()==20, true, "at (117,20)")
    H.assertEq(facing(), 0, "facing UP toward the IMPRESARIO")
    H.assertEq(settled(), true, "doorstep is QUIET")
    H.assertEq(sw(0x0331), 0, "$0331 CLEAR -- the letter has not appeared yet")
    H.assertEq(sw(0x0340), 0, "$0340 CLEAR -- the opera is not open yet")
    H.log(string.format("[opera_doorstep] f%d map=%d (%d,%d) face=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), facing()))
    H.screenshot("opera_doorstep")
  end),
  H.saveState("opera_doorstep.mss"),

  -- VERIFY the banked state is truly one A-press from the plot: tap A up and
  -- confirm _ca9337 fires (the "Maria!?" dialog, then $0331=1 as the letter
  -- NPC spawns).  This runs AFTER the mint, so the saved blob is untouched;
  -- it just proves the doorstep is not a dead one-press-short state.
  (function() local hb,aPh=0,0
    return H.driveUntil(function() return sw(0x0331)==1 or map()~=209 end, 12000, {
      H.call(function() hb=hb+1; aPh=(aPh+1)%8
        if hb%120==0 then H.log(string.format("[verify f%d] dlg=%s $0331=%d $0340=%d",
          hb, tostring(H.dialogWaiting()), sw(0x0331), sw(0x0340))) end
        if H.battleLoadStarted() then H.setPad(aPh<4 and {"a"} or {}); return end
        H.setPad(aPh<4 and {"a","up"} or {}) end) }, "one A-press fires the opera plot")
  end)(),
  H.call(function()
    H.assertEq(sw(0x0331), 1, "VERIFIED: one A-press fired _ca9337 -- the letter appeared ($0331=1)")
    H.log(string.format("[verify] opera plot started: map=%d $0331=%d $0340=%d",
      map(), sw(0x0331), sw(0x0340)))
    H.screenshot("opera_doorstep_verify")
  end),
  H.logStep(function()
    return string.format("opera_doorstep minted at frame %d -- one A-press below the map-209 IMPRESARIO", H.frame)
  end),
})
