-- probe_banon_chest.lua -- from returner_hideout.mss (map 108, entry hall)
-- through the Returner Hideout to banon_joined.mss: map 112 (7,43),
-- TERRA + EDGAR + SABIN + BANON, $0018 set (the raft is armed).  Also
-- instruments the deep chest near (26,22) after the escort.
--
-- The hideout gates progress through five NPCs talked to in a partial
-- order, each setting a switch the next one reads:
--   map 109 ( 9,25) greeter $0413            escorts the party in
--   map 110 (51,50) BANON   $041d            the decision speech; rebuilds
--       the party down to TERRA alone and moves her to map 110 (21,48)
--   map 110 (27,48) LOCKE   $0420 -> sets $015A
--   map 109 (26,28) SABIN   $0416 -> sets $015B
--   map 110 (52,48) EDGAR   $041f -> sets $015C
--   map 109 ( 9,25) greeter again: requires $015A/$015B/$015C all set,
--       then sets $0421, which spawns BANON on map 108
--   map 108 (14,49) BANON   $0421            the decision prompt
--
-- Map 109's vestibule (five tiles, (9,26)-(9,30)) is blocked by the
-- greeter at (9,25); talking to him escorts the party to (22,21) and
-- opens the rest of the map.  Maps 109 and 110 are each partitioned: map
-- 110's west room (bbox (20,46)-(29,54)) and east half (bbox
-- (41,38)-(57,54)) connect only through map 109, whose three doors lead
-- to three different destinations:
--     (11, 8) -> 110 (44,27)   east
--     (14,17) -> 110 (22,53)   west
--     (25,15) -> 110 (42,44)   east -- the one BANON is behind
-- Door C, (25,15), is a door tile: it is a wall until CheckDoor swaps the
-- open-door tiles in, and only for a party pressing into it from directly
-- above or below, so it is crossed by staging on (25,16) and holding UP
-- rather than by navTo.
--
-- The decision prompt is dlg $0131 ("Will you become our last ray of
-- hope?  0: Yes  1: No").  Yes gives TERRA a GAUNTLET.  No, answered
-- three times, gives TERRA a GENJI GLOVE instead: refusal 1 sets $0014,
-- refusal 2 sets $0015, refusal 3 sets $0016 and forces the party's
-- departure.  $0013 stays clear on the No path.  Both paths converge and
-- set $0018, EDGAR and SABIN rejoin, LOCKE drops out, and the party lands
-- on map 112 (7,42).  Banon is character 14 (WEDGE in the disassembly);
-- $185E is the byte that records his party membership.
--
-- The refusal driver reads $056F (live choice count) and $056E (0-based
-- selected row, clamped at $056F-1) rather than tapping A blind, since a
-- blind A always confirms row 0 (Yes).
--
-- The hideout has no random encounters (maps 108/109/110/112 all clear
-- bit 7 of map_prop byte $0525), so all navigation runs in "tactical"
-- battle mode: TERRA is the whole party for the last stretch and a Banon
-- death is an unrecoverable game over, so any battle that did fire would
-- be fought with real input.
--
-- Poison drains max HP/32 per step (floor 1), so this generator clears
-- status before the walk and again before the exit assertions.
--
-- Map 109's (25,23) trigger (the scrap-of-paper gag) only fires on A
-- pressed while facing down, not on a walk-past, so this route does not
-- handle its prompt; it instead asserts $016B (the flag the trigger sets)
-- stays clear.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/returner_hideout.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile.  Object number = the map's NPC record index
-- + 16, spawned or not.
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) $0011=%d $0013=%d $0018=%d " ..
    "$015A=%d $015B=%d $015C=%d $0421=%d $016B=%d " ..
    "| refusals $0014=%d $0015=%d $0016=%d relic $0017=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0011), sw(0x0013),
    sw(0x0018), sw(0x015A), sw(0x015B), sw(0x015C), sw(0x0421), sw(0x016B),
    sw(0x0014), sw(0x0015), sw(0x0016), sw(0x0017)))
end

