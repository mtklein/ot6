-- gen_opera5_dance.lua -- v0.5 Beat A leg 5: opera_stage (map 238 {99,20},
-- $0056=1) -> the ARIA forks {0,1,0} -> the FLOWER DANCE on map 236 -> $0111=1.
-- Mints opera_dance_done.mss on map 238 {98,7} after the aria is solved.
--
-- THE FLOWER DANCE (every claim measured -- probe_opera_geom/occ/dance5-8):
--  * Map 236 is Z-SPLIT.  p1 tile props: 09 = upper-z only, 02 = lower-z only,
--    03/0b = both-z BRIDGE tiles.  Stepping off a 09 tile drops z->1, off a 02
--    tile z->2, a 03/0b tile KEEPS z (player.asm zAfter).  The lib's bfsPath
--    seeds one z and SIMULATES zAfter along the path, but the live engine's z
--    diverges across the 09<->02<->03<->0b joins, so bfsPath returns NO PATH
--    from the postfork basin (5,21) to the dance area -- the documented blocker.
--    The fix is gen_zozo4_dadaluma's corridorFollow: a HAND-CODED per-tile
--    direction table driven ONE canStep-gated step at a time on the LIVE z
--    (which is always correct), pulsing the pad so no press outlives its step.
--  * DRACO is obj#19 (=NPC_4=$13, event _cabd35) and starts AT (12,19),
--    OCCUPYING it -- that occupancy is what seals the basin from the upper
--    region.  (The scoping record's "flowers {12,19}"/"Draco {12,14}" had the
--    two swapped: (12,19) is Draco, (12,14) is just open floor above.)
--  * THE WALTZ: stand at (11,19) (basin edge, reachable) and touch Draco to the
--    right.  Each touch runs _cabd35/_cabd5c/_cabd6a: he leads a SLOW dance step
--    that hops him a few tiles around the basin (all uniform 09, so a greedy
--    canStep chase catches him) and sets $01F0->$01F1->$01F2.  A 4th touch runs
--    _cabd7a: Draco is hidden and the FLOWERS (obj#16=NPC_1) spawn at (12,19).
--  * THE FLOWERS: touch obj#16 -> _cabf27 sets $0057=1 and moves NPC_1 away,
--    which FREES (12,19) and finally opens the climb to the upper region.
--  * THE BALCONY: climb (12,19)->(12,14) up the x=12 corridor, right to (14,14),
--    up the 0b column (14,13/12/11) to (14,10), left along y=10 to (11,10), up
--    to the y=9 strip, left to (8,9).  This DETOURS right/up AWAY from (8,9)
--    (why manhattan-greedy oscillated).  Stepping onto (8,9) fires _cabe6d
--    (gated $0057=1): it STOPS the timer, then rides the wedding-waltz finale
--    (TEXT_ONLY verses -> load_map 233 rafters -> load_map 238) and sets
--    $0111=1 on 238 at (98,7).  rideOpen (gen_opera3's stall-safe A/START rider)
--    carries that untimed tail.
--  * THE TIMER: start_timer 0, 2336, _cabd21 arms as control returns on 236
--    (~2287 grace).  climb+waltz+flowers+balcony to (8,9) measured ~1360 frames,
--    then stop_timer -- comfortable margin.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local STRIDE=0x29
local function ovis(i) return H.readByte(0x0867 + i*STRIDE) end
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
local MOVES={"up","upleft","upright","left","right","downleft","downright","down"}
local function key(x,y) return y*256+x end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d)z%d | 56=%d 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    sw(0x0056), sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)))
end

-- The aria forks: three chained choice dialogs, correct sequence {0,1,0}.  The
-- choice engine exposes cur=$056e, max=$056f; drive the cursor to idx, confirm.
local function ariaFork(idx, what)
  local ph, confirmed = 0, false
  return H.driveUntil(function()
    if confirmed and H.readByte(0x056f) < 2 and not H.dialogWaiting() then return true end
    return sw(0x0111)==1 or (map()~=236 and map()~=238)
  end, 15000, { H.call(function() ph=(ph+1)%8
    local maxc, cur = H.readByte(0x056f), H.readByte(0x056e)
    if maxc >= 2 then
      if cur < idx then H.setPad(ph<3 and {"down"} or {})
      elseif cur > idx then H.setPad(ph<3 and {"up"} or {})
      else H.setPad(ph<3 and {"a"} or {}); if ph<3 then confirmed=true end end
    else H.setPad(ph<4 and {"a"} or {}) end
  end) }, what)
