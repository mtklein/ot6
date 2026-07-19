-- probe_pipcell.lua -- what ELSE writes the party-window bp pip cell?
--
-- Playtest report (v0.2 RC): "the boost chevrons sometimes turn into
-- numbers", at no pattern the player could name.  The leading hypothesis
-- was font-cell eviction (our glyph tiles overwritten, so our tile
-- indices render as whatever vanilla loaded there).  That is already
-- falsified statically: vanilla's small font is BLANK at every cell OT6
-- claims -- small_font_en.2bpp non-blank runs are $80-$CF, $D2-$EA,
-- $F0-$FA, and Ot6BgGlyphCellTbl (ot6.asm:3178) claims $65-$79 only.  An
-- evicted glyph would render EMPTY, not as a digit.  Digits are cells
-- $B4-$BD ('0'-'9'), which nothing in OT6 ever writes.
--
-- So the substitution most likely arrives as a TILEMAP write, not a font
-- write.  This probe samples, every frame, the map word at the pip cell
-- for all four party rows in BOTH window bands (rows 1+2r and 9+2r --
-- the party window is double-buffered and the scroll picks a band), logs
-- every transition, and records the context of the frame it changed on:
--   menu open ($7bca), menu state ($7bc2), active slot ($62ca),
--   pending boost + bp, OT6_PIPCUR/PIPCELL, OT6_FONTDIRTY, OT6_HUDVEIL.
-- It also runs the glyph canary at the end, so a font-eviction cause
-- would still be caught rather than assumed away.
--
-- Quiet-test guard: the probe asserts it actually saw the pip glyph at
-- least once (otherwise "no digits seen" would be vacuously true because
-- the cell was never ours to begin with).
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local PIP  = { [0x72]=1, [0x73]=1, [0x75]=1, [0x76]=1, [0x77]=1, [0x79]=1 }
local ARROW= { [0x68]=1, [0x6c]=1, [0x6d]=1 }
local function isDigit(c) return c >= 0xb4 and c <= 0xbd end

local prev, events, sawPip, sawDigit, frames = {}, {}, false, false, 0
local seen = {}

local function mapBase()
  local reg = H.readByte(0x897f)
  return ((reg - (reg % 4)) * 256) * 2
end

local function ctx()
  local a = H.readByte(0x62ca) & 3
  return string.format(
    "menu=%d st=%02x act=%d pend=%d bp=%d pipcur=%04x pipcell=%04x fd=%d veil=%d",
    H.readByte(0x7bca), H.readByte(0x7bc2), H.readByte(0x62ca),
    H.readByte(0x3e9d + a*2), H.readByte(0x3e9c + a*2),
    H.readWord(0x57cc), H.readWord(0x57d0),
    H.readByte(0x57b9), H.readByte(0x57be))
end

local function sample()
  local base = mapBase()
  frames = frames + 1
  for row = 0, 3 do
    for _, band in ipairs({ 1 + row*2, 9 + row*2 }) do
      local key = row .. "/" .. band
      local w = emu.readWord(base + band*0x40 + 40, emu.memType.snesVideoRam)
      local cell = w & 0xff
      seen[cell] = (seen[cell] or 0) + 1
      if PIP[cell] or ARROW[cell] then sawPip = true end
      if isDigit(cell) then sawDigit = true end
      if prev[key] ~= nil and prev[key] ~= w then
        local tag = PIP[cell] and "pip" or ARROW[cell] and "arrow"
                 or isDigit(cell) and "DIGIT" or (cell == 0xff and "blank")
                 or string.format("other(%02x)", cell)
        if #events < 200 then
          events[#events+1] = string.format("f%05d r%d b%02d %04x->%04x %-10s %s",
            frames, row, band, prev[key], w, tag, ctx())
        end
      end
      prev[key] = w
    end
  end
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(180),
  H.call(function()
    -- survive a long fight so many events get a chance to fire
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    for s = 0, 3 do
      if H.readWord(0x3bf4 + s*2) > 0 then H.writeWord(0x3bf4 + s*2, 900) end
      H.writeByte(0x3e9c + s*2, 3)          -- bp to spend
    end
    H.log("sampling begins: " .. ctx())
  end),
  -- long, self-driving battle: press A whenever a menu is up, tapping R
  -- on some turns so the pip cell holds arrows too.
  H.driveUntil(function()
    sample()
    return frames >= 6000
  end, 40000, {
    H.call(function()
      sample()
      if H.readByte(0x7bca) ~= 0 then
        if (frames // 97) % 2 == 0 then H.setPad({ "r" }) else H.setPad({ "a" }) end
      else
        H.setPad({})
      end
    end),
    H.waitFrames(3),
    H.call(function() sample(); H.setPad({}) end),
    H.waitFrames(14),
  }, "long battle sampled"),
  H.call(function()
    H.log(string.format("frames sampled: %d, transitions logged: %d",
      frames, #events))
    for _, e in ipairs(events) do H.log(e) end
    local hist = {}
    for c, n in pairs(seen) do hist[#hist+1] = string.format("%02x x%d", c, n) end
    table.sort(hist)
    H.log("cell histogram: " .. table.concat(hist, ", "))
    H.log("saw a pip/arrow glyph in the cell at all: " .. tostring(sawPip))
    H.log("saw a DIGIT in the cell: " .. tostring(sawDigit))
    H.assertEq(sawPip, true, "positive control: the pip cell was ours sometimes")
    H.glyphCanary()
    H.log("glyph canary clean (font cells still hold OT6 art)")
  end),
})