-- HP, status 1 and the poison cure, at both ends of the walk.
local ANTIDOTE = 0xF2
local GAUNTLET, GENJI_GLOVE = 0xD0, 0xD1
local function roster(tag)
  local out = {}
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local base = 0x1600 + 37 * c
      out[#out + 1] = string.format("c%d %d/%d hp status1=%02X", c,
        H.readWord(base + 9), H.readWord(base + 11), H.readByte(base + 20))
    end
  end
  H.log(string.format("[roster %s] %s | antidote=%d", tag,
    table.concat(out, "  "), H.invCountOf(ANTIDOTE)))
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- settled() does not require player control: $087C&$0F alternates between
-- 2 and 4 under any async object script.
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = "tactical" }),
    H.waitFrames(30),
  })
end

local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

-- an ordinary floor-tile entrance: BFS routes straight onto it
local function crossTo(tx, ty, dstMap, what)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap)
    end),
    H.navTo(tx, ty, { maxFrames = 20000, arrive = mapChanged(),
      playBattles = "tactical" }),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- a door-tile entrance: stage on the neighbour and hold into it, because
-- BFS cannot plan onto a tile that is a wall until CheckDoor opens it
local function crossDoorHold(sx, sy, dir, dstMap, what)
  local aPh = 0
  return seq({
    H.logStep(function()
      return string.format("cross %s: stage (%d,%d) hold %s -> map %d",
        what, sx, sy, dir, dstMap)
    end),
    H.navTo(sx, sy, { maxFrames = 20000, arrive = mapChanged(),
      playBattles = "tactical" }),
    H.release(),
    H.driveUntil(function() return map() ~= 109 and map() ~= 110
                            or map() == dstMap end, 1800, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        H.setPad({ [dir] = true })
      end),
    }, what),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- Talk to object `obj`, tracked by its live tile.  CheckNPCs activates
-- whichever object is one tile in the party's facing direction while A is
-- held; a two-frame turn press does not set the facing byte, so the
-- direction is held until $087F reads back the wanted value before A is
-- edge-tapped (4 on / 4 off).  The approach tile is the nearest
-- BFS-reachable neighbour, re-resolved periodically.
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- EDGAR ($041f) and the guard at (44,14) ($041e) move randomly; LOCKE
-- ($0420), SABIN and BANON stand still.
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
      maxFrames = maxF or 20000,
      playBattles = "tactical",
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
        if waited % 300 == 0 then
          local ox, oy = objAt()
          H.log(string.format("  %s: f%d me=(%d,%d) npc=(%d,%d) adj=%s " ..
            "ctl=%s face=%d", what, H.frame, H.fieldX(), H.fieldY(), ox, oy,
            tostring(adjacent()), tostring(H.hasControl()), facing()))
        end
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
    H.logStep(function()
      local ox, oy = objAt()
      return string.format("%s: obj %d at (%d,%d); party at (%d,%d)",
        what, obj, ox, oy, H.fieldX(), H.fieldY())
    end),
    walkStep(), pokeStep(1, 600, false),
    -- rounds are written out flat: repeatN cannot replay navTo/driveUntil
    -- bodies, since their latched state carries over
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, false) }, {}),
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(3, 1200, true) }, {}),
    H.release(),
  })
end

-- Talk to BANON and answer his prompt with option 1, "No".
--   a choice list is up ($056F >= 2)     -> walk $056E onto row 1, then A
--   an ordinary page is waiting          -> edge-A to page it
--   anything else (animation, map load)  -> empty pad
-- A blind A while a list is up confirms row 0 (Yes), so it is never used.
-- `swId` is $0014, $0015, $0016 for refusals 1, 2, 3.
local function refuseBanon(n, swId, swName)
  local what = string.format("BANON refusal %d (option 1 = No, -> %s)",
    n, swName)
  local ph = 0
  return seq({
    talkToObj(16, string.format("BANON (refusal %d)", n)),
    H.driveUntil(function() return sw(swId) == 1 end, 12000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.readByte(0x056f) >= 2 then
          if H.readByte(0x056e) ~= 1 then
            H.setPad(ph < 4 and { down = true } or {})
          else
            H.setPad(ph < 4 and { "a" } or {})
          end
          return
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, what),
    H.release(),
    H.call(function()
      H.assertEq(sw(swId), 1, what .. ": the No branch ran")
      where(string.format("after refusal %d", n))
    end),
  })
