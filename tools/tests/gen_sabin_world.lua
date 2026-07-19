-- gen_sabin_world.lua -- leg 1 of SABIN's scenario: the hub dispatch, the
-- overworld landing, SHADOW's house, and the walk to the Imperial Camp gate.
-- Mints two states:
--   sabin_world.mss  world map 0 at (161,36), SABIN alone -- the first
--                    controllable frame of the scenario
--   sabin_camp.mss   map 117 (IMPERIAL CAMP) just inside the north gate,
--                    SABIN + SHADOW, controllable
--
-- WHY TWO, AND WHY THIS LEG IS ITS OWN FILE.  The Sabin arc is ~15 maps and
-- a single generator for it would be tens of thousands of frames long: every
-- experiment on the Phantom Train would replay the hub, the house and the
-- camp first.  So the arc is cut at the points where the game itself hands
-- control back on a fresh map, and each cut is a frontier link.
--
-- THE ROUTE, read off the event script (ff6/src/event/event_main.asm):
--   hub obj 17 SABIN  $032a -> _cb0a1c            (:39463)
--     ... dlg $01B1, fade, `party_chars SABIN`,
--         `load_map 0, {161,36}, DOWN, ASYNC` + `set_script_mode WORLD`
--                                                 (:39501-39503)
--     => THE SCENARIO STARTS ON THE OVERWORLD.  Not a field map: every
--        field predicate in the lib is meaningless until we leave it, and
--        worldNavTo is needed from the very first controllable frame.
--   world (165,35) -> map 115 at (7,13)           (short_entrance.dat, map 0)
--     map 115 is the house.  Its one NPC, obj 16 at {4,12} with
--     `set_npc_event _cb0a5f` (npc_prop.asm:4553), is SHADOW -- drawn with
--     `set_npc_gfx SHADOW` but spoken of as "MAN" until the game names him.
--   _cb0a5f (:39496): dlg $01C4/$01C5, the dog, `name_menu SHADOW` (:39531),
--     then dlg $01CA "Welcome a partner?" with `choice _cb0aca, _cb0b07`
--     (:39549).  OPTION 0 = Yes = _cb0aca (:39570) is the branch that does
--     `char_party SHADOW, 1`; option 1 = _cb0b07 (:39601) deletes him again.
--   map 115 long entrance y=15, x 0..14 -> world (165,36)
--   world (179,71) -> event trigger _cb0bb7 (event_trigger.asm:30, :39715)
--     -> `load_map 117, {36,2}, DOWN` and the camp startup event _cb0bc4
--        re-creates SABIN (+ SHADOW if $02F3) and walks the party DOWN 1.
--
-- THE NAME MENU IS NOT A DIALOG AND NOT A FIELD MENU.  `name_menu` is event
-- command $98 (ff6/src/field/event.asm:3600), which stores #$01 to $0200 and
-- calls OpenMenu; OpenMenu ends in `jsl OpenMenu_ext` (field/menu.asm:322),
-- a BLOCKING call -- the field module stops running entirely while the menu
-- is up.  So every signal the lib's drivers watch goes quiet at once:
-- hasControl() false, dialogWaiting() false, battleLoadStarted() false,
-- screen at full brightness, event PC parked on the name_menu command.  A
-- plain advanceStory() sits there holding a neutral pad until its budget
-- runs out.  The menu is dismissed with START (name_change.asm:85, "jump if
-- start button is pressed").
--
-- MEASURED, run 1 of this file, at the moment SHADOW's menu was up:
--     $0200=1  $0059=1  $0084=0  $0026=$5F  $0027=$5F  $00BA=0  $00D3=0
-- $0200 is event command $98's own marker ("#$01 = name change menu"), and
-- $0059 is the field's menu-open gate -- the same byte hasControl() already
-- watches.  $0026/$0027 are the MENU module's zMenuState/zNextMenuState
-- (menu/menu_ram.inc:112-113, direct-page $26 by the ram_byte running
-- offset), and $5F is exactly the state MenuState_5d parks in after its
-- fade ("lda #$5f / sta zNextMenuState", name_change.asm:60-61).  So the
-- detector is $0200 == 1 AND $0059 ~= 0: $0200 alone goes stale after the
-- menu closes, and $0059 alone is true of any menu.  CYAN (:61204) and GAU
-- (:66618) hit the same menu later in the arc.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/scenario_hub.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- multiple-choice state (src/field/text.asm), same addresses gen_scenario
-- uses: $056E = cursor row, $056F = option count.  $056F is only FINAL once
-- the prompt is input-ready, so nothing is read off it before dialogWaiting().
local CH_SEL, CH_MAX = 0x056E, 0x056F
local NAME_MENU = 0x0200          -- field/event.asm:3607, #$01 = name change

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}

-- gen_banon's talkToObj by way of gen_scenario_locke, unchanged in shape:
-- the approach tile is re-resolved every 30 frames (NPCs walk), facing is
-- computed from the LIVE delta, and a soft activation round precedes a hard
-- one.  Flat, never repeatN -- repeatN cannot replay navTo/driveUntil bodies.
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
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.release(),
  })
end

