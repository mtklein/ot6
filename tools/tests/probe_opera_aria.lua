-- probe_opera_aria.lua -- EXPLORE Beat A's aria.  Boots opera_open (map 237,
-- one A-press from the performance), rides the performance intro to backstage,
-- MINTS opera_backstage.mss (so later iterations skip the intro), then dumps
-- map-234 geometry + stage-door reachability, and tries to reach map 238 and
-- the aria trigger (97,7).  Pure measurement.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function prop1(x,y) return H.readByte(0x7E7600 + H.maptile(x,y)) end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
local function dumpsw(tag)
  H.log(string.format("[%s] map=%d (%d,%d) face=%d ctl=%s | 55=%d 56=%d 57=%d 58=%d 110=%d 111=%d 340=%d 341=%d 345=%d 346=%d 355=%d 366=%d",
    tag, map(), H.fieldX(), H.fieldY(), facing(), tostring(H.hasControl()),
    sw(0x0055), sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0110), sw(0x0111),
    sw(0x0340), sw(0x0341), sw(0x0345), sw(0x0346), sw(0x0355), sw(0x0366)))
end
local function tiledump(x0,x1,y0,y1)
  for y=y0,y1 do
    local row = {}
    for x=x0,x1 do row[#row+1] = string.format("%02X", prop1(x,y)) end
    H.log(string.format("  y=%2d x%d..%d: %s", y, x0, x1, table.concat(row," ")))
  end
end
local function rideOpen(pred, maxFrames, what)
  local aPh,sPh,stallN,lx,ly = 0,0,0,-1,-1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8; sPh=(sPh+1)%16
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then killBitAll(); stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if menuOpen() then stallN=0; H.setPad(sPh<6 and {"start"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=180 then
        if (aPh%2)==0 then H.setPad(aPh<4 and {"a"} or {}) else H.setPad(sPh<6 and {"start"} or {}) end
        return
      end
      H.setPad({})
    end) }, what)
end

H.run({ maxFrames = 260000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_open.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(), 237, "boot map 237"); dumpsw("boot") end),

  -- 1. talk impresario -> leave map 237 (the intro begins)
  (function() local aPh=0
    return H.driveUntil(function() return map()~=237 end, 8000, {
      H.call(function() aPh=(aPh+1)%8; H.setPad(aPh<4 and {"a","up"} or {}) end) }, "start the performance") end)(),
  H.call(function() dumpsw("left-237") end),

  -- 2. ride the whole intro to SUSTAINED field control on a NON-237 map
  (function() local calm,last=0,-1
    return rideOpen(function()
      if map()~=last then last=map(); H.log(string.format("[intro] f%d -> map %d (%d,%d) 55=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0055))) end
      local ok = settled() and map()~=237
      calm = ok and calm+1 or 0
      return calm>=30
    end, 80000, "ride the intro to backstage control")
  end)(),
  H.waitFrames(60),
  H.call(function() dumpsw("BACKSTAGE-landing"); H.screenshot("aria_backstage") end),
  H.saveState("opera_backstage.mss"),

  -- 3. map-234 geometry + stage-door reachability
  H.call(function()
    H.log("=== map "..map().." geometry ===")
    H.log(string.format("party at (%d,%d) prop=%02X", H.fieldX(), H.fieldY(), prop1(H.fieldX(),H.fieldY())))
    H.log("-- around the party --")
    tiledump(math.max(0,H.fieldX()-10), H.fieldX()+10, math.max(0,H.fieldY()-4), H.fieldY()+3)
    H.log("-- claimed stage doors y=22..27, x=2..30 --")
    tiledump(2,30,22,27)
    for _,d in ipairs({{4,24},{4,25},{28,24},{28,25},{16,24},{16,25},{3,24},{5,24},{27,24},{29,24}}) do
      local p = H.bfsPath(d[1],d[2])
      H.log(string.format("  bfsPath ->(%d,%d): %s  prop=%02X", d[1],d[2], p and ("len "..#p) or "NO PATH", prop1(d[1],d[2])))
    end
  end),

  -- 4. try the RIGHT stage door (28,24): navTo approach, bump UP
  H.navTo(28, 25, { maxFrames=12000, arrive=function() return map()==238 end }),
  H.call(function() dumpsw("after navTo(28,25)") end),
  (function() local hb=0
    return H.driveUntil(function() return map()==238 end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if hb%16<8 then H.setPad({up=true}) elseif hb%16<12 then H.setPad({"a"}) else H.setPad({}) end
      end) }, "bump UP into (28,24) -> map 238") end)(),
  H.waitUntil(function() return map()==238 and settled() end, 3000, "map 238 control", 5),
  H.waitFrames(60),
  H.call(function()
    dumpsw("MAP-238-entry"); H.screenshot("aria_238_entry")
    if map()==238 then
      H.log("=== map 238 geometry ===")
      H.log(string.format("party at (%d,%d)", H.fieldX(), H.fieldY()))
      H.log("-- entry area y=15..20, x=94..102 --")
      tiledump(94,102,15,20)
      H.log("-- aria trigger area y=5..11, x=93..101 --")
      tiledump(93,101,5,11)
      for _,d in ipairs({{97,7},{97,8},{99,18},{99,19}}) do
        local p=H.bfsPath(d[1],d[2])
        H.log(string.format("  bfsPath ->(%d,%d): %s", d[1],d[2], p and ("len "..#p) or "NO PATH"))
      end
    end
  end),
  H.logStep(function() return string.format("probe done at f%d map=%d (%d,%d)", H.frame, map(), H.fieldX(), H.fieldY()) end),
})
