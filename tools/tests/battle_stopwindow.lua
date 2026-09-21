-- @suite savestate=kolts_cave
-- battle_stopwindow.lua -- a Stopped actor's command window is entered,
-- not waited on (#224).
--
-- Brainpan's Smirk on the Floating Continent lands Stop on a member whose
-- command window is open, or whose full gauge opens one before the
-- freeze takes hold, and the engine keeps that window open until the
-- counter clears (lib/ot6.lua, M.windowKept: CheckPlayerAction @091f
-- cancels the menu for Sleep, Berserk and Petrify only).  The driver
-- answered every denied actor's window by pressing nothing, so the party
-- stood still: fc-alcove control seed 0 fight 6 sat 2,276 frames at
-- `menu=01 state=05 actor=2` while SHADOW fell 1050 -> 0.  The fix plans
-- an attack at a kept window -- the command waits in the pending list and
-- fires when Stop clears -- and the window closes for the rest of the
-- party.
--
-- This is a focused mechanism test and stages with sanctioned expedient
-- writes: Stop is POKED onto the actor whose command window is open,
-- in the engine's own shape -- STATUS3 bit 4, the $3AF1 counter at $12
-- (SetStatus_14 @467d) and $3AA0 bit 4 (the gauge hold `_c208c6` leaves
-- after the landing action's AfterAction2) -- because a real Smirk into
-- an open window is a Brainpan's roll on the FC descent, which no fixture
-- near a save point draws on cue.  The battle itself is a natural Mt.
-- Kolts cave encounter paced into from kolts_cave; the driver is the
-- route's own (M.newFightDriver, the walk options).
--
-- Asserted, from the poke frame:
--   1. the driver said the [status] line for it, naming the kept window;
--   2. it planned for the Stopped actor at that window, before Stop
--      cleared, and the plan was an attack, never care;
--   3. the window moved on: another actor's plan came inside 600 frames
--      (stop_stalls.py's stall threshold);
--   4. the entered command executed (ExecCmd with X = the actor's offset)
--      only after Stop cleared -- the engine held it for the counter, as
--      the fix relies on -- and the actor's [status] CLEARED line came
--      first.
-- Negative control: stub M.windowKept to false (the old driver's shape)
-- and 2 goes red -- the actor gets no plan while its window sits open.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE, CMDTBL, BCHID = 0x7BCA, 0x62CA, 0x7BC2, 0x202E, 0x3ED8
local ST1, ST2, ST3, ATBFLAGS, STOP_COUNT = 0x3EE4, 0x3EE5, 0x3EF8, 0x3AA0, 0x3AF1
local ST_CMD, CMD_FIGHT = 0x05, 0x00
local STOP_TICKS = 0x12

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

local function map() return H.mapId() & 0x1ff end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function hasFight(e)
  for row = 0, 3 do
    if H.readByte(CMDTBL + e * 12 + row * 3) == CMD_FIGHT
       and (H.readByte(CMDTBL + e * 12 + row * 3 + 1) & 0x80) == 0 then return true end
  end
  return false
end

local F = nil
local stopped, pokeFrame, pokeLine = nil, nil, nil
local clearedFrame, clearedLine, stallLine = nil, nil, nil
local execFrame, execCmd = nil, nil

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires (the
  -- danger counter accrues per step and rolls the encounter itself)
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
    F = H.newFightDriver("stopwindow", { tactical = true, boost = true, bank = 2,
                                         items = true, healPercent = 50 })
    -- when the party's command executes: which entity, and which command
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xFFFF
      if stopped ~= nil and x == stopped * 2 and execFrame == nil and pokeFrame ~= nil then
        execFrame, execCmd = H.frame, H.readByte(0xB5)
        H.log(string.format("[test] f%d entity %d's command $%02X executes (Stop %s)",
          H.frame, stopped, execCmd,
          clearedFrame and ("cleared at f" .. clearedFrame) or "still on"))
      end
    end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  end),

  -- the driver fights until a command window is open for a member with a
  -- Fight row and a living ally; that member is Stopped in the window
  H.driveUntil(function()
    if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_CMD then return false end
    local e = H.readByte(ACTOR) & 3
    if hp(e) == 0 or maxhp(e) == 0 or not hasFight(e) then return false end
    local allies = 0
    for p = 0, 3 do if p ~= e and hp(p) > 0 and maxhp(p) > 0 then allies = allies + 1 end end
    if allies == 0 then return false end
    -- the poke: Stop in the engine's own shape (see the header)
    H.writeByte(ST3 + e * 2, H.readByte(ST3 + e * 2) | 0x10)
    H.writeByte(STOP_COUNT + e * 2, STOP_TICKS)
    H.writeByte(ATBFLAGS + e * 2, H.readByte(ATBFLAGS + e * 2) | 0x10)
    stopped, pokeFrame, pokeLine = e, H.frame, #lines
    H.log(string.format("[test] f%d Stop poked onto entity %d char %d at its open command "
      .. "window (menu=%02X st=%02X actor=%d atb=%04X $3AA0=%02X counter=%d); %d allies up",
      H.frame, e, H.readByte(BCHID + e * 2), H.readByte(MENU), H.readByte(MSTATE),
      H.readByte(ACTOR) & 3, H.readWord(0x3218 + e * 2), H.readByte(ATBFLAGS + e * 2),
      H.readByte(STOP_COUNT + e * 2), allies))
    return true
  end, 20000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "a member's command window is open with an ally standing"),

  -- ...and keeps fighting until the Stopped member's command has executed
  -- after Stop cleared, or the battle ends
  H.driveUntil(function()
    if not H.battleLoadStarted() then return true end
    if stallLine == nil and H.frame >= pokeFrame + 600 then stallLine = #lines end
    if clearedFrame == nil and (H.readByte(ST3 + stopped * 2) & 0x10) == 0 then
      clearedFrame, clearedLine = H.frame, #lines
      H.log(string.format("[test] f%d Stop cleared on entity %d (%d frames after the poke)",
        H.frame, stopped, H.frame - pokeFrame))
    end
    return execFrame ~= nil and clearedFrame ~= nil and H.frame - execFrame > 120
  end, 12000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "the Stopped member's entered command executes after Stop clears"),

  H.call(function()
    H.setPad({})
    local e = stopped
    -- 1. the [status] line names the kept window
    local statusLine = nil
    for i = pokeLine + 1, #lines do
      if lines[i]:find("%[status%] f%+%d+ entity " .. e .. " char %d+ is under STOP") then
        statusLine = lines[i]; break
      end
    end
    H.assertEq(statusLine ~= nil, true, "the driver said the [status] line for the Stop")
    H.assertEq(statusLine:find("keeps the window it has open NOW", 1, true) ~= nil, true,
      "...naming the window the engine keeps (M.windowKept)")
    -- 2. a plan for the Stopped actor at the kept window -- before Stop
    -- cleared (the log's line order; the driver's plan line carries no
    -- frame, so the clear's own [test] line is the bound) -- and an attack
    local ownPlan, ownKind = nil, nil
    local otherPlan = nil
    for i = pokeLine + 1, #lines do
      local kind = lines[i]:match("actor=" .. e .. " char=%d+ plan=(%S+)")
      if kind and ownPlan == nil then ownPlan, ownKind = i, kind end
      local a = lines[i]:match("actor=(%d) char=%d+ plan=")
      if a and tonumber(a) ~= e and otherPlan == nil then otherPlan = i end
    end
    H.assertEq(ownPlan ~= nil and clearedLine ~= nil and ownPlan < clearedLine, true,
      string.format("the driver planned for the Stopped actor %d at the window the engine "
        .. "kept, before Stop cleared (plan at log line %s, the clear at %s; the old driver "
        .. "pressed nothing there)", e, tostring(ownPlan), tostring(clearedLine)))
    H.assertEq(ownKind ~= "item" and ownKind ~= "heal" and ownKind ~= "summon", true,
      "...and the plan is an attack, not care (plan=" .. tostring(ownKind) .. ")")
    -- 3. the window moved on: another actor planned inside 600 frames
    H.assertEq(otherPlan ~= nil and stallLine ~= nil and otherPlan < stallLine, true,
      string.format("another actor got a plan inside 600 frames of the poke (plan at log "
        .. "line %s, the 600-frame mark at %s): the window moved on", tostring(otherPlan),
        tostring(stallLine)))
    -- 4. the entered command ran only after Stop cleared
    H.assertEq(clearedFrame ~= nil, true, "Stop cleared on its counter")
    H.assertEq(execFrame ~= nil, true, "the Stopped member's command executed")
    H.assertEq(execFrame > clearedFrame, true, string.format("...after Stop cleared (exec f%d, "
      .. "cleared f%d): the engine held the entered command for the counter", execFrame or -1,
      clearedFrame or -1))
    H.assertEq(execCmd == CMD_FIGHT or ownKind ~= "fight", true,
      string.format("...and it was the command entered ($%02X for plan=%s)", execCmd or 0xFF, ownKind))
    H.log(string.format("[test] Stop on entity %d: poked f%d, plan=%s, cleared f%d (+%d), "
      .. "command $%02X ran f%d (+%d after the clear)", e, pokeFrame, ownKind, clearedFrame,
      clearedFrame - pokeFrame, execCmd, execFrame, execFrame - clearedFrame))
  end),
})
