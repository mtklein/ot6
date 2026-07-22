-- probe_opera_aria2.lua -- boots opera_backstage (map 234 theater, 16,46) and
-- tests the LEFT stage door (4,24) -> map 238, then maps the stage side (where
-- CELES stands at 99,19 and the aria trigger 97,7 live).  Fast: no intro.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
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
  H.log(string.format("[%s] map=%d (%d,%d) face=%d ctl=%s | 55=%d 56=%d 57=%d 58=%d 111=%d 340=%d 345=%d 355=%d 366=%d",
    tag, map(), H.fieldX(), H.fieldY(), facing(), tostring(H.hasControl()),
    sw(0x0055), sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0111),
    sw(0x0340), sw(0x0345), sw(0x0355), sw(0x0366)))
end
local function tiledump(x0,x1,y0,y1)
  for y=y0,y1 do
    local row = {}
    for x=x0,x1 do row[#row+1] = string.format("%02X", prop1(x,y)) end
    H.log(string.format("  y=%2d x%2d..%2d: %s", y, x0, x1, table.concat(row," ")))
  end
end
local function bumpUp(dest, what)
  local hb=0
  return H.driveUntil(function() return map()==dest end, 4000, {
    H.call(function() hb=hb+1
      if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
      if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if hb%16<8 then H.setPad({up=true}) elseif hb%16<12 then H.setPad({"a"}) else H.setPad({}) end
    end) }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_backstage.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),234,"boot 234"); dumpsw("boot-backstage") end),

  -- go to the LEFT stage door (4,24)
  H.navTo(4, 25, { maxFrames=12000, arrive=function() return map()==238 end }),
  H.call(function() dumpsw("at left door approach") end),
  bumpUp(238, "LEFT door (4,24) -> map 238"),
  H.waitUntil(function() return map()==238 and settled() end, 3000, "238 control", 5),
  H.waitFrames(60),
  H.call(function()
    dumpsw("MAP-238 via LEFT door"); H.screenshot("aria_238_left")
    H.log("=== map 238 around landing ("..H.fieldX()..","..H.fieldY()..") ===")
    tiledump(math.max(0,H.fieldX()-8), H.fieldX()+8, math.max(0,H.fieldY()-6), H.fieldY()+4)
    for _,d in ipairs({{97,7},{99,18},{99,19},{97,18},{97,19}}) do
      local p=H.bfsPath(d[1],d[2])
      H.log(string.format("  bfsPath ->(%d,%d): %s", d[1],d[2], p and ("len "..#p) or "NO PATH"))
    end
  end),

  -- if the stage (97,7) is reachable, walk toward CELES (99,19) and up to (97,7)
  H.call(function()
    local p = H.bfsPath(99,19)
    H.log("stage reachable: "..tostring(p~=nil))
  end),
  H.navTo(99, 20, { maxFrames=12000 }),
  H.call(function() dumpsw("near CELES (99,20)") end),
  -- try to trigger $0056: face up + A around (99,19)/(99,18)
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 or H.dialogWaiting() end, 3000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if hb%12<6 then H.setPad({"up","a"}) else H.setPad({}) end
      end) }, "talk CELES / read score -> $0056") end)(),
  H.call(function() dumpsw("after talk-attempt"); H.screenshot("aria_talk_attempt") end),
  H.logStep(function() return string.format("probe2 done f%d map=%d (%d,%d) 56=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0056)) end),
})
