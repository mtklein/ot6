-- gen_whelk.lua -- reach the Whelk fight DETERMINISTICALLY: BFS-navigate on
-- the engine's own passability rules (H.canStep / H.bfsPath / H.navTo) to
-- (42,6), one tile SOUTH of the Whelk event trigger at (42,5), mint the
-- doorstep savestate there, then take one deliberate step onto the trigger
-- and let the event run: it force-walks the party down to (42,7), shows
-- dialogs $0B6E ("We won't hand over the Esper!!") / $0B6F ("Whelk! Get
-- them!") -- both EDGE-tapped through -- and starts the Whelk battle
-- (formation $01B0; species words 0x0100/0x0134 land in $57C0).  Random
-- encounters en route are cleared with the kill-bit idiom; the goal
-- formation is spared by guard.  Emits whelk_doorstep.mss + whelk_battle
-- screenshot.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

-- goal-fight signature: during the Whelk fight the six formation species
-- words at $57C0 read 0x0100 and 0x0134 (NOT 0x135 -- measured, the old
-- predicate was wrong).  0x134 is the distinctive one; both are spared.
local WHELK = { [0x0134] = true }
local SPARE = { 0x0134, 0x0100 }
local function whelk()
  -- gate on battleLoadStarted: $57C0 is battle scratch (power-on garbage
  -- until the first fight, stale words after one), never read it cold
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

local aPhase = 0

H.run({ maxFrames = 9000 }, {
  -- boot preamble: SRM sidecar inject to $30:6000, Continue, land on field
  H.waitFrames(5),
  H.call(function()
    local data = H.b64decode(H.resolveStateB64(SRM))
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end
  end),
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.hasControl() end, 2000, "field control", 10),
  H.call(function()
    local done = (H.readByte(0x1ea6) & 0x20) ~= 0   -- event switch $135
    H.log(string.format("start (%d,%d) map=%d whelk-done flag=%s (must be clear)",
      H.fieldX(), H.fieldY(), H.mapId(), tostring(done)))
    if done then error("boot save already has the Whelk beaten; trigger inert", 0) end
  end),

  -- walk to the doorstep tile (42,6), one short of the trigger
  H.navTo(42, 6, { arrive = whelk, maxFrames = 6000, spare = SPARE }),

  H.cond(function() return whelk() end, {
    -- shouldn't happen (BFS from the south never crosses (42,5)) but if the
    -- event fired en route, the fight is already the goal -- just no doorstep
    H.logStep("whelk fired en route; NO doorstep state minted this run"),
  }, {
    H.call(function()
      H.assertEq(H.fieldX() == 42 and H.fieldY() == 6, true,
        "at the whelk doorstep (42,6)")
      H.assertEq(H.hasControl() and H.tileAligned(), true,
        "doorstep is calm (user control, at rest, no battle)")
    end),
    H.saveState("whelk_doorstep.mss"),
    H.logStep(function()
      return string.format("doorstep minted at (42,6), frame %d", H.frame)
    end),
    -- the deliberate step: single-step up onto (42,5); the event force-walks
    -- us down and opens edge-triggered dialogs; a random encounter on this
    -- step is cleared like any other (the goal fight is guarded by arrive)
    H.driveUntil(function() return whelk() end, 2200, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.battleLoadStarted() then
          if whelk() then H.setPad({}); return end     -- pred fires next frame
          if H.monstersPresent() > 0 then
            for slot = 0, 5 do
              if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
                H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
              end
            end
          end
          H.setPad(aPhase < 4 and { "a" } or {})
          return
        end
        if H.dialogWaiting() then                      -- $0B6E then $0B6F
          H.setPad(aPhase < 4 and { "a" } or {})
          return
        end
        if not H.hasControl() then H.setPad({}); return end  -- event walking us
        if not H.tileAligned() then H.setPad({}); return end -- glide out steps
        -- at rest with control: step toward the trigger (down = re-approach
        -- if we somehow stand on/above an unfired trigger)
        H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
      end),
    }, "whelk event fires"),
  }),

  -- the fight is loading; let it come up on screen and prove it's Whelk
  H.call(function() H.setPad({}) end),
  H.waitUntilSoft(function() return H.battleActive() end, 900, "whelk_up", 30),
  H.call(function()
    H.assertEq(whelk(), true, "Whelk formation words present at $57C0")
    local w = H.formationWords()
    H.log(string.format("formation: %04X %04X %04X %04X %04X %04X (screen up=%s)",
      w[1], w[2], w[3], w[4], w[5], w[6], tostring(H.vars.whelk_up)))
    H.screenshot("whelk_battle")
    H.log(string.format("WHELK battle at frame %d", H.frame))
  end),
})
