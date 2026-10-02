-- @suite slow
-- battle_cointoss.lua -- SETZER's Coin Toss (#319, kits.md "Setzer"): the
-- Slot row's table, and its second row thrown twice, unboosted and at 1 BP.
--
-- Played, not staged: Continue the wor-tomb-v1 battery (CELES, SABIN,
-- EDGAR and SETZER on Darill's Tomb's B3 save point; SETZER back in the
-- World of Ruin, so his Jackpot is learned), walk the east room until the
-- game deals a battle (field group 151: a Mad Oscar; a Mad Oscar and an
-- Exoray; a PowerDemon and two Exorays), and play SETZER's turns through
-- the real menu (H.setzerBattle).  Every assertion is derived from that
-- battle's own state, so any formation the room deals is a valid draw;
-- SETZER_SKIP (default 0) battles are fought out first to vary it.
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

SETZER_SKIP = SETZER_SKIP or 0
local COIN = 0x59


local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

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
local done, battles = {}, 0
local function remaining()
  local t = {}
  for i = #done + 1, #WANT do t[#t + 1] = WANT[i] end
  return t
end

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.repeatN(SETZER_SKIP, { walkToBattle(), H.setzerBattle({}) }),
  -- both throws, in as many battles as the draws take (at most four)
  H.driveUntil(function() return #done >= #WANT end, 160000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, "both throws within four battles")
    end),
    walkToBattle(),
    H.cond(function() return true end, {
      (function()
        local step
        return { tick = function()
          step = step or H.setzerBattle(remaining(), { onList = checkList, shot = "cointoss_table" })
          local r = step:tick()
          if r == "done" then
            for _, rec in ipairs(H.vars.setzer) do done[#done + 1] = rec end
            step = nil
          end
          return r
        end, reset = function() step = nil end }
      end)(),
    }),
  }, "both Coin Tosses resolve"),
  H.call(function()
    H.assertEq(#done, #WANT, "two Coin Tosses resolved")
    for i, r in ipairs(done) do
      H.assertEq(r.row, COIN, string.format("record %d is a Coin Toss", i))
      H.assertEq(r.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
      checkThrow(r, i)
    end
    H.log(string.format("[cointoss] PASSED: %d throws over %d battle(s)", #done, battles))
  end),
})