end

-- active (vis-bit7) map-236 dance objects in range (Draco / the flowers)
local function activeObjs()
  local t={}
  for i=0,31 do
    local x,y=ox(i),oy(i)
    if i~=6 and (ovis(i)&0x80)~=0 and x>=3 and x<=16 and y>=5 and y<=28 then t[#t+1]={i=i,x=x,y=y} end
  end
  return t
end

-- corridorFollow: drive a per-tile direction table to (tx,ty), pulsed pad,
-- canStep-gated on the live z.  doneFn is an optional early terminator.
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
    if not H.tileAligned() then H.setPad({}); return end   -- pulse: no press outlives its step
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(TBL[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, what)
end

-- the waltz: from (11,19), greedy-chase the nearest active object and touch it.
-- Runs until $0057 (Draco waltzed x3 -> flowers spawned -> flowers touched).
local function waltz(maxF)
  local ph,hb=0,0
  return H.driveUntil(function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end, maxF, {
    H.call(function() ph=(ph+1)%6; hb=hb+1
      if hb%120==0 then dumpsw("[waltz]") end
      if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      local x,y=H.fieldX(),H.fieldY()
      local objs=activeObjs()
      if #objs>0 then
        local best,bd=nil,1e9
        for _,o in ipairs(objs) do local d=math.abs(o.x-x)+math.abs(o.y-y); if d<bd then bd=d; best=o end end
        if bd<=1 then  -- adjacent: face + tap A (touch)
          local dx,dy=best.x-x,best.y-y
          local fdir=(math.abs(dx)>=math.abs(dy)) and (dx<0 and "left" or "right") or (dy<0 and "up" or "down")
          H.setPad(ph<3 and {fdir} or {fdir,"a"}); return
        end
        local bm,bmd=nil,1e9   -- greedy step toward Draco (basin is uniform 09)
        for _,mv in ipairs(MOVES) do if H.canStep(x,y,mv) then
          local dd=DELTA[mv]; local dist=math.abs(x+dd[1]-best.x)+math.abs(y+dd[2]-best.y)
          if dist<bmd then bmd=dist; bm=mv end end end
        if bm then H.setPad({[H.movePress(bm)]=true}); return end
      end
      H.setPad(ph<3 and {"right"} or {"right","a"})   -- fallback: touch right toward (12,19)
    end) }, "waltz")
end

-- rideOpen: gen_opera3's TEXT_ONLY-stall-safe rider (A/START on a control-less
-- stall) -- carries the untimed balcony finale (verses + load 233 + load 238).
local function rideOpen(pred, maxFrames, what)
  local aPh,sPh,stallN,lx,ly = 0,0,0,-1,-1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8; sPh=(sPh+1)%16
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if aPh==0 and (H.frame%600<8) then dumpsw("["..what.."]") end
      if H.battleLoadStarted() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if menuOpen() then stallN=0; H.setPad(sPh<6 and {"start"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=120 then
        if (aPh%2)==0 then H.setPad(aPh<4 and {"a"} or {}) else H.setPad(sPh<6 and {"start"} or {}) end
        return
      end
      H.setPad({})
    end) }, what)
end

