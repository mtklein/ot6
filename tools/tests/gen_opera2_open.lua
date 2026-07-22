-- gen_opera2_open.lua -- v0.5 Beat A leg 2: opera_doorstep (map 209, one
-- A-press below the map-209 IMPRESARIO) -> DRIVE THE OPERA-OPEN CUTSCENE
-- (_ca9337 "Maria!?" -> the letter $0331 -> the Setzer intro + name_menu ->
-- $0340=1) -> travel 209 -> Jidoor (198) -> world -> the OPERA HOUSE (map 237,
-- world {45,154}) -> parked at {60,49} facing UP below the now-VISIBLE
-- IMPRESARIO ({60,48}, _caae15).  Mints opera_open.mss -- one A-press from the
-- performance proper (the aria).
--
-- MEASURED (probe_opera_intro): the intro rides on a hasControl-gated stall
-- fallback that alternates A and START, which clears BOTH the dialog pages and
-- the name_menu SETZER without special-casing either; it ends on map 209
-- {118,24} with control and $0340=1/$010E=1.  Travel anchors: 209's {118,29}
-- door -> Jidoor {16,14}; Jidoor's SOUTH edge (long-entrance src{0,63} HORIZ
-- len31) -> world {27,132}; world -> opera approach {45,153} -> step DOWN.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

-- ride a cutscene: edge-A through dialog, START through a menu ($0059), and
-- when parked flag-less with no field control, alternate A/START (clears the
-- name_menu too).  Stall gated on hasControl (gen_zozo5's issue-#3 fix).
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

-- drive a cardinal direction until the map flips (bump/walk doors + edges)
local function pushTo(dir, destMap, maxFrames, what)
  local hb=0
  return H.driveUntil(function() return map()==destMap end, maxFrames, {
    H.call(function() hb=hb+1
      if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
      if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir]=true }) end) }, what)
end

