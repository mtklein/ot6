-- probe_rafterlab_catwalk.lua -- rafter-crossing lab, fixture half.
--
-- Hand-run instrument (probe_): boots build/states/rafterlab_briefing.mss
-- (a byte-identical retained artifact from the 2026-08-26 ultros2_entry
-- runs: the briefing is done, $0110 armed, map 231), replays the approach
-- from gen_opera6_rafter.lua verbatim, and banks rafterlab_catwalk.mss on
-- the catwalk tile with the chase clock live.  Crossing experiments boot
-- that state so one experiment costs seconds, not a full replay -- the
-- iteration loop the KNOWN BROKEN header asked for.
--
-- Also logs the lab's ground truth: the passability byte and object-map
-- bit for the rafter region, the rat line, and the clock, so strategy
-- work can reason about chokepoints offline.

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

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/rafterlab_briefing.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 231, "briefing state boots in the active theater (231)")
    H.assertEq(sw(0x0110), 1, "$0110 SET -- rafter timer armed")
    H.log(string.format("[lab] boot map=%d (%d,%d) timer=%d",
      map(), H.fieldX(), H.fieldY(), H.readWord(0x1189)))
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
  H.call(function() H.log("[lab] on 235: " .. ratLine()) end),
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

  -- Ground truth for the lab notebook.
  H.call(function()
    H.log(string.format("[lab] CATWALK map=%d (%d,%d) z=%d timer=%d rats: %s",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
      H.readWord(0x1189), ratLine()))
    -- Passability dump of the rafter region: per tile, the p1 prop byte
    -- low bits decide walkability (0x07==0x07 is a wall) and the object
    -- map bit 0x80 clear means an object stands there.  '.' = open,
    -- '#' = wall-ish, 'o' = object standing on an open tile.
    for y = 0, 20 do
      local row = {}
      for x = 0, 25 do
        local p1 = H.readByte(0x7E7600 + H.maptile(x, y))
        local obj = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
        local ch
        if (p1 & 0x07) == 0x07 then ch = "#"
        elseif (p1 & 0x03) == 0 then ch = "^"   -- not walkable at either z
        else ch = obj and "o" or "." end
        row[#row + 1] = ch
      end
      H.log(string.format("[grid] y=%02d %s", y, table.concat(row)))
    end
    -- and the raw p1 bytes, for offline BFS reconstruction
    for y = 0, 20 do
      local row = {}
      for x = 0, 25 do
        row[#row + 1] = string.format("%02X", H.readByte(0x7E7600 + H.maptile(x, y)))
      end
      H.log(string.format("[p1] y=%02d %s", y, table.concat(row, " ")))
    end
  end),
  H.saveState("rafterlab_catwalk.mss"),
  H.logStep(function()
    return string.format("probe_rafterlab_catwalk: banked the catwalk lab fixture at f%d, timer=%d",
      H.frame, H.readWord(0x1189))
  end),
})
