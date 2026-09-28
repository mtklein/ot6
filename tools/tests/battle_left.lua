-- @suite savestate=kolts_cave
-- battle_left.lua -- the fight driver's care lines and a member who LEFT the
-- battle (#255, H.leftMask).
--
-- A member sneezed away (the Chitonid's and the Baskervor's Sneeze), who
-- ran, or who threw a Smoke Bomb keeps its HP and its seat's words, but its
-- bit is up in $3A39 (TargetEffect_27 sets it with the member's $3018 bit)
-- and it is out of the fight.  The driver's care lines -- the heals, the
-- cures, the raises, the one-round price, the party's damage window and
-- the raise rule's top-up race -- read HP and max HP through H.leftMask
-- (lib/ot6.lua makePlan's hpNow / maxOf), so a member who left is never a
-- patient, a corpse or a hand.
--
-- The natural case is rare: across the review's 43 members the Baskervor
-- sneezed out with others still fighting (build/attempts/wt/wor-tzen-door/
-- review-final/wob/off_s*.log) every one left above the heal fraction, and
-- so did the 9 of this change's lab at a 95% fraction, 52 in all
-- (build/attempts/wt/wor-sabin/lab/left/).  So this is a focused mechanism
-- test and stages with sanctioned expedient writes:
--   * the member's bit is POKED into $3A39 in the engine's own shape (the
--     byte TargetEffect_27 writes), so the driver reads it as having left;
--   * its HP is POKED down to a third, the way battle_doom and
--     battle_healerdown hurt their patients, so the heal line has a member
--     it would take at the 60% fraction.
-- The battle is a natural Mt. Kolts cave encounter paced into from
-- kolts_cave; the driver is the route's own.  At the first open command
-- window of a member with an Item row and a Potion or Tonic in the bag,
-- another living member is marked as having left and hurt; then the fight
-- runs for the next two command windows of members still in, and no plan
-- may name the member who left (heal / cure / revive entity N).
-- Negative control: stub H.leftMask to 0 (MUTANT below) and the hurt member
-- is healed at the next window -- the assertion goes red
-- (build/attempts/wt/wor-sabin/lab/left_suite/).
local H = dofile("tools/tests/lib/ot6.lua")
local MUTANT = false
if MUTANT then H.leftMask = function() return 0 end end
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE, CMDTBL, BCHID = 0x7BCA, 0x62CA, 0x7BC2, 0x202E, 0x3ED8
local ST_CMD, CMD_ITEM, LEFT = 0x05, 0x01, 0x3A39

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

local function map() return H.mapId() & 0x1ff end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function hasRow(e, cmd)
  for row = 0, 3 do
    if H.readByte(CMDTBL + e * 12 + row * 3) == cmd
       and (H.readByte(CMDTBL + e * 12 + row * 3 + 1) & 0x80) == 0 then return true end
  end
  return false
end
local function bagHas(id)
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == id and H.readByte(0x2686 + i * 5 + 3) > 0 then return true end
  end
  return false
end

local F = nil
local gone, pokeLine, pokeActor = nil, nil, nil
local windows, lastWin = {}, nil

H.run({ maxFrames = 60000 }, {
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
  H.call(function()
    -- freeRound = "care", as battle_doom: this encounter can open as a
    -- preemptive strike, whose free round defers every top-up one turn
    F = H.newFightDriver("left", { tactical = true, boost = true, bank = 2,
                                   items = true, healPercent = 60,
                                   freeRound = "care" })
  end),

  -- the first open command window of a member with an Item row: another
  -- living member leaves the battle and is hurt to a third
  H.driveUntil(function()
    if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_CMD then return false end
    local e = H.readByte(ACTOR) & 3
    if hp(e) == 0 or maxhp(e) == 0 or not hasRow(e, CMD_ITEM) then return false end
    if not (bagHas(0xE9) or bagHas(0xE8)) then
      error("no Potion or Tonic in the battle bag: nothing for the heal line to offer", 0)
    end
    local c = nil
    for p = 0, 3 do
      if p ~= e and hp(p) > 0 and maxhp(p) > 0 then c = p end
    end
    if c == nil then return false end
    H.writeByte(LEFT, H.readByte(LEFT) | (1 << c))
    H.writeWord(0x3BF4 + c * 2, math.max(1, maxhp(c) // 3))
    gone, pokeLine, pokeActor = c, #lines, e
    H.log(string.format("[test] f%d entity %d char %d marked as having LEFT ($3A39=%02X) and set "
      .. "to %d/%d HP, under the 60%% fraction, at actor %d's open command window%s", H.frame, c,
      H.readByte(BCHID + c * 2), H.readByte(LEFT), hp(c), maxhp(c), e,
      MUTANT and " -- MUTANT: H.leftMask stubbed to 0" or ""))
    return true
  end, 20000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "a member's command window is open with an ally standing"),

  -- the next two command windows of members still in (the poked actor's
  -- own counts: the driver decides it on this window)
  H.driveUntil(function()
    if not H.battleLoadStarted() then return true end
    if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD then
      local e = H.readByte(ACTOR) & 3
      if e ~= gone and lastWin ~= e then
        windows[#windows + 1] = { actor = e, frame = H.frame }
        lastWin = e
      end
    elseif H.readByte(MENU) == 0 then
      lastWin = nil
    end
    return #windows >= 3
  end, 12000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "two more command windows of members still in the fight"),

  H.call(function()
    H.setPad({})
    local planned, named = 0, nil
    for i = pokeLine + 1, #lines do
      local s = lines[i]
      if s:find("char=%d+ plan=") then planned = planned + 1 end
      if named == nil and (s:find("heal entity " .. gone .. " %(") or s:find("cure entity " .. gone .. " %(")
         or s:find("cure entity " .. gone .. "'s") or s:find("revive entity " .. gone .. " ")) then
        named = s
      end
    end
    H.log(string.format("[test] %d command window(s) after the poke, %d plan(s) said; a plan on the "
      .. "member who left: %s", #windows, planned, tostring(named)))
    H.assertEq(planned >= 1, true, "the driver planned at least one turn after the member left")
    H.assertEq(H.readWord(0x3BF4 + gone * 2) > 0 and (H.readByte(LEFT) >> gone) & 1, 1,
      "the member who left is still marked as gone and standing")
    H.assertEq(named, nil, "no heal, cure or raise plan named the member who left the battle")
  end),
})
