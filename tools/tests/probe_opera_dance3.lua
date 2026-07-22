-- probe_opera_dance3.lua -- CORRECTED flower dance.  NPC(12,19)=FLOWERS
-- (_cabf27 -> $0057).  balcony (8,9)=_cabe6d needs only $0057 -> $0111.
-- Ignore Draco.  Touch flowers from (12,18) facing DOWN, then climb to (8,9).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
local MOVES={"up","upleft","upright","left","right","downleft","downright","down"}
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) face=%d | 57=%d 111=%d 1F0=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), facing(), sw(0x0057), sw(0x0111), sw(0x01F0)))
end
local function greedyStep(tx,ty, jitter)
  local x,y=H.fieldX(),H.fieldY()
  local best,bd=nil,1e9
  for _,mv in ipairs(MOVES) do
    if H.canStep(x,y,mv) then
      local d=DELTA[mv]; local dist=math.abs(x+d[1]-tx)+math.abs(y+d[2]-ty)
      if jitter and (mv=="down" or mv=="right") then dist=dist+0.4 end
      if dist<bd then bd=dist; best=mv end
    end
  end
  return best
end
-- drive toward (tx,ty); when within `near` tiles, press A (talk); watch `doneFn`
local function driveTo(tx,ty, near, doneFn, maxF, what)
  local ph,last,stuck,hb=0,nil,0,0
  return H.driveUntil(doneFn, maxF, { H.call(function() ph=(ph+1)%6; hb=hb+1
    if hb%60==0 then dumpsw(what) end
    if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY(); local key=x*256+y
    if key==last then stuck=stuck+1 else stuck=0 end; last=key
    local dist=math.abs(x-tx)+math.abs(y-ty)
    if dist<=near then
      -- face the target and tap A (talk the flowers / step the trigger)
      local dx,dy=tx-x,ty-y
      local fdir = (math.abs(dx)>=math.abs(dy)) and (dx<0 and "left" or "right") or (dy<0 and "up" or "down")
      if ph<3 then H.setPad({fdir}) elseif ph<5 then H.setPad({fdir,"a"}) else H.setPad({}) end
      return
    end
    local mv=greedyStep(tx,ty, stuck>2)
    if mv then H.setPad({[H.movePress(mv)]=true}) else H.setPad({}) end
  end) }, what)
end

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpsw("start") end),

  -- PHASE 1: touch the FLOWERS (12,19) from above -> $0057=1
  driveTo(12,19, 1, function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end, 4000, "toFlowers"),
  H.call(function() dumpsw("after flowers"); H.screenshot("dance3_flowers") end),

  -- PHASE 2: climb to the balcony (8,9) -> _cabe6d -> $0111=1
  driveTo(8,9, 0, function() return sw(0x0111)==1 or map()~=236 end, 6000, "toBalcony"),
  H.waitFrames(150),
  H.call(function() dumpsw("DONE"); H.screenshot("dance3_done") end),
  H.logStep(function() return string.format("dance3 f%d map=%d (%d,%d) 57=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111)) end),
})
