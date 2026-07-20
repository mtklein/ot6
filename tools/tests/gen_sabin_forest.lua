-- gen_sabin_forest.lua -- leg 7 of SABIN's scenario: the Phantom Forest, from
-- the World-of-Balance landing to boarding the Phantom Train.  Mints:
--   forest_done.mss   map 145 (26,11), the Phantom Train interior -- the
--                     party has just boarded; the train leg builds from here.
--
-- THE ROUTE (verified from the entrance tables + event scripts, decoded by a
-- read-only source pass; short-entrance record = [SrcX,SrcY,Map,Flags,DestX,
-- DestY] in trigger/short_entrance.dat):
--   world (179,71) -- walk S; the drop tile _cb0bb7 is inert now ($0037=1)
--   world (178,82) -> map 132 (1,9)               [world short-entrance]
--   132 (28,7)     -> map 133 (3,13)
--   133 (20,14)    -> map 134 (5,8)               [past the recovery spring]
--   134 (11,7)     -> map 135 (3,12)  via event _cba3c4 (event_main.asm:62340,
--                     `if_switch $003A=1, EventReturn` -- $003A=0 pre-train, so
--                     it loads 135; AFTER the Ghost Train it diverts to world)
--   135 (23,7)     -> map 140 (79,14)
--   140: (79,13) door _cba852 ($01F0), (79,11) discovery cutscene _cba864
--        (dlg $02A4, $0038), then W to (72,10) _cba8f1 boarding cutscene ->
--        `load_map 145,{26,11}` (event_main.asm:62961), $017C cleared to 0.
-- No scripted battles/choices/name-menus on the walk; only field random
-- encounters (kill-bit-safe trash) and the boarding dialogs (tap-A).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/camp_escaped.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end

-- drive the world toward (tx,ty), kill-bitting random encounters (overworld
-- trash -- safe), and STOP when the map index leaves the world (an entrance
-- fired) or we arrive.  worldBfs plans; hold-through per the world latch.
local function worldToMap(tx, ty, what, budget)
  local plan, idx, phase, hb = nil, 1, 0, -600
  return H.driveUntil(function()
    return not H.worldMode()
        or (H.worldX() == tx and H.worldY() == ty and H.worldHasControl())
  end, budget or 25000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("world[%s] f%d (%d,%d) wctl=%s", what, H.frame,
          H.worldX(), H.worldY(), tostring(H.worldHasControl())))
      end
      if H.battleLoadStarted() then
        plan = nil
        if H.monstersPresent() > 0 then
          for s = 0, 5 do
            if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
              H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
            end
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end
      if not H.worldHasControl() then H.setPad({}); return end
      if not H.worldAligned() then return end
      if bright() < 15 then H.setPad({}); return end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then error("worldToMap: no path to ("..tx..","..ty..")", 0) end
      end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "world->" .. what)
end

-- edge tiles double as MAP EXITS, so a naive navTo whose target sits next to
-- a back-exit walks the party out the wrong door (navTo's BFS is blind to
-- which floor tiles are entrances).  crossVia sidesteps that: navTo to an
-- INTERIOR waypoint reached without touching any exit, then hold `dir` one
-- step onto the real exit.  Battles (kill-bit -- forest trash) and cutscene
-- dialogs (tap-A) handled throughout; done when the map becomes `toMap`.
local function crossVia(wx, wy, dir, toMap, what)
  return H.cond(function() return true end, {
    H.logStep(function()
      return string.format("[forest] crossVia %s: navTo waypoint (%d,%d) then "..
        "%s -> map %d from (%d,%d) f%d", what, wx, wy, dir, toMap,
        H.fieldX(), H.fieldY(), H.frame)
    end),
    H.navTo(wx, wy, { maxFrames = 14000, arrive = function()
      return mapIdx() == toMap or (H.fieldX() == wx and H.fieldY() == wy
         and H.hasControl() and H.tileAligned()) end }),
    (function()
      local phase = 0
      return H.driveUntil(function() return mapIdx() == toMap end, 6000, {
        H.call(function()
          phase = (phase + 1) % 8
          if H.battleLoadStarted() then
            if H.monstersPresent() > 0 then
              for s = 0, 5 do
                if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
                  H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
                end
              end
            end
            H.setPad(phase < 4 and { "a" } or {}); return
          end
          if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
          if not H.hasControl() then H.setPad({}); return end
          H.setPad({ [dir] = true })   -- step onto the exit
        end),
      }, what .. " step onto exit")
    end)(),
    H.waitUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
    end, 3000, what .. " settle", 5),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. " fade", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(mapIdx(), toMap, what .. " -- crossed to map " .. toMap)
      H.log(string.format("[forest] on map %d at (%d,%d) f%d", mapIdx(),
        H.fieldX(), H.fieldY(), H.frame))
    end),
  }, {})
