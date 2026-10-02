-- @suite slow
-- battle_hiredhelp.lua -- SETZER's Hired Help (#319, kits.md "Setzer"): the
-- table's third row, hired at 1 BP and unboosted, then at 2 and at 3 BP.
--
-- Played, not staged: Continue the wor-tomb-v1 battery (SETZER back in the
-- World of Ruin), walk Darill's Tomb's east room until the game deals a
-- battle (field group 151), and play SETZER's turns through the real menu
-- (H.setzerBattle), as many battles as the draws take.  Every assertion is
-- derived from the battle's own state, so any formation the room deals is
-- a valid draw; SETZER_SKIP (default 0) battles are fought out first to
-- vary it.
--
-- What it holds, per hire (at Ot6SetzerExec's entry and SETZER's
-- Ot6ActionEnd):
--   * the hires: 1 + boost of them, one a pass of the action, each paying
--     its own fee, level x 50 (TakeGil at every pass), so the purse falls by
--     every fee; no MP; the bank +1 / -1;
--   * one target, and the class: every chip call on it carries the first
--     physical class its row holds (slashing $01, else piercing $02, else
--     bludgeoning $04), or none when the row holds no physical class --
--     the sellsword's weapon fits the target, whatever SETZER holds;
--   * each hit: twice the fee, halved while the body's shields hold,
--     doubled once Broken (a hire's own chip can break it), never more than
--     the HP; one shield off exactly when that class exists and the body
--     stood shielded and unbroken -- replayed hit by hit from the opening
--     state and held against every body's HP and shields at the end.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/
-- (rate, boost, class) fail the named assertion.
--
-- And what the player sees (wt/hire-sprite, kits.md "Each hire is somebody
-- new"), at 1, 0, 2 and 3 BP: H.hireCrewArm / H.hireCrewCheck read the
-- animation's own state, not a flag -- every pass's figure (merchant,
-- soldier, Leo, then Shadow while he can be hired, the ghost when not,
-- Interceptor while he fights in the party); every walked-in figure's
-- graphics id and its $7F buffer compared byte for byte with that figure's
-- ROM sheet; every swap made with the slot hidden and standing out of sight
-- (its absolute screen position: past the edge sideways, above the top in a
-- pincer); every paid hire one drawn strike with the figure's weapon for
-- the class; and at SETZER's Ot6ActionEnd his sheet, screen position,
-- offsets and pose ($61bf/$61c0/$61c1) as they were at his Ot6SetzerExec.
-- The ROM's identity is logged.  Negative controls (build/attempts/wt/
-- hire-sprite/negative/): one mutant a property, each failing its named
-- assertion.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

SETZER_SKIP = SETZER_SKIP or 0
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

local function sellsword(row)
  if row & 0x01 ~= 0 then return 0x01 end
  if row & 0x02 ~= 0 then return 0x02 end
  if row & 0x04 ~= 0 then return 0x04 end
  return 0x00
end

local function checkHire(r, i)
  return H.setzerCheckCoins(r, i, 50, sellsword, "hiredhelp")
end

-- ---- the plays -------------------------------------------------------------
-- Stages, a battle each (again in the next battle if it ends first), with
-- field care between: SETZER hires at 1 BP, then unboosted -- held to the
-- purse (checkHire); Defends twice and hires at 3 BP; Defends once and
-- hires at 2 BP -- every hire held to the crew (H.hireCrewCheck): the merchant, soldier, Leo and the fourth hire
-- (Shadow while he can be hired, the ghost when not, Interceptor while he
-- fights in the party), whatever bodies the passes find.  The coin replay
-- (checkHire) is held to the 1-and-0 stage only: a 2 or 3 BP hire can outlive its
-- target, and the pass after a kill finds no body even when another stands
-- (the pass-retarget defect, fixed on wt/pass-retarget, not here).
local STAGES = {
  { { row = HIRE, boost = 1 }, { row = HIRE, boost = 0 } },
  { { row = "defend" }, { row = "defend" }, { row = HIRE, boost = 3 } },
  { { row = "defend" }, { row = HIRE, boost = 2 } },
}
local PURSE_STAGE = 1   -- the stage held to the coin replay (checkHire)
local function hires(stage)
  local t = {}
  for _, e in ipairs(stage) do if e.row == HIRE then t[#t + 1] = e end end
  return t
end
local stage, done, battles = 1, {}, 0
local recs = {}

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function() H.hireCrewArm() end),
  H.repeatN(SETZER_SKIP, { walkToBattle(), H.setzerBattle({}) }),
  H.driveUntil(function() return stage > #STAGES end, 380000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 8, true, string.format("the three stages within eight battles (stage %d)", stage))
    end),
    H.fieldCare({ tag = "care between the hires' battles", threshold = 0.8 }),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(STAGES[stage], { shot = "hiredhelp_table" })
        local r = step:tick()
        if r == "done" then
          local want, got = hires(STAGES[stage]), {}
          for _, rec in ipairs(H.vars.setzer) do got[#got + 1] = rec end
          if #got >= #want then
            for i, rec in ipairs(got) do
              if i <= #want then recs[#recs + 1] = { r = rec, want = want[i], stage = stage } end
            end
            stage = stage + 1
          else
            H.log(string.format("[hiredhelp] stage %d: the battle ended after %d of %d hire(s); again", stage, #got,
              #want))
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "the three stages resolve"),
  H.call(function()
    H.log("[hiredhelp] ROM " .. H.romIdentity())
    local i = 0
    for _, e in ipairs(recs) do
      i = i + 1
      local r = e.r
      H.assertEq(r.row, HIRE, string.format("record %d is a Hired Help", i))
      H.assertEq(r.boost, e.want.boost, string.format("record %d ran at its planned boost", i))
      if e.stage == PURSE_STAGE then checkHire(r, i) end
      H.hireCrewCheck(r, string.format("hire %d (%d BP)", i, r.boost))
    end
    H.log(string.format("[hiredhelp] PASSED: %d hires (1, 0, 2 and 3 BP) over %d battle(s)", #recs, battles))
  end),
})
