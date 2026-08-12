-- @suite
-- battle_seedladder.lua -- the retry ladder plays three different fights, and
-- the check that says so is not vacuous.
--
-- Issue #83.  Nine generators carry a three-attempt retry ladder whose whole
-- claim to being evidence is that its attempts are three different fights: a
-- ladder that loses all three is reported as a finding about the encounter
-- rather than retried, which is what replaced the rigging #74 documents.  The
-- attempts were spread with `H.waitFrames((n - 1) * 37)` and a comment saying
-- that varied the battle RNG seed.  Nothing read the seed back.
--
-- Where the seed comes from (ff6/src/battle/battle_main.asm:6174-6176, inside
-- InitBattle at :6138): `lda $021e / asl2 / sta $be`.  $021e is
-- wGameTimeFrames (ff6/src/menu/menu_ram.inc:343), which IncGameTime
-- (ff6/src/menu/menu_common.asm:3522-3549) runs 1..60 and wraps, ticked once
-- per vblank from the field, world and battle NMIs.  So the seed is
-- (frames * 4) & $FF, one value per phase, and $be indexes RNGTbl for every
-- battle Rand (battle_main.asm:12640-12666).
--
-- probe_ladder_seed.lua measured the shipped ladder against that.  The
-- premise held -- waiting does move the phase -- but the spread did not
-- follow from it.  Attempts 2 and 3 reload the entry blob and then spend a
-- fixed ~92 frames before their own offset, so they land 37 apart; attempt 1
-- runs in place at whatever phase the generator's step layout leaves it.  With
-- 36 frames of lead in front of attempt 1 and nothing else changed, attempts 1
-- and 2 both drew seed $9C and attempt 3 drew $4C: one fight played twice,
-- which is #80's reported signature.
--
-- H.newSeedLadder replaces the constant with the counter the seed is made of.
-- This test runs it over battle_entry's first encounter and checks both
-- halves of the claim:
--
--   1. positive -- three attempts through the reload-and-spread shape draw
--      three distinct seeds, and L.report() passes;
--   2. negative -- two attempts driven onto one phase draw one seed, and
--      L.report() raises.  Without this half, a report() that could never
--      fail would print the same green as one that checked something.  The
--      control is a real pair of attempts, not a poked table: identical route,
--      identical seed, which is exactly how the old ladder degenerated.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local blob = nil

-- Capture the entry-point blob every attempt reloads.
local function captureBlob()
  local req
  return H.seqStep({
    H.call(function() req = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "entry-point blob")
      blob = req.blob
    end),
  })
end

-- One attempt: reload the entry point, take the ladder's spread, walk into
-- the fight.  Attempt 1 reloads too, so every attempt of both ladders has the
-- same route and the spread is the only difference between them.
local function attempt(L, n, sopts)
  local loadReq
  return H.seqStep({
    H.call(function() loadReq = H.requestLoadState(blob) end),
    H.waitFrames(2),
    H.call(function() H.checkReq(loadReq, "entry-point reload") end),
    H.waitFrames(90),
    L.spread(n, sopts),
    H.enterEncounter(),
    H.waitFrames(20),
  })
end

local POS = H.newSeedLadder("spread ladder")
local NEG = H.newSeedLadder("collision control")

H.run({ maxFrames = 8000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  captureBlob(),

  -- 1. The positive case.
  POS.watch(),
  attempt(POS, 1), attempt(POS, 2), attempt(POS, 3),
  POS.report(),
  H.call(function()
    -- The seeds are also required to be the ones the phases predict, so this
    -- test fails if the seeder stops being (game-time frames * 4) rather than
    -- quietly watching an instruction that no longer means what the header
    -- says.  A distinctness check over garbage would still pass.
    for n = 1, 3 do
      local s = POS.seeds[n]
      H.assertEq(s ~= nil, true, "attempt " .. n .. " recorded a seeding")
      H.assertEq(s.seed, H.seedOf(s.phase),
        "attempt " .. n .. " seed is (game-time frames * 4) & $FF")
    end
    -- ...and spread apart rather than merely unequal: the gap is 20 phases,
    -- and the drive from the spread to InitBattle jittered by 3 frames when
    -- measured, so anything under about 10 would mean the spread is not
    -- surviving the walk into the fight.
    for a = 1, 3 do
      for b = a + 1, 3 do
        local d = (POS.seeds[a].phase - POS.seeds[b].phase) % H.SEED_PERIOD
        d = math.min(d, H.SEED_PERIOD - d)
        H.log(string.format("attempts %d/%d are %d phases apart", a, b, d))
        H.assertEq(d >= 10, true,
          string.format("attempts %d and %d are at least 10 phases apart", a, b))
      end
    end
  end),

  -- 2. The negative control: attempt 2 is pinned to attempt 1's phase.  Same
  -- route, same phase, so the same fight -- and the checker has to say so.
  NEG.watch(),
  attempt(NEG, 1),
  attempt(NEG, 2, { forcePhase = function() return NEG.targets[1] end }),
  H.call(function()
    H.assertEq(NEG.seeds[1] ~= nil and NEG.seeds[2] ~= nil, true,
      "both control attempts reached a battle")
    H.assertEq(NEG.seeds[2].seed, NEG.seeds[1].seed,
      "the control's two attempts drew ONE seed (same route, same phase)")
    -- report() is a no-frame step, so its tick can be run here and caught.
    local ok, err = pcall(NEG.report().tick)
    H.assertEq(ok, false,
      "the ladder's own check REJECTS two attempts that drew one seed")
    H.log("negative control raised, as it must: " .. tostring(err))
    H.assertEq(tostring(err):find("both drew battle RNG seed") ~= nil, true,
      "and it failed for the seed collision, not for some other reason")
  end),

  -- 3. The other way report() can be vacuous: nothing recorded at all.
  H.call(function()
    local EMPTY = H.newSeedLadder("empty control")
    local ok, err = pcall(EMPTY.report().tick)
    H.assertEq(ok, false,
      "a ladder that recorded no seeding at all FAILS rather than passing")
    H.assertEq(tostring(err):find("no battle seeding was recorded") ~= nil, true,
      "and it says so")
  end),
})