-- ---- the two hand-coded stair corridors (measured tile props) --------------
local CLIMB={}   -- postfork basin (5,21) -> (11,19), adjacent to Draco
local function c(x,y,d) CLIMB[key(x,y)]=d end
c(5,21,{"right"}); c(6,21,{"right"}); c(7,21,{"right"}); c(8,21,{"right"}); c(9,21,{"right"})
c(10,21,{"right"}); c(11,21,{"up"}); c(11,20,{"up"})
local BAL={}     -- (11,19) -> up the z-split stairs -> balcony trigger (8,9)
local function b(x,y,d) BAL[key(x,y)]=d end
b(11,19,{"right"}); b(12,19,{"up"}); b(12,18,{"up"}); b(12,17,{"up"}); b(12,16,{"up"}); b(12,15,{"up"})
b(12,14,{"right"}); b(13,14,{"right"}); b(14,14,{"up"}); b(14,13,{"up"}); b(14,12,{"up"}); b(14,11,{"up"})
b(14,10,{"left"}); b(13,10,{"left"}); b(12,10,{"left"}); b(11,10,{"up"}); b(11,9,{"left"}); b(10,9,{"left"}); b(9,9,{"left"})

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    H.assertEq(sw(0x0056), 1, "$0056 SET -- the aria is ARMED")
    H.assertEq(sw(0x0057), 0, "$0057 CLEAR -- fresh attempt")
    H.assertEq(sw(0x0111), 0, "$0111 CLEAR -- aria not yet solved")
    dumpsw("boot")
  end),

  -- fire the aria trigger {97,7} -> map 236 -> the lyric forks {0,1,0}
  H.navTo(97, 7, { maxFrames=8000, arrive=function() return map()~=238 end }),
  H.waitUntil(function() return map()==236 end, 6000, "aria loads map 236", 10),
  ariaFork(0, "fork1 (0)"), ariaFork(1, "fork2 (1)"), ariaFork(0, "fork3 (0)"),
  H.waitUntil(function() return map()==236 and H.hasControl() and H.tileAligned() end, 6000, "control on 236 (timer armed)", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(map(), 236, "on the castle stage (map 236)")
    H.assertEq(H.fieldX()==5 and H.fieldY()==21, true, "postfork at (5,21)")
    H.assertEq(sw(0x0111), 0, "$0111 still CLEAR (forks did not solve it)")
    dumpsw("POSTFORK"); H.screenshot("dance_postfork")
  end),

  -- climb the basin to Draco's edge (11,19)
  corridor(CLIMB, 11, 19, 2500, nil, "climb->(11,19)"),
  H.call(function()
    H.assertEq(H.fieldX()==11 and H.fieldY()==19, true, "at (11,19), left of Draco (12,19)")
    dumpsw("AT-DRACO")
  end),

  -- the waltz (3 touches) then the flowers -> $0057
  waltz(6000),
  H.call(function()
    H.assertEq(sw(0x0057), 1, "$0057 SET -- waltz done + flowers picked up")
    H.assertEq(map(), 236, "still on map 236")
    dumpsw("FLOWERS"); H.screenshot("dance_flowers")
  end),

  -- climb the z-split stairs to the balcony trigger (8,9)
  corridor(BAL, 8, 9, 5000,
    function() return sw(0x0111)==1 or map()~=236 or (H.fieldX()==8 and H.fieldY()==9) end,
    "balcony->(8,9)"),
  H.call(function() dumpsw("AT-BALCONY"); H.screenshot("dance_balcony") end),

  -- ride the wedding-waltz finale (untimed; stop_timer fired on (8,9)) -> $0111
  rideOpen(function() return sw(0x0111)==1 end, 20000, "finale->$0111"),

  -- settle on map 238 and mint the doorstep: the flower dance is SOLVED
  H.waitUntil(function() return map()==238 and settled() end, 6000, "control back on 238", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 238, "back on the stage (map 238)")
    H.assertEq(sw(0x0111), 1, "$0111 SET -- THE ARIA IS SOLVED (flower dance cracked)")
    H.assertEq(sw(0x0057), 1, "$0057 still SET")
    H.assertEq(settled(), true, "doorstep is QUIET -- no battle/event in flight")
    H.log(string.format("[opera_dance_done] f%d map=%d (%d,%d) $0111=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0111)))
    H.screenshot("opera_dance_done")
  end),
  H.saveState("opera_dance_done.mss"),
  H.logStep(function()
    return string.format("opera_dance_done minted at frame %d -- $0111=1, the flower-dance blocker is CRACKED", H.frame)
  end),
})
