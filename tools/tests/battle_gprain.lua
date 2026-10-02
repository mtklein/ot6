-- @suite slow
-- battle_gprain.lua -- the Coin Toss relic's GP Rain since #319: Slot gives
-- way to GP Rain (no table), and its coins are now special (one chip on a
-- special-weak body) and boostable (the boost doubles the coins, as Coin
-- Toss's does; before, GP Rain's boost bought nothing, because Ot6BoostDmg's
-- multiplier runs in CalcDmg and GP Rain's effect overwrites the damage).
--
-- Played, no writes: Continue the wor-tomb-v1 battery, put the bag's Coin
-- Toss relic on SETZER through the Relic menu (H.equipKit), walk Darill's
-- Tomb's east room into a random battle, and throw GP Rain from the command
-- row (H.setzerBattle's `cmd` entries) at 1 BP and unboosted, as many
-- battles as the draws take (at most four).  Per throw (Cmd_18's entry and
-- SETZER's Ot6ActionEnd): the command list holds GP Rain and no Slot; the
-- gil is level x 30 x 2^boost and the purse falls by it; the damage is twice
-- that over the targets, halved while a body's shields hold, doubled once
-- Broken, capped at 9,999 and the HP; every chip call carries special ($08)
-- and a special-weak shielded body loses one shield.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local SETZER, COIN_TOSS_RELIC = 9, 0xD6

local function bits(m) local n = 0; while m > 0 do n = n + (m & 1); m = m >> 1 end; return n end

local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

local function checkRain(r, i)
  local want = r.level * 30 * (1 << r.boost)
  H.log(string.format("[gprain] rain %d at %d BP, L%d: TakeGil %s, purse %d -> %d, targets $%02X", i, r.boost,
    r.level, tostring(r.cost), r.gil0, r.gil1, r.targets))
  H.assertEq(r.cost, want, string.format("rain %d: the gil thrown is level x 30 x 2^boost", i))
  H.assertEq(r.gil0 - r.gil1, want, string.format("rain %d: the purse falls by that", i))
  local n = bits(r.targets)
  for _, c in ipairs(r.chips) do
    if c.y >= 8 then H.assertEq(c.class, 0x08, string.format("rain %d: the coins are special", i)) end
  end
  for s = 0, 5 do
    if (r.targets >> s) & 1 == 1 then
      local o, m = r.mon0[s], r.mon1[s]
      local d = (2 * want) // n
      local sh = o.sh
      local chip = o.sh > 0 and o.brk == 0 and (o.cls & 0x08) ~= 0
      if chip then sh = sh - 1 end
      if o.brk == 0 and sh > 0 then d = (d * 8) >> 4
      elseif (o.brk ~= 0 or (chip and sh == 0)) and d < 32768 then d = d * 2 end
      d = math.min(d, 9999, o.hp)
      H.log(string.format("[gprain]   slot %d: HP %d -> %d (want -%d), shields %d -> %d (row $%02X)", s, o.hp, m.hp,
        d, o.sh, m.sh, o.cls))
      H.assertEq(o.hp - m.hp, d, string.format("rain %d: slot %d's share of the coins", i, s))
      if not (chip and sh == 0) then
        H.assertEq(o.sh - m.sh, chip and 1 or 0, string.format("rain %d: slot %d's shields", i, s))
      end
    end
  end
end

local WANT = { { cmd = 0x18, boost = 1 }, { cmd = 0x18, boost = 0 } }
local done, battles = {}, 0
local function remaining()
  local t = {}
  for i = #done + 1, #WANT do t[#t + 1] = WANT[i] end
  return t
end

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    H.assertEq(H.invCountOf(COIN_TOSS_RELIC) > 0, true, "the bag holds the Coin Toss relic")
  end),
  H.equipKit(SETZER, { { 4, COIN_TOSS_RELIC } }, { tag = "the Coin Toss relic on SETZER" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * SETZER + 0x23), COIN_TOSS_RELIC, "SETZER wears the Coin Toss relic")
  end),
  H.driveUntil(function() return #done >= #WANT end, 160000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, "both throws within four battles")
    end),
    walkToBattle(),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    H.call(function()
      local slot = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == SETZER then slot = s end end
      H.assertEq(slot ~= nil, true, "SETZER is seated")
      local cmds = {}
      for r = 0, 3 do cmds[#cmds + 1] = H.readByte(0x202E + slot * 12 + r * 3) end
      local rain, slotCmd = false, false
      for _, c in ipairs(cmds) do if c == 0x18 then rain = true elseif c == 0x0F then slotCmd = true end end
      H.log(string.format("[gprain] SETZER's commands: $%02X $%02X $%02X $%02X", cmds[1], cmds[2], cmds[3], cmds[4]))
      H.assertEq(rain, true, "the relic gives SETZER GP Rain")
      H.assertEq(slotCmd, false, "in place of Slot")
    end),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(remaining(), {})
        local r = step:tick()
        if r == "done" then
          for _, rec in ipairs(H.vars.setzer) do done[#done + 1] = rec end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "both GP Rains resolve"),
  H.call(function()
    H.assertEq(#done, #WANT, "two GP Rains resolved")
    for i, r in ipairs(done) do
      H.assertEq(r.row, 0x18, string.format("record %d is a GP Rain", i))
      H.assertEq(r.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
      checkRain(r, i)
    end
    H.log(string.format("[gprain] PASSED: %d GP Rains over %d battle(s)", #done, battles))
  end),
})
