-- gen_fc_landing.lua -- the Floating Continent landing: checkpoint Q.
--
-- Cold-Continues the tracked `thamasa-done-v1` battery (boundary P: the
-- WoB stop line world (249,128) beside the Blackjack), does the prep a
-- person does at Thamasa (Potions/Fenix/Tonics, the bag arranged so the
-- combat items sit on top), boards, forms TERRA LOCKE EDGAR at the deck's
-- party select, fights the whole Imperial Air Force gauntlet (Sky Armor /
-- Spit Fire waves, Ultros IV + Chupon, the Air Force), lands on the
-- continent (394), walks to the landing SavePoint 394 (7,12) and saves --
-- the `fc-landing-v1` checkpoint, the seed at the gauntlet's far side.
-- The descent to the save alcove (358) and SHADOW are gen_fc_alcove's,
-- booted from this seed.
--
-- Reads and pad presses only; the gauntlet is fought for real -- a game
-- over is a loud failure (a lab), never a retry.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- Choice windows on these rides go through H.newChoice (lib/ot6_field.lua):
-- steered from the moment $056F reads nonzero ("count", min 1), on this
-- file's 24-frame pulse (a steer press on phase 0-2, the confirm on 12-14),
-- the landed row asserted when the window closes.
local function choicePress(ph, kind)
  if kind == "confirm" then return ph >= 12 and ph < 15 end
  return ph < 3
end


local ZMENUSTATE = 0x26
local POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY = 0xE9, 0xF0, 0xE8, 0xF2, 0xF5   -- item ids (the care kernel's)
local TINCTURE, REVIVIFY, TENT = 0xEB, 0xF1, 0xF7
local TERRA, LOCKE, SHADOW, EDGAR = 0x00, 0x01, 0x03, 0x04
local RAMUH, SHIVA = 0x00, 0x02
local function map() return H.mapId() & 0x3ff end
local function mapIs(m) return map() == m end
local function charPos(c) return function() return (H.readByte(0x1850 + c) >> 3) & 0x03 end end
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

-- the party select (the Blackjack's IAF launch) is the lib's M.newPartySelect
local PICK = { TERRA, LOCKE, EDGAR }

-- ---- the IAF / FC fight driver -----------------------------------------
-- The IAF trash (Sky Armor $043 pierce-class, Spit Fire $0E3 slash-class,
-- both bolt|WIND-weak with 2 authored pips; floating-continent-route.md
-- s3) is a DPS race the first cut lost with a poison tool and one Bolt
-- caster.  The keys P's roster holds: Bolt from TERRA (RAMUH) and LOCKE
-- (MADUIN) as party attack magic, LOCKE's dual blades (ThunderBlade
-- slash + Guardian pierce: one hand chips each machine), and EDGAR's
-- AutoCrossbow -- the driver's DEFAULT tool, four pierce hits that sweep
-- the Sky Armors and, later, the AirForce's pierce-class parts.  Bolt is
-- every FC boss's row too (Ultros IV, AirForce, Atma, Nerapa).
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
                healPercent = 50, magic = { [TERRA] = { spell = 2 }, [LOCKE] = { spell = 2 } },
                nuke = { 2 } }

-- ---- descent (probe_fc_descent -> probe_fc_alcove2) ----------------------
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end

