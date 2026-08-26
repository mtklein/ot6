-- @suite
-- battle_seedladder.lua -- H.newSeedLadder must draw three distinct battle
-- RNG seeds across a three-attempt retry ladder, and its report() must
-- actually fail when that isn't true.
--
-- The battle RNG seed is (game-time frames * 4) & $FF, computed once per
-- phase from $021e (wGameTimeFrames, ticked once per vblank from the field,
-- world and battle NMIs) at InitBattle; $be indexes RNGTbl for every battle
-- Rand.
--
-- This test runs the ladder over battle_entry's first encounter and checks:
--   1. positive -- three attempts through the reload-and-spread shape draw
--      three distinct seeds, and L.report() passes;
--   2. negative -- two attempts driven onto one phase draw one seed, and
--      L.report() raises;
--   3. report() also fails on a ladder that recorded no seeding at all, and
--      on an attempt that took a phase but never fought;
--   4/5. the harness samples $021e once per emulated frame, but the real
--      counter's tick straddles that boundary, so about a quarter of the
--      phases are never what a sample returns. spread() must release when
--      the target phase is one the sampler never shows (case 4), and must
--      still fail when the counter genuinely never moves (case 5).

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local blob = nil

-- Tick one step per frame until it finishes or raises, keeping the error
-- instead of letting it end the run.  The spread is a step, and two of the
-- cases below are about what it does over time rather than what it returns.
local function drive(mk, out, budget, what)
  local step = nil
  return H.seqStep({
    H.call(function() step = mk(); out.frames = 0 end),
    H.driveUntil(function() return out.done end, budget, {
      H.call(function()
        if out.done then return end
        out.frames = out.frames + 1
        local ok, r = pcall(function() return step:tick() end)
        if not ok then out.done, out.err = true, r
        elseif r == "done" then out.done = true end
      end),
    }, what),
  })
end

-- A sampler that aliases the way the real one does: the counter still
-- advances 60 phases per 60 frames, on a four-frame beat (2,1,0,1), and a
-- quarter of them are never what a sample returns.
local BEAT = { 2, 1, 0, 1 }
local function sampleSeq(start, count)          -- the beat, as plain data
  local out, cur = {}, start
  for i = 0, count - 1 do
    out[#out + 1] = cur
    cur = (cur - 1 + BEAT[i % 4 + 1]) % H.SEED_PERIOD + 1
  end
  return out
end
-- The same walk, stepped once per emulated frame rather than once per call,
-- because the spread reads the counter more than once in the frame it starts.
local function aliasedSampler(start)
  local i, cur, atFrame = 0, start, nil
  return function()
    if atFrame ~= H.frame then
      if atFrame ~= nil then
        cur = (cur - 1 + BEAT[i % 4 + 1]) % H.SEED_PERIOD + 1
        i = i + 1
      end
      atFrame = H.frame
    end
    return cur
  end
end
-- The first phase at least `away` ahead of `start` that the sampler never
-- returns.  `away` keeps the case honest by putting the target most of a
-- cycle out.
local function neverSampled(start, away)
  local seen = {}
  for _, v in ipairs(sampleSeq(start, H.SEED_PERIOD * 4)) do seen[v] = true end
  for d = away, H.SEED_PERIOD - 1 do
    local v = (start - 1 + d) % H.SEED_PERIOD + 1
    if not seen[v] then return v end
  end
  return nil
end

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
    -- The seeds must also equal what the phases predict, not merely differ
    -- from each other.
    for n = 1, 3 do
      local s = POS.seeds[n]
      H.assertEq(s ~= nil, true, "attempt " .. n .. " recorded a seeding")
      H.assertEq(s.seed, H.seedOf(s.phase),
        "attempt " .. n .. " seed is (game-time frames * 4) & $FF")
    end
    -- ...and spread apart rather than merely unequal: the gap is 20 phases;
    -- anything under about 10 means the spread did not survive the walk
    -- into the fight.
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

  -- 3. The other two ways report() could be vacuous.
  H.call(function()
    local EMPTY = H.newSeedLadder("empty control")
    local ok, err = pcall(EMPTY.report().tick)
    H.assertEq(ok, false,
      "a ladder that recorded no seeding at all FAILS rather than passing")
    H.assertEq(tostring(err):find("no battle seeding was recorded") ~= nil, true,
      "and it says so")
  end),

  -- An attempt that takes a phase and then never fights is the subtler one:
  -- the other attempts still compare fine, so the ladder would report green
  -- while covering one fewer fight than it claims.  SILENT spreads and stops.
  (function()
    local SILENT = H.newSeedLadder("silent-attempt control")
    return H.seqStep({
      SILENT.watch(),
      SILENT.spread(1),
      H.call(function()
        local ok, err = pcall(SILENT.report().tick)
        H.assertEq(ok, false,
          "an attempt that took a phase and drew no seed FAILS the ladder")
        H.assertEq(tostring(err):find("drew no seed") ~= nil, true,
          "and it names the attempt rather than reporting a bare pass")
      end),
    })
  end)(),

  -- 4. The spread must not need to SEE its target phase: the harness samples
  -- $021e once per emulated frame while the counter's tick straddles that
  -- boundary, so a quarter of the phases are never what a sample returns.
  (function()
    local START = 1
    local blind = neverSampled(START, 30)
    local A = H.newSeedLadder("aliasing control",
                              { phaseSource = aliasedSampler(START) })
    local out = {}
    return H.seqStep({
      H.call(function()
        H.assertEq(blind ~= nil, true,
          "the aliased sampler really does hide a phase from the harness")
        H.log("aliasing control: phase " .. tostring(blind) ..
          " is never what a sample returns")
      end),
      A.watch(),
      A.spread(1),
      drive(function() return A.spread(2, { forcePhase = blind }) end, out,
            400, "aliasing control: spread onto a phase never sampled"),
      H.call(function()
        H.assertEq(out.err, nil,
          "the spread RELEASES on a target the sampler never shows, rather "
          .. "than reporting a stopped counter: " .. tostring(out.err))
        H.assertEq(out.frames >= 25 and out.frames <= H.SEED_PERIOD + 5, true,
          string.format("after most of a cycle of held frames, and inside one "
            .. "full cycle (%d frames)", out.frames))
      end),
    })
  end)(),

  -- 5. ...and a counter that really is stopped still fails.  This is the half
  -- that must not become "wait a bit and hope": a ladder that cannot spread
  -- has to say so rather than run a second attempt on the first one's seed.
  (function()
    local S = H.newSeedLadder("stopped counter control",
                              { phaseSource = function() return 30 end })
    local out = {}
    return H.seqStep({
      S.watch(),
      S.spread(1),
      drive(function() return S.spread(2, { forcePhase = 10 }) end, out,
            400, "stopped counter control: spread on a counter that never moves"),
      H.call(function()
        H.assertEq(out.err ~= nil, true,
          "a spread on a counter that never moves FAILS rather than releasing")
        H.assertEq(tostring(out.err):find("has not moved at all") ~= nil, true,
          "and it reports the stopped counter, with where to put the spread "
          .. "instead: " .. tostring(out.err))
      end),
    })
  end)(),
})
