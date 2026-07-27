-- gen_vector_doorstep.lua -- v0.6 leg 1: cold Continue from the versioned
-- post-Opera battery anchor, validate its semantic contract, then walk the
-- world to the VECTOR event trigger and mint the real v0.6 doorstep.
--
-- Unlike the tactical frontier chain, this starts from power-on and lets
-- Mesen load an ordinary .srm from its private save directory.  The anchor
-- contains one valid game in slot 3.
--
-- WHAT THIS REPLACES (issue #17).  The previous version of this generator
-- held RIGHT off the anchor tile until `(mapId & 0x1ff) == 323`, asserted
-- field (2,17), and minted `vector_arrival.mss` logging "entered Vector".
-- **Map 323 is ALBROOK.**  `ff6/src/field/map_prop.dat` is 33 bytes x 415
-- records and byte 0 is the map-title index (`LoadMapProp`,
-- `ff6/src/field/map.asm:143-157`, copies the record to $0520..$0540;
-- `ShowMapTitle`, `ff6/src/field/text.asm:112-119`, indexes MapTitlePtrs
-- with $0520).  Map 323 -> title 53 -> "ALBROOK"; maps 242 and 253 ->
-- title 49 -> "VECTOR".  The east step off the anchor lands in the Albrook
-- short-entrance record at world (138,203)/(139,203), which is why the old
-- assertions were green while standing in the wrong town, and why nothing
-- downstream of it could ever have reached the Magitek Research Facility --
-- map 323's only exits are the four Albrook shops, maps 330/332, and the
-- long entrance back to the world.
--
-- HOW VECTOR IS ACTUALLY ENTERED.  Not by an entrance record at all: there
-- is no entrance anywhere in the game whose destination is map 242 or 253.
-- Vector is a world EVENT TRIGGER --
--
--   ff6/src/event/event_trigger.asm:36-37
--       make_event_trigger {120, 187}, _ca5ecf
--       make_event_trigger {121, 187}, _ca5ecf
--   ff6/src/event/event_main.asm:14196-14200
--       _ca5ecf: set_script_mode WORLD
--                if_switch $0079=1, _ca5edc          ; post-story Vector (253)
--                load_map 242, {32,61}, UP, {Z_UPPER, SHOW_TITLE, ...}
--
-- $0079 is set only at event_main.asm:46316/:97003/:99716, all after v0.6,
-- so on this route the trigger loads map 242 at (32,61) facing UP.  The
-- v0.6 opening is therefore an ordinary ON-FOOT WORLD WALK, not an airship
-- sequence: no vehicle/airship_pos opcode is involved.
--
-- WHY worldGrind AND NOT worldNavTo.  The 31-step walk from the anchor tile
-- (137,203) to (122,187) runs entirely inside the random-battle band (world
-- tile prop bit6 $40 on every tile of the path).  A battle snapshots and
-- restores the party to the same tile (move.asm:916-921 / world_start.asm
-- :465-482), which worldNavTo's verified-step loop reads as "the press
-- never moved us"; it condemns the edge, and with the whole band hot it
-- condemns them all.  That is the failure that broke gen_opera1; the same
-- grind-and-replan walker is used here (see gen_opera1_doorstep.lua:47-76).
--
-- THE POSITIVE CONTROL.  Issue #17's acceptance criterion is that this
-- fixture must fail loudly if the party is on the wrong map, rather than
-- pass because a hard-coded map id matched a constant that was chosen
-- wrong -- which is exactly how the Albrook bug stayed green.  So the
-- landing is checked through the game's OWN map-title machinery: read the
-- live title index the engine loaded into $0520, follow MapTitlePtrs
-- ($E68400) into MapTitle ($CEF100), decode it, and require the string
-- "VECTOR".  A wrong turn now reports the name of the town it is actually
-- standing in.  mapTitleHere() is exercised on the Albrook gate FIRST --
-- the exact step the retired generator took -- so the control cannot pass
-- by returning "" for everything.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local ACTIVE = 0x021f
local ULTROS2 = 0x012d
local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- The map name the ENGINE would print for the map it is standing on.
-- $0520 is map_prop byte 0, copied by LoadMapProp (field/map.asm:143-157);
-- ShowMapTitle (field/text.asm:112-119) uses it exactly this way.  HiROM
-- file offset = cpu & $3FFFFF, so MapTitlePtrs $E68400 -> $268400 and
-- MapTitle $CEF100 -> $0EF100.  Font encoding: $20-$39 A-Z, $3A-$53 a-z,
-- $54-$5D 0-9, $65 '.', $7F space.
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

-- Robust world walk to (tx,ty): re-plan a worldBfs each time the plan runs
-- out, press the next step, kill-bit any encounter.  No edge is ever
-- condemned, so a battle-restored tile is simply retried until a step
-- lands.  Arrives at (tx,ty) or when the party leaves the world map.
local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); plan = nil; H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

