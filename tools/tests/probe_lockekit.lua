-- probe_lockekit.lua -- what is solo LOCKE actually holding, and what are his
-- stats, at the top of his own scenario?  Reads only (issue #75).
--
-- Asked because the first full-frontier run that ever reached sfigaro_town
-- measured him doing EIGHT damage a swing to the gate soldier's HeavyArmor
-- (495 hp, level 13, weak to bolt|water -- neither of which LOCKE can
-- reach).  Eight is low enough that "he is unarmed" and "the fight is tuned
-- past him" are both live explanations, and they call for very different
-- responses, so look before concluding.
--
-- Character block is $1600 + 37*c: +8 level, +9/+11 hp, +13/+15 mp,
-- +$0C..$0F the four battle powers, +$1F/$20 weapon/shield, +$21..$23 the
-- rest of the equipment (ff6/notes/field-ram.txt).
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_lockekit.lua
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/locke_scenario.mss.lua"

H.run({ maxFrames = 20000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 900, "field control", 5),
  H.call(function()
    for _, c in ipairs(H.partyMembers()) do
      local b = 0x1600 + 37 * c
      local eq = {}
      for o = 0x1f, 0x23 do
        eq[#eq + 1] = string.format("%02X", H.readByte(b + o))
      end
      H.log(string.format("char %d: L%d hp=%d/%d mp=%d/%d | vigor=%d " ..
        "speed=%d stamina=%d magpwr=%d | equip %s", c,
        H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11),
        H.readWord(b + 13), H.readWord(b + 15),
        H.readByte(b + 0x0c), H.readByte(b + 0x0d),
        H.readByte(b + 0x0e), H.readByte(b + 0x0f),
        table.concat(eq, " ")))
      H.log(string.format("char %d: row byte $1850+%d = %02X (back=%s)",
        c, c, H.readByte(0x1850 + c),
        tostring((H.readByte(0x1850 + c) & 0x20) ~= 0)))
    end
    local inv = {}
    for i = 0, 30 do
      local id, n = H.readByte(0x1869 + i), H.readByte(0x1969 + i)
      if n > 0 then inv[#inv + 1] = string.format("%02X x%d", id, n) end
    end
    H.log("bag: " .. table.concat(inv, ", "))
    H.log(string.format("gil=%d", H.readByte(0x1860)
      + (H.readByte(0x1861) << 8) + (H.readByte(0x1862) << 16)))
  end),
})
