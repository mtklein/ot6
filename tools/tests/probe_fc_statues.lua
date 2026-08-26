-- probe_fc_statues.lua -- from fc_atma_down (60,16, AtmaWeapon just
-- fell), heal up, walk the spine north onto the (60,11) trigger, absorb
-- the statue cutscene, and land on the escape map 393 at (67,16).  Banks
-- fc_escape_start.mss right after Shadow's "Get outta here" dialog --
-- the 6:00 master clock and the 5:55 Shadow timer start at that dialog,
-- and they run during menus and battles, so all healing happens back on
-- 394 before the trigger.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local FA = H.newFightDriver("spine", { tactical = true, boost = true, bank = 3,
  items = true, healPercent = 60, magic = { [0x07] = { spell = 2 } } })
H.run({ maxFrames = 80000 }, {
  H.loadState("build/states/fc_atma_down.mss.lua"),
  H.waitFrames(60),
  H.fieldCare({ tag = "post-atma", threshold = 0.95 }),
  H.release(),
  H.waitFrames(30),
  -- north up the stair spine onto the statue trigger; stall rotation
  -- because y12-14 are prop-3 stairs that only move on diagonal input
  (function()
    local wps = { {60,14}, {60,12}, {60,11} }
    local wi, t, wt = 1, 0, 0
    local lastK, lastT = -1, 0
    return H.driveUntil(function()
      t = t + 1
      return mapIs(393)
    end, 60000, {
      H.call(function()
        if t % 2400 == 0 then
          H.log(string.format("  [spine] t=%d map=%d (%d,%d) wp=%d", t,
            H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), wi))
        end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          -- no known choice in the statue scene; take the first row
          H.setPad(t % 24 < 3 and { "a" } or {})
          return
        end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if not H.hasControl() then H.setPad({}); return end
        local wp = wps[wi]
        if not wp then H.setPad({}); return end
        local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
        wt = wt + 1
        if (dx == 0 and dy == 0) or wt > 700 then
          wi, wt = wi + 1, 0
          H.setPad({})
          return
        end
        local px = dx > 0 and "right" or "left"
        local py = dy > 0 and "down" or "up"
        local k = H.fieldX() * 256 + H.fieldY()
        if k ~= lastK then lastK, lastT = k, t end
        if t - lastT > 240 then
          local alts = dy ~= 0
            and { { [py] = true, left = true }, { [py] = true, right = true },
                  { [py] = true }, { left = true }, { right = true } }
            or { { [px] = true, up = true }, { [px] = true, down = true },
                  { [px] = true }, { up = true }, { down = true } }
          H.setPad(alts[(math.floor(t / 36) % #alts) + 1])
          return
        end
        H.setPad(math.abs(dx) >= math.abs(dy) and { [px] = true }
                                              or { [py] = true })
      end),
    }, "statue scene -> map 393")
  end)(),
  -- absorb Shadow's dialog; the timers start when it closes.  settle
  -- until control holds.
  (function()
    local t, calm = 0, 0
    return H.driveUntil(function()
      t = t + 1
      if not H.hasControl() or H.dialogWaiting() then calm = 0
      else calm = calm + 1 end
      return t >= 9000 or calm >= 180
    end, 9500, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "escape start settled")
  end)(),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp+1] = H.charHp(c) end
    H.log(string.format("escape start: map=%d (%d,%d) hp=%s escape-sw=%d",
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), table.concat(hp, "/"),
      (H.readByte(0x1ED7) >> 4) & 1))
    H.screenshot("escape_start")
    H.assertEq(mapIs(393), true, "on the escape map")
  end),
  H.saveState("fc_escape_start.mss"),
  H.logStep(function() return "done" end),
})
