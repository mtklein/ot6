-- probe_rafterlab_catwalk_fast.lua -- rafter lab: the config-tuned twin of
-- probe_rafterlab_catwalk.lua.
--
-- Boots build/states/rafterlab_dropped.mss (map 238 stage, envelope
-- touched, chase timer NOT armed -- the menu is safe here), drives the
-- Config menu to Battle Speed 1 / Message Speed 1 ($1d4d bits 0-2 and 4-6
-- to 0; input-driven, verified by probe_rafterlab_cfgexplore.lua: config
-- state $26=0x0E, Bat.Speed row $4b=1, Msg.Speed row $4b=2, LEFT
-- decreases), then replays gen_opera6_rafter.lua's briefing + approach
-- and banks rafterlab_catwalk_fast.mss on the catwalk with the clock
-- live.  Crossing experiments on this fixture measure what the two
-- sliders are worth per fight.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function ratLine()
  local t = {}
  for k = 0, 4 do
    local obj = 24 + k
    local ox = H.readWord(0x086a + 0x29 * obj) >> 4
    local oy = H.readWord(0x086d + 0x29 * obj) >> 4
    t[#t + 1] = string.format("%d%s@(%d,%d)", k,
      sw(0x034C + k) == 1 and "+" or "-", ox, oy)
  end
  return table.concat(t, " ")
end

local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly = 0, 0, -1, -1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=180 then H.setPad(aPh<4 and {"a"} or {}); return end
      H.setPad({})
    end) }, what)
end

