-- gen_opera1_entry.lua -- v0.5 Beat A step 1: zozo_done (map 221 Zozo
-- street {57,45}) -> the world -> JIDOOR (map 198) -> its north door {16,12}
-- -> map 209 (the opera-plot room) -> parked at {117,20} facing UP, one
-- A-press below the IMPRESARIO ({117,19}, _ca9337).  Generates
-- opera_entry.mss.

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local function worldGrind(tx, ty, what)
  local plan, idx, step = nil, 1, nil
  local battN, battleFrames, hb = 0, 0, -600
  local DW = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }
  local sawBattle = false
  return H.driveUntil(function()
    return H.worldMode() and H.worldX()==tx and H.worldY()==ty
      and H.worldHasControl() and H.worldAligned()
  end, 90000, {
    H.call(function()
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN > 0 then
        plan, step, sawBattle = nil, nil, true
        if battN == 3 then
          local w = H.formationWords()
          H.log(string.format("[grind] battle up f%d (%04X %04X %04X %04X " ..
            "%04X %04X) -- fleeing with L+R", H.frame,
            w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        battleFrames = battleFrames + 1
        if battleFrames > 2400 then
          error("world encounter did not yield to 2400 frames of L+R", 0)
        end
        H.setPad({ l = true, r = true })
        return
      end
      if not H.worldMode() then
        if sawBattle then battleFrames = battleFrames + 1 end
        if battleFrames > 2400 then
          error("world encounter did not return to the map after 2400 frames", 0)
        end
        plan, step = nil, nil
        H.setPad({ l = true, r = true }); return
      end
      if sawBattle then
        H.log(string.format("[grind] fled; world resumed at (%d,%d)",
          H.worldX(), H.worldY()))
        sawBattle, battleFrames = false, 0
      end
      if not H.worldHasControl() then
        plan, step = nil, nil; H.setPad({}); return
      end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      if step then
        if x == step.tx and y == step.ty then
          step = nil; idx = idx + 1
        elseif x ~= step.fx or y ~= step.fy then
          plan, step = nil, nil
        else
          step.held = step.held + 1
          if step.held > 90 then
            plan, step = nil, nil; H.setPad({}); return
          end
          H.setPad({ [step.dir] = true }); return
        end
      end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[grind] NO PATH (%d,%d)->(%d,%d) f%d",
              x, y, tx, ty, H.frame))
          end
          H.setPad({}); return
        end
      end
      local dir = plan[idx]
      local d = DW[dir]
      step = { dir = dir, fx = x, fy = y,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, held = 0 }
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

H.run({ maxFrames = 250000 }, {
  H.loadState("build/states/zozo_done.mss.lua"),
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

  H.fieldCare({ tag = "care before leaving Zozo", threshold = 0.9 }),

  -- 1. off the street to the world (approach {62,45}, step RIGHT onto x=63).
  -- Flee the street encounters rather than blind-A-tapping them: this is the
  -- road out, not a fight to win, and a fled encounter cannot lose the party
  -- the way a blindly-fought one did after the RNG re-roll.
  H.navTo(62, 45, { maxFrames = 12000, playBattles = "flee" }),
  (function() local hb=0
    return H.driveUntil(function() return H.worldMode() end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({ right=true }) end) }, "onto the world-exit column x=63") end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() and bright()>=15 end,
    2000, "world control", 5),
  H.waitFrames(30),
  H.call(function() H.log(string.format("[world] landed at (%d,%d)", H.worldX(), H.worldY()))
    H.screenshot("opera_world_landing") end),

  -- 2. world walk to Jidoor entrance {27,129}, step DOWN -> map 198 {15,61}
  -- (worldGrind rather than worldNavTo, because of the (34,103) battle-zone
  -- blocklist problem)
  worldGrind(27, 129, "world walk -> Jidoor approach (27,129)"),
  H.call(function()
    H.log(string.format("[world] approach stop: world=%s map=%d world=(%d,%d) " ..
      "field=(%d,%d) control=%s aligned=%s", tostring(H.worldMode()), map(),
      H.worldX(), H.worldY(), H.fieldX(), H.fieldY(),
      tostring(H.worldHasControl()), tostring(H.worldAligned())))
  end),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end,
    2000, "at Jidoor approach", 5),
  (function() local hb=0
    return H.driveUntil(function() return not H.worldMode() and map()==198 end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({ down=true }) end) }, "into Jidoor (map 198)") end)(),
  H.waitUntil(function() return map()==198 and settled() end, 2400, "Jidoor control", 5),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 198, "in Jidoor (map 198)")
    H.log(string.format("[jidoor] landed at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- 3. Jidoor -> the north door: navTo the approach {16,13}, BUMP up into
  --    the {16,12}->209 archway (a $F7 wall entrance).
  H.navTo(16, 13, { maxFrames=24000, playBattles=true, arrive=function() return map()==209 end }),
  (function() local hb=0
    return H.driveUntil(function() return map()==209 end, 3000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if hb%16<8 then H.setPad({up=true}) elseif hb%16<12 then H.setPad({"a"}) else H.setPad({}) end
      end) }, "bump up into the (16,12) door -> map 209") end)(),
  H.waitUntil(function() return map()==209 and settled() end, 2400, "map 209 control", 5),
  H.waitFrames(150),
  -- The Zozo-to-Jidoor road may cost several failed run rolls.  Recover in
  -- town before banking the plot checkpoint so it represents arrival, not
  -- a party that happened to stagger through the door.
  H.fieldCare({ tag = "care on arrival in Jidoor", threshold = 0.55 }),
  H.call(function()
    H.assertEq(map(), 209, "in the opera-plot room (map 209)")
    H.log(string.format("[map209] landed at (%d,%d) $0331=%d $0340=%d",
      H.fieldX(), H.fieldY(), sw(0x0331), sw(0x0340)))
  end),

  H.openChest{ stand = { 125, 12 }, face = "up", bit = 66,
               what = "Tincture", item = 0xEB,
               nav = { playBattles = true } },

  -- 4. up to {117,20}, directly below the IMPRESARIO ({117,19}); face UP.
  H.navTo(117, 20, { maxFrames=12000, playBattles=true }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(6),
  (function() local calm=0
    return H.driveUntil(function()
      local ok = H.fieldX()==117 and H.fieldY()==20 and settled() and facing()==0
      calm = ok and calm+1 or 0
      if calm>=20 then H.setPad({}); return true end
      return false
    end, 3000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({"a"}); return end
        H.setPad({}) end) }, "twenty settled frames below the IMPRESARIO")
  end)(),
  H.call(function()
    H.assertEq(map(), 209, "on map 209")
    H.assertEq(H.fieldX()==117 and H.fieldY()==20, true, "at (117,20)")
    H.assertEq(facing(), 0, "facing UP toward the IMPRESARIO")
    H.assertEq(settled(), true, "entry point is QUIET")
    H.assertEq(sw(0x0331), 0, "$0331 CLEAR -- the letter has not appeared yet")
    H.assertEq(sw(0x0340), 0, "$0340 CLEAR -- the opera is not open yet")
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("opera_entry: char %d is on their feet", c))
    end
    H.log(string.format("[opera_entry] f%d map=%d (%d,%d) face=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), facing()))
    H.screenshot("opera_entry")
  end),
  H.saveState("opera_entry.mss"),

  -- Verify the banked state is one A-press from the plot: tap A up and
  -- confirm _ca9337 fires (the "Maria!?" dialog, then $0331=1 as the letter
  -- NPC spawns).  This runs after the state is generated, so the saved blob
  -- is unaffected; it confirms the entry point is not one press short of
  -- working.
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
    H.screenshot("opera_entry_verify")
  end),
  H.logStep(function()
    return string.format("opera_entry generated at frame %d -- one A-press below the map-209 IMPRESARIO", H.frame)
  end),
})
