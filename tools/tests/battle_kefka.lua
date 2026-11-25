-- @suite savestate=kefka_entry slow
-- battle_kefka.lua -- the generated-savestate test for the Battle for
-- Narshe's KEFKA, fought for real from kefka_entry.mss (party 1 =
-- TERRA+EDGAR+CELES at (19,36), KEFKA one tile below; gen_narshe_battle
-- generates it, and suite.sh adds this test when the fixture exists and
-- reports `skip` when it does not).
--
-- What it asserts:
--   1. battle 57 seeds formation 505: KEFKA_NARSHE $014A alone, gauge
--      6/6 and his class row straight off Ot6ShieldTbl (H.speciesClassRow:
--      the authored row rather than the formula; #566: two of the six
--      classes, the children of v0.50's slash|pierce $03, and one of them a
--      class the party's own hands hold).
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
--   5. (wt/v051-tg-wob2, bosses-wob.md block 10) his telegraph, under the boss contract, played first from the same
--      entry as a mechanism test (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written
--      out: the gauge, the row's classes for the breaking Fight, and HP held).  His script (ai_script.asm
--      AIScript::_330) now arms a fuse on his clock (the monster timer at 40) on a turn that is vanilla's opening
--      Battle; "Frost creeps!" (battle dialogue $9B) and a glow announce it on his next turn, and Ice on the
--      whole squad (attack $01, command $02) follows on the turn after.  A break while it is lit cancels it
--      (Ot6FuseTbl's row $014A): switch 0 goes and his clock restarts.
--        unbroken  the party Defends; the line shows once his clock has run; the lit-fuse mark stands before his
--                  shield emblem; Ice on the squad is dispatched on his next turn, a glow between; the mark goes.
--        broken    one member's aimed Fight is confirmed once the mark is up and breaks him: the cancel fires, the
--                  mark goes with the hit, switch 0 is clear and the clock reads 0, no Ice on his first turns
--                  back, and the line returns only once his clock has climbed to 40 again; the cast follows.
--        outside   a break before his clock has run: nothing is cancelled and the cells stand, two Fights in the
--                  window wind nothing, and the fuse then lights and fires as in the first case.
--      Then the entry is restored and the real fight below is played: the cases are staged, the fight is not.
--      Mutants (build/attempts/wt/v051-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break
--      during the fuse cancels it"; kefka_no_trigger (his row keeps every bit and restarts no clock:
--      Ot6FuseTbl+133=FF, +135=00 on the merged table; +93/+95 before) at "monster switch 0 is clear after the cancel".
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
--   tool    AutoCrossbow, from the ROM's data: power 125, ignores defence,
--           4 MP (Ot6AbilityCostTbl).  Under four classes $AA was OT6_PIERCE
--           and pierce one of KEFKA's shield classes; under six (#566) it is
--           OT6_RANGED (Ot6WeapClassTbl) and keys him only if his row holds
--           that -- the chips this suite asserts (3) are counted on the
--           gauge, whatever lands them.  The Bio Blaster ($A4) the old fighter's cursor named
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

-- the activation: face him once (a held DOWN that cannot step), release, then edge-A only, because a held
-- direction starves CheckNPCs
local function engage()
  return H.seqStep({
    H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
    H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }, "clean A into KEFKA -> battle 57"),
  })
end

-- the telegraph's cases (5. above): the suite's declared writers, through which M.fuseCases stages the gauge, the
-- row's classes and held HP, and nothing else
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local CLOCK = 2 * 40            -- if_monster_timer 40 reads half the timer word
local FUSE = {
  tag = "kefka", species = KEFKA, write = WRITE,
  line = 0x9B, move = { cmd = 0x02, atk = 0x01 }, turns = 1, glows = 1,
  arm = "idle",
  -- (wt/v051-tg-wob1's review) Ice is queued on the whole squad, and a fifth case: CELES's Runic, confirmed after
  -- the line, takes the announced cast
  allTargets = true,
  runic = { who = 0x06 },
  bossHp = nil,                 -- his own maximum, read at the open
  partway = function(W)
    local c = W.cells()
    return c ~= nil and c.timer >= 20 and c.timer < CLOCK - 20 and c.mvar & 0x01 == 0
  end,
  earned = function(C, W)
    local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
    H.assertEq(post.mvar & 0x01, 0, "kefka: monster switch 0 is clear after the cancel")
    H.assertEq(pre.timer >= CLOCK and post.timer <= 1, true, string.format("kefka: his clock was restarted by the "
      .. "cancel (the monster's timer read %d at the break and %d after it)", pre.timer, post.timer))
    H.assertEq(l2.cells.timer >= CLOCK, true, string.format("kefka: the line returned only once his clock had "
      .. "climbed to 40 again (timer %d at the second line)", l2.cells.timer))
  end,
}

-- The cap: back to the 120,000 it was before the telegraph's cases: the whole run, cases (the Runic case included)
-- and the real fight, ended at f24,380 on the merged ROM before the Runic case, about 8,000 more with it
-- (wt/v051-tg-wob1), well inside the fight's own budget.
H.run({ maxFrames = 120000 }, {
  H.loadState(ENTRY),
  H.waitFrames(30),
  engage(),
  H.waitUntil(function() return H.battleActive() end, 3000, "fight up (the telegraph's cases)", 10),
  H.call(function()
    local s = findKefka()
    H.assertEq(s >= 0, true, "KEFKA_NARSHE $014A on the field (formation 505)")
    FUSE.bossHp = H.readWord(0x3C1C + 8 + 2 * s)
    H.log(string.format("[kefka] the telegraph's cases: Kefka in slot %d, HP %d", s, FUSE.bossHp))
  end),
  H.fuseCases(FUSE),
  H.logStep("[kefka] PASS: the telegraph's announce, schedule, cancel and clock earned again; the real fight next"),

  H.loadState(ENTRY),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 22, "booted on map 22")
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "at (19,36), KEFKA's entry point")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 (TERRA+EDGAR+CELES) active")
  end),
  engage(),
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
            local row = H.speciesClassRow(KEFKA)
            H.assertEq(H.readByte(WKC(ks)), row, "class row: the ROM's (Ot6ShieldTbl $014A)")
            -- what the v0.50 row $03 gave this fight and the six-class row must still: two classes, and a
            -- key in the hands that meet him (TERRA's, EDGAR's or CELES's weapon; EDGAR's AutoCrossbow)
            local bits, held = 0, 0
            for b = 0, 5 do if row & (1 << b) ~= 0 then bits = bits + 1 end end
            for e = 0, 3 do
              local ch = H.readByte(0x3ED8 + e * 2)
              if ch < 16 then
                held = held | H.weaponClass(H.readByte(0x1600 + 37 * ch + 0x1F))
                local l = H.readByte(0x1600 + 37 * ch + 0x20)
                if H.isWeapon(l) then held = held | H.weaponClass(l) end
              end
            end
            held = held | H.weaponClass(H.AUTOCROSSBOW)
            H.log(string.format("[kefka] class row $%02X (%d classes); the party's hands and the AutoCrossbow hold $%02X",
              row, bits, held))
            H.assertEq(bits, 2, "KEFKA's row holds two weapon classes (v0.50's slash|pierce, split)")
            H.assertEq(row & held ~= 0, true, "and the party that meets him holds one of them")
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
