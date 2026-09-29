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
--   4. the scripted win branch runs, on real damage, on the FIRST attempt.
--      The fight is played to its own end (if_b_switch $40 -> _ccbcb1): the
--      party is not warped to the {25,5} lose-path save point and the win
--      scene runs.
--
-- The fight is the one both generators play (gen_narshe_battle,
-- gen_kefka_won): the library's fight driver with FIGHT below
-- (H.newFightDriver; one definition of every line, the same one the rest of
-- the route fights with).  #257 moved it there from a private fighter that
-- had no heal line, dropped the boost when its Tool fell back to Fight, named
-- whatever Tool its cursor sat on (the Bio Blaster, $A4) and won only through
-- a three-attempt reload ladder.  There is no ladder now: a wipe is a wipe.
-- It ends the run through the canary (class=wipe) and this suite, which
-- runs one attempt, is red.  The lab behind FIGHT and its first-attempt
-- rate is build/attempts/wt/kefka-lab/ (#257).

local H = dofile("tools/tests/lib/ot6.lua")
local ENTRY = "build/states/kefka_entry.mss.lua"

local KEFKA = 0x014A

-- The KEFKA fighter (#257), verbatim in battle_kefka, gen_narshe_battle and
-- gen_kefka_won.  Each lever was measured in build/attempts/wt/kefka-lab/:
--   runic   CELES holds Runic.  KEFKA's script is Fight plus spells, and a
--           spell that lands unabsorbed can take a member in one action:
--           every attributed [death] in the lab was Ice 2 (atk $06) or Drain
--           ($04) on one member, from 282-349 HP.
--   cure    false.  Runic absorbs the party's own casts too: with it up,
--           TERRA's Cure never landed ("restores ?" on every cast, her HP
--           falling while her MP paid).  The heal line is the bag.
--   healer  TERRA (0) takes the one care turn a round, with Potions (the
--           driver's own choice in battle), so CELES's turn stays Runic and
--           EDGAR, the harder hitter, keeps swinging.  The top-up fraction is
--           the driver's healPercent; 85 bought no margin over 70 and spent
--           2-7 Potions a fight.
--   tool    AutoCrossbow, from the ROM's data: $AA is OT6_PIERCE
--           (Ot6WeapClassTbl), power 125, ignores defence, 4 MP
--           (Ot6AbilityCostTbl), and pierce is one of KEFKA's shield classes
--           (row $03).  The Bio Blaster ($A4) the old fighter's cursor named
--           resolves as spell $7D (ThrowToolsItemTbl): power 20 poison, 8 MP.
--           The driver names the tool by id, and the boost it cannot pay for
--           stays on the Fight it falls back to.
--   boost   banked to 2 and spent, up to 3; a member inside one priced round
--           of death spends every pip first (the driver's spend rule).
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
  cure = false, runic = true, healer = 0, healPercent = 70,
  tool = H.AUTOCROSSBOW }

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end

local BCHP, BCMAXHP = 0x3bf4, 0x3c1c
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

local chippedTwice, winSceneObserved = false, false

H.run({ maxFrames = 120000 }, {
  H.loadState(ENTRY),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 22, "booted on map 22")
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "at (19,36), KEFKA's entry point")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 (TERRA+EDGAR+CELES) active")
  end),
  -- activation: face him once (a held DOWN that cannot step), release,
  -- then edge-A only, because a held direction starves CheckNPCs
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "fight up", 10),
  -- Played to the scripted verdict: the generators' discriminator (both
  -- endings run events, so the save-point warp is the tell).  A wipe never
  -- gets here: the canary ends the run with class=wipe.
  (function()
    local F = H.newFightDriver("kefka", FIGHT)
    local battN, ks, seedChecked, postN, evN = 0, -1, false, 0, 0
    local lastSh, lastRvc = 6, 0
    return H.driveUntil(function()
      if battN > 0 or H.battleLoadStarted() then return false end
      H.assertEq(H.fieldX() == 25 and H.fieldY() == 5, false,
        "NOT at the {25,5} save point -- battle 57's lose path did not run")
      postN = postN + 1
      evN = (H.eventRunning() or H.dialogWaiting()) and evN + 1 or evN
      if postN >= 600 and evN >= 60 then
        winSceneObserved = true
        return true
      end
      return false
    end, 90000, {
      H.call(function()
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN >= 3 then
          postN, evN = 0, 0
          if battN == 3 then
            H.log(string.format("[kefka] battle up f%d party [%s]", H.frame,
              partyLine()))
          end
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
          if ks >= 0 then
            local sh, rvc = H.readByte(SH(ks)), H.readByte(RVC(ks))
            if sh ~= lastSh or rvc ~= lastRvc then
              H.log(string.format("[chip] f%d gauge %d->%d revC $%02X->$%02X hp=%d party [%s]",
                H.frame, lastSh, sh, lastRvc, rvc, monHp(ks), partyLine()))
              lastSh, lastRvc = sh, rvc
            end
            if not chippedTwice and sh <= 4 and rvc ~= 0 then
              chippedTwice = true
              H.log(string.format("[kefka] two class chips landed (gauge %d, " ..
                "revC $%02X) at f%d", sh, rvc, H.frame))
            end
          end
          F.frame()
          return
        end
        F.idle()
        if H.dialogWaiting() then
          H.setPad(H.frame % 8 < 4 and { "a" } or {})
          return
        end
        H.setPad({})
      end),
    }, "the real Kefka fight, one attempt")
  end)(),

  H.call(function()
    H.assertEq(chippedTwice, true,
      "two real class chips landed and revealed before the fight ended")
    H.assertEq(H.fieldX() == 25 and H.fieldY() == 5, false,
      "NOT at the {25,5} save point -- the lose path did not run")
    H.assertEq(winSceneObserved, true,
      "the authored win scene owned the stage for a sustained interval " ..
      "(_ccbcb1), even if it completed before this verdict ran")
    H.log(string.format("[verdict] win at f%d on the first attempt", H.frame))
  end),
})
