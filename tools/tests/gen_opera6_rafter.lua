-- gen_opera6_rafter.lua -- v0.5 Beat A step 6: opera_dance_done (map 238
-- {98,7}, $0111=1) -> the RAFTER CHASE -> generate ultros2_doorstep one
-- interaction before battle 104 (Ultros②, $012d, 6 shields, slash|pierce).
--
-- Measured route: touch Ultros's letter, return through the active theater to
-- alert the Impresario, ride the briefing, talk to the stage master, operate
-- the far-right switch, enter the left framework, and cross map 235 to Ultros.
--
-- THE RAT GATES ARE PLAYED (issue #75).  The five rat NPCs ({8,11} {11,15}
-- {18,14} {21,7} {13,12}, switches $034C-$0350, npc_prop.asm _235) used to
-- be switched off before map 235 instantiated; now they wander live.  Each
-- is a no_react collision NPC whose event is `battle 25` -> win despawns it
-- and clears its switch, loss restarts the chase (_caba0b).  The catwalk
-- crossing simply FIGHTS whichever rats collide -- navTo's playBattles mode
-- taps the fight like any encounter -- inside the same 5-minute timer
-- (start_timer 0, 18000, event_main.asm:28736; it ticks through battles, so
-- the route stays lean and un-collided rats are left alone).  Before the
-- entry point generate the script WAITS until no live rat stands within 4
-- tiles of (14,7), so the banked state cannot boot into a rat collision
-- under battle_ultros2's immediate A-taps.
--
-- THE FACING IS EARNED, NOT POKED: the old generator wrote the object facing
-- byte and $0743 to point the party at Ultros; now the last act at the
-- entry point is a short RIGHT press against his occupied tile {15,7} -- a
-- blocked press turns the party in place -- and the facing is asserted
-- from RAM afterwards.  This file writes no emulated game state.
--
-- IMPORTANT: the WoB story encounter is `_cabf4b` -> battle 104.  Battle 134
-- belongs to the WoR Opera House dragon/weight event (`$0387=1`); older route
-- notes incorrectly conflated the two.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function key(x,y) return y*256+x end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d)z%d ctl=%s | 58=%d 110=%d 111=%d 345=%d 355=%d 366=%d 387=%d 1B0=%d 1B4=%d A4=%d 2BA=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    tostring(H.hasControl()),
    sw(0x0058), sw(0x0110), sw(0x0111), sw(0x0345), sw(0x0355), sw(0x0366),
    sw(0x0387), sw(0x01B0), sw(0x01B4), sw(0x00A4), sw(0x02BA)))
end

-- rat bookkeeping: NPC_9..NPC_13 ride objects 24..28 (NPC_n = object
-- n+15, gen_moogle's measured map), gates $034C..$0350 in list order.
-- A rat is LIVE while its gate switch is still set.
local function ratLine()
  local t = {}
  for k = 0, 4 do
    local obj = 24 + k
    local ox = H.readWord(0x086a + 0x29 * obj) >> 4
    local oy = H.readWord(0x086d + 0x29 * obj) >> 4
    t[#t + 1] = string.format("%d%s@(%d,%d)", k,
      sw(0x034C + k) == 1 and "+" or "-", ox, oy)
  end
  return table.concat(t, " ")
end
local function ratNear(x, y, r)
  for k = 0, 4 do
    if sw(0x034C + k) == 1 then
      local obj = 24 + k
      local ox = H.readWord(0x086a + 0x29 * obj) >> 4
      local oy = H.readWord(0x086d + 0x29 * obj) >> 4
      if math.abs(ox - x) + math.abs(oy - y) < r then return true end
    end
  end
  return false
end

-- rideScene: the gen_zozo5_ramuh stall-safe cutscene rider (stall counter gated
-- on hasControl(), NOT eventRunning() -- issue #3, REQUIRED for v0.5 cutscenes).
local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly = 0, 0, -1, -1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=180 then H.setPad(aPh<4 and {"a"} or {}); return end
      H.setPad({})
    end) }, what)
end

