-- @suite slow
-- battle_hirecrew.lua -- SETZER's Hired Help at 3 and 2 BP (wt/hire-sprite,
-- kits.md "Each hire is somebody new"): every boost point's hire is the
-- next figure -- the merchant, the Imperial soldier, General Leo, and the
-- fourth: Shadow while he can be hired (recruited, $02E3, and not left on
-- the Floating Continent: in the World of Ruin, $00A4, only with $037D),
-- Interceptor while Shadow is in the battle's party, a Phantom Train ghost
-- when he can't be hired.  battle_hiredhelp holds the 1 BP and unboosted
-- hires (merchant, soldier) and their purse; this holds the 3 and 2 BP ones.
--
-- Played, not staged: Continue the wor-tomb-v1 battery, walk Darill's
-- Tomb's east room into its randoms, and play SETZER through the real menu
-- (H.setzerBattle): Defend, Defend, Hired Help at 3 BP; then, in a later
-- battle, Defend and Hired Help at 2 BP; field care between battles (a
-- stage whose battle ends first is played again in the next).  At this
-- fixture Shadow is recruited and the escape waited for him, so the
-- fourth hire is Shadow (lab_fallback and lab_fcsetzer in build/attempts/
-- wt/hire-sprite/ play the ghost and Interceptor).
--
-- Every hire is held to H.hireCrewCheck (lib/ot6.lua): the animation's own
-- state, not a flag -- each pass's figure; each walked-in figure's
-- graphics id and its $7F graphics buffer compared byte for byte with that
-- figure's ROM sheet (as LoadCharGfx builds it); each swap made with the
-- slot hidden (w7e61ac) and standing out of sight (its absolute screen
-- position past the edge, or above the top in a pincer); each paid hire
-- one drawn strike with the figure's weapon for the class; and at SETZER's
-- Ot6ActionEnd his sheet, screen position, offsets and pose ($61c0/$61c1)
-- as at his Ot6SetzerExec.  The purse is not replayed here: a 2 or 3 BP
-- hire can outlive its target, and the pass after a kill finds no body
-- even while another stands (the pass-retarget defect, wt/pass-retarget's);
-- a no-body pass still walks its figure in and out, and is checked so.
-- The ROM's identity is logged.  Negative controls: build/attempts/wt/
-- hire-sprite/negative/.
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

local STAGES = {
  { { row = "defend" }, { row = "defend" }, { row = HIRE, boost = 3 } },
  { { row = "defend" }, { row = HIRE, boost = 2 } },
}
local stage, battles, recs = 1, 0, {}

H.run({ maxFrames = 300000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function() H.hireCrewArm() end),
  H.repeatN(SETZER_SKIP, { walkToBattle(), H.setzerBattle({}) }),
  H.driveUntil(function() return stage > #STAGES end, 280000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 6, true, string.format("the 3 and 2 BP hires within six battles (stage %d)", stage))
    end),
    H.fieldCare({ tag = "care between the hires' battles", threshold = 0.8 }),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(STAGES[stage], {})
        local r = step:tick()
        if r == "done" then
          local got = nil
          for _, rec in ipairs(H.vars.setzer) do if rec.row == HIRE then got = rec end end
          if got then
            recs[#recs + 1] = got
            stage = stage + 1
          else
            H.log(string.format("[hirecrew] stage %d: the battle ended before the hire; again", stage))
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "the 3 and 2 BP hires resolve"),
  H.call(function()
    H.log("[hirecrew] ROM " .. H.romIdentity())
    local want = { 3, 2 }
    for i, r in ipairs(recs) do
      H.assertEq(r.boost, want[i], string.format("record %d ran at %d BP", i, want[i]))
      H.hireCrewCheck(r, string.format("hire %d (%d BP)", i, r.boost))
    end
    H.log(string.format("[hirecrew] PASSED: %d hires (3 and 2 BP) over %d battle(s)", #recs, battles))
  end),
})
