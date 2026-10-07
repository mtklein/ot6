-- gen_wor_edgar.lua -- the World of Ruin from South Figaro to Edgar:
-- cold-Continue the `wor-south-figaro-v1` battery (CELES and SABIN at world
-- (113,96), outside South Figaro), and save on the world map outside the
-- surfaced Figaro Castle with EDGAR in the party: the `wor-edgar-v1`
-- battery.  Generates wor_edgar.mss; its capture run (OT6_CAPTURE_SRM)
-- cuts `wor-edgar-v1`.  docs/design/route-wor-edgar.md has the plan
-- (sections 2.5-2.8, 6) and what this measured (section 12).
--
-- The route:
--   1. The South Figaro continent's grass, forest and plain (41-43), walked
--      in a loop and fought until both members are L30 (TARGET_LEVEL):
--      SABIN's Air Blade.  Not its desert (44): see GRIND below.
--   1b. The bag's Peace Rings on once Muddle has been seen, since every
--      body in the cave Muddles: whoever lacks one, at each arrival in the
--      cave and the basements; the usual relics back for the Tentacles and
--      the save (route-wor-edgar 12.4, #320).  The bag's Back Guard on
--      CELES from the cave's door (no back or pincer attacks), and a
--      Muddled ally left to the monsters' hits, no cure-hit from a Genji
--      pair (backGuard, CAVE_FIGHT; route-wor-edgar 12.5).
--      Informed choices (an experienced player's knowledge, from the labs
--      and the ROM, not from what this run has met): the Back Guard at the
--      door, the relics and the hands at the stop before the Tentacles,
--      and Air Blade there (backGuard, section 4 below).
--   2. The Figaro cave behind the thieves: map 68's three pieces by their
--      links, the turtle scene on 90's arrival tile, the crossing (face up
--      and hold A on (47,29)), 92, 53, and the castle's basement 61, where
--      Gerad goes on ahead.  The chests on the way are opened where the
--      party can reach them.
--   3. The basements: 61 to the lower hall 59 and back to 61's west room,
--      62, the chest room of 63, and 62's engine-room floor; each door and
--      link is a leg of its own (the navigator plans within one piece).
--   4. The stop before the Tentacles: no element in any hand (they absorb
--      fire, ice and bolt between them, and the runner's absorb guard
--      refuses such a fight), the field care to full -- and again on the
--      tile below Gerad, after the few steps up (route-wor-edgar 12.5).
--   5. Gerad at the engines: EDGAR joins (dressed by the game's Optimum from
--      the bag) and battle 84 opens: the Tentacles, fought by the tactical
--      driver with SABIN's blitz set to Air Blade.  A loss is a game over,
--      retried from the checkpoint by the runner.
--   6. The kits back, EDGAR's relics and RAMUH, the Soul Sabre behind the
--      engines, the way back to the engineer in basement 1 (a different
--      way: basement 3's east stairs), the surfacing, and out of the castle
--      to world (81,86) and the real Save UI into slot 3.
-- Every battle's [outcome] is asserted said, judged on the battle's own end
-- reading, and paid as due.  Nothing is written; every step, menu and fight
-- is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN, EDGAR = 6, 5, 4
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, GREEN_CHERRY = 0xF1, 0xF8
local CAVE_DOOR = { 106, 98 }
local REGALCUTLASS, METALKNUCKLE, MITHRIL_SHLD, ENHANCER = 0x0B, 0x53, 0x5C, 0x13
local THUNDERBLADE, FIRE_KNUCKLE, SOUL_SABRE = 0x0F, 0x57, 0x16
local JEWEL_RING, STAR_PENDANT, PEACE_RING, BLACK_BELT = 0xB5, 0xB1, 0xB2, 0xD5
local BACK_GUARD = 0xE1                             -- no back or pincer attacks (ChooseBattleType @2e3a)
local RAMUH = 0                                     -- esper index
local AIR_BLADE = 0x62                              -- SABIN's blitz, learned at L30
local TENTACLES_FORM = 454                          -- event battle 84
local B2_EXITS = { { 13, 12 }, { 14, 8 }, { 2, 13 }, { 4, 6 }, { 8, 18 }, { 8, 6 } }  -- map 62's doors
local MAP_CAVE1, MAP_CAVE2, MAP_CAVE3, MAP_CAVE4 = 68, 90, 92, 53
local MAP_B1, MAP_B2, MAP_B3, MAP_ENGINE = 61, 62, 63, 64
local MAP_CASTLE = 55
local SAVE_TILE = { 81, 86 }                        -- where the castle's exit returns the party (measured)

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch or CELES, 8)) end
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
-- The Muddle guard (#320): every body in the cave and the basements
-- Muddles (the Humpty's Hug, the Cruller's BrainStorm, the NeckHunter's
-- Mad Sickle, the Drop's Mad Signal), and the Peace Ring guards Muddle.
-- A person reaches for it once they have seen Muddle, not before: from
-- the first landing this run (H.statusSeen, every landing the fight
-- driver saw), each arrival on a map or piece of the cave and the
-- basements puts the bag's rings on whoever lacks one, in order SABIN
-- (for his Black Belt), EDGAR once he has joined (for his Star Pendant),
-- CELES (for her Jewel Ring).  The bag holds one at the checkpoint and
-- the NeckHunter drops more.  At the Tentacles (none of which Muddles;
-- informed: read from their scripts, not met) and out of the castle for
-- the save, each member's own relic goes back (usualRelics).  The lab
-- behind it is route-wor-edgar 12.4
-- (build/attempts/wt/figaro-muddle/).
-- A relic change on a Genji Glove wearer (SABIN and CELES) re-runs the
-- game's Optimum on leaving the Relic screen (CheckReequipRelics, menu
-- equip.asm @9f5c: a Genji Glove, Gauntlet or Merit Award in either slot
-- before or after): measured, CELES's ring at the stop before Edgar put
-- the Break Blade in her off hand and the Crystal Helm on her, and EDGAR's
-- own Optimum then took the Blizzard into the Tentacles, which the absorb
-- guard refused (`char 4's R-hand item $0E (ice) is ABSORBED by slot 2
-- species $013C`, build/attempts/wt/figaro-muddle/final_v1/k3_s0.log).
-- So `hands` (member -> { right, left }) puts the hands back after a
-- relic change where no kit step follows; a stop with a kit step of its
-- own changes the relics first.
local MEMBERS = { { SABIN, "SABIN" }, { EDGAR, "EDGAR" }, { CELES, "CELES" } }
local function handsBack(m, keep, what)
  return H.cond(function()
    return H.readByte(c(m[1], 0x1F)) ~= keep[1] or H.readByte(c(m[1], 0x20)) ~= keep[2]
  end, { H.equipKit(m[1], { { 0, keep[1] }, { 1, keep[2] } },
           { tag = m[2] .. ": the hands back after the game's Optimum (" .. what .. ")" }) }, {})
end
local function wearsPeace(ch)
  return H.readByte(c(ch, 0x23)) == PEACE_RING or H.readByte(c(ch, 0x24)) == PEACE_RING
end
local function wearsBackGuard(ch)
  return H.readByte(c(ch, 0x23)) == BACK_GUARD or H.readByte(c(ch, 0x24)) == BACK_GUARD
end
-- The Back Guard (the bag holds one, $E1) on CELES in place of her Jewel
-- Ring for the cave and the basements: it takes the back and pincer
-- attacks off the table, and a back attack or a pincer turns the pair's
-- back row to the front, where the monsters' blows and a Muddled ally's
-- Genji pair land in full.  Informed: it goes on at the cave's door
-- whatever this run has met, on the lab's measurement (route-wor-edgar
-- 12.5, the re-cut chain's cave mouth): without it 96 of 651
-- formation-232 fights were a back attack or a pincer and 4 of those were
-- lost (2 of the 555 normal ones); with it 330 fights, all normal, none
-- lost.  The lineage has been pincered before (the re-cut captures: one in
-- wor-tzen-door-v1, two in wor-nikeah-v1, build/attempts/wt/recut/capture/),
-- but not in Tzen's house: gen_wor_sabin wears the Back Guard before the
-- house's clock starts (HOUSE_BACK_GUARD), so no pincer happens there.  CELES rather
-- than SABIN: the Peace Ring goes to SABIN first (peaceRings), and nothing
-- in the cave Petrifies (her Jewel Ring's guard).
local function backGuard(what, hands)
  local m = MEMBERS[3]
  return H.cond(function()
    return inParty(CELES) and not wearsBackGuard(CELES) and H.invCountOf(BACK_GUARD) > 0
  end, { H.equipKit(CELES, { { 5, BACK_GUARD } }, { tag = "CELES: the Back Guard (" .. what .. ")" }),
         hands and handsBack(m, hands[CELES], what) or H.seqStep({}) }, {})
end
local function peaceRings(what, hands)
  local steps = {}
  for _, m in ipairs(MEMBERS) do
    local keep = hands and hands[m[1]]
    steps[#steps + 1] = H.cond(function()
      return (H.statusSeen.Muddle or 0) > 0 and inParty(m[1]) and not wearsPeace(m[1])
        and not wearsBackGuard(m[1]) and H.invCountOf(PEACE_RING) > 0
    end, { H.equipKit(m[1], { { 5, PEACE_RING } }, { tag = m[2] .. ": a Peace Ring (" .. what
             .. ", Muddle seen this run)" }),
           keep and handsBack(m, keep, what) or H.seqStep({}) }, {})
  end
  return H.seqStep(steps)
end
-- each member's own relic back in place of a Peace Ring or the Back Guard
-- (slot 5, where peaceRings and backGuard put them), from the bag
local USUAL_RELIC = { [SABIN] = BLACK_BELT, [EDGAR] = STAR_PENDANT, [CELES] = JEWEL_RING }
local function usualRelics(what, hands)
  local steps = {}
  for _, m in ipairs(MEMBERS) do
    local keep = hands and hands[m[1]]
    steps[#steps + 1] = H.cond(function()
      local r = H.readByte(c(m[1], 0x24))
      return inParty(m[1]) and (r == PEACE_RING or r == BACK_GUARD)
        and H.invCountOf(USUAL_RELIC[m[1]]) > 0
    end, { m[1] == CELES
             -- CELES's through the relic rule over it (H.relicKit): a Ribbon
             -- the Back Guard took off goes back on, not the Jewel Ring
             and H.relicKit(CELES, m[2], { [5] = USUAL_RELIC[CELES] },
               { tag = m[2] .. ": the usual relic back (" .. what .. ")" })
             or H.equipKit(m[1], { { 5, USUAL_RELIC[m[1]] } }, { tag = m[2] .. ": the usual relic back (" .. what .. ")" }),
           keep and handsBack(m, keep, what) or H.seqStep({}) }, {})
  end
  return H.seqStep(steps)
end
-- The cave's fights leave a Muddled ally to the monsters' hits, which clear
-- Muddle the same way (CalcMaxDmg strips it from a physically damaged
-- target), rather than the Muddle rule's cure-hit (#170): here the hitter
-- carries a Genji pair, and its cure-hit is the party's biggest hit --
-- SABIN's took 947 of CELES's 1038 with the Peace Ring on him, and a
-- monster finished her (build/attempts/wt/edgar-regress/arms/
-- new_ringnow_c68/er_k1_s0_c68_w41.log: `[unmuddle] actor 1 (char 5)'s hit
-- on entity 0 took 947 (1038 -> 91)`).  Measured on the re-cut chain's
-- cave mouth (formation 232, the pair, 33 runs of 6 battles an arm):
-- SABIN's ring on once Muddle is seen, with the cure-hit, lost 4 of 159
-- fights (7 with a death); the same without it lost 0 of 165 (2); bare,
-- 1 of 162 (6) and 1 of 165 (3) (route-wor-edgar 12.5).
local CAVE_FIGHT = { unmuddle = false }
-- the hands the cave is walked in, put back after a ring's Optimum
local CAVE_HANDS = { [SABIN] = { FIRE_KNUCKLE, FIRE_KNUCKLE }, [CELES] = { ENHANCER, THUNDERBLADE } }
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d revivify=%d greencherry=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(GREEN_CHERRY), H.gil())
end
local function member(ch, name)
  return string.format("%s L%d HP %d/%d MP %d/%d status1 $%02X", name, level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine()
  local s = member(CELES, "CELES") .. "; " .. member(SABIN, "SABIN")
  if inParty(EDGAR) then s = s .. "; " .. member(EDGAR, "EDGAR") end
  return s
end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end
-- ---- the battles --------------------------------------------------------
-- Every battle the walkers and the story driver fight ends in an [outcome];
-- each is asserted judged on its own end reading and paid as due, and the
-- count is asserted against the runner's own battle count (gen_wor_sabin's
-- shape).  The Tentacles pay nothing (vanilla XP 0): paid as due is 0.
local seen, tally, outcome0, battles0
local function tallyReset()
  tally = { won = 0, ["party left"] = 0, lost = 0, escaped = 0, forms = {}, order = {} }
  outcome0, battles0 = #H.outcomes, H.absorbGuardBattles
  seen = outcome0
end
tallyReset()
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own "
        .. "end reading (the UpdateSRAM hook), not the last per-frame one", what, i - outcome0,
        o.form & 0x1FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x1FF, o.kind))
      tally[o.kind] = (tally[o.kind] or 0) + 1
      tally.escaped = tally.escaped + #o.escaped
      local k = string.format("$%03X", o.form & 0x1FF)
      if not tally.forms[k] then tally.order[#tally.order + 1] = k end
      tally.forms[k] = (tally.forms[k] or 0) + 1
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    if #H.outcomes > seen then
      seen = #H.outcomes
      H.log(string.format("[route] %s: %d battle(s) so far, %d [outcome] line(s) (%d won, %d the "
        .. "party left, %d monster escape(s)); %s; %s", what, H.absorbGuardBattles - battles0,
        seen - outcome0, tally.won, tally["party left"], tally.escaped, whereLine(), supplies()))
    end
  end)
