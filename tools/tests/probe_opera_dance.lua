-- probe_opera_dance.lua -- opera_stage -> aria -> forks {0,1,0} -> then the
-- FLOWER DANCE on map 236: dump geometry, reach NPC(12,19)=_cabf27 ($0057=1) and
-- Draco NPC(12,14)=_cabd35, then the balcony trigger (8,9)=_cabe6d -> $0111=1.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function prop1(x,y) return H.readByte(0x7E7600 + H.maptile(x,y)) end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) f=%d ctl=%s | 57=%d 58=%d 110=%d 111=%d 1F0=%d 1F1=%d 1F2=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), facing(), tostring(H.hasControl()),
    sw(0x0057), sw(0x0058), sw(0x0110), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)))
end
local function tiledump(x0,x1,y0,y1)
  for y=y0,y1 do local r={}; for x=x0,x1 do r[#r+1]=string.format("%02X",prop1(x,y)) end
    H.log(string.format("  y=%2d x%2d..%2d: %s", y, x0, x1, table.concat(r," "))) end
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
-- navTo a tile adjacent to (nx,ny), face it, tap A; report the target switch
local function talkAt(ax,ay, fdir, watchId, what)
  return H.cond(function() return true end, {
    H.navTo(ax, ay, { maxFrames=6000 }),
    (function() local ph=0
      return H.driveUntil(function() return sw(watchId)==1 or H.dialogWaiting() end, 2500, {
        H.call(function() ph=(ph+1)%10
          if H.dialogWaiting() then H.setPad(ph<4 and {"a"} or {}); return end
          if ph<3 then H.setPad({fdir}) elseif ph<6 then H.setPad({fdir,"a"}) else H.setPad({}) end
        end) }, what) end)(),
    -- ride any dialog to close
    (function() local ph=0
      return H.driveUntil(function() return not H.dialogWaiting() and H.hasControl() end, 3000, {
        H.call(function() ph=(ph+1)%8; H.setPad(H.dialogWaiting() and ph<4 and {"a"} or {}) end) }, what.." close") end)(),
    H.call(function() dumpsw(what.." result") end),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.navTo(97, 7, { maxFrames=8000, arrive=function() return map()~=238 end }),
  H.waitUntil(function() return map()==236 end, 6000, "aria loaded 236", 10),
  ariaFork(0, "fork1"), ariaFork(1, "fork2"), ariaFork(0, "fork3"),
  H.waitUntil(function() return map()==236 and H.hasControl() and H.tileAligned() end, 6000, "control after forks", 5),
  H.waitFrames(20),
  H.call(function()
    dumpsw("DANCE-start"); H.screenshot("dance_start")
    H.log("=== map 236 geometry (x0..24, y6..28) ===")
    tiledump(0,24,6,28)
    for _,d in ipairs({{8,9},{12,19},{12,20},{12,14},{12,15},{8,10}}) do
      local p=H.bfsPath(d[1],d[2])
      H.log(string.format("  bfsPath ->(%d,%d): %s prop=%02X", d[1],d[2], p and ("len "..#p) or "NO PATH", prop1(d[1],d[2])))
    end
  end),

  -- try Draco first (12,14): follow-lead _cabd35 ($01F0..)
  talkAt(12, 15, "up", 0x01F0, "talk Draco(12,14)"),
  -- try the flower NPC (12,19): _cabf27 ($0057=1)
  talkAt(12, 20, "up", 0x0057, "talk NPC(12,19)"),
  -- head to the balcony (8,9): _cabe6d -> $0111=1
  H.navTo(8, 10, { maxFrames=8000 }),
  H.call(function() dumpsw("at balcony approach") end),
  (function() local ph=0
    return H.driveUntil(function() return sw(0x0111)==1 or map()~=236 or H.dialogWaiting() end, 4000, {
      H.call(function() ph=(ph+1)%10
        if H.dialogWaiting() then H.setPad(ph<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if ph<4 then H.setPad({up=true}) else H.setPad({}) end
      end) }, "step onto balcony (8,9)") end)(),
  H.waitFrames(120),
  H.call(function() dumpsw("BALCONY-result"); H.screenshot("dance_balcony") end),
  H.logStep(function() return string.format("dance done f%d map=%d (%d,%d) 57=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111)) end),
})
