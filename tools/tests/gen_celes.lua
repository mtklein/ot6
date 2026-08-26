-- gen_celes.lua -- from sfigaro_passage.mss (LOCKE in the rich man's secret
-- passage, map 86 at (7,51)) through the mansion and the basement to the
-- moment Celes is freed and joins.
-- Generates one state:
--   celes_freed.mss  map 83 (56,9), LOCKE + CELES, the sleeping soldier's
--                    clock key taken.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/sfigaro_passage.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
-- party facing, through the party-object offset ($0803)
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
-- H.cond with an always-true predicate wraps a step list into one step
-- (a bare list can't be spliced into a step list)
local function seq(steps) return H.cond(function() return true end, steps) end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- all EIGHT for door staging: a door at the head of a stair can be entered
-- diagonally, and a diagonal candidate must also produce that move in the
-- engine
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}

local WATCH = { 0x0103, 0x0104, 0x0105, 0x0107, 0x001C, 0x001D, 0x001E,
                0x0317, 0x01D0, 0x01F0, 0x01F1 }
local function where(tag)
  local out = {}
  for _, s in ipairs(WATCH) do out[#out + 1] = string.format("%04X=%d", s, sw(s)) end
  H.log(string.format("[%s] f%d map=%d (%d,%d) bright=%d ctl=%s | %s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    tostring(H.hasControl()), table.concat(out, " ")))
end

-- Settle after a map load: a fully lit screen plus whatever else the caller
-- names, held for 20 consecutive frames, then a 30-frame margin.  Drives
-- rather than waits so a dialog on the arrival tile cannot stall it; on a
-- quiet field advanceStory holds the pad empty.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end

local aPhase = 0

-- One short step to a waypoint on the current map; long BFS queries on
-- map 75 exceed the 4096-node cap.
local function hop(tx, ty, what)
  return seq({
    H.navTo(tx, ty, { maxFrames = 12000, playBattles = true }),
    H.release(),
    H.call(function()
      H.assertEq(H.fieldX(), tx, what .. ": at x=" .. tx)
      H.assertEq(H.fieldY(), ty, what .. ": at y=" .. ty)
    end),
  })
end

-- One crossing: ordinary walkable entrance tile -> navTo straight onto it;
-- door tile (a wall until CheckDoor) -> stage on a neighbour, hold in;
-- same-map warp (maps 78/83/86 are built out of them).  CheckDoor only
-- opens a tile whose tilemap byte is $15/$17/$1C, and only for a party
-- standing directly above or below it.
local function go(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function arrived()                       -- see note 5
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  -- The staging tile is re-resolved every 90 frames, not latched once:
  -- town NPCs wander and can make a resolved tile unreachable.
  local pickAt = -1000
  local function stage()
    if pick == nil or (H.frame - pickAt >= 90 and not arrived()) then
      pickAt = H.frame
      local fresh
      if H.bfsPath(sx, sy) then
        fresh = { sx, sy, nil }                  -- walkable: stand on it
      else
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            fresh = { cx, cy, press }; break
          end
        end
      end
      fresh = fresh or pick or { sx, sy + 1, "up" }
      if pick == nil or fresh[1] ~= pick[1] or fresh[2] ~= pick[2]
         or fresh[3] ~= pick[3] then
        pick = fresh
        H.log(string.format("%s: staging (%d,%d)%s at f%d", what,
          pick[1], pick[2],
          pick[3] and (", hold " .. pick[3] .. " into (" .. sx .. "," .. sy .. ")")
                  or " (walk straight onto the entrance tile)", H.frame))
      end
    end
    return pick
  end
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 20000, arrive = arrived, playBattles = true }),
    H.cond(function() return stage()[3] ~= nil end, {
      H.driveUntil(arrived, 1800, {
        H.call(function()
          aPhase = (aPhase + 1) % 8
          if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
          H.setPad({ [stage()[3]] = true })
        end),
      }, what .. ": hold into the door"),
    }, {}),
    H.release(),
    settleField(dm),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on map " .. dm)
      H.log(string.format("%s: DONE map=%d (%d,%d) f%d", what,
        map(), H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Approach re-resolved from live object coords (NPCs wander), facing
-- computed from the live delta, soft rounds before a hard one.  CheckNPCs
-- activates whatever the object map holds one tile in the party's facing
-- direction while A is held; a two-frame turn press does not set the
-- facing byte, so the direction is held until it reads back, and only then
-- is A edge-tapped.
local function talkToObj(obj, what, maxF)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      apPick = { ox, oy + 1 }
      for _, c in ipairs(NEIGHBOURS) do
        local cx, cy = ox + c[1], oy + c[2]
        if H.bfsPath(cx, cy) then apPick = { cx, cy }; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      maxFrames = maxF or 20000, playBattles = true,
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
    })
  end
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      if started >= 6 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned() and adjacent()) then
          H.setPad({}); return
        end
        local ox, oy = objAt()
        local dx, dy = ox - H.fieldX(), oy - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    H.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    -- flat, not repeatN: it cannot replay navTo/driveUntil bodies
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.release(),
  })
