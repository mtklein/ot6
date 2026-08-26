-- gen_banon.lua -- from returner_hideout.mss (map 108, the entry hall)
-- through the Returner Hideout to the moment the party casts off for
-- Narshe.  Generates one state:
--   banon_joined.mss  map 112 (7,43), TERRA + EDGAR + SABIN + BANON, $0018
--                     set (the raft is armed).

-- Progress gates on talking to five NPCs in a partial order, each setting
-- a switch the next one reads.

local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/returner_hideout.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (object number = the map's NPC record index +
-- 16).  The greeter's own escort moves him from (9,25) to (25,17).
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

-- ANTIDOTE is $F2.
local ANTIDOTE = 0xF2
-- the two relics the BANON decision chooses between
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

-- settleField drives past a lingering dialog or encounter without
-- requiring player control ($087C&$0F alternates between 2 and 4 under any
-- async object script).
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

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- EDGAR ($041f) and the guard at (44,14) ($041e) move randomly
-- (npc_prop.asm); LOCKE, SABIN and BANON stand still.  The approach tile is
-- re-resolved at most every 30 frames and facing is computed from the live
-- delta every frame.
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
    -- bodies, because their latched state carries over
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
-- A blind A while a list is up confirms row 0 (Yes).  `swId` is $0014,
-- $0015 and $0016 for refusals 1, 2 and 3.
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

