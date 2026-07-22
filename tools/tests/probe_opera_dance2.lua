-- probe_opera_dance2.lua -- boot aria_postfork; drive the flower dance
-- adaptively: chase the nearest play-stage NPC (Draco), A-mash to advance
-- _cabd35 ($01F0/1/2) and _cabf27 ($0057), then head to balcony (8,9)=_cabe6d
-- ($0111).  Heavy logging: a failure still reveals the mechanic.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function objX(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function objY(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local PLAY={3,7,8,9,10,12}   -- play-stage NPC object indices (from objscan)
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
local MOVES={"up","upright","upleft","right","left","downright","downleft","down"}
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d CELES(%d,%d) | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | draco?obj3=(%d,%d)",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2), objX(3), objY(3)))
end
-- nearest play NPC to CELES (returns tx,ty,dist)
local function nearestNPC()
  local cx,cy=H.fieldX(),H.fieldY()
  local bx,by,bd=nil,nil,1e9
  for _,i in ipairs(PLAY) do
    local x,y=objX(i),objY(i)
    if x<60 and y<40 then local d=math.abs(x-cx)+math.abs(y-cy)
      if d<bd then bd=d; bx=x; by=y end end
  end
  return bx,by,bd
end
-- greedy step toward (tx,ty); returns pressed move or nil
local function greedyStep(tx,ty, jitter)
  local x,y=H.fieldX(),H.fieldY()
  local best,bd=nil,1e9
  for _,mv in ipairs(MOVES) do
    if H.canStep(x,y,mv) then
      local d=DELTA[mv]; local dist=math.abs(x+d[1]-tx)+math.abs(y+d[2]-ty)
      if jitter and (mv=="right" or mv=="down") then dist=dist+0.5 end
      if dist<bd then bd=dist; best=mv end
    end
  end
  return best
end

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpsw("start") end),

  -- PHASE 1: chase & touch the nearest play NPC until $01F2 or $0057 sets
  (function() local ph,last,stuck,hb=0,nil,0,0
    return H.driveUntil(function()
      return sw(0x0057)==1 or sw(0x01F2)==1 or sw(0x0111)==1 or map()~=236
    end, 5000, { H.call(function() ph=(ph+1)%5; hb=hb+1
      if hb%60==0 then dumpsw("chase") end
      if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      local tx,ty,dist=nearestNPC()
      local x,y=H.fieldX(),H.fieldY(); local key=x*256+y
      if key==last then stuck=stuck+1 else stuck=0 end; last=key
      if not tx then H.setPad({}); return end
      if dist<=1 or ph==4 then H.setPad({"a"}); return end   -- adjacent/periodic: talk
      local mv=greedyStep(tx,ty, stuck>2)
      if mv then H.setPad({[H.movePress(mv)]=true}) else H.setPad({"a"}) end
    end) }, "chase Draco -> $01F2/$0057")
  end)(),
  H.call(function() dumpsw("after chase"); H.screenshot("dance2_chase") end),

  -- PHASE 2: head to balcony (8,9); A-mash to catch $0057 en route
  (function() local ph,last,stuck,hb=0,nil,0,0
    return H.driveUntil(function() return sw(0x0111)==1 or map()~=236 end, 5000, {
      H.call(function() ph=(ph+1)%6; hb=hb+1
        if hb%60==0 then dumpsw("toBalcony") end
        if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local x,y=H.fieldX(),H.fieldY(); local key=x*256+y
        if key==last then stuck=stuck+1 else stuck=0 end; last=key
        if ph==5 then H.setPad({"a"}); return end
        local mv=greedyStep(8,9, stuck>2)
        if mv then H.setPad({[H.movePress(mv)]=true}) else H.setPad({"a"}) end
      end) }, "climb to balcony (8,9) -> $0111")
  end)(),
  H.waitFrames(120),
  H.call(function() dumpsw("DONE"); H.screenshot("dance2_done") end),
  H.logStep(function() return string.format("dance2 f%d map=%d (%d,%d) 57=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111)) end),
})
