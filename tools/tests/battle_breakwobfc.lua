-- @suite
-- battle_breakwobfc.lua -- the Floating Continent's monster box, its authored break row re-verified from the
-- shipped ROM (the battle_breakgate discipline): Gigantos carries its Ot6ShieldTbl row, and its formation (170) is
-- chippable by the landing party, TERRA, LOCKE and EDGAR's blades (slash) and SHADOW's point (pierce).
-- docs/design/wob-towns-boxes.md section 4 is the design these numbers come from.
local H = dofile("tools/tests/lib/ot6.lua")

local WANT = {                    -- species -> { shields, class mask }
  [0x0AE] = { 5, 0x01 | 0x04 },   -- gigantos: slash|bludg
}
local FORMS = { 170 }
local PARTY_CLASSES = 0x01 | 0x02          -- slash+pierce on hand

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local tbl = H.sym("Ot6ShieldTbl") & 0x3FFFFF
    local found, a = {}, tbl
    while true do
      local sp = H.readRomByte(a) | (H.readRomByte(a + 1) << 8)
      if sp == 0xFFFF then break end
      found[sp] = { H.readRomByte(a + 2), H.readRomByte(a + 3) }
      a = a + 4
    end
    for sp, want in pairs(WANT) do
      local got = found[sp]
      H.assertEq(got ~= nil, true, string.format("species $%03X has an authored row", sp))
      H.assertEq(got[1], want[1], string.format("species $%03X shields", sp))
      H.assertEq(got[2], want[2], string.format("species $%03X class mask", sp))
    end
    local bm = H.sym("BattleMonsters") & 0x3FFFFF
    for _, f in ipairs(FORMS) do
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local n, chippable = 0, false
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then
          local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
          H.assertEq(WANT[sp] ~= nil, true, string.format("formation %d slot %d: species $%03X is the box's "
            .. "authored one", f, s, sp))
          n = n + 1
          if (found[sp][2] & PARTY_CLASSES) ~= 0 then chippable = true end
        end
      end
      H.assertEq(n > 0 and chippable, true, string.format("formation %d is chippable by the party's classes", f))
    end
    H.log("the Floating Continent's box row verified against the shipped ROM")
  end),
})