H.run({ maxFrames = 320000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 108, "booted on map 108, the hideout entry hall")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0011), 0, "$0011 clear -- the speech has not run")
    where("booted")
    roster("booted")
  end),

  -- care stop: a no-op that only logs when nobody needs healing
  H.fieldCare({ tag = "care on arrival", threshold = 0.85 }),

  -- ===================================================================== --
  -- Phase 1: in, past the greeter.  The vestibule on map 109 reaches five
  -- tiles and he is standing on the sixth; the escort is the only way out
  -- of it, and it ends with the party at (22,21).
  -- ===================================================================== --
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
  -- Control returns before the greeter finishes walking clear of the
  -- corridor, so this waits for the path to open rather than for a frame
  -- count.
  H.waitUntil(function() return H.bfsPath(25, 16) ~= nil end, 3000,
    "the greeter walks clear of door C's approach", 10),
  H.call(function()
    H.log(string.format("greeter now at (%d,%d); (25,16) is %d steps away",
      objX(16), objY(16), #H.bfsPath(25, 16)))
    H.screenshot("banon_escorted")
  end),

  H.navTo(22, 23, { maxFrames = 8000, playBattles = "tactical" }),
  H.release(),
  (function()
    local t, calm = 0, 0
    return H.driveUntil(function()
      t = t + 1
      if H.eventRunning() or not H.hasControl() then calm = 0
      else calm = calm + 1 end
      return calm >= 120
    end, 9000, {
      H.call(function()
        if t % 1200 == 0 then
          H.log(string.format("  [drain] t=%d $E5=%04X calm=%d",
            t, H.readWord(0x00e5), calm))
        end
        H.setPad({})
      end),
    }, "the escort's event tail drains, off the trigger tile")
  end)(),
  H.openChest{ stand = {26, 22}, face = "up", bit = 41, what = "Green Cherry",
               nav = { playBattles = "tactical" } },

  -- ===================================================================== --
  -- PHASE 2: THE SPEECH.  Door C is the only way to Banon's half of map
  -- 110, and it is a door tile, so it is staged rather than planned through.
  -- ===================================================================== --
  crossDoorHold(25, 16, "up", 110, "H2 map 109 -> map 110 EAST (door C)"),
  H.call(function()
    H.assertEq(sw(0x041D), 1, "$041D set -- BANON is here")
    H.assertEq(objX(16), 51, "BANON obj 16 at x=51")
    H.assertEq(objY(16), 50, "BANON obj 16 at y=50")
  end),
  talkToObj(16, "BANON (the speech)"),
  -- the speech reloads map 110 at (21,48): same map id, so $0011 is the
  -- only real arrival signal
  rideTo(function() return map() == 110 and sw(0x0011) == 1 end,
    "after the speech", 40000),
  H.call(function()
    H.assertEq(sw(0x0011), 1, "$0011 set -- the speech ran")
    H.assertEq(sw(0x041D), 0, "$041D clear -- BANON left map 110")
    H.assertEq(sw(0x041F), 1, "$041F set -- EDGAR is an NPC (east)")
    H.assertEq(sw(0x0420), 1, "$0420 set -- LOCKE is an NPC (west)")
    H.assertEq(sw(0x0416), 1, "$0416 set -- SABIN is an NPC on map 109")
    H.log(string.format("the speech left the party at (%d,%d); " ..
      "LOCKE obj 19 at (%d,%d)", H.fieldX(), H.fieldY(), objX(19), objY(19)))
    for _, c in ipairs({ { 27, 49 }, { 27, 47 }, { 26, 48 }, { 28, 48 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("  approach (%d,%d): %s", c[1], c[2],
        p and (#p .. " steps") or "NO PATH"))
    end
    -- TERRA alone: char 0 in, 1/4/5 out
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA in the party")
    H.assertEq((H.readByte(0x1851) & 0x07) ~= 0, false, "LOCKE out")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, false, "EDGAR out")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, false, "SABIN out")
    H.screenshot("banon_speech")
  end),

  -- ===================================================================== --
  -- Phase 3: the three friends.  $015A/$015B/$015C, the lock on _cafa67.
  -- LOCKE is in this room; SABIN is on map 109; EDGAR is back across door C.
  -- ===================================================================== --
  talkToObj(19, "LOCKE ($015A)"),
  rideTo(function() return sw(0x015A) == 1 end, "locke done"),
  H.call(function() H.assertEq(sw(0x015A), 1, "$015A set (LOCKE)") end),

  H.openChest{ stand = {28, 50}, face = "up", bit = 42, what = "Fenix Down",
               item = 0xF0, nav = { playBattles = "tactical" } },

  -- west room -> map 109 by the floor-tile door (22,54)
  crossTo(22, 54, 109, "H3 map 110 WEST -> map 109 (for SABIN)"),
  talkToObj(19, "SABIN ($015B)"),
  rideTo(function() return sw(0x015B) == 1 end, "sabin done"),
  H.call(function() H.assertEq(sw(0x015B), 1, "$015B set (SABIN)") end),

  -- back through door C for EDGAR
  crossDoorHold(25, 16, "up", 110, "H4 map 109 -> map 110 EAST (for EDGAR)"),
  talkToObj(18, "EDGAR ($015C)"),
  rideTo(function() return sw(0x015C) == 1 end, "edgar done"),
  H.call(function()
    H.assertEq(sw(0x015C), 1, "$015C set (EDGAR)")
    where("three of three")
  end),

  H.openChest{ stand = {55, 49}, face = "up", bit = 48, what = "Potion",
               item = 0xE9, nav = { playBattles = "tactical" } },

  -- ===================================================================== --
  -- Phase 4: the greeter unlocks BANON, setting $0421.  Every map load
  -- re-inits NPCs from npc_prop, so the greeter is back on his spawn tile
  -- (9,25); talkToObj tracks him live either way.
  -- ===================================================================== --
  crossTo(42, 45, 109, "H5 map 110 EAST -> map 109 (for the greeter)"),
  talkToObj(16, "the greeter (unlock BANON)"),
  rideTo(function() return sw(0x0421) == 1 end, "banon unlocked"),
  H.call(function()
    H.assertEq(sw(0x0421), 1, "$0421 set -- BANON is waiting on map 108")
  end),

  crossTo(9, 30, 108, "H6 map 109 -> map 108 (to BANON)"),
  H.call(function()
    H.assertEq(objX(16), 14, "BANON obj 16 at x=14")
    H.assertEq(objY(16), 49, "BANON obj 16 at y=49")
    H.assertEq(H.invCountOf(GENJI_GLOVE), 0, "no Genji Glove in the bag yet")
    H.assertEq(H.invCountOf(GAUNTLET), 0, "no Gauntlet in the bag yet")
  end),

  refuseBanon(1, 0x0014, "$0014"),
  settleField(109),
  H.call(function()
    H.assertEq(map(), 109, "refusal 1 put the party back on map 109")
    H.assertEq(sw(0x0413), 0, "$0413 clear -- _cafcd8 despawned the greeter")
    H.assertEq(H.invCountOf(GAUNTLET), 0,
      "the No branch handed over no Gauntlet")
    H.log(string.format(
      "one-refusal variant: $0414=%d, (11,8) door %s, (11,15) %s, " ..
      "(11,9) %s -- the glove NPC is map 110 (44,14) behind it",
      sw(0x0414),
      H.bfsPath(11, 8) and (#H.bfsPath(11, 8) .. " steps") or "NO PATH",
      H.bfsPath(11, 15) and (#H.bfsPath(11, 15) .. " steps") or "NO PATH",
      H.bfsPath(11, 9) and (#H.bfsPath(11, 9) .. " steps") or "NO PATH"))
  end),

  crossTo(9, 30, 108, "H7 map 109 -> map 108 (back to BANON, refusal 2)"),
  refuseBanon(2, 0x0015, "$0015"),
  settleField(109),
  H.call(function()
    H.assertEq(map(), 109, "refusal 2 put the party back on map 109")
  end),

  crossTo(9, 30, 108, "H8 map 109 -> map 108 (back to BANON, refusal 3)"),
  H.call(function()
    H.assertEq(sw(0x0421), 1, "$0421 still set -- BANON is still on map 108")
  end),
  -- The third refusal clears $0421 and runs the forced departure directly
  -- to map 112, rather than returning control on map 109.
  refuseBanon(3, 0x0016, "$0016"),
  H.advanceStory(function()
    return map() == 112 and sw(0x0018) == 1 and H.hasControl()
       and H.tileAligned() and bright() >= 15 and not H.battleLoadStarted()
  end, 60000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 112, "on map 112 -- the passage to the Lete River")
    -- $0013 is set only on the Yes path.
    H.assertEq(sw(0x0013), 0,
      "$0013 clear -- the YES branch never ran (_cafba6 not called)")
    H.assertEq(sw(0x0016), 1, "$0016 set -- the third refusal ran (_cafd86)")
    H.assertEq(sw(0x0017), 1, "$0017 set -- the relic was handed over")
    H.assertEq(H.invCountOf(GENJI_GLOVE), 1,
      "a Genji Glove is in the bag (event_main.asm:37834)")
    H.assertEq(H.invCountOf(GAUNTLET), 0,
      "and no Gauntlet -- the two are exclusive, this is the trade")
    H.assertEq(sw(0x0018), 1, "$0018 set -- _cb059f will let the raft board")
    H.assertEq(sw(0x016B), 0,
      "$016B clear -- the scrap-of-paper prompt never fired")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    -- the raft party: TERRA + EDGAR + SABIN + BANON (char 14, aka WEDGE)
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA in the party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, true, "EDGAR back")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, true, "SABIN back")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true,
      "BANON joined (char 14 -- const.inc calls 14 both WEDGE and BANON)")
    H.assertEq((H.readByte(0x1851) & 0x07) ~= 0, false,
      "LOCKE left (he is off to South Figaro)")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    where("banon joined")
    roster("before the exit care stop")
    H.screenshot("banon_joined")
  end),

  -- exit care stop: the first moment all four party records are visible
  H.fieldCare({ tag = "care before the raft", threshold = 0.85 }),
  H.call(function()
    roster("banon_joined exit")
    -- H.assertPartyStanding: nobody dead, petrified, zombie, poisoned, or
    -- at/below max HP / 8.
    H.assertPartyStanding("banon_joined exit")
  end),
  H.saveState("banon_joined.mss"),
  H.logStep(function()
    return string.format("banon_joined generated at frame %d", H.frame)
  end),
})
