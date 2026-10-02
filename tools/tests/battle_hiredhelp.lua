-- @suite slow
-- battle_hiredhelp.lua -- SETZER's Hired Help (#319, kits.md "Setzer"): the
-- table's third row, hired twice, at 1 BP and unboosted.
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
-- new"): every hire held to H.hireCrewCheck, which reads the animation's
-- own state, not a flag -- each pass's figure (merchant, then soldier);
-- each walked-in figure's graphics id and its $7F buffer compared byte for
-- byte with that figure's ROM sheet; each swap made with the slot hidden
-- and standing out of sight (its absolute screen position past the edge);
-- each paid hire one drawn strike with the figure's weapon for the class;
-- and at SETZER's Ot6ActionEnd his sheet, screen position, offsets and
-- pose ($61c0/$61c1) as at his Ot6SetzerExec.  The 2 and 3 BP hires (Leo,
-- the fourth hire) are battle_hirecrew's.  The ROM's identity is logged.
-- Negative controls: build/attempts/wt/hire-sprite/negative/.

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

local WANT = { { row = HIRE, boost = 1 }, { row = HIRE, boost = 0 } }   -- two hires, then one
local done, battles = {}, 0
local function remaining()
  local t = {}
  for i = #done + 1, #WANT do t[#t + 1] = WANT[i] end
  return t
end

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function() H.hireCrewArm(); H.log("[hiredhelp] ROM " .. H.romIdentity()) end),
  H.repeatN(SETZER_SKIP, { walkToBattle(), H.setzerBattle({}) }),
  H.driveUntil(function() return #done >= #WANT end, 160000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 4, true, "both hires within four battles")
    end),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(remaining(), { shot = "hiredhelp_table" })
        local r = step:tick()
        if r == "done" then
          for _, rec in ipairs(H.vars.setzer) do
            done[#done + 1] = rec
            local i = #done      -- held as the battle ends, before the next one
            H.assertEq(rec.row, HIRE, string.format("record %d is a Hired Help", i))
            H.assertEq(rec.boost, WANT[i].boost, string.format("record %d ran at its planned boost", i))
            checkHire(rec, i)
            H.hireCrewCheck(rec, string.format("hire %d (%d BP)", i, rec.boost))
          end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "both hires resolve"),
  H.call(function()
    H.assertEq(#done, #WANT, "two hires resolved")
    H.log(string.format("[hiredhelp] PASSED: %d hires over %d battle(s)", #done, battles))
  end),
})