local function toDoor(tx,ty,bumpDir,destMap,what)
  return H.cond(function() return true end, {
    H.navTo(tx,ty,{maxFrames=18000,playBattles=true,arrive=function() return map()==destMap end}),
    (function() local n=0 return H.driveUntil(function() return map()==destMap end,3000,{
      H.call(function()
        n=n+1
        if H.dialogWaiting() then H.setPad(n%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(n%16<10 and {[bumpDir]=true} or {})
      end)
    },what) end)(),
    H.waitUntil(function() return map()==destMap and settled() end,3000,what.." settled",5),
  })
end

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/rafterlab_dropped.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 238, "dropped state boots on the stage (map 238)")
    H.assertEq(sw(0x0058), 1, "$0058 SET -- Ultros has threatened the opera")
    H.assertEq(sw(0x0110), 0, "$0110 CLEAR -- the rafter timer is NOT armed (menu safe)")
    H.log(string.format("[lab] boot $1d4d=%02X", H.readByte(0x1d4d)))
  end),

  -- Config: Battle Speed 1, Message Speed 1.
  H.driveUntil(function() return H.readByte(0x26) == 0x05 end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "open main menu"),
  H.waitFrames(20),
  H.driveUntil(function()
    return H.readByte(0x26) == 0x05 and H.readByte(0x4b) == 5
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
    "cursor to Config row"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return H.readByte(0x26) == 0x0E end, 300, "Config screen", 5),
  H.waitFrames(10),
  H.driveUntil(function()
    return H.readByte(0x26) == 0x0E and H.readByte(0x4b) == 1
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
    "cursor on Bat.Speed"),
  H.driveUntil(function() return (H.readByte(0x1d4d) & 0x07) == 0 end, 600,
    { H.pressButtons({ "left" }, 2), H.waitFrames(8) }, "Bat.Speed to 1"),
  H.driveUntil(function()
    return H.readByte(0x26) == 0x0E and H.readByte(0x4b) == 2
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
    "cursor on Msg.Speed"),
  H.driveUntil(function() return (H.readByte(0x1d4d) & 0x70) == 0 end, 600,
    { H.pressButtons({ "left" }, 2), H.waitFrames(8) }, "Msg.Speed to 1"),
  H.driveUntil(function() return H.hasControl() end, 1200,
    { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, "back out of the menu"),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.readByte(0x1d4d), 0x00,
      "$1d4d == 00: Battle Speed 1, Msg Speed 1, Active, defaults elsewhere")
  end),

  -- Briefing chain, verbatim from gen_opera6_rafter.lua.
  toDoor(100,23,"down",237,"stage -> opera house"),
  H.navTo(72,30,{maxFrames=12000,playBattles=true,arrive=function() return map()==233 end}),
  H.waitUntil(function() return map()==233 and settled() end,3000,"active theater settled",5),
  H.navTo(15,45,{maxFrames=12000,playBattles=true}),
  (function() local n=0 return H.driveUntil(function()
    return sw(0x0110)==1 or H.dialogWaiting()
  end,3000,{H.call(function()
    n=n+1
    H.setPad(n%12<6 and {"down","a"} or {})
  end)},"talk active-opera impresario") end)(),
  rideScene(function() return sw(0x0110)==1 and map()==231 and settled() end,18000,
    "ride the 5-minute briefing"),
  H.call(function()
    H.assertEq(map(),231,"briefing lands in the active theater (231)")
    H.assertEq(sw(0x0110),1,"$0110 SET -- rafter timer armed")
    H.log(string.format("[lab] briefed, timer=%d", H.readWord(0x1189)))
  end),

  -- The approach, verbatim from gen_opera6_rafter.lua.
  H.navTo(28,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"right room",3),
  H.driveUntil(function() return H.fieldY()==35 end,300,{H.hold({"up"})},"leave right landing"),
  H.driveUntil(function() return H.fieldY()==34 end,300,{H.hold({"up"})},"right stair 1"),
  H.driveUntil(function() return H.fieldX()==113 end,300,{H.hold({"left"})},"right stair 2"),
  H.driveUntil(function() return H.fieldY()==32 end,500,{H.hold({"up"})},"right stair 3"),
  H.driveUntil(function() return H.fieldX()==114 end,300,{H.hold({"right"})},"right stair 4"),
  H.driveUntil(function() return H.fieldX()>=117 and H.fieldY()<=29 end,800,{
    H.call(function()
      if H.dialogWaiting() then H.setPad({"a"})
      elseif H.hasControl() then H.setPad({"up","right"})
      else H.setPad({}) end
    end)},"reach stage master"),
  H.driveUntil(function() return sw(0x01B4)==1 end,1000,{
    H.call(function() H.setPad({"right","a"}) end)},"talk stage master"),
  H.navTo(120,28,{maxFrames=1500,playBattles=true}),
  H.driveUntil(function() return sw(0x0355)==0 end,500,{
    H.call(function() H.setPad({"up","a"}) end)},"operate far-right switch"),
  H.navTo(114,37,{maxFrames=3000,playBattles=true,arrive=function() return map()==231 end}),
  H.waitUntil(function() return map()==231 and settled() end,1000,"return theater",3),
  H.navTo(28,27,{maxFrames=500,playBattles=true}),
  H.navTo(4,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"left room",3),
  H.driveUntil(function() return H.fieldY()==13 end,500,{H.hold({"up"})},"leave left landing"),
  H.navTo(117,5,{maxFrames=2500,playBattles=true}),
  H.navTo(117,3,{maxFrames=6000,playBattles=true,arrive=function() return map()==235 end}),
  H.waitUntil(function() return map()==235 and settled() end,1500,"framework",3),
  H.navTo(6,16,{maxFrames=30000,playBattles=true}),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()<=10 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({up=true}) end) }, "climb framework") end)(),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()>=11 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({down=true}) end) }, "step onto rafters") end)(),
  H.waitUntil(function() return settled() end, 1500, "catwalk settled", 3),

  H.call(function()
    H.assertEq(H.readByte(0x1d4d), 0x00, "config survived to the catwalk")
    H.log(string.format("[lab] CATWALK-FAST map=%d (%d,%d) z=%d timer=%d rats: %s",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
      H.readWord(0x1189), ratLine()))
  end),
  H.saveState("rafterlab_catwalk_fast.mss"),
  H.logStep(function()
    return string.format("probe_rafterlab_catwalk_fast: banked the fast catwalk fixture at f%d, timer=%d",
      H.frame, H.readWord(0x1189))
  end),
})
