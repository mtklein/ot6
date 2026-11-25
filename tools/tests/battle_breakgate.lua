-- @suite
-- battle_breakgate.lua -- the Sealed Gate cave's authored break rows,
-- re-verified from the shipped ROM (the battle_breakvector discipline):
-- every cave species carries its authored Ot6ShieldTbl row, and every
-- formation the maps 382-386 can draw is chippable by the mission
-- party's hands (TERRA's and EDGAR's blades, LOCKE's daggers, EDGAR's
-- AutoCrossbow, SABIN's fists).  docs/design/break-coverage-gate.md
-- is the survey these numbers came from.
local H = dofile("tools/tests/lib/ot6.lua")

local SWORD, DAGGER, BLUNT, RANGED, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20   -- ot6_class.asm (#566)
local W, SK = H.weaponClass, H.skillClass   -- a hand: the class the built ROM gives a weapon, a skill

local WANT = {                    -- species -> { shields, class mask }
  -- audit_break_coverage.py's break-dark findings (kolts + zozo):
  [0x086] = { 2, DAGGER | RANGED }, -- cirpius: dagger|ranged
  [0x053] = { 2, BLUNT | RANGED },  -- hadesgigas: blunt|ranged
  [0x052] = { 2, SWORD | KATANA },  -- slamdancer: sword|katana
  [0x04E] = { 2, SWORD | SPEAR },   -- harvester: sword|spear
  [0x0DF] = { 2, DAGGER | RANGED }, -- gabbldegak: dagger|ranged
  [0x06E] = { 2, SWORD | DAGGER },  -- ninja: sword|dagger
  [0x0E5] = { 2, KATANA | BLUNT | RANGED }, -- spirit: katana|blunt|ranged (#347)
  [0x0B3] = { 2, SWORD },           -- soft flier: sword
  [0x048] = { 3, DAGGER | BLUNT },  -- shelled tank: dagger|blunt
  [0x082] = { 4, SWORD | RANGED },  -- brute: sword|ranged
}
-- the mission party's hands (gate-cave-save-v1): TERRA's ThunderBlade $0F and EDGAR's Blizzard $0E, LOCKE's
-- MithrilKnives $01, EDGAR's AutoCrossbow $AA, SABIN's Pummel $5D and his Poison Claw $56
local PARTY_CLASSES = W(0x0F) | W(0x0E) | W(0x01) | W(0xAA) | SK(0x5D) | W(0x56)

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    -- 1. the authored rows, straight out of the shipped table
    local tbl = H.sym("Ot6ShieldTbl") & 0x3FFFFF
    local found = {}
    local a = tbl
    while true do
      local sp = H.readRomByte(a) | (H.readRomByte(a + 1) << 8)
      if sp == 0xFFFF then break end
      found[sp] = { H.readRomByte(a + 2), H.readRomByte(a + 3) }
      a = a + 4
    end
    for sp, want in pairs(WANT) do
      local got = found[sp]
      H.assertEq(got ~= nil, true,
        string.format("species $%03X has an authored row", sp))
      H.assertEq(got[1], want[1],
        string.format("species $%03X shields", sp))
      H.assertEq(got[2], want[2],
        string.format("species $%03X class mask", sp))
    end

    -- 2. every drawable formation on maps 382-386 is chippable by the
    -- mission party's classes (the coverage rule, applied here)
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    for _, m in ipairs({ 382, 383, 384, 385, 386 }) do
      local g = H.readRomByte(sbg + m)
      for slot = 0, 3 do
        local f = H.readRomByte(rbg + g * 8 + slot * 2)
              | (H.readRomByte(rbg + g * 8 + slot * 2 + 1) << 8)
        local rec = bm + f * 15
        local pres = H.readRomByte(rec + 1)
        local hi = H.readRomByte(rec + 14)
        local chippable = false
        for s = 0, 5 do
          if (pres & (1 << s)) ~= 0 then
            local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
            local row = found[sp]
            if row and (row[2] & PARTY_CLASSES) ~= 0 then
              chippable = true
            end
          end
        end
        H.assertEq(chippable, true, string.format(
          "map %d group %d slot %d (formation %d) is chippable by the "
          .. "mission party", m, g, slot, f))
      end
    end
    H.log("sealed-gate break rows verified against the shipped ROM")
  end),
})
