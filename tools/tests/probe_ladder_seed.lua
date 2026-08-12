-- probe_ladder_seed.lua -- read-only instrument (issue #83): does the
-- three-attempt retry ladder actually play three different fights?
--
-- The claim under test, as the generators state it: "H.waitFrames((n-1)*37)
-- -- vary the battle RNG seed".  Nothing in the tree had ever read the seed
-- back, so this probe reads it.
--
-- Where the seed comes from, from source rather than folklore
-- (ff6/src/battle/battle_main.asm:6174-6176, inside InitBattle at :6138):
--
--     lda     $021e       ; low byte of game time (frames)
--     asl2
--     sta     $be         ; set random number seed
--
-- $021e is wGameTimeFrames (ff6/src/menu/menu_ram.inc:343, the fourth byte
-- of the $021b hours/minutes/seconds/frames block).  IncGameTime
-- (ff6/src/menu/menu_common.asm:3522-3549) runs it 1..60 and wraps, so the
-- phase has period 60, and A is 8-bit here, so the seed is
-- (frames * 4) & $FF: 60 distinct values, 4..240.  $be is the index into
-- RNGTbl that every battle Rand/RandA/RandCarry walks
-- (battle_main.asm:12640-12666).
--
-- This probe hooks the `sta $be` instruction itself and records what each
-- battle was actually seeded with.  It runs the standard ladder shape --
-- attempt 1 in place, attempts 2 and 3 reloading an entry-point blob, each
-- offset by (n-1)*37 frames -- over the battle_entry fixture's first
-- encounter, which is the cheapest real field-to-battle transition in the
-- tree.
--
-- It asserts nothing about the answer.  It prints the three seeds and
-- whether any two collide.
--
--   tools/tests/run.sh tools/tests/probe_ladder_seed.lua

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local PHASE = 0x021E                    -- wGameTimeFrames

-- Locate `lda $021e / asl / asl / sta $be` by its bytes rather than by a
-- hand-copied address: battle_main moves whenever a hook shim changes size.
-- AD 1E 02 = lda abs $021e, 0A 0A = asl a x2, 85 BE = sta dp $be.
local SIG = { 0xAD, 0x1E, 0x02, 0x0A, 0x0A, 0x85, 0xBE }
local function findSeedStore()
  local base = H.sym("InitBattle") & 0x3FFFFF     -- HiROM: cpu -> file offset
  local hits = {}
  for off = 0, 0x200 - #SIG do
    local ok = true
    for i = 1, #SIG do
      if H.readRomByte(base + off + i - 1) ~= SIG[i] then ok = false break end
    end
    if ok then hits[#hits + 1] = base + off end
  end
  assert(#hits == 1, string.format(
    "expected exactly one seed store within InitBattle+$200, found %d", #hits))
  return (hits[1] | 0xC00000) + 5, (hits[1] | 0xC00000)   -- sta addr, lda addr
end

local seedAddr, ldaAddr = nil, nil
local seen = {}                          -- ordered list of observed seeds
local attemptNow, runNow = 0, 0
local LEADS = { [1] = 0, [2] = 36 }

-- One run of the three-attempt ladder, with `lead` frames inserted between
-- the blob capture and attempt 1's entry drive.
local function ladder(run, lead)
  local steps = { H.logStep(string.format(
    "==== ladder run %d (lead %d frames before attempt 1) ====", run, lead)) }
  for n = 1, 3 do
    local loadReq
    steps[#steps + 1] = H.seqStep({
      H.call(function() runNow, attemptNow = run, n end),
      -- Every attempt of run 2, and attempts 2-3 of run 1, start from the
      -- blob; only run 1 attempt 1 is genuinely "in place".  Reloading first
      -- makes the two runs differ in `lead` alone.
      (n > 1 or run > 1) and H.seqStep({
        H.call(function() loadReq = H.requestLoadState(H.vars.blob) end),
        H.waitFrames(2),
        H.call(function() H.checkReq(loadReq, "entry-point reload") end),
        H.waitFrames(90),
      }) or H.seqStep({}),
      (n == 1) and H.waitFrames(lead) or H.waitFrames((n - 1) * 37),
      H.call(function()
        H.log(string.format(
          "[ladder] run %d attempt %d starts driving at f%d, $021e=%d",
          run, n, H.frame, H.readByte(PHASE)))
      end),
      H.enterEncounter(),
      H.waitFrames(30),
    })
  end
  return H.seqStep(steps)
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),

  H.call(function()
    seedAddr, ldaAddr = findSeedStore()
    H.log(string.format("[seed] InitBattle=$%06X  lda $021e at $%06X  sta $be at $%06X",
      H.sym("InitBattle"), ldaAddr, seedAddr))
    emu.addMemoryCallback(function()
      -- Mesen fires an exec callback before the instruction runs, so A here
      -- is the value about to land in $be.  The live phase is logged beside
      -- it so the (frames*4)&$FF relation is checked and not assumed.
      local a = emu.getState()["cpu.a"] & 0xff
      local phase = H.readByte(PHASE)
      seen[#seen + 1] = { run = runNow, attempt = attemptNow, seed = a,
                          phase = phase, frame = H.frame }
      H.log(string.format(
        "[seed] run %d attempt %d: battle seeded $be=$%02X from $021e=%d at f%d",
        runNow, attemptNow, a, phase, H.frame))
    end, emu.callbackType.exec, seedAddr, seedAddr)
  end),

  -- Control 1: does the game-time phase advance one per frame in the field?
  -- If it does not, no amount of waiting moves the seed and the ladder is
  -- dead on arrival regardless of the constant it uses.
  (function()
    local before = nil
    return H.seqStep({
      H.call(function() before = H.readByte(PHASE) end),
      H.waitFrames(37),
      H.call(function()
        local after = H.readByte(PHASE)
        H.log(string.format(
          "[clock] $021e %d -> %d over 37 field frames (delta mod 60 = %d; "
          .. "37 expected if the field NMI ticks it every frame)",
          before, after, (after - before) % 60))
      end),
    })
  end)(),

  -- The entry-point blob the ladder reloads between attempts.
  (function()
    local req
    return H.seqStep({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "entry-point blob")
        H.vars.blob = req.blob
        H.log(string.format("[ladder] blob captured at f%d, $021e=%d",
          H.frame, H.readByte(PHASE)))
      end),
    })
  end)(),

  -- Two runs of the standard three-attempt shape, copied verbatim from
  -- gen_ifrit_magicite.lua:299-325 and battle_brokendeath.lua:248-263, and
  -- differing only in `lead`: the number of frames between the blob capture
  -- and attempt 1's entry drive.
  --
  -- `lead` is the term the ladder never controlled.  Attempt 1 runs in place,
  -- so its phase is (blob phase + lead).  Attempts 2 and 3 reload the blob and
  -- then spend a fixed ~92 frames of trampoline and settle before their own
  -- offset, so their phase is (blob phase + 92 + 37*(n-1)).  Attempts 2 and 3
  -- are therefore always 37 apart, but attempt 1 sits wherever the generator's
  -- own step layout puts it.  Whenever lead lands congruent with attempt 2's
  -- total mod 60, attempts 1 and 2 draw one seed and play one fight twice.
  ladder(1, 0),                          -- the shape as shipped
  ladder(2, 36),                         -- the same shape, 36 frames of lead

  H.call(function()
    H.log("---- ladder seed report ----")
    local first = {}
    for _, s in ipairs(seen) do
      local key = s.run .. "/" .. s.attempt
      if not first[key] then first[key] = s end
      H.log(string.format("  run %d attempt %d  $be=$%02X  $021e=%d  f%d  "
        .. "((021e*4)&FF = $%02X)",
        s.run, s.attempt, s.seed, s.phase, s.frame, (s.phase * 4) & 0xFF))
    end
    for r = 1, 2 do
      local collisions = 0
      for a = 1, 3 do
        for b = a + 1, 3 do
          local x, y = first[r .. "/" .. a], first[r .. "/" .. b]
          if x and y and x.seed == y.seed then
            collisions = collisions + 1
            H.log(string.format(
              "  run %d COLLISION: attempts %d and %d both seeded $%02X "
              .. "-- one fight, played twice", r, a, b, x.seed))
          end
        end
      end
      H.log(string.format("  run %d (lead %d): %d colliding pairs",
        r, LEADS[r], collisions))
    end
  end),
})
