-- probe_opera_dance8.lua -- boot aria_postfork; the FULL flower dance:
--  climb (5,21)->(11,19); waltz Draco (obj#19) x3 by greedy-chase in the basin
--  ($01F0/1/2); touch flowers (obj#16) -> $0057; then the BALCONY corridor
--  (12,19 now free) up the z-split stairs to (8,9) -> _cabe6d -> $0111=1.
-- Validates the whole solve off the fast checkpoint (timer running).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function ovis(i) return H.readByte(0x0867 + i*STRIDE) end
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
local MOVES={"up","upleft","upright","left","right","downleft","downright","down"}
local function key(x,y) return y*256+x end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function activeObjs()
  local t={}
  for i=0,31 do
    local x,y=ox(i),oy(i)
    if i~=6 and (ovis(i)&0x80)~=0 and x>=3 and x<=16 and y>=5 and y<=28 then t[#t+1]={i=i,x=x,y=y} end
  end
  return t
end
local function dumpsw(tag)
  local a={}; for _,o in ipairs(activeObjs()) do a[#a+1]=string.format("#%d(%d,%d)",o.i,o.x,o.y) end
  H.log(string.format("[%s] f%d (%d,%d)z%d | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | %s",
    tag, H.frame, H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2), table.concat(a," ")))
end

local CLIMB={}
local function c(x,y,d) CLIMB[key(x,y)]=d end
c(5,21,{"right"}); c(6,21,{"right"}); c(7,21,{"right"}); c(8,21,{"right"}); c(9,21,{"right"})
c(10,21,{"right"}); c(11,21,{"up"}); c(11,20,{"up"})
local BAL={}
local function b(x,y,d) BAL[key(x,y)]=d end
b(11,19,{"right"}); b(12,19,{"up"}); b(12,18,{"up"}); b(12,17,{"up"}); b(12,16,{"up"}); b(12,15,{"up"})
b(12,14,{"right"}); b(13,14,{"right"}); b(14,14,{"up"}); b(14,13,{"up"}); b(14,12,{"up"}); b(14,11,{"up"})
b(14,10,{"left"}); b(13,10,{"left"}); b(12,10,{"left"}); b(11,10,{"up"}); b(11,9,{"left"}); b(10,9,{"left"}); b(9,9,{"left"})

local function tableDrive(TBL, tx,ty, maxF, doneFn, what)
  local hb=0
  return H.driveUntil(function()
    if doneFn and doneFn() then return true end
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if hb%40==0 then dumpsw(what) end
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

local function waltz(maxF, doneFn)
  local ph,hb=0,0
  return H.driveUntil(doneFn, maxF, { H.call(function() ph=(ph+1)%6; hb=hb+1
    if hb%40==0 then dumpsw("waltz") end
    if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    local objs=activeObjs()
    if #objs>0 then
      local best,bd=nil,1e9
      for _,o in ipairs(objs) do local d=math.abs(o.x-x)+math.abs(o.y-y); if d<bd then bd=d; best=o end end
      if bd<=1 then
        local dx,dy=best.x-x,best.y-y
        local fdir=(math.abs(dx)>=math.abs(dy)) and (dx<0 and "left" or "right") or (dy<0 and "up" or "down")
        H.setPad(ph<3 and {fdir} or {fdir,"a"}); return
      end
      local bm,bmd=nil,1e9
      for _,mv in ipairs(MOVES) do if H.canStep(x,y,mv) then
        local dd=DELTA[mv]; local dist=math.abs(x+dd[1]-best.x)+math.abs(y+dd[2]-best.y)
        if dist<bmd then bmd=dist; bm=mv end end end
      if bm then H.setPad({[H.movePress(bm)]=true}); return end
    end
    H.setPad(ph<3 and {"right"} or {"right","a"})
  end) }, "waltz")
end

-- rideOpen: gen_opera3's TEXT_ONLY-stall-safe finale rider (A/START on stall)
local function rideOpen(pred, maxFrames, what)
  local aPh,sPh,stallN,lx,ly = 0,0,0,-1,-1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8; sPh=(sPh+1)%16
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if aPh==0 then dumpsw("ride") end
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

H.run({ maxFrames = 30000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpsw("START") end),
  tableDrive(CLIMB, 11,19, 2500, nil, "climb"),
  H.call(function() dumpsw("AT-11-19") end),
  waltz(6000, function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end),
  H.call(function() dumpsw("FLOWERS-DONE"); H.screenshot("dance8_flowers") end),
  -- balcony corridor -> step on (8,9); done when reached / event took over / $0111
  tableDrive(BAL, 8,9, 5000, function() return sw(0x0111)==1 or map()~=236 or (H.fieldX()==8 and H.fieldY()==9) end, "balcony"),
  H.call(function() dumpsw("AT-BALCONY"); H.screenshot("dance8_balcony") end),
  -- ride the balcony FINALE (verses + load 233 + load 238) until $0111=1 on 238
  rideOpen(function() return sw(0x0111)==1 end, 20000, "finale->$0111"),
  H.waitFrames(30),
  H.call(function() dumpsw("DONE"); H.screenshot("dance8_done") end),
  H.logStep(function() return string.format("dance8 f%d map=%d (%d,%d) 57=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111)) end),
})
