-- probe_esperdetail_statblock.lua -- issue #62's LAYOUT instrument.
--
-- #62 turned the esper detail page's single "While worn...<Stat> + N" line into a
-- multi-stat block, because Ot6EsperStatTbl now carries up to four SIGNED deltas
-- in vanilla's own equipment layout.  This probe exists to SEE that block: it
-- dumps every cell of BG1 screen B rows 15-29 as a decoded text row and takes a
-- screenshot, for four stones chosen to cover every shape the layout can take:
--
--   IFRIT   (1)  three terms, the first with a NEGATIVE one (+6 vig/+4 stm/-3 mag)
--   SHIVA   (2)  three terms whose FIRST is negative (-3 vig/+4 spd/+6 mag)
--   MADUIN  (6)  the crown, and the encoding's ceiling (+7 mag)
--   TERRATO (4)  the no-mod control: caption and all four term rows blank
--
-- Booted from a COLD Continue off the tracked post-Opera battery anchor, which
-- survives ROM changes (issue #9) where savestate fixtures do not -- the same
-- boot probe_esperdetail_anchor.lua uses, and the reason this can be run against
-- a fresh menu-bank build with no re-mint:
--
--   OT6_SRAM_ANCHOR=tools/tests/anchors/post-opera-v1 \
--     tools/tests/run.sh tools/tests/probe_esperdetail_statblock.lua
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99
local SKILLCOLOR = 0x79
local ESPERS     = 0x1a69
local GENJULIST  = 0x9d89
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local IFRIT, SHIVA, TERRATO, MADUIN = 1, 2, 4, 6

local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

local function st() return H.readByte(ZMENUSTATE) end

-- Minimal reverse of ff6/tools/char_table/text_en.json for the glyphs this page
-- can draw, so the dump is readable without leaving the log.
local function glyph(b)
  if b == 0xff then return "." end
  if b >= 0x80 and b <= 0x99 then return string.char(string.byte("A") + b - 0x80) end
  if b >= 0x9a and b <= 0xb3 then return string.char(string.byte("a") + b - 0x9a) end
  if b >= 0xb4 and b <= 0xbd then return string.char(string.byte("0") + b - 0xb4) end
  if b == 0xc4 then return "-" end
  if b == 0xca then return "+" end
  if b == 0xc5 then return "." end
  if b == 0xc1 then return ":" end
  if b == 0xcd then return "%" end
  return "?"
end

local function dumpPage(tag)
  H.log(("---- %s: BG1B rows 15-29, cols 0-31 ----"):format(tag))
  H.log("        0123456789012345678901234567890123456789012345678901234567890123"
    :sub(1, 8 + 32))
  for y = 15, 29 do
    local row = {}
    for x = 0, 31 do row[#row + 1] = glyph(cell(x, y)) end
    H.log(("  r%2d  |%s|"):format(y, table.concat(row)))
  end
end

local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return st() == ST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if ph >= 4 then H.setPad({}); return end
      local target
      for r = 0, 26 do
        if H.readByte(GENJULIST + r) == idx then target = r; break end
      end
      if not target then H.setPad({}); return end
      local row = H.readByte(ZCURSOR)
      local d = target - row
      if d % 2 ~= 0 then
        if row % 2 == 0 then
          H.setPad(row >= 26 and { up = true } or { right = true })
        else
          H.setPad({ left = true })
        end
      else
        H.setPad(d > 0 and { down = true } or { up = true })
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- gen_vector_doorstep.lua's cold Continue off the battery anchor, verbatim from
-- probe_esperdetail_anchor.lua:82-96.
local all = {
  H.waitFrames(350),
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
    H.log(("[pin] $1a69 was %02x; pinning IFRIT+SHIVA+TERRATO+MADUIN")
      :format(H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x56)       -- bits 1,2,4,6
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x00)
    H.writeByte(ESPERS + 3, 0x00)
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
    H.assertEq(H.readByte(SKILLCOLOR), 0x20, "Espers row enabled (color $20)")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0
  end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
    "skills submenu cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "esper list", 5),
  H.call(function()
    H.assertEq(H.readByte(ZLISTTYPE), 4, "list type GENJU (menu_ram.inc)")
  end),
}

local function visit(idx, tag)
  all[#all + 1] = listSeek(idx, "cursor to " .. tag)
  all[#all + 1] = H.waitFrames(20)
  all[#all + 1] = H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, tag .. " detail")
  all[#all + 1] = H.waitFrames(30)
  all[#all + 1] = H.call(function()
    H.assertEq(H.readByte(Z99), idx, "detail page is " .. tag .. "'s")
    dumpPage(tag)
    H.screenshot("esper_statblock_" .. tag:lower())
  end)
  all[#all + 1] = H.pressButtons({ "b" }, 2)
  all[#all + 1] = H.waitUntil(function() return st() == ST_LIST end, 300,
    "back to list from " .. tag, 5)
  all[#all + 1] = H.waitFrames(10)
end

visit(IFRIT, "IFRIT")
visit(SHIVA, "SHIVA")
visit(MADUIN, "MADUIN")
visit(TERRATO, "TERRATO")

all[#all + 1] = H.call(function()
  H.log("[statblock] four pages dumped; read the rows above against the layout")
end)

H.run({ maxFrames = 90000 }, all)
