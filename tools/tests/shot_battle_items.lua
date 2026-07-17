-- shot_battle_items.lua -- SCREENSHOT EVIDENCE for weapon-class icons in the
-- battle Item list. The magitek party carries no weapons, so poke one weapon
-- of each break class (plus the classless Heal Rod) into the field inventory
-- at $1869/$1969 before walking into fight 1, then open Item and shoot.
--
--   slot 0  $00 Dirk       PIERCE  {spear} (was {dagger})
--   slot 1  $2B Ashura     SLASH   {sword} (was {katana})
--   slot 2  $47 Boomerang  BLUDG   {staff} (was {special})
--   slot 3  $51 Dice       SPECIAL {special} (was {card})
--   slot 4  $33 Heal Rod   no class - repurposed {card} cell (dash)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local ITEMS = { 0x00, 0x2B, 0x47, 0x51, 0x33 }

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  H.call(function()
    for i, id in ipairs(ITEMS) do
      H.writeByte(0x1869 + i - 1, id)
      H.writeByte(0x1969 + i - 1, 9)
    end
    H.log("inventory slots 0-4 poked with one weapon per class")
  end),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  -- input during the first window-open animation wedges the battle menu
  H.waitFrames(240),

  H.waitUntil(function() return H.readByte(0x7bca) ~= 0 end, 1200,
    "command window ready", 10),
  H.call(function()
    -- battle command table: 4 x [cmd, ?, targeting] per slot
    for slot = 0, 3 do
      local base = 0x202e + 12 * slot
      H.log(string.format("cmds slot %d: %02X %02X %02X %02X", slot,
        H.readByte(base), H.readByte(base + 3),
        H.readByte(base + 6), H.readByte(base + 9)))
    end
  end),

  -- Item is the LAST command for every magitek rider (slot dumps:
  -- 1D FF 02 01 / 1D FF FF 01); up from the top wraps straight to it
  H.pressButtons({ "up" }, 4), H.waitFrames(12),
  H.pressButtons({ "a" }, 4),
  H.waitFrames(180),
  H.call(function() H.screenshot("battle_items_top") end),

  -- scroll down to put the 5th row (Heal Rod) in view
  H.pressButtons({ "down" }, 4), H.waitFrames(12),
  H.pressButtons({ "down" }, 4), H.waitFrames(12),
  H.pressButtons({ "down" }, 4), H.waitFrames(12),
  H.pressButtons({ "down" }, 4), H.waitFrames(30),
  H.call(function() H.screenshot("battle_items_scrolled") end),
})
