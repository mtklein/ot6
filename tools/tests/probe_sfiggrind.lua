-- probe_sfiggrind.lua -- the development harness for the paced grind on the
-- world map outside South Figaro, and the measurement of what one lap of it
-- earns.  Built separately from probe_sfigshops.lua so a shop mistake does
-- not cost the grind's minutes and vice versa.
--
-- The southern walkable region draws battles at the normal rate; OT6 halves
-- the per-step danger increment and doubles random-battle rewards, so a
-- fight is expected about every 37 steps.  The danger counter is zeroed by
-- every battle and by every map load, so the lap route, (100,105) <->
-- (87,105) on row 105, avoids South Figaro's own entrance tiles to keep
-- accumulated danger from being thrown away.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function seq(steps) return H.cond(function() return true end, steps) end

local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end
-- experience is the 3-byte field at $1600 + 37*c + $11
local function expOf(c)
  local b = 0x1600 + 37 * c + 0x11
  return H.readByte(b) + (H.readByte(b + 1) << 8) + (H.readByte(b + 2) << 16)
end
local function levelOf(c) return H.readByte(0x1600 + 37 * c + 8) end

-- LOCKE is char 1.  The target is his TOTAL experience when the grind ends,
-- not a level, because the level he arrives at his own scenario with is set
-- by this number plus whatever Mt Kolts, VARGAS and the hideout add on top.
-- 2033 lands him at level 10 for the gate soldier.
local LOCKE, EXP_TARGET = 1, 2033

local function rosterLine()
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    local b = 0x1600 + 37 * c
    out[#out + 1] = string.format("c%d L%d %d/%d hp xp=%d", c,
      levelOf(c), H.readWord(b + 9), H.readWord(b + 11), expOf(c))
  end
  return table.concat(out, " | ")
end
local function where(tag)
  H.log(string.format("[%s] f%d world=(%d,%d) map=%d gil=%d | %s", tag,
    H.frame, H.worldX(), H.worldY(), map(), gil(), rosterLine()))
end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = (emu.getState()["ppu.screenBrightness"] or 0) >= 15
           and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleWorld(maxF)
  return seq({
    H.advanceStory(settled(20, function()
      return H.worldHasControl() and H.worldAligned()
    end), maxF or 12000, { playBattles = "flee" }),
    H.waitFrames(30),
  })
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = "flee" }),
    H.waitFrames(30),
  })
end

local POTION = 0xE9
local function care(tag)
  return H.fieldCare({ tag = "care " .. tag, threshold = 0.85,
                       reserve = { [POTION] = 3 }, mpFloor = 0.5 })
end

-- one lap: east to (100,105), back west to (87,105); 26 steps at ~37
-- steps/fight, a little under one fight a lap.  Skipped once the target is
-- met, so a fixed list of laps is a bounded grind.
local done = function() return expOf(LOCKE) >= EXP_TARGET end
local laps = 0
local function lap(n)
  return H.cond(function() return not done() end, {
    H.logStep(function()
      return string.format("grind lap %d: xp=%d/%d gil=%d f%d", n,
        expOf(LOCKE), EXP_TARGET, gil(), H.frame)
    end),
    H.worldNavTo(100, 105, { maxFrames = 40000, playBattles = "tactical",
                             reserve = { [POTION] = 3 } }),
    H.release(),
    H.worldNavTo(87, 105, { maxFrames = 40000, playBattles = "tactical",
                            reserve = { [POTION] = 3 } }),
    H.release(),
    H.call(function() laps = n; where("lap " .. n) end),
    care("lap " .. n),
  }, {})
end

H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, SOUTH FIGARO")
    H.assertEq(H.hasControl(), true, "controllable")
    where("boot")
  end),
  -- out of town by the x=0 column -> world (84,112)
  H.navTo(1, 28, { maxFrames = 20000, playBattles = "flee" }),
  H.release(), H.waitFrames(30),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "left" }), H.waitFrames(8),
  }, "leave South Figaro (x=0 column)"),
  H.release(),
  settleWorld(),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map")
    where("outside")
  end),
  -- north first: the two tiles east of the exit are the town's own
  -- entrance records
  H.worldNavTo(84, 108, { maxFrames = 20000, playBattles = "tactical" }),
  H.release(),
  H.call(function()
    H.assertEq(H.worldMode(), true, "still outside (the town tiles were avoided)")
    H.assertEq(H.worldX(), 84, "staged north of the gate, x=84")
    H.assertEq(H.worldY(), 108, "staged north of the gate, y=108")
  end),

  lap(1), lap(2), lap(3), lap(4), lap(5), lap(6), lap(7),
  lap(8), lap(9), lap(10), lap(11), lap(12), lap(13), lap(14),
  lap(15), lap(16), lap(17), lap(18),

  H.call(function()
    where("grind done")
    H.log(string.format("[grind] %d laps, LOCKE L%d xp=%d (target %d), gil=%d",
      laps, levelOf(LOCKE), expOf(LOCKE), EXP_TARGET, gil()))
  end),

  -- back into town at (86,111) -> map 75 (1,28)
  H.worldNavTo(86, 111, { maxFrames = 40000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField(75),
  H.call(function()
    H.assertEq(map(), 75, "back inside South Figaro")
    where("back in town")
  end),
})
