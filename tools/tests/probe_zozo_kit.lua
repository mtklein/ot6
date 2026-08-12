-- probe_zozo_kit.lua -- do the six Zozo equips actually land?
--
-- H.equipWeapon grew opts.slot so it could reach the helmet, armour and the
-- two relic rows, and the relic rows are a different menu with their own
-- states and their own cursor.  That is new menu driving, and the place it
-- would be discovered broken is three hours into a savestate chain.  This
-- runs it once, on its own, and reads the slots back.
--
-- It boots zozo_arrival and does exactly what gen_zozo4 now does after its
-- care stop: CELES's LeatherArmor, Star Pendant and Peace Ring, SABIN's
-- Buckler, Star Pendant and Black Belt.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function worn(c, s) return H.readByte(0x1600 + 37 * c + 0x1F + s) end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
    -- The before-state, so a pass here cannot be a slot that was already
    -- filled.  All six must read $ff before anything is driven.
    for _, w in ipairs({ { 6, 3 }, { 6, 4 }, { 6, 5 },
                         { 5, 1 }, { 5, 4 }, { 5, 5 } }) do
      H.assertEq(worn(w[1], w[2]), 0xFF,
        string.format("char %d slot %d is EMPTY before the equip stop",
          w[1], w[2]))
    end
    H.log("[kit] all six slots empty at boot, as measured")
  end),
  H.equipWeapon(1, 0x84, { slot = 3, tag = "CELES LeatherArmor" }),
  H.equipWeapon(1, 0xB1, { slot = 4, tag = "CELES Star Pendant" }),
  H.equipWeapon(1, 0xB2, { slot = 5, tag = "CELES Peace Ring" }),
  H.equipWeapon(3, 0x5A, { slot = 1, tag = "SABIN Buckler" }),
  H.equipWeapon(3, 0xB1, { slot = 4, tag = "SABIN Star Pendant" }),
  H.equipWeapon(3, 0xD5, { slot = 5, tag = "SABIN Black Belt" }),
  H.call(function()
    for _, w in ipairs({ { 6, 3, 0x84, "CELES wears the LeatherArmor" },
                         { 6, 4, 0xB1, "CELES wears the Star Pendant" },
                         { 6, 5, 0xB2, "CELES wears the Peace Ring" },
                         { 5, 1, 0x5A, "SABIN carries the Buckler" },
                         { 5, 4, 0xB1, "SABIN wears the Star Pendant" },
                         { 5, 5, 0xD5, "SABIN wears the Black Belt" } }) do
      H.assertEq(worn(w[1], w[2]), w[3], w[4])
    end
    -- LOCKE's Genji Glove pair is the thing an accidental Optimum would
    -- eat, so check it survived the six walks.
    H.assertEq(worn(1, 0), 0x02, "LOCKE still holds the Guardian")
    H.assertEq(worn(1, 1), 0x01, "LOCKE still holds the MithrilKnife")
    H.assertEq(worn(1, 4), 0xD1, "LOCKE still wears the Genji Glove")
    H.log("[kit] six slots filled, LOCKE's pair untouched")
  end),
})
