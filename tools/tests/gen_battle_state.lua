-- gen_battle_state.lua -- drive OT6 from power-on into the first battle and
-- capture savestates.  Run with:
--
--   tools/tests/run.sh tools/tests/gen_battle_state.lua
--
-- Route (FF3us 1.0 New Game):
--   power-on -> title logo (Start presses) -> opening credits + Magitek walk
--   (all automatic, ~4.5 min emulated) -> Narshe cliff dialogs (mash A)
--   -> player control at the town gate -> walk north (hold Up, mash A)
--   -> scripted guard battle trigger.
--
-- Outputs (decoded from stdout by run.sh into build/states/):
--   battle_doorstep.mss[.lua]  field state a few seconds before the trigger
--   first_battle.mss[.lua]     in-battle state (only if the battle engine
--                              comes up; on a broken build this is skipped)
--   shots/gen_*.png            progress screenshots
--
-- Exit codes: 0 = in-battle state captured, 1 = battle never became active
-- (doorstep state still emitted), 2 = frame budget blown.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local doorstep, doorstepPrev = nil, nil

H.run({ maxFrames = 60000 }, {
  -- 1. Title screen: press Start a few times while the logo is up.  (The
  --    title also auto-advances into the intro, so this is belt+braces.)
  H.waitFrames(355),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.logStep("title handled; waiting out the opening (this takes a while)..."),

  -- 2. Opening narration + credits + Magitek snow walk are automatic.
  H.waitUntil(function() return H.frame >= 15500 end, 16000, "intro to finish"),
  H.call(function() H.screenshot("gen_cliff") end),

  -- 3. Cliff dialogs + town gate: walk north, mash A, keep rolling
  --    doorstep savestates so we always have a just-before-battle state.
  H.driveUntil(function() return H.battleLoadStarted() end, 15000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
    H.call(function()
      if H.frame % 150 < 30 then
        doorstepPrev = doorstep
        doorstep = emu.createSavestate()
      end
    end),
  }, "first battle load"),

  H.call(function()
    H.log("battle load began at frame " .. H.frame)
    local d = doorstepPrev or doorstep
    if d then H.emitBlob("battle_doorstep.mss", d) end
  end),

  -- 4. Wait for the battle to become ACTIVE (battle RAM + screen rendering).
  H.waitUntilSoft(function() return H.battleActive() end, 900, "battle_up", 30),
  H.call(function() H.screenshot("gen_battle_entry") end),

  H.cond(function() return H.vars.battle_up end, {
    -- happy path: let it settle, log the goods, save the state
    H.waitFrames(180),
    H.call(function()
      H.screenshot("gen_first_battle")
      local ids = H.monsterIds()
      H.log(string.format("monster ids: %04X %04X %04X %04X %04X %04X",
        ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]))
      local hp = H.partyHp()
      H.log(string.format("party battle hp: %d %d %d %d", hp[1], hp[2], hp[3], hp[4]))
      H.saveState("first_battle.mss")
    end),
  }, {
    -- battle load began but the engine never came up (screen stayed black):
    -- this is the regression signature this harness exists to catch.
    H.call(function()
      error("battle load started but battle never became active " ..
        "(battle_doorstep.mss emitted; see shots/gen_battle_entry.png)", 0)
    end),
  }),
})
