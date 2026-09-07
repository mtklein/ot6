-- @manual
-- probe_forest_bridge.lua -- cross the Phantom Forest corridor bridge (map
-- 132, the (16,8) bridge tile and its z-transition aprons) with random
-- encounters LIVE, fought, many times, and measure what happens after
-- each battle ends: does the field release the party (issue #147)?
--
-- v0.16 shipped an encounter-suppression rectangle over the bridge
-- (Ot6AllowSubBattle, ot6_break.asm) authored against a stall measured
-- once on the pre-3fffb2a ROM; this instrument is the re-examination on
-- the ROM with the rectangle removed.  Read-only: pad presses, RAM reads,
-- read-only exec observers, and whole-machine snapshots (H.requestSaveState
-- / H.requestLoadState -- the policy's snapshot-and-branch).
--
-- Ancestry: camp_escaped (the generated fixture) -> world walk to the
-- forest entrance (178,82) -> map 132 (1,9).  That corridor-entry machine
-- state is captured ONCE and every attempt restores it and then varies the
-- play legitimately: a different idle count before the first step and a
-- different amount of pacing in the west corridor before the bridge, then
-- LAPS laps across the bridge between (12,9) and (20,9), then the real
-- crossing to map 133 the way gen_sabin_forest does it.  Every encounter
-- is fought by navTo's tactical driver (FIGHT_NOT_FLEE); every outcome is
-- logged and kept.
--
-- Copies of this file with the VARIANT/ATTEMPTS/LAPS constants rewritten
-- run in parallel (each run.sh invocation is isolated).
local H = dofile("tools/tests/lib/ot6.lua")

local VARIANT = 0        -- rewritten per parallel copy
local ATTEMPTS = 4       -- attempts per run
local LAPS = 2           -- corridor laps (12,9)<->(20,9) before the crossing
local SHORT = 8          -- bridge laps (13,8)<->(18,8): 4 of the 5 tiles are
                         -- inside the retired rectangle, so most of their
                         -- encounters roll ON the bridge structure
local STALL_FRAMES = 3000  -- no observable progress for this long = stall

local DOOR = "build/states/camp_escaped.mss.lua"
local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function evpc()
  return H.readByte(0xE7) * 65536 + H.readByte(0xE6) * 256 + H.readByte(0xE5)
end
local function rngCols()
  return string.format("$1f6d=%02X $1f6e=%02X $1f6f=%02X $be=%02X",
    H.readByte(0x1f6d), H.readByte(0x1f6e), H.readByte(0x1f6f), H.readByte(0xbe))
end
local function fieldHp()
  -- party slots -> character ids ($1850 bits 0-2 = slot+1 when in party)
  local s = {}
  for c = 0, 15 do
    if inParty(c) then s[#s + 1] = string.format("c%d:%d", c, H.charHp(c)) end
  end
  return table.concat(s, ",")
end

-- read-only exec observers on the win path: WinBattle is jsr'd from the
-- normal end-of-battle path AND from Ot6ShadowLeaves (the 1/16 roll's
-- body, a no-op by design since 3fffb2a), so wins = WinBattle execs and
-- passed Shadow rolls = Ot6ShadowLeaves execs.  TerminateBattle = any end.
local CNT = { win = 0, shadow = 0, term = 0 }
emu.addMemoryCallback(function() CNT.win = CNT.win + 1 end,
  emu.callbackType.exec, H.sym("WinBattle"))
emu.addMemoryCallback(function() CNT.shadow = CNT.shadow + 1 end,
  emu.callbackType.exec, H.sym("Ot6ShadowLeaves"))
emu.addMemoryCallback(function() CNT.term = CNT.term + 1 end,
  emu.callbackType.exec, H.sym("TerminateBattle"))

local function dumpControl(tag)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) ctl=%s aligned=%s evt=%s dlg=%s | $087C=%02X " ..
    "$1EB9=%02X evtPC=%06X $0084=%02X $0059=%02X $BA=%02X $D3=%02X " ..
    "batt=%s mons=%d $3A76=%02X $3A77=%02X bright=%d hp=%s",
    tag, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    H.readByte(0x087C), H.readByte(0x1EB9), evpc(),
    H.readByte(0x0084), H.readByte(0x0059), H.readByte(0xBA),
    H.readByte(0xD3), tostring(H.battleLoadStarted()), H.monstersPresent(),
    H.readByte(0x3A76), H.readByte(0x3A77), bright(), fieldHp()))
