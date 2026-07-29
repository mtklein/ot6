-- probe_wallet.lua -- issue #35 MEASUREMENT ONLY: where does vanilla's
-- battle Magic window show the caster's current MP (the pane _c1050c
-- composes into w7e5d15), and what does the Blitz (tools-shell) window
-- show in the same region?  Dumps the menu (BG2) tilemap rows around the
-- open list windows plus screenshots, so the wallet display (#35) can be
-- placed with measured coordinates instead of guesses.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2

local msPresent = {}
local sabin = false

local function pinField()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local st1 = 0x3EE4 + s * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
      if sabin then
        H.writeByte(0x3ED8 + s * 2, 0x05)               -- CHAR::SABIN
        for i = 0, 3 do H.writeByte(0x202E + s * 12 + i * 3, 0x0A) end
      else
        H.writeByte(0x3ED8 + s * 2, 0x00)               -- CHAR::TERRA
        H.writeByte(0x202E + s * 12 + 0 * 3, 0x02)      -- Magic
        H.writeByte(0x202E + s * 12 + 1 * 3, 0x00)      -- Fight
        H.writeByte(0x202E + s * 12 + 2 * 3, 0xFF)
        H.writeByte(0x202E + s * 12 + 3 * 3, 0xFF)
      end
      H.writeWord(0x3BF4 + s * 2, 999)
      H.writeWord(0x3C30 + s * 2, 99)                   -- max MP
      H.writeWord(0x3C08 + s * 2, 47)                   -- current MP 47
    end
  end
  H.writeByte(0x1D28, 0xE5)                             -- known blitzes
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)
    if H.readWord(0x3BFC + m * 2) < 0x6000 then H.writeWord(0x3BFC + m * 2, 0xF000) end
  end
end

-- FF6 battle-font glyphs (battle_blitzgrey's mapping)
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x0000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

-- locate a glyph run and dump the surrounding rows at its own map base
local function locate(tag, seq)
  local w = findName(seq)
  if not w then H.log("locate " .. tag .. ": NOT FOUND") return end
  H.log(string.format("locate %s: vram word %04x (row %d col %d of a $%04x-based 32-wide map)",
    tag, w, (w % 0x400) >> 5, w & 0x1F, w - (w % 0x400)))
  local base = (w - (w % 0x400))
  local row = (w % 0x400) >> 5
  for r = math.max(0, row - 2), math.min(31, row + 3) do
    local cells = {}
    for col = 0, 31 do
      cells[#cells + 1] = string.format("%04x",
        emu.readWord((base + r * 32 + col) * 2, emu.memType.snesVideoRam))
    end
    H.log(string.format("R%02d %s", r, table.concat(cells, " ")))
  end
end

-- dump nonblank rows of the menu (bg2) map, both bands
local function dumpMenuMap(tag)
  local reg = H.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  H.log("== menu map dump: " .. tag .. string.format(" (base vram byte %06x)", base))
  for row = 0, 27 do
    local cells, nonblank = {}, false
    for col = 0, 31 do
      local w = emu.readWord(base + row * 0x40 + col * 2, emu.memType.snesVideoRam)
      cells[#cells + 1] = string.format("%04x", w)
      local g = w & 0xFF
      if g ~= 0xFF and g ~= 0x00 and w ~= 0x21FF and w ~= 0x01EE then nonblank = true end
    end
    if nonblank then
      H.log(string.format("r%02d %s", row, table.concat(cells, " ")))
    end
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    pinField()
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinField), H.waitFrames(1),
  }, "a battle menu opens"),

  -- ---- phase A: the vanilla Magic window and its MP pane ----
  H.driveUntil(function() return H.readByte(MSTATE) == 0x0e end, 1500, {
    H.call(function() pinField(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "magic list opens (browse state $0e)"),
  H.waitFrames(30),
  H.call(function()
    H.screenshot("wallet_magic_window")
    locate("magic 'Needed' pane", glyphs("Needed"))
    local regs = {}
    for i = 0, 0x13 do regs[#regs+1] = string.format("%02x", H.readByte(0x896F + i)) end
    H.log("896f..8982 shadows: " .. table.concat(regs, " "))
    dumpMenuMap("magic window open (caster MP pinned 47/99)")
    -- what vanilla composed in the w7e5d15 pane buffer
    local b = {}
    for i = 0, 0x1f do b[#b + 1] = string.format("%02x", H.readByte(0x5D15 + i)) end
    H.log("w7e5d15 pane buffer: " .. table.concat(b, " "))
    local c = {}
    for i = 0, 0x1b do c[#c + 1] = string.format("%02x", H.readByte(0x5CA5 + i)) end
    H.log("w7e5ca5 mp text buffer: " .. table.concat(c, " "))
  end),
  H.call(function() H.setPad({ "b" }) end), H.waitFrames(4),
  H.call(function() H.setPad({}) end), H.waitFrames(20),
  H.call(function() H.setPad({ "b" }) end), H.waitFrames(4),
  H.call(function() H.setPad({}) end), H.waitFrames(20),

  -- ---- phase B: the Blitz (tools shell) window, same dump ----
  H.call(function() sabin = true; pinField() end),
  H.waitFrames(30),
  H.driveUntil(function() return H.readByte(MSTATE) == 0x30 end, 3000, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "blitz list opens (tools shell $30)"),
  H.waitFrames(30),
  H.call(function()
    H.screenshot("wallet_blitz_window")
    locate("blitz 'Pummel' row", glyphs("Pummel"))
    locate("blitz 'Suplex' row", glyphs("Suplex"))
    dumpMenuMap("blitz window open (actor MP pinned 47/99)")
  end),
  -- ---- phase C: poke marker glyphs into the $7c00 list map to learn which
  -- cells are visible inside the open blitz window (candidate wallet homes)
  H.call(function()
    local vr = emu.memType.snesVideoRam
    local function put(row, col, glyph)
      emu.writeWord((0x7C00 + row * 32 + col) * 2, 0x2100 | glyph, vr)
    end
    -- 'A' on row 0 (above Pummel), cols 2 and 26
    put(0, 2, 0x80); put(0, 26, 0x80)
    -- 'B' on row 2 (between list rows), col 2 and 26
    put(2, 2, 0x81); put(2, 26, 0x81)
    -- 'C' on row 7 (fourth list row), cols 2 and 26
    put(7, 2, 0x82); put(7, 26, 0x82)
    -- 'D' on row 1 cols 27..30 (right of Suplex's cost, outside 0..26)
    put(1, 27, 0x83); put(1, 28, 0x83); put(1, 30, 0x83)
    -- 'E' on rows 8/9 (below the fourth row)
    put(8, 2, 0x84); put(9, 2, 0x84)
  end),
  H.waitFrames(4),
  H.call(function() H.screenshot("wallet_blitz_markers") end),
  H.logStep(function() return "probe_wallet complete" end),
})