end

-- ride whatever scene just started until `pred` holds on a settled field
local function rideTo(pred, what, maxF)
  return seq({
    H.advanceStory(function()
      return pred() and H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.battleLoadStarted()
    end, maxF or 25000, { playBattles = "tactical" }),
    H.waitFrames(20),
    H.call(function() where(what) end),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 108, "booted on map 108, the hideout entry hall")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0011), 0, "$0011 clear -- the speech has not run")
    where("booted")
    roster("booted")
  end),

  -- Care stop on arrival, before the walking that would otherwise cost a
  -- poisoned character HP.  No-op when nobody needs care.
  H.fieldCare({ tag = "care on arrival", threshold = 0.85 }),

  -- Phase 1: in, past the greeter; the escort ends with the party at (22,21).
  crossTo(10, 48, 109, "H1 entry hall -> map 109"),
  H.call(function()
    H.assertEq(sw(0x01F0), 0, "$01F0 clear -- the escort has not run")
    H.assertEq(sw(0x0413), 1, "$0413 set -- the greeter is on the map")
    local p = H.bfsPath(25, 16)
    H.assertEq(p, nil,
      "the vestibule cannot reach door C yet -- the greeter is the wall")
  end),
  talkToObj(16, "the greeter (the escort)"),
  rideTo(function() return map() == 109 and sw(0x01F0) == 1 end,
    "escorted in"),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 set -- the escort ran")
  end),
  -- Control returns before the greeter finishes walking clear of door C's
  -- approach, so wait for the path to open rather than for a frame count.
  H.waitUntil(function() return H.bfsPath(25, 16) ~= nil end, 3000,
    "the greeter walks clear of door C's approach", 10),
  H.call(function()
    H.log(string.format("greeter now at (%d,%d); (25,16) is %d steps away",
      objX(16), objY(16), #H.bfsPath(25, 16)))
    H.screenshot("banon_escorted")
  end),

  -- ===== deep chest instrument (probe_banon_chest) =====
  H.navTo(26, 22, { maxFrames = 15000, playBattles = "tactical" }),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    local function blk(x, y)
      return H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF))
    end
    H.log(string.format(
      "pre-A: (%d,%d) face=%02X $E5=%04X $E7=%02X $BA=%02X bit41=%s",
      H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803)),
      H.readWord(0x00e5), H.readByte(0x00e7), H.readByte(0x00ba),
      tostring(H.chestOpen(41))))
    H.log(string.format(
      "pre-A: blk(26,21)=%02X blk(26,22)=%02X bag[8]=%02X x%d",
      blk(26, 21), blk(26, 22),
      H.readByte(0x1869 + 8), H.readByte(0x1969 + 8)))
    H.screenshot("chest_preA")
  end),
  -- face up (closed loop), then five clean single A taps, logging after
  (function()
    local t = 0
    return H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == 0
    end, 300, {
      H.call(function() H.setPad({ up = true }) end),
    }, "faced up")
  end)(),
  H.release(),
  H.waitFrames(8),
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return t >= 600 or H.dialogWaiting()
    end, 900, {
      H.call(function()
        local c = t % 120
        H.setPad(c < 4 and { a = true } or {})
        if c == 60 then
          H.log(string.format(
            "  tap %d: $BA=%02X dlg=%s bit41=%s $E5=%04X bag[8]=%02X x%d (%d,%d)",
            math.floor(t / 120) + 1, H.readByte(0x00ba),
            tostring(H.dialogWaiting()), tostring(H.chestOpen(41)),
            H.readWord(0x00e5), H.readByte(0x1869 + 8),
            H.readByte(0x1969 + 8), H.fieldX(), H.fieldY()))
        end
      end),
    }, "five instrumented A taps")
  end)(),
  H.call(function()
    H.log(string.format("post: dlg=%s bit41=%s $BA=%02X",
      tostring(H.dialogWaiting()), tostring(H.chestOpen(41)),
      H.readByte(0x00ba)))
    H.screenshot("chest_postA")
  end),
})
