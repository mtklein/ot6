-- @suite
-- battle_absorbguard.lua -- the absorbed-weapon guard.
--
--   tools/tests/run.sh tools/tests/battle_absorbguard.lua
--
-- The guard lives in M.run's per-frame callback (lib/ot6.lua): once per
-- battle it reads the formation's species and every party member's
-- equipped weapon, and fails the run if a weapon's element is absorbed by
-- anything in the formation.
--
-- This file checks it on the Whelk fight, whose shell $0100 absorbs bolt:
--
--   1. the offsets, pinned against behaviour recorded elsewhere -- if
--      monster_prop's absorb byte moves, or item_prop's element byte
--      does, these fail here rather than silently making the guard read
--      zeroes and pass everything;
--   2. the live formation really is read, and it really does contain an
--      absorber;
--   3. THE NEGATIVE CONTROL: the same M.absorbClashesFor the guard calls,
--      given the live formation off $57c0 and one fabricated ThunderBlade,
--      must report the clash;
--   4. the guard actually ran on this battle (M.absorbGuardBattles) and
--      found nothing, which is correct: the Magitek party holds no
--      elemental weapon;
--   5. a party holding no weapon at all, and a formation of absorbers,
--      must produce nothing -- the clause that would catch a guard that
--      returns a hit for everything.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"

local SHELL, HEAD = 0x0100, 0x0134
local THUNDERBLADE, MITHRILKNIFE = 0x0F, 0x01

local aPhase = 0

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  -- 1. the data offsets, before any of it is used.
  H.call(function()
    H.assertEq(H.weaponElement(THUNDERBLADE), 0x04, "ThunderBlade $0F is bolt")
    H.assertEq(H.weaponElement(MITHRILKNIFE), 0x00,
      "MithrilKnife $01 carries no element")
    H.assertEq(H.monsterAbsorb(0x0109), 0x01, "Ifrit $0109 absorbs fire")
    H.assertEq(H.monsterAbsorb(0x0108), 0x02, "Shiva $0108 absorbs ice")
    H.assertEq(H.monsterAbsorb(0x010D), 0x04, "Crane $010D absorbs bolt")
    H.assertEq(H.monsterAbsorb(SHELL), 0x04, "Whelk shell $0100 absorbs bolt")
  end),

  -- walk onto the trigger tile
  H.driveUntil(function()
    return H.battleLoadStarted() and H.monstersPresent() > 0
  end, 2600, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then H.setPad({}); return end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  -- past the guard's own settle, so the count below is the battle's
  H.waitFrames(120),

  H.call(function()
    -- 2. the formation, read the way the guard reads it
    local species = H.formationSpecies()
    local shown = {}
    for _, s in ipairs(species) do
      shown[#shown + 1] = string.format("slot %d $%04X absorb=%s", s.slot,
        s.species, H.elemStr(H.monsterAbsorb(s.species)))
    end
    H.log(string.format("formation mask $%02X: %s",
      H.readByte(H.FORMATION_MASK), table.concat(shown, ", ")))
    H.assertEq(#species, 2, "the whelk formation occupies two slots")
    H.assertEq(species[1].species, SHELL, "slot 0 is the shell $0100")
    H.assertEq(species[2].species, HEAD, "slot 1 is the head $0134")

    -- 3. the negative control. Live formation, fabricated weapon: the
    -- shell absorbs bolt, so a ThunderBlade in anyone's hand must clash.
    local bolt = H.absorbClashesFor(
      { { char = 0, hand = "R", item = THUNDERBLADE } }, species)
    H.assertEq(#bolt, 1, "a ThunderBlade into the live whelk formation "
      .. "is one clash")
    H.assertEq(bolt[1].species, SHELL, "and the absorber named is the shell")
    H.assertEq(bolt[1].absorbed, 0x04, "on bolt")
    H.log("negative control: " .. H.clashStr(bolt[1]))

    -- and the other half of it: an element-free weapon against the same
    -- formation is not a clash, so this is not a function that says yes
    -- to everything
    H.assertEq(#H.absorbClashesFor(
      { { char = 0, hand = "R", item = MITHRILKNIFE } }, species), 0,
      "a MithrilKnife into the same formation is no clash")

    -- 5. no weapons at all, against a formation of three absorbers
    H.assertEq(#H.absorbClashesFor({}, {
      { slot = 0, species = SHELL }, { slot = 1, species = 0x0109 },
      { slot = 2, species = 0x010D },
    }), 0, "an empty party clashes with nothing")

    -- 4. and the guard itself ran, on this battle, against the party's
    -- real gear.
    local live = {}
    for _, w in ipairs(H.partyWeapons()) do
      live[#live + 1] = string.format("c%d/%s=$%02X(%s)", w.char, w.hand,
        w.item, H.elemStr(H.weaponElement(w.item)))
    end
    H.log("party weapons: " .. (table.concat(live, " ")))
    H.assertEq(H.absorbGuardBattles >= 1, true,
      "the guard inspected this battle")
    H.assertEq(H.absorbGuardClashes, 0,
      "and found no clash in the party's real gear")
    H.assertEq(H.readByte(H.RANDBTL), 0,
      "the whelk is an event battle, so the guard would have failed on a "
      .. "clash rather than logged one")
  end),
})
