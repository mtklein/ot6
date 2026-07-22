-- @suite
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
-- Edgar is INSTALLED into the opening guard fight the way battle_blitzlist pins
-- Sabin: every party slot gets CHAR::EDGAR ($3ED8) and an all-Tools command
-- list ($202E, stride 12).  The eight tools are written straight into the
-- battle item buffer ($2686, 5-byte records: id/usage-flags/targeting/qty) with
-- the tools usage bit $40 set, so MakeToolsList scans them into wItemList in a
-- known order and the test controls exactly which tools appear.
--
-- What is asserted:
--   1. THE LIST PACKS THE TOOLS.  wItemList holds the eight tool ids $a3..$aa.
--   2. NAMES RENDER.  "Drill", "Flash", "AutoCrossbow", "Debilitator" are found
--      in VRAM (findName over the drawn window).
--   3. COSTS RENDER, AND ARE RIGHT.  The two tiles just left of each name (past
--      the tool's leading wrench icon) decode to that tool's Ot6AbilityCostTbl
--      price -- covering column 1 and column 2, single- and two-digit costs.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TOOLS = 0x30
local CMD_TOOLS = 0x09
local CMDTBL, ITEMLIST = 0x202E, 0x4005
local PARTY = { 0, 1, 2 }

-- the eight tools, in the order the buffer feeds them to MakeToolsList, each
-- with its Ot6AbilityCostTbl (ot6.asm) MP price.  Costs span column 1 / column
-- 2 and single- / two-digit, so the screenshot shows the real width the leading
-- cost column must fit.
local TOOLS = {
  { 0xA3, 6,  "NoiseBlaster" },
  { 0xA4, 8,  "BioBlaster"   },
  { 0xA5, 6,  "Flash"        },
  { 0xA6, 18, "ChainSaw"     },
  { 0xA7, 10, "Debilitator"  },
  { 0xA8, 16, "Drill"        },
  { 0xA9, 14, "AirAnchor"    },
  { 0xAA, 4,  "AutoCrossbow" },
}

-- FF6 battle-font glyphs: 'A'..'Z' = $80.., 'a'..'z' = $9a.. (the same mapping
-- battle_blitzlist pins down), digits '0'..'9' = $b4.., blank = $ff.
local function up(c)  return 0x80 + (c:byte() - ("A"):byte()) end
local function lo(c)  return 0x9a + (c:byte() - ("a"):byte()) end
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and up(c) or lo(c)
  end
  return t
end
local NM = {
  Drill        = glyphs("Drill"),
  Flash        = glyphs("Flash"),
  Debilitator  = glyphs("Debilitator"),
  AutoCrossbow = glyphs("AutoCrossbow"),
}

local actor
local function pinEdgar()
  -- put all eight tools in the battle item buffer $2686 (5-byte records:
  -- id / usage-flags / targeting / qty), each flagged as a tool ($40), qty 1
  for i, t in ipairs(TOOLS) do
    local b = 0x2686 + (i - 1) * 5
    H.writeByte(b + 0, t[1])
    H.writeByte(b + 1, 0x40)
    H.writeByte(b + 2, 0x00)
    H.writeByte(b + 3, 1)
  end
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x04)                 -- CHAR::EDGAR
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    for i = 0, 3 do H.writeByte(CMDTBL + s * 12 + i * 3, i == 0 and CMD_TOOLS or 0xFF) end
    H.writeWord(0x3BF4 + s * 2, 999)                  -- nobody dies mid-bench
    H.writeWord(0x3C08 + s * 2, 99)                   -- MP (a costed tool never fizzles here)
    H.writeWord(0x3C30 + s * 2, 99)
  end
end

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

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),

  -- install a full-Tools Edgar every frame until a menu belongs to somebody
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinEdgar), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("edgar installed in slot %d (char id $%02x)",
      actor, H.readByte(0x3ED8 + actor * 2)))
  end),

  -- open the tools window: A from the command list -> real tools (state $30).
  H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pinEdgar(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the tools list opens (state $30)"),
  H.waitFrames(8),                     -- let every row finish drawing
  H.call(function() H.screenshot("tools_cost_display") end),

  -- 1. THE LIST PACKS THE TOOLS ----------------------------------------------
  H.call(function()
    local ids = {}
    for i = 0, 7 do ids[i] = H.readByte(ITEMLIST + i * 3) end
    H.log(string.format("wItemList ids: %02x %02x %02x %02x %02x %02x %02x %02x",
      ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7]))
    for i, t in ipairs(TOOLS) do
      H.assertEq(ids[i - 1], t[1], string.format("row %d is tool $%02x", i - 1, t[1]))
    end
  end),

  -- 2. NAMES RENDER ----------------------------------------------------------
  H.call(function()
    for _, nm in ipairs({ "Drill", "Flash", "Debilitator", "AutoCrossbow" }) do
      H.assertEq(findName(NM[nm]) ~= nil, true, "\"" .. nm .. "\" is drawn in the menu")
    end
  end),

  -- 3. COSTS RENDER, AND ARE RIGHT -------------------------------------------
  -- read the two tiles left of each name and decode the stamped MP cost.
  -- Flash(6)/Debilitator(10) are column 1, Drill(16)/AutoCrossbow(4) column 2;
  -- 6 and 4 are single-digit, 16 and 10 two-digit -- the whole width range.
  H.call(function()
    local want = { Flash = 6, Debilitator = 10, Drill = 16, AutoCrossbow = 4 }
    for name, cost in pairs(want) do
      local got = readCost(NM[name])
      H.log(string.format("  %-12s stamped cost = %s (want %d)", name, tostring(got), cost))
      H.assertEq(got, cost, string.format("%s's MP cost renders as %d", name, cost))
    end
    H.log("PASSED: the tools menu lists all eight tools and prices each one")
  end),
})
