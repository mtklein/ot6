-- probe_cave_1640_stall.lua -- REPRODUCTION INSTRUMENT, temporary.
-- The flee-doctrine escape run parked at map 69 (16,40) for 20000 frames
-- with control lost, NO battle flag and NO dialog -- a different shape
-- from the map-87 park (which had a live battle).  The same tile hosted a
-- real battle in the tactical run, so the tile itself is fine.  This
-- replays from the freshly-generated sfigaro_escape (world map), crosses to
-- the cave, walks toward warp A, and dumps everything the moment control
-- goes away: field cells, world-module cells, the $3BF4 battle-HP words
-- battleLoadStarted() reads, the event PC, and screenshots.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/sfigaro_escape.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function dump(tag)
  local po = H.readWord(0x0803)
  local bhp = {}
  for i = 0, 3 do bhp[#bhp + 1] = string.format("%d", H.readWord(0x3BF4 + i * 2)) end
  H.log(string.format(
    "[%s] f%d map=%d field(%d,%d) world(%d,%d) worldMode=%s bright=%d | " ..
    "$1eb9=%02X $0084=%02X $0059=%02X mvType=%02X evPC=%02X%02X%02X " ..
    "$ba=%d $d3=%d | bhp=%s battLS=%s | ctl=%s wctl=%s algn=%s dlg=%s ev=%s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(),
    H.worldX() or -1, H.worldY() or -1, tostring(H.worldMode()), bright(),
    H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059),
    H.readByte(0x087c + po), H.readByte(0x00e7), H.readByte(0x00e6),
    H.readByte(0x00e5), H.readByte(0x00ba), H.readByte(0x00d3),
    table.concat(bhp, ","), tostring(H.battleLoadStarted()),
    tostring(H.hasControl()), tostring(H.worldHasControl()),
    tostring(H.tileAligned()), tostring(H.dialogWaiting()),
    tostring(H.eventRunning())))
end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function() dump("boot (sfigaro_escape)") end),
  H.worldNavTo(75, 102, { maxFrames = 45000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and map() == 69
    end), 12000, { playBattles = "flee" }),
    H.waitFrames(30),
  }),
  H.call(function() dump("cave landing") end),

  -- walk toward warp A's source (14,33), stopping on 30 lost frames
  (function()
    local lostN = 0
    local DP = { up = "up", down = "down", left = "left", right = "right",
      upleft = "left", upright = "right", downleft = "left", downright = "right" }
    return H.driveUntil(function()
      lostN = H.hasControl() and 0 or lostN + 1
      return lostN >= 30
    end, 20000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local p = H.bfsPath(14, 33)
        if p and #p > 0 then H.setPad({ [DP[p[1]]] = true })
        else H.setPad({}) end
      end),
    }, "walk toward (14,33) until control is lost")
  end)(),
  H.release(),
  H.call(function()
    dump("control lost 30")
    H.screenshot("cave_stall_t0")
  end),
  H.waitFrames(90),
  H.call(function() dump("t+90") H.screenshot("cave_stall_t90") end),
  H.waitFrames(210),
  H.call(function() dump("t+300") H.screenshot("cave_stall_t300") end),
  H.waitFrames(600),
  H.call(function() dump("t+900") H.screenshot("cave_stall_t900") end),
  -- hold L+R for a while (what the flee branch would do if it saw a battle)
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      return H.hasControl() or n >= 600
    end, 700, {
      H.call(function() H.setPad({ l = true, r = true }) end),
    }, "hold L+R against the stall")
  end)(),
  H.release(),
  H.call(function() dump("after L+R") H.screenshot("cave_stall_lr") end),
  -- then edge-tap A
  (function()
    local ph, n = 0, 0
    return H.driveUntil(function()
      n = n + 1
      return H.hasControl() or n >= 900
    end, 1000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "edge-tap A against the stall")
  end)(),
  H.release(),
  H.call(function() dump("after A taps") H.screenshot("cave_stall_a") end),
})
