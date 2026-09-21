-- @suite savestate=kolts_cave
-- battle_fleesolo.lua -- a lone survivor whose selection window is open
-- still gets away (#245, M.fleePress).
--
-- In Wait mode a selection window stops the battle clock (btlgfx
-- UpdateMenuState_05 `inc $2f41` at the A that opens one; UpdateBattleTime
-- skips its tick while `$2f41 & $3a8f` is set), and the run counter only
-- moves on the tick (CheckRunAway), so M.fleeBattle's held L+R under an
-- open list never rolled: battle_assassinate shift 42 held it 8752 frames
-- with SHADOW the sole survivor.  The fix is what a person does -- B out
-- of the window, L+R held throughout.  The command window itself runs
-- the clock (`stz $2f41` at its entry) and is measured here too.
--
-- This is a focused mechanism test and stages with sanctioned expedient
-- writes: at a member's open Item list the other two are POKED dead (HP
-- 0 and STATUS1 $80, the pair the engine's own death leaves; battle_
-- healerdown's shape), because a natural double death under an open list
-- is a roll no fixture near a save point makes on cue.  The battle is a
-- natural Mt. Kolts cave encounter paced into from kolts_cave; a draw the
-- engine refuses to run from ($b1 bit 1, the same read as lib/ot6_field's
-- flee) is fought out with the route's own driver and the next is taken.
--
-- From one snapshot of that moment, three drives:
--   1. the old shape (L+R only) for 1800 frames: the battle is still up
--      and nobody ran -- the block is real;
--   2. M.fleeBattle: the battle ends by a run ($3a38, "a character just
--      ran away") with monsters still standing;
--   3. the same corpses with the list closed (B, back to the command
--      window) under the old shape: whether the run rolls there is
--      measured and logged, not assumed.
-- Negative control: stub H.fleePress to the old shape (`return { l = true,
-- r = true }`) and 2 goes red -- the flee step times out.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE, CMDTBL, BCHID = 0x7BCA, 0x62CA, 0x7BC2, 0x202E, 0x3ED8
local ST1, RAN, TIME_STOPPED, WAIT_MODE = 0x3EE4, 0x3A38, 0x2F41, 0x3A8F
local CANT_RUN, NO_LR_RUN, RUNNING, RUN_DIFF = 0x00B1, 0x2F4B, 0x2F45, 0x3A3B
local ST_CMD, ST_ITEM, CMD_ITEM = 0x05, 0x0A, 0x01

local function map() return H.mapId() & 0x1ff end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function itemRow(e)
  for row = 0, 3 do
    if H.readByte(CMDTBL + e * 12 + row * 3) == CMD_ITEM
       and (H.readByte(CMDTBL + e * 12 + row * 3 + 1) & 0x80) == 0 then return row end
  end
  return nil
end
local function refused()
  return (H.readByte(CANT_RUN) & 0x02) ~= 0 or (H.readByte(NO_LR_RUN) & 0x01) ~= 0
end
local function counters()
  return string.format("$2F41=%d $3A8F=%d $2F45=%d diff=%d run=%d,%d,%d,%d $3A38=%02X $B1=%02X",
    H.readByte(TIME_STOPPED), H.readByte(WAIT_MODE), H.readByte(RUNNING), H.readByte(RUN_DIFF),
    H.readByte(0x3D70), H.readByte(0x3D72), H.readByte(0x3D74), H.readByte(0x3D76),
    H.readByte(RAN), H.readByte(CANT_RUN))
end

local F = nil
local survivor, stagedFrame = nil, nil
local snap, loadReq = nil, nil
local ranSeen = {}                    -- arm -> the frame $3A38 first read nonzero
local standingAtEnd = {}              -- arm -> monsters standing when the battle ended

-- the old shape, kept here as the control: L+R while anything stands, for
-- `frames` frames or until the battle ends (a counted drive, not a timeout)
local function oldShape(arm, frames)
  local n = 0
  return H.driveUntil(function()
    n = n + 1
    if H.readByte(RAN) ~= 0 and ranSeen[arm] == nil then ranSeen[arm] = H.frame end
    return not H.battleLoadStarted() or n > frames
  end, frames + 120, {
    H.call(function()
      standingAtEnd[arm] = #H.stageSlots()
      H.setPad({ l = true, r = true })
    end),
  }, "arm " .. arm .. ": the old shape, L+R only")
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires that the
  -- engine lets the party run from; one it refuses is fought out first
  (function()
    local battN, waited, lane, fighting, draws = 0, 0, nil, false, 0
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN == 1 then draws = draws + 1 end
      if battN >= 90 and not fighting then
        if refused() then
          fighting = true
          H.log(string.format("[test] draw %d refuses the run (%s) -- fighting it out, "
            .. "then the next draw", draws, counters()))
        else
          H.log(string.format("[test] draw %d can be run from (%s)", draws, counters()))
          H.setPad({})
          return true
        end
      end
      if fighting and battN == 0 then fighting = false; F.idle() end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 60000
    end, 60600, {
      H.call(function()
        if fighting then F.frame() return end
        if H.battleLoadStarted() then H.setPad({}) return end
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
    }, "a runnable cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(function()
    F = H.newFightDriver("fleesolo", { tactical = true, boost = true, bank = 2,
                                       items = true, healPercent = 50 })
    H.assertEq(H.readByte(WAIT_MODE), 1, "the config is Wait mode ($3A8F), where a "
      .. "selection window stops the clock")
  end),

  -- the driver fights until a member's command window is open with two
  -- allies standing; then the Item row is taken (the list opens) and the
  -- allies are poked dead under it
  (function()
    local phase, row = 0, nil
    return H.driveUntil(function()
      if H.readByte(MENU) == 0 then return false end
      local e = H.readByte(ACTOR) & 3
      local st = H.readByte(MSTATE)
      if survivor == nil then
        if st ~= ST_CMD or hp(e) == 0 or maxhp(e) == 0 then return false end
        local allies = 0
        for p = 0, 3 do if p ~= e and hp(p) > 0 and maxhp(p) > 0 then allies = allies + 1 end end
        if allies < 1 then return false end
        row = itemRow(e)
        if row == nil then return false end
        survivor = e
        H.log(string.format("[test] f%d entity %d char %d holds the command window; "
          .. "steering to its Item row %d", H.frame, e, H.readByte(BCHID + e * 2), row))
        return false
      end
      if st ~= ST_ITEM then return false end
      -- the list is open: the corpses (see the header)
      for p = 0, 3 do
        if p ~= survivor and maxhp(p) > 0 then
          H.writeWord(0x3BF4 + p * 2, 0)
          H.writeByte(ST1 + p * 2, H.readByte(ST1 + p * 2) | 0x80)
        end
      end
      stagedFrame = H.frame
      H.log(string.format("[test] f%d staged: entity %d alone at its open Item list "
        .. "(menu=%02X st=%02X), the others at 0 HP; %s; %d monster(s) standing",
        H.frame, survivor, H.readByte(MENU), st, counters(), #H.stageSlots()))
      return true
    end, 20000, {
      H.call(function()
        if survivor == nil then F.frame() return end
        -- one press per 8 frames: down/up to the Item row, then A
        phase = (phase + 1) % 8
        local st = H.readByte(MSTATE)
        if st ~= ST_CMD or phase >= 4 then H.setPad({}) return end
        local cur = H.readByte(0x890F + survivor) & 3
        if cur == row then H.setPad({ "a" })
        else H.setPad({ cur < row and "down" or "up" }) end
      end),
      H.waitFrames(1),
    }, "a member's Item list is open with allies standing")
  end)(),
  H.call(function()
    H.setPad({})
    snap = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the staged moment") end),

  -- 1. the old shape under the open list: the block
  oldShape(1, 1800),
  H.call(function()
    H.log(string.format("[test] arm 1 (old shape, list open) after 1800 frames: battle=%s "
      .. "ran=%s standing=%d %s", tostring(H.battleLoadStarted()), tostring(ranSeen[1]),
      #H.stageSlots(), counters()))
    H.assertEq(H.battleLoadStarted() and ranSeen[1] == nil, true,
      "1. L+R alone under the open list for 1800 frames: nobody ran and the battle is "
      .. "still up -- the clock is stopped ($2F41) and the run counter never moves")
  end),

  -- 2. M.fleeBattle from the same moment
  H.call(function() loadReq = H.requestLoadState(snap.blob) end),
  H.waitFrames(2),
  H.call(function() H.checkReq(loadReq, "reload the staged moment for arm 2") end),
  H.waitFrames(2),
  (function()
    local flee = H.fleeBattle(6000)
    return H.driveUntil(function()
      if H.readByte(RAN) ~= 0 and ranSeen[2] == nil then ranSeen[2] = H.frame end
      if H.battleLoadStarted() then standingAtEnd[2] = #H.stageSlots() end
      return not H.battleLoadStarted()
    end, 6000, { flee }, "arm 2: M.fleeBattle from the staged moment")
  end)(),
  H.call(function()
    H.log(string.format("[test] arm 2 (M.fleeBattle) at f%d: battle=%s ran at %s, %d standing "
      .. "as it ended", H.frame, tostring(H.battleLoadStarted()), tostring(ranSeen[2]),
      standingAtEnd[2] or -1))
    H.assertEq(not H.battleLoadStarted(), true,
      "2. M.fleeBattle got the lone survivor out from under the open list")
    H.assertEq(ranSeen[2] ~= nil, true,
      "2. ...by a run ($3A38 read nonzero), not a win")
    H.assertEq((standingAtEnd[2] or 0) > 0, true,
      "2. ...with the monsters still standing as the battle ended")
  end),

  -- 3. the command window itself: back out of the list (B), then the old
  -- shape -- measured
  H.call(function() loadReq = H.requestLoadState(snap.blob) end),
  H.waitFrames(2),
  H.call(function() H.checkReq(loadReq, "reload the staged moment for arm 3") end),
  H.waitFrames(2),
  (function()
    local phase = 0
    return H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
    end, 600, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "b" } or {})
      end),
    }, "arm 3: B back to the command window")
  end)(),
  H.call(function()
    H.setPad({})
    H.log(string.format("[test] arm 3 at the command window: %s", counters()))
  end),
  oldShape(3, 3000),
  H.call(function()
    H.setPad({})
    H.log(string.format("[test] arm 3 (old shape at the command window) after up to 3000 "
      .. "frames: battle=%s ran=%s standing=%s %s -- measured, not assumed: the command "
      .. "window %s the run", tostring(H.battleLoadStarted()), tostring(ranSeen[3]),
      tostring(standingAtEnd[3]), counters(),
      ranSeen[3] and "does not block" or "also blocks"))
    H.log(string.format("[test] fleesolo: staged f%d; arm 1 no run in 1800 frames; arm 2 ran at "
      .. "f%s; arm 3 %s", stagedFrame, tostring(ranSeen[2]),
      ranSeen[3] and ("ran at f" .. ranSeen[3]) or "no run in 3000 frames"))
  end),
})
