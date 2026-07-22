-- probe_opera_route.lua -- find the aria entry.  Boots opera_backstage (map
-- 234 theater 16,46).  Door topology (decoded): 234 bottom doors (7,49)->237(48,32)
-- and (25,49)->237(72,32); 237 stage door (82,32)->238(100,22) stage; CELES stands
-- at 238(99,19) (obj_event _caba44 sets $0056=1); aria trigger 238(97,7).
-- Route A: 234 -> 237 -> (82,32) -> 238 stage -> talk CELES -> walk (97,7).
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
  H.log(string.format("[%s] map=%d (%d,%d) face=%d ctl=%s | 55=%d 56=%d 57=%d 58=%d 111=%d 345=%d 355=%d 366=%d",
    tag, map(), H.fieldX(), H.fieldY(), facing(), tostring(H.hasControl()),
    sw(0x0055), sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0111), sw(0x0345), sw(0x0355), sw(0x0366)))
end
local function reach(tag, pts)
  for _,d in ipairs(pts) do
    local p=H.bfsPath(d[1],d[2])
    H.log(string.format("  [%s] ->(%d,%d): %s", tag, d[1],d[2], p and ("len "..#p) or "NO PATH"))
  end
end
-- navTo a door src, then (fallback) bump the given dir until the map flips
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

H.run({ maxFrames = 90000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_backstage.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),234,"boot 234"); dumpsw("boot")
    reach("234", {{4,24},{28,24},{7,49},{25,49}}) end),

  -- 234 -> 237 via the RIGHT bottom door (25,49) [->237(72,32)]
  toDoor(25, 49, "down", 237, "234(25,49) -> 237"),
  H.call(function() dumpsw("on 237"); H.screenshot("route_237")
    reach("237", {{82,32},{80,32},{84,32},{72,32}}) end),

  -- 237 -> 238 stage via (82,32) [->238(100,22)]
  toDoor(82, 32, "up", 238, "237(82,32) -> 238 stage"),
  H.call(function() dumpsw("on 238 stage"); H.screenshot("route_238stage")
    reach("238", {{99,19},{99,18},{97,7},{97,8},{100,20}}) end),

  -- reach CELES (99,19): approach from below, face up, A to trigger _caba44 -> $0056
  H.navTo(99, 21, { maxFrames=12000 }),
  H.call(function() dumpsw("below CELES") end),
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 or H.dialogWaiting() end, 4000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if hb%12<6 then H.setPad({"up","a"}) else H.setPad({}) end
      end) }, "talk CELES -> $0056") end)(),
  -- ride any resulting dialog until control returns
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 and settled() end, 8000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({})
      end) }, "settle after CELES talk") end)(),
  H.call(function() dumpsw("after CELES talk"); H.screenshot("route_after_celes")
    reach("post", {{97,7},{97,8}}) end),
  H.assertEq(sw(0x0056), 1, "$0056 SET after CELES talk")
  H.saveState("opera_stage.mss"),

  -- walk directly onto the aria trigger (97,7); BFS approaches from (98,7)
  H.navTo(97, 7, { maxFrames=12000, arrive=function() return map()~=238 or sw(0x0111)==1 or not H.hasControl() end }),
  H.waitFrames(180),
  H.call(function() dumpsw("ARIA-fired?"); H.screenshot("route_aria_fired") end),
  H.logStep(function() return string.format("route probe done f%d map=%d (%d,%d) 56=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0056), sw(0x0111)) end),
})