end

-- $056F is the option count, final once dialogWaiting() is true (it is
-- built up as the text types out, and meaningless during a battle); $056E
-- is the 0-based selection; the steering presses are edges because $056D
-- latches a held direction to exactly one row.
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function rideUntil(pred, what, budget, choices)
  local phase, dlgN, ci, inChoice = 0, 0, 0, false
  return H.driveUntil(pred, budget or 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      local chMax = (not H.battleLoadStarted()) and H.readByte(CH_MAX) or 0
      if chMax >= 2 then
        if not H.dialogWaiting() then H.setPad({}); return end
        if not inChoice then
          inChoice = true; ci = ci + 1
          local c = (choices or {})[ci]
          if not c then
            error(string.format("%s: unexpected choice prompt #%d (%d options)",
              what, ci, chMax), 0)
          end
          H.assertEq(chMax, c.max,
            string.format("%s choice #%d option count (%s)", what, ci, c.what))
          H.log(string.format("%s: CHOICE #%d up (%d options) -- taking %d :: %s",
            what, ci, chMax, c.want, c.what))
        end
        local c, sel = choices[ci], H.readByte(CH_SEL)
        if sel < c.want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > c.want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      elseif inChoice then
        inChoice = false
        H.log(string.format("%s: choice #%d resolved at f%d", what, ci, H.frame))
      end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- talk to `obj`, then ride what it says (steering `choices`) back to a
-- settled, controllable field
local function talkThrough(obj, what, choices, budget)
  local calm = 0
  return seq({
    talkToObj(obj, what),
    rideUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, what, budget or 20000, choices),
    H.release(),
  })
end