end

-- per-attempt bookkeeping
local A = nil
local function newAttempt(n, idle, prewalk)
  A = { n = n, idle = idle, prewalk = prewalk, t0 = H.frame,
        battles = 0, wins = 0, term = 0, shadow = 0, losses = 0,
        stall = false, stallWhat = nil, inBattle = false, bStart = 0,
        bTile = nil, gil0 = 0, win0 = 0, shadow0 = 0, term0 = 0,
        endedAt = nil, lastProg = H.frame, sig = nil, lastDump = 0,
        bridgeBattles = 0, maxRelease = 0,
        visits = {}, lastTile = nil, rectSteps = 0, bridgeSteps = 0 }
end

-- the arrive thunk shared by every navTo of an attempt: watches each
-- battle from its rise to the field's release, and trips the stall flag
-- when nothing observable changes for STALL_FRAMES.
local function inRect(x, y) return x >= 14 and x <= 17 and y >= 8 and y <= 9 end
local function watch(goal)
  return function()
    if goal() then return true end
    local batt = H.battleLoadStarted()
    -- tile visits (a landing = aligned on a tile different from the last
    -- one), so the summary can prove the bridge tile itself was stepped
    if not batt and mapIdx() == 132 and H.tileAligned() then
      local k = H.fieldX() * 256 + H.fieldY()
      if k ~= A.lastTile then
        A.lastTile = k
        A.visits[k] = (A.visits[k] or 0) + 1
        if inRect(H.fieldX(), H.fieldY()) then A.rectSteps = A.rectSteps + 1 end
        if H.fieldX() == 16 and H.fieldY() == 8 then A.bridgeSteps = A.bridgeSteps + 1 end
      end
    end
    if batt and not A.inBattle then
      A.inBattle = true
      A.battles = A.battles + 1
      A.bStart = H.frame
      A.bTile = { H.fieldX(), H.fieldY() }
      A.gil0, A.win0, A.shadow0, A.term0 = H.gil(), CNT.win, CNT.shadow, CNT.term
      if inRect(A.bTile[1], A.bTile[2]) then A.bridgeBattles = A.bridgeBattles + 1 end
      H.log(string.format("[bridge] a%d battle #%d up f%d at (%d,%d)%s %s",
        A.n, A.battles, H.frame, A.bTile[1], A.bTile[2],
        inRect(A.bTile[1], A.bTile[2]) and " IN-RECT" or "", rngCols()))
    elseif A.inBattle and not batt then
      -- the HP table left the battle shape: battle over (won, or wiped:
      -- the canary's all-zero shape), the field is reloading
      A.inBattle = false
      A.endedAt = H.frame
      local dw, ds, dt = CNT.win - A.win0, CNT.shadow - A.shadow0, CNT.term - A.term0
      A.wins = A.wins + dw
      A.shadow = A.shadow + ds
      A.term = A.term + dt
      H.log(string.format("[bridge] a%d battle #%d down f%d (%d frames) at (%d,%d)%s: " ..
        "WinBattle+%d ShadowLeaves+%d TerminateBattle+%d gil %d->%d hp=%s",
        A.n, A.battles, H.frame, H.frame - A.bStart, A.bTile[1], A.bTile[2],
        inRect(A.bTile[1], A.bTile[2]) and " IN-RECT" or "",
        dw, ds, dt, A.gil0, H.gil(), fieldHp()))
    end
    if A.endedAt and H.hasControl() then
      local rel = H.frame - A.endedAt
      if rel > A.maxRelease then A.maxRelease = rel end
      H.log(string.format("[bridge] a%d battle #%d released f%d: control back " ..
        "%d frames after the HP table cleared, at (%d,%d) evpc=%06X",
        A.n, A.battles, H.frame, rel, H.fieldX(), H.fieldY(), evpc()))
      A.endedAt = nil
    end
    -- dense watch through the post-battle window (the wedge, if it forms,
    -- forms here) -- every 60 frames until control is back
    if A.endedAt and H.frame - A.lastDump >= 60 then
      A.lastDump = H.frame
      dumpControl("post")
    end
    -- progress signature: anything a live game changes
    local hp = H.partyHp()
    local sig = string.format("%d,%d,%d,%s,%s,%d,%d,%d,%d,%02X,%02X,%06X,%d,%d",
      mapIdx(), H.fieldX(), H.fieldY(), tostring(H.hasControl()), tostring(batt),
      hp[1], hp[2], hp[3], hp[4], H.readByte(0x3A76), H.readByte(0x3A77), evpc(),
      H.monstersPresent(), H.readByte(0x087C))
    if not batt then
      -- out of battle nothing moves while a menu is open (care stop), so
      -- fold the menu cursor and the gil/tonic counts in too
      sig = sig .. string.format(",%d,%02X,%02X", H.gil(), H.readByte(0x0200), H.readByte(0x0201))
    else
      -- in battle: monster hp words and the command-menu state
      local m = {}
      for s = 0, 5 do m[#m + 1] = H.readWord(0x3BFC + 8 + s * 2) end
      sig = sig .. string.format(",%d,%d,%d,%d,%d,%d,%02X,%02X,%02X",
        m[1], m[2], m[3], m[4], m[5], m[6],
        H.readByte(0x7B), H.readByte(0x7C), H.readByte(0x3A7B))
    end
    if sig ~= A.sig then A.sig = sig; A.lastProg = H.frame end
    if H.frame - A.lastProg > STALL_FRAMES then
      A.stall = true
      A.stallWhat = string.format("no observable progress for %d frames (sig %s)",
        H.frame - A.lastProg, sig)
      return true
    end
    return false
  end
end

local function navWatched(tx, ty, goal, what, budget)
  return H.navTo(tx, ty, { maxFrames = budget or 12000, playBattles = "tactical",
    wipeEndsRide = true, arrive = watch(goal) })
end

local function attemptStep(n)
  -- variation: idle frames before the first step, and pacing pairs in the
  -- west corridor.  Both are ordinary human play.
  local idle = ((VARIANT * 7 + n * 13) % 23) * 9
  local prewalk = (VARIANT + n) % 4
  local stallBlob = nil
  local steps = {
    H.call(function()
      newAttempt(n, idle, prewalk)
      H.log(string.format("[bridge] === attempt %d (variant %d) idle=%d prewalk=%d f%d " ..
        "map=%d (%d,%d) %s gil=%d hp=%s shadow=%s",
        n, VARIANT, idle, prewalk, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
        rngCols(), H.gil(), fieldHp(), tostring(inParty(3))))
    end),
    H.waitFrames(idle),
  }
  for k = 1, prewalk do
    steps[#steps + 1] = navWatched(6, 9, function() return A.stall end, "prewalk out")
    steps[#steps + 1] = navWatched(2, 9, function() return A.stall end, "prewalk back")
  end
  for lap = 1, LAPS do
    steps[#steps + 1] = H.logStep(function()
      return string.format("[bridge] a%d lap %d east from (%d,%d) f%d", n, lap,
        H.fieldX(), H.fieldY(), H.frame)
    end)
    steps[#steps + 1] = navWatched(20, 9, function() return A.stall end, "lap east")
    steps[#steps + 1] = H.logStep(function()
      return string.format("[bridge] a%d lap %d west from (%d,%d) f%d", n, lap,
        H.fieldX(), H.fieldY(), H.frame)
    end)
    steps[#steps + 1] = navWatched(12, 9, function() return A.stall end, "lap west")
  end
  for lap = 1, SHORT do
    steps[#steps + 1] = H.logStep(function()
      return string.format("[bridge] a%d short lap %d from (%d,%d) f%d", n, lap,
        H.fieldX(), H.fieldY(), H.frame)
    end)
    steps[#steps + 1] = navWatched(18, 8, function() return A.stall end, "short east")
    steps[#steps + 1] = navWatched(13, 8, function() return A.stall end, "short west")
  end
  -- the real crossing, as gen_sabin_forest's crossTo(28,7,133)
  steps[#steps + 1] = H.logStep(function()
    return string.format("[bridge] a%d crossing 132->133 from (%d,%d) f%d", n,
      H.fieldX(), H.fieldY(), H.frame)
  end)
  steps[#steps + 1] = navWatched(28, 7, function() return A.stall or mapIdx() == 133 end,
    "crossing", 16000)
  steps[#steps + 1] = H.cond(function() return A.stall end, {
    -- STALL: autopsy window with a neutral pad, then a whole-machine
    -- snapshot for the report (H.saveState -> build/states/)
    H.call(function()
      H.log(string.format("[bridge] a%d STALL f%d: %s", n, H.frame, A.stallWhat))
      dumpControl("stall")
    end),
    (function()
      local t1
      return H.driveUntil(function()
        if not t1 then t1 = H.frame end
        return H.frame - t1 > 1100
      end, 2400, {
        H.call(function()
          if H.frame - A.lastDump >= 120 then A.lastDump = H.frame; dumpControl("autopsy") end
          H.setPad({})
        end),
      }, "post-stall autopsy window")
    end)(),
    H.saveState(string.format("forest_bridge_stall_v%d_a%d.mss", VARIANT, n)),
  }, {
    H.call(function()
      H.assertEq(mapIdx(), 133, string.format("a%d crossed to map 133", n))
    end),
  })
  steps[#steps + 1] = H.call(function()
    if not A.stall and mapIdx() ~= 133 then A.losses = A.losses + 1 end
    local nTiles = 0
    for _ in pairs(A.visits) do nTiles = nTiles + 1 end
    H.log(string.format("[bridge] --- attempt %d summary: variant=%d idle=%d prewalk=%d " ..
      "frames=%d battles=%d in_rect=%d wins=%d shadow_rolls=%d terminated=%d " ..
      "wiped=%d stall=%s max_release=%d bridge_steps=%d rect_steps=%d tiles=%d " ..
      "end map=%d (%d,%d) shadow_aboard=%s hp=%s",
      n, VARIANT, idle, prewalk, H.frame - A.t0, A.battles, A.bridgeBattles,
      A.wins, A.shadow, A.term, A.losses, tostring(A.stall), A.maxRelease,
      A.bridgeSteps, A.rectSteps, nTiles,
      mapIdx(), H.fieldX(), H.fieldY(), tostring(inParty(3)), fieldHp()))
  end)
  return H.cond(function() return true end, steps, {})
end

local entry = nil
local plan = {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "start on the World of Balance")
    H.log(string.format("[bridge] start world (%d,%d) f%d party sabin=%s cyan=%s shadow=%s %s",
      H.worldX(), H.worldY(), H.frame, tostring(inParty(5)), tostring(inParty(2)),
      tostring(inParty(3)), rngCols()))
  end),
  H.worldNavTo(178, 82, { maxFrames = 25000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function()
    return mapIdx() == 132 and H.hasControl() and H.tileAligned()
  end, 4000, "map 132 control", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "map 132 fade", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 132, "entered Phantom Forest map 132")
    H.log(string.format("[bridge] corridor entry at (%d,%d) f%d %s gil=%d hp=%s -- snapshot",
      H.fieldX(), H.fieldY(), H.frame, rngCols(), H.gil(), fieldHp()))
    -- tile-property truth for the corridor, x 1..28, y 7..11 (the walker
    -- also uses the z-1 floor under the bridge, (16,9)->(15,10))
    for y = 7, 11 do
      local row = {}
      for x = 1, 28 do
        local tile = H.maptile(x, y)
        row[#row + 1] = string.format("%d:%02X/%02X", x,
          H.readByte(0x7E7600 + tile), H.readByte(0x7E7700 + tile))
      end
      H.log(string.format("[props y=%d] %s", y, table.concat(row, " ")))
    end
    entry = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(entry, "corridor-entry snapshot")
    H.log(string.format("[bridge] corridor-entry snapshot captured f%d (%d bytes)",
      H.frame, #entry.blob))
  end),
}
for n = 1, ATTEMPTS do
  if n > 1 then
    local req
    plan[#plan + 1] = H.call(function()
      H.log(string.format("[bridge] restoring corridor-entry snapshot for attempt %d f%d", n, H.frame))
      req = H.requestLoadState(entry.blob)
    end)
    plan[#plan + 1] = H.waitFrames(2)
    plan[#plan + 1] = H.call(function()
      H.checkReq(req, "corridor-entry restore")
      H.assertEq(mapIdx(), 132, "restored on map 132")
    end)
    plan[#plan + 1] = H.waitFrames(10)
  end
  plan[#plan + 1] = attemptStep(n)
end
plan[#plan + 1] = H.logStep(function()
  return string.format("[bridge] run done f%d: WinBattle=%d ShadowLeaves=%d TerminateBattle=%d",
    H.frame, CNT.win, CNT.shadow, CNT.term)
end)

H.run({ maxFrames = 900000 }, plan)
