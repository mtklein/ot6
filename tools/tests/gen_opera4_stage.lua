-- gen_opera4_stage.lua -- v0.5 Beat A leg 4: opera_backstage (theater map 234
-- {16,46}) -> ROUTE A onto the STAGE (map 238) with the aria ARMED ($0056=1),
-- parked at {99,20} one navTo from the aria trigger {97,7}.  Mints opera_stage.mss.
--
-- ROUTE A, measured (probe_opera_route/stage), from the decoded door topology
-- (short_entrance.dat, maps 234/237/238):
--  * The two theater STAGE doors {4,24}/{28,24} both dump into a BACKSTAGE
--    region of 238 (x>=109) that is passability-DISCONNECTED from the stage.
--    The stage is reached through the opera-house interior instead:
--      234 {25,49} --> 237 {72,32}  (theater floor exit)
--      237 {82,32} --> 238 {100,22} (the STAGE door; walk RIGHT from {72,32})
--    237's IMPRESARIO sits at {60,48}, far from the {72,32}->{82,32} walk, so
--    the performance trigger _caae15 is never re-armed in passing.
--  * On 238, map-init _caf187 shows CELES at {99,19} (obj_event _caba44) while
--    $0055=1 & $0056=0.  Talking her ({99,21} facing UP, A) runs the pre-aria
--    dialog _caba44->_cabaa8, which sets $0056=1 and hands control back at
--    {99,20}.  The aria trigger _cabafd {97,7} then fires ($0056=1 & $0057=0).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
-- navTo a walk-on door src, bump fallback, settle on the destination map
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
  H.call(function()
    H.assertEq(map(), 234, "boot backstage (map 234)")
    H.assertEq(sw(0x0055), 1, "$0055 SET (performance underway)")
    H.assertEq(sw(0x0056), 0, "$0056 CLEAR (aria not armed)")
    H.log(string.format("[boot] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  -- 234 -> 237 (theater floor exit {25,49}) -> 238 stage (door {82,32})
  toDoor(25, 49, "down", 237, "234(25,49) -> 237"),
  H.call(function() H.assertEq(map(),237,"in the opera house (237)")
    H.log(string.format("[237] at (%d,%d)", H.fieldX(), H.fieldY())) end),
  toDoor(82, 32, "up", 238, "237(82,32) -> 238 stage"),
  H.call(function() H.assertEq(map(),238,"on the stage (238)")
    H.log(string.format("[238] at (%d,%d)", H.fieldX(), H.fieldY())) end),

  -- talk CELES ({99,19}) from below -> _caba44/_cabaa8 -> $0056=1
  H.navTo(99, 21, { maxFrames=12000 }),
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 or H.dialogWaiting() end, 4000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if hb%12<6 then H.setPad({"up","a"}) else H.setPad({}) end
      end) }, "talk CELES -> $0056=1") end)(),
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0056)==1 and settled() end, 8000, {
      H.call(function() hb=hb+1
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({})
      end) }, "settle after CELES") end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 238, "on the stage (map 238)")
    H.assertEq(sw(0x0056), 1, "$0056 SET -- the aria is ARMED")
    H.assertEq(sw(0x0057), 0, "$0057 CLEAR -- fresh attempt")
    H.assertEq(sw(0x0111), 0, "$0111 CLEAR -- aria not yet solved")
    H.assertEq(H.bfsPath(97,7)~=nil, true, "aria trigger (97,7) reachable")
    H.assertEq(settled(), true, "stage doorstep is QUIET")
    H.log(string.format("[opera_stage] f%d map=%d (%d,%d) $0056=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0056)))
    H.screenshot("opera_stage")
  end),
  H.saveState("opera_stage.mss"),
  H.logStep(function()
    return string.format("opera_stage minted at frame %d -- stage armed ($0056=1), one navTo from the aria", H.frame)
  end),
})
