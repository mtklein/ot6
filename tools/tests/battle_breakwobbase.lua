-- @suite
-- battle_breakwobbase.lua -- the Imperial Base's guard fights' authored break rows, re-verified from the shipped
-- ROM (the battle_breakgate discipline): the three species carry their Ot6ShieldTbl rows, and both guard
-- formations (416, 417) are chippable by the party that first meets them, EDGAR, SABIN, LOCKE and CELES after the
-- Opera (the pike, the daggers, the blade, SABIN's knuckle and blitzes).  docs/design/wob-towns-boxes.md
-- section 1 is the design these numbers come from.
local H = dofile("tools/tests/lib/ot6.lua")

local SWORD, DAGGER, BLUNT, RANGED, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20   -- ot6_class.asm (#566)
local W, SK = H.weaponClass, H.skillClass   -- a hand: the class the built ROM gives a weapon, a skill

local WANT = {                    -- species -> { shields, class mask }
  [0x0C7] = { 2, DAGGER },          -- commando: dagger
  [0x165] = { 2, RANGED },          -- protoarmor: ranged
  [0x102] = { 3, DAGGER | BLUNT },  -- mega armor: dagger|blunt
}
local FORMS = { 416, 417 }
-- post-opera-v1: EDGAR's Mithril Pike $1D, LOCKE's MithrilKnives $01, CELES's RegalCutlass $0B, SABIN's Kaiser $55
-- and Pummel $5D
local PARTY_CLASSES = W(0x1D) | W(0x01) | W(0x0B) | W(0x55) | SK(0x5D)

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
          H.assertEq(WANT[sp] ~= nil, true, string.format("formation %d slot %d: species $%03X is one of the base's "
            .. "authored three", f, s, sp))
          n = n + 1
          if (found[sp][2] & PARTY_CLASSES) ~= 0 then chippable = true end
        end
      end
      H.assertEq(n > 0 and chippable, true, string.format("formation %d is chippable by the party's classes", f))
    end
    H.log("the Imperial Base's guard rows verified against the shipped ROM")
  end),
})
