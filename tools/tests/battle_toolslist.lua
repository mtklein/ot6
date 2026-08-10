-- @suite frontier=kolts_cave
-- battle_toolslist.lua -- menu-bank: the Tools window prices each tool.
--
-- v0.5 costs every ability MP; the menu-bank modules SHOW the price beside the
-- name so the charge is not a hidden tax.  Blitz did it first (battle_blitzlist)
-- in the tools-shell's two columns; this is the same feature on the REAL tools
-- window (Edgar, cmd $09), which is genuine inventory built by vanilla's
-- MakeToolsList -- NOT Ot6BlitzListOpen -- so the injection point differs.
--
-- FIT FINDING (documented, the way the Blitz commit documented its 2-column
-- win): the tools window is two columns of 13-wide ITEM names, and those names
-- already fill the row edge to edge (verified by rendering the bare window --
-- AutoCrossbow/NoiseBlaster reach the right border).  A Blitz-style cost AFTER
-- each name overflows the screen, and a true single column -- which would fit a
-- trailing cost -- needs the fixed 4x2 tools grid to SCROLL, i.e. re-cutting the
-- shared item/throw cursor+draw state machine.  So Ot6ToolRowDecorate (ot6.asm,
-- bank F0) stamps the cost in the row's LEADING space pair instead: the
-- template's two leading spaces before name 1 and its two-space column gap
-- before name 2 are each exactly the two tiles ListText cmd $02 draws a 2-digit
-- number into.  Same 31-tile width, all 8 tools, no re-layout; the price reads
-- immediately left of the name it belongs to.  DrawToolsListText jsl's the shim
-- for real-tools rows (the not-blitz arm); the cost gating lives in the battle
-- object, so the shared C1 bank and the nomp baseline are untouched.
--
-- ISSUE #75 CONVERSION -- the tools are OWNED and the fight is REAL.  This
-- file used to install CHAR::EDGAR into every slot of the magitek intro
-- party, hand-write eight tool records into the battle item buffer, pin HP
-- and MP, and rewrite the $202E command rows.  All of that is gone: it now
-- boots kolts_cave (party TERRA LOCKE EDGAR -- the real Edgar, whose record
-- carries Tools), paces the cave lane until a natural encounter fires
-- (battle_naturalmp's drive, same fixture), waits for EDGAR's own menu, and
-- opens his real Tools window.  The list is therefore vanilla MakeToolsList
-- over the REAL BAG -- the AutoCrossbow Edgar starts with plus the
-- BioBlaster and NoiseBlaster gen_edgar BUYS from the Figaro tool merchant
-- -- and the expected rows are derived from the battle inventory's own
-- $40-flagged records, so a future purchase adds a row without touching
-- this file.  Prices are read from Ot6AbilityCostTbl in the ROM (the table
-- Ot6CostFor charges from), not written down, so a retune moves both sides.
--
-- What is asserted:
--   1. THE LIST PACKS THE OWNED TOOLS.  wItemList holds exactly the battle
--      inventory's tool-flagged ids, in bag order, $ff-terminated -- and the
--      three real ones are individually required (the Figaro buys are what
--      battle_vargas's proof 3 rides on; losing one here fails loudly).
--   2. NAMES RENDER.  "BioBlaster", "NoiseBlaster", "AutoCrossbow" are found
--      in VRAM (findName over the drawn window) -- with three entries the
--      grid uses BOTH columns (row-major: entries 0/2 left, 1 right).
--   3. COSTS RENDER, AND ARE RIGHT.  The two tiles just left of each name
--      decode to that tool's Ot6AbilityCostTbl price, read from the ROM.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TOOLS = 0x30
local EDGAR = 0x04
local ITEMLIST = 0x4005                 -- MakeToolsList's wItemList (3/entry)
local BATTINV  = 0x2686                 -- battle inventory, 5 bytes/entry

-- The three tools the chain really owns here -- Edgar's starter AutoCrossbow
-- plus gen_edgar's two Figaro purchases.  Required present; the full expected
-- list is still derived from the inventory so more tools would ADD rows.
local BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW = 0xA4, 0xA3, 0xAA

-- Ot6AbilityCostTbl: (key, cost) pairs, $ff-terminated (ot6_boost.asm), the
-- very table Ot6CostFor scans for the charge and the row stamp.
local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

-- FF6 battle-font glyphs: 'A'..'Z' = $80.., 'a'..'z' = $9a.. (the same mapping
-- battle_blitzlist pins down), digits '0'..'9' = $b4.., blank = $ff.
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- "Bio Blaster" carries a real SPACE (item_name_en.json:175), and in the
-- item-name records it is the NARROW-SPACE glyph $fe (item_name_en.dat
-- record $a4: e5 81 a2 a8 FE 81 a5 ...), the same tile "W Wind" uses in
-- magic_name records -- not the $ff blank.  Its expected run spells that
-- out; the other two names are contiguous.  (The pre-conversion file dodged
-- this by asserting only the spaceless synthetic tools it had installed.)
local function seqJoin(a, mid, b)
  local t = {}
  for _, v in ipairs(a) do t[#t + 1] = v end
  t[#t + 1] = mid
  for _, v in ipairs(b) do t[#t + 1] = v end
  return t
end
local NM = {
  [BIOBLASTER]   = { name = "Bio Blaster",
                     g = seqJoin(glyphs("Bio"), 0xfe, glyphs("Blaster")) },
  [NOISEBLASTER] = { name = "NoiseBlaster", g = glyphs("NoiseBlaster") },
  [AUTOCROSSBOW] = { name = "AutoCrossbow", g = glyphs("AutoCrossbow") },
}

-- word address of a rendered glyph run in VRAM, or nil (battle_blitzlist's
-- findName).
local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

-- decode one rendered cost: the row draws [tens][units][wrench][name...], so the
-- units digit sits two tiles left of the name's first letter and the tens digit
-- three left.  digits are $b4+d; a blank ($ff) tens place means a single digit.
local function readCost(nameSeq)
  local w = findName(nameSeq)
  if not w then return nil end
  local vr = emu.memType.snesVideoRam
  local units = emu.readWord((w - 2) * 2, vr) & 0xFF
  local tens  = emu.readWord((w - 3) * 2, vr) & 0xFF
  if units < 0xb4 or units > 0xbd then return nil end   -- not a digit: unexpected
  local n = units - 0xb4
  if tens >= 0xb4 and tens <= 0xbd then n = n + (tens - 0xb4) * 10 end
  return n
end

-- wait for EDGAR's own menu, consuming other characters' turns with a real
-- Defend (right swaps Fight->Def, then A) -- battle_naturalmp's pattern on
-- this same fixture.  The monsters take their own turns in here; their
-- damage lands on party HP, which nothing in this test asserts on.
local slotOf = {}
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) == 0 then
        -- no menu up: page any battle dialog with A (the battle_vargas
        -- hazard -- a monster dialog blocks the queue until dismissed)
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires
  -- (battle_naturalmp's drive: the danger counter accrues per step and rolls
  -- the encounter itself)
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),

  -- the REAL party: find Edgar's slot and derive the expected tool rows from
  -- the battle inventory's own $40-flagged records (bag order).
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[EDGAR], "EDGAR present (kolts party)")
    local want, seen = {}, {}
    for i = 0, 255 do
      local id = H.readByte(BATTINV + i * 5)
      local fl = H.readByte(BATTINV + i * 5 + 1)
      local qty = H.readByte(BATTINV + i * 5 + 3)
      if id ~= 0xFF and (fl & 0x40) == 0x40 and qty > 0 then
        want[#want + 1] = id
        seen[id] = true
      end
      if id == 0xFF and i > 0 then break end
    end
    local names = {}
    for _, id in ipairs(want) do
      names[#names + 1] = string.format("$%02x(%s, %d MP)", id,
        NM[id] and NM[id].name or "?", costOf(id))
    end
    H.log("bag tools (battle inventory, $40-flagged): " .. table.concat(names, ", "))
    H.assertEq(seen[BIOBLASTER] == true, true,
      "the BioBlaster is really in the bag (gen_edgar's Figaro buy)")
    H.assertEq(seen[NOISEBLASTER] == true, true,
      "the NoiseBlaster is really in the bag (gen_edgar's Figaro buy)")
    H.assertEq(seen[AUTOCROSSBOW] == true, true,
      "the AutoCrossbow is really in the bag (Edgar's starter tool)")
    H.assertEq(#want >= 3, true, "at least the three real tools")
    H.vars.wantTools = want
  end),

  -- open the tools window: wait for EDGAR's menu, walk Fight -> Tools (his
  -- real row 1, cmd $09), A -> the real tools list (state $30).
  menuFor(EDGAR, "edgar's command window"),
  H.waitFrames(30),
  H.pressButtons({ "down" }, 4), H.waitFrames(20),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 300,
    "the tools list opens (state $30)", 5),
  H.waitFrames(20),                    -- let every row finish drawing
  H.call(function() H.screenshot("tools_cost_display") end),

  -- 1. THE LIST PACKS THE OWNED TOOLS ----------------------------------------
  H.call(function()
    local want = H.vars.wantTools
    local ids = {}
    for i = 0, 7 do ids[i] = H.readByte(ITEMLIST + i * 3) end
    H.log(string.format("wItemList ids: %02x %02x %02x %02x %02x %02x %02x %02x",
      ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7]))
    for i, id in ipairs(want) do
      H.assertEq(ids[i - 1], id,
        string.format("row %d is the bag's tool $%02x", i - 1, id))
    end
    if #want < 8 then
      H.assertEq(ids[#want], 0xFF,
        "the list terminates after the owned tools -- no phantom rows")
    end
  end),

  -- 2. NAMES RENDER ----------------------------------------------------------
  H.call(function()
    for _, id in ipairs({ BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW }) do
      H.assertEq(findName(NM[id].g) ~= nil, true,
        "\"" .. NM[id].name .. "\" is drawn in the menu")
    end
  end),

  -- 3. COSTS RENDER, AND ARE RIGHT -------------------------------------------
  -- read the two tiles left of each name and decode the stamped MP cost
  -- against the charge table in the ROM.  With three entries the grid is
  -- row-major over two columns, so this covers column 1 (entries 0, 2) and
  -- column 2 (entry 1) in one render.
  H.call(function()
    for _, id in ipairs({ BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW }) do
      local want = costOf(id)
      H.assertEq(want > 0, true, NM[id].name .. " is priced in Ot6AbilityCostTbl")
      local got = readCost(NM[id].g)
      H.log(string.format("  %-12s stamped cost = %s (table %d)",
        NM[id].name, tostring(got), want))
      H.assertEq(got, want,
        string.format("%s's MP cost renders as %d", NM[id].name, want))
    end
    H.log("PASSED: the real tools window lists exactly the bag's tools and "
      .. "prices each one from the charge authority")
  end),
})
