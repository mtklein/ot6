-- @suite savestate=sfigaro_passage
-- field_mpvisible.lua -- the field menu shows every character's MP, since
-- OT6_MP_COSTS returns has-MP unconditionally (Ot6MpUniversal idiom).
--
-- Fixture: sfigaro_passage, LOCKE solo, no spells known, no espers owned.
--
-- Asserted from the field-menu BG1 tilemap (menu charset: letters $80+,
-- digits $b4-$bd, blank $ff; the char block draws "LV/HP/MP" labels at col
-- 10 of successive rows):
--   1. control: the "HP" label renders, so the menu is open.
--   2. the "MP" label renders one row below it.
--   3. the current-MP digits right of the label equal Locke's save-record MP.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/sfigaro_passage.mss.lua"

local function findPair(a, b)
  local vr = emu.memType.snesVideoRam
  for w = 0x0000, 0x7FF0 do
    if (emu.readWord(w * 2, vr) & 0xFF) == a
       and (emu.readWord((w + 1) * 2, vr) & 0xFF) == b then
      return w
    end
  end
  return nil
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 2000, "field control", 5),
  H.pressButtons({ "x" }, 4),
  H.waitFrames(400),
  H.call(function()
    H.screenshot("field_mp_menu")
    local vr = emu.memType.snesVideoRam
    -- 1. the "HP" label ($87,$8f) anchors the char block
    local hp = findPair(0x87, 0x8F)
    assert(hp, "the field menu's HP label is on screen (menu open)")
    local row = {}
    for c = -1, 12 do
      row[#row + 1] = string.format("%02x", emu.readWord((hp + 32 + c) * 2, vr) & 0xFF)
    end
    H.log("row below HP label: " .. table.concat(row, " "))
    -- 2. the MP label one row (32 map words) below
    local mp = hp + 32
    H.assertEq(emu.readWord(mp * 2, vr) & 0xFF, 0x8C,
      "the MP label renders for a spell-less, esper-less LOCKE ('M')")
    H.assertEq(emu.readWord((mp + 1) * 2, vr) & 0xFF, 0x8F,
      "...and 'P' beside it (pre-fix: the whole row is blank)")
    -- 3. the digits right of the label = Locke's save MP ($1600 + $25*1,
    -- current MP at +$0d).
    local want = H.readWord(0x1632)
    local got, seen = 0, false
    for c = 2, 6 do
      local g = emu.readWord((mp + c) * 2, vr) & 0xFF
      if g >= 0xB4 and g <= 0xBD then
        got = got * 10 + (g - 0xB4)
        seen = true
      end
    end
    H.log(string.format("Locke save MP=%d, menu draws %d", want, got))
    H.assertEq(seen, true, "current-MP digits render beside the label")
    H.assertEq(got, want, "and they equal Locke's natural save pool")
  end),
  H.logStep(function() return "field_mpvisible complete" end),
})
