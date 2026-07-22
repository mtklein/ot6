-- probe_opera_stage.lua -- mint opera_stage.mss: boot opera_backstage, run
-- Route A (234 theater -> 237 -> stage door 82,32 -> 238 stage 100,22 -> talk
-- CELES -> $0056=1), settle, SAVE.  One navTo(97,7) from the aria.  No aria drive.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
local function dumpsw(tag)
  H.log(string.format("[%s] map=%d (%d,%d) face=%d ctl=%s | 55=%d 56=%d 57=%d 58=%d 111=%d 355=%d 366=%d",
    tag, map(), H.fieldX(), H.fieldY(), facing(), tostring(H.hasControl()),
    sw(0x0055), sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0111), sw(0x0355), sw(0x0366)))
end
local function toDoor(tx,ty,bumpDir,destMap,what)
  return H.cond(function() return true end, {
    H.navTo(tx, ty, { maxFrames=15000, arrive=function() return map()==destMap end }),
    (function() local hb=0
      return H.driveUntil(function() return map()==destMap end, 4000, {
        H.call(function() hb=hb+1
          if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
          if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
          if not H.hasControl() then H.setPad({}); return end
          if hb%16<10 then H.setPad({[bumpDir]=true}) elseif hb%16<13 then H.setPad({"a"}) else H.setPad({}) end
        end) }, what) end)(),
    H.waitUntil(function() return map()==destMap and settled() end, 3000, what.." settled", 5),
    H.waitFrames(60),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_backstage.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),234,"boot 234"); H.assertEq(sw(0x0055),1,"$0055 set"); dumpsw("boot") end),

  toDoor(25, 49, "down", 237, "234(25,49) -> 237"),
  H.call(function() dumpsw("on 237") end),
  toDoor(82, 32, "up", 238, "237(82,32) -> 238 stage"),
  H.call(function() dumpsw("on 238 stage") end),

  -- talk CELES (99,19) from below -> $0056=1
  H.navTo(99, 21, { maxFrames=12000 }),
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 or H.dialogWaiting() end, 4000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if hb%12<6 then H.setPad({"up","a"}) else H.setPad({}) end
      end) }, "talk CELES -> $0056") end)(),
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 and settled() end, 8000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({})
      end) }, "settle after CELES talk") end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(),238,"on map 238 stage")
    H.assertEq(sw(0x0056),1,"$0056 SET -- aria armed")
    H.assertEq(sw(0x0057),0,"$0057 clear -- fresh attempt")
    H.assertEq(H.bfsPath(97,7)~=nil, true, "aria trigger (97,7) reachable")
    dumpsw("opera_stage"); H.screenshot("opera_stage")
  end),
  H.saveState("opera_stage.mss"),
  H.logStep(function() return string.format("opera_stage minted f%d map=%d (%d,%d) 56=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0056)) end),
})
