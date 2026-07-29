-- probe_swdtechcost.lua -- issue #56: what the SwdTech loadout page's cost
-- field actually renders, cell by cell, under the #45 cost column.
--
-- Not a suite test (no `-- @suite` marker): it asserts nothing and exists to
-- MEASURE.  It opens the page twice -- once with the scenario-band learned set
-- (Dispatch/Retort/Slash: costs 4/10/13, so a one-digit rung and two two-digit
-- ones) and once with all eight learned (Stunner/Quadra Slice/Cleave: 22/30/46,
-- and "Quadra Slice" is the ONLY twelve-cell BushidoName, i.e. the widest name
-- next to a two-digit price) -- and dumps rows 1..15 of the BG1A shadow as
-- text plus a screenshot of each.
--
-- The dump is the point: `menu_swdtechpage.lua` says WHICH cell is wrong, this
-- says what the whole row looks like, which is what a column-budget decision
-- needs.  Path and install-state are lifted verbatim from that test.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local CMD3 = 0x1618
local LEARNED, LOADOUT = 0x1cf7, 0x1e1d
local BATTLE_CMD_BUSHIDO = 0x07
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LOADOUT = 0x05, 0x06, 0x0a, 0x7b
local BG1A = 0x3849

local function st() return H.readByte(ZMENUSTATE) end
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- text_en.json: 'A'=$80..'Z'=$99, 'a'=$9a..'z'=$b3, '0'=$b4..'9'=$bd,
-- ' '/{pad}=$ff, $00 = never drawn.  Anything else prints as its hex byte so a
-- garbage glyph (the bug: 10 + ZERO_CHAR = $be, one past '9') is visible.
local function glyph(b)
  if b == 0 then return "." end
  if b == 0xff then return "_" end
  if b >= 0x80 and b <= 0x99 then return string.char(65 + b - 0x80) end
  if b >= 0x9a and b <= 0xb3 then return string.char(97 + b - 0x9a) end
  if b >= 0xb4 and b <= 0xbd then return string.char(48 + b - 0xb4) end
  if b == 0xc0 then return "/" end
  if b == 0xd2 then return "=" end
  return "?"
end

local function dump(what)
  H.log("---- " .. what .. " ----")
  H.log("       01234567890123456789012345678901")
  H.log("       0         1         2         3")
  for y = 0, 15 do
    local s = ""
    for x = 0, 31 do s = s .. glyph(cell(x, y)) end
    H.log(string.format("row %2d [%s]", y, s))
  end
  -- and the raw bytes of the price field's neighbourhood on the three slot rows
  for _, y in ipairs({ 3, 5, 7 }) do
    local s = ""
    for x = 16, 29 do s = s .. string.format("%02x ", cell(x, y)) end
    H.log(string.format("row %d cols 16..29 raw: %s", y, s))
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BUSHIDO)
    H.writeByte(LEARNED, 0x07)
    H.writeByte(LOADOUT, 0)
    H.writeByte(LOADOUT + 1, 0)
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
  H.waitFrames(10),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 2
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to SwdTech"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300, "configurator", 5),
  H.waitFrames(90),
  H.call(function()
    dump("3 learned: Dispatch 4 / Retort 10 / Slash 13")
    H.screenshot("probe_swdtech_cost_3learned")
  end),

  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "back out", 5),
  H.call(function()
    H.writeByte(LEARNED, 0xff)
    H.writeByte(LOADOUT, 0)
    H.writeByte(LOADOUT + 1, 0)
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300, "reopened", 5),
  H.waitFrames(90),
  H.call(function()
    dump("8 learned: Stunner 22 / Quadra Slice 30 / Cleave 46")
    H.screenshot("probe_swdtech_cost_8learned")
    H.log("PROBE DONE")
  end),
})
