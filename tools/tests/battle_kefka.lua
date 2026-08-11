-- @suite frontier=kefka_doorstep
-- battle_kefka.lua -- the generated-savestate test for v0.3's stop-line boss: the
-- Battle for Narshe's KEFKA, fought for REAL from kefka_doorstep.mss
-- (party 1 = TERRA+EDGAR+CELES at (19,36), KEFKA one tile below --
-- gen_narshe_battle generates it; suite.sh adds this test when the fixture
-- exists and reports `skip` when it does not, the battle_vargas pattern).
--
-- What it asserts, and why each line is the one that matters:
--   1. battle 57 seeds formation 505: KEFKA_NARSHE $014A alone, gauge
--      6/6 and class row $03 = OT6_SLASH|OT6_PIERCE straight off
--      Ot6ShieldTbl (ot6.asm) -- the authored row, not the formula.
--   2. THE ELEMENT ADD IS LIVE.  His weak byte reads EXACTLY $09 =
--      fire|poison.  Vanilla KEFKA_NARSHE has NO weakness, so the whole
--      byte is Ot6ElemAddTbl's row -- this is the assertion that fails
--      if that row is dropped (battle_vargas's poison|holy $28, one boss
--      later).
--   3. CLASS SHIELDS CHIP UNDER REAL INPUT.  The party's own weapon
--      swings must remove two gauge points and reveal the class before
--      the fight ends.  Axis-by-axis coverage belongs to battle_class;
--      tying this story test to incidental party equipment and ATB order
--      made it brittle.
--   4. THE SCRIPTED WIN TAKES IT, on real damage.  The fight is PLAYED
--      to its own end (if_b_switch $40 -> _ccbcb1): the party is NOT
--      warped to the {25,5} lose-path save point and the win scene owns
--      the stage.
--
-- Issue #75 conversion.  Three write idioms are gone:
--   * party HP := max + ATB := $1000 every frame ("keep the rotation
--     moving") -- replaced by gen_narshe_battle's input-driven fighter, the
--     machine that beats this exact battle to generate the fixture: one
--     button per 30-frame pulse once the menu flag holds, a per-turn
--     sequence built live from the actor's id and banked BP (boost to
--     2-3 and dump; EDGAR's AutoCrossbow at tier 2+; CELES's Runic at
--     tier 3+ -- it eats KEFKA's Ice 2; Fight otherwise), and a
--     stall-recovery tail (A, A, B, rebuild).
--   * KEFKA MHP := 1 after two chips ("the vargas clamp idiom") -- the
--     fight now runs on real damage until his own script ends it.
--   * losses are handled the way the generator handles them: the
--     entry point is captured ONCE at boot (a savestate blob in memory,
--     zero writes) and a lost attempt reloads it and escalates the
--     policy tier, three attempts total -- the same ladder that generated
--     the fixture, so a fixture this test can boot is a fixture this
--     ladder can beat.
--
-- FIXTURE VINTAGE NOTE (2026-08-10): kefka_doorstep.mss is the July 30
-- generation -- stamp-fresh against current sources, but generated before
-- the chain's own input-driven conversion caught up to this tier.  The
-- input-driven regeneration replaces the bytes, not this test.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/kefka_doorstep.mss.lua"

local KEFKA = 0x014A

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local BCHID, BCHP, BCMAXHP = 0x3ed8, 0x3bf4, 0x3c1c
local MENU, ACTOR = 0x7bca, 0x62ca
local BP = 0x3e9c
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function findKefka()
  for s = 0, 5 do
    if monPresent(s) and monSpecies(s) == KEFKA then return s end
  end
  return -1
end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end

-- gen_narshe_battle's per-turn sequence, verbatim (party 1 carries EDGAR
-- id 4 and CELES id 6; TERRA and anyone else Fight)
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  local function push(...)
    for _, b in ipairs({ ... }) do seq[#seq + 1] = b end
    return seq
  end
  if id == 4 and tier >= 2 then return push("down", "a", "a", "a") end
  if id == 6 and tier >= 3 then return push("down", "a", "a") end
  return push("a", "a")
end

-- gen_narshe_battle's fighter, trimmed to one battle: chips watched for
-- assertion 3, wipe watched for the retry verdict
local function mkFighter(tier, tag)
  local F = { lost = nil, chippedTwice = false }
  local up = false
  local wipedN = 0
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local phase = 0
  local lastSh, lastRvc = 6, 0
  function F.frame(battN, ks)
    phase = (phase + 1) % 8
    if battN == 3 then
      up = true
      H.log(string.format("[%s] battle up f%d party [%s]", tag, H.frame,
        partyLine()))
    end
    if up and ks >= 0 then
      local sh, rvc = H.readByte(SH(ks)), H.readByte(RVC(ks))
      if sh ~= lastSh or rvc ~= lastRvc then
        H.log(string.format("[chip] f%d gauge %d->%d revC $%02X->$%02X hp=%d",
          H.frame, lastSh, sh, lastRvc, rvc, monHp(ks)))
        lastSh, lastRvc = sh, rvc
      end
      if not F.chippedTwice and sh <= 4 and rvc ~= 0 then
        F.chippedTwice = true
        H.log(string.format(
          "[%s] two class chips landed (gauge %d, revC $%02X) at f%d -- " ..
          "the fight plays on, on real damage", tag, sh, rvc, H.frame))
      end
      -- wipe watch: every fielded entity at 0 HP, 90 straight frames
      local wiped, any = true, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) > 0 then wiped = false end
        end
      end
      wipedN = (any and wiped) and wipedN + 1 or 0
      if wipedN >= 90 and not F.lost then
        F.lost = string.format("PARTY WIPED at f%d (tier %d) -- [%s]",
          H.frame, tier, partyLine())
        H.log("[" .. tag .. "] " .. F.lost)
      end
    end
    if not up or H.readByte(MENU) == 0 then
      mStreak, mSeq = 0, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mStreak = mStreak + 1
    if mStreak < 4 then H.setPad({}); return end
    if mSeq == nil then
      local slot = H.readByte(ACTOR) & 3
      local id = H.readByte(BCHID + slot * 2)
      mSeq, mIdx, mTick, mStall = seqFor(id, tier, slot), 1, 0, 0
      H.log(string.format("[%s] cast f%d slot=%d char=%d bp=%d seq=%s",
        tag, H.frame, slot, id, H.readByte(BP + slot * 2),
        table.concat(mSeq, ",")))
    end
    mTick = mTick + 1
    local ph = mTick % 30
    local btn
    if mIdx <= #mSeq then
      btn = mSeq[mIdx]
    elseif mStall < 2 then
      btn = "a"                 -- a prompt the sequence did not know
    elseif mStall < 4 then
      btn = "b"                 -- back out (an MP refusal, a dead end)
    else
      mSeq = nil                -- rebuild from wherever the cursor is
      H.setPad({})
      return
    end
    if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
    if ph == 29 then
      if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
    end
  end
  return F
