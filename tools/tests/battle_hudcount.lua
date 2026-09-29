-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_hudcount.lua -- the shield icon under a monster draws its true
-- count, above 6 too  (#292)
--
-- Boots n024-entry-save-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/n024-entry-save-v1 \
--     tools/tests/run.sh tools/tests/battle_hudcount.lua <log>
--
-- Before #292 the HUD builder clamped the count to 6 (`cmp #$07 / lda #$06`
-- in Ot6BgHudLine), so NUMBER 024's 7 read 6 and AtmaWeapon's 11 read 6.
-- Now each monster slot owns one font cell, and the HUD uploads the tile for
-- that slot's live count (Ot6ShieldGlyphs, 1..99) into it.
--
-- The run: Continue at the 273 save point, walk the two steps to the
-- NUMBER 024 entry point, face it and press A (battle 72).  The monster with
-- the most shields must have more than 6 (the precondition this test
-- exists for; derived from the battle, not assumed).  Once its HUD line is
-- drawn on the field map, the word there must name that slot's cell and
-- the cell's VRAM tile must be the ROM's tile for the true count, which is
-- not the tile for 6.  Screenshot hudcount_<n>.
--
-- Then a SYNTHETIC step (declared in state_write_waivers.txt): the count is
-- written to 11, AtmaWeapon's authored count, which no fixture reaches
-- before the Floating Continent.  It shows the two-numeral tile drawn and
-- exercises the change path (a new count uploads a new tile).  It is a
-- mechanism check of the drawing, not play.  Screenshot hudcount_11_synthetic.

local H = dofile("tools/tests/lib/ot6.lua")

local SHADOW = 0xECF1                 -- OT6_SHADOW: 6 lines x 14 bytes
local SHIELD_CUR, SHIELD_MAX = 0x3E40, 0x3E41   -- monster slot s at +s*2
local BROKEN = 0x3E90

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local vr, rom = emu.memType.snesVideoRam, emu.memType.snesPrgRom

local function tileBytes(cell)
  local t = {}
  for i = 0, 15 do t[#t + 1] = emu.read(0xB000 + cell * 16 + i, vr) end
  return t
end
local function romTile(n)
  local base = (H.sym("Ot6ShieldGlyphs") & 0x3FFFFF) + (n - 1) * 16
  local t = {}
  for i = 0, 15 do t[#t + 1] = emu.read(base + i, rom) end
  return t
end
local function hex(t)
  local s = {}
  for _, b in ipairs(t) do s[#s + 1] = string.format("%02x", b) end
  return table.concat(s, " ")
end

-- the boss line: what the shadow says cell 0 is, and whether the field map
-- shows it (not veiled by an animation or a dialog)
local slot
local function line(s)
  local base = SHADOW + s * 14
  local addr = H.readWord(base)
  local word = H.readWord(base + 4)
  local drawn = addr ~= 0 and (emu.read(addr * 2, vr) | (emu.read(addr * 2 + 1, vr) << 8)) or nil
  return addr, word, drawn
end
local function lineDrawn(s)
  local addr, word, drawn = line(s)
  return addr ~= 0 and (word & 0xFF) ~= 0xFF and drawn == word
end

local function check(n, tag)
  local addr, word, drawn = line(slot)
  local cell = word & 0xFF
  local got = tileBytes(cell)
  H.log(string.format("[hudcount] %s: slot %d shields %d/%d, line @%04X cell $%02X "
    .. "(field map word %04X), tile %s", tag, slot, H.readByte(SHIELD_CUR + slot * 2),
    H.readByte(SHIELD_MAX + slot * 2), addr, cell, drawn or 0, hex(got)))
  H.screenshot("hudcount_" .. tag)
  local want = romTile(n)
  H.log(string.format("[hudcount] %s: ROM tile for %d: %s; for 6: %s", tag, n, hex(want),
    hex(romTile(6))))
  H.assertEq(hex(got), hex(want),
    string.format("%s: the drawn shield tile is the ROM's tile for the true count %d", tag, n))
  H.assertEq(hex(want) ~= hex(romTile(6)), true,
    string.format("%s: the tile for %d is not the tile for 6", tag, n))
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntilSoft(function()
    return map() == 273 and H.tileAligned() and bright() >= 15
  end, 3000, "landed at the 273 save point"),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("n024-entry-save-v1") end),
  H.navTo(25, 52, { maxFrames = 6000, playBattles = "tactical" }),
  H.call(function()
    H.assertEq(map(), 273, "on map 273")
    H.assertEq(H.fieldX(), 25, "NUMBER 024 entry point x")
    H.assertEq(H.fieldY(), 52, "NUMBER 024 entry point y")
  end),
  H.hold({ "up" }), H.waitFrames(4), H.release(), H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "battle 72 opens"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.call(function()
    local best
    for s = 0, 5 do
      if (H.readByte(0x3AA8 + s * 2) & 1) == 1 then
        local m = H.readByte(SHIELD_MAX + s * 2)
        if best == nil or m > best then best, slot = m, s end
      end
    end
    H.assertEq(slot ~= nil, true, "a monster is present")
    H.log(string.format("[hudcount] most-shielded monster: slot %d, species $%03X, %d shields",
      slot, H.readWord(0x57C0 + slot * 2), best))
    H.assertEq(best > 6, true, "precondition: a monster here carries more than 6 shields")
    H.assertEq(H.readByte(SHIELD_CUR + slot * 2), best, "precondition: its shields are all up")
  end),
  H.waitUntil(function() return lineDrawn(slot) end, 1800,
    "the boss's HUD line is drawn on the field map", 5),
  H.waitFrames(8),
  H.call(function() check(H.readByte(SHIELD_CUR + slot * 2), tostring(H.readByte(SHIELD_CUR + slot * 2))) end),

  -- SYNTHETIC: two numerals (see the header)
  H.call(function()
    H.log("[hudcount] SYNTHETIC: shields written to 11 (declared expedient)")
    H.writeByte(SHIELD_CUR + slot * 2, 11)
  end),
  H.waitUntil(function()
    return H.readByte(BROKEN + slot * 2) == 0 and lineDrawn(slot)
      and hex(tileBytes(select(2, line(slot)) & 0xFF)) == hex(romTile(11))
  end, 600, "the slot's cell holds the tile for 11", 1),
  H.waitFrames(4),
  H.call(function() check(11, "11_synthetic") end),
})
