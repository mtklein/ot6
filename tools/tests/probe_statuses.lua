-- @manual
-- probe_statuses.lua -- how the fight driver sees a turn-denying status
-- (#187): Stop ($3EF8 bit 4), Sleep ($3EE5 bit 7), Berserk ($3EE5 bit 4)
-- and Imp ($3EE4 bit 5), reached where the route offers them and fought
-- by the route's own driver (navTo's playBattles="tactical", i.e.
-- M.newFightDriver with the walk options).  Nothing is written; the
-- fights are ordinary randoms rolled by walking, and the probe PASSes
-- whatever it sees -- it measures, it does not assert.
--
-- Sources (monster_prop +31 special byte, decoded per battle_main.asm
-- @3318: effect < $20 is a status index; audit_encounters for the pools):
--   train   forest_done, map 145: Whisper ($00E) special $45 = Imp,
--           no damage; in 3 of the 4 pool slots
--   zozo    zozo_clock_solved, map 225: SlamDancer ($052) special $4F =
--           Sleep; in 3 of 4 slots
--   forest  camp_escaped -> world (178,82) -> map 132: Ghost ($05A)
--           special $54 = Stop; in every slot
-- Berserk has no random source before the Esper Mountain (Insecare, map
-- 372-374, three hops past the save room); Telstar's MEGAZERK is a
-- Blitz retaliation the route never fights.  It is not probed live.
--
-- Run one mode (the token is substituted, probe_muddle_n024's shape):
--   sed 's/@WHICH@/train/' tools/tests/probe_statuses.lua > build/probe_statuses_train.lua
--   tools/tests/run.sh build/probe_statuses_train.lua build/states/probe_statuses_train.log
--
-- Read-only observers, on a startFrame callback so they ride under
-- navTo's own fighting:
--   [status]  any of a party member's four status bytes changing, with
--             the frame, the battle tick, and which of the four statuses
--             landed or cleared;
--   [landed]  the moment one lands: the ATB gauge ($3218,e*2) and its
--             $3AA0 flags, the menu byte $7BCA, the menu state $7BC2, the
--             actor holding the window ($62CA) and the command rows'
--             flags ($202E: bit 7 = disabled), so "did it land in an
--             open window" and "which rows went grey" are on the record;
--   [denied]  every 120 frames while it stands: the same cells, plus
--             whether that entity's window has opened since;
--   [window]  the first time the window opens for an entity under one;
--   [cleared] when it clears: how long it stood, windows opened under it,
--             and what the driver did meanwhile (its own [navTo] lines
--             are in the log between the two).
-- The [result] line counts, per status: landings, landings into that
-- actor's own open window, windows opened under it, and frames stood.
local H = dofile("tools/tests/lib/ot6.lua")

local WHICH = "@WHICH@"
if WHICH:sub(1, 1) == "@" then WHICH = "train" end

local MENU, MSTATE, ACTOR, CMDTBL, BCHID = 0x7BCA, 0x7BC2, 0x62CA, 0x202E, 0x3ED8
local ATB, ATBFLAGS = 0x3218, 0x3AA0
local S1, S2, S3, S4 = 0x3EE4, 0x3EE5, 0x3EF8, 0x3EF9
-- name -> { byte base, bit }
local WATCH = {
  { name = "Imp", base = S1, bit = 0x20 },
  { name = "Berserk", base = S2, bit = 0x10 },
  { name = "Muddle", base = S2, bit = 0x20 },
  { name = "Sleep", base = S2, bit = 0x80 },
  { name = "Stop", base = S3, bit = 0x10 },
}

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function st4(e)
  return H.readByte(S1 + e * 2), H.readByte(S2 + e * 2),
         H.readByte(S3 + e * 2), H.readByte(S4 + e * 2)
end
local function cmdFlags(e)
  local t = {}
  for row = 0, 3 do
    t[#t + 1] = string.format("%02X:%02X", H.readByte(CMDTBL + e * 12 + row * 3),
      H.readByte(CMDTBL + e * 12 + row * 3 + 1))
  end
  return table.concat(t, ",")
end
local function cells(e)
  return string.format("atb=%04X $3AA0=%02X menu=%02X st=%02X actor=%d cmds=%s hp=%d",
    H.readWord(ATB + e * 2), H.readByte(ATBFLAGS + e * 2), H.readByte(MENU),
    H.readByte(MSTATE), H.readByte(ACTOR) & 3, cmdFlags(e), hp(e))
end

-- tallies per status name
local R = {}
for _, w in ipairs(WATCH) do
  R[w.name] = { landed = 0, intoOwnWindow = 0, windows = 0, frames = 0, longest = 0 }
end
local live = {}                        -- e -> { name -> { since, tick, window } }
local last = {}                        -- e -> { s1, s2, s3, s4 }
local bTick, bUp, fights, seenAny = 0, nil, 0, {}
local fightLog = {}

local function observe()
  if not H.battleLoadStarted() then
    if bUp ~= nil then
      -- the battle ended: close every live entry
      for e, byName in pairs(live) do
        for name, L in pairs(byName) do
          local stood = H.frame - L.since
          R[name].frames = R[name].frames + stood
          if stood > R[name].longest then R[name].longest = stood end
          H.log(string.format("[cleared f%d] entity %d's %s ended with the battle "
            .. "after %d frames (windows opened under it: %d)", H.frame, e, name,
            stood, L.window))
        end
      end
      live, last = {}, {}
      fights = fights + 1
      fightLog[#fightLog + 1] = string.format("#%d:f%d..f%d", fights, bUp, H.frame)
      H.log(string.format("[fight #%d] over at f%d (%d frames)", fights, H.frame,
        H.frame - bUp))
      bUp, bTick = nil, 0
    end
    return
  end
  if bUp == nil then bUp = H.frame end
  bTick = bTick + 1
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local a, b, c, d = st4(e)
      local L = last[e]
      if L ~= nil and (L[1] ~= a or L[2] ~= b or L[3] ~= c or L[4] ~= d) then
        local landed, cleared = {}, {}
        for _, w in ipairs(WATCH) do
          local was = (w.base == S1 and L[1] or w.base == S2 and L[2] or L[3]) & w.bit
          local now = (w.base == S1 and a or w.base == S2 and b or c) & w.bit
          if was == 0 and now ~= 0 then landed[#landed + 1] = w.name end
          if was ~= 0 and now == 0 then cleared[#cleared + 1] = w.name end
        end
        H.log(string.format("[status f%d b+%d] entity %d char %d %02X/%02X/%02X/%02X -> "
          .. "%02X/%02X/%02X/%02X%s%s", H.frame, bTick, e, H.readByte(BCHID + e * 2),
          L[1], L[2], L[3], L[4], a, b, c, d,
          #landed > 0 and (" LANDED " .. table.concat(landed, "+")) or "",
          #cleared > 0 and (" cleared " .. table.concat(cleared, "+")) or ""))
        for _, name in ipairs(landed) do
          live[e] = live[e] or {}
          local own = H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == e
          live[e][name] = { since = H.frame, tick = bTick, window = 0, own = own }
          R[name].landed = R[name].landed + 1
          seenAny[name] = true
          if own then R[name].intoOwnWindow = R[name].intoOwnWindow + 1 end
          H.log(string.format("[landed f%d] %s on entity %d%s: %s", H.frame, name, e,
            own and " INTO ITS OWN OPEN WINDOW" or "", cells(e)))
          pcall(H.screenshot, string.format("status_%s_%s_f%d", WHICH, name, H.frame))
        end
        for _, name in ipairs(cleared) do
          local Lv = live[e] and live[e][name]
          if Lv then
            local stood = H.frame - Lv.since
            R[name].frames = R[name].frames + stood
            if stood > R[name].longest then R[name].longest = stood end
            H.log(string.format("[cleared f%d] %s off entity %d after %d frames "
              .. "(windows opened under it: %d; landed %s): %s", H.frame, name, e,
              stood, Lv.window, Lv.own and "in its own window" or "outside its window",
              cells(e)))
            live[e][name] = nil
          end
        end
      end
      last[e] = { a, b, c, d }
      if live[e] then
        for name, Lv in pairs(live[e]) do
          local open = H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == e
          if open and not Lv.openNow then
            Lv.window = Lv.window + 1
            R[name].windows = R[name].windows + 1
            H.log(string.format("[window f%d] entity %d's window opened under %s "
              .. "(%d frames in, opening #%d): %s", H.frame, e, name,
              H.frame - Lv.since, Lv.window, cells(e)))
          end
          Lv.openNow = open
          if (H.frame - Lv.since) % 120 == 0 then
            H.log(string.format("[denied f%d] entity %d %s for %d frames: %s",
              H.frame, e, name, H.frame - Lv.since, cells(e)))
          end
        end
      end
    end
  end
end

-- how many fights to sit through; the point is to see each source land
-- at least once and watch the driver through the whole fight it lands in
local WANT_FIGHTS = tonumber("@FIGHTS@") or 6
local function enough() return fights >= WANT_FIGHTS end

-- Roll randoms by walking: a direction jitter (probe_throw's shape --
-- every 24 frames the next of the four directions, pressed only while the
-- party is in control and on a tile, so no map geometry is assumed) with
-- the route's own walk fighter (M.newWalkFighter: newFightDriver with the
-- walk options, plus the between-battles care stop, so a status that
-- persists out of battle -- Imp -- meets fieldCare's cure the way it
-- does on the route).
-- SLOW=1: a plainer, still plausible policy -- unboosted Fights, no
-- tools or blitzes, Potions under 45% -- so the caster lives to the
-- script line its SPECIAL sits on (Ghost's is after a `wait`,
-- SlamDancer's after two; the walk options killed most casters on their
-- first turn: 19 Ghost fights on camp_escaped's forest walk drew none).
local SLOW = "@SLOW@" == "1"
local function slowFighter(tag)
  local F = H.newFightDriver(tag, { tactical = false, boost = false, items = true,
    healPercent = 45 })
  local battN, fought, careD, settleN = 0, 0, nil, nil
  local function settled()
    if (emu.getState()["ppu.screenBrightness"] or 0) < 15 then return false end
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end
  local W = {}
  function W.frame()
    if careD then
      careD.frame()
      if careD.done() then careD = nil end
      return true
    end
    if H.battleLoadStarted() then
      battN = battN + 1
      F.frame()
      return true
    end
    if battN > 0 then
      F.idle()
      battN, fought, settleN = 0, fought + 1, 0
    end
    if settleN then
      settleN = settleN + 1
      if not settled() then
        if H.dialogWaiting() then return false end
        if settleN > 600 then settleN = nil; return false end
        H.setPad({})
        return true
      end
      settleN = nil
      careD = H.newCareDriver({ threshold = 0.7, tag = "care after battle (" .. tag .. ")" })
      careD.frame()
      if careD.done() then careD = nil; return false end
      return true
    end
    return false
  end
  return W
end

local function wander(mapWanted, budget, avoid)
  local W = SLOW and slowFighter("statuses " .. WHICH)
              or H.newWalkFighter("statuses " .. WHICH)
  local n = 0
  local DIRS = { "left", "up", "right", "down" }
  return H.driveUntil(function() return enough() end, budget, {
    H.call(function()
      n = n + 1
      if W.frame() then return end
      if H.dialogWaiting() then H.setPad(n % 8 < 4 and { "a" } or {}); return end
      if mapIdx() ~= mapWanted then
        error(string.format("wandered off map %d to %d at (%d,%d)", mapWanted,
          mapIdx(), H.fieldX(), H.fieldY()), 0)
      end
      if H.hasControl() and H.tileAligned() then
        local dir = DIRS[1 + (n // 24) % 4]
        -- the forest's arrival tile (1,9) sits on the world exit: a LEFT
        -- there leaves the map, so the walker keeps off the west edge
        if dir == "left" and H.fieldX() <= 2 then dir = "right" end
        -- the clock room's north tile (98,59) is the clock's trigger: an
        -- UP onto it opens the hour menu, which the A-tap answers for ever
        if avoid and avoid[dir] then dir = (n // 24) % 2 == 0 and "left" or "right" end
        H.setPad({ [dir] = true })
      else
        H.setPad({})
      end
    end),
  }, "wander for randoms")
end

local MODES = {
  train = { state = "build/states/forest_done.mss.lua", map = 145 },
  -- the clock room is two tiles tall: UP from (98,60) is the clock's
  -- trigger tile, DOWN from (98,61) the door back to the street (221)
  zozo = { state = "build/states/zozo_clock_solved.mss.lua", map = 225,
           avoid = { up = true, down = true } },
  forest = { state = "build/states/camp_escaped.mss.lua", map = 132,
             world = { 178, 82 } },
  -- Pipsqueak ($041) special $45 = Imp, its script's SPECIAL on the
  -- second line; map 269 (lab_map269_random's walk from the Ifrit &
  -- Shiva save: navTo (9,5) crosses onto 269)
  m269 = { state = "build/states/magicite_ifrit_shiva.mss.lua", map = 269,
           enter = { 9, 5 } },
  -- map 263 (mrf_263): Pipsqueak x5 in 2 of the 4 pool slots
  mrf = { state = "build/states/mrf_263.mss.lua", map = 263 },
}
local mode = MODES[WHICH] or error("unknown mode " .. WHICH)

local steps = {
  H.loadState(mode.state),
  H.waitFrames(60),
  H.call(function()
    emu.addEventCallback(function() observe() end, emu.eventType.startFrame)
    H.log(string.format("[probe] mode=%s map=%d at (%d,%d) world=%s", WHICH, mapIdx(),
      H.fieldX(), H.fieldY(), tostring(H.worldMode())))
  end),
}
if mode.world then
  steps[#steps + 1] = H.worldNavTo(mode.world[1], mode.world[2], {
    maxFrames = 25000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end })
  steps[#steps + 1] = H.waitUntil(function()
    return mapIdx() == mode.map and H.hasControl() and H.tileAligned()
  end, 4000, "the field map loads", 5)
  steps[#steps + 1] = H.waitUntil(function() return bright() >= 15 end, 900, "fade", 10)
  steps[#steps + 1] = H.waitFrames(30)
end
if mode.enter then
  steps[#steps + 1] = H.navTo(mode.enter[1], mode.enter[2], {
    maxFrames = 9000, playBattles = "tactical",
    arrive = function() return mapIdx() == mode.map end })
  steps[#steps + 1] = H.waitUntil(function()
    return mapIdx() == mode.map and H.hasControl() and H.tileAligned()
  end, 4000, "the rolling map loads", 5)
  steps[#steps + 1] = H.waitUntil(function() return bright() >= 15 end, 900, "fade", 10)
  steps[#steps + 1] = H.waitFrames(30)
end
steps[#steps + 1] = H.call(function()
  H.assertEq(mapIdx(), mode.map, "on the rolling map")
  H.log(string.format("[probe] walking map %d from (%d,%d)", mapIdx(), H.fieldX(), H.fieldY()))
end)
steps[#steps + 1] = wander(mode.map, 160000, mode.avoid)
steps[#steps + 1] = H.call(function()
  H.setPad({})
  local parts = {}
  for _, w in ipairs(WATCH) do
    local r = R[w.name]
    parts[#parts + 1] = string.format("%s=%d(own_window=%d windows_under=%d frames=%d longest=%d)",
      w.name, r.landed, r.intoOwnWindow, r.windows, r.frames, r.longest)
  end
  H.log(string.format("[result] probe=statuses mode=%s fights=%d %s fights_at=%s",
    WHICH, fights, table.concat(parts, " "), table.concat(fightLog, ";")))
end)

H.run({ maxFrames = 200000, allowGameOver = true }, steps)