end

-- ------------------------------------------------- the attempt ladder --
local doorBlob, won, lostWhy = nil, false, nil

local function attempt(n)
  local F, battN, ks, seedChecked = nil, 0, -1, false
  local postN, evN = 0, 0
  local ldReq
  return H.cond(function() return not won end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[kefka] ATTEMPT %d -- reloading the entry point " ..
          "after a loss (%s)", n, tostring(lostWhy))
      end),
      H.call(function() ldReq = H.requestLoadState(doorBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "kefka attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function()
      F, battN, ks, seedChecked, postN, evN = mkFighter(n, "kefka" .. n),
        0, -1, false, 0, 0
      lostWhy = nil
    end),
    -- activation: face down once, then CLEAN edge-A (a held direction
    -- starves CheckNPCs -- measured, probe_kefka_npc)
    H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
    H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }, "clean A into KEFKA -> battle 57"),
    H.waitUntil(function() return H.battleActive() end, 3000, "fight up", 10),
    -- play it to the scripted verdict (gen_narshe_battle's discriminator:
    -- both endings run events, so the save-point warp is the tell)
    H.driveUntil(function()
      if battN > 0 or H.battleLoadStarted() then return false end
      if H.fieldX() == 25 and H.fieldY() == 5 then
        lostWhy = (F and F.lost) or string.format(
          "battle 57 LOST at f%d (tier %d): the lose path parked the " ..
          "party at the {25,5} save point", H.frame, n)
        return true
      end
      postN = postN + 1
      evN = (H.eventRunning() or H.dialogWaiting()) and evN + 1 or evN
      if postN >= 600 and evN >= 60 then
        if F and F.lost then lostWhy = F.lost end
        return true
      end
      return false
    end, 90000, {
      H.call(function()
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN >= 3 then
          postN, evN = 0, 0
          if ks < 0 then ks = findKefka() end
          if battN == 150 and not seedChecked then
            seedChecked = true
            H.assertEq(ks >= 0, true,
              "KEFKA_NARSHE $014A on the field (formation 505)")
            H.assertEq(H.readByte(SH(ks)), 6, "gauge seeds 6 (Ot6ShieldTbl $014A)")
            H.assertEq(H.readByte(SMX(ks)), 6, "gauge max 6")
            H.assertEq(H.readByte(WKC(ks)), 0x03,
              "class row $03 = OT6_SLASH|OT6_PIERCE")
            H.assertEq(H.readByte(WKE(ks)), 0x09,
              "weak byte EXACTLY $09 -- vanilla has none; the byte IS the ElemAdd row")
            H.assertEq(H.readByte(RVC(ks)), 0, "nothing revealed yet (classes)")
            H.assertEq(H.readByte(RVE(ks)), 0, "nothing revealed yet (elements)")
          end
          F.frame(battN, ks)
          return
        end
        if H.dialogWaiting() then
          H.setPad(H.frame % 8 < 4 and { "a" } or {})
          return
        end
        H.setPad({})
      end),
    }, "the real Kefka fight, attempt " .. n),
    H.call(function()
      if lostWhy == nil then
        won = true
        H.vars.chippedTwice = F.chippedTwice
        H.log(string.format("[kefka] attempt %d WON battle 57 at f%d",
          n, H.frame))
      end
    end),
  }, {})
end

H.run({ maxFrames = 300000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 22, "booted on map 22")
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "at (19,36), KEFKA's entry point")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 (TERRA+EDGAR+CELES) active")
  end),
  -- capture the entry point ONCE: the retry ladder's rewind point (this
  -- boot's own state; nothing is written to the game)
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "entry-point capture")
        doorBlob = req.blob
      end),
    }, {})
  end)(),

  attempt(1),
  attempt(2),
  attempt(3),

  -- the win verdict: chips actually happened, and the WIN branch ran
  H.call(function()
    H.assertEq(won, true,
      "KEFKA beaten within 3 attempts (real damage, real menus)")
    H.assertEq(H.vars.chippedTwice, true,
      "two real class chips landed and revealed before the fight ended")
    local atSave = H.fieldX() == 25 and H.fieldY() == 5
    H.assertEq(atSave, false,
      "NOT at the {25,5} save point -- the lose path did not run")
    H.assertEq(H.eventRunning() or H.dialogWaiting(), true,
      "the win scene owns the stage (_ccbcb1)")
    H.log(string.format("[verdict] win at f%d", H.frame))
  end),
})
