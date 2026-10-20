-- @manual
-- readme_shots_aura.lua -- battle_boostaura.lua's drive to 3 BP in a real kolts_cave
-- fight (the first character to open a menu banks by Defending, then R,R,R),
-- then screenshots of the aura while the command window is up (README boost
-- bullet).  Not a test.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local OAM, CG = emu.memType.snesSpriteRam, emu.memType.snesCgRam
local PRISTINE = 0x7E81AD                  -- w7e81ad: unaltered char palettes
local FLOOR = 0x97                      -- the budget stops here (FF6 overflows lines below it on purpose)
local TOPN, BOTN = { 2, 3, 6 }, { 2, 3, 3 } -- Ot6HaloTopN, Ot6HaloBotN: copies a half wants at 1/2/3 BP
local actor
local copiesSeen = 0                       -- halo copies seen over the run: the halo must show somewhere
local function pend(s) return H.readByte(0x3e9d + s * 2) end
local function bp(s) return H.readByte(0x3e9c + s * 2) end
local function map() return H.mapId() & 0x1ff end

-- body sprites of `slot` in the PPU's OAM, and the leftmost/rightmost x

-- press R until the pending boost reads `level`, as a player who sees the
-- press not take presses again.  Ot6Boost samples the held buttons once per
-- battle main-loop tick, and the main loop can stall for several frames
-- (an enemy's turn being worked out), so a single short press can fall
-- inside a stall and be missed: kolts_cave's regenerated fight did that to
-- a 6-frame press (qualification, v0.32 #445).  Each attempt is a 6-frame
-- hold and a 10-frame release; the boost is only ever raised one step.
local function raiseTo(level)
  local ph = 0
  return H.driveUntil(function() return pend(actor) == level end, 600, {
    H.call(function()
      if pend(actor) > level then
        error(string.format("R raised the boost past %d (now %d)", level, pend(actor)), 0)
      end
      H.setPad(ph % 16 < 6 and { r = true } or {})
      ph = ph + 1
    end),
  }, "R raises the boost to " .. level)
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),
  (function()
    local waited, lane = 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      if H.battleLoadStarted() then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  -- every menu that opens Defends (right, A) until the first character to
  -- open one holds 3 BP (1 at the open + 1 per unboosted action) with its
  -- command window up again
  (function()
    local ph = 0
    return H.driveUntil(function()
      if H.readByte(MENU) == 0 then return false end
      local a = H.readByte(ACTOR) & 3
      if actor == nil then actor = a; H.log("boosting slot " .. a) end
      return a == actor and bp(a) >= 3 and H.readByte(MSTATE) == 0x05
    end, 20000, {
      H.call(function()
        ph = ph + 1
        if H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        else
          local step = ph % 40
          if step < 4 then H.setPad({ right = true })
          elseif step >= 20 and step < 24 then H.setPad({ a = true })
          else H.setPad({}) end
        end
      end),
    }, "the first actor banks 3 BP by Defending")
  end)(),
  H.release(),
  H.waitFrames(30),
  raiseTo(3), H.waitFrames(12),
  H.call(function() H.screenshot("boost_cand0") H.log(string.format("[shot] boost_cand0: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand1") H.log(string.format("[shot] boost_cand1: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand2") H.log(string.format("[shot] boost_cand2: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand3") H.log(string.format("[shot] boost_cand3: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand4") H.log(string.format("[shot] boost_cand4: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand5") H.log(string.format("[shot] boost_cand5: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand6") H.log(string.format("[shot] boost_cand6: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
  H.call(function() H.screenshot("boost_cand7") H.log(string.format("[shot] boost_cand7: slot %d bp %d pend %d state $%02x", actor, bp(actor), pend(actor), H.readByte(MSTATE))) end),
  H.waitFrames(5),
})
