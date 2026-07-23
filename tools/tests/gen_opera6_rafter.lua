-- gen_opera6_rafter.lua -- v0.5 Beat A leg 6: opera_dance_done (map 238 {98,7},
-- $0111=1) -> the RAFTER CHASE -> mint ultros2_doorstep one interaction before
-- battle 134 (Ultros②, $012d, 6 shields, slash|pierce).
--
-- ============================ STATUS: UNVALIDATED ==========================
-- This generator could NOT be run: opera_dance_done is unreachable because the
-- prerequisite chain does not mint (sfigaro_town's cider-runner STEAL fails
-- deterministically -- see docs/design/wob-route.md "Beat A -- fourth pass").
-- The drive below is authored ENTIRELY from the vanilla event disassembly
-- (ff6/src/event/event_main.asm, npc_prop.asm, event_trigger.asm) and the
-- house idioms; every coord/switch carries its source line.  It is a measured
-- STARTING POINT, not a proven mint.  Treat every leg past the boot asserts as
-- a hypothesis to verify with a probe (probe_opera_rafter2.lua drives leg 1).
-- ==========================================================================
--
-- THE CHASE, decoded from source (all "_caXXXX" are event_main.asm labels):
--
--  LEG 1 -- ULTROS DROPS IN.  On boot $0345=1, so the ENVELOPE NPC sits at
--    238 {99,20} (npc_prop.asm:10427, gate $0345, event _cabf31).  It is
--    set_npc_no_react -> fires on CONTACT.  Walk into it: _cabf31 (:29595) runs
--    dlg $04C8 (Ultros "jam up your opera") + dlg $04C9 (LOCKE "tell the
--    Impresario"), then switch $0345=0, switch $0058=1.  ==> $0058=1 is leg 1's
--    latch.  (probe_opera_rafter2 confirms exactly this leg from source.)
--
--  LEG 2 -- ALERT THE IMPRESARIO (untimed).  The IMPRESARIO (event _cab724,
--    :28244) is NPC $0300 on MAP 234 {15,46} (npc_prop.asm:10077).  So travel
--    238 -> 237 -> 234 (reverse of gen_opera4's Route A: 234{25,49}<->237{72,32}
--    and 237{82,32}<->238{100,22}).  Talk him with $0058=1 & $0110=0: _cab724
--    -> _cab744 (:28266) -> (if $02BA=1 _cab95f else the full weight-hang
--    cutscene) -> the "5 minutes" scene -> _cab99b (:28677) loads the rafters
--    and reaches the briefing (:28716, dlg $04D8 "talk to the man in the room
--    to the far right"), which sets switch $0110=1, $02BA=1, $02BC=1 and
--    start_timer 0, 18000, _caba09 (:28736).  ==> $0110=1 is leg 2's latch AND
--    arms the 5-minute (18000f) chase timer; on expiry _caba09 (:28738) dumps
--    to a loss.  Party lands controllable near map 231 {15,37} (:28688).
--
--  LEG 3 -- THE STAGE MASTER + the framework.  With $0110=1 the STAGE MASTER
--    (_cab455, :27803) lets you up (_cab45f) and hints the "far right switch"
--    ($0355) and "the room to the far left of the stage, then the framework
--    above the stage" ($00A4 gates that hint, :27822).  Climb into the CATWALK
--    MAZE 233 -> 231 -> 239 -> 232 (these are Z-SPLIT catwalk maps; expect
--    bfsPath to fail across z-joins -> hand-coded corridor tables per
--    gen_zozo4_dadaluma / gen_opera5_dance).
--
--  LEG 4 -- THE 4-TON WEIGHT (map 232).  event_trigger.asm:1033 puts four
--    step-triggers on MAP 232 at y=27:
--       {120,27} _cab484 -- WRONG switch: switch $0355=0 (:27838)
--       {118,27} _cab497 -- the WEIGHT DROP (:27840): if ($01B0=1 & $01B4=1)
--                 drop -> fall anim -> load_map 231 -> if_switch $0387=1 ->
--                 _cab6d6 (:28199) -> battle 134 (:28207).  ==> THE FIGHT.
--       {117,27} _cab570 -- load_map 239 (:27978)
--       {116,27} _cab6fb -- BG tile mod only
--    The weight only drops when $01B0 & $01B4 are BOTH set (Ultros positioned)
--    and only fires battle 134 when $0387=1.  ***OPEN: what sets $01B0/$01B4/
--    $0387 during the chase is NOT yet decoded -- this is the crux the next
--    pass must measure (probe map 232 while walking the switches).***
--
--  DOORSTEP.  battle_ultros2.lua boots ultros2_doorstep and A-mashes into the
--    fight, so the doorstep must be a state whose first uninterrupted advance
--    reaches battle 134.  Best candidate: standing on map 232 one step N of
--    {118,27} with $01B0=$01B4=$0387=1, OR mid-_cab497 just before _cab6d6
--    (the fall->load->battle tail is dialog-free and auto-plays).  VERIFY.
--
--  Post-battle (_cab6d6 tail, :28208+): call _ca5ea9, switch $0332=1, load_map
--    237 -> Setzer scene.  The kill-bit _won idiom applies IF the post-battle
--    gate is battle-switch based (VERIFY before minting ultros2_won).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function key(x,y) return y*256+x end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d)z%d ctl=%s | 58=%d 110=%d 111=%d 345=%d 355=%d 366=%d 387=%d 1B0=%d 1B4=%d A4=%d 2BA=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    tostring(H.hasControl()),
    sw(0x0058), sw(0x0110), sw(0x0111), sw(0x0345), sw(0x0355), sw(0x0366),
    sw(0x0387), sw(0x01B0), sw(0x01B4), sw(0x00A4), sw(0x02BA)))
