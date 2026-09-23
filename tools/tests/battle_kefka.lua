-- @suite savestate=kefka_entry
-- battle_kefka.lua -- the generated-savestate test for the Battle for
-- Narshe's KEFKA, fought for real from kefka_entry.mss (party 1 =
-- TERRA+EDGAR+CELES at (19,36), KEFKA one tile below; gen_narshe_battle
-- generates it, and suite.sh adds this test when the fixture exists and
-- reports `skip` when it does not).
--
-- What it asserts:
--   1. battle 57 seeds formation 505: KEFKA_NARSHE $014A alone, gauge
--      6/6 and class row $03 = OT6_SLASH|OT6_PIERCE straight off
--      Ot6ShieldTbl (ot6.asm), which is the authored row rather than the
--      formula.
--   2. the element add is live.  His weak byte reads exactly $09 =
--      fire|poison.  Vanilla KEFKA_NARSHE has no weakness, so the whole
--      byte comes from Ot6ElemAddTbl's row.
--   3. class shields chip under real input.  The party's own weapon
--      swings must remove two gauge points and reveal the class before
--      the fight ends.
--   4. the scripted win branch runs, on real damage.  The fight is played
--      to its own end (if_b_switch $40 -> _ccbcb1): the party is not
--      warped to the {25,5} lose-path save point and the win scene runs.
--
-- The fight is driven by gen_kefka_won's input-driven fighter (the one
-- gen_narshe_battle also carries), the code that beats this battle to
-- generate kefka_won: one button per 30-frame pulse once the menu flag
-- holds, a per-turn sequence built live from the actor's id and banked BP
-- (boost to 2-3 and dump, priced through H.boostPlan; EDGAR's AutoCrossbow
-- at tier 2+ when his pool can pay it; CELES's Runic at tier 3+, which
-- absorbs KEFKA's Ice 2; Fight otherwise), and a stall-recovery tail (A, A,
-- B, rebuild).  KEFKA runs on real damage until his own script ends the
-- fight.  Losses are handled the way the generator handles them: the entry
-- point is captured once at boot (a savestate blob in memory, with no
-- writes), a wipe is read on every frame and ends the attempt at once, and
-- the next attempt reloads the entry point and escalates the policy tier,
-- for three attempts total.  A win on attempt 2 or 3 is a loss on the
-- record (the [kefka] ATTEMPT lines), not a hidden one.

local H = dofile("tools/tests/lib/ot6.lua")
local ENTRY = "build/states/kefka_entry.mss.lua"

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

-- gen_kefka_won's per-turn sequence, verbatim (party 1 carries EDGAR id 4
-- and CELES id 6; TERRA and anyone else Fight).  #230: pressing R is a claim
-- the caster can pay for what the turn names, so the boost goes through
-- H.boostPlan, and a Tools row the pool cannot pay even unboosted falls back
-- to Fight -- EDGAR opens this fixture with a few MP, and an unpriced tier-2
-- AutoCrossbow is refused at the confirm (Ot6KitConfirmMP), which is a stall.
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  local costed = nil
  if id == 4 and tier >= 2 then
    costed = H.namedTool(slot)
    if costed == nil then tier = 0 end   -- no tool in the bag: Fight
  end
  local ok
  boost, ok = H.boostPlan({ slot = slot, id = costed, want = boost,
                            tag = "kefka" })
  if not ok then tier = 0 end          -- cannot pay even unboosted: Fight
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

-- gen_kefka_won's [death] lines (newFightDriver's shape), so the pips a
-- member held when they fell are on the record for tools/audit_boost.py.
local function newDeathWatch(tag)
  local W = {}
  function W.reset()
    W.tick, W.opened, W.hp, W.said = 0, false, {}, {}
  end
  W.reset()
  function W.frame()
    if not H.battleLoadStarted() then W.reset(); return end
    if not W.opened and H.monstersPresent() == 0 then return end
    W.tick = W.tick + 1
    local pbp = {}
    for p = 0, 3 do pbp[#pbp + 1] = tostring(H.readByte(0x3E9C + p * 2)) end
    local party_bp = table.concat(pbp, ",")
    if not W.opened then
      W.opened = true
      local hp = {}
      for e = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + e * 2)) end
      H.log(string.format("[%s] battle f+%d partyhp=%s party_bp=%s monsters=%d",
        tag, W.tick, table.concat(hp, ","), party_bp, H.monstersPresent()))
    end
    for e = 0, 3 do
      local hp, maxhp = H.readWord(0x3BF4 + e * 2), H.readWord(0x3C1C + e * 2)
      local last = W.hp[e]
      if last ~= nil and last ~= 0xFFFF and last > 0 and hp == 0 and maxhp > 0
         and not W.said[e] then
        W.said[e] = true
        local bp = H.readByte(0x3E9C + e * 2)
        H.log(string.format("[%s] [death] f+%d entity %d char %d from %d/%d by "
          .. "nobody (no monster action attributed) bp=%d party_bp=%s%s", tag,
          W.tick, e, H.readByte(0x3ED8 + e * 2), last, maxhp, bp, party_bp,
          bp >= 3 and string.format(" -- died holding %d BP", bp) or ""))
      elseif hp > 0 and hp ~= 0xFFFF then
        W.said[e] = nil
      end
      W.hp[e] = hp
    end
  end
  return W
