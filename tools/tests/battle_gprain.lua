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
-- row (H.setzerBattle's `cmd` entries) at 1 BP and unboosted in the
-- battles that deal a crowd (two or more monsters, one special-weak), so a
-- toss splits across bodies and chips the special-weak one (asserted:
-- coverage); any other battle is fought out by the route's fight driver
-- and followed by field care, within the budget decoded from the room's
-- pool (H.setzerCrowdBattles: the worst encounter-counter state's
-- encounters to the next crowd, per crowd the throws need).  Per throw (Cmd_18's entry and
-- SETZER's Ot6ActionEnd): the command list holds GP Rain and no Slot; 1 +
-- boost tosses, each that finds a body paying level x 30; every toss
-- replayed (H.setzerCheckCoins: twice its gil over the bodies it hit, the
-- shields' halving, the Broken double, the cap, special on every hit, a
-- shield off a special-weak body).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

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

local function checkRain(r, i)
  return H.setzerCheckCoins(r, i, 30, function() return 0x08 end, "gprain")
end

local WANT = { { cmd = 0x18, boost = 1 }, { cmd = 0x18, boost = 0 } }
local walk, S = H.setzerCrowdBattles({
  tag = "gprain", want = WANT, wps = { { 124, 26 }, { 120, 11 } },
  onBattle = function()
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
  end,
  check = function(rec, i)
    H.assertEq(rec.row, 0x18, string.format("record %d is a GP Rain", i))
    H.assertEq(rec.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
    return checkRain(rec, i)
  end,
})

H.run({ maxFrames = 1200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    H.assertEq(H.invCountOf(COIN_TOSS_RELIC) > 0, true, "the bag holds the Coin Toss relic")
  end),
  H.equipKit(SETZER, { { 4, COIN_TOSS_RELIC } }, { tag = "the Coin Toss relic on SETZER" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * SETZER + 0x23), COIN_TOSS_RELIC, "SETZER wears the Coin Toss relic")
  end),
  walk,
  H.call(function()
    H.assertEq(#S.done, #WANT, "two GP Rains resolved")
    coverage(S.all, "gprain")
    H.log(string.format("[gprain] PASSED: %d GP Rains over %d battle(s), %d of them crowds", #S.done, S.battles,
      S.crowds))
  end),
})