end

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- rideScene: the gen_zozo5_ramuh stall-safe cutscene rider (stall counter gated
-- on hasControl(), NOT eventRunning() -- issue #3, REQUIRED for v0.5 cutscenes).
local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly = 0, 0, -1, -1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then killBitAll(); stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=180 then H.setPad(aPh<4 and {"a"} or {}); return end
      H.setPad({})
    end) }, what)
end

-- corridor: hand-coded per-tile direction table, canStep-gated on the live z,
-- pulsed so no press outlives its step (gen_opera5_dance's `corridor`).
local function corridor(TBL, tx, ty, maxF, doneFn, what)
  local hb=0
  return H.driveUntil(function()
    if doneFn and doneFn() then return true end
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if hb%120==0 then dumpsw("["..what.."]") end
    if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
    if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(TBL[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, what)
end

-- bump an on-contact (no_react) NPC at (tx,ty) from approach tile (sx,sy).
local function bumpInto(sx, sy, dir, pred, maxF, what)
  local ph=0
  return H.cond(function() return true end, {
    H.navTo(sx, sy, { maxFrames=8000 }),
    H.driveUntil(pred, maxF, { H.call(function() ph=(ph+1)%16
      if H.battleLoadStarted() then killBitAll() end
      if ph<8 then H.setPad({[dir]=true}) elseif ph<12 then H.setPad({"a"}) else H.setPad({}) end
    end) }, what),
  })
end

H.run({ maxFrames = 90000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    -- BOOT INVARIANTS (these are the only lines this file can guarantee until
    -- opera_dance_done can be minted).
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    H.assertEq(sw(0x0111), 1, "$0111 SET -- the aria is solved (opera_dance_done)")
    H.assertEq(sw(0x0058), 0, "$0058 CLEAR -- Ultros has not dropped in yet")
    H.assertEq(sw(0x0345), 1, "$0345 SET -- the ENVELOPE (Ultros) is at 238 {99,20}")
    dumpsw("BOOT"); H.screenshot("rafter_boot")
  end),

  -- LEG 1: walk into the envelope at {99,20} -> _cabf31 -> $0058=1.
  bumpInto(99, 19, "down", function() return sw(0x0058)==1 or map()~=238 end, 6000,
    "touch the envelope -> $0058"),
  rideScene(function() return H.hasControl() and not H.dialogWaiting() end, 4000,
    "ride Ultros's threat dialog"),
  H.call(function()
    H.assertEq(sw(0x0058), 1, "$0058 SET -- Ultros threatened the opera")
    dumpsw("AFTER-ENVELOPE"); H.screenshot("rafter_ultros_dropped")
  end),
  -- CHECKPOINT: this is a clean, cheap replay point for the legs below.
  H.saveState("ultros_dropped.mss"),

  -- ===================== BELOW HERE IS UNVALIDATED ==========================
  -- LEG 2: travel 238 -> 237 -> 234 to the IMPRESARIO {15,46}, talk him to arm
  -- the timer + set $0110.  The 238<->237 door is 238{100,22}<->237{82,32};
  -- 237<->234 is 237{72,32}<->234{25,49} (gen_opera4 Route A, reversed).  navTo
  -- may not cross the door seams (z / disconnected regions) -- if it stalls,
  -- hand-code the door hops like gen_opera4 did.  Left as a documented TODO:
  -- the exact per-map hop tables must be measured on 237/234 first.
  --
  --   H.navTo(100,22,{arrive=function() return map()==237 end}),  -- 238->237
  --   ... walk 237 to {72,32} ...                                  -- 237->234
  --   bumpInto/ talk the impresario {15,46} -> rideScene until $0110==1
  --
  -- LEG 3-4: stage master, climb 233->231->239->232 (corridor tables TBD), then
  -- step {118,27} with $01B0&$01B4&$0387 -> _cab497 -> battle 134.  The
  -- $01B0/$01B4/$0387 trap mechanic is NOT decoded yet (see header) -- probe
  -- map 232 to learn what sets them before authoring this leg.
  --
  --   H.saveState("ultros2_doorstep.mss") -- one advance before battle 134
  -- ==========================================================================
  H.logStep(function()
    return string.format("gen_opera6_rafter: leg 1 done (ultros_dropped, $0058=1) at f%d; legs 2-4 UNVALIDATED (opera_dance_done unmintable -- sfigaro blocker)", H.frame)
  end),
})
