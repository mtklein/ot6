-- gen_rapids.lua -- from scenario_hub.mss into TERRA/BANON/EDGAR's scenario:
-- the resumed raft ride down the lower LETE RIVER and the landing on the
-- World of Balance north-east of Narshe.
-- Mints two states:
--   rapids_start.mss  map 113 at the ride's re-entry tile (104,61), TERRA +
--                     EDGAR + BANON aboard with the RAFT sprite, upstream of
--                     the leg's one FORCED fight -- the cheap doorstep for
--                     anything that wants `battle 8, RIVER` without replaying
--                     the hub.
--   rapids_done.mss   the World of Balance at (93,41), on foot and
--                     controllable: the ride finished, the overland walk to
--                     Narshe not started.  gen_terra_narshe rides from here.
--
-- ONE EVENT, THREE DOORS.  BANON {8,10}, TERRA {7,11} and EDGAR {9,11} on the
-- hub map are three NPCs with ONE `set_npc_event _cb094e` between them
-- (npc_prop.asm:489, :497, :505) -- the split is three ways, not five, and
-- which of the three you talk to cannot matter.  TERRA (obj 19) is the one
-- taken here, and only because the states are named for her.
--
-- ===================== THE UPSTREAM LEG'S TWO TRAPS ARE NOT HERE ==========
-- gen_scenario.lua's river needed a steering driver and two hand-walked
-- handoffs.  This continuation needs NEITHER, and the reason is worth
-- writing down rather than rediscovering: _cb094e (:39355-39461) contains no
-- `choice` opcode and no `player_ctrl_on` between its map load and its last
-- `wait_obj`.  Read the whole event and what is left is four
-- `obj_script SLOT_1, ASYNC { move … }` / `wait_obj SLOT_1` pairs with
-- battles between them.  Specifically:
--
--   * THE VANILLA GRIND LOOP IS UPSTREAM.  It is _cb07f2's option 0
--     (:39152-39197, `if_switch $0176=0, _cb07f2`), reached from the ride
--     _cb0657 starts.  This event re-enters map 113 at (104,61) -- past it.
--     Nothing on this leg ever asks the player which way to go, so the
--     driver below does not steer a cursor; it ASSERTS that no multiple
--     choice ever opens ($056F >= 2 while the dialog is input-ready is a
--     hard error), which is the same fact stated as a test.
--   * THE FACING-DOWN HANDOFFS ARE MAP 114'S.  _cb051c/_cb055c both open
--     `if_switch $01B2=0, EventReturn` -- $01B2 being bit 2 of $1EB6, the
--     engine's live control-flags byte, i.e. "facing down"
--     (field/event.asm:5415-5432) -- and they are EventTrigger::_114's
--     (event_trigger.asm:464-468).  This leg never loads map 114.  It runs
--     113 -> world, end of story.
--
-- CONTROL IS ON FOR THE ENTIRE RIDE, so hasControl() is not a progress gate
-- here and is never used as one below.  :39391 `call _cacb95`, and _cacb95
-- ends `update_party / player_ctrl_on` (:31276-31283), runs BEFORE
-- `load_map 113`.  The field control flag therefore reads true from the
-- first frame on the raft while the object script owns SLOT_1's movement
-- anyway.  Every gate in this script is map id + position + the world-mode
-- word; the pad is neutral except for A into a battle or an open dialog.
--
-- THE LEG HAS ONE FORCED FIGHT AND UP TO TWO MORE ON A COIN FLIP.  The
-- survey called `battle 8, RIVER` (:39412) "the scenario's only combat",
-- which is true of the FORCED ones and not of the leg:
--       :39428  call _cb048f   ->  if_rand ; battle 8, RIVER   (:38659-38666)
--       :39446  call _cb0486   ->  if_rand ; battle 7, RIVER   (:38653-38658)
-- are both real, both on this leg's critical path, and each fires about half
-- the time.  So the driver names and logs EVERY battle it clears, and the
-- run's battle count is reported rather than assumed.
--
-- WHAT `battle N` RESOLVES TO (field/event.asm EventBattle, :1910-1922): the
-- group index is scaled by FOUR -- two formation words per group -- and
-- UpdateBattleGrpRng takes the second word 1/4 of the time.  So from
-- event_battle_group.dat: group 8 -> formation 35 (3/4) or 37 (1/4); group 7
-- -> formation 38 (3/4) or 39 (1/4).  The species, hp and OT6 shield counts
-- are read off battle RAM on each fight's rising edge and logged, because a
-- balance claim about this leg has to rest on what the ROM actually seeds.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local HUB = "/Users/mtklein/ot6/build/states/scenario_hub.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function seq(steps) return H.cond(function() return true end, steps) end