end
local function control(what)
  return H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
  end, 3000, what, 5)
end
-- walk onto a map edge / entrance tile until the map changes
-- The arrival counts only once the new map is lit and in control: the map
-- word turns during the fade while the old coordinates still read, and a
-- party that lands next to another exit can be carried on through it
-- (measured once: basement 3's (47,8) -> 62 (3,12), then 62's (2,13) back
-- to 63 (46,9) inside the fade-in).  So the walk goes again, up to three
-- times, until the party stands on `dst` with control.
-- `story`: the arrival starts a scene (the turtle's), which the caller's
-- advanceStory pages; the walk then ends as soon as the map has turned.
local function walkInto(x, y, dst, what, avoid, story)
  local function there()
    return map() == dst and (story or (H.hasControl() and H.tileAligned() and bright() >= 15))
  end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = CAVE_FIGHT, avoid = avoid,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
        H.waitUntil(function()
          return story or (H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting())
        end, 3000, what .. ": control", 5),
        H.call(function()
          if map() ~= dst then
            H.log(string.format("[route] %s: carried on to map %d (%d,%d); going again", what, map(),
              H.fieldX(), H.fieldY()))
          end
        end),
      }, {}),
    }),
    H.call(function()
      H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY()))
      H.assertEq(map(), dst, what .. ": on map " .. dst)
    end),
  })
