-- gen_scenario_locke.lua -- one step PAST the hub: pick LOCKE's scenario and
-- mint the first controllable frame of it.  Reconnaissance, not the Locke
-- chain: it proves the hub is dispatchable and measures what "choosing a
-- scenario" actually costs, so the three v0.3 chains can be scoped.
-- Mints one state:
--   locke_scenario.mss  map 75 (South Figaro) at (48,43), LOCKE alone,
--                       controllable -- the doorstep of the Locke scenario.
--
-- THE HUB IS SIX NPCs ON A TINY MAP (NPCProp::_9, npc_prop.asm:473-521), and
-- the party -- SCENARIO_MOG, char 13, dropped in at (8,3) by _caad4c -- walks
-- to whichever one it wants:
--   obj 16  LOCKE  ( 5, 8) $0329 -> _ca84ab (:20202)   South Figaro
--   obj 17  SABIN  (11, 8) $032a -> _cb0a1c (:39463)   the world at (161,36)
--   obj 18  BANON  ( 8,10) $032b -> _cb094e (:39355)   back onto the raft
--   obj 19  TERRA  ( 7,11) $032c -> _cb094e            (same event)
--   obj 20  EDGAR  ( 9,11) $032d -> _cb094e            (same event)
--   obj 21  SAVE_POINT (8,6) $0632
-- Three NPCs share _cb094e because BANON/TERRA/EDGAR are one scenario -- the
-- raft ride resumed to Narshe (`load_map 113, {104,61}` + `vehicle … RAFT` +
-- `battle 8, RIVER`, :39357-39371).  So the split is genuinely three ways,
-- not five, and the completion flags are $001E (Locke), $0044 (Sabin) and
-- $0021 (Terra); with all three set the hub takes _caadb9 (:26683) instead.
--
-- WHAT EACH ENTRY COSTS, read off the three events -- this is the part that
-- shapes how the chains get dispatched:
--   LOCKE  _ca84ab  party_chars LOCKE / load_map 75 {48,43} / … /
--                   player_ctrl_on.  A FIELD map, and it is the same map 75
--                   gen_kolts already mints south_figaro on.
--   SABIN  _cb0a1c  party_chars SABIN / load_map 0 {161,36} /
--                   set_script_mode WORLD.  Starts on the OVERWORLD, so that
--                   chain needs worldNavTo from its first frame.
--   BANON  _cb094e  resumes the raft: map 113 at (104,61) with the RAFT
--                   vehicle sprite and `battle 8, RIVER`, ending
--                   `load_map 0, {93,41}`.  That chain re-enters the river
--                   driver this file's sibling gen_scenario.lua already has.
--
-- THE SAVE POINT AT (8,6) IS ON THE WAY and is harmless HERE, for a reason
-- worth stating because it bit gen_scenario hard one link back: SavePoint
-- (event_main.asm:100749) branches on $0133, and $0133 was set by the Lete
-- River's landing.  So it now takes its short path -- sfx, flash,
-- `player_ctrl_on`, return -- rather than the one-time tutorial whose "No"
-- answer ends in a bare EventReturn and never gives control back.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/scenario_hub.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function seq(steps) return H.cond(function() return true end, steps) end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}

-- gen_banon's talkToObj, unchanged in shape: approach re-resolved, facing
-- computed from the live delta, soft rounds before a hard one.
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

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 9, "booted on map 9, the scenario hub")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, true,
      "SCENARIO_MOG (char 13) is the party")
    H.log(string.format("[hub] f%d (%d,%d) -- the five scenario NPCs:",
      H.frame, H.fieldX(), H.fieldY()))
    local NAMES = { [16] = "LOCKE  -> _ca84ab (South Figaro)",
                    [17] = "SABIN  -> _cb0a1c (the world map)",
                    [18] = "BANON  -> _cb094e (the raft)",
                    [19] = "TERRA  -> _cb094e (the raft)",
                    [20] = "EDGAR  -> _cb094e (the raft)",
                    [21] = "SAVE_POINT" }
    for i = 16, 21 do
      local p = H.bfsPath(objX(i), objY(i) + 1)
      H.log(string.format("  obj %d at (%2d,%2d)  %-34s approach from below: %s",
        i, objX(i), objY(i), NAMES[i],
        p and (#p .. " steps") or "no path"))
    end
    H.assertEq(sw(0x0133), 1,
      "$0133 set -- the (8,6) save point takes its short, ctrl-restoring path")
  end),

  -- ===================================================================== --
  -- PICK LOCKE.  One of three; chosen because it lands on a FIELD map the
  -- frontier already knows (75, where gen_kolts mints south_figaro), which
  -- makes it the cheapest of the three to verify as a doorstep.
  -- ===================================================================== --
  talkToObj(16, "LOCKE's scenario NPC"),
  H.advanceStory(function()
    return map() == 75 and H.hasControl() and H.tileAligned()
       and bright() >= 15 and not H.battleLoadStarted()
  end, 30000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 75, "on map 75 -- SOUTH FIGARO, LOCKE's scenario")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    -- LOCKE alone: char 1 in, MOG out
    H.assertEq((H.readByte(0x1851) & 0x07) ~= 0, true, "LOCKE in the party")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, false, "SCENARIO_MOG gone")
    H.assertEq(sw(0x001E), 0, "$001E still clear -- the scenario is not done")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.log(string.format("[locke_scenario] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("locke_scenario")
  end),
  H.saveState("locke_scenario.mss"),
  H.logStep(function()
    return string.format("locke_scenario minted at frame %d", H.frame)
  end),
})
