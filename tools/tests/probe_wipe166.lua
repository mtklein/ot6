-- @manual
-- probe_wipe166.lua -- #166: measure the wipe predicate on the two wipes
-- the old one was blind to, with real bytes.
--
--   A. a two-character party with a full-HP word in a seat nobody in the
--      party holds (falls_done: SABIN and CYAN after SHADOW left) -- a
--      Veldt random entered from the shore transit's own first leg, then
--      the pad released: a person who never presses a button.  Measured
--      on the first run: the 394/394 in seat 2 is not a stale word at all
--      but GAU, actor 11, the Veldt formation's hidden character AI
--      (InitParty seats him with the "target present" bit clear; the
--      engine's alive mask $3a74 reads $03 for the two real members), so
--      the seat mask is the actor byte AND the present bit.
--   B. a battle fought with $1850 marking MORE than four members (the
--      Narshe three-party descent: kefka_entry, seven marked, three
--      seated) -- A into KEFKA, then hands off the same way.
--
-- Every 600 frames, and on each edge, the line carries the engine's own
-- bytes -- the seats ($3ed8 actor : $3bf4 hp / $3c1c max), the $1850
-- head count, $3ebc, $3a74 -- beside the OLD predicate (the pre-#166
-- scan, copied verbatim below) and the new one, and the canary's counter.
-- allowGameOver, as every ladder runs, so the run outlives the count and
-- the second part can boot.
--
-- Read-only under docs/TESTING.md: pad presses and memory reads; whole
-- fixture boots.
local H = dofile("tools/tests/lib/ot6.lua")

local FALLS = "build/states/falls_done.mss.lua"
local KEFKA = "build/states/kefka_entry.mss.lua"
local function mapIdx() return H.readWord(0x1f64) & 0x3FF end

-- ================== verbatim: M.partyWipedInBattle before #166 ============
local function oldPredicate()
  local sane, alive = 0, 0
  for e = 0, 3 do
    local mx = H.readWord(0x3c1c + e * 2)
    if mx > 0 and mx < 10000 then
      sane = sane + 1
      if H.readWord(0x3bf4 + e * 2) > 0 then alive = alive + 1 end
    end
  end
  if sane == 0 then return false end
  local want = 0
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then want = want + 1 end
  end
  return want >= 1 and want <= 4 and sane >= math.min(want, 4) and alive == 0
end
-- ===========================================================================

local function seats()
  local p = {}
  for e = 0, 3 do
    local a = H.readByte(0x3ed8 + e * 2)
    local present = (H.readByte(0x3aa0 + e * 2) & 1) == 1
    p[#p + 1] = string.format("%s%s:%d/%d", a == 0xFF and "-" or ("a" .. a),
      (a ~= 0xFF and not present) and "(hidden)" or "",
      H.readWord(0x3bf4 + e * 2), H.readWord(0x3c1c + e * 2))
  end
  return table.concat(p, " ")
end
local function marked()
  local n = 0
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then n = n + 1 end
  end
  return n
end
local function status(tag)
  H.log(string.format("[wipe166] %s f%d seats=[%s] $1850 marks %d $3ebc=%02X " ..
    "$3a74=%02X old=%s new=%s gameOverFired=%d padFrozen=%s",
    tag, H.frame, seats(), marked(), H.readByte(0x3ebc), H.readByte(0x3a74),
    tostring(oldPredicate()), tostring(H.partyWipedInBattle()),
    H.gameOverFired or 0, tostring(H.padFrozen)))
end

-- the passive fight: log the edges, stop when the canary counts
local function passiveWipe(tag)
  local t, newAt, oldAt, flagAt, firedAt = 0, nil, nil, nil, nil
  return H.cond(function() return true end, {
    H.driveUntil(function()
      t = t + 1
      if newAt == nil and H.partyWipedInBattle() then
        newAt = H.frame
        status(tag .. ": first frame the NEW predicate reads wiped")
      end
      if oldAt == nil and oldPredicate() then
        oldAt = H.frame
        status(tag .. ": first frame the OLD predicate reads wiped")
      end
      if flagAt == nil and (H.readByte(0x3ebc) & 1) == 1 then
        flagAt = H.frame
        status(tag .. ": LoseBattle's $3ebc bit 0 set")
      end
      if (H.gameOverFired or 0) > 0 then
        firedAt = H.frame
        status(tag .. ": the canary counted")
        return true
      end
      return t > 90000
    end, 91000, {
      H.call(function()
        H.setPad({})                          -- a person who never presses
        if t % 600 == 0 then status(tag .. ": hands off") end
      end),
    }, tag .. ": the passive fight"),
    H.call(function()
      H.log(string.format("[wipe166] %s: newAt=%s oldAt=%s flagAt=%s (+%s after new) " ..
        "firedAt=%s (+%s after new)", tag, tostring(newAt), tostring(oldAt),
        tostring(flagAt), newAt and flagAt and tostring(flagAt - newAt) or "?",
        tostring(firedAt), newAt and firedAt and tostring(firedAt - newAt) or "?"))
      H.assertEq(firedAt ~= nil, true, tag .. ": the canary counted the wipe")
    end),
  })
end

H.run({ maxFrames = 400000, allowGameOver = true }, {
  -- ---- A. the stale-seat wipe -------------------------------------------
  H.loadState(FALLS),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 159, "boot on the shore, map 159")
    status("A: booted falls_done")
  end),
  H.navTo(8, 14, { maxFrames = 6000, playBattles = "tactical", arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world live before the crossing", 5),
  H.call(function() status("A: on the Veldt shore, walking into a random") end),
  H.worldNavTo(220, 115, { maxFrames = 30000,
    arrive = function() return H.battleLoadStarted() end }),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "A: the random is up", 30),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("[wipe166] A: formation %04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]))
    status("A: battle up, pad released")
  end),
  passiveWipe("A"),

  -- ---- B. seven marked, three seated -----------------------------------
  H.loadState(KEFKA),
  H.waitFrames(60),
  H.call(function()
    H.gameOverFired = 0                     -- part A's count, part A's fixture
    status("B: booted kefka_entry")
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "B: A into KEFKA -> battle 57"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "B: KEFKA up", 10),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("[wipe166] B: formation %04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]))
    status("B: battle up, pad released")
    H.assertEq(marked() > 4, true, "B: $1850 marks more than four members")
  end),
  passiveWipe("B"),
  H.logStep("probe_wipe166: done"),
})
