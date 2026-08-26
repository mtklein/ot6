-- gen_vector_sneak.lua -- v0.6 step 2: vector_entry (VECTOR, map 242,
-- {32,61}) -> the Returner sympathizer at {45,39} -> his choice dialog ->
-- the facing-gated sneak ledge at {43,38} -> control back at {57,34}, north
-- of both the gate guards and the "You!? How'd you get in here?" trigger row.
-- Generates vector_sneak.

-- Why navTo cannot reach the MAGITEK FACTORY door from the arrival tile.
-- The door is map 242's long entrance at (57,2) len 2 -> map 262 (28,8).
-- The corridor to it is three parallel lanes at y=39/40/41 and each lane is
-- plugged by a guard NPC at (54,39), (55,40) and (54,41) (npc_prop.asm:10777,
-- :10784, :10791), all behind visibility switch $062B, which is 1 at new
-- game (`ff6/src/field/init_npc_switch.dat` -> InitNPCSwitches,
-- field/obj.asm:176-184) and is cleared exactly once, at
-- event_main.asm:96986, after the factory escape.  The passability model
-- refuses a tile an object stands on (ot6_field.lua:166-168), so navTo(57,2)
-- from the south is a genuine NO-PATH and would use its 20 retries and then
-- error.  Behind the guards is a further problem: event_trigger.asm:1070-1072
-- puts an ungated trigger on (56,39)/(57,39)/(58,39) -> _cc93dc (:99473) ->
-- dlg $06B0 -> `battle 29` -> load_map 242 {34,58}, i.e. a forced fight and
-- a teleport back to the south of the map.

-- The intended way in, and the two things about it a walker cannot discover:

--  1. The old man is a choice dialog.  npc_prop.asm:10770 puts the Returner
--     sympathizer at {45,39} behind switch $063B with event _cc9627
--     (event_main.asm:99897).  It ends `dlg $054E` ("All ready? 0: Yes
--     1: No") + `choice _cc9659, _cc96bd`; only branch 0 runs the drunk act
--     and only its tail sets `switch $01F0=1` (:100017).  Branch 1 does
--     nothing.  So the pick is driven by value off the cursor
--     ($056E) and the choice count ($056F), the gen_zozo3_clock idiom.

--  2. The ledge is facing-gated.  event_trigger.asm:1067 puts _cc96c9 on
--     {43,38}; event_main.asm:100025-100029 opens with

--         if_any
--                 switch $01F0=0
--                 switch $01B2=0
--                 goto EventReturn

--     and $01B2 is not a story switch.  Switch $01B0-$01B7 alias $1EB6,
--     the engine's live facing/A/tile-latch byte, which UpdateCtrlFlags
--     rewrites every event tick from the party facing byte $087F,y and the
--     A-button state (field/event.asm:5415-5433, called at :92;
--     notes/field-ram.txt:1072-1080).  $01B2 means the party is facing DOWN.
--     navTo releases the pad between steps and plans by shortest path, so
--     it can arrive on {43,38} from the east facing LEFT, and the trigger
--     then does nothing.  The party must arrive by stepping DOWN
--     from {43,37}, which is why this step navTos to {43,37} and then drives
--     a held DOWN rather than navTo-ing the trigger tile.

-- Where it ends.  _cc96c9's SLOT_1 obj_script walks the party over
-- non-walkable rooftop tiles: {43,38} -> {42,38} -> {41,38} -> {41,35} ->
-- {49,35} -> {49,34} -> {54,34} -> {54,35} -> {57,35} -> {57,34}, then
-- `switch $01F0=0` and `player_ctrl_on` (event_main.asm:100029-100105).
-- (57,34) is confirmed live below; it was read off the move list, which the
-- route recon listed as an open probe.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local fighter = H.newFightDriver("vector_sneak",
  { tactical = true, boost = true })
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

-- Log the live party: $1850+charId is verbbppp -- v visible, e enabled,
-- r battle row, bb battle order, ppp party number (notes/field-ram.txt:928).
-- A character is in the active party iff its ppp equals $1A6D.
local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      -- character data is $1600 + 37*c (notes/field-ram.txt:884): +$08
      -- level, +$1F weapon, +$20 shield, +$21 helmet, +$22 armor.
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

-- Drive an NPC conversation that ends in a `choice`, picking index `idx`,
-- until switch `doneId` latches.  Same shape as gen_zozo3_clock's clockPick:
-- $056F is the choice count (0 while ordinary text pages are up) and $056E
-- is a linear cursor moved one step per d-pad edge.  Terminating on
-- dialogWaiting would confirm with no menu up, because $BA/$D3 dip between
-- pages.
local function talkPick(idx, doneId, maxFrames, what)
  local ph = 0
  return H.driveUntil(function() return sw(doneId) == 1 end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if sw(doneId) == 1 then H.setPad({}); return end
      if H.battleLoadStarted() then
        fighter.frame(); return
      end
      fighter.idle()
      local d3, maxc, cur =
        H.readByte(0x00d3), H.readByte(0x056f), H.readByte(0x056e)
      if maxc >= 2 then                        -- the choice list is up
        if cur < idx then H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then H.setPad(ph < 3 and { "up" } or {})
        else H.setPad(ph < 3 and { "a" } or {}) end
      elseif d3 == 1 then                      -- a text page: advance it
        H.setPad(ph < 3 and { "a" } or {})
      elseif settled() then
        -- back in control with the switch still clear: the party is
        -- standing below the old man and has not started, or has dropped
        -- out of, the conversation.  Face DOWN and press A.
        H.setPad(ph < 4 and { "a", "down" } or { "down" })
      else
        H.setPad({})                           -- scene running: hands off
      end
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/vector_entry.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(mapTitleHere(), "VECTOR", "booted in VECTOR (live map title)")
    H.assertEq(map(), 242, "booted on map 242")
    H.assertEq(H.fieldX(), 32, "boot x")
    H.assertEq(H.fieldY(), 61, "boot y")
    H.assertEq(sw(0x01F0), 0, "$01F0 CLEAR at boot")
    H.log(partyReport("vector_entry"))
  end),

  H.navTo(45, 38, { maxFrames = 40000, playBattles = "tactical" }),
  H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.fieldX(), 45, "at the sympathizer's entry point x")
    H.assertEq(H.fieldY(), 38, "at the sympathizer's entry point y")
    H.assertEq(facing(), 2, "facing DOWN toward the sympathizer (EVENT_DIR 2)")
    H.log(string.format("[oldman] at (%d,%d) facing %d $01F0=%d",
      H.fieldX(), H.fieldY(), facing(), sw(0x01F0)))
    H.screenshot("vector_oldman")
  end),

  -- 2. talk him through to the choice and pick 0 (Yes) -> _cc9659 -> the
  --    drunk act -> switch $01F0=1 (event_main.asm:100017).
  talkPick(0, 0x01F0, 20000, "the sympathizer's choice: 0 = Yes -> $01F0"),
  H.waitUntil(settled, 3000, "control back after the drunk act", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 SET -- the soldiers are distracted")
    H.log(string.format("[distracted] at (%d,%d) $01F0=%d",
      H.fieldX(), H.fieldY(), sw(0x01F0)))
    H.screenshot("vector_distracted")
  end),

  -- 3. the facing-gated ledge.  navTo {43,37}, then hold DOWN: the step
  --    onto {43,38} leaves the party facing DOWN, which is the $01B2 the
  --    trigger requires.  A navTo straight to {43,38} could arrive facing
  --    LEFT, and the trigger would then do nothing.
  H.navTo(43, 37, { maxFrames = 30000, playBattles = "tactical" }),
  H.call(function()
    H.assertEq(H.fieldX(), 43, "above the sneak ledge x")
    H.assertEq(H.fieldY(), 37, "above the sneak ledge y")
    H.log(string.format("[ledge] poised at (%d,%d) $01F0=%d",
      H.fieldX(), H.fieldY(), sw(0x01F0)))
  end),
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() == 57 and H.fieldY() == 34 and settled()
    end, 20000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          fighter.frame(); return
        end
        fighter.idle()
        if H.dialogWaiting() then
          H.setPad(ph < 4 and { "a" } or {}); return
        end
        if not H.hasControl() then H.setPad({}); return end
        -- still controllable: press DOWN.  From {43,37} that steps onto the
        -- trigger facing DOWN; once on {43,38} the press is refused by the
        -- wall below and holds the facing the trigger needs.
        H.setPad({ down = true })
      end),
    }, "step DOWN onto {43,38} -> the sneak scene -> control at (57,34)")
  end)(),

  H.waitFrames(60),
  H.call(function()
    H.assertEq(mapTitleHere(), "VECTOR", "still in VECTOR after the sneak")
    H.assertEq(map(), 242, "still on map 242")
    H.assertEq(H.fieldX(), 57, "sneak exit x -- PROBE 9 of the route recon")
    H.assertEq(H.fieldY(), 34, "sneak exit y -- PROBE 9 of the route recon")
    H.assertEq(sw(0x01F0), 0, "$01F0 cleared by the scene tail (:100104)")
    H.assertEq(sw(0x062B), 1, "$062B still SET -- the guards are still standing")
    -- The party is now north of the trigger row (56..58,39) and of the guard
    -- lanes, so the column to the factory door is clear.  Assert that the
    -- door tile is reachable now, which is the point of this step: it was
    -- NO-PATH from the arrival tile.
    H.assertEq(H.bfsPath(57, 2) ~= nil, true,
      "the factory door (57,2) is now reachable -- it was NO-PATH before the sneak")
    H.log(string.format("[vector_sneak] f%d map=%d (%d,%d) door plan=%d steps",
      H.frame, map(), H.fieldX(), H.fieldY(), #H.bfsPath(57, 2)))
    H.log(partyReport("vector_sneak"))
    H.screenshot("vector_sneak")
  end),
  H.saveState("vector_sneak.mss"),
  H.logStep(function()
    return string.format(
      "vector_sneak generated at frame %d -- VECTOR (57,34), past the gate guards",
      H.frame)
  end),
})
