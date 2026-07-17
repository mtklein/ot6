-- shot_field_items.lua -- SCREENSHOT EVIDENCE for weapon-class icons + the
-- relabeled type-word column in the FIELD item menu. Loads the arvis_wake
-- fixture (Terra alone, normal commands), pokes one weapon per break class
-- (plus classless Heal Rod) into $1869/$1969, opens the menu with start,
-- enters Items (default cursor entry), and screenshots the list.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/arvis_wake.mss.lua"

local ITEMS = { 0x00, 0x2B, 0x47, 0x51, 0x33 }

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "field control", 5),

  H.call(function()
    for i, id in ipairs(ITEMS) do
      H.writeByte(0x1869 + i - 1, id)
      H.writeByte(0x1969 + i - 1, 9)
    end
    H.log("inventory slots 0-4 poked with one weapon per class")
  end),

  -- FF6 opens the field menu with X
  H.pressButtons({ "x" }, 4),
  H.waitFrames(150),
  H.call(function() H.screenshot("field_menu_main") end),

  -- cursor opens on Items
  H.pressButtons({ "a" }, 4),
  H.waitFrames(150),
  H.call(function() H.screenshot("field_items") end),
})
