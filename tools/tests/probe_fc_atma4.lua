-- probe_fc_atma4.lua -- the south route back to (60,16), one tile below
-- AtmaWeapon's NPC at (60,15), then diagnostics and a doorstep state
-- bank: party z ($b2), the props at (60,15)/(60,16), the NPC-block bits,
-- and the $035F switch.  It PASSES on reaching the doorstep -- the talk
-- attempt at the end is best-effort telemetry, not the goal.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local MAG = { [0x07] = { spell = 2, boost = false } }
local FA = H.newFightDriver("atma", { tactical = true, boost = true, bank = 3,
  items = true, healPercent = 60, magic = { [0x07] = { spell = 2 } } })
local function leg(x, y)
  return H.navTo(x, y, { maxFrames = 30000, playBattles = "tactical",
    magic = MAG })
end
local function ride(x, y, tag)
  local near = false
  return H.cond(function() return true end, {
    H.navTo(x, y, { maxFrames = 15000, playBattles = "tactical",
      magic = MAG,
      arrive = function()
        if H.fieldX() == x and H.fieldY() == y then near = true end
        return near
      end }),
    -- absorb: hold NOTHING until the scripted ride fully settles
    (function()
      local t, calm = 0, 0
      return H.driveUntil(function()
        t = t + 1
        if not H.hasControl() or H.dialogWaiting() then calm = 0
        else calm = calm + 1 end
        return t >= 2400 or calm >= 180
      end, 3000, {
        H.call(function()
          if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
          else H.setPad({}) end
        end),
      }, tag .. " absorbed")
    end)(),
    H.call(function()
      H.log(string.format("[%s] landed (%d,%d)", tag, H.fieldX(), H.fieldY()))
    end),
  }, {})
end
local function blind(wps, pred, cap, tag)
  local wi, t, wt = 1, 0, 0
  return H.driveUntil(function()
    t = t + 1
    return t >= cap or pred()
  end, cap + 500, {
    H.call(function()
      if t % 1200 == 0 then
        H.log(string.format("  [%s] t=%d (%d,%d) wp=%d", tag, t,
          H.fieldX(), H.fieldY(), wi))
      end
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
      if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
      -- NO hasControl gate: ladder tiles report control=false while
      -- climbing and need the direction HELD to continue
      local wp = wps[wi]
      if not wp then H.setPad({}); return end
      local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
      wt = wt + 1
      if (dx == 0 and dy == 0) or wt > 700 then
        wi, wt = wi + 1, 0
        H.setPad({})
        return
      end
      local d = math.abs(dx) >= math.abs(dy)
        and (dx > 0 and "right" or "left")
        or (dy > 0 and "down" or "up")
      H.setPad({ [d] = true })
    end),
  }, tag)
end
H.run({ maxFrames = 150000 }, {
  H.loadState("build/states/fc_shadow.mss.lua"),
  H.waitFrames(60),
  leg(19, 12), leg(25, 19), leg(40, 12),
  ride(40, 6, "chute 40,6"),
  leg(36, 28),
  ride(67, 39, "walk-pair 67,39"),
  ride(40, 24, "tunnel 40,24"),
  ride(59, 39, "reveal 59,39"),
  ride(52, 24, "reveal 52,24"),
  leg(82, 30),
  ride(89, 25, "tunnel 89,25"),
  -- y29 corridor + ladder + spine, all blind (bfs-dark territory)
  blind({ {70,29},{64,29},{63,29},{63,28},{63,25},{63,24},
          {62,24},{62,23},{60,23},{60,16} },
    function() return H.fieldX() == 60 and H.fieldY() <= 17 end,
    12000, "corridor-ladder-spine"),
  H.release(),
  H.waitFrames(120),
  H.call(function()
    local xm = H.readByte(0x0086)
    local function tl(x, y)
      return H.readByte(0x7F0000 + (y & H.readByte(0x0087)) * 256 + (x & xm))
    end
    local function p1(x, y) return H.readByte(0x7E7600 + tl(x, y)) end
    local function p2(x, y) return H.readByte(0x7E7700 + tl(x, y)) end
    local function blk(x, y)
      return H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF))
    end
    H.log(string.format("doorstep (%d,%d) z=%02X atma-sw=%d",
      H.fieldX(), H.fieldY(), H.readByte(0xb2),
      (H.readByte(0x1EEB) >> 7) & 1))
    for y = 13, 17 do
      H.log(string.format("  (60,%d) p1=%02X p2=%02X blk=%02X",
        y, p1(60, y), p2(60, y), blk(60, y)))
    end
    H.screenshot("atma_door")
  end),
  H.saveState("fc_atma_door.mss"),
  -- best-effort talk: tap-to-face then edge A, no held direction
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return t >= 4000 or H.dialogWaiting() or H.battleActive()
        or H.battleLoadStarted()
    end, 4500, {
      H.call(function()
        local c = t % 48
        if c < 4 then H.setPad({ up = true })
        elseif c >= 24 and c < 28 then H.setPad({ a = true })
        else H.setPad({}) end
      end),
    }, "talk attempt")
  end)(),
  H.call(function()
    H.log(string.format("talk result: dlg=%s battle=%s|%s at (%d,%d)",
      tostring(H.dialogWaiting()), tostring(H.battleActive()),
      tostring(H.battleLoadStarted()), H.fieldX(), H.fieldY()))
    H.assertEq(mapIs(394), true, "still on 394")
    H.assertEq(H.fieldX(), 60, "at the doorstep column")
  end),
  H.logStep(function() return "done" end),
})
