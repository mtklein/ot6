-- probe_opera_dance7.lua -- boot aria_postfork; climb to (11,19) [reachable edge
-- of the basin, adjacent to the occupied (12,19)]; then TALK toward (12,19) and
-- observe: scan objects 0..31, log who is at (12,19), who MOVES on touch, and
-- the $01F0/1/2/$0057 switches.  Learn the real waltz mechanic + Draco slot.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function ovis(i) return H.readByte(0x0867 + i*STRIDE) end
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local function occFree(x,y) return (H.readByte(0x7E2000 + (y&0xFF)*256 + (x&0xFF)) & 0x80) ~= 0 end
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
local MOVES={"up","upleft","upright","left","right","downleft","downright","down"}
local function key(x,y) return y*256+x end
local CLIMB={}
local function c(x,y,d) CLIMB[key(x,y)]=d end
c(5,21,{"right"}); c(6,21,{"right"}); c(7,21,{"right"}); c(8,21,{"right"}); c(9,21,{"right"})
c(10,21,{"right"}); c(11,21,{"up"}); c(11,20,{"up"})
-- objects with vis bit7 set (active) OR nonzero low-area position, in dance-region range
local function activeObjs()
  local t={}
  for i=0,31 do
    local x,y=ox(i),oy(i)
    if i~=6 and (ovis(i)&0x80)~=0 and x>=3 and x<=16 and y>=5 and y<=28 then t[#t+1]={i=i,x=x,y=y,v=ovis(i)} end
  end
  return t
end
local function objline()
  local s={}
  for _,o in ipairs(activeObjs()) do s[#s+1]=string.format("#%d(%d,%d)v%02x",o.i,o.x,o.y,o.v) end
  -- also who occupies (12,19) region
  return table.concat(s," ")
end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d (%d,%d)z%d fc=%d | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | occ(12,19)=%s occ(12,14)=%s | act: %s",
    tag, H.frame, H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    H.readByte(0x087f+H.readWord(0x0803)), sw(0x0057), sw(0x0111),
    sw(0x01F0), sw(0x01F1), sw(0x01F2), tostring(occFree(12,19)), tostring(occFree(12,14)), objline()))
end
local function climbTo(tx,ty, maxF)
  local hb=0
  return H.driveUntil(function()
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if not H.hasControl() or not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(CLIMB[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, "climb")
end
-- from (11,19), waltz: chase the nearest active object, touch it (A while facing)
local function waltz(maxF, doneFn)
  local ph,hb=0,0
  return H.driveUntil(doneFn, maxF, { H.call(function() ph=(ph+1)%6; hb=hb+1
    if hb%20==0 then dumpsw("waltz") end
    if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    local objs=activeObjs()
    if #objs>0 then
      local best,bd=nil,1e9
      for _,o in ipairs(objs) do local d=math.abs(o.x-x)+math.abs(o.y-y); if d<bd then bd=d; best=o end end
      if bd<=1 then  -- adjacent: face + A
        local dx,dy=best.x-x,best.y-y
        local fdir=(math.abs(dx)>=math.abs(dy)) and (dx<0 and "left" or "right") or (dy<0 and "up" or "down")
        H.setPad(ph<3 and {fdir} or {fdir,"a"}); return
      end
      -- greedy step toward Draco (canStep live-z gated)
      local bm,bmd=nil,1e9
      for _,mv in ipairs(MOVES) do if H.canStep(x,y,mv) then
        local dd=DELTA[mv]; local dist=math.abs(x+dd[1]-best.x)+math.abs(y+dd[2]-best.y)
        if dist<bmd then bmd=dist; bm=mv end end end
      if bm then H.setPad({[H.movePress(bm)]=true}); return end
    end
    -- no active object: try talking toward (12,19) (right) from (11,19)
    H.setPad(ph<3 and {"right"} or {"right","a"})
  end) }, "waltz")
end

H.run({ maxFrames = 10000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpsw("START") end),
  climbTo(11,19, 2500),
  H.call(function() dumpsw("AT-11-19"); H.screenshot("dance7_at1119") end),
  waltz(5000, function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end),
  H.waitFrames(20),
  H.call(function() dumpsw("AFTER-WALTZ"); H.screenshot("dance7_afterwaltz") end),
  H.logStep(function() return string.format("dance7 f%d (%d,%d) 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d", H.frame, H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)) end),
})
