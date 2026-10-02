-- @suite slow
-- battle_gprain.lua -- the Coin Toss relic's GP Rain since #319: Slot gives
-- way to GP Rain (no table), and its coins are now special (one chip on a
-- special-weak body) and boostable (the boost buys another toss a point, as
-- Coin Toss's does; before, GP Rain's boost bought nothing, because
-- Ot6BoostDmg's multiplier runs in CalcDmg and GP Rain's effect overwrites
-- the damage).
--
-- Played, no writes: Continue the wor-tomb-v1 battery, put the bag's Coin
-- Toss relic on SETZER through the Relic menu (H.equipKit), walk Darill's
-- Tomb's east room into random battles, and throw GP Rain from the command
-- row (H.setzerBattle's `cmd` entries) at 1 BP and unboosted in the first
-- battles that deal a crowd (two or more monsters, one special-weak:
-- crowdHere; the rest are fought out with the free Fight), at most eight
-- battles, so a toss splits across bodies and chips the special-weak one
-- (asserted: coverage).  Per throw (Cmd_18's entry and
-- SETZER's Ot6ActionEnd): the command list holds GP Rain and no Slot; 1 +
-- boost tosses, each that finds a body paying level x 30; every toss
-- replayed (H.setzerCheckCoins: twice its gil over the bodies it hit, the
-- shields' halving, the Broken double, the cap, special on every hit, a
-- shield off a special-weak body).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- a crowd worth the coins: two or more monsters standing, one of them
-- special-weak (its class row holds $08) and shielded.  A battle without
-- one is fought out with the free Fight (an empty plan) and the walk goes
-- on, as a player saving the coins would; the draws are the room's own.
local function crowdHere(tag, n)
  local alive, weak = 0, 0
  for s = 0, 5 do
    if H.readWord(0x3BFC + s * 2) > 0 and (H.readByte(0x3AA8 + s * 2) & 1) == 1 then
      alive = alive + 1
      if (H.readByte(0x3EA4 + s * 2) & 0x08) ~= 0 and H.readByte(0x3E40 + s * 2) > 0 then weak = weak + 1 end
    end
  end
  local yes = alive >= 2 and weak >= 1
  H.log(string.format("[%s] battle %d: %d monster(s), %d special-weak and shielded -- %s", tag, n, alive, weak,
    yes and "throw here" or "fight it out"))
  return yes
end

-- the draw this suite needs (kit-setzer round 4: a lone Mad Oscar had
-- crept in, and the split across bodies and the special chip stopped
-- running): at least one toss over two or more bodies, and at least one
-- chip on a special-weak body
local function coverage(all, tag)
  local split, chip = 0, 0
  for _, ps in ipairs(all) do
    for _, p in ipairs(ps) do
      if #p.hits >= 2 then split = split + 1 end
      for _, h in ipairs(p.hits) do if h.chip then chip = chip + 1 end end
    end
  end
  H.log(string.format("[%s] coverage: %d toss(es) split over two or more bodies, %d special chip(s)", tag, split, chip))
  H.assertEq(split > 0, true, tag .. ": a toss split across two or more bodies (the draw deals a crowd)")
  H.assertEq(chip > 0, true, tag .. ": a toss chipped a special-weak body")
end

local SETZER, COIN_TOSS_RELIC = 9, 0xD6


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
  return H.setzerCheckCoins(r, i, 30, function() return 0x08 end, "gprain")
end

local WANT = { { cmd = 0x18, boost = 1 }, { cmd = 0x18, boost = 0 } }
local done, battles = {}, 0
local function remaining()
  local t = {}
  for i = #done + 1, #WANT do t[#t + 1] = WANT[i] end
  return t
end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    H.assertEq(H.invCountOf(COIN_TOSS_RELIC) > 0, true, "the bag holds the Coin Toss relic")
  end),
  H.equipKit(SETZER, { { 4, COIN_TOSS_RELIC } }, { tag = "the Coin Toss relic on SETZER" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * SETZER + 0x23), COIN_TOSS_RELIC, "SETZER wears the Coin Toss relic")
  end),
  H.driveUntil(function() return #done >= #WANT end, 360000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 8, true, "both throws within eight battles")
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
        step = step or H.setzerBattle(crowdHere("gprain", battles) and remaining() or {}, {})
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
    local all = {}
    H.assertEq(#done, #WANT, "two GP Rains resolved")
    for i, r in ipairs(done) do
      H.assertEq(r.row, 0x18, string.format("record %d is a GP Rain", i))
      H.assertEq(r.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
      all[#all + 1] = checkRain(r, i)
    end
    coverage(all, "gprain")
    H.log(string.format("[gprain] PASSED: %d GP Rains over %d battle(s)", #done, battles))
  end),
})
