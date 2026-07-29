-- probe_blitzpage.lua -- what the field Skills->Blitz page draws TODAY (#46).
-- Not a suite test: a measurement.  Dumps the BG1A tilemap shadow row by row
-- so the pre-change page can be compared against the post-change one.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local BLITZ_ROW_COLOR = 0x7c            -- zSkillsTextColor::Blitz
local CMD3 = 0x1618
local BATTLE_CMD_BLITZ = 0x0a
local BLITZES = 0x1D28                  -- known-blitz bitmask
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_BLITZ = 0x05, 0x06, 0x0a, 0x33
local SKILLS_ROW_BLITZ = 3

local function st() return H.readByte(ZMENUSTATE) end
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

local function dump(tag)
  H.log("---- BG1A " .. tag .. " ----")
  for y = 0, 27 do
    local s, any = "", false
    for x = 0, 31 do
      local b = cell(x, y)
      if b ~= 0 then any = true end
      if b == 0 then s = s .. "."
      elseif b == 0xff then s = s .. " "
      elseif b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
      elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
      elseif b >= 0xb4 and b <= 0xbd then s = s .. string.char(48 + b - 0xb4)
      else s = s .. "?" end
    end
    if any then H.log(string.format("row %2d |%s|", y, s)) end
  end
  H.log("---- raw nonzero cells ----")
  for y = 0, 27 do
    local r = {}
    for x = 0, 31 do
      local b = cell(x, y)
      if b ~= 0 then r[#r + 1] = string.format("%d:%02x", x, b) end
    end
    if #r > 0 then H.log(string.format("row %2d %s", y, table.concat(r, " "))) end
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BLITZ)
    H.writeByte(BLITZES, 0x07)          -- Pummel / AuraBolt / Suplex
    H.log("installed: Blitz on the lead, 3 blitzes known")
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
  H.call(function()
    H.log("blitz row color = " .. string.format("%02x", H.readByte(BLITZ_ROW_COLOR)))
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_BLITZ
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Blitz"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300, "blitz page open", 5),
  H.waitFrames(90),
  H.call(function()
    dump("3 known")
    H.screenshot("probe_blitz_3known")
  end),
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "back out", 5),
  H.call(function() H.writeByte(BLITZES, 0xff) end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300, "blitz page reopen", 5),
  H.waitFrames(90),
  H.call(function()
    dump("8 known")
    H.screenshot("probe_blitz_8known")
  end),
})