H.run({ maxFrames = 120000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_doorstep.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 209, "boot map 209")
    H.assertEq(sw(0x0340), 0, "$0340 CLEAR (opera not open)")
  end),

  -- 1. the opera-open cutscene chain: talk impresario -> letter -> $0331=1
  (function() local aPh=0
    return H.driveUntil(function() return sw(0x0331)==1 or H.dialogWaiting() end, 2400, {
      H.call(function() aPh=(aPh+1)%8; H.setPad(aPh<4 and {"a","up"} or {}) end) }, "impresario answers") end)(),
  rideOpen(function() return sw(0x0331)==1 end, 12000, "impresario scene -> letter"),
  H.waitUntil(function() return map()==209 and H.hasControl() and H.tileAligned() end, 3000, "control after impresario", 5),
  -- read the letter NPC at {118,25}
  H.navTo(118, 26, { maxFrames=9000 }),
  H.hold({"up"}), H.waitFrames(8), H.release(), H.waitFrames(6),
  (function() local aPh=0
    return H.driveUntil(function() return H.dialogWaiting() or sw(0x01CC)==1 or map()~=209 end, 2400, {
      H.call(function() aPh=(aPh+1)%8; H.setPad(aPh<4 and {"a","up"} or {}) end) }, "read the letter") end)(),
  rideOpen(function() return sw(0x0340)==1 end, 40000, "letter -> Setzer intro -> $0340=1"),
  H.waitUntil(function() return map()==209 and settled() end, 3000, "control after opening the opera", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0340), 1, "$0340 SET -- the opera is OPEN")
    H.log(string.format("[opened] map=%d (%d,%d) $010E=%d", map(), H.fieldX(), H.fieldY(), sw(0x010E)))
    H.screenshot("opera_opened")
  end),

  -- 2. travel: 209 -> its {118,29} door -> Jidoor (198) {16,14}
  H.navTo(118, 28, { maxFrames=9000 }),
  pushTo("down", 198, 4000, "209 -> Jidoor (map 198)"),
  H.waitUntil(function() return map()==198 and settled() end, 2400, "Jidoor control", 5),
  H.waitFrames(150),
  H.call(function() H.log(string.format("[jidoor] at (%d,%d)", H.fieldX(), H.fieldY())) end),

  -- 3. Jidoor -> the SOUTH edge -> world {27,132}: navTo above the edge, push down
  H.navTo(16, 61, { maxFrames=15000 }),
  (function() local hb=0
    return H.driveUntil(function() return H.worldMode() end, 6000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ down=true }) end) }, "off Jidoor's south edge to the world") end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() and bright()>=15 end, 2000, "world control", 5),
  H.waitFrames(30),
  H.call(function() H.log(string.format("[world] Jidoor exit at (%d,%d)", H.worldX(), H.worldY())) end),

  -- 4. world -> the opera-house approach {45,153}, step DOWN -> map 237
  H.worldNavTo(45, 153, { maxFrames=60000, arrive=function() return not H.worldMode() end }),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end, 2000, "opera approach", 5),
  (function() local hb=0
    return H.driveUntil(function() return not H.worldMode() and map()==237 end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({ down=true }) end) }, "into the opera house (map 237)") end)(),
  H.waitUntil(function() return map()==237 and settled() end, 2400, "opera foyer control", 5),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 237, "in the opera house (map 237)")
    H.log(string.format("[237] landed (%d,%d) $0340=%d $0341=%d", H.fieldX(), H.fieldY(), sw(0x0340), sw(0x0341)))
  end),

  -- 5. up to {60,49}, below the now-VISIBLE IMPRESARIO ({60,48}); face UP
  H.navTo(60, 49, { maxFrames=9000 }),
  H.hold({"up"}), H.waitFrames(8), H.release(), H.waitFrames(6),
  (function() local calm=0
    return H.driveUntil(function()
      local ok=H.fieldX()==60 and H.fieldY()==49 and settled() and facing()==0
      calm=ok and calm+1 or 0; if calm>=20 then H.setPad({}); return true end; return false
    end, 3000, { H.call(function()
      if H.battleLoadStarted() then killBitAll(); H.setPad({"a"}); return end
      H.setPad({}) end) }, "settled below the opera-house IMPRESARIO") end)(),
  H.call(function()
    H.assertEq(map(), 237, "map 237")
    H.assertEq(H.fieldX()==60 and H.fieldY()==49, true, "at (60,49)")
    H.assertEq(facing(), 0, "facing UP")
    H.assertEq(sw(0x0340), 1, "$0340 SET -- opera open, IMPRESARIO visible")
    H.assertEq(sw(0x0055), 0, "$0055 CLEAR -- performance not started")
    H.log(string.format("[opera_open] f%d map=%d (%d,%d)", H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("opera_open")
  end),
  H.saveState("opera_open.mss"),

  -- self-verify: one A-press starts the performance (_caae15 -> $0055=1)
  (function() local aPh,hb=0,0
    return H.driveUntil(function() return sw(0x0055)==1 or map()~=237 end, 8000, {
      H.call(function() aPh=(aPh+1)%8; hb=hb+1
        if hb%120==0 then H.log(string.format("[verify f%d] $0055=%d map=%d", hb, sw(0x0055), map())) end
        if H.battleLoadStarted() then H.setPad(aPh<4 and {"a"} or {}); return end
        H.setPad(aPh<4 and {"a","up"} or {}) end) }, "one A-press starts the performance")
  end)(),
  H.call(function()
    H.log(string.format("[verify] performance kicked: $0055=%d map=%d", sw(0x0055), map()))
    H.assertEq(sw(0x0055)==1 or map()~=237, true, "VERIFIED: one A-press fired _caae15 (the performance)")
    H.screenshot("opera_open_verify")
  end),
  H.logStep(function() return string.format("opera_open minted at frame %d -- opera OPEN, at the performance trigger", H.frame) end),
})
