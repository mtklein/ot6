-- @suite slow
-- battle_cointoss.lua -- SETZER's Coin Toss (#319, kits.md "Setzer"): the
-- Slot row's table, and its second row thrown twice, unboosted and at 1 BP.
--
-- Played, not staged: Continue the wor-tomb-v1 battery (CELES, SABIN,
-- EDGAR and SETZER on Darill's Tomb's B3 save point; SETZER back in the
-- World of Ruin, so his Jackpot is learned), walk the east room into
-- random battles (field group 151: a Mad Oscar; a Mad Oscar and an Exoray;
-- a PowerDemon and two Exorays), and play SETZER's turns through the real
-- menu (H.setzerBattle) in the battles that deal a crowd -- two or more
-- monsters, one special-weak -- so a toss splits across bodies and chips
-- the special-weak one, asserted (coverage), since a lone Mad Oscar dealt
-- first had quietly stopped both from running.  Any other battle is fought
-- out by the route's fight driver and followed by field care
-- (H.setzerCrowdBattles).  The budget is decoded from the room's pool: the
-- most encounters any encounter-counter state needs to the next crowd (19
-- on this ROM), per crowd the throws need -- at most two, since each crowd
-- battle gives at least one throw.  Every other assertion is derived from
-- the battle's own state.
--
-- What it holds, per throw (the action's own edges: Ot6SetzerExec's entry
-- and SETZER's Ot6ActionEnd):
--   * the table: Slot $5C, Coin Toss $59, Hired Help $5A, Jackpot $5B down
--     the left column, Jackpot priced 99 MP and the rest unpriced, Coin
--     Toss targeting the enemy side ($6A, GP Rain's), mode 4;
--   * the tosses: 1 + boost of them (the boost buys tosses, owner
--     2026-10-02), one pass of the action each, each that finds a body
--     paying level x 30 (TakeGil), none past the last standing body, and
--     the purse falling by exactly those;
--   * no MP; the bank: +1 unboosted, -1 at 1 BP;
--   * every toss replayed from the opening state (H.setzerReplay): twice
--     its gil over the bodies it hit, each share halved while shields hold,
--     doubled once Broken (a toss's own chip can break it), capped at 9,999
--     and the HP; the class special ($08) on every hit, a shield off a
--     special-weak body that stood shielded and unbroken -- held against
--     every body's HP and shields at the end.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/
-- (rate, boost, class) fail the named assertion.
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

local COIN = 0x59

local function checkList(l)
  local want = { [0] = 0x5C, 0xFF, 0x59, 0xFF, 0x5A, 0xFF, 0x5B, 0xFF }
  for i = 0, 7 do
    H.assertEq(l.ids[i], want[i], string.format("the table's cell %d", i))
  end
  H.assertEq(l.mode, 4, "the Tools shell is in setzer mode ($6168 = 4)")
  H.assertEq(l.qty[6], 99, "Jackpot is drawn at 99 MP")
  H.assertEq(l.qty[2] + l.qty[4], 0, "Coin Toss and Hired Help draw no MP price")
  H.assertEq(l.flags[2], 0x6A, "Coin Toss targets the enemy side (GP Rain's $6A)")
  H.assertEq(l.flags[4], 0x43, "Hired Help targets one enemy ($43)")
end

local function checkThrow(r, i)
  return H.setzerCheckCoins(r, i, 30, function() return 0x08 end, "cointoss")
end

local WANT = { { row = COIN, boost = 1 }, { row = COIN, boost = 0 } }
local walk, S = H.setzerCrowdBattles({
  tag = "cointoss", want = WANT, wps = { { 124, 26 }, { 120, 11 } },
  setzerOpts = { onList = checkList, shot = "cointoss_table" },
  check = function(rec, i)
    H.assertEq(rec.row, COIN, string.format("record %d is a Coin Toss", i))
    H.assertEq(rec.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
    return checkThrow(rec, i)
  end,
})

H.run({ maxFrames = 1200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  walk,
  H.call(function()
    H.assertEq(#S.done, #WANT, "two Coin Tosses resolved")
    coverage(S.all, "cointoss")
    H.log(string.format("[cointoss] PASSED: %d throws over %d battle(s), %d of them crowds", #S.done, S.battles,
      S.crowds))
  end),
})
