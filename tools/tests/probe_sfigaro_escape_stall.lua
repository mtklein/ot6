-- probe_sfigaro_escape_stall.lua -- replays the map 87 (57,48) -> map 86
-- (49,31) crossing and dumps every control-gate cell hasControl() reads,
-- the event PC, the dialog/choice cells, and the whole object table, plus
-- screenshots.  Map 87 has no event triggers and no NPCs in the tables.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/celes_freed.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function seq(steps) return H.cond(function() return true end, steps) end
local FACE = { up = 0, right = 1, down = 2, left = 3 }

local function dump(tag)
  local po = H.readWord(0x0803)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) bright=%d | $1eb9=%02X $0084=%02X $0059=%02X " ..
    "mvType=%02X evPC=%02X%02X%02X $ba=%d $d3=%d $056e=%d $056f=%d " ..
    "ctl=%s algn=%s dlg=%s ev=%s batt=%s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059),
    H.readByte(0x087c + po), H.readByte(0x00e7), H.readByte(0x00e6),
    H.readByte(0x00e5), H.readByte(0x00ba), H.readByte(0x00d3),
    H.readByte(0x056e), H.readByte(0x056f),
    tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.dialogWaiting()), tostring(H.eventRunning()),
    tostring(H.battleLoadStarted())))
  local objs = {}
  for i = 0, 31 do
    local x = H.readWord(0x086a + 0x29 * i) >> 4
    local y = H.readWord(0x086d + 0x29 * i) >> 4
    local live = H.readByte(0x0868 + 0x29 * i)
    objs[#objs + 1] = string.format("%d:(%d,%d,%02X)", i, x, y, live)
  end
  H.log("[" .. tag .. "] objs " .. table.concat(objs, " "))
end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end

local function go(sx, sy, dm, dx, dy, what)
  local startMap
  local function arrived()
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  return seq({
    H.call(function() startMap = map() end),
    H.navTo(sx, sy, { maxFrames = 20000, arrive = arrived, playBattles = true }),
    H.release(),
    settleField(dm),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on map " .. dm)
    end),
  })
end

local function hop(tx, ty, what)
  return seq({
    H.navTo(tx, ty, { maxFrames = 12000, playBattles = true }),
    H.release(),
  })
end

local function windClock()
  local ph = 0
  return seq({
    hop(18, 49, "onto the clock trigger (18,49)"),
    H.driveUntil(function() return sw(0x010D) == 1 end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if facing() ~= FACE.up then H.setPad({ up = true }); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "wind the clock ($010D)"),
    H.release(),
    settleField(84),
  })
end

H.run({ maxFrames = 80000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function() dump("boot") end),
  go(57, 13, 83, 35, 14, "celes room -> corridor"),
  go(45, 12, 84, 8, 57, "corridor -> map 84"),
  windClock(),
  go(15, 51, 87, 20, 33, "clock passage -> map 87"),
  H.call(function() dump("map 87 landing") end),

  -- Walk toward (57,48) the way navTo would, but stop as soon as control
  -- goes away for 30 consecutive frames, then observe without touching
  -- the pad.
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
        local p = H.bfsPath(57, 48)
        if p and #p > 0 then H.setPad({ [DP[p[1]]] = true })
        else H.setPad({}) end
      end),
    }, "walk toward (57,48) until control is lost")
  end)(),
  H.release(),
  H.call(function()
    dump("control lost 30 frames")
    H.screenshot("stall_t0")
  end),
  H.waitFrames(120),
  H.call(function()
    dump("t+120")
    H.screenshot("stall_t120")
  end),
  H.waitFrames(300),
  H.call(function()
    dump("t+420")
    H.screenshot("stall_t420")
  end),
  H.waitFrames(600),
  H.call(function()
    dump("t+1020")
    H.screenshot("stall_t1020")
  end),
  -- test whether an A press clears it: tap A for a while, then dump again.
  (function()
    local ph, waited = 0, 0
    return H.driveUntil(function()
      waited = waited + 1
      return H.hasControl() or waited >= 1100
    end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "try edge-tapped A against the stall")
  end)(),
  H.release(),
  H.call(function()
    dump("after A taps")
    H.screenshot("stall_after_a")
  end),
})
