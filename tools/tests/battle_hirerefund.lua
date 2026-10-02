-- @suite slow
-- battle_hirerefund.lua -- a hire that finds no body standing charges
-- nothing (#319 review, 2026-10-02).  Hired Help at 3 BP is four hires,
-- one pass of the action each; when the hires before it have felled the
-- last body, a later pass has no target, and it must not take its fee.
--
-- Played, no writes: Continue the wor-tomb-v1 battery, walk Darill's Tomb's
-- east room into random battles, and play SETZER through the real menu
-- (H.setzerBattle): Defend twice (the bank to 3), then Hired Help at 3 BP,
-- battle after battle until one of them has more hires than bodies to take
-- them (at most four battles; a lone Mad Oscar of 2,900 HP falls to the
-- second hire at L31).  Every hire is held to the purse: the gil falls by
-- one fee (level x 50) for each hire that landed on a body (each landed
-- hire is a chip call on a monster) and by nothing for one that found none,
-- and TakeGil is reached once a landed hire.
-- Red before the fix: the fee was taken at every pass (build/attempts/wt/
-- kit-setzer/refund/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local HIRE = 0x5A

local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

local battles, short, held = 0, 0, 0

local function check(r)
  local fee = r.level * 50
  local landed = 0
  for _, c in ipairs(r.chips) do if c.y >= 8 then landed = landed + 1 end end
  local paid = r.gil0 - r.gil1
  H.log(string.format("[refund] Hired Help at %d BP, L%d: %d hire(s) paid for, %d landed, TakeGil x%d (%s), purse "
    .. "%d -> %d (paid %d)", r.boost, r.level, 1 + r.boost, landed, #r.costs, table.concat((function()
      local t = {} for _, c in ipairs(r.costs) do t[#t + 1] = c end return t end)(), "/"), r.gil0, r.gil1, paid))
  H.assertEq(landed >= 1, true, "a hire landed")
  H.assertEq(paid, fee * landed, string.format("the purse falls by one fee (%d) a landed hire (%d landed)", fee,
    landed))
  H.assertEq(#r.costs, landed, "TakeGil once a landed hire")
  held = held + 1
  if landed < 1 + r.boost then short = short + 1 end
end

H.run({ maxFrames = 220000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.driveUntil(function() return short >= 1 end, 200000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, string.format("a Hired Help outlived the bodies within four battles "
        .. "(%d held, none short)", held))
    end),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle({ { row = "defend" }, { row = "defend" }, { row = HIRE, boost = 3 } }, {})
        local r = step:tick()
        if r == "done" then
          for _, rec in ipairs(H.vars.setzer) do
            if rec.row == HIRE then check(rec) end
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "a Hired Help with more hires than bodies"),
  H.call(function()
    H.log(string.format("[refund] PASSED: %d Hired Help(s) held to the purse, %d with hires past the last body, "
      .. "over %d battle(s)", held, short, battles))
  end),
})