H.run({ maxFrames = 80000 }, {
  H.waitFrames(350),
  -- Title -> New Game/Continue -> Continue -> the sole valid slot (3) ->
  -- "This data?" -> field.  Repeated edge presses tolerate title animation
  -- timing while the semantic checks below prevent a false landing.
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl()
      and H.worldAligned()
  end, 3000, "cold Continue to post-Opera world doorstep", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),
  H.call(function()
    H.assertEq(H.readByte(ACTIVE), 3, "Continue loaded save slot 3")
    H.assertEq(sw(0x034b), 0, "anchor: Ultros 2 cleared")
    H.assertEq(sw(0x005d), 1, "anchor: Setzer bargain complete")
    H.assertEq(sw(0x005e), 1, "anchor: Blackjack arrival complete")
    H.assertEq(sw(0x0246), 0, "anchor: Blackjack is active airship")
    H.assertEq(sw(0x0079), 0,
      "anchor: $0079 CLEAR -- the Vector trigger loads map 242, not 253")
    -- The anchor's own world tile.  It is one step WEST OF THE ALBROOK
    -- GATE (the short-entrance records at (138,203)/(139,203)), which is
    -- what the retired generator walked into and called Vector.
    H.assertEq(H.worldX(), 137, "anchor: world x, west of the Albrook gate")
    H.assertEq(H.worldY(), 203, "anchor: world y, west of the Albrook gate")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "anchor: slot 3 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "anchor: slot 3 codex magic 8")
    H.assertEq(emu.read(0x316810 + ULTROS2, emu.memType.snesMemory), 0x01,
      "anchor: bank-31 element-codex witness survived cold Continue")
    H.assertEq(emu.read(0x316990 + ULTROS2, emu.memType.snesMemory), 0x01,
      "anchor: bank-31 class-codex witness survived cold Continue")
  end),

  -- POSITIVE CONTROL: THE PARTY, COUNTED (issue #21).
  --
  -- $1850+charId is verbbppp (ff6/notes/field-ram.txt:928); the low three
  -- bits are the party the character belongs to, 0 for nobody's.
  -- char_party writes it (field/event.asm:563-585) and RemoveChar zeroes it
  -- (battle_main.asm:11927).
  --
  -- This used to be a LOG LINE and nothing else, and that is exactly how
  -- #21 survived a release and a half: the leave-Zozo `party_menu 1,
  -- NO_RESET, {LOCKE, CELES}` was answered with START, the two free slots
  -- were never filled, and the whole v0.5 tail plus every v0.6 leg ran two
  -- characters -- while every fixture below still passed, because each was
  -- asserting story switches and map ids, and a switch cannot say how many
  -- people are walking.  COUNTING the entries is the check that catches a
  -- chain which silently loses (or never gains) a member; it is asserted
  -- here, at the anchor, because this is the boundary every v0.6 balance
  -- number is measured across.
  --
  -- The owner's canonical fixture party is LOCKE, CELES, SABIN, EDGAR
  -- (#21, 2026-07-27): slash, pierce and bludgeon covered with no shop
  -- trip, SABIN answering the Vector band's deliberate OT6_BLUDG row.
  H.call(function()
    local t = {}
    for c = 0, 13 do t[#t + 1] = string.format("%02X", H.readByte(0x1850 + c)) end
    H.log("[roster] $1850+0..13 = " .. table.concat(t, " ")
      .. string.format("  $1EDE=%02X $1EDF=%02X $1A6D=%02X",
        H.readByte(0x1EDE), H.readByte(0x1EDF), H.readByte(0x1A6D)))
    local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
    local n = 0
    for c = 0, 15 do if partyOf(c) ~= 0 then n = n + 1 end end
    H.assertEq(n, 4,
      "anchor: FOUR characters carry a party assignment (#21 -- the count "
      .. "is the control; a two-character chain must fail here, loudly)")
    H.assertEq(partyOf(0x01), 1, "anchor: LOCKE in the party")
    H.assertEq(partyOf(0x06), 1, "anchor: CELES in the party")
    H.assertEq(partyOf(0x05), 1, "anchor: SABIN in the party (bludgeon)")
    H.assertEq(partyOf(0x04), 1, "anchor: EDGAR in the party (pierce+Tools)")
  end),

  -- POSITIVE CONTROL, part 1: prove mapTitleHere() actually reads the
  -- engine's live title and is not just returning "" for everything.  Step
  -- east into the Albrook gate exactly the way the retired generator did,
  -- read the name the game itself would print, and require "ALBROOK" --
  -- the string the old fixture was silently standing on.  Then walk back
  -- out of town so the real leg starts from the anchor tile.
  H.driveUntil(function() return map() == 323 end, 1200, {
    H.hold({ "right" }),
  }, "step RIGHT into the ALBROOK gate (control probe)"),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "Albrook control", 5),
  H.call(function()
    H.assertEq(map(), 323, "control probe: map 323")
    H.assertEq(mapTitleHere(), "ALBROOK",
      "CONTROL: map 323's own title reads ALBROOK -- this is the town the "
      .. "retired vector_arrival fixture was standing in")
    H.log(string.format("[control] map=%d title=%q at (%d,%d)",
      map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.screenshot("v06_control_albrook")
  end),
  -- Back out.  Map 323's world exits are LONG entrances on its west and
  -- north edges (decoded from LongEntrance, $EDF480/$EDF882): a vertical
  -- run at x=0, y=0..29 -> world (137,203), and two horizontal runs at
  -- y=0 and y=1, x=0..31 -> world (138,202).  The party lands at (2,17),
  -- so LEFT reaches the column and UP reaches the rows; alternate the two
  -- rather than assume which lane is open from this tile.
  (function() local hb = 0
    return H.driveUntil(function() return H.worldMode() end, 8000, {
      H.call(function() hb = hb + 1
        if H.battleLoadStarted() then
          killBitAll(); H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        H.setPad(hb % 240 < 120 and { left = true } or { up = true })
      end) }, "back out of Albrook to the world") end)(),
  -- $E0/$E2 read (0,0) for tens of frames after the exit fires -- world
  -- control and full brightness both come back BEFORE InitWorld has
  -- written the position from $1F60.  Gate on the destination tile itself
  -- (the x=0 column's LongEntrance DestPos) so the log and the leg below
  -- both start from a real coordinate.
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() == 137 and H.worldY() == 203
  end, 2400, "back on the world at (137,203), the anchor tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldX(), 137, "back on the world: x")
    H.assertEq(H.worldY(), 203, "back on the world: y")
  end),

  -- LEG 1: the world walk.  31 steps, every tile battle-enabled.
  worldGrind(122, 187, "world walk -> the Vector trigger approach (122,187)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned()
  end, 2400, "at the Vector trigger approach", 5),
  H.call(function()
    H.assertEq(H.worldX(), 122, "trigger approach x")
    H.assertEq(H.worldY(), 187, "trigger approach y")
    H.log(string.format("[world] at the Vector trigger approach (%d,%d)",
      H.worldX(), H.worldY()))
  end),

  -- one LEFT step onto (121,187) fires _ca5ecf -> load_map 242 {32,61}
  (function() local hb = 0
    return H.driveUntil(function() return not H.worldMode() and map() == 242 end,
      6000, {
      H.call(function() hb = hb + 1
        if H.battleLoadStarted() then
          killBitAll(); H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        H.setPad({ left = true })
      end) }, "step LEFT onto (121,187) -> the Vector trigger") end)(),
  H.waitUntil(function()
    return map() == 242 and H.hasControl() and H.tileAligned()
      and bright() >= 15 and not H.dialogWaiting()
  end, 6000, "Vector control", 5),
  H.waitFrames(120),

  H.call(function()
    -- POSITIVE CONTROL, part 2: the same live title read that returned
    -- "ALBROOK" above must now return "VECTOR".  This is the assertion
    -- issue #17 asks for -- it names the town the party is standing in
    -- rather than agreeing with a constant.
    H.assertEq(mapTitleHere(), "VECTOR",
      "the map the party is standing on calls itself VECTOR")
    H.assertEq(map(), 242, "Vector town is map 242")
    H.assertEq(H.fieldX(), 32, "Vector arrival x (_ca5ecf load_map 242 {32,61})")
    H.assertEq(H.fieldY(), 61, "Vector arrival y")
    H.assertEq(sw(0x01F0), 0, "$01F0 CLEAR -- the old man's distraction has not run")
    H.assertEq(sw(0x062B), 1, "$062B SET -- the three gate guards are present")
    H.assertEq(sw(0x063B), 1, "$063B SET -- the Returner sympathizer is present")
    H.assertEq(sw(0x006B), 0, "$006B CLEAR -- the factory escape has not happened")
    H.log(string.format("[vector_doorstep] f%d map=%d title=%q (%d,%d)",
      H.frame, map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.screenshot("vector_doorstep")
  end),
  H.saveState("vector_doorstep.mss"),
  H.logStep(function()
    return string.format(
      "cold battery Continue walked the world into VECTOR (map 242, %q) "
      .. "and minted vector_doorstep at frame %d", mapTitleHere(), H.frame)
  end),
})
