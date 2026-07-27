-- gen_opera6_rafter.lua -- v0.5 Beat A leg 6: opera_dance_done (map 238 {98,7},
-- $0111=1) -> the RAFTER CHASE -> mint ultros2_doorstep one interaction before
-- battle 104 (Ultros②, $012d, 6 shields, slash|pierce).
--
-- Measured route: touch Ultros's letter, return through the active theater to
-- alert the Impresario, ride the briefing, talk to the stage master, operate
-- the far-right switch, enter the left framework, and cross map 235 to Ultros.
-- The five rat NPC gates carry no story state and are cleared before map 235
-- instantiates so the mint is deterministic inside the five-minute timer.
--
-- IMPORTANT: the WoB story encounter is `_cabf4b` -> battle 104.  Battle 134
-- belongs to the WoR Opera House dragon/weight event (`$0387=1`); older route
-- notes incorrectly conflated the two.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function clearSw(id)
  local a=0x1e80+math.floor(id/8)
  H.writeByte(a,H.readByte(a)&(~(1<<(id%8))&0xff))
end
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

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- rideScene: the gen_zozo5_ramuh stall-safe cutscene rider (stall counter gated
-- on hasControl(), NOT eventRunning() -- issue #3, REQUIRED for v0.5 cutscenes).
local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly = 0, 0, -1, -1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then killBitAll(); stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
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
    if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
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
    H.navTo(sx, sy, { maxFrames=8000 }),
    H.driveUntil(pred, maxF, { H.call(function() ph=(ph+1)%16
      if H.battleLoadStarted() then killBitAll() end
      if ph<8 then H.setPad({[dir]=true}) elseif ph<12 then H.setPad({"a"}) else H.setPad({}) end
    end) }, what),
  })
end

local function toDoor(tx,ty,bumpDir,destMap,what)
  return H.cond(function() return true end, {
    H.navTo(tx,ty,{maxFrames=12000,arrive=function() return map()==destMap end}),
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

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    -- BOOT INVARIANTS (these are the only lines this file can guarantee until
    -- opera_dance_done can be minted).
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    H.assertEq(sw(0x0111), 1, "$0111 SET -- the aria is solved (opera_dance_done)")
    H.assertEq(sw(0x0058), 0, "$0058 CLEAR -- Ultros has not dropped in yet")
    H.assertEq(sw(0x0345), 1, "$0345 SET -- the ENVELOPE (Ultros) is at 238 {99,20}")
    dumpsw("BOOT"); H.screenshot("rafter_boot")
  end),

  -- LEG 1: walk into the envelope at {99,20} -> _cabf31 -> $0058=1.
  bumpInto(99, 19, "down", function() return sw(0x0058)==1 or map()~=238 end, 6000,
    "touch the envelope -> $0058"),
  rideScene(function() return H.hasControl() and not H.dialogWaiting() end, 4000,
    "ride Ultros's threat dialog"),
  H.call(function()
    H.assertEq(sw(0x0058), 1, "$0058 SET -- Ultros threatened the opera")
    dumpsw("AFTER-ENVELOPE"); H.screenshot("rafter_ultros_dropped")
  end),
  -- CHECKPOINT: this is a clean, cheap replay point for the legs below.
  H.saveState("ultros_dropped.mss"),

  -- LEG 2 (measured): 238 stage door -> 237, then the audience-floor step
  -- trigger at {72,30}.  Since $0057=1, _ca5f48 loads map 233 (the active-opera
  -- variant of the theater), whose IMPRESARIO is still _cab724 at {15,46}.
  -- Stand above him at {15,45} and talk; the long 5-minute briefing lands on
  -- map 231 and sets $0110.
  toDoor(100,23,"down",237,"stage -> opera house"),
  H.navTo(72,30,{maxFrames=12000,arrive=function() return map()==233 end}),
  H.waitUntil(function() return map()==233 and settled() end,3000,"active theater settled",5),
  H.navTo(15,45,{maxFrames=12000}),
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

  -- LEG 3: stage master, far-right switch, then the newly-opened far-left
  -- framework.  The room landings and stairs are Z-split, so the short raw
  -- presses below are measured joins around otherwise ordinary navTo legs.
  H.navTo(28,24,{maxFrames=6000,arrive=function() return map()==232 end}),
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
  H.navTo(120,28,{maxFrames=1500}),
  H.driveUntil(function() return sw(0x0355)==0 end,500,{
    H.call(function() H.setPad({"up","a"}) end)},"operate far-right switch"),
  H.navTo(114,37,{maxFrames=3000,arrive=function() return map()==231 end}),
  H.waitUntil(function() return map()==231 and settled() end,1000,"return theater",3),
  H.navTo(28,27,{maxFrames=500}),
  H.navTo(4,24,{maxFrames=6000,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"left room",3),
  H.driveUntil(function() return H.fieldY()==13 end,500,{H.hold({"up"})},"leave left landing"),
  H.navTo(117,5,{maxFrames=2500}),
  -- Rat battles carry no story state.  Remove their random blockers before
  -- map 235 instantiates so fixture generation traverses the full catwalk
  -- deterministically inside the five-minute window.
  H.call(function() for id=0x034c,0x0350 do clearSw(id) end end),
  H.navTo(117,3,{maxFrames=1000,arrive=function() return map()==235 end}),
  H.waitUntil(function() return map()==235 and settled() end,1000,"framework",3),
  H.navTo(6,16,{maxFrames=1000}),
  H.driveUntil(function() return H.fieldY()<=10 end,1000,{H.hold({"up"})},"climb framework"),
  H.driveUntil(function() return H.fieldY()>=11 end,1000,{H.hold({"down"})},"step onto rafters"),

  H.navTo(14,7,{maxFrames=5000}),
  H.call(function()
    local off=H.readWord(0x0803)
    H.writeByte(0x087f+off,1) -- face RIGHT toward Ultros
    H.writeByte(0x0743,1)
  end),
  H.call(function()
    H.assertEq(map(),235,"Ultros doorstep is on rafters map 235")
    H.assertEq(sw(0x02BC),1,"rafter timer is active at doorstep")
    dumpsw("ULTROS2-DOORSTEP")
  end),
  H.saveState("ultros2_doorstep.mss"),
  H.logStep(function()
    return string.format("gen_opera6_rafter: catwalk traversal banked Ultros 2 doorstep at f%d", H.frame)
  end),
})
