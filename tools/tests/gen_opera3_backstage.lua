-- gen_opera3_backstage.lua -- v0.5 Beat A leg 3: opera_open (map 237, one
-- A-press below the IMPRESARIO _caae15) -> RIDE THE PERFORMANCE INTRO -> the
-- party lands controllable BACKSTAGE in the theater, map 234 at {16,46},
-- $0055=1 (performance underway).  Mints opera_backstage.mss.
--
-- MEASURED (probe_opera_aria):
--  * Talking the impresario fires _caae15; the long intro cutscene (Locke's
--    plan, "we'll let him grab her", the scene-set) rides on the same
--    hasControl-gated A/START stall fallback gen_opera2 used, and DROPS the
--    party controllable on map 234 -- the THEATER SEATING (audience above,
--    the party in the stalls) -- at {16,46} facing DOWN, $0055=1, $0340=0.
--  * The intro is NOT ~14,400 frames of the survey's guess; it settles to
--    control near frame ~6k.  The ride terminates on 30 straight settled()
--    frames on a non-237 map so a transient control blip cannot mint early.
--  * The two STAGE doors out of 234 sit at its top corners {4,24} (left) and
--    {28,24} (right); the theater floor exits {7,49}/{25,49} lead to the
--    opera-house interior (237).  gen_opera4 routes 234 -> 237 -> the stage.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
-- the generic "advance everything" ride (gen_opera2's rideOpen idiom)
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

H.run({ maxFrames = 160000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_open.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 237, "boot map 237 (opera house)")
    H.assertEq(sw(0x0340), 1, "$0340 SET -- opera open")
    H.assertEq(sw(0x0055), 0, "$0055 CLEAR -- performance not started")
    H.log(string.format("[boot] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  -- 1. talk the IMPRESARIO -> _caae15 -> leave map 237 (the intro begins)
  (function() local aPh=0
    return H.driveUntil(function() return map()~=237 end, 8000, {
      H.call(function() aPh=(aPh+1)%8; H.setPad(aPh<4 and {"a","up"} or {}) end) }, "start the performance") end)(),

  -- 2. ride the whole intro to SUSTAINED field control on a NON-237 map
  (function() local calm,last=0,-1
    return rideOpen(function()
      if map()~=last then last=map(); H.log(string.format("[intro] f%d -> map %d (%d,%d) $0055=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0055))) end
      local ok = settled() and map()~=237
      calm = ok and calm+1 or 0
      return calm>=30
    end, 90000, "ride the intro to backstage control")
  end)(),
  H.waitUntil(function() return map()==234 and settled() end, 4000, "backstage control", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 234, "backstage on map 234 (theater)")
    H.assertEq(H.fieldX()==16 and H.fieldY()==46, true, "at (16,46)")
    H.assertEq(sw(0x0055), 1, "$0055 SET -- performance underway")
    H.assertEq(sw(0x0056), 0, "$0056 CLEAR -- aria not armed")
    H.assertEq(settled(), true, "backstage is QUIET")
    -- the stage doors out of the theater are reachable
    H.assertEq(H.bfsPath(25,49)~=nil, true, "theater exit (25,49)->237 reachable")
    H.assertEq(H.bfsPath(28,24)~=nil, true, "stage door (28,24)->238 reachable")
    H.log(string.format("[opera_backstage] f%d map=%d (%d,%d) face=%d $0055=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), facing(), sw(0x0055)))
    H.screenshot("opera_backstage")
  end),
  H.saveState("opera_backstage.mss"),
  H.logStep(function()
    return string.format("opera_backstage minted at frame %d -- theater (map 234), $0055=1", H.frame)
  end),
})
