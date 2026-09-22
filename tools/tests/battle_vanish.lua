-- @suite savestate=kolts_cave
-- battle_vanish.lua -- the lib reads Vanish and Image off the stage
-- (#190, H.dodges / H.dodgerUp), and a Fight on a Vanished monster lands
-- nothing.
--
-- gen_fc_alcove's Ninja fades out ("Inviz") and every physical action
-- the party owned resolved for 0 while it hit for 220-839 a round; the
-- generator's gate switched TERRA to Fire 2 while a live monster wore
-- Vanish or Image.  That read now lives in the lib -- STATUS1 bit 4
-- ($3EE4) and STATUS2 bit 2 ($3EE5) of each monster in the formation (entity
-- 4 + slot) -- and the generator is its first caller.
--
-- This is a focused mechanism test and stages with sanctioned expedient
-- writes: the status is POKED onto a monster in the formation (the bit is all
-- the engine's status set leaves for these two), because the Ninja's
-- Inviz is on the Floating Continent and no fixture near a save point
-- draws a Vanish on cue.  The battle is a natural Mt. Kolts cave
-- encounter paced into from kolts_cave.
--
-- Asserted:
--   1. H.dodgerUp answers nil on the untouched stage, the slot and
--      "Vanish" under STATUS1 $10, the slot and "Image" under STATUS2
--      $04, "Vanish" when both stand, and nil again once both are off;
--      a dead slot wearing the bit is skipped;
--   2. with Vanish on the one slot the party's next Fight lands on, the
--      driver's damage watch settles that Fight at 0 -- the miss the
--      generator measured, on this ROM, on cue.
-- Negative control: stub H.dodges to nil and 1 goes red.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, MSTATE, ACTOR = 0x7BCA, 0x7BC2, 0x62CA
local ST1, ST2, MON_HP, MON_PRESENT = 0x3EE4, 0x3EE5, 0x3BFC, 0x3AA8
local ST_CMD = 0x05

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

local function map() return H.mapId() & 0x1ff end
local function monAlive(s)
  return H.readWord(MON_HP + s * 2) > 0 and (H.readByte(MON_PRESENT + s * 2) & 1) == 1
end
local function setBit(addr, bit, on)
  local v = H.readByte(addr)
  H.writeByte(addr, on and (v | bit) or (v & ~bit))
end

local F = nil
local vanished, pokeLine = nil, nil

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
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
  H.waitFrames(120),

  -- 1. the read, on the live stage
  H.call(function()
    local slots = {}
    for s = 0, 5 do if monAlive(s) then slots[#slots + 1] = s end end
    H.assertEq(#slots >= 1, true, "a monster is in the formation")
    local s = slots[1]
    local e = 4 + s
    H.assertEq(H.dodgerUp(), nil, "the untouched stage: nothing dodges")
    setBit(ST1 + e * 2, 0x10, true)
    local got, what = H.dodgerUp()
    H.assertEq(got, s, "STATUS1 $10 on slot " .. s .. ": H.dodgerUp names the slot")
    H.assertEq(what, "Vanish", "...as Vanish")
    setBit(ST2 + e * 2, 0x04, true)
    got, what = H.dodgerUp()
    H.assertEq(what, "Vanish", "both bits: Vanish is named first")
    setBit(ST1 + e * 2, 0x10, false)
    got, what = H.dodgerUp()
    H.assertEq(got, s, "STATUS2 $04 alone: the slot")
    H.assertEq(what, "Image", "...as Image")
    setBit(ST2 + e * 2, 0x04, false)
    H.assertEq(H.dodgerUp(), nil, "both off: nothing dodges again")
    -- a slot with no body on it is skipped even with the bit set: the
    -- status cells are not cleared between battles (gen_fc_alcove's
    -- stage note), so a stale bit on an empty slot must not read as a
    -- dodger
    local empty = nil
    for s2 = 0, 5 do if not monAlive(s2) then empty = s2; break end end
    if empty ~= nil then
      setBit(ST1 + (4 + empty) * 2, 0x10, true)
      H.assertEq(H.dodgerUp(), nil, "a Vanish bit on empty slot " .. empty .. " is not a dodger")
      setBit(ST1 + (4 + empty) * 2, 0x10, false)
    else
      H.log("[test] every slot is occupied; the empty-slot case is not staged here")
    end
    H.log("[test] H.dodgerUp read Vanish and Image off slot " .. s .. " and nothing off the bare stage")
    -- 2. Vanish on every living slot, so whichever the party's Fight
    -- lands on is a miss (the poke is the bit alone: SetStatus for
    -- Vanish/Image writes nothing else the driver reads)
    for _, s3 in ipairs(slots) do setBit(ST1 + (4 + s3) * 2, 0x10, true) end
    vanished, pokeLine = slots, #lines
    F = H.newFightDriver("vanish", { tactical = true, boost = true, bank = 2,
                                     items = true, healPercent = 50 })
  end),

  -- the driver fights until a party Fight has been settled by its damage
  -- watch (the "took N off the monsters" line), or the battle ends
  H.driveUntil(function()
    if not H.battleLoadStarted() then return true end
    for i = pokeLine + 1, #lines do
      if lines[i]:find("'s fight took %d+ off the monsters") then return true end
    end
    return false
  end, 12000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "a party Fight settles on the Vanished stage"),

  H.call(function()
    H.setPad({})
    local took = nil
    for i = pokeLine + 1, #lines do
      local n = lines[i]:match("'s fight took (%d+) off the monsters")
      if n then took = tonumber(n); break end
    end
    H.assertEq(took ~= nil, true, "a party Fight settled while every slot wore Vanish")
    H.assertEq(took, 0, "...and it took 0 off the monsters: the miss the generator measured")
    for _, s3 in ipairs(vanished) do setBit(ST1 + (4 + s3) * 2, 0x10, false) end
    H.log("[test] a Fight on a Vanished monster took " .. took .. "; Vanish cleared")
  end),
})