-- Every `choice` this leg can reach, answered in order.  `max` is asserted
-- against $056F, so a fork the route does not know about fails loudly
-- instead of being answered blind.
local CHOICES = {
  { want = 0, max = 2,
    what = "SHADOW joins (dlg $01CA): 0 = Yes -- option 1 (_cb0b07) " ..
           "deletes him again" },
}
local ci, inChoice = 0, false
local nameMenusSeen = 0

-- The leg driver.  Steers choices, kill-bits battles, taps dialogs, and
-- dismisses the name menu.  Everything the arc's later legs need is here so
-- they can copy one function rather than five special cases.
local function rideUntil(pred, what, budget)
  local phase, battN, dlgN, quiet, hb = 0, 0, 0, 0, -900
  return H.driveUntil(pred, budget or 40000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("sabin f%d map=%d fld(%d,%d) wld(%d,%d) ctl=%s " ..
          "wctl=%s dlg=%s batt=%s ev=%s br=%d chMax=%d $0200=%d",
          H.frame, map(), H.fieldX(), H.fieldY(), H.worldX(), H.worldY(),
          tostring(H.hasControl()), tostring(H.worldHasControl()),
          tostring(H.dialogWaiting()), tostring(H.battleLoadStarted()),
          tostring(H.eventRunning()), bright(), H.readByte(CH_MAX),
          H.readByte(NAME_MENU)))
      end

      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0

      -- 1. a multiple choice: steer to the wanted row, then confirm
      local chMax = (battN == 0) and H.readByte(CH_MAX) or 0
      if chMax >= 2 then
        quiet = 0
        if not H.dialogWaiting() then H.setPad({}); return end
        if not inChoice then
          inChoice = true
          ci = ci + 1
          local c = CHOICES[ci]
          if not c then
            error(string.format("sabin: unexpected choice prompt #%d (%d " ..
              "options) on map %d -- this leg knows of only %d",
              ci, chMax, map(), #CHOICES), 0)
          end
          H.assertEq(chMax, c.max,
            string.format("choice #%d option count (%s)", ci, c.what))
          H.log(string.format("sabin: CHOICE #%d up (%d options) -- taking " ..
            "option %d :: %s", ci, chMax, c.want, c.what))
        end
        local c, sel = CHOICES[ci], H.readByte(CH_SEL)
        if sel < c.want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > c.want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      elseif inChoice then
        inChoice = false
        H.log(string.format("sabin: choice #%d resolved at f%d", ci, H.frame))
      end

      -- 2. battle: kill-bit everything present and tap through the text
      if battN >= 3 then
        quiet = 0
        if battN == 3 then
          local w = H.formationWords()
          H.log(string.format("sabin: battle up f%d (%04X %04X %04X %04X " ..
            "%04X %04X)", H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        for slot = 0, 5 do
          if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
            H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end

      -- 3. plain dialog: edge-tap A
      if dlgN >= 3 then quiet = 0; H.setPad(phase < 4 and { "a" } or {}); return end

      -- 4. THE NAME MENU: $0200 == 1 (event cmd $98's marker) AND $0059 ~= 0
      --    (a menu is open).  Debounced 30 frames so the fade into the menu
      --    is not mistaken for the menu itself.
      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0 then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            nameMenusSeen = nameMenusSeen + 1
            H.log(string.format("sabin: NAME MENU #%d at f%d -- $0200=%d " ..
              "$0059=%d $0026=%02X $0027=%02X; START confirms " ..
              "(name_change.asm:85)", nameMenusSeen, H.frame,
              H.readByte(NAME_MENU), H.readByte(0x0059),
              H.readByte(0x0026), H.readByte(0x0027)))
            H.screenshot("sabin_name_menu")
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      -- 5. anything else (fades, map loads, object scripts): hands off
      H.setPad({})
    end),
  }, what)
end

-- n consecutive settled frames of real FIELD control on map m: control,
-- tile-aligned, fully faded in, no battle.  Brightness is not optional -- a
-- cutscene can report control on a black screen (gen_kolts.lua header).
local function landedField(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d): map=%d ctl=%s algn=%s br=%d batt=%s",
        m, map(), tostring(H.hasControl()), tostring(H.tileAligned()),
        bright(), tostring(H.battleLoadStarted())))
    end
    return cnt >= n
  end
end

local function landedWorld(n)
  local cnt = 0
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
           and bright() >= 15
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- worldNavTo with a WRONG-MAP GUARD.  The overworld BFS knows only tile
-- passability -- it has no idea that some passable tiles are doorways -- so
-- a plan that clips a town entrance silently walks into that town, and from
-- then on worldHasControl() is false forever and the walker idles out its
-- whole budget with nothing in the log but a frozen coordinate.  That is
-- exactly how run 1 of this file burned 30,000 frames: leaving SHADOW's
-- house drops the party at (164,35), one tile WEST of the door tile
-- (165,35), and the BFS toward the camp went east through the door on its
-- second step.  Landing on any map other than `want` now fails immediately
-- and says which one.
-- `want` is the field map this leg is ALLOWED to end on (nil = the leg ends
-- on the overworld, at the target tile, and any field map at all is wrong).
local function worldLeg(tx, ty, want, what, budget)
  return H.worldNavTo(tx, ty, {
    maxFrames = budget or 30000,
    arrive = function()
      if H.worldMode() then return false end          -- let the coord check run
      if want and map() == want then return true end
      if H.readByte(0x0084) == 0 and bright() >= 15 then
        error(string.format(
          "%s: fell off the overworld onto map %d at (%d,%d) -- the BFS " ..
          "routed through a doorway (wanted %s)", what, map(), H.fieldX(),
          H.fieldY(), want and tostring(want) or "no map at all"), 0)
      end
      return false
    end,
  })
