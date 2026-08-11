-- probe_menucols.lua -- reference probe, not a suite test (no @suite marker).
--
-- Establishes vanilla's own cursor/text relationship for the EN field-menu
-- window, measured on the shipped OT6 ROM (the Magic and Espers lists are
-- untouched by OT6, so they show vanilla's geometry in the frame buffer
-- the owner sees).  Dumps, per list: the first non-zero BG1A column of each
-- drawn row, plus a screenshot for pixel measurement of the cursor sprite.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local CMD3 = 0x1618
local ST_MAIN, ST_CHAR, ST_SKILLS = 0x05, 0x06, 0x0a
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end
local function st() return H.readByte(ZMENUSTATE) end

local function dumpCols(tag)
  for y = 0, 27 do
    local first, last = nil, nil
    for x = 0, 31 do
      local c = cell(x, y)
      if c ~= 0 then
        if not first then first = x end
        last = x
      end
    end
    if first then
      H.log(string.format("%s: row %2d  first-col=%2d  last-col=%2d", tag, y, first, last))
    end
  end
  -- $4f/$50 are the cursor's column and row indices within the list (the
  -- pair skills.asm:100-105 saves into $023e,x), not pixels.  The sprite's
  -- pixel position is not in WRAM at a fixed address; it is measured off the
  -- screenshots instead, by diffing two frames whose cursor index differs.
  H.log(string.format("%s: cursor index col=%d row=%d  menu state=$%02x",
    tag, H.readByte(0x4f), H.readByte(0x50), st()))
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  H.call(function()
    H.writeByte(CMD3, 0x02)               -- BATTLE_CMD::MAGIC on the lead
    for i = 0, 53 do H.writeByte(0x1a6e + i, 0xff) end  -- every spell learned
    for i = 0, 1 do H.writeByte(0x1a69 + i, 0xff) end   -- espers 0..15 owned
  end),

  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(20),

  -- Magic is row 1 of the skills submenu (Espers, Magic, SwdTech, ...), and it
  -- is where the submenu's cursor already sits on entry here.  Espers (row 0)
  -- is not dumped: the observed submenu cursor is 1, and driving it to 0 needs
  -- an owned-esper state this fixture does not have.  The esper columns in the
  -- report come from the source (skills.asm:1733, :1737), not from this probe.
  H.call(function()
    H.log("skills cursor on entry = " .. H.readByte(ZCURSOR) .. " (expect 1, Magic)")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 1
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "skills cursor to Magic"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(90),
  H.call(function()
    dumpCols("MAGIC")
    H.screenshot("vanilla_magic_list")
  end),
  -- move the cursor one row down and one column right, so the screenshot pair
  -- pins both cursor columns against both text columns.
  H.pressButtons({ "down" }, 2),
  H.waitFrames(20),
  H.pressButtons({ "right" }, 2),
  H.waitFrames(40),
  H.call(function()
    dumpCols("MAGIC-R")
    H.screenshot("vanilla_magic_list_right")
    H.log("PASSED: reference dump complete")
  end),
})
