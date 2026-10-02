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
-- table through the real menu (H.setzerBattle).  At L31 a throw is 930 gil
-- (1,860 at 1 BP) and a hire 1,550 (two hires at 1 BP, 3,100), so with
-- 1,700 in the purse:
--   1. Coin Toss at 1 BP (1,860): refused, the list stays up;
--   2. Hired Help at 1 BP (3,100 for the two): refused;
--   3. Coin Toss unboosted (930): taken -- the purse falls to 770;
--   4. Coin Toss unboosted again (930 > 770): refused.
-- The prices are derived from the battle's own level, so the arithmetic is
-- asserted rather than assumed; a battle that ends before all four is
-- followed by another, at most four.
-- Negative control: a mutant whose grey ignores the purse takes row 1
-- (build/attempts/wt/kit-setzer/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local COIN, HIRE = 0x59, 0x5A
local PURSE = 1700

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
  { row = COIN, boost = 1, refused = true },
  { row = HIRE, boost = 1, refused = true },
  { row = COIN, boost = 0 },
  { row = COIN, boost = 0, refused = true },
}
local k, battles, took = 1, 0, {}
local plan

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    H.writeWord(0x1860, PURSE)
    H.writeByte(0x1862, 0)
    local lv = H.readByte(0x1600 + 37 * 9 + 8)
    H.log(string.format("[grey] SETZER L%d; the purse set to %d (declared expedient)", lv, PURSE))
    H.assertEq(lv * 30 <= PURSE and lv * 30 * 2 > PURSE and lv * 50 * 2 > PURSE
      and PURSE - lv * 30 < lv * 30, true,
      string.format("L%d prices put the four steps where this suite says (throw %d, hire %d)", lv, lv * 30, lv * 50))
  end),
  H.driveUntil(function() return k > #WANT end, 160000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, "the four steps within four battles")
      plan = {}
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
          -- the steps this battle settled, in order
          local n = 0
          for _, p in ipairs(plan) do
            if p.refused then
              if not p.refusedSeen then break end
              H.log(string.format("[grey] step %d: row $%02X at %d BP refused at the list", k, p.row, p.boost))
            else
              local rec = H.vars.setzer[1]
              if rec == nil then break end
              took[#took + 1] = rec
              H.log(string.format("[grey] step %d: row $%02X at %d BP taken, purse %d -> %d", k, p.row, p.boost,
                rec.gil0, rec.gil1))
            end
            k, n = k + 1, n + 1
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "the four steps settle"),
  H.call(function()
    H.assertEq(#took, 1, "exactly one row was taken")
    local r = took[1]
    H.assertEq(r.row, COIN, "the taken row is Coin Toss")
    H.assertEq(r.gil0, PURSE, "with the whole purse in hand")
    H.assertEq(r.gil0 - r.gil1, r.level * 30, "it took one throw's gil")
    H.log("[grey] PASSED: a row the purse cannot pay at the pending boost is refused; one it can is taken")
  end),
})
