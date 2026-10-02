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
--   * the gil: TakeGil takes level x 30 at 0 BP and twice that at 1 BP
--     (the boost buys coins), and the purse falls by exactly that;
--   * no MP; the bank: +1 unboosted, -1 at 1 BP;
--   * the damage: twice the gil over the targets, each target's share
--     halved while its shields hold, doubled once Broken (the throw's own
--     chip can break it), never more than the HP it had;
--   * the class: every chip call carries special ($08), and a target loses
--     one shield exactly when its row holds special and it stood shielded
--     and unbroken.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/
-- (rate, boost, class) fail the named assertion.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

SETZER_SKIP = SETZER_SKIP or 0
local COIN = 0x59

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
  local want = r.level * 30 * (1 << r.boost)
  H.log(string.format("[cointoss] throw %d at %d BP, L%d: TakeGil %s, purse %d -> %d", i, r.boost, r.level,
    tostring(r.cost), r.gil0, r.gil1))
  H.assertEq(r.cost, want, string.format("throw %d: the gil thrown is level x 30 x 2^boost", i))
  H.assertEq(r.gil0 - r.gil1, want, string.format("throw %d: the purse falls by that", i))
  H.assertEq(r.mp1, r.mp0, string.format("throw %d: no MP", i))
  local bank = r.boost == 0 and math.min(5, r.bank0 + 1) or r.bank0 - r.boost
  H.assertEq(r.bank1, bank, string.format("throw %d: the bank (%d before, %d BP)", i, r.bank0, r.boost))
  local n = bits(r.targets)
  H.assertEq(n >= 1, true, string.format("throw %d hit at least one monster (mask $%02X)", i, r.targets))
  for _, c in ipairs(r.chips) do
    if c.y >= 8 then H.assertEq(c.class, 0x08, string.format("throw %d: the coins are special", i)) end
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
      H.log(string.format("[cointoss]   slot %d: HP %d -> %d (want -%d), shields %d -> %d (row $%02X, %s)",
        s, o.hp, m.hp, d, o.sh, m.sh, o.cls, chip and "special: chips" or "no special chip"))
      H.assertEq(o.hp - m.hp, d, string.format("throw %d: slot %d's share of the coins", i, s))
      if not (chip and sh == 0) then
        H.assertEq(o.sh - m.sh, chip and 1 or 0, string.format("throw %d: slot %d's shields", i, s))
      end
    end
  end
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