-- corridor: hand-coded per-tile direction table, canStep-gated on the live z,
-- pulsed so no press outlives its step (gen_opera5_dance's `corridor`).
local function corridor(TBL, tx, ty, maxF, doneFn, what)
  local hb=0
  return H.driveUntil(function()
    if doneFn and doneFn() then return true end
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if hb%120==0 then dumpsw("["..what.."]") end
    if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(TBL[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, what)
end

-- bump an on-contact (no_react) NPC at (tx,ty) from approach tile (sx,sy).
local function bumpInto(sx, sy, dir, pred, maxF, what)
  local ph=0
  return H.cond(function() return true end, {
    H.navTo(sx, sy, { maxFrames=12000, playBattles=true }),
    H.driveUntil(pred, maxF, { H.call(function() ph=(ph+1)%16
      if H.battleLoadStarted() then
        H.setPad(ph % 8 < 4 and { "a" } or {})   -- fought, not write-cleared
        return
      end
      if ph<8 then H.setPad({[dir]=true}) elseif ph<12 then H.setPad({"a"}) else H.setPad({}) end
    end) }, what),
  })
end

local function toDoor(tx,ty,bumpDir,destMap,what)
  return H.cond(function() return true end, {
    H.navTo(tx,ty,{maxFrames=18000,playBattles=true,arrive=function() return map()==destMap end}),
    (function() local n=0 return H.driveUntil(function() return map()==destMap end,3000,{
      H.call(function()
        n=n+1
        if H.dialogWaiting() then H.setPad(n%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(n%16<10 and {[bumpDir]=true} or {})
      end)
    },what) end)(),
    H.waitUntil(function() return map()==destMap and settled() end,3000,what.." settled",5),
  })
end

H.run({ maxFrames = 250000 }, {
  H.loadState("build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    -- BOOT INVARIANTS (these are the only lines this file can guarantee until
    -- opera_dance_done can be generated).
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    H.assertEq(sw(0x0111), 1, "$0111 SET -- the aria is solved (opera_dance_done)")
    H.assertEq(sw(0x0058), 0, "$0058 CLEAR -- Ultros has not dropped in yet")
    H.assertEq(sw(0x0345), 1, "$0345 SET -- the ENVELOPE (Ultros) is at 238 {99,20}")
    dumpsw("BOOT"); H.screenshot("rafter_boot")
  end),

  -- STEP 1: walk into the envelope at {99,20} -> _cabf31 -> $0058=1.
  bumpInto(99, 19, "down", function() return sw(0x0058)==1 or map()~=238 end, 6000,
    "touch the envelope -> $0058"),
  rideScene(function() return H.hasControl() and not H.dialogWaiting() end, 4000,
    "ride Ultros's threat dialog"),
  H.call(function()
    H.assertEq(sw(0x0058), 1, "$0058 SET -- Ultros threatened the opera")
    dumpsw("AFTER-ENVELOPE"); H.screenshot("rafter_ultros_dropped")
  end),
  -- CHECKPOINT: this is a clean, cheap replay point for the steps below.
  H.saveState("ultros_dropped.mss"),

  -- STEP 2 (measured): 238 stage door -> 237, then the audience-floor step
  -- trigger at {72,30}.  Since $0057=1, _ca5f48 loads map 233 (the active-opera
  -- variant of the theater), whose IMPRESARIO is still _cab724 at {15,46}.
  -- Stand above him at {15,45} and talk; the long 5-minute briefing lands on
  -- map 231 and sets $0110.
  toDoor(100,23,"down",237,"stage -> opera house"),
  H.navTo(72,30,{maxFrames=12000,playBattles=true,arrive=function() return map()==233 end}),
  H.waitUntil(function() return map()==233 and settled() end,3000,"active theater settled",5),
  H.navTo(15,45,{maxFrames=12000,playBattles=true}),
  (function() local n=0 return H.driveUntil(function()
    return sw(0x0110)==1 or H.dialogWaiting()
  end,3000,{H.call(function()
    n=n+1
    H.setPad(n%12<6 and {"down","a"} or {})
  end)},"talk active-opera impresario") end)(),
  rideScene(function() return sw(0x0110)==1 and map()==231 and settled() end,18000,
    "ride the 5-minute briefing"),
  H.call(function()
    H.assertEq(map(),231,"briefing lands in the active theater (231)")
    H.assertEq(sw(0x0110),1,"$0110 SET -- rafter timer armed")
    dumpsw("AFTER-BRIEFING")
  end),
  H.saveState("rafter_briefing.mss"),

  -- STEP 3: stage master, far-right switch, then the newly-opened far-left
  -- framework.  The room landings and stairs are Z-split, so the short raw
  -- presses below are measured joins around otherwise ordinary navTo steps.
  H.navTo(28,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"right room",3),
  H.driveUntil(function() return H.fieldY()==35 end,300,{H.hold({"up"})},"leave right landing"),
  H.driveUntil(function() return H.fieldY()==34 end,300,{H.hold({"up"})},"right stair 1"),
  H.driveUntil(function() return H.fieldX()==113 end,300,{H.hold({"left"})},"right stair 2"),
  H.driveUntil(function() return H.fieldY()==32 end,500,{H.hold({"up"})},"right stair 3"),
  H.driveUntil(function() return H.fieldX()==114 end,300,{H.hold({"right"})},"right stair 4"),
  H.driveUntil(function() return H.fieldX()>=117 and H.fieldY()<=29 end,800,{
    H.call(function()
      if H.dialogWaiting() then H.setPad({"a"})
      elseif H.hasControl() then H.setPad({"up","right"})
      else H.setPad({}) end
    end)},"reach stage master"),
  H.driveUntil(function() return sw(0x01B4)==1 end,1000,{
    H.call(function() H.setPad({"right","a"}) end)},"talk stage master"),
  H.navTo(120,28,{maxFrames=1500,playBattles=true}),
  H.driveUntil(function() return sw(0x0355)==0 end,500,{
    H.call(function() H.setPad({"up","a"}) end)},"operate far-right switch"),
  H.navTo(114,37,{maxFrames=3000,playBattles=true,arrive=function() return map()==231 end}),
  H.waitUntil(function() return map()==231 and settled() end,1000,"return theater",3),
  H.navTo(28,27,{maxFrames=500,playBattles=true}),
  H.navTo(4,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"left room",3),
  H.driveUntil(function() return H.fieldY()==13 end,500,{H.hold({"up"})},"leave left landing"),
  H.navTo(117,5,{maxFrames=2500,playBattles=true}),
  -- The five rat gates stay LIVE (see the header): the catwalk is crossed
  -- with navTo's playBattles mode, and a rat that collides fires battle 25 --
  -- fought by the same taps; a win despawns it and clears its gate.
  H.navTo(117,3,{maxFrames=6000,playBattles=true,arrive=function() return map()==235 end}),
  H.waitUntil(function() return map()==235 and settled() end,1500,"framework",3),
  H.call(function() H.log("[rats] on 235: " .. ratLine()) end),
  H.navTo(6,16,{maxFrames=30000,playBattles=true}),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()<=10 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({up=true}) end) }, "climb framework") end)(),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()>=11 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({down=true}) end) }, "step onto rafters") end)(),

  H.navTo(14,7,{maxFrames=30000,playBattles=true}),
  -- face Ultros by INPUT: his NPC occupies {15,7}, so a short RIGHT press
  -- is a blocked step that turns the party in place
  H.hold({ "right" }), H.waitFrames(6), H.release(), H.waitFrames(6),
  H.call(function()
    H.assertEq(H.fieldX()==14 and H.fieldY()==7, true,
      "still at (14,7) -- the blocked press did not step")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1,
      "facing RIGHT at Ultros (EVENT_DIR 1), earned by the blocked press")
  end),
  -- the banked state must not boot into a rat collision: wait until no
  -- LIVE rat stands within 4 tiles of the entry point (they wander off; the
  -- timer has headroom for this wait, and the log shows the field)
  (function() local calm=0
    return H.driveUntil(function()
      calm = (settled() and not ratNear(14,7,4)) and calm+1 or 0
      return calm >= 20
    end, 9000, { H.call(function()
      if H.battleLoadStarted() then H.setPad(H.frame%8<4 and {"a"} or {}); return end
      H.setPad({}) end) }, "a rat-free, settled entry point") end)(),
  H.call(function()
    H.assertEq(map(),235,"Ultros entry point is on rafters map 235")
    H.assertEq(sw(0x02BC),1,"rafter timer is active at the entry point")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing RIGHT")
    H.log("[rats] at generation: " .. ratLine())
    dumpsw("ULTROS2-DOORSTEP")
  end),
  H.saveState("ultros2_doorstep.mss"),
  H.logStep(function()
    return string.format("gen_opera6_rafter: catwalk traversal banked the Ultros 2 entry point at f%d", H.frame)
  end),
})
