-- probe_fc_exit.lua -- what the BFS sees right after the alcove's scripted
-- exit puts the party on 394 at (90,42): position/$b2 over time, the tile
-- props and object map around the tile, and path verdicts at several settle
-- times and after one real step.  Both the deck re-entry and this exit
-- left navTo with "no path" to anything; measure before theorizing.
-- A probe: reads and presses only.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local function verdicts(tag)
  local function v(x, y) return H.bfsPath(x, y) and "path" or "NO" end
  H.log(string.format("[exit %s] f%d map=%d at (%d,%d) $b2=%02X ctrl=%s aligned=%s | (89,25) %s (82,30) %s (63,28) %s (90,44) %s (90,40) %s",
    tag, H.frame, H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), H.readByte(0x00b2), tostring(H.hasControl()), tostring(H.tileAligned()),
    v(89, 25), v(82, 30), v(63, 28), v(90, 44), v(90, 40)))
end
local function dumpArea(tag, x0, y0, x1, y1)
  for y = y0, y1 do
    local row = {}
    for x = x0, x1 do
      local t = H.maptile(x, y)
      row[#row + 1] = string.format("%02X/%02X/%02X", H.readByte(0x7E7600 + t), H.readByte(0x7E7700 + t), H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)))
    end
    H.log(string.format("[exit %s] y=%2d: %s", tag, y, table.concat(row, " ")))
  end
end
local t = 0
H.run({ maxFrames = 20000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return mapIs(358) and H.hasControl() end, 3000, "cold Continue to the alcove", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.navTo(8, 9, { maxFrames = 3000, playBattles = "tactical", healer = 0 }),
  H.driveUntil(function() t = t + 1; return mapIs(394) end, 1800, {
    H.call(function()
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ up = true })
    end),
  }, "up through (8,8) -> 394"),
  H.release(),
  H.call(function() verdicts("t+0") end),
  H.waitFrames(60),  H.call(function() verdicts("t+60") end),
  H.waitUntil(function() return H.hasControl() and bright() >= 15 end, 900, "control + fade-in", 10),
  H.call(function() verdicts("control") end),
  H.waitFrames(120),
  H.call(function()
    verdicts("t+control+120")
    local function v(x, y) return H.bfsPath(x, y) and "path" or "NO" end
    H.log(string.format("[exit probe] from (90,42): (90,38) %s (90,36) %s (88,33) %s (86,30) %s (84,28) %s (86,26) %s (88,26) %s",
      v(90, 38), v(90, 36), v(88, 33), v(86, 30), v(84, 28), v(86, 26), v(88, 26)))
    dumpArea("area", 80, 24, 92, 34)
  end),
  -- walk to (82,30) (reachable), then hold directions toward (89,25) the way
  -- the descent's burst did, logging where the party actually goes
  H.navTo(82, 30, { maxFrames = 6000, playBattles = "tactical", healer = 0 }),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "NO" end
    H.log(string.format("[exit probe] at (%d,%d): (89,25) %s (88,26) %s (86,26) %s (84,28) %s", H.fieldX(), H.fieldY(), v(89, 25), v(88, 26), v(86, 26), v(84, 28)))
  end),
  (function()
    local t, last = 0, ""
    return H.driveUntil(function()
      t = t + 1
      return (H.fieldX() == 89 and H.fieldY() == 25) or t > 1500
    end, 1600, {
      H.call(function()
        if not H.hasControl() then H.setPad({}); return end
        local dx, dy = 89 - H.fieldX(), 25 - H.fieldY()
        local d = (t % 200 < 100) and ((math.abs(dx) >= math.abs(dy)) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up"))
                                   or ((math.abs(dx) < math.abs(dy)) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up"))
        H.setPad({ [d] = true })
        local pos = string.format("(%d,%d) $b2=%02X", H.fieldX(), H.fieldY(), H.readByte(0x00b2))
        if pos ~= last then H.log("[exit probe] raw walk: " .. pos); last = pos end
      end),
    }, "raw walk toward (89,25)")
  end)(),
  H.release(),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "NO" end
    H.log(string.format("[exit probe] raw walk ended at (%d,%d) $b2=%02X: (89,25) %s (70,25) %s", H.fieldX(), H.fieldY(), H.readByte(0x00b2), v(89, 25), v(70, 25)))
  end),
})
