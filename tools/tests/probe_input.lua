-- probe_input: verify the INPUT LAYER stays alive over a LONG, REALISTIC run.
-- The old $4218/$4219 read-hack silently died after ~7000 frames, freezing
-- the party mid-navigation. With emu.setInput(input, port) inside an
-- inputPolled event callback, held input reaches the ROM every frame for the
-- whole run. Boot into the mine and pace the party; random encounters WILL
-- fire, so clear them inline (the clearBattle idiom) and keep going. Assert
-- the party keeps racking up tile transitions -- including in the run's
-- second half, the exact window where the old hack went dead.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

local FLIP = 30
local lastX, lastY, dir, firstHalf, secondHalf, iters, battles =
      nil, nil, "down", 0, 0, 0, 0
local HALF = 900

H.run({ maxFrames = 40000 }, {
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
    H.log(string.format("post-boot: (%d,%d) map=%d", H.fieldX(), H.fieldY(),
      H.mapId()))
  end),
  H.driveUntil(function()
    iters = iters + 1
    if (iters % FLIP) < (FLIP / 2) then dir = "down" else dir = "up" end

    if H.battleActive() or H.battleLoadStarted() then
      if H.battleActive() then
        if lastX ~= "batt" then battles = battles + 1 end
        lastX = "batt"                       -- mark: last sample was a battle
        for slot = 0, 5 do
          if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
            H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
          end
        end
      end
      H.setPad({ "a" })                      -- advance load / victory / exp
    elseif not H.hasControl() then
      H.setPad({ "a" })                      -- advance any event/dialog
    else
      local x, y = H.fieldX(), H.fieldY()
      if type(lastX) == "number" and (x ~= lastX or y ~= lastY) then
        if iters <= HALF then firstHalf = firstHalf + 1
        else secondHalf = secondHalf + 1 end
      end
      lastX, lastY = x, y
      H.setPad({ [dir] = true })
    end

    if (iters % 150) == 0 then
      H.log(string.format("  it=%d tile=(%d,%d) fh=%d sh=%d battles=%d",
        iters, H.fieldX(), H.fieldY(), firstHalf, secondHalf, battles))
    end
    return iters >= 2 * HALF
  end, 36000, { H.waitFrames(3) }, "pace"),
  H.call(function()
    H.log(string.format("pace: firstHalf=%d, secondHalf=%d, battles=%d, ended (%d,%d)",
      firstHalf, secondHalf, battles, H.fieldX(), H.fieldY()))
    -- input alive the WHOLE run: it must still drive movement in the 2nd half
    H.assertEq(secondHalf >= 5, true,
      "input stays alive: party still moving in the run's second half")
  end),
})