-- multiple-choice state (src/field/text.asm): $056F is the option count and
-- is only final once the dialog is input-ready; it is field RAM the battle
-- module scribbles, so it is never read during a fight.
local CH_MAX = 0x056F
-- battle readouts: species $57c0+2i, hp $3bfc+2i, shields $3e40+2i
-- (even = current, odd = max -- metrics_battle.lua:110)
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monMaxHp(i) return H.readWord(0x3c1c + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}

-- gen_scenario_locke's talkToObj, unchanged: approach re-resolved every 30
-- frames, facing computed from the live delta, a soft round before a hard one.
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

-- ------------------------------------------------------------ the driver --
-- Kill-bit every battle, tap every dialog, refuse every choice, touch
-- nothing else.  `fights` accumulates one row per fight so the run can
-- report what it actually met instead of what the route expected.
local fights = {}
local function rideUntil(pred, what, budget)
  local phase, battN, dlgN, hb = 0, 0, 0, -900
  return H.driveUntil(pred, budget or 40000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("rapids f%d map=%d (%d,%d) ctl=%s batt=%s dlg=%s " ..
          "ev=%s bright=%d chMax=%d world=%s fights=%d",
          H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), bright(), H.readByte(CH_MAX),
          tostring(H.worldMode()), #fights))
      end

      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0

      -- 1. A CHOICE HERE WOULD MEAN THE ROUTE IS WRONG.  _cb094e has no
      --    `choice` opcode, so any prompt with >= 2 options is a fork this
      --    file does not know about -- and A-mashing an unknown fork on this
      --    river is exactly how the upstream leg found the vanilla grind
      --    loop.  Fail loudly instead.  Read only when no battle is up (the
      --    battle module scribbles $056F) and only once the dialog is
      --    input-ready (it counts options as the text types out,
      --    field/text.asm:684).
      if battN == 0 and H.dialogWaiting() and H.readByte(CH_MAX) >= 2 then
        H.screenshot("rapids_unexpected_choice")
        error(string.format("rapids: a %d-option choice opened on map %d at " ..
          "f%d -- _cb094e has no `choice` opcode, so the route is wrong",
          H.readByte(CH_MAX), map(), H.frame), 0)
      end

      -- 2. battle: name it once on the rising edge, then kill-bit it
      if battN >= 3 then
        if battN == 3 then
          local w = H.formationWords()
          local row = { frame = H.frame, slots = {} }
          H.log(string.format("rapids: BATTLE #%d up f%d formation words " ..
            "(%04X %04X %04X %04X %04X %04X)", #fights + 1, H.frame,
            w[1], w[2], w[3], w[4], w[5], w[6]))
          for i = 0, 5 do
            if monPresent(i) then
              H.log(string.format("   slot %d species $%04X hp=%d/%d shields=%d",
                i, monSpecies(i), monHp(i), monMaxHp(i), monShields(i)))
              row.slots[#row.slots + 1] = {
                sp = monSpecies(i), hp = monMaxHp(i), sh = monShields(i) }
            end
          end
          fights[#fights + 1] = row
          H.screenshot(string.format("rapids_battle%d", #fights))
        end
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if monPresent(slot) then
              H.writeByte(0x3eec + slot * 2,
                H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end

      -- 3. plain dialog: edge-tap through it ($0168's "…ride the rapids
      --    toward Narshe" is TEXT_ONLY but still waits for a keypress)
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end

      -- 4. the raft moving, fades, map loads: hands off
      H.setPad({})
    end),
  }, what)
end

-- n consecutive frames on `m` with the screen fully up and no fight running.
-- Says why it is not satisfied every 600 frames: a settle predicate that just
-- returns false is the worst thing in this harness to debug.
local function onMap(m, n)
  local cnt, hb = 0, -600
  return function()
    local okMap, okBright = map() == m, bright() >= 15
    local okBatt = not H.battleLoadStarted()
    local ok = okMap and okBright and okBatt
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("onMap(%d) f%d blocked: map=%s(%d) bright=%s(%d) " ..
        "batt=%s at (%d,%d) ev=%s", m, H.frame, tostring(okMap), map(),
        tostring(okBright), bright(), tostring(okBatt),
        H.fieldX(), H.fieldY(), tostring(H.eventRunning())))
    end
    return cnt >= (n or 20)
  end
end

local function onWorld(n)
  local cnt, hb = 0, -600
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
           and bright() >= 15 and not H.battleLoadStarted()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("onWorld f%d blocked: $1F64=%04X world=%s ctl=%s " ..
        "algn=%s bright=%d batt=%s field=(%d,%d) map=%d", H.frame,
        H.readWord(0x1f64), tostring(H.worldMode()),
        tostring(H.worldHasControl()), tostring(H.worldAligned()), bright(),
        tostring(H.battleLoadStarted()), H.fieldX(), H.fieldY(), map()))
    end
    return cnt >= (n or 20)
  end
end

local function logParty(tag)
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local base = 0x1600 + 37 * c
      H.log(string.format("%s char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
        tag, c, H.readByte(base), H.readByte(base + 8),
        H.readWord(base + 9), H.readWord(base + 11),
        H.readWord(base + 13), H.readWord(base + 15)))
    end
  end
end

H.run({ maxFrames = 120000 }, {
  H.loadState(HUB),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 9, "booted on map 9, the scenario hub")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, true,
      "SCENARIO_MOG (char 13) is the party")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- TERRA/BANON's scenario not done")
    H.assertEq(sw(0x032C), 1, "$032C set -- TERRA's scenario NPC is on the map")
    H.assertEq(sw(0x0133), 1,
      "$0133 set -- the (8,6) save point takes its short, ctrl-restoring path")
    local p = H.bfsPath(objX(19), objY(19) + 1)
    H.log(string.format("[hub] f%d at (%d,%d); TERRA obj 19 at (%d,%d), " ..
      "approach from below: %s", H.frame, H.fieldX(), H.fieldY(),
      objX(19), objY(19), p and (#p .. " steps") or "no path"))
  end),

  -- ===================================================================== --
  -- ENTER.  Talk to TERRA (obj 19, {7,11}) -> _cb094e.
  -- ===================================================================== --
  talkToObj(19, "TERRA's scenario NPC"),

  -- ===================================================================== --
  -- THE RIDE, PART 1: the hub tear-down, dlg $0168, and `load_map 113,
  -- {104,61}`.  Mint before the forced fight so a battle test can boot here.
  -- ===================================================================== --
  rideUntil(onMap(113, 20), "the raft re-entry on map 113", 30000),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 113, "on map 113, the LETE RIVER, aboard the raft")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(#fights, 0, "minted UPSTREAM of the forced fight")
    H.assertEq(H.readByte(CH_MAX), 0, "no choice prompt open")
    -- the party _cb094e assembled: TERRA (0) + EDGAR (4) + BANON (14).
    -- $185E is the byte that settles the WEDGE/BANON symbol collision:
    -- const.inc gives both id 14 and the disassembly's picker prints the
    -- first match, so the event reads `vehicle WEDGE` and means Banon.
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA in the party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, true, "EDGAR in the party")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true,
      "BANON in the party ($185E -- char 14, the `WEDGE` the event names)")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, false, "SCENARIO_MOG gone")
    H.assertEq(sw(0x0021), 0, "$0021 still clear -- the scenario is not done")
    logParty("[rapids_start]")
    H.log(string.format("[rapids_start] f%d map=%d (%d,%d) bright=%d ctl=%s",
      H.frame, map(), H.fieldX(), H.fieldY(), bright(),
      tostring(H.hasControl())))
    H.screenshot("rapids_start")
  end),
  H.saveState("rapids_start.mss"),
  H.logStep(function()
    return string.format("rapids_start minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- THE RIDE, PART 2: `battle 8, RIVER`, the two if_rand fights, and the
  -- spill onto the World of Balance at (93,41) (:39455-39459).
  -- ===================================================================== --
  rideUntil(onWorld(20), "the rest of the rapids, out onto the world map",
    70000),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map (set_script_mode WORLD)")
    H.assertEq(H.readWord(0x1f64) & 0x3FF, 0, "on the World of Balance")
    H.assertEq(H.worldX(), 93, "world spawn x=93 (`load_map 0, {93,41}`)")
    H.assertEq(H.worldY(), 41, "world spawn y=41")
    H.assertEq(H.readByte(0x11fa) & 0x03, 0,
      "on foot -- the RAFT sprite was cosmetic and `vehicle … NONE` cleared it")
    H.assertEq(H.worldHasControl(), true, "controllable")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x0021), 0, "$0021 still clear -- the scenario is not done")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON still aboard")
    H.assertEq(#fights >= 1, true,
      string.format("the forced `battle 8, RIVER` was met (%d fights)", #fights))
    for i, f in ipairs(fights) do
      local parts = {}
      for _, s in ipairs(f.slots) do
        parts[#parts + 1] = string.format("$%04X hp%d sh%d", s.sp, s.hp, s.sh)
      end
      H.log(string.format("[battles] #%d f%d: %s", i, f.frame,
        table.concat(parts, " | ")))
    end
    logParty("[rapids_done]")
    H.log(string.format("[rapids_done] f%d world (%d,%d) $1F64=%04X",
      H.frame, H.worldX(), H.worldY(), H.readWord(0x1f64)))
    H.screenshot("rapids_done")
  end),
  H.saveState("rapids_done.mss"),
  H.logStep(function()
    return string.format("rapids_done minted at frame %d, %d fights cleared",
      H.frame, #fights)
  end),
})