end

H.run({ maxFrames = 90000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 9, "booted on map 9, the scenario hub")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- SABIN's scenario is not done")
    H.log(string.format("[hub] f%d (%d,%d); SABIN NPC obj 17 at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY(), objX(17), objY(17)))
  end),

  -- ==================================================================== --
  -- 1. PICK SABIN.  _cb0a1c ends on the OVERWORLD, not a field map.
  -- ==================================================================== --
  talkToObj(17, "SABIN's scenario NPC"),
  rideUntil(landedWorld(10), "the overworld landing", 30000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map")
    H.assertEq(H.worldId(), 0, "world 0 (World of Balance)")
    H.assertEq(H.worldX(), 161, "world x = 161 (load_map 0, {161,36})")
    H.assertEq(H.worldY(), 36, "world y = 36")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(3), false, "SHADOW not yet")
    H.log(string.format("[sabin_world] f%d world (%d,%d)",
      H.frame, H.worldX(), H.worldY()))
    H.screenshot("sabin_world")
  end),
  H.saveState("sabin_world.mss"),
  H.logStep(function()
    return string.format("sabin_world minted at frame %d", H.frame)
  end),

  -- ==================================================================== --
  -- 2. SHADOW'S HOUSE.  world (165,35) -> map 115 (7,13).
  -- ==================================================================== --
  worldLeg(165, 35, 115, "to SHADOW's house", 12000),
  rideUntil(landedField(115, 10), "inside the house (map 115)", 12000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 115, "map 115 -- the house on the overworld")
    H.log(string.format("[house] f%d party (%d,%d); objects:",
      H.frame, H.fieldX(), H.fieldY()))
    for i = 16, 19 do
      H.log(string.format("  obj %d at (%d,%d)", i, objX(i), objY(i)))
    end
  end),

  -- talk to the man: dlg, the dog gag, the name menu, then the Yes/No fork
  talkToObj(16, "SHADOW (the man in the house)"),
  rideUntil(function()
    return sw(0x02F3) == 1 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "SHADOW joins ($02F3)", 30000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x02F3), 1, "$02F3 set by _cb0aca -- SHADOW joined")
    H.assertEq(sw(0x000B), 1, "$000B set -- the house scene has played")
    H.assertEq(inParty(3), true, "SHADOW in the party")
    H.assertEq(inParty(5), true, "SABIN still in the party")
    H.assertEq(nameMenusSeen, 1, "exactly one name menu (SHADOW)")
    H.log(string.format("[house] SHADOW joined at f%d, party at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
  end),

  -- ==================================================================== --
  -- 3. OUT AND SOUTH-EAST.  map 115's long entrance is the whole of row
  -- y=15 (x 0..15, `len+1` tiles inclusive -- entrance.asm:69-102) and its
  -- record's destination is used VERBATIM: the run offset is computed into
  -- $26 and then never read (entrance.asm:78 vs :132).  The record says
  -- (165,36); the party actually lands at (164,35), which is one tile west
  -- of the door -- so the table's DestPos is not the whole story and the
  -- route trusts the measurement, not the record.
  --
  -- THE WAYPOINT AT (161,36) IS LOAD-BEARING, not scenery.  It is the
  -- landing tile from step 1, so it is proven passable, and it lies WEST of
  -- the door: from there every shortest path to the camp runs south-east,
  -- and none of them can pass back through (165,35).  Going straight from
  -- (164,35) does not have that property -- see worldLeg's comment.
  -- ==================================================================== --
  H.navTo(7, 15, {
    maxFrames = 8000,
    arrive = function() return H.worldMode() end,
  }),
  rideUntil(landedWorld(10), "back on the overworld", 8000),
  H.waitFrames(30),
  H.logStep(function()
    return string.format("[world] back outside at (%d,%d)",
      H.worldX(), H.worldY())
  end),

  worldLeg(161, 36, nil, "clear of the house door", 8000),
  worldLeg(179, 71, 117, "to the Imperial Camp gate", 30000),
  rideUntil(landedField(117, 10), "inside the Imperial Camp (map 117)", 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 117, "map 117 -- the IMPERIAL CAMP")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(3), true, "SHADOW in the party")
    H.assertEq(sw(0x0044), 0, "$0044 still clear")
    for c = 0, 15 do
      if inParty(c) then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    H.log(string.format("[sabin_camp] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("sabin_camp")
  end),
  H.saveState("sabin_camp.mss"),
  H.logStep(function()
    return string.format("sabin_camp minted at frame %d", H.frame)
  end),
})
