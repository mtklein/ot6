-- probe_grind.lua -- INSTRUMENTATION (#132): first airship autopilot attempt.
-- Closed-loop on MEASURED velocity: thrust forward, and steer left/right to
-- align the measured movement vector with the bearing to the target tile.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function tileX() return ((rd(0x35) << 16) | H.readWord(0x33)) >> 12 end
local function tileY() return ((rd(0x39) << 16) | H.readWord(0x37)) >> 12 end
local TX, TY = 200, 100                  -- arbitrary target to prove convergence
local lx, ly = nil, nil
local function cross(ax, ay, bx, by) return ax * by - ay * bx end
H.run({ maxFrames = 12000 }, {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),
  H.pressButtons({ "a" }, 4), H.waitFrames(60),
  H.call(function()
    lx, ly = tileX(), tileY()
    H.log(string.format("aloft at (%d,%d), target (%d,%d)", lx, ly, TX, TY))
  end),
  H.driveUntil(function()
    local dx, dy = TX - tileX(), TY - tileY()
    return (dx * dx + dy * dy) <= 9          -- within 3 tiles
  end, 10000, {
    H.call(function()
      local x, y = tileX(), tileY()
      if H.frame % 120 == 0 then
        H.log(string.format("  f%d pos=(%d,%d) dist=%d hdg=%d", H.frame, x, y,
          math.floor(math.sqrt((TX-x)^2 + (TY-y)^2)), rd(0x73)))
      end
      -- steering: compare measured velocity to target bearing every frame
      local vx, vy = x - (lx or x), y - (ly or y)
      lx, ly = x, y
      local tvx, tvy = TX - x, TY - y
      local btn = { "a" }                    -- always thrust
      if (vx ~= 0 or vy ~= 0) then
        local c = cross(vx, vy, tvx, tvy)    -- >0: target is left of heading
        if c > 0 then btn[#btn+1] = "left"
        elseif c < 0 then btn[#btn+1] = "right" end
      else
        btn[#btn+1] = "left"                 -- not moving yet: rotate to build a vector
      end
      H.setPad(btn)
    end)
  }, "fly to (200,100)"),
  H.call(function()
    H.log(string.format("ARRIVED near target: pos=(%d,%d)", tileX(), tileY()))
  end),
  H.logStep(function() return "done" end),
})