-- A deep door: the entrance source sits one tile beyond a CheckDoor door,
-- so no staging neighbour is standable.  Stand on (fx,fy) and hold `dir`;
-- one continuous press opens the door and carries the party through the
-- source in a single glide.  Arrival is the map change.
local function deepDoor(fx, fy, dstMap, dir, what)
  local sm
  return seq({
    hop(fx, fy, what .. ": to the entry point"),
    -- latch the source map before the drive so the arrival predicate
    -- doesn't compare against nil
    H.call(function() sm = map() end),
    H.driveUntil(function() return map() ~= sm end, 1200, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [dir] = true })
      end),
    }, what .. ": hold " .. dir .. " through the door"),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": on map " .. dstMap)
      H.log(string.format("%s: DONE map=%d (%d,%d) f%d", what, map(),
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Walk onto the Celes cutscene trigger; navTo taps A through the (29,9)
-- change-clothes prompt.  Arrival is a sustained control loss, debounced
-- past async control-flicker.  The naming menu ($0059) is committed with
-- START; ends at (37,14) with $001C=1.
local function reachCelesCutscene()
  local phase, named = 0, false
  return seq({
    (function()
      local lost = 0
      return H.navTo(35, 15, { maxFrames = 16000, playBattles = true,
        arrive = function()
          lost = (not H.hasControl()) and lost + 1 or 0
          return lost >= 90 or H.fieldX() >= 50
        end })
    end)(),
    H.release(),
    H.logStep(function()
      return string.format("Celes cutscene fired at f%d (%d,%d)",
        H.frame, H.fieldX(), H.fieldY())
    end),
    -- ride the scene: commit the naming menu with START, tap dialogs, kill
    -- any battle (there is none), until control returns with $001C set
    (function()
      local calm = 0
      return H.driveUntil(function()
        local ok = H.hasControl() and H.tileAligned() and bright() >= 15
               and not H.dialogWaiting() and not H.eventRunning()
               and not H.battleLoadStarted() and sw(0x001C) == 1
        calm = ok and calm + 1 or 0
        return calm >= 20
      end, 40000, {
        H.call(function()
          phase = (phase + 1) % 8
          if H.readByte(0x0059) ~= 0 and not H.battleLoadStarted() then
            if not named then
              named = true
              H.log(string.format("naming menu up ($0059=%02X) f%d -- START",
                H.readByte(0x0059), H.frame))
            end
            H.setPad(phase == 0 and { "start" } or {})
            return
          end
          if not H.hasControl() then H.setPad(phase < 4 and { "a" } or {}); return end
          H.setPad({})
        end),
      }, "the Celes chains cutscene")
    end)(),
    H.release(),
    H.waitFrames(30),
  })
end

H.run({ maxFrames = 150000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 86, "booted in the secret passage (map 86)")
    H.assertEq(sw(0x0105), 1, "$0105 -- LOCKE's scenario is live")
    H.assertEq(sw(0x001E), 0, "$001E clear -- the scenario is not done")
    where("boot (sfigaro_passage)")
  end),

  -- LOCKE's occupied-town kit: Dirk, Leather Hat, LeatherArmor.
  H.equipLoadout(1, {
    { 0, 0x00 }, -- Dirk
    { 2, 0x69 }, -- Leather Hat
    { 3, 0x84 }, -- LeatherArmor
  }, { tag = "LOCKE passage kit" }),

  -- ===================================================================== --
  -- PHASE 1: the passage -> the rich man's house -> town.  The passage
  -- (3,53) fires _ca798e, a scripted walk that lands on the rich man's
  -- house (map 86 (6,36)); its (8,25) door returns to occupied town.
  -- ===================================================================== --
  go(3, 53, 86, 6, 36, "P1 passage (3,53) -> rich house (6,36)"),

  -- Elixir chest, bit 31 (map 86's second chest).
  H.openChest{ stand = { 7, 32 }, face = "up", bit = 31, what = "Elixir",
               nav = { playBattles = true } },

  go(8, 25, 75, 22, 13, "P2 rich house (8,25) -> town (22,13)"),

  -- ===================================================================== --
  -- PHASE 2: the mansion (map 81) -- a deep door then a three-warp descent
  -- to the basement (map 83).
  -- ===================================================================== --
  deepDoor(23, 17, 81, "up", "P3 door B -> the mansion (81)"),
  go(3, 5, 81, 5, 54, "M81a warp (3,5) -> (5,54)"),
  go(13, 51, 81, 39, 17, "M81b warp (13,51) -> (39,17)"),
  go(27, 10, 83, 7, 5, "P4 mansion (27,10) -> basement 83 (7,5)"),
  go(8, 12, 83, 18, 5, "B83a warp (8,12) -> (18,5)"),
  H.call(function() where("in the basement (18,5)") end),

  -- ===================================================================== --
  -- PHASE 3: the Celes cutscene, the naming menu, and freeing her.
  -- ===================================================================== --
  reachCelesCutscene(),
  H.call(function()
    H.assertEq(sw(0x001C), 1, "$001C -- the 'she's a general' scene ran")
    H.assertEq(sw(0x0317), 1, "$0317 -- CELES_CHAINS spawned")
    where("Celes cutscene done")
  end),

  -- her chains are in the (57,x) room, reached by the (35,12)->(57,12) warp
  go(35, 12, 83, 57, 12, "B83b warp (35,12) -> Celes room (57,12)"),
  talkThrough(19, "Celes in chains (free her)", {
    { want = 0, max = 2, what = "Remove her chains? 0=Yes -> she joins" },
  }, 40000),
  H.call(function()
    H.assertEq(sw(0x001D), 1, "$001D -- Celes freed")
    H.assertEq((H.readByte(0x1856) & 0x07) ~= 0, true, "CELES in the party")
    where("Celes freed")
  end),

  -- the sleeping soldier's clock key (peaceful; needs $001D=1)
  talkThrough(17, "the sleeping soldier (clock key)", {
    { want = 0, max = 2, what = "Take the clock key? 0=Take it" },
  }, 20000),
  H.call(function()
    H.assertEq(sw(0x01D1), 1, "$01D1 -- took the clock key")
    H.assertEq(sw(0x001A), 1,
      "$001A already set -- the Figaro cave will load map 70 (TunnelArmr)")
    where("celes_freed")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.assertPartyStanding("celes_freed")
    H.screenshot("celes_freed")
  end),
  H.saveState("celes_freed.mss"),
  H.logStep(function()
    return string.format("celes_freed generated at frame %d", H.frame)
  end),
})
