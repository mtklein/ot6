-- shot_field_items.lua -- SCREENSHOT EVIDENCE for weapon-class icons + the
-- relabeled type-word column in the FIELD item menu.
--
-- ISSUE #75 CONVERSION.  This script used to poke one weapon per break class
-- into arvis_wake's empty bag ($1869/$1969) and shoot the forged list.  It
-- now boots vector_doorstep -- the input-driven post-Opera savestate (LOCKE
-- CELES SABIN EDGAR standing in Vector) -- and shoots the bag THAT SAVE
-- really carries.
--
-- What the real bag holds (measured 2026-08-10, recon over the Aug-9
-- regenerations; vector_doorstep is the class-richest bag on the whole
-- input-driven chain):
--   PIERCE  $00 Dirk, $01 MithrilKnife x3, $02 Guardian, $AA
--   SLASH   $0F ThunderBlade x2, $2B Ashura
--   ...plus a page of classless rows (tools, relics, consumables), so the
--   icon column's "no class = no icon" face shows beside both glyphs.
-- That is TWO of the four classes.  No v0.6 bag reachable in play holds BLUDG or
-- SPECIAL yet (the recon swept every Aug-9 fixture); those two glyphs'
-- correctness is asserted per-class in battle_class/battle_breaktbl, and
-- their menu face can be shot organically once a chain step buys or finds
-- one (the plan's "four classes is fine" expected a richer bag than the
-- chain really owns -- recorded here so the gap is a fact, not a surprise).
--
-- The bag composition is LOGGED (read-only) so the shot is self-describing.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_doorstep.mss.lua"

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

  -- the real bag, read and logged -- the evidence the shot is OF
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

  -- scroll so the save's SLASH rows (ThunderBlade, Ashura -- mid-list in the
  -- menu's own display order) are in a shot too
  H.repeatN(27, { H.pressButtons({ "down" }, 4), H.waitFrames(8) }),
  H.waitFrames(30),
  H.call(function() H.screenshot("field_items_scrolled") end),
})
