-- probe_opera_dance4.lua -- LAST dance attempt + diagnosis.  Climb the x=12
-- column to Draco (12,14), talk UP to advance _cabd35 ($01F0->1->2), tracking
-- every object so Draco's movement is visible.  Then flowers -> balcony.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local STRIDE=0x29
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
local MOVES={"up","upleft","upright","left","right","downleft","downright","down"}
local function objline()
  local s={}
  for _,i in ipairs({0,3,7,8,9,10,12,13,14,15}) do
    local x,y=ox(i),oy(i); if x<60 and y<40 then s[#s+1]=string.format("#%d(%d,%d)",i,x,y) end
  end
  return table.concat(s," ")
end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d (%d,%d) fc=%d | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | objs %s",
    tag, H.frame, H.fieldX(), H.fieldY(), facing(), sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2), objline()))
end
local function greedyStep(tx,ty, jitter)
  local x,y=H.fieldX(),H.fieldY(); local best,bd=nil,1e9
  for _,mv in ipairs(MOVES) do if H.canStep(x,y,mv) then
    local d=DELTA[mv]; local dist=math.abs(x+d[1]-tx)+math.abs(y+d[2]-ty)
    if jitter and (mv=="down" or mv=="right") then dist=dist+0.4 end
    if dist<bd then bd=dist; best=mv end end end
  return best
end
-- climb to (tx,ty); when within `near`, tap A facing UP (talk Draco above); done on `doneFn`
local function climbTalk(tx,ty,near,fdir, doneFn,maxF,what)
  local ph,last,stuck,hb=0,nil,0,0
  return H.driveUntil(doneFn, maxF, { H.call(function() ph=(ph+1)%6; hb=hb+1
    if hb%60==0 then dumpsw(what) end
    if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY(); local key=x*256+y
    if key==last then stuck=stuck+1 else stuck=0 end; last=key
    if math.abs(x-tx)+math.abs(y-ty)<=near then
      if ph<3 then H.setPad({fdir}) elseif ph<5 then H.setPad({fdir,"a"}) else H.setPad({}) end
      return
    end
    local mv=greedyStep(tx,ty, stuck>2)
    if mv then H.setPad({[H.movePress(mv)]=true}) else H.setPad({fdir,"a"}) end
  end) }, what)
end

H.run({ maxFrames = 14000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpsw("start") end),
  -- talk Draco up the column: aim (12,15), talk UP, until $01F2 (waltz done)
  climbTalk(12,15,1,"up", function() return sw(0x01F2)==1 or sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end, 5000, "waltz"),
  H.call(function() dumpsw("after waltz"); H.screenshot("dance4_waltz") end),
  -- flowers (12,19) from above
  climbTalk(12,18,1,"down", function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end, 3000, "flowers"),
  H.call(function() dumpsw("after flowers"); H.screenshot("dance4_flowers") end),
  -- balcony (8,9)
  climbTalk(8,9,0,"up", function() return sw(0x0111)==1 or map()~=236 end, 4000, "balcony"),
  H.waitFrames(120),
  H.call(function() dumpsw("DONE"); H.screenshot("dance4_done") end),
  H.logStep(function() return string.format("dance4 f%d map=%d (%d,%d) 57=%d 111=%d 1F2=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111), sw(0x01F2)) end),
})