end

-- Talk to an NPC standing at (x,y) from the tile below it: the tactical
-- walker up to (x, y+1) (a random battle on the way is fought by the
-- driver), then face up and press A until `started` holds.  Not
-- H.talkToObj, whose approach plays battles by mashing A (measured twice
-- here: the Tentacles fought by mashing, every member dead with 5 BP banked,
-- build/attempts/wt/wor-edgar/leg3/ed9.log; a cave battle on the way to
-- Siegfried, which the [outcome] count caught: `an [outcome] said for every
-- battle fought ... got 28, want 29`, leg3/var_ed3/k3_s0.log).
-- `topUp`: the field care to full on the tile below, before the talk --
-- for a talk that opens a boss, where a random battle on the few steps up
-- would otherwise send the party in hurt.
local function talkUp(x, y, started, what, topUp)
  local ph = 0
  return H.seqStep({
    H.navTo(x, y + 1, { maxFrames = 6000, playBattles = "tactical", fight = CAVE_FIGHT }),
    topUp and H.fieldCare({ threshold = 1.0, tag = what .. ": topped up on the tile below" }) or H.seqStep({}),
    H.withReset(H.driveUntil(function()
      return started() or (H.eventRunning() and not H.battleLoadStarted() and H.dialogWaiting())
    end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.readByte(0x087F + H.readWord(0x0803)) ~= 0 then H.setPad({ up = true }); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, what), function() ph = 0 end),
    H.release(),
  })
