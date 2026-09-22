-- @manual
-- lab_airforce_bake.lua -- the Air Force lab's fixture half (#201).
--
-- gen_fc_landing.lua's route, verbatim, from the cold Continue of the
-- tracked `thamasa-done-v1` battery through the Thamasa prep, the boarding,
-- the deck party select, the IAF waves (EDGAR dressed in the first
-- between-wave window) to the Ultros teaser ($01F0) -- where it banks
-- `airforcelab_teaser.mss` (the last field-control window before the
-- chain's two bosses) -- then the arming walk to (22,6) and Ultros IV +
-- Chupon under the gen's own FIGHT driver, and at the first input-gated
-- moment after that battle (a dialog box waiting, or control) before the
-- Air Force loads, `airforcelab_doorstep.mss`: the Air Force's doorstep,
-- reached the way the route reaches it, for lab_airforce_template.lua to
-- branch into policy x seed experiments (docs/TESTING.md: one
-- legitimately reached snapshot, many experiments).  If the chain goes
-- from the Ultros fight into the Air Force with no input in between the
-- log says so and only the teaser snapshot is banked.
--
-- Reads and pad presses only; the waves and Ultros are fought for real.
-- The segment runner retries a wave wipe (seed-dependent) from the boot
-- snapshot, up to 3 attempts; the Air Force is never fought here.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")


local ZMENUSTATE = 0x26
local POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY = 0xE9, 0xF0, 0xE8, 0xF2, 0xF5   -- item ids (the care kernel's)
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
-- Character record $1600 + 37*c (field-ram.txt:885-927): +8 level, +9 HP,
-- +11 max HP, +13 MP, +15 max MP, +$1E esper, +$1F..+$24 weapon/shield/
-- helm/armor/relic/relic; spells known $1A6E + 54*c + spell ($FF).  The
-- lab header's "what the party has" row (lab_nerapa_bake's probe).
local function probeParty(where)
  for _, c in ipairs(H.partyMembers()) do
    local b = 0x1600 + 37 * c
    local known = {}
    for id = 0, 53 do
      if H.readByte(0x1A6E + c * 54 + id) == 0xFF then known[#known + 1] = string.format("%02X", id) end
    end
    H.log(string.format("[party %s] char=%d L%d hp=%d/%d mp=%d/%d row=%s esper=$%02X gear=%02X,%02X,%02X,%02X,%02X,%02X spells=%s",
      where, c, H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11), H.readWord(b + 13), H.readWord(b + 15),
      (H.readByte(0x1850 + c) & 0x20) ~= 0 and "back" or "front",
      H.readByte(b + 0x1E), H.readByte(b + 0x1F), H.readByte(b + 0x20), H.readByte(b + 0x21),
      H.readByte(b + 0x22), H.readByte(b + 0x23), H.readByte(b + 0x24), table.concat(known, ",")))
  end
  H.log(string.format("[bag %s] tonic=%d potion=%d fenix=%d autocrossbow=%d gil=%d",
    where, H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.invCountOf(H.AUTOCROSSBOW), H.gil()))
end

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

local DECK = { S = H.newPartySelect(PICK), helmT = 0, formed = false, careD = nil }
local function deckDrive(untilKit)
    local S = DECK.S
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
        if active or H.battleLoadStarted() then F.frame(); return end
        local ms = H.readByte(ZMENUSTATE)
        if ms >= 0x2c and ms <= 0x2f then
          if not DECK.formed and S.ready() and S.complete() then
            DECK.formed = true
            H.log("party select group: " .. S.group())
          end
          S.pulse(); return
        end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          local sel, ph = H.readByte(0x056E), H.frame % 24
          if sel > 0 then H.setPad(ph < 3 and { up = true } or {})
          else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
          return
        end
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

H.run({ maxFrames = 600000, retries = 3 }, flatten({
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
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.shopClose("Thamasa item shop"),
  H.call(function()
    H.log(string.format("[prep] shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN), H.gil(), H.frame))
    H.assertEq(H.invCountOf(POTION) >= 65, true, "Potions stocked to 65 for the gauntlet -- the L29 band plus the measured FC spend")
    H.assertEq(H.invCountOf(FENIX_DOWN) >= 25, true, "Fenix Downs stocked to 25")
  end),
  H.bagArrange({ POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top" }),
  H.call(function()
    H.assertEq(H.readByte(0x1869), POTION, "slot 0 is Potion: the combat heal is one press away")
    H.assertEq(H.readByte(0x186A), FENIX_DOWN, "slot 1 is Fenix Down")
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
  -- probe_p_ship.lua).  Boarding here is a TALK, not a walk: face WEST
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
  H.call(function() probeParty("teaser") end),
  H.saveState("airforcelab_teaser.mss"),
  H.logStep(function() return string.format("[bake] airforcelab_teaser banked at f%d, $021e=%d, at (%d,%d)", H.frame, H.readByte(0x021E), H.fieldX(), H.fieldY()) end),
  H.navTo(22, 6, { maxFrames = 6000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
                   nuke = FIGHT.nuke, items = true, bank = FIGHT.bank, healPercent = FIGHT.healPercent,
                   care = false, arrive = function() return not H.hasControl() or H.fieldX() == 22 end }),
  -- ---- 1d. Ultros IV + Chupon, then stop at the Air Force's doorstep ----
  -- The gen's deckDrive(false) rides the rest of the chain to the
  -- continent, A-tapping every dialog.  Here the same driver fights
  -- Ultros IV + Chupon (formation species $168 / $12F), and once that
  -- battle has torn down nothing is pressed: the first frame the game
  -- waits on the player (a dialog box, or control) is the doorstep.  If
  -- the Air Force's formation ($113) loads first, there is no window.
  (function()
    local seenUltros, ultrosDone, window, t = false, false, nil, 0
    return H.driveUntil(function()
      t = t + 1
      if (H.gameOverFired or 0) > 0 then
        error(string.format("the chain was LOST (game over after %d battles) -- a lab, not a retry", seenBattles), 0)
      end
      local active, loading = H.battleActive(), H.battleLoadStarted()
      if (active or loading) and H.formationHas({ [0x0168] = true, [0x012F] = true }) then
        if not seenUltros then
          seenUltros = true
          H.log(string.format("[bake] Ultros IV up at f%d ($021e=%d)", H.frame, H.readByte(0x021E)))
        end
      end
      if (active or loading) and H.formationHas({ [0x0113] = true }) then
        window = "none"
        H.log(string.format("[bake] the Air Force loaded at f%d with no input window after Ultros (ultrosDone=%s): only the teaser snapshot is banked", H.frame, tostring(ultrosDone)))
        return true
      end
      if seenUltros and not active and not loading then
        if not ultrosDone then
          ultrosDone = true
          H.log(string.format("[bake] Ultros IV torn down at f%d ($021e=%d); pressing nothing until the game waits on the player", H.frame, H.readByte(0x021E)))
        end
        if H.dialogWaiting() then window = "dialog"; return true end
        if H.hasControl() then window = "control"; return true end
      end
      return false
    end, 40000, {
      H.call(function()
        local active = H.battleActive()
        if active and not lastActive then
          seenBattles = seenBattles + 1
          H.log(string.format("  [IAF battle %d] f%d", seenBattles, H.frame))
        end
        lastActive = active
        if active or H.battleLoadStarted() then F.frame(); return end
        if not ultrosDone and H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "arm Ultros -> Ultros IV + Chupon -> the first input-gated moment before the Air Force")

  end)(),
  H.release(),
  H.call(function()
    H.assertEq(seenBattles >= 1, true, "the IAF chain was fought")
    H.log(string.format("[bake] doorstep reached at f%d: map %d (%d,%d) dialog=%s control=%s $021e=%d battles=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.dialogWaiting()), tostring(H.hasControl()),
      H.readByte(0x021E), seenBattles))
  end),
  H.cond(function() return H.dialogWaiting() or H.hasControl() end, {
    H.call(function() probeParty("doorstep") end),
    H.screenshot("airforcelab_doorstep"),
    H.saveState("airforcelab_doorstep.mss"),
    H.logStep(function() return string.format("[bake] airforcelab_doorstep banked at f%d, $021e=%d (dialog=%s control=%s)",
      H.frame, H.readByte(0x021E), tostring(H.dialogWaiting()), tostring(H.hasControl())) end),
  }, {
    H.logStep("[bake] no doorstep snapshot: the Air Force loaded straight from the Ultros fight; the lab branches from airforcelab_teaser.mss"),
  }),
}))
