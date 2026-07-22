-- probe_opera_postfork.lua -- mint aria_postfork (opera_stage -> aria -> forks
-- {0,1,0} -> control on 236), then GREEDY-climb toward the balcony (8,9) with
-- A-mashing, logging switches + position to crack the flower-dance stair nav.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) f=%d ctl=%s dlg=%s | 57=%d 58=%d 110=%d 111=%d 1F0=%d 1F1=%d 1F2=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), facing(), tostring(H.hasControl()), tostring(H.dialogWaiting()),
    sw(0x0057), sw(0x0058), sw(0x0110), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)))
end
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
local MOVES={"up","upright","upleft","right","left","downright","downleft","down"}
local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0},upright={1,-1},upleft={-1,-1},downright={1,1},downleft={-1,1}}
-- greedy: step toward (tx,ty) via canStep, minimizing manhattan dist; A-mash
local function climb(tx,ty, watchDone, maxFrames, what)
  local ph,last,stuck,hb = 0, nil, 0, 0
  return H.driveUntil(function() return watchDone() end, maxFrames, {
    H.call(function() ph=(ph+1)%6; hb=hb+1
      if hb % 60 == 0 then dumpsw("climb:"..what) end
      if H.dialogWaiting() then H.setPad(ph<3 and {"a"} or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      local x,y=H.fieldX(),H.fieldY()
      local key=x*256+y; if key==last then stuck=stuck+1 else stuck=0 end; last=key
      -- every ~6th aligned frame, press A (talk NPCs) instead of moving
      if ph==5 then H.setPad({"a"}); return end
      local best,bd=nil,1e9
      for _,mv in ipairs(MOVES) do
        if H.canStep(x,y,mv) then
          local d=DELTA[mv]; local nx,ny=x+d[1],y+d[2]
          local dist=math.abs(nx-tx)+math.abs(ny-ty)
          -- when stuck, add jitter so we escape local minima
          if stuck>3 then dist=dist+((mv=="left" or mv=="up") and 0 or 1) end
          if dist<bd then bd=dist; best=mv end
        end
      end
      if best then H.setPad({[H.movePress(best)]=true}) else H.setPad({}) end
    end) }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.navTo(97, 7, { maxFrames=8000, arrive=function() return map()~=238 end }),
  H.waitUntil(function() return map()==236 end, 6000, "aria 236", 10),
  ariaFork(0, "fork1"), ariaFork(1, "fork2"), ariaFork(0, "fork3"),
  H.waitUntil(function() return map()==236 and H.hasControl() and H.tileAligned() end, 6000, "control after forks", 5),
  H.waitFrames(20),
  H.call(function() dumpsw("POSTFORK"); H.screenshot("postfork") end),
  H.saveState("aria_postfork.mss"),

  -- greedy climb toward (12,19) [flower NPC -> $0057], then (8,9) [balcony -> $0111]
  climb(12, 19, function() return sw(0x0057)==1 or sw(0x0111)==1 or map()~=236 end, 6000, "to flower(12,19)"),
  H.call(function() dumpsw("after climb1"); H.screenshot("climb1") end),
  climb(8, 9, function() return sw(0x0111)==1 or map()~=236 end, 8000, "to balcony(8,9)"),
  H.waitFrames(120),
  H.call(function() dumpsw("CLIMB-DONE"); H.screenshot("climb_done") end),
  H.logStep(function() return string.format("postfork/climb f%d map=%d (%d,%d) 57=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111)) end),
})
