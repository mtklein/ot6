-- shot_field_items.lua -- screenshot evidence for weapon-class icons and the
-- relabeled type-word column in the field item menu.
--
-- Boots vector_entry (LOCKE CELES SABIN EDGAR standing in Vector) and
-- shoots the bag that save carries: PIERCE and SLASH weapons plus a page
-- of classless rows, so the icon column's "no class = no icon" face shows
-- beside both glyphs.  BLUDG and SPECIAL icon correctness is asserted
-- per-class in battle_class and battle_breaktbl instead.
--
-- The bag composition is logged (read-only) so the shot is self-describing.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_entry.mss.lua"

local WCLASS = H.sym("Ot6WeapClassTbl") & 0x3FFFFF

local function classOf(id)
  local c = H.readRomByte(WCLASS + id)
  local names = {}
  if (c & 0x01) ~= 0 then names[#names + 1] = "SLASH" end
  if (c & 0x02) ~= 0 then names[#names + 1] = "PIERCE" end
  if (c & 0x04) ~= 0 then names[#names + 1] = "BLUDG" end
  if (c & 0x08) ~= 0 then names[#names + 1] = "SPECIAL" end
  if #names == 0 then return nil end
  return table.concat(names, "+")
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),

  -- the real bag, read and logged: the evidence the shot documents
  H.call(function()
    local classes = {}
    for i = 0, 255 do
      local id = H.readByte(0x1869 + i)
      if id ~= 0xFF then
        local cl = classOf(id)
        if cl then
          classes[cl] = true
          H.log(string.format("bag[%3d] item=$%02X x%d class=%s", i, id,
            H.readByte(0x1969 + i), cl))
        end
      end
    end
    local cs = {}
    for k in pairs(classes) do cs[#cs + 1] = k end
    table.sort(cs)
    H.log("bag weapon classes: " .. table.concat(cs, " "))
    H.assertEq(#cs >= 2, true,
      "the save's own bag carries at least two weapon classes to shoot")
  end),

  -- FF6 opens the field menu with X
  H.pressButtons({ "x" }, 4),
  H.waitFrames(150),
  H.call(function() H.screenshot("field_menu_main") end),

  -- cursor opens on Items
  H.pressButtons({ "a" }, 4),
  H.waitFrames(150),
  H.call(function() H.screenshot("field_items") end),

  -- scroll so the save's SLASH rows (ThunderBlade, Ashura, mid-list in the
  -- menu's own display order) are in a shot too
  H.repeatN(27, { H.pressButtons({ "down" }, 4), H.waitFrames(8) }),
  H.waitFrames(30),
  H.call(function() H.screenshot("field_items_scrolled") end),
})
