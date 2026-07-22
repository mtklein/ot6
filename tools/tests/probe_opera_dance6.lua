-- probe_opera_dance6.lua -- boot aria_postfork; drive the HAND-CODED climb table
-- (5,21)->(12,14) across the z-split stair tiles (canStep-gated, live z, pulsed
-- pad -- corridorFollow precedent), then chase+mash to observe the Draco waltz:
-- log all visible objects + switches so we SEE how the waltz fires and moves.
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

-- the CLIMB corridor (5,21) -> (12,14): per-tile ordered candidate moves
local CLIMB={}
local function c(x,y,d) CLIMB[key(x,y)]=d end
c(5,21,{"right"}); c(6,21,{"right"}); c(7,21,{"right"}); c(8,21,{"right"}); c(9,21,{"right"})
c(10,21,{"up"}); c(10,20,{"up"}); c(10,19,{"right"}); c(11,19,{"right"}); c(12,19,{"up"})
c(12,18,{"up"}); c(12,17,{"up"}); c(12,16,{"up"}); c(12,15,{"up"})

local function visObjs()
  local t={}
  for i=0,15 do
    if (ovis(i) & 0x80) ~= 0 then
      local x,y=ox(i),oy(i)
      if i~=6 and x<40 and y<40 then t[#t+1]={i=i,x=x,y=y} end
    end
  end
  return t
end
local function objline()
  local s={}
  for _,o in ipairs(visObjs()) do s[#s+1]=string.format("#%d(%d,%d)",o.i,o.x,o.y) end
  return table.concat(s," ")
end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d (%d,%d)z%d fc=%d | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | vis: %s",
    tag, H.frame, H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    H.readByte(0x087f+H.readWord(0x0803)), sw(0x0057), sw(0x0111),
    sw(0x01F0), sw(0x01F1), sw(0x01F2), objline()))
end

-- corridor follower: drive per-tile table to target (tx,ty)
local function climbTo(tx,ty, maxF)
  local hb=0
  return H.driveUntil(function()
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if hb%30==0 then dumpsw("climb") end
    if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(CLIMB[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, "climb")
end

-- chase nearest visible object + mash A to observe the waltz
local function chaseMash(maxF, doneFn)
  local ph,hb=0,0
  return H.driveUntil(doneFn, maxF, { H.call(function() ph=(ph+1)%6; hb=hb+1
    if hb%30==0 then dumpsw("chase") end
    if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    if ph>=4 then H.setPad({"a"}); return end   -- mash A 1/3 of the time
    local objs=visObjs(); if #objs==0 then H.setPad({"a"}); return end
    local x,y=H.fieldX(),H.fieldY()
    -- nearest object
    local best,bd=nil,1e9
    for _,o in ipairs(objs) do local d=math.abs(o.x-x)+math.abs(o.y-y); if d<bd then bd=d; best=o end end
    if bd<=1 then H.setPad({"a"}); return end   -- adjacent: touch
    -- greedy step toward it (dance area is uniform 02, canStep ok)
    local bm,bmd=nil,1e9
    for _,mv in ipairs(MOVES) do if H.canStep(x,y,mv) then
      local dd=DELTA[mv]; local dist=math.abs(x+dd[1]-best.x)+math.abs(y+dd[2]-best.y)
      if dist<bmd then bmd=dist; bm=mv end end end
    if bm then H.setPad({[H.movePress(bm)]=true}) else H.setPad({"a"}) end
  end) }, "chaseMash")
end

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpsw("START") end),
  climbTo(12,14, 4000),
  H.call(function() dumpsw("AT-DANCE"); H.screenshot("dance6_atdance") end),
  chaseMash(6000, function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end),
  H.waitFrames(30),
  H.call(function() dumpsw("AFTER-CHASE"); H.screenshot("dance6_afterchase") end),
  H.logStep(function() return string.format("dance6 f%d (%d,%d) 57=%d 111=%d 1F2=%d", H.frame, H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111), sw(0x01F2)) end),
})
