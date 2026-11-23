-- @suite slow
-- battle_hireimp.lua -- SETZER's third hire is an Imp (owner, 2026-11-17; kits.md "Each hire is somebody new",
-- docs/design/leo-reveal.md: General Leo, who held the place, must not walk on before Gogo's reveal nor beside
-- him after).
--
-- battle_hirecrew plays the 3 and 2 BP hires as they fall, and in its battles the first hire's blow fells the
-- target, so the later figures walk in, find no one and leave without a swing.  Here the third figure has to
-- swing: Continue the wor-tomb-v1 battery, care, SETZER's guard (battle_hirecrew's), Darill's Tomb's east room
-- into a random battle, and -- the declared unit-test expedient (tools/state_write_waivers.txt) -- every present
-- monster's HP raised to 30,000 at the battle's open, so the three hires of a 2-BP Hired Help each strike; then
-- SETZER through the real menu (H.setzerBattle): Defend, Hired Help at 2 BP.  Held to H.hireCrewCheck: each
-- pass's figure, the slot's graphics and its whole buffer against the figure's ROM sheet, the swap hidden and out
-- of sight, the strike's weapon for the class; the third pass is the Imp (graphics $0F, the Imp status's battle
-- set, its palette loaded into the slot's by status_pat_tfr) swinging the Imp Halberd or, on a target answered with
-- a blow (#566: a Fist or Arcane hire), the Morning Star; and at SETZER's Ot6ActionEnd his own sheet, position and pose, not the Imp's.
-- A mechanism test of the crew's third figure, not a claim about play.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

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

local got, impSwaps = nil, 0
-- the Imp's walk in and strike, shot (Ot6HireSwap with A = $0F)
local function shots()
  local at = {}
  local swap = H.sym("Ot6HireSwap")
  emu.addMemoryCallback(function()
    if (emu.getState()["cpu.a"] & 0xFF) == 0x0F then
      impSwaps = impSwaps + 1
      if impSwaps == 1 then
        for _, d in ipairs({ 30, 60, 90, 120, 150, 180 }) do at[#at + 1] = { f = H.frame + d, tag = string.format("battle_hireimp_f%03d", d) } end
      end
    end
  end, emu.callbackType.exec, swap, swap)
  emu.addEventCallback(function()
    for i = #at, 1, -1 do if H.frame >= at[i].f then H.screenshot(at[i].tag); table.remove(at, i) end end
  end, emu.eventType.endFrame)
end
H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.fieldCare({ threshold = 1.0, tag = "before the walk" }),
  H.guardOn(9, "SETZER", 0x02, 0x20, { threats = H.ARC_THREATS["wor-falcon"], tag = "SETZER's guard" }),
  H.call(function() H.hireCrewArm(); shots() end),
  H.driveUntil(function() return got ~= nil end, 180000, {
    H.fieldCare({ tag = "care between battles", threshold = 0.8 }),
    walkToBattle(),
    H.waitUntil(function() return H.battleActive() end, 3000, "the battle is up", 2),
    H.call(function()
      for m = 0, 5 do
        if (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 then
          H.writeWord(0x3BF4 + 8 + m * 2, 30000)
        end
      end
      H.log("[hireimp] every present monster's HP := 30000 (declared expedient)")
    end),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle({ { row = "defend" }, { row = HIRE, boost = 2 } }, {})
        local r = step:tick()
        if r == "done" then
          -- a hire whose third pass found no one to strike is played again in the next battle (gate 3 at
          -- ce985aaa: "pass 3: mark $A2 -- the Imp (class bits 0)", two strikes paid,
          -- build/attempts/wt/v049-land/gate3/suite_battle_hireimp.log); the battle that is judged had all three
          for _, rec in ipairs(H.vars.setzer) do
            if rec.row == HIRE and rec.costs ~= nil and #rec.costs == 3 then got = rec
            elseif rec.row == HIRE and not rec.saidShort then
              rec.saidShort = true
              H.log(string.format("[hireimp] the hire struck %d time(s), the Imp's pass found no one; again",
                rec.costs and #rec.costs or 0))
            end
          end
          if got == nil then H.log("[hireimp] no hire with three strikes in this battle; again") end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "a 2-BP Hired Help whose three hires strike"),
  H.call(function()
    H.assertEq(got.boost, 2, "the hire ran at 2 BP")
    H.hireCrewCheck(got, "hire (2 BP)")
    H.assertEq(#got.costs, 3, "all three hires were paid and struck (the third, the Imp, among them)")
    H.assertEq(impSwaps >= 1, true, "the slot was swapped to the Imp's graphics ($0F) for a pass")
    H.log(string.format("[hireimp] PASSED: three hires struck, the third the Imp (%d swap(s) to $0F)", impSwaps))
  end),
})