end

-- walk to field edge tile (tx,ty) on the current map and cross; done when the
-- map index becomes `toMap`.  navTo handles the walk, random encounters
-- (kill-bit), and any cutscene dialogs (tap-A); the short-entrance fires on
-- arrival, so control is never handed back on (tx,ty) itself.  Use this only
-- where the path to (tx,ty) does not brush another exit; else use crossVia.
local function crossTo(tx, ty, toMap, what)
  return H.cond(function() return true end, {
    H.logStep(function()
      return string.format("[forest] crossTo %s: navTo (%d,%d) -> map %d "..
        "from map %d (%d,%d) f%d", what, tx, ty, toMap, mapIdx(),
        H.fieldX(), H.fieldY(), H.frame)
    end),
    H.navTo(tx, ty, { maxFrames = 16000,
      arrive = function() return mapIdx() == toMap end }),
    H.waitUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
    end, 3000, what .. " settle control", 5),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. " fade", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(mapIdx(), toMap, what .. " -- crossed to map " .. toMap)
      H.log(string.format("[forest] on map %d at (%d,%d) f%d", mapIdx(),
        H.fieldX(), H.fieldY(), H.frame))
    end),
  }, {})
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "start on the World of Balance")
    H.assertEq(sw(0x0037), 1, "$0037 set -- escape done")
    H.log(string.format("[forest] start world (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- world -> Phantom Forest map 132
  worldToMap(178, 82, "forest entrance (178,82)", 25000),
  H.waitUntil(function()
    return mapIdx() == 132 and H.hasControl() and H.tileAligned()
  end, 4000, "map 132 control", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "map 132 fade", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 132, "entered Phantom Forest map 132")
    H.log(string.format("[forest] on map 132 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- forest map chain
  crossTo(28, 7, 133, "132->133"),

  -- MAP 133 IS A ONE-WAY SPRING PUZZLE.  Arrival (3,13) can only step UP (to
  -- the spring (3,12)) or DOWN (to (3,14), the back-exit to 132); east along
  -- y=13 is walled.  So the recovery spring _cba3d1 (event_main.asm:62344,
  -- `move UP,3 move RIGHT,2` then `switch $0192=1` + heal dlg $0B83) is a
  -- MANDATORY conveyor: stepping onto (3,12) auto-walks the party to (5,9),
  -- past the (3,14) trap, from where east+down to the (20,14) exit is open.
  H.cond(function() return true end, {
    H.logStep(function()
      return string.format("[forest] map 133 spring: hold UP from (%d,%d) f%d",
        H.fieldX(), H.fieldY(), H.frame)
    end),
    (function()
      local phase = 0
      return H.driveUntil(function()
        return sw(0x0192) == 1 and mapIdx() == 133 and H.hasControl()
           and H.tileAligned()
      end, 8000, {
        H.call(function()
          phase = (phase + 1) % 8
          if H.battleLoadStarted() then
            if H.monstersPresent() > 0 then
              for s = 0, 5 do
                if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
                  H.writeByte(0x3eec + s * 2,
                    H.readByte(0x3eec + s * 2) | 0x80)
                end
              end
            end
            H.setPad(phase < 4 and { "a" } or {}); return
          end
          if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
          if H.eventRunning() or not H.hasControl() then H.setPad({}); return end
          H.setPad({ up = true })   -- step onto the spring (3,12)
        end),
      }, "map 133 recovery spring")
    end)(),
    H.call(function()
      H.log(string.format("[forest] spring done at (%d,%d) $0192=%d f%d",
        H.fieldX(), H.fieldY(), sw(0x0192), H.frame))
    end),
  }, {}),

  crossTo(20, 14, 134, "133->134"),
  -- 134 arrival (5,8): straight UP is the (5,7) back-exit to 133, so navTo to
  -- the interior waypoint (11,8) (straight east, avoids (5,7)) then step UP
  -- onto the real exit (11,7) -> 135 (event _cba3c4, $003A=0).
  crossVia(11, 8, "up", 135, "134->135"),
  crossTo(23, 7, 140, "135->140"),

  -- BOARD THE TRAIN.  Map 140: walk UP from arrival (79,14) through the door
  -- (79,13) _cba852 (opens the platform tiles, $01F0) and the discovery
  -- cutscene (79,11) _cba864 (dlg $02A4, $0038) -- only AFTER $0038 does the
  -- west path to the boarding tile open (measured) -- then WEST to (72,11)
  -- _cba8e7 (auto-steps up to (72,10) _cba8f1) which runs the boarding
  -- cutscene (dlg $02AB/$02A5/$02A6/$02D2) and load_map 145 {26,11}.  navTo
  -- reaches (72,11) via the discovery; a generous cutscene-tolerant settle
  -- then rides the boarding dialogs onto map 145.
  H.call(function()
    H.log(string.format("[forest] on map 140 at (%d,%d) -- board the train",
      H.fieldX(), H.fieldY()))
  end),
  H.navTo(72, 11, { maxFrames = 16000,
    arrive = function() return mapIdx() == 145 end }),
  (function()
    local phase, hb = 0, -600
    return H.driveUntil(function()
      return mapIdx() == 145 and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 14000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.frame - hb >= 600 then
          hb = H.frame
          H.log(string.format("board f%d map=%d (%d,%d) ctl=%s dlg=%s ev=%s "..
            "$0038=%d", H.frame, mapIdx(), H.fieldX(), H.fieldY(),
            tostring(H.hasControl()), tostring(H.dialogWaiting()),
            tostring(H.eventRunning()), sw(0x0038)))
        end
        if H.battleLoadStarted() then
          if H.monstersPresent() > 0 then
            for s = 0, 5 do
              if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
                H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
              end
            end
          end
          H.setPad(phase < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        -- still on map 140 with control but short of the board tile: nudge W
        if mapIdx() == 140 and H.hasControl() and H.tileAligned() then
          H.setPad(phase < 4 and { left = true } or {}); return
        end
        H.setPad({})   -- boarding cutscene / fades: hands off
      end),
    }, "board the train onto map 145")
  end)(),

  -- settled on the train (map 145); mint the doorstep
  H.call(function()
    H.assertEq(mapIdx(), 145, "boarded -- Phantom Train interior map 145")
    H.assertEq(sw(0x0038), 1, "$0038 set -- train discovered")
    H.assertEq(inParty(5), true, "SABIN aboard")
    H.assertEq(inParty(2), true, "CYAN aboard")
    H.assertEq(sw(0x003A), 0, "$003A clear -- Ghost Train not yet beaten")
    H.log(string.format("[forest_done] f%d map=%d (%d,%d) $0038=%d $017C=%d",
      H.frame, mapIdx(), H.fieldX(), H.fieldY(), sw(0x0038), sw(0x017C)))
    H.screenshot("forest_done")
  end),
  H.saveState("forest_done.mss"),
  H.logStep(function()
    return string.format("forest_done minted at frame %d map 145 (%d,%d)",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
