-- @suite slow
-- battle_setzergrey.lua -- SETZER's gil rows grey and refuse what the purse
-- cannot pay (#319, kits.md "Setzer"; Ot6SetzerRowGrey, read by the row's
-- colour and by Ot6KitConfirmMP's refusal alike).
--
-- One declared unit-test expedient (tools/state_write_waivers.txt): the
-- party's gil is written to PURSE before the walk, because the battery
-- carries a quarter of a million and no route shop empties it on cue.
-- Everything after is played: Continue the wor-tomb-v1 battery (SETZER L31),
-- walk Darill's Tomb's east room into a random battle, and play SETZER's
-- table through the real menu (H.setzerBattle): two Defends first (the
-- bank to 3), then the steps.  A boost buys one more throw or hire at the
-- same price (Ot6CoinTotal: one, two, three or four of them), and at L31 a
-- throw is 930 gil and a hire 1,550, so with 2,000 in the purse:
--   1. Coin Toss at 3 BP (four throws, 3,720): refused, the list stays up;
--   2. Coin Toss at 2 BP (three, 2,790): refused;
--   3. Hired Help at 1 BP (two hires, 3,100): refused;
--   4. Coin Toss at 1 BP (two, 1,860): taken -- the purse falls to 140;
--   5. Coin Toss unboosted (930 > 140): refused.
-- (A draw whose first throw fells the last body pays one throw and leaves
-- 1,070, so step 5 would be taken and "exactly one row" fails: the draw,
-- not the grey, changed.)
-- The prices are derived from the battle's own level, so the arithmetic is
-- asserted rather than assumed; a battle that ends before all five is
-- followed by another (two Defends again first), at most four.
-- Negative controls (build/attempts/wt/kit-setzer/): a grey that ignores
-- the purse takes step 1; Ot6CoinTotal's four-pass arm priced as two
-- throws (1,860) takes step 1, its three-pass arm priced as two takes
-- step 2.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local COIN, HIRE = 0x59, 0x5A
local PURSE = 2000

local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

local WANT = {
  { row = COIN, boost = 3, refused = true },
  { row = COIN, boost = 2, refused = true },
  { row = HIRE, boost = 1, refused = true },
  { row = COIN, boost = 1 },
  { row = COIN, boost = 0, refused = true },
}
local DEFENDS = 2
local k, battles, took = 1, 0, {}
local plan

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    H.writeWord(0x1860, PURSE)
    H.writeByte(0x1862, 0)
    local lv = H.readByte(0x1600 + 37 * 9 + 8)
    H.log(string.format("[grey] SETZER L%d; the purse set to %d (declared expedient)", lv, PURSE))
    H.assertEq(lv * 30 * 4 > PURSE and lv * 30 * 3 > PURSE and lv * 50 * 2 > PURSE and lv * 30 * 2 <= PURSE
      and PURSE - lv * 30 * 2 < lv * 30 and lv * 30 * 2 <= PURSE, true,
      string.format("L%d prices put the five steps where this suite says (throw %d, hire %d)", lv, lv * 30, lv * 50))
  end),
  H.driveUntil(function() return k > #WANT end, 160000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, "the five steps within four battles")
      plan = {}
      for _ = 1, DEFENDS do plan[#plan + 1] = { row = "defend" } end
      for i = k, #WANT do
        local c = {}
        for kk, v in pairs(WANT[i]) do c[kk] = v end
        plan[#plan + 1] = c
      end
    end),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(plan, { shot = "grey_table" })
        local r = step:tick()
        if r == "done" then
          -- step 1 is the first battle's first entry, and SETZER's first
          -- turn reaches it: its refusal is asserted here, by name (and
          -- H.setzerBattle fails at once if a refused entry's confirm goes
          -- through to target select)
          if k == 1 then
            H.assertEq(plan[DEFENDS + 1].refusedSeen == true, true, string.format("step 1: Coin Toss at 3 BP (four "
              .. "throws, %d) with %d in the purse is refused at the list", 4 * H.readByte(0x1600 + 37 * 9 + 8) * 30,
              PURSE))
          end
          -- the steps this battle settled, in order
          local n = 0
          for _, p in ipairs(plan) do
            if p.row == "defend" then
              -- the bank's Defends, not steps
            elseif p.refused then
              if not p.refusedSeen then break end
              H.log(string.format("[grey] step %d: row $%02X at %d BP refused at the list", k, p.row, p.boost))
            else
              local rec = H.vars.setzer[1]
              if rec == nil then break end
              took[#took + 1] = rec
              H.log(string.format("[grey] step %d: row $%02X at %d BP taken, purse %d -> %d", k, p.row, p.boost,
                rec.gil0, rec.gil1))
            end
            if p.row ~= "defend" then k, n = k + 1, n + 1 end
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "the five steps settle"),
  H.call(function()
    H.assertEq(#took, 1, "exactly one row was taken")
    local r = took[1]
    H.assertEq(r.row, COIN, "the taken row is Coin Toss")
    H.assertEq(r.gil0, PURSE, "with the whole purse in hand")
    H.assertEq(r.boost, 1, "at 1 BP")
    H.assertEq(#r.costs >= 1 and #r.costs <= 2, true, "one or two throws paid (two, unless the first felled the last body)")
    H.assertEq(r.gil0 - r.gil1, r.level * 30 * #r.costs, string.format("it took %d throw(s)' gil", #r.costs))
    H.log("[grey] PASSED: a row the purse cannot pay at the pending boost is refused; one it can is taken")
  end),
})
