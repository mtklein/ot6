-- probe_grind.lua -- INSTRUMENTATION (#132): airship autopilot v2.
-- Wrap-aware (256x256 world), and steers in cycles: each ~16f cycle, measure
-- the velocity over the last cycle, compare to the wrap-aware bearing to the
-- target, and rotate a short burst only if misaligned; thrust every frame.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function tileX() return (((rd(0x35) << 16) | H.readWord(0x33)) >> 12) & 0xFF end
local function tileY() return (((rd(0x39) << 16) | H.readWord(0x37)) >> 12) & 0xFF end
local function wrap(d) d = d % 256; if d > 128 then d = d - 256 end; return d end
local TX, TY = 200, 100
local px, py = nil, nil        -- pos at last cycle start
local turn = nil               -- current burst decision
H.run({ maxFrames = 14000 }, {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),
  H.pressButtons({ "a" }, 4), H.waitFrames(60),
  H.call(function() px, py = tileX(), tileY()
    H.log(string.format("aloft (%d,%d) -> target (%d,%d)", px, py, TX, TY)) end),
  H.driveUntil(function()
    local dx, dy = wrap(TX - tileX()), wrap(TY - tileY())
    return (dx * dx + dy * dy) <= 16
  end, 12000, {
    H.call(function()
      local x, y = tileX(), tileY()
      local ph = H.frame % 16
      if ph == 0 then
        local vx, vy = wrap(x - px), wrap(y - py)     -- velocity over last cycle
        local tx, ty = wrap(TX - x), wrap(TY - y)     -- bearing to target
        px, py = x, y
        if H.frame % 96 == 0 then
          H.log(string.format("  f%d pos=(%d,%d) dist=%d v=(%d,%d)", H.frame, x, y,
            math.floor(math.sqrt(tx*tx + ty*ty)), vx, vy))
        end
        local speed = math.sqrt(vx*vx + vy*vy)
        if speed < 0.5 then turn = "left"             -- not moving: build a vector
        else
          local cross = vx * ty - vy * tx             -- >0: target left of heading
          local dot = vx * tx + vy * ty               -- <0: target behind
          local mag = speed * math.sqrt(tx*tx + ty*ty)
          if mag > 0 and (dot / mag) > 0.94 then turn = nil   -- aligned (<~20deg): coast
          elseif cross > 0 then turn = "left" else turn = "right" end
        end
      end
      local btn = { "a" }
      if turn and ph < 4 then btn[#btn+1] = turn      -- short steer burst per cycle
      end
      H.setPad(btn)
    end)
  }, "autopilot -> (200,100)"),
  H.call(function() H.log(string.format("ARRIVED (%d,%d)", tileX(), tileY())) end),
  H.logStep(function() return "done" end),
})