end

-- step onto a same-map link tile until `across` holds (the party has been
-- moved to the link's far side), fighting what comes on the way
local function crossLink(x, y, across, what)
  return H.seqStep({
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = CAVE_FIGHT, arrive = across }),
    H.release(),
    H.waitUntil(function() return across() and H.hasControl() and H.tileAligned() end, 900,
      what .. ": across", 5),
  })
end

-- A chest on the way: opened from whichever neighbour the party can reach
-- where it stands (the cave's pieces are joined by links the walker does
-- not plan through), else said and left.  H.openChest is idempotent on the
-- treasure bit, so one the World of Balance opened (the $01x bits the WoB
-- cave shares) is a logged no-op.
local function chest(x, y, bit, what, item)
  local steps = {}
  for _, c in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" } }) do
    local sx, sy = x + c[1], y + c[2]
    steps[#steps + 1] = H.cond(function()
      return not H.chestOpen(bit) and H.bfsPath(sx, sy) ~= nil
    end, { H.openChest({ stand = { sx, sy }, face = c[3], bit = bit, what = what, item = item,
             nav = { fight = CAVE_FIGHT } }) }, {})
  end
  steps[#steps + 1] = H.call(function()
    if not H.chestOpen(bit) then
      H.log(string.format("[chest] %s (%d,%d) bit $%03X: no neighbour reachable from (%d,%d); left",
        what, x, y, bit, H.fieldX(), H.fieldY()))
    end
  end)
  return H.seqStep(steps)
end