-- The (70,29) "return?" Yes lands the party on the Blackjack deck with
-- SHADOW posed: wheel right+A, steer dialog $0527 to row 0 ("Find the
-- Floating Continent" -- with $00A0=1 the quick re-arrival, no IAF), the
-- party select again, then talk SHADOW into the party beside (10,16).
local seenBattles, lastActive = 0, false
local F = H.newFightDriver("IAF", FIGHT)
-- The Air Force (#201, docs/design/airforce.md): the gauntlet's last fight,
-- AirForce $113 slot 0 + Laser Gun $145 slot 2 + MissileBay $147 slot 4.
-- The Laser Gun dying while the bay stands arms the body's countdown
-- (Speck, then a Count a turn, then WaveCannon), and only the body's own
-- death ends it; the bay under 1536 HP fires Launcher.  FIGHT's default
-- targeting killed the gun and then spread the party across the bay and
-- the body, and at the regeneration's shift 0 the count ran out:
-- `wipe context ... formation 0113 FFFF 0145 0146 0147 FFFF; seats ...
-- a0:316/960 bp1 a1:528/1129 bp3 a4:0/1048 bp3`.  A person kills the gun
-- (the Atomic Ray), then the body the moment the countdown starts, and
-- lets the bay be.  The same driver options with that kill order passed
-- that exact fight (the rest of the route byte-identical) and all 10 runs
-- (9 distinct seeds) from the Ultros teaser.  That order was a mask this
-- file authored; the driver now plans it from the formation's own
-- scripts (#189, readParts): the gun's death sets battle switch 0.0,
-- which the body's script counts from, the body's death ends the fight,
-- the Speck is the body's own and the bay's death changes nothing --
-- kill order {2, 0}, the same driver on the same options.
-- #412: the Air Force's driver also spends TERRA's once-a-battle RAMUH
-- summon (Bolt Fist, every part, each bolt-weak)
local FAF_OPTS = {}
for k, v in pairs(FIGHT) do FAF_OPTS[k] = v end
FAF_OPTS.summon = { [TERRA] = {} }
local FAF = H.newFightDriver("IAF", FAF_OPTS)
local function airForceUp() return H.formationHas({ [0x0113] = true }) end

local function kitSteps(char, name, pairs_)
  local steps = {}
  for _, p in ipairs(pairs_) do
    local slot, item = p[1], p[2]
    local tag = string.format("%s FC kit slot %d", name, slot)
    steps[#steps + 1] = H.cond(
      function() return H.invSlotOf(item) ~= nil end,
      { H.equipLoadout(char, { { slot, item } }, { tag = tag, optional = true }) },
      { H.logStep(string.format("%s: $%02X not in this run's bag; keeping current gear", tag, item)) })
  end
  return steps
end

local u4Req = nil                         -- the ultros4_entry capture
local DECK = { S = H.newPartySelect(PICK), helmT = 0, formed = false, careD = nil }
-- The fights after the IAF waves (#404): Ultros IV ($168) and Chupon
-- ($12F), who steps into his fight (battle_ultros4), then the Floating
-- Continent's own pool (map 394), read from the ROM.  The deck kit's Relic
-- session lets the game's Optimum re-pick hands element-blind (it handed
-- LOCKE the Flame Sabre Chupon absorbs, the f77db439 chain), but the deck
-- kit runs in the between-wave window, whose timer runs while the menu is
-- closed: an absorb-aware deck kit (H.equipKit's opts.absorbs) re-armed
-- TERRA there and the next wave took LOCKE's session ("timeout after 900
-- frames driving toward LOCKE deck kit (relics): cursor on the menu row",
-- 3 of 3 attempts, build/attempts/wt/v026-route2/e404/).  So the re-arm
-- is one stop after the last wave, before the walk that arms Ultros IV:
-- H.absorbSafeArms, the strongest bag weapon by the ROM's power byte that
-- none of them absorbs, then asserted.
-- Ultros IV's fight-mates come from the formation table, not a list: every
-- species in any slot (present or held back for restore_monsters, which is
-- how Chupon steps in) of a formation that holds Ultros IV ($168).
local ULTROS4 = 0x0168
local function fcAhead()
  local out, seen = {}, {}
  local bm = H.sym("BattleMonsters") & 0x3FFFFF
  for id = 0, 575 do
    local rec = H.formationRecord(function(i) return H.readRomByte(bm + id * 15 + i) end)
    local has = false
    for _, sp in pairs(rec.species) do if sp == ULTROS4 then has = true end end
    if has then
      for _, sp in pairs(rec.species) do
        if not seen[sp] then seen[sp] = true; out[#out + 1] = sp end
      end
    end
  end
  H.assertEq(seen[ULTROS4] == true, true, "a formation holds Ultros IV ($168)")
  for _, r in ipairs(H.poolSpecies(H.fieldEncounterGroup(394))) do out[#out + 1] = r.species end
  return out
end

local function deckDrive(untilKit)
    local S = DECK.S
    local C = H.newChoice(0, { ready = "count", min = 1, press = choicePress,
      tag = "deck" })
    -- The story's own FC cutscene (Gestahl and Kefka on the continent)
    -- visits map 394 with no control long before the party lands there:
    -- the terminal is CONTROL on 394 after the chain's battles were seen.
    return H.driveUntil(function()
      if (H.gameOverFired or 0) > 0 then
        error(string.format("the IAF gauntlet was LOST (game over after %d battles) -- a lab, not a retry", seenBattles), 0)
      end
      -- phase 1 stops at the FIRST between-wave window: the deck right
      -- after the select has its menu disabled (measured: X did nothing
      -- for 1200 frames, no dialog up), and the first window the game
      -- opens the menu in is the gap after wave 1 -- where a person
      -- dresses the one who came off the bench bare
      if untilKit == true and DECK.formed and seenBattles >= 1 and H.hasControl() and mapIs(10)
         and not H.eventTimerLive() and not H.dialogWaiting() then
        return true
      end
      -- phase 2 stops at the Ultros teaser ($01F0): the arming walk to the
      -- deck's right edge is a real pathed walk (a raw hold-right from the
      -- helm was blocked at (14,6) for 92k frames in the regen's fc_landing)
      if untilKit == "ultros" and sw(0x01F0) == 1 and H.hasControl() and mapIs(10)
         and not H.dialogWaiting() and H.fieldX() ~= 22 then
        return true
      end
      return mapIs(394) and H.hasControl() and seenBattles >= 1
    end, 120000, {
      H.call(function()
        local active = H.battleActive()
        if active and not lastActive then
          seenBattles = seenBattles + 1
          H.log(string.format("  [IAF battle %d] f%d", seenBattles, H.frame))
        end
        lastActive = active
        if active or H.battleLoadStarted() then
          if airForceUp() then FAF.frame() else F.frame() end
          return
        end
        local ms = H.readByte(ZMENUSTATE)
        if ms >= 0x2c and ms <= 0x2f then
          if not DECK.formed and S.ready() and S.complete() then
            DECK.formed = true
            H.log("party select group: " .. S.group())
          end
          S.pulse(); return
        end
        if C.frame(H.frame % 24) then return end
        -- a live care stop owns the frame until it is done: with the menu
        -- open the field reports no control, so this check sits ABOVE the
        -- control gate (the first cut put it below and hung with the menu
        -- open for 109k frames, the wave timers paused, nothing pressed)
        if DECK.careD then
          if DECK.careD.done() then DECK.careD = nil else DECK.careD.frame(); return end
        end
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}); return end
        if H.hasControl() and (mapIs(6) or mapIs(10)) then
          -- between waves the field menu opens (the wave timers pause in
          -- menus): heal the way a person would before the next wave
          if seenBattles >= 1 and not H.eventTimerLive() then
            local hurt = false
            for _, c in ipairs(H.partyMembers()) do
              if H.charHp(c) < H.charMaxHp(c) * 0.7 then hurt = true end
            end
            if hurt then
              DECK.careD = H.newCareDriver({ threshold = 0.9, tag = "care between IAF waves" })
              DECK.careD.frame(); return
            end
          end
          DECK.helmT = DECK.helmT + 1
          -- after the "something curious approaches" teaser ($01F0) the
          -- party ARMS Ultros IV by walking to the deck's right edge
          -- (map 10 triggers (22,5-7)); before it, the helm (14,6) is the
          -- talk that launches everything
          local tx, ty = 14, 6
          if sw(0x01F0) == 1 then tx, ty = 22, 6 end
          if H.fieldX() == tx and H.fieldY() == ty then
            H.setPad(DECK.helmT % 16 < 4 and { "a" } or {})
          else
            local dx, dy = tx - H.fieldX(), ty - H.fieldY()
            local d = math.abs(dx) >= math.abs(dy)
              and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
            H.setPad(DECK.helmT % 4 < 2 and { [d] = true } or {})
          end
          return
        end
        H.setPad({})
      end),
    }, untilKit == true and "deck -> gate cutscene -> party select -> control on the deck"
       or untilKit == "ultros" and "deck -> helm -> the IAF waves -> the Ultros teaser"
       or "deck -> arm Ultros -> the rest of the chain -> the Floating Continent")
end

H.run({ maxFrames = 600000 }, flatten({
  -- ---- 0. cold Continue of P, contract, kits ------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the thamasa-done world stop line", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("thamasa-done-v1") end),
  -- ---- 0b. the prep a person does before the gauntlet ---------------------
  -- Attempts 10-11 opened the IAF with 9 Potions at bag row 43: the
  -- in-battle heal was a 43-row walk of the item list at one row per
  -- pulse, and two of three died while it walked.  So: Thamasa's item
  -- shop (POTION to 65 -- the combat heal; FENIX DOWN to ~level; TONIC 99),
  -- then the bag arranged so the combat items sit at slots 0-4, then back
  -- out to the world for the boarding walk (measured: probe_fc_prep.lua).
  (function() local W = H.newWalkFighter("held RIGHT onto (250,128)")
    return H.driveUntil(function() return not H.worldMode() end, 2000, {
      H.call(function()
        if W.frame() then return end
        H.setPad({ right = true })
      end),
    }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)") end)(),
  H.release(),
  H.waitUntil(function() return (mapIs(340) or mapIs(343)) and H.hasControl() end, 3000, "Thamasa map loaded (post-massacre Thamasa is 340; the door asserts the shop)", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "Thamasa fade-in", 10),
  H.waitFrames(30),
  H.crossDoor(26, 37, 347, 36, 44, "item shop door 343(26,37)->347(36,44)", { healer = TERRA }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400, "shop interior settled", 10),
  H.waitFrames(150),
  H.shopTalk(36, 39, "Thamasa item shop", { healer = TERRA }),
  -- POTION to 65 (#176): this is the WoB's last shop, and the band
  -- (~level x1.5, docs/design/level-curve.md) is what the bag should hold
  -- arriving at every fight through the escape -- 44 at the L29 the
  -- escape_start fixture holds.  The stretch's measured spend off the old
  -- target of 40: the IAF gauntlet 40 -> 24 (fc_landing.log "[prep] shop
  -- done: ... potion=40" against the fixture's 24), the alcove leg 36 -> 33
  -- and the escape 33 -> 31 (the fc-landing-v1 / fc-alcove-v1 payloads
  -- against their fixtures), 21 in all: 44 + 21 = 65.  Held for #179 (the
  -- bigger purchase moved the RNG under an IAF wave) until the segment
  -- runner (#178) retried such losses.
  H.buyItem(POTION, 1, function() return 65 - H.invCountOf(POTION) end, "POTION to 65"),
  H.buyItem(FENIX_DOWN, 6, function() return 25 - H.invCountOf(FENIX_DOWN) end, "FENIX DOWN to 25"),
  -- #231 (docs/design/supply.md): the last counter in the WoB.  REVIVIFY
  -- to 3; TINCTURE to 7, the MP band at L28 (~level / 4) for the walks
  -- between the continent's save points; TENT to 10 for those save points
  -- (394 (7,12) and 358 (8,10)), where a Tent restores the whole party's
  -- both pools for 1200 -- fc_landing stood on the first at TERRA 178/228,
  -- LOCKE 73/256, EDGAR 114/218 MP with ten of them unpitched.
  H.buyItem(REVIVIFY, 5, function() return 3 - H.invCountOf(REVIVIFY) end, "REVIVIFY to 3"),
  H.buyItem(TINCTURE, 2, function() return 7 - H.invCountOf(TINCTURE) end, "TINCTURE to 7"),
  H.buyItem(TENT, 7, function() return 10 - H.invCountOf(TENT) end, "TENT to 10"),
  -- #361: the continent's map 394 deals Apokryphos and Misfits in half its
  -- draws (battle_procboost's pool decode, build/attempts/wt/procboost-v024/
  -- summary.txt), and both cast Mute, which greys TERRA's and CELES's
  -- Magic until cured.  The bag came here with one Echo Screen and at most
  -- one Remedy, so a second Mute had no cure (that suite's K5: "the magic
  -- row greyed (status bytes 00 08)" for 26000 frames once the one Echo
  -- Screen had gone to SHADOW).  This counter sells no Echo Screen; its
  -- Remedy (row 3) carries Mute's STATUS2 bit (M.statusCure reads it off
  -- the ROM), and at 1000 gil against a six-figure purse a person carries
  -- one for each of the three legs (the gauntlet, the alcove, the escape)
  -- before the World of Ruin's first counter, plus two for a leg that
  -- meets more.
  H.buyItem(REMEDY, 3, function() return 5 - H.invCountOf(REMEDY) end, "REMEDY to 5"),
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.shopClose("Thamasa item shop"),
  H.call(function()
    H.log(string.format("[prep] shop done: tonic=%d potion=%d fenix=%d tincture=%d tent=%d remedy=%d echo=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN),
      H.invCountOf(TINCTURE), H.invCountOf(TENT), H.invCountOf(REMEDY),
      H.invCountOf(0xFB), H.gil(), H.frame))
    H.assertEq(H.invCountOf(POTION) >= 65, true, "Potions stocked to 65 for the gauntlet -- the L29 band plus the measured FC spend")
    H.assertEq(H.invCountOf(FENIX_DOWN) >= 25, true, "Fenix Downs stocked to 25")
    H.assertEq(H.invCountOf(TINCTURE) >= 7, true, "Tinctures stocked to 7 -- the L28 MP band (#231)")
    H.assertEq(H.invCountOf(TENT) >= 10, true, "Tents at 10 for the continent's save points (#231)")
    H.assertEq(H.invCountOf(REMEDY) >= 5, true, "Remedies at 5: a Mute on the continent has a cure (#361)")
  end),
  H.bagArrange({ POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top" }),
  H.call(function()
    H.assertEq(H.readByte(0x1869), POTION, "slot 0 is Potion: the combat heal is one press away")
    H.assertEq(H.readByte(0x186A), FENIX_DOWN, "slot 1 is Fenix Down")
  end),
  -- #412: RAMUH on TERRA.  The Air Force's every part is bolt-weak ($84),
  -- and TERRA came to it with no stone and no Bolt: her free turns were a
  -- Fight landing 83 a hit (airforce.md "TERRA wears no esper"), while
  -- RAMUH sat in the bag.  Worn, he gives her Bolt (folds to Bolt2/Bolt3
  -- under boost) and, once a battle, his Bolt Fist on every part.  A person
  -- puts the stone on her before the gauntlet; here, in town, where the
  -- menu has no wave timer running.
  H.equipEsper(charPos(TERRA), RAMUH, { tag = "RAMUH -> TERRA" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * TERRA + 0x1E), RAMUH, "TERRA wears RAMUH into the gauntlet")
  end),
  H.crossDoor(36, 45, 340, 26, 39, "item shop door 347(36,45)->340(26,39), return", { healer = TERRA }),
  H.navTo(23, 46, { maxFrames = 9000, playBattles = "tactical", items = true, healer = TERRA }),
  H.driveUntil(function() return H.worldMode() end, 2000, {
    H.call(function() H.setPad({ down = true }) end),
  }, "held DOWN off (23,46) -> the world map"),
  H.release(),
  H.waitUntil(function() return H.worldMode() and bright() >= 15 end, 900, "world fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[prep] back on the world at (%d,%d); ship (%d,%d)",
      H.worldX(), H.worldY(), H.readByte(0x1f62), H.readByte(0x1f63)))
  end),
  -- EDGAR is benched here, and the field Equip screen never shows a bench
  -- member, so he is dressed in the gauntlet's first between-wave window
  -- (step 1b below), the first place the game opens the menu for him.
  -- ---- 1. board, deck, party select ---------------------------------------
  H.call(function()
    H.log(string.format("party (%d,%d), airship (%d,%d)", H.worldX(), H.worldY(),
      H.readByte(0x1f62), H.readByte(0x1f63)))
  end),
  -- The Blackjack's tile is $1f62/$1f63, one step north of the stop line;
  -- the step lands the party ON it, still on the world map (measured,
  -- probe_p_ship.lua, deleted in 895b8e67; last version at 3b51556d).
  -- Boarding here is a TALK, not a walk: face WEST
  -- toward the parked ship (LEFT is blocked, so the press only turns) and
  -- tap A -- control drops, and the story-phase deck loads (map 10),
  -- whose flow plays the Sealed Gate cutscene (391), returns to the deck,
  -- and runs the 3-character party select for the IAF launch.  One state
  -- machine rides all of it: dialogs A-tapped, choice boxes answered YES
  -- (row 0: "Find the Floating Continent"), the select formed to PICK and
  -- confirmed, the helm trigger walked if the deck hands control back,
  -- and the IAF chain fought until the continent (394) loads.
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical", magic = FIGHT.magic,
      arrive = function()
        return H.worldX() == H.readByte(0x1f62) and H.worldY() == H.readByte(0x1f63)
      end }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldX() == H.readByte(0x1f62) and H.worldY() == H.readByte(0x1f63), true,
      "standing on the Blackjack's tile")
  end),
  H.pressButtons({ "left" }, 8), H.waitFrames(30),
  H.pressButtons({ "a" }, 8), H.waitFrames(30),
  H.waitUntil(function() return not H.worldMode() end, 600, "the deck scene starts", 5),
  deckDrive(true),
  -- ---- 1b. dress the three in the first between-wave window ---------------
  -- One Equip session and one Relic session per character (M.equipKit):
  -- the wave timer runs while the menu is closed, so round trips are what
  -- the window cannot afford.  Ladders list the strongest first; what
  -- EDGAR can wear is the game's call, read from his own list.  He came
  -- off the bench bare and fought wave 1 that way (the first cut of this
  -- seed fought all 13 naked).
  H.call(function()
    H.log(string.format("[deck kit] between-wave window at f%d after %d battle(s): dressing", H.frame, seenBattles))
  end),
  -- #406: the first window can open with a member down (TERRA, SHIVA's
  -- wearer, died in IAF battle 1 at 4 of 32 shifts on the driver branch's
  -- run, build/attempts/wt/v026-driver2/402/base2/base_s{19,22,34,36};
  -- also 402/ab/new_s{28,53}), and the Skills menu
  -- will not open for a dead member, so the stone cannot move.  A person
  -- raises them first: the field care (Fenix Down from the bag), with the
  -- menu open the wave timers paused.
  H.cond(function()
    for _, c in ipairs(H.partyMembers()) do
      if (H.charStatus1(c) & 0xC2) ~= 0 or H.charHp(c) == 0 then return true end
    end
    return false
  end, {
    H.fieldCare({ tag = "raise before the deck kit", threshold = 0.9 }),
    H.call(function()
      for _, c in ipairs(H.partyMembers()) do
        H.assertEq((H.charStatus1(c) & 0xC2) == 0 and H.charHp(c) > 0, true,
          string.format("char %d stands before the deck kit (status1 $%02X, HP %d)",
            c, H.charStatus1(c), H.charHp(c)))
      end
    end),
  }, {}),
  H.equipEsper(charPos(EDGAR), SHIVA, { tag = "SHIVA -> EDGAR" }),
  H.equipKit(EDGAR, { { 0, 0x0B }, { 0, 0x0A },
                      { 1, 0x5B }, { 1, 0x5A },
                      { 2, 0x76 }, { 2, 0x6B }, { 2, 0x69 },
                      { 3, 0x8F }, { 3, 0x84 },
                      { 4, 0xB3 }, { 5, 0xB1 } }, { tag = "EDGAR deck kit", ladder = true }),
  -- Relics: TERRA takes $B7 (Barrier Ring) + $B1 (Star Pendant), LOCKE $B1 beside
  -- the Genji Glove he already wears (slot 4 stays: owner guideline, the
  -- glove pairs the boost-Fight chips).  A Relic-screen back-out with the
  -- Genji Glove involved makes the game run its own Optimum (the lib's
  -- hazard note; measured in probe_equip_kit.lua, where swapping the
  -- glove OUT re-dressed the gear session's picks; here the glove stays
  -- and Optimum re-picked LOCKE's off-hand $02 -> $05): best-attack gear,
  -- element-blind, which for a gauntlet of physical hitters is the intent.
  H.equipKit(TERRA, { { 4, 0xB7 }, { 5, 0xB1 } }, { tag = "TERRA deck kit" }),
  H.equipKit(LOCKE, { { 5, 0xB1 } }, { tag = "LOCKE deck kit" }),
  H.call(function()
    local base = 0x1600 + 37 * EDGAR
    H.assertEq(H.readByte(base + 0x1F) ~= 0xFF and H.readByte(base + 0x22) ~= 0xFF, true,
      "EDGAR wears a weapon and armor into the rest of the gauntlet")
  end),
  deckDrive("ultros"),
  -- ---- 1c. arm Ultros IV: a pathed walk to the deck's right edge ---------
  H.call(function()
    H.log(string.format("[deck] the Ultros teaser is up ($01F0) at f%d, at (%d,%d); walking to (22,6)", H.frame, H.fieldX(), H.fieldY()))
  end),
  H.absorbSafeArms(nil, fcAhead, { tag = "arms for Ultros IV and the continent" }),
  -- ultros4_entry: the deck, controllable, one walk from arming Ultros IV
  -- (battle_ultros4 boots it).  Captured with no frames spent (H.saveState
  -- waits 2, which moved every IAF battle after it and changed the play;
  -- #329 review) and emitted after the landing save.
  H.call(function() u4Req = H.requestSaveState() end),
  H.navTo(22, 6, { maxFrames = 6000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
                   nuke = FIGHT.nuke, items = true, bank = FIGHT.bank, healPercent = FIGHT.healPercent,
                   care = false, arrive = function() return not H.hasControl() or H.fieldX() == 22 end }),
  deckDrive(false),
  H.call(function()
    H.assertEq(mapIs(394) and H.hasControl(), true, "the Floating Continent loaded with control: the IAF gauntlet is won")
    H.assertEq(seenBattles >= 1, true, "the IAF chain was fought, not skipped")
    H.log(string.format("IAF: %d battles; FC landing at (%d,%d)", seenBattles, H.fieldX(), H.fieldY()))
    H.screenshot("fc_landing")
  end),
  (function()
    local t = 0
    return H.driveUntil(function() return H.hasControl() and not H.dialogWaiting() end, 3000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "arrival settles")
  end)(),
  -- ---- 2. the landing SavePoint: checkpoint Q (fc-landing-v1) -----------
  -- 394 (7,12) is a SavePoint (the map's trigger block; route doc §4), three
  -- tiles east of where the Blackjack sets the party down.
  H.navTo(7, 12, { maxFrames = 6000, playBattles = "tactical", healer = TERRA,
                   items = true, magic = FIGHT.magic }),
  H.call(function()
    H.assertEq(mapIs(394) and H.fieldX() == 7 and H.fieldY() == 12, true,
      "standing on the landing SavePoint 394 (7,12)")
  end),
  -- Rows, here and not on the deck: the between-wave window fits the kit
  -- but not one more Order-screen session (the regen's fc_landing timed
  -- out opening it as wave 2 arrived).  TERRA (Magic) and EDGAR (Tools)
  -- never swing, so the back row costs them nothing and halves the
  -- physical damage they take; LOCKE fights, front row.  (All three
  -- arrive back-row from P; only LOCKE moves.)
  H.setRows({ [TERRA] = true, [EDGAR] = true, [LOCKE] = false }, { tag = "landing rows" }),
  H.fieldCare({ tag = "care at the landing save point", threshold = 0.95 }),
  H.call(function()
    H.assertExitContractPreSave("fc-landing-v1")
    H.screenshot("fc_landing_q_tile")
  end),
  H.saveState("fc_landing.mss"),
  H.call(function()
    H.checkReq(u4Req, "ultros4_entry capture")
    H.emitBlob("ultros4_entry.mss", u4Req.blob)
  end),
  H.saveGame({ slot = 3, tag = "fc-landing-v1 save" }),
  H.call(function()
    H.assertExitContract("fc-landing-v1")
  end),
  H.logStep(function()
    return string.format("fc-landing-v1 saved via the real Save UI at frame %d -- map 394 (%d,%d), slot 3; boundary Q",
      H.frame, H.fieldX(), H.fieldY())
  end),
}))