end

-- gen_kefka_won's fighter, trimmed to one battle: chips watched for
-- assertion 3, and the loss watched on EVERY frame of the drive (F.watch).
-- #163: a wipe zeroes every battle-HP word, which battleLoadStarted() reads
-- as "no battle", so a loss check behind that gate never sees the one state
-- it exists for; and the run canary counts a 300-frame battle-side wipe as a
-- game over.  This file's copy predated both: its wipe line was written, the
-- drive rode on waiting for the {25,5} save point, and the canary ended the
-- run at attempt 1 of 3 (2026-09-23, the regenerated kefka_entry: KEFKA's
-- Ice 2 at f3851 took TERRA 244 and CELES 242 to 0 and EDGAR 354 to 96, then
-- Drain took EDGAR; build/attempts/wt/regen-suites/).  Now a loss ends the
-- drive at once and the next attempt reloads, the way both generators do.
local function mkFighter(tier, tag)
  local F = { lost = nil, chippedTwice = false }
  local watch = newDeathWatch(tag)
  local up = false
  local wipeN = 0
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local phase = 0
  local lastSh, lastRvc = 6, 0
  function F.watch()
    watch.frame()
    wipeN = H.partyWipedInBattle() and wipeN + 1 or 0
    if (H.gameOverFired or 0) > 0 and not F.lost then
      F.lost = string.format("GAME OVER counted by the canary at f%d " ..
        "(tier %d) -- party [%s]", H.frame, tier, partyLine())
      H.log("[" .. tag .. "] " .. F.lost)
    end
    if wipeN >= 90 and not F.lost then
      F.lost = string.format("PARTY WIPED at f%d (tier %d) -- [%s]",
        H.frame, tier, partyLine())
      H.log("[" .. tag .. "] " .. F.lost)
    end
  end
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
      -- the wipe verdict is F.watch's, taken before this gate (#163)
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

-- ------------------------------------------------- the attempt sweep --
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
      H.call(function()
        H.checkReq(ldReq, "kefka attempt " .. n)
        -- the restored snapshot restarts the experiment: the canary's
        -- count belongs to the lost attempt
        H.gameOverFired = 0
      end),
      H.waitFrames(60),
    }, {}),
    H.call(function()
      F, battN, ks, seedChecked, postN, evN = mkFighter(n, "kefka" .. n),
        0, -1, false, 0, 0
      lostWhy = nil
      H.gameOverFired = 0
    end),
    H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
    H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }, "clean A into KEFKA -> battle 57"),
    H.waitUntil(function() return H.battleActive() end, 3000, "fight up", 10),
    -- play it to the scripted verdict (the generators' discriminator:
    -- both endings run events, so the save-point warp is the tell), or to a
    -- loss, which ends the drive at once: reloading beats riding the fail
    -- path into the canary
    H.driveUntil(function()
      if F.lost then
        lostWhy = F.lost
        return true
      end
      if battN > 0 or H.battleLoadStarted() then return false end
      if H.fieldX() == 25 and H.fieldY() == 5 then
        lostWhy = string.format(
          "battle 57 LOST at f%d (tier %d): the lose path parked the " ..
          "party at the {25,5} save point", H.frame, n)
        return true
      end
      postN = postN + 1
      evN = (H.eventRunning() or H.dialogWaiting()) and evN + 1 or evN
      if postN >= 600 and evN >= 60 then
        H.vars.winSceneObserved = true
        return true
      end
      return false
    end, 90000, {
      H.call(function()
        F.watch()                           -- every frame, outside the gate
        if F.lost then H.setPad({}); return end
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

-- allowGameOver: the sweep deliberately survives a lost battle 57, as both
-- generators' do (#163); F.watch reads H.gameOverFired as a loss and the
-- next attempt reloads the entry point.  The verdict below still requires
-- the win.
H.run({ maxFrames = 300000, allowGameOver = true }, {
  H.loadState(ENTRY),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 22, "booted on map 22")
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "at (19,36), KEFKA's entry point")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 (TERRA+EDGAR+CELES) active")
  end),
  -- capture the entry point once: the retry sweep's rewind point (this
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

  H.call(function()
    H.assertEq(won, true,
      "KEFKA beaten within 3 attempts (real damage, real menus)")
    H.assertEq(H.vars.chippedTwice, true,
      "two real class chips landed and revealed before the fight ended")
    local atSave = H.fieldX() == 25 and H.fieldY() == 5
    H.assertEq(atSave, false,
      "NOT at the {25,5} save point -- the lose path did not run")
    H.assertEq(H.vars.winSceneObserved, true,
      "the authored win scene owned the stage for a sustained interval " ..
      "(_ccbcb1), even if it completed before this verdict ran")
    H.log(string.format("[verdict] win at f%d", H.frame))
  end),
})