-- The grind (a lever: GRIND_ON, TARGET_LEVEL; route-wor-edgar 12 has the
-- lab): a loop through the grass, forest and plain (groups 41-43), off the
-- desert and the doors, to TARGET_LEVEL.  Not the desert (group 44): its
-- Sand Horse pair (formation 222; Sand Storm, 400-450 a member) was won 6
-- times and lost 2 across the variation sets, both losses with the horses
-- untouched (monhp s0:1025/sh2 s1:1025/sh2) while the pair spent its turns
-- on heals and items (build/attempts/wt/wor-edgar/leg3/var_ed_v1/k2_s0.log,
-- var_ed2/k2_s0.log) -- a driver finding and a lab candidate, not a level
-- wall (route-wor-edgar 12.1, 13); off the loop until it is measured.
local GRIND_ON, TARGET_LEVEL = true, 30
local GRIND = { { 106, 100 }, { 111, 101 }, { 101, 83 }, { 80, 103 } }
local DOORS = { { 113, 95 }, { 106, 98 }, { 81, 85 }, { 82, 85 } }
local GRIND_AVOID = nil                             -- the doors and every desert tile, built live
local function grindAvoid()
  if GRIND_AVOID == nil then
    local list = {}
    for y = 60, 120 do for x = 60, 125 do
      if H.worldEncounterGroup(x, y, x, y) == 44 then list[#list + 1] = { x, y } end
    end end
    for _, t in ipairs(DOORS) do list[#list + 1] = t end
    GRIND_AVOID = H.worldAvoidSet(list)
  end
  return GRIND_AVOID
end
local gwp, grindLegs, grindDone = 1, 0, false

H.run({ maxFrames = 600000 }, {
  -- ---- 0. cold Continue of wor-south-figaro-v1 ------------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the World of Ruin outside South Figaro", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    H.assertEntryContract("wor-south-figaro-v1")
    tallyReset()
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s; kit CELES %s, SABIN %s; %s", H.frame,
      H.worldId(), H.worldX(), H.worldY(), whereLine(), kit(CELES), kit(SABIN), supplies()))
  end),

  -- ---- 0b. the South Figaro continent, to TARGET_LEVEL ------------------------------------
  -- A loop through the continent's grass, forest and plain (41-43:
  -- route-wor-edgar 3.2; the walk to the cave alone crosses 14 steps of
  -- 41/43), fought and cared for as every walk is, until both members reach
  -- TARGET_LEVEL -- the Tentacles at the end of the cave are an event battle
  -- whose loss is a game over (section 6).
  H.cond(function() return GRIND_ON end, {
    H.withReset(H.driveUntil(function() return grindDone end, 600000, {
      H.worldNavTo(function() return GRIND[gwp][1] end, function() return GRIND[gwp][2] end,
        { maxFrames = 20000, playBattles = "tactical", avoid = grindAvoid }),
      H.fieldCare({ tag = "care on the grind" }),
      H.call(function()
        gwp = gwp % #GRIND + 1
        grindLegs = grindLegs + 1
        grindDone = level(CELES) >= TARGET_LEVEL and level(SABIN) >= TARGET_LEVEL
      end),
    }, "the grind to L" .. TARGET_LEVEL), function() gwp, grindLegs, grindDone = 1, 0, false end),
    H.call(function()
      H.log(string.format("[wor] grind done f%d after %d legs: %s; %s", H.frame, grindLegs, whereLine(), supplies()))
    end),
    checkOutcomes("the grind"),
  }, {}),

  -- ---- 0c. the Muddle guard (#320) -------------------------------------------------------
  -- The checkpoint's bag holds a Peace Ring (wor-south-figaro-v1: $B2 x1);
  -- it goes on at the first stop after a Muddle has been seen (peaceRings).
  H.call(function()
    H.assertEq(H.invCountOf(PEACE_RING) >= 1, true,
      "the bag holds a Peace Ring for the cave (wor-south-figaro-v1's bag: $B2 x1)")
    H.log(string.format("[wor] the Muddle guard: %d Peace Ring(s) in the bag; Muddle seen %d time(s) so far",
      H.invCountOf(PEACE_RING), H.statusSeen.Muddle or 0))
  end),
  peaceRings("before the cave", CAVE_HANDS),
  H.call(function()
    H.assertEq(H.invCountOf(BACK_GUARD) >= 1 or wearsBackGuard(CELES), true,
      "the bag holds a Back Guard for the cave (wor-south-figaro-v1's bag: $E1 x1)")
  end),
  backGuard("before the cave", CAVE_HANDS),

  -- ---- 1. into the Figaro cave ------------------------------------------------------------
  H.worldNavTo(CAVE_DOOR[1], CAVE_DOOR[2], { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_CAVE1 end, 2400, "the cave: map 68", 5),
  control("the cave: control"),
  H.call(function() say("cave", "in the cave") end),
  H.cond(function() return sw(0x0398) == 1 end, {
    talkUp(14, 36, function() return sw(0x0399) == 1 end, "Siegfried at the cave's mouth (14,36)"),
    H.advanceStory(function() return sw(0x0399) == 1 and H.hasControl() and not H.dialogWaiting() end, 3000, { playBattles = "tactical", fight = CAVE_FIGHT }),
  }, {}),
  -- map 68 is three pieces joined by same-map links (route_data field-path
  -- 68 16 42 10 2: 70 steps through (14,33) -> (55,56) and (61,57) ->
  -- (17,21)); the navigator plans within a piece, so each link is a leg
  chest(3, 18, 0x012, "X-Potion", 0xEA),
  chest(33, 23, 0x061, "Ether", 0xEC),
  crossLink(14, 33, function() return H.fieldX() > 40 end, "the cave: the link (14,33) -> (55,56)"),
  peaceRings("map 68, the second piece", CAVE_HANDS),
  crossLink(61, 57, function() return H.fieldX() < 40 end, "the cave: the link (61,57) -> (17,21)"),
  peaceRings("map 68, the third piece", CAVE_HANDS),
  chest(3, 18, 0x012, "X-Potion", 0xEA),
  chest(33, 23, 0x061, "Ether", 0xEC),
  -- (10,2) -> map 90 (55,31), the turtle scene's own tile
  walkInto(10, 2, MAP_CAVE2, "the cave: on to map 90", nil, true),
  H.advanceStory(function()
    return sw(0x0383) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting() and bright() >= 15
  end, 12000, { playBattles = "tactical", fight = CAVE_FIGHT }),
  H.call(function()
    say("cave", "the turtle is fed")
    H.assertEq(sw(0x0383), 1, "the turtle scene ran ($0383, _ca76e1)")
  end),
  -- the crossing: (47,29) facing up with A held carries the party to (47,25)
  H.navTo(47, 29, { maxFrames = 6000, playBattles = "tactical", fight = CAVE_FIGHT }),
  H.faceAndHoldA("up", function() return H.fieldY() <= 25 and H.hasControl() and H.tileAligned() end,
    3000, "the turtle: face up and hold A on (47,29) -- _ca76b3"),
  H.release(),
  control("across the water"),
  peaceRings("across the water", CAVE_HANDS),
  H.call(function() say("cave", "across on the turtle") end),
  chest(52, 14, 0x013, "Hero Ring", 0xC9),
  walkInto(47, 24, MAP_CAVE3, "the cave: on to map 92"),
  control("map 92"),
  peaceRings("map 92", CAVE_HANDS),
  walkInto(47, 11, MAP_CAVE4, "the cave: on to map 53"),
  control("map 53"),
  peaceRings("map 53", CAVE_HANDS),
  H.call(function() say("cave", "map 53") end),
  walkInto(21, 56, MAP_B1, "the cave: into the castle's basement"),
  H.advanceStory(function()
    return map() == MAP_B1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting() and bright() >= 15
  end, 6000, { playBattles = "tactical", fight = CAVE_FIGHT }),
  H.call(function() say("castle", "basement 1") end),
  H.navTo(35, 40, { maxFrames = 3000, playBattles = "tactical", fight = CAVE_FIGHT,
    arrive = function() return sw(0x026E) == 1 end }),
  H.advanceStory(function()
    return sw(0x026E) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, { playBattles = "tactical", fight = CAVE_FIGHT }),
  H.call(function() say("castle", "Gerad went on ahead") end),
  peaceRings("basement 1", CAVE_HANDS),
  -- basement 1 is two rooms joined through the castle's lower hall, map 59:
  -- up Gerad's way, the stairs (27,31) -> 59 (14,48), across to (9,49) ->
  -- 61 (10,33), and down (2,37) to basement 2 (measured: from the prison
  -- side the live BFS reaches (27,31) in 21 steps and not (2,37))
  walkInto(27, 31, 59, "basement 1 -> the lower hall (map 59)"),
  control("the lower hall"),
  walkInto(9, 49, MAP_B1, "the lower hall -> basement 1's west room"),
  control("basement 1, west"),
  walkInto(2, 37, MAP_B2, "basement 1 -> basement 2"),
  control("basement 2"),
  peaceRings("basement 2", CAVE_HANDS),
  H.call(function() say("castle", "basement 2") end),
  -- basement 2's door to the engine room is on a floor reached only through
  -- basement 3: (14,8) -> 63 (54,6), its link (56,15) -> (87,7), and the
  -- stairs (84,3) -> 62 (8,17)
  walkInto(14, 8, MAP_B3, "basement 2 -> basement 3"),
  control("basement 3"),
  crossLink(56, 15, function() return H.fieldX() > 70 end, "basement 3: the link (56,15) -> (87,7)"),
  peaceRings("basement 3", CAVE_HANDS),
  chest(80, 14, 0x096, "Ether", 0xEC),
  chest(82, 14, 0x097, "X-Potion", 0xEA),
  chest(86, 14, 0x098, "Gravity Rod", 0x3A),
  chest(88, 14, 0x099, "Crystal Helm", 0x7E),
  H.crossDoor(84, 3, MAP_B2, 8, 17, "basement 3's stairs 63(84,3)->62(8,17)", { fight = CAVE_FIGHT }),
  control("basement 2, the engine-room floor"),
  peaceRings("basement 2, the engine-room floor", CAVE_HANDS),
  H.call(function() say("castle", "basement 2, the engine-room floor") end),
  H.crossDoor(8, 6, MAP_ENGINE, 29, 20, "the engine room's door 62(8,6)->64(29,20)", { fight = CAVE_FIGHT }),
  control("the engine room"),
  H.call(function() say("castle", "the engine room") end),
  checkOutcomes("the cave and the basements"),

  -- ---- the stop before Edgar and the Tentacles ---------------------------------------
  -- Informed (the party has not met the Tentacles; an experienced player
  -- knows them): the hands, the relics and the blitz below are chosen for
  -- this boss.  #324 would have the driver swap hands in battle on seeing
  -- an absorb instead.
  -- No element: the four absorb fire, ice and bolt between them, and the
  -- runner's absorb guard refuses a fight entered with an absorbed weapon
  -- (measured with the plains kit: `char 5's R-hand item $57 (fire) is
  -- ABSORBED by slot 3 species $011B`, `char 6's ... $0E (ice) ... $013C`,
  -- `... $0F (bolt) ... $013D`, build/attempts/wt/wor-edgar/leg3/tent1.log).
  -- CELES: the Enhancer and the RegalCutlass on the Genji Glove; SABIN: the
  -- MetalKnuckle and a Mithril Shld (the bag's one claw).  The bag's best
  -- blade left for EDGAR's Optimum is then the Break Blade (117).
  -- the usual relics back first (none of the Tentacles Muddles): a relic
  -- change on a Genji Glove wearer re-runs the game's Optimum (above), and
  -- the hands are set after it
  usualRelics("the stop before Edgar"),
  -- The relics for this boss through the lib's relic rule, armed against
  -- the Tentacles' own threats (H.FIGHT_THREATS.tentacles: Bio and Poison,
  -- magic that inflicts Poison; an informed reading of their scripts).  On
  -- the 1791fcdf chain the rule put the widest Poison guard (a Star
  -- Pendant) on CELES, the caster, and a Shell ward (the Barrier Ring) on
  -- SABIN over his Black Belt (`Star Pendant $B1 goes to CELES's slot 5`,
  -- `Barrier Ring $B7 goes to SABIN's slot 5`); whatever it picks, the
  -- Back Guard and the usual relics come back after the fight as before
  -- (SABIN's only by way of a Peace Ring, once Muddle has been seen).
  -- Relics against these threats were labbed from three of this
  -- generator's own engine-room stops (shifts 0, 11, 23), each talked to
  -- Gerad at 60 shifts, retries off: as shipped before, 10 of 180 runs
  -- lost (3 of 45 distinct battle keys); the Czarina Ring on CELES, 5 of
  -- 180 (4 of 108 keys); with a Star Pendant on SABIN too, 4 of 180 (4 of
  -- 90 keys).  No measured difference (p 0.17 by runs, 0.69 by keys): a
  -- player's choice, not a fix.  The losses left are the
  -- driver's (wipes with 3-5 BP banked, heals landing after the Bio),
  -- build/attempts/wt/v026-retries/wor_edgar/ (#416).
  H.dressRelics({ { CELES, "CELES" }, { SABIN, "SABIN" } },
    { threats = H.FIGHT_THREATS.tentacles, tag = "relics for the Tentacles" }),
  H.equipKit(CELES, { { 0, ENHANCER }, { 1, REGALCUTLASS } }, { tag = "CELES: no element for the Tentacles" }),
  H.equipKit(SABIN, { { 0, METALKNUCKLE }, { 1, MITHRIL_SHLD } }, { tag = "SABIN: no element for the Tentacles" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Tentacles" }),
  H.call(function()
    say("castle", "ready for Edgar: kit CELES " .. kit(CELES) .. ", SABIN " .. kit(SABIN))
    for _, ch in ipairs({ CELES, SABIN }) do
      for _, s in ipairs({ 0x1F, 0x20 }) do
        local it = H.readByte(c(ch, s))
        H.assertEq(it == 0xFF or H.weaponElement(it) == 0, true,
          string.format("char %d's hand $%02X carries no element (item $%02X)", ch, s, it))
      end
    end
  end),

  -- ---- Edgar, and the Tentacles ----------------------------------------------------------
  -- "Gerad" (NPC_11) stands at (29,16), three steps above the door.  The
  -- walk up is the tactical walker's (a random battle on the way is
  -- fought), then the party faces him and presses A until the scene runs.
  -- Not H.talkToObj: its approach plays battles by mashing A, and the
  -- scene opens battle 84 inside it (measured: a run whose talk engaged
  -- late fought the Tentacles by mashing -- no driver line, every member
  -- dead with 5 BP banked, build/attempts/wt/wor-edgar/leg3/ed9.log).
  -- The scene joins EDGAR, dresses him from the bag (opt_equip) and opens
  -- battle 84: the Tentacles, fought by the tactical driver; a loss is a
  -- game over (_ca5ea9), retried from the checkpoint by the runner.
  -- SABIN's blitz there is Air Blade (wind, every Tentacle at once, and
  -- none of the four absorbs wind), learned at L30 -- the grind's level:
  -- the lab from one engine-room snapshot at L31/30/30, 12 in-battle draws
  -- an arm, won 10 of 12 with his default Pummel and 11 of 12 with Air
  -- Blade: on the same draws Pummel lost two that Air Blade won and Air
  -- Blade lost one that Pummel won, so no measured difference (route-wor-
  -- edgar 12.2; build/attempts/wt/wor-edgar/leg3/tent_l30.out,
  -- tent_l30_airblade.out).  The variation set with Air Blade won the
  -- Tentacles in all 13 runs that reached them (leg3/var_ed4/).  Informed:
  -- "none absorbs wind" is the ROM's data, not something the party has seen.
  H.call(function()
    H.assertEq((H.readByte(0x1D28) & 0x20) ~= 0, true,
      string.format("SABIN knows Air Blade ($1D28 bit 5; SABIN L%d, BlitzLevelTbl 30)", level(SABIN)))
  end),
  -- The care to full again on the tile below Gerad: the three steps up from
  -- the door can meet a random battle after the stop's care (measured on
  -- the re-cut chain: a battle there in 8 of the 23 runs that reached it,
  -- none in the old chain's 15, the party then
  -- entering the Tentacles at 1129/1595 and 1263/1609 (build/attempts/wt/
  -- edgar-regress/before_snap/k7_s0.log), and a lab draw that met one lost
  -- the Tentacles from 1095/1319 (tent/new_base/er_k7_s0_e64p_w18.log)).
  talkUp(29, 16, function() return sw(0x02F4) == 1 end, "Gerad at the engines (29,16)", true),
  H.advanceStory(function()
    return sw(0x00C6) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
      and bright() >= 15
  end, 60000, { playBattles = "tactical", fight = { blitz = AIR_BLADE } }),
  H.call(function()
    say("castle", "EDGAR joined, the Tentacles beaten")
    local o = H.outcomes[#H.outcomes]
    H.assertEq(o ~= nil and (o.form & 0x1FF) == TENTACLES_FORM and o.kind == "won", true,
      "the Tentacles (formation 454) were won on this attempt")
    H.assertEq(sw(0x02F4), 1, "Edgar's joining ran ($02F4, :15934)")
    H.assertEq(sw(0x00C6), 1, "the Tentacles are beaten ($00C6, :16121)")
    H.assertEq(inParty(EDGAR), true, "EDGAR is in the party")
    H.assertEq(level(EDGAR) >= 28, true, "EDGAR joined at max(28, the average) (norm_lvl)")
    H.log(string.format("[castle] EDGAR's kit from the game's Optimum: %s", kit(EDGAR)))
    H.assertEq(H.weaponElement(H.readByte(c(EDGAR, 0x1F))), 0, "EDGAR's Optimum blade carries no element")
  end),
  checkOutcomes("the Tentacles"),

  -- ---- after the fight: care, the kits back, EDGAR dressed ------------------------------------
  H.fieldCare({ tag = "after the Tentacles" }),
  H.equipKit(EDGAR, { { 4, JEWEL_RING }, { 5, STAR_PENDANT } }, { tag = "EDGAR relics" }),
  peaceRings("after the Tentacles"),
  backGuard("after the Tentacles"),
  H.equipKit(CELES, { { 0, ENHANCER }, { 1, THUNDERBLADE } }, { tag = "CELES: the ThunderBlade back" }),
  H.equipKit(SABIN, { { 0, FIRE_KNUCKLE }, { 1, FIRE_KNUCKLE } }, { tag = "SABIN: the Fire Knuckles back" }),
  H.equipEsper(function() return (H.readByte(0x1850 + EDGAR) >> 3) & 3 end, RAMUH,
    { tag = "RAMUH -> EDGAR" }),
  H.call(function()
    say("castle", "dressed: CELES " .. kit(CELES) .. ", SABIN " .. kit(SABIN) .. ", EDGAR " .. kit(EDGAR))
  end),

  -- ---- the Soul Sabre, behind the engines (64 (29,5) -> 65; chest bit $09B) ------------------
  H.crossDoor(29, 5, 65, 68, 16, "behind the engines 64(29,5)->65(68,16)", { fight = CAVE_FIGHT }),
  H.openChest({ stand = { 68, 11 }, face = "up", bit = 0x09B, what = "Soul Sabre", item = SOUL_SABRE,
    nav = { fight = CAVE_FIGHT } }),
  H.navTo(68, 16, { maxFrames = 3000, playBattles = "tactical", fight = CAVE_FIGHT }),
  (function()
    return H.seqStep({
      H.driveUntil(function() return map() == MAP_ENGINE end, 600, { H.hold({ "down" }) }, "back to the engine room"),
      H.release(),
    })
  end)(),
  control("the engine room again"),

  -- ---- the way back to basement 1's engineer ---------------------------------------------------
  -- the reverse of the way in: 64 (29,21) -> 62 (8,8), (8,18) -> 63 (84,5),
  -- 63's stairs (87,5) -> (56,14), (53,5) -> 62 (13,7), (13,12) -> 61 (3,36)
  walkInto(29, 21, MAP_B2, "the engine room -> basement 2"),
  control("basement 2 (engine-room floor)"),
  peaceRings("the way back: basement 2", CAVE_HANDS),
  walkInto(8, 18, MAP_B3, "basement 2 -> basement 3's chest room"),
  control("basement 3's chest room"),
  peaceRings("the way back: basement 3", CAVE_HANDS),
  -- (81,5) -> (44,14) and on through (47,8) is a pocket of basement 2
  -- whose only way on is back to basement 3 (measured: from 62 (3,12) no
  -- path to (13,12) off its (2,13) door); the way to basement 1 is the
  -- east stairs (87,5) -> (56,14) and (53,5) -> 62 (13,7)
  H.crossDoor(87, 5, MAP_B3, 56, 14, "basement 3's stairs 63(87,5)->63(56,14)", { fight = CAVE_FIGHT }),
  H.crossDoor(53, 5, MAP_B2, 13, 7, "basement 3's stairs 63(53,5)->62(13,7)", { fight = CAVE_FIGHT }),
  control("basement 2"),
  peaceRings("the way back: basement 2's west", CAVE_HANDS),
  -- basement 2's other exits are on the way: a plan through (2,13) is back
  -- in basement 3 (measured: `no path (46,9)->(13,12)`)
  walkInto(13, 12, MAP_B1, "basement 2 -> basement 1", B2_EXITS),
  control("basement 1"),
  H.call(function() say("castle", "back in basement 1") end),
  -- the engineer's trigger (5,35): with $00C6 set, "It's been fixed!
  -- Next stop, the surface!" (_ca69fd)
  H.navTo(5, 35, { maxFrames = 6000, playBattles = "tactical", fight = CAVE_FIGHT,
    arrive = function() return sw(0x00C7) == 1 or H.eventRunning() end }),
  H.advanceStory(function()
    return sw(0x00C7) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
      and bright() >= 15
  end, 12000, { playBattles = "tactical", fight = CAVE_FIGHT }),
  H.call(function()
    say("castle", "the castle has surfaced")
    H.assertEq(sw(0x00C7), 1, "the castle surfaced ($00C7, _ca69fd)")
    H.assertEq(sw(0x0106), 1, "the castle stands on the world map by South Figaro ($0106)")
  end),
  checkOutcomes("the way out"),
  -- out of the Muddle: the usual relics back before the save
  usualRelics("out of the cave", CAVE_HANDS),
  H.call(function()
    for _, m in ipairs(MEMBERS) do
      H.assertEq(wearsPeace(m[1]) or wearsBackGuard(m[1]), false,
        m[2] .. " leaves the cave in the usual relics, no Peace Ring or Back Guard")
    end
  end),

  -- ---- out of the castle, and the save ------------------------------------------------------------
  -- 61's stairs (11,32) -> the lower hall 59 (10,48), its stairs (12,50) ->
  -- the castle's court 55 (28,40), and out by the south row (y=43, map 511:
  -- the parent tile the surfacing set, world (81,85))
  walkInto(11, 32, 59, "basement 1 -> the lower hall"),
  walkInto(12, 50, MAP_CASTLE, "the lower hall -> the castle"),
  H.call(function() say("castle", "in the castle") end),
  H.navTo(28, 42, { maxFrames = 6000, playBattles = "tactical", fight = CAVE_FIGHT }),
  H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ "down" }) }, "out of Figaro Castle to the world"),
  H.release(),
  (function()
    local n = 0
    return H.withReset(H.waitUntil(function()
      local ok = H.worldSettled() and H.worldAligned() and H.worldPassable(H.worldX(), H.worldY())
      n = ok and n + 1 or 0
      return n >= 30
    end, 2400, "back on the World of Ruin map"), function() n = 0 end)
  end)(),
  H.call(function()
    H.log(string.format("[wor] out of Figaro Castle f%d: world %d (%d,%d); %s; %s", H.frame, H.worldId(),
      H.worldX(), H.worldY(), whereLine(), supplies()))
    H.assertEq(H.worldId() == 1 and H.worldX() == SAVE_TILE[1] and H.worldY() == SAVE_TILE[2], true,
      string.format("on the World of Ruin map at (%d,%d), outside Figaro Castle", SAVE_TILE[1], SAVE_TILE[2]))
  end),
  H.saveGame({ slot = 3, tag = "wor-edgar-v1 save" }),
  H.call(function()
    H.assertSavedSlotWorld(SAVE_TILE[1], SAVE_TILE[2], "wor-edgar-v1", 3, 1)
    H.assertExitContract("wor-edgar-v1")
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the battles: %d (%s): %d won, %d the party left, %d monster escape(s)",
      seen - outcome0, table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped))
    H.log(string.format("[wor] the stretch: %s; kit CELES %s, SABIN %s, EDGAR %s; %s", whereLine(),
      kit(CELES), kit(SABIN), kit(EDGAR), supplies()))
    H.screenshot("wor_edgar")
  end),
  H.saveState("wor_edgar.mss"),
  H.logStep(function()
    return string.format("wor_edgar generated: CELES L%d, SABIN L%d and EDGAR L%d on the World of Ruin at (%d,%d), outside Figaro Castle, saved in slot 3",
      level(CELES), level(SABIN), level(EDGAR), H.worldX(), H.worldY())
  end),
})
