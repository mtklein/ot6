-- gen_vector_sneak.lua -- v0.6 leg 2: vector_doorstep (VECTOR, map 242,
-- {32,61}) -> the Returner sympathizer at {45,39} -> his choice dialog ->
-- the FACING-GATED sneak ledge at {43,38} -> control back at {57,34}, north
-- of both the gate guards and the "You!? How'd you get in here?" trap row.
-- Mints vector_sneak.
--
-- WHY THE MAGITEK FACTORY DOOR IS NOT navTo-ABLE FROM THE ARRIVAL TILE.
-- The door is map 242's long entrance at (57,2) len 2 -> map 262 (28,8).
-- The corridor to it is three parallel lanes at y=39/40/41 and each lane is
-- plugged by a guard NPC -- (54,39), (55,40), (54,41), npc_prop.asm:10777,
-- :10784, :10791, all behind visibility switch $062B, which is 1 at new
-- game (`ff6/src/field/init_npc_switch.dat` -> InitNPCSwitches,
-- field/obj.asm:176-184) and is cleared exactly once, at
-- event_main.asm:96986, AFTER the factory escape.  The passability model
-- refuses a tile an object stands on (ot6_field.lua:166-168), so navTo(57,2)
-- from the south is a genuine NO-PATH and would burn its 20 retries and
-- error.  Behind the guards is worse: event_trigger.asm:1070-1072 puts an
-- UNGATED trigger on (56,39)/(57,39)/(58,39) -> _cc93dc (:99473) ->
-- dlg $06B0 -> `battle 29` -> load_map 242 {34,58}, i.e. a forced fight and
-- a teleport back to the south of the map.
--
-- THE INTENDED WAY IN, and the two things about it a walker cannot discover:
--
--  1. THE OLD MAN IS A CHOICE DIALOG.  npc_prop.asm:10770 puts the Returner
--     sympathizer at {45,39} behind switch $063B with event _cc9627
--     (event_main.asm:99897).  It ends `dlg $054E` ("All ready? 0: Yes
--     1: No") + `choice _cc9659, _cc96bd`; only branch 0 runs the drunk act
--     and only its tail sets `switch $01F0=1` (:100017).  Branch 1 does
--     nothing at all.  So the pick has to be driven by VALUE off the cursor
--     ($056E) and the choice count ($056F), the gen_zozo3_clock idiom.
--
--  2. THE LEDGE IS FACING-GATED.  event_trigger.asm:1067 puts _cc96c9 on
--     {43,38}; event_main.asm:100025-100029 opens with
--
--         if_any
--                 switch $01F0=0
--                 switch $01B2=0
--                 goto EventReturn
--
--     and **$01B2 is not a story switch**.  Switch $01B0-$01B7 alias $1EB6,
--     the engine's live facing/A/tile-latch byte, which UpdateCtrlFlags
--     rewrites every event tick from the party facing byte $087F,y and the
--     A-button state (field/event.asm:5415-5433, called at :92;
--     notes/field-ram.txt:1072-1080).  $01B2 = "the party is facing DOWN".
--     navTo releases the pad between steps and plans by shortest path, so
--     it will happily arrive on {43,38} from the east facing LEFT and the
--     trigger will silently no-op.  The party must arrive by stepping DOWN
--     from {43,37}, which is why this leg navTos to {43,37} and then drives
--     a held DOWN rather than navTo-ing the trigger tile.
--
-- WHERE IT ENDS.  _cc96c9's SLOT_1 obj_script walks the party over
-- non-walkable rooftop tiles: {43,38} -> {42,38} -> {41,38} -> {41,35} ->
-- {49,35} -> {49,34} -> {54,34} -> {54,35} -> {57,35} -> {57,34}, then
-- `switch $01F0=0` and `player_ctrl_on` (event_main.asm:100029-100105).
-- (57,34) confirmed live below -- it was read off the move list, which is
-- probe item 9 in docs/design/vector-route-recon.md.
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
-- A character is IN the active party iff its ppp equals $1A6D.
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
-- is a LINEAR cursor moved one step per d-pad EDGE.  Terminating on
-- dialogWaiting would confirm into the void -- $BA/$D3 dip between pages.
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
        -- back in control with the switch still clear: we are standing
        -- below the old man and have not started (or have fallen out of)
        -- the conversation.  Face DOWN and press A.
        H.setPad(ph < 4 and { "a", "down" } or { "down" })
      else
        H.setPad({})                           -- scene running: hands off
      end
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/vector_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(mapTitleHere(), "VECTOR", "booted in VECTOR (live map title)")
    H.assertEq(map(), 242, "booted on map 242")
    H.assertEq(H.fieldX(), 32, "boot x")
    H.assertEq(H.fieldY(), 61, "boot y")
    H.assertEq(sw(0x01F0), 0, "$01F0 CLEAR at boot")
    H.log(partyReport("vector_doorstep"))
  end),

  -- 1. up to {45,38}, directly ABOVE the sympathizer at {45,39}.  This was
  --    a navTo haul followed by a local tapWalk for the last tiles, because
  --    the pre-#22 navTo could not come to rest on an odd x reached
  --    rightward; the library lands exactly now, so one navTo does it.
  --    A DOWN press on {45,38} cannot step (his object occupies {45,39})
  --    so it only turns the party -- the standard face-an-NPC idiom.
  H.navTo(45, 38, { maxFrames = 40000, honest = "tactical" }),
  H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.fieldX(), 45, "at the sympathizer's doorstep x")
    H.assertEq(H.fieldY(), 38, "at the sympathizer's doorstep y")
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
  --    trigger demands.  A navTo straight to {43,38} would be free to
  --    arrive facing LEFT and the trigger would no-op silently.
  H.navTo(43, 37, { maxFrames = 30000, honest = "tactical" }),
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
        -- still ours: press DOWN.  From {43,37} that steps onto the
        -- trigger facing DOWN; once on {43,38} the press is refused by the
        -- wall below and simply holds the facing the trigger needs.
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
    -- The party is now NORTH of the trap row (56..58,39) and of the guard
    -- lanes; the column to the factory door is clear.  Assert that the
    -- door tile is reachable NOW, which is the whole point of this leg --
    -- it was NO-PATH from the arrival tile.
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
      "vector_sneak minted at frame %d -- VECTOR (57,34), past the gate guards",
      H.frame)
  end),
})
