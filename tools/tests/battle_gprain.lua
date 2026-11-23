-- @suite slow savestate=wor_tomb_b1_hunt_b1
-- battle_gprain.lua -- the Coin Toss relic's GP Rain since #319: Slot gives
-- way to GP Rain (no table), and its coins are Arcane (special until #566; one chip on a
-- arcane-weak body) and boostable (the boost buys another toss a point, as
-- Coin Toss's does; before, GP Rain's boost bought nothing, because
-- Ot6BoostDmg's multiplier runs in CalcDmg and GP Rain's effect overwrites
-- the damage).
--
-- Played, no writes: boot wor_tomb_b1_hunt_b1 (gen_wor_tomb_b1_hunt's frame on
-- Darill's Tomb's B1 stairs; until #566 the wor-tomb-v1 battery and the east
-- room, whose bodies hold no arcane weakness under six classes: battle_cointoss's
-- header), put the bag's Coin
-- Toss relic on SETZER through the Relic menu (H.equipKit), care to full and
-- hand SETZER the party's widest guard (H.guardOn: the tomb Zombies), walk
-- B1 (field group 149) into random battles, and throw GP Rain from the command
-- row (H.setzerBattle's `cmd` entries) at 1 BP and unboosted in the
-- battles that deal a crowd (two or more monsters, one arcane-weak), so a
-- toss splits across bodies and chips the arcane-weak one (asserted:
-- coverage); any other battle is fought out by the route's fight driver
-- and followed by field care, within the budget decoded from the room's
-- pool (H.setzerCrowdBattles: the worst encounter-counter state's
-- encounters to the next crowd, per crowd the throws need).  Per throw (Cmd_18's entry and
-- SETZER's Ot6ActionEnd): the command list holds GP Rain and no Slot; 1 +
-- boost tosses, each that finds a body paying level x 30; every toss
-- replayed (H.setzerCheckCoins: twice its gil over the bodies it hit, the
-- shields' halving, the Broken double, the cap, Arcane on every hit, a
-- shield off an arcane-weak body).
local H = dofile("tools/tests/lib/ot6.lua")

-- the draw this suite needs (kit-setzer round 4: a lone Mad Oscar had
-- crept in, and the split across bodies and the arcane chip stopped
-- running): at least one toss over two or more bodies, and at least one
-- chip on an arcane-weak body (up to two more crowds, one GP Rain each, when
-- the crowd's arcane-weak body is broken or dead by the time the coins land)
local function coverage(alls, tag)
  local split, chip = 0, 0
  for _, all in ipairs(alls) do
    for _, ps in ipairs(all) do
      for _, p in ipairs(ps) do
        if #p.hits >= 2 then split = split + 1 end
        for _, h in ipairs(p.hits) do if h.chip then chip = chip + 1 end end
      end
    end
  end
  H.log(string.format("[%s] coverage: %d toss(es) split over two or more bodies, %d arcane chip(s)", tag, split, chip))
  H.assertEq(split > 0, true, tag .. ": a toss split across two or more bodies (the draw deals a crowd)")
  H.assertEq(chip > 0, true, tag .. ": a toss chipped an arcane-weak body")
end

local SETZER, COIN_TOSS_RELIC = 9, 0xD6
local ARCANE = 0x08     -- OT6_ARCANE: the coins' class (OT6_CLS_COIN; special until #566)
local STATE, MAP_B1 = "build/states/wor_tomb_b1_hunt_b1.mss.lua", 298
local B1_LAP = { { 13, 16 }, { 13, 17 } }      -- gen_wor_tomb_b1_hunt's lap, clear of the stairs' tiles

local function checkRain(r, i)
  return H.setzerCheckCoins(r, i, 30, function() return ARCANE end, "gprain")
end

local WANT = { { cmd = 0x18, boost = 1 }, { cmd = 0x18, boost = 0 } }
local function crowdWalk(tag, want)
  return H.setzerCrowdBattles({
    tag = tag, want = want, wps = B1_LAP,
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
      H.assertEq(rec.boost, want[i].boost, string.format("record %d ran at its planned boost", i))
      return checkRain(rec, i)
    end,
  })
end
local walk, S = crowdWalk("gprain", WANT)
-- A crowd is chosen as it opens (two or more bodies, one arcane-weak and
-- shielded), and the arcane-weak body can be Broken or dead by the time
-- SETZER's coins land: v0.50's replay, his GP Rain confirmed at f4384 and
-- run at f5632 on a body broken in between ('slot 0: HP 1385 -> 0, shields
-- 0 -> 0, broken 14 -> 11, row 0B', build/attempts/wt/v050-multihit-anim/
-- ab/gprain_windowrecheck_red.log), so no toss could chip.  As
-- battle_cointoss does: up to two more crowds, one GP Rain each, until a
-- toss chips one; the coverage then holds over every toss played.
local EXTRA = 2
local extras = {}
for e = 1, EXTRA do
  local w, s2 = crowdWalk("gprain extra " .. e, { { cmd = 0x18, boost = 0 } })
  extras[e] = { walk = w, S = s2 }
end
local function played()
  local alls = { S.all }
  for _, x in ipairs(extras) do if #x.S.done > 0 then alls[#alls + 1] = x.S.all end end
  return alls
end
local function chips(alls)
  local n = 0
  for _, all in ipairs(alls) do
    for _, ps in ipairs(all) do
      for _, p in ipairs(ps) do for _, h in ipairs(p.hits) do if h.chip then n = n + 1 end end end
    end
  end
  return n
end
local extraSteps = {}
for e = 1, EXTRA do
  extraSteps[#extraSteps + 1] = H.cond(function() return chips(played()) == 0 end, {
    H.call(function()
      H.log(string.format("[gprain] no toss so far chipped an arcane-weak body (it was broken or dead when the "
        .. "coins landed): crowd %d more, one GP Rain", e))
    end),
    extras[e].walk,
  }, {})
end

H.run({ maxFrames = 1200000 }, {
  -- #566: the coins' crowd is dealt on B1 (the header), from gen_wor_tomb_b1_hunt's own frame on its stairs
  H.waitFrames(20), H.loadState(STATE), H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and not H.dialogWaiting() end, 3000,
    "control on B1's stairs", 5),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, MAP_B1, "booted on Darill's Tomb's B1 (map 298), gen_wor_tomb_b1_hunt's stairs")
    H.assertEq(H.readByte(0x1850 + 9) & 7, H.readByte(0x1A6D) & 7, "SETZER is in the active party")
    H.assertEq(H.kitClass("coin"), ARCANE, "the coins' class is Arcane (Ot6KitClassTbl +1)")
  end),
  H.call(function()
    H.assertEq(H.invCountOf(COIN_TOSS_RELIC) > 0, true, "the bag holds the Coin Toss relic")
  end),
  H.equipKit(SETZER, { { 4, COIN_TOSS_RELIC } }, { tag = "the Coin Toss relic on SETZER" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * SETZER + 0x23), COIN_TOSS_RELIC, "SETZER wears the Coin Toss relic")
  end),
  -- SETZER has to take the throws, and the room's bodies Zombie him (route-wor-falcon.md section 1, item 5): the
  -- party, cared to full, hands him its widest guard beside the Coin Toss (#501: the sweep's K=2 shift-7 draw
  -- Zombied him and then SABIN, and crowd battle 3 ended with no throw)
  H.fieldCare({ threshold = 1.0, tag = "before the walk" }),
  H.guardOn(SETZER, "SETZER", 0x02, 0x20, { threats = H.ARC_THREATS["wor-falcon"], tag = "SETZER's guard" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * SETZER + 0x23), COIN_TOSS_RELIC, "SETZER still wears the Coin Toss relic")
  end),
  walk,
  H.cond(function() return true end, extraSteps),
  H.call(function()
    H.assertEq(#S.done, #WANT, "two GP Rains resolved")
    coverage(played(), "gprain")
    H.log(string.format("[gprain] PASSED: %d GP Rains over %d battle(s), %d of them crowds", #S.done, S.battles,
      S.crowds))
  end),
})
