-- @suite savestate=first_battle
-- battle_healerdown.lua -- #128: a dead opts.healer must not lock the fight
-- driver out of all healing.
--
-- The lock, measured twice before the fix (the Zozo stairs, the Thamasa
-- fire): newFightDriver's makePlan gated every item heal and revive on
-- `actor == opts.healer`, so the moment the designated healer died no other
-- actor would ever touch the bag, and the party bled out holding full
-- supplies.  The fix (ot6.lua, the mayHeal block): when no living entity
-- carries the healer's char id, whoever holds an Item row inherits the job.
--
-- This is a focused unit test and stages with sanctioned expedient writes
-- (owner ruling: expedients are fine for unit-style tests; the long
-- playthroughs stay honest):
--   * the healer's death is POKED (hp=0 + status1 $80, the same pair the
--     engine's own dead_sub/SetStatus1 leaves -- measured on real corpses:
--     hp=0 st1=80), because arranging a real targeted kill would couple this
--     test to formation AI luck;
--   * a Fenix Down is ensured in the battle inventory the same way.
-- Both writes are this file's waiver lines.
--
-- The arm: healer dead -> ANOTHER actor revives them with the Fenix Down
-- (asserted by the healer's HP rising above 0 and the Fenix count dropping).
-- The control -- healer ALIVE keeps the role assignment -- is not re-proven
-- here: every chain generator that passes opts.healer (gen_tunnelarmr's
-- healer=6 among them) exercises it green on every full run.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"

local BCHID, BATTINV = 0x3ED8, 0x2686
local FENIX_DOWN = 0xF0

local function hp(e)    return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function st1(e)   return H.readByte(0x3EE4 + e * 2) end

local function fenixCount()
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == FENIX_DOWN then
      return H.readByte(BATTINV + i * 5 + 3), i
    end
  end
  return 0, nil
end

local F = nil          -- the driver under test, built once the battle is up
local healerChid, healerEnt = nil, nil
local fenix0 = 0

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleLoadStarted() end, 3000,
    "the battle is up"),
  H.waitFrames(120),

  H.call(function()
    -- pick the entity in slot 0 as the designated healer, by char id
    healerEnt = 0
    healerChid = H.readByte(BCHID + healerEnt * 2)
    H.assertEq(maxhp(healerEnt) > 0, true, "slot 0 is a real party member")

    -- ensure a Fenix Down exists (expedient write; see header)
    local n, idx = fenixCount()
    if n == 0 then
      for i = 0, 251 do
        if H.readByte(BATTINV + i * 5) == 0xFF then
          H.writeByte(BATTINV + i * 5, FENIX_DOWN)
          H.writeByte(BATTINV + i * 5 + 3, 2)
          break
        end
      end
    end
    fenix0 = fenixCount()
    H.assertEq(fenix0 > 0, true, "a Fenix Down is in the battle bag")

    -- kill the healer (expedient write pair; the engine's own corpse shape)
    H.writeWord(0x3BF4 + healerEnt * 2, 0)
    H.writeByte(0x3EE4 + healerEnt * 2, st1(healerEnt) | 0x80)
    H.assertEq(hp(healerEnt), 0, "the healer is down")
    H.log(string.format("healer = chid %02X in entity %d, killed; fenix=%d",
      healerChid, healerEnt, fenix0))

    F = H.newFightDriver("healerdown", {
      items = true, healer = healerChid, cure = false,
    })
  end),

  -- drive the fight until someone else raises the healer
  H.driveUntil(function()
    return hp(healerEnt) > 0
  end, 30000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "a surviving actor revives the dead healer (#128)"),

  H.call(function()
    H.assertEq(hp(healerEnt) > 0, true,
      "the healer is back on their feet -- the bag opened without them")
    local n = fenixCount()
    H.assertEq(n < fenix0, true,
      "the revive spent a Fenix Down (count " .. fenix0 .. " -> " .. n .. ")")
    H.log("PASSED: a dead designated healer no longer locks the party " ..
      "out of its own bag (#128)")
  end),
})
