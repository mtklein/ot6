-- @manual
-- probe_backattack_j39.lua -- the fight driver against a BACK ATTACK (#176).
--
--   tools/tests/run.sh tools/tests/probe_backattack_j39.lua \
--     build/states/backattack_j39.log
--
-- Boots `_lab_j39_start.mss` -- the first frame of the J39-row fight the
-- potion-route dadaluma_entry attempt drew as a back attack, banked by
-- `lab_zozo4_j39_snap.lua` on origin/wt/potion-route (commit f157c19b) and
-- copied in; it is a legitimately reached in-battle snapshot of that run,
-- not a state this file builds.  The fixture is not in the savestate graph,
-- so this is a hand-run instrument rather than a suite test; the layout
-- arithmetic it exercises (H.battleLayout) is asserted in the suite by
-- battle_healpolicy.
--
-- The fight is played by the library driver with the Zozo climb's own
-- options (the ones the failing run used: Bio Blaster, the six-slot focus
-- order).  Before the fix the focus steer pressed LEFT to cross from the
-- party side -- in a back attack LEFT is an rts (btlgfx_main.asm's "move
-- character target left jump table", back-attack entry `_c174e9: rts`) --
-- and the parked-window watchdog dropped the plan every 13 pulses until
-- the party died.  This asserts the driver reads the layout, crosses to
-- the monster side, and wins.
local H = dofile("tools/tests/lib/ot6.lua")

local CELES = 6
local ZOZO_FOCUS = {
  { slot = 0, mask = 0x01 }, { slot = 1, mask = 0x02 },
  { slot = 2, mask = 0x04 }, { slot = 3, mask = 0x08 },
  { slot = 4, mask = 0x10 }, { slot = 5, mask = 0x20 },
}
local STATE = "build/states/_lab_j39_start.mss.lua"

local F = H.newFightDriver("j39 back attack", { tactical = true, boost = true,
  bank = 3, items = true, healPercent = 60, healer = CELES, cadence = 12,
  tool = H.BIO_BLASTER, focus = ZOZO_FOCUS })

local function chp(e) return H.readWord(0x3BF4 + e * 2) end
local function mhp(s) return H.readWord(0x3BFC + s * 2) end
local function monstersLeft()
  local n = 0
  for s = 0, 5 do if mhp(s) > 0 then n = n + 1 end end
  return n
end
local function partyAlive()
  local n = 0
  for e = 0, 3 do if chp(e) > 0 then n = n + 1 end end
  return n
end

local crossed, sawMons, pulses = false, 0, 0
local startFrame = nil
-- The last reading taken while the battle was still up: after it ends the
-- battle HP words read $FFFF and the monster table is stale, so "won" has
-- to be recorded on the frame it happened.
local lastUp = nil

H.run({ maxFrames = 40000, allowGameOver = true }, {
  H.loadState(STATE),
  H.waitFrames(60),
  H.call(function()
    startFrame = H.frame
    local L = H.battleLayout()
    H.log(string.format("[probe] loaded: battle type $%02X (%s) group $%02X, "
      .. "party %d/%d/%d/%d, monsters up %d, menu state $%02X",
      L.type, L.name, L.group, chp(0), chp(1), chp(2), chp(3),
      monstersLeft(), H.readByte(0x7BC2)))
    H.assertEq(L.type, 1, "the J39-row fight is a BACK ATTACK ($201F = 1)")
    H.assertEq(L.toMonsters[1], "right",
      "in a back attack the cursor crosses to the monsters with RIGHT")
  end),

  -- play it
  H.driveUntil(function() return not H.battleLoadStarted() end, 36000, {
    H.call(function()
      pulses = pulses + 1
      local mons = H.readByte(0x7B7E)
      if H.readByte(0x7BC2) == 0x38 and mons ~= 0 then
        sawMons = sawMons + 1
        if not crossed then
          crossed = true
          H.log(string.format("[probe] the cursor is on the MONSTER side at "
            .. "f%d: mons=%02X chars=%02X", H.frame, mons, H.readByte(0x7B7D)))
        end
      end
      if pulses % 600 == 0 then
        H.log(string.format("[probe] f%d party=%d/%d/%d/%d monsters up %d",
          H.frame, chp(0), chp(1), chp(2), chp(3), monstersLeft()))
      end
      if H.battleActive() then
        lastUp = { frame = H.frame, monsters = monstersLeft(), alive = partyAlive(),
                   hp = string.format("%d/%d/%d/%d", chp(0), chp(1), chp(2), chp(3)) }
      end
      F.frame()
    end),
  }, "the back-attack fight, played by the driver"),

  H.call(function()
    H.setPad({})
    H.log(string.format("[probe] battle over at f%d (+%d); last in-battle "
      .. "reading f%d: party %s (%d alive), monsters up %d; target-select "
      .. "frames on the monster side %d", H.frame, H.frame - startFrame,
      lastUp and lastUp.frame or -1, lastUp and lastUp.hp or "?",
      lastUp and lastUp.alive or -1, lastUp and lastUp.monsters or -1, sawMons))
    H.assertEq(crossed, true,
      "the target cursor reached the monster side in a back attack")
    H.assertEq(lastUp ~= nil and lastUp.monsters, 0,
      "every monster is down on the last in-battle frame: the fight is won")
    H.assertEq(lastUp ~= nil and lastUp.alive > 0, true,
      "the party came out of it alive")
  end),
})
