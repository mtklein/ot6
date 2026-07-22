-- probe_opera_geom.lua -- boot opera_stage, drive the aria forks {0,1,0} to
-- control on map 236, MINT aria_postfork.mss, then dump ground truth for the
-- flower-dance nav: every field object (vis/x/y/face/movetype), and the p1/p2
-- passability grid over the pocket+stairs+balcony region x[3..18] y[6..27].
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function ovis(i) return H.readByte(0x0867 + i*STRIDE) end
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local function oface(i) return H.readByte(0x087f + i*STRIDE) end
local function omove(i) return H.readByte(0x087c + i*STRIDE) end
local function p1(x,y) return H.readByte(0x7E7600 + H.maptile(x,y)) end
local function p2(x,y) return H.readByte(0x7E7700 + H.maptile(x,y)) end
local function tid(x,y) return H.maptile(x,y) end

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

local function dumpObjs(tag)
  H.log(string.format("[objs %s] f%d map=%d party=$%03x -> obj#%d CELES(%d,%d) z=%d | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d",
    tag, H.frame, map(), H.readWord(0x0803), H.readWord(0x0803)//STRIDE,
    H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)))
  for i=0,15 do
    local v,x,y = ovis(i), ox(i), oy(i)
    if v~=0 or (x<200 and y<200 and (x~=0 or y~=0)) then
      H.log(string.format("   obj#%2d vis=$%02x (%3d,%3d) face=%d move=$%02x", i, v, x, y, oface(i), omove(i)))
    end
  end
end

local function dumpGrid(x0,x1,y0,y1)
  -- header
  local hdr="   y\\x"
  for x=x0,x1 do hdr=hdr..string.format(" %02d",x) end
  H.log("[p1grid]"..hdr)
  for y=y0,y1 do
    local row=string.format("   %3d ",y)
    for x=x0,x1 do row=row..string.format(" %02x",p1(x,y)) end
    H.log("[p1] "..row)
  end
  H.log("[p2grid]"..hdr)
  for y=y0,y1 do
    local row=string.format("   %3d ",y)
    for x=x0,x1 do row=row..string.format(" %02x",p2(x,y)) end
    H.log("[p2] "..row)
  end
end

H.run({ maxFrames = 40000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.navTo(97, 7, { maxFrames=8000, arrive=function() return map()~=238 end }),
  H.waitUntil(function() return map()==236 end, 6000, "aria 236", 10),
  ariaFork(0, "fork1"), ariaFork(1, "fork2"), ariaFork(0, "fork3"),
  H.waitUntil(function() return map()==236 and H.hasControl() and H.tileAligned() end, 6000, "control after forks", 5),
  H.waitFrames(10),
  H.call(function() dumpObjs("POSTFORK"); H.screenshot("geom_postfork") end),
  H.saveState("aria_postfork.mss"),
  H.call(function() dumpGrid(3,18,6,27) end),
  H.logStep(function() return string.format("geom dump done f%d map=%d (%d,%d)", H.frame, map(), H.fieldX(), H.fieldY()) end),
})
