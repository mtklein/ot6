-- gen_wor_sabin.lua -- the World of Ruin from Tzen's door to Sabin: cold-
-- Continue the `wor-tzen-door-v1` battery (CELES alone at world (131,179),
-- one step east of Tzen's door), walk into Tzen, ride the Light of
-- Judgment, take what the town offers before the timed scene, start the
-- scene at the house where Sabin holds the roof up, go in under its 6:00
-- clock, bring the child out, ride Sabin's joining, dress him, and save on
-- the World of Ruin map outside Tzen: the `wor-sabin-v1` battery.
-- Generates wor_sabin.mss, and its capture run (OT6_CAPTURE_SRM) cuts
-- `wor-sabin-v1`.  docs/design/route-wor-sabin.md has the plan (sections
-- 2.4-2.7, 3) and what this measured (section 11).
--
-- The route:
--   1. Into Tzen by its door (130,179) and up the street onto the Light of
--      Judgment's trigger (22,25)/(23,25), which every way in crosses.
--      After it the bounce at (22,28)/(23,28) keeps the party in town until
--      Sabin joins (section 2.4): this segment is committed from here.
--   2. The prep, with no clock running yet: the Seraphim seller's 10 GP
--      stone (a person buys it), the item shop only when a supply is under
--      the band, and the inn -- free while the town waits for help
--      (_cc5c8d) -- only when CELES is not whole.
--   3. (16,9), before the house: "SABIN!", and timer 0 starts: 21,600
--      frames that run through menus and battles, and whose expiry is a
--      game over (_cc592e).  From here to the house's exit no menu opens
--      (the walkers' field care stays out under a live counter,
--      H.eventTimerLive), every battle is fought by the tactical driver,
--      which reads the clock (lib/ot6.lua Driver:watchTimer: top-ups only
--      under the timed fraction, the menus pressed at the timed cadence,
--      and a run from a random battle whose measured cost plus the walk
--      still ahead the time left cannot cover -- the owner's rule for a
--      visible clock, docs/guidelines.md "Fight, don't flee"),
--      and a lone condemned CELES is played as the race it is (the Doom
--      Sting every Scorpion opens with; makePlan's solo Doom rule).  The
--      timer's remaining time is said at every step.  An expired clock is
--      a lost attempt (LOST:), retried from the checkpoint by the runner.
--      Before the clock CELES trades the Genji Glove for the Back Guard
--      (HOUSE_BACK_GUARD): no pincer, no back attack in the house.
--   4. The house, map 311: in at (123,60), up by the same-map link
--      (102,53) -> (125,23), to the child's tile (117,12), "face up and
--      hold A" (H.faceAndHoldA: _cc5958 reads facing up and A held), down
--      by (126,22) -> (103,52), and out by (123,61).  No chest: the timer
--      is the house's budget (section 11 has the margin measured).
--   5. Sabin's scene (_cc5980): stop_timer 0, "SABIN: Wait!", the
--      collapse, and SABIN into the party at max(26, CELES's level)
--      (norm_lvl), with nothing equipped.
--   6. The town again, now without a clock: the inn (350 GP) when anyone
--      is short, the item shop at the band, CELES's Genji Glove and blades
--      back on, and SABIN dressed from the
--      weapon and armor shops and the bag: two Fire Knuckles on the bag's
--      second Genji Glove, the Tiger Mask, the Power Sash, the Black Belt,
--      and IFRIT.
--   7. Out by the south edge to the World of Ruin map, (131,179), and the
--      real Save UI into slot 3.
-- Every battle's [outcome] is asserted said, judged on the battle's own
-- end reading, and paid as due (as gen_wor_tzen_door does).
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN = 6, 5
local IFRIT, SRAPHIM = 1, 21                        -- esper indices ($1A69 bits)
local FIRE_KNUCKLE, TIGER_MASK, POWER_SASH = 0x57, 0x77, 0x90
local GENJI, BLACK_BELT, BACK_GUARD, JEWEL_RING = 0xD1, 0xD5, 0xE1, 0xB5
local BLIZZARD, THUNDERBLADE = 0x0E, 0x0F
-- The house's relic (a lever; route-wor-sabin.md 11 has the A/B): the
-- Back Guard takes the Genji Glove's slot from before the clock until
-- Sabin has joined.  A solo CELES cannot flee a pincer, and in one her
-- back row does not halve the Scorpions' blows and each lands from
-- behind: 177-186 a hit against about 60 in a normal layout, and a
-- pincered Scorpion trio killed her from 793 HP in 1592 ticks (the lab's
-- timer-rules-off arm, build/attempts/wt/wor-sabin/lab/ab_off/k0_s0.log).
-- ChooseBattleType (battle_main.asm @2e3a) drops pincers and back attacks
-- with it worn.  The price is the Genji pair: one hand chips one of a
-- Scorpion's two shields a swing, so a Scorpion takes a boosted Fight or
-- two turns instead of one unboosted, and the house's fights run about
-- a thousand frames longer (the A/B in section 11: exit margins 4099-11730
-- frames against 7362-14076).  The Jewel Ring stays: the HermitCrab's Rock
-- answers even its own killing blow once one body is left, and a statue is
-- a lost fight alone.
local HOUSE_BACK_GUARD = true
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local MAP_TZEN, MAP_HOUSE = 305, 311
local MAP_ITEMSHOP, MAP_INN, MAP_WEAPON, MAP_ARMOR = 307, 308, 309, 310
local SHOP_ITEMS, SHOP_WEAPON, SHOP_ARMOR = 54, 52, 53
local TZEN_DOOR = { 130, 179 }                      -- ShortEntrance map 1 -> 305 (23,29)
local SAVE_TILE = { 131, 179 }                      -- where Tzen's exit returns the party
-- the house (docs/design/route-wor-sabin.md 3.2): the same-map links and
-- the child's trigger
local HOUSE_IN = { 123, 60 }
local LINK_UP, LINK_UP_TO = { 102, 53 }, { 125, 23 }
local CHILD = { 117, 12 }
local LINK_DOWN, LINK_DOWN_TO = { 126, 22 }, { 103, 52 }
-- the supply band (guidelines "Supply band"; gen_wor_tzen_door's numbers):
-- no Tonic seller on the stretch, so Potions carry the combat band plus
-- the plains' measured field care
local FIELD_CARE_POTIONS = 6
local HOUSE_FRAMES = 21600                          -- start_timer 0, 21600 (:90010)
-- What a house fight costs of the clock, for the driver's run rule (lib/
-- ot6.lua Driver:watchTimer; owner, 2026-09-28, docs/guidelines.md "Fight,
-- don't flee": inside a visible clock, run from a random battle the time
-- left cannot cover): the worst of 53 house fights under draw variation,
-- 2197-4151 frames, mean 3526 (build/attempts/wt/wor-sabin/lab/var-final/,
-- "the battle took N frames of it").
local HOUSE_FIGHT_COST = 4151
-- The house's legs in order, with the steps each walks when taken whole
-- (the navigator's own plans: `nav: planned 44 steps from (123,60)`, 26
-- from (125,23), 27 from (117,12), 43 from (103,52); build/attempts/wt/
-- wor-sabin/lab/ws/lab3b.log), then the one step out.  A step costs about
-- 17 frames (44 steps in 731, var-final/k2_s0.log), the child's scene about
-- 150, and each same-map link about 40.
local HOUSE_LEGS = { { 102, 53, 44 }, { 117, 12, 26 }, { 126, 22, 27 }, { 123, 60, 43 } }
local STEP_FRAMES, CHILD_FRAMES, LINK_FRAMES = 17, 150, 40

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function esperHeld(i) return (H.readByte(0x1A69 + (i >> 3)) >> (i & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch or CELES, 8)) end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end
local function timer0() return H.readWord(0x1189) end
local function clock()
  return H.sceneTimerStr() or string.format("no scene timer (timer 0 counter %d)", timer0())
end
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.gil())
end
local function member(ch, name)
  return string.format("%s L%d HP %d/%d MP %d/%d status1 $%02X", name, level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine()
  local s = member(CELES, "CELES")
  if inParty(SABIN) then s = s .. "; " .. member(SABIN, "SABIN") end
  return s
end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies(), clock()))
end
local function whole(ch)
  return H.charHp(ch) == H.charMaxHp(ch) and H.charMp(ch) == H.charMaxMp(ch)
    and H.charStatus1(ch) == 0
end
-- #411: no Tonic seller -- see H.careStockPotions
local function potionBand() return H.careStockPotions(level(), { spend = FIELD_CARE_POTIONS }) end
local function short()
  return H.invCountOf(POTION) < potionBand() or H.invCountOf(FENIX) < level()
end

-- ---- the clock ------------------------------------------------------------
-- Timer 0 counts while the scene waits for the child: from (16,9)
-- ($028C set) until the party is out of the house with her, when Sabin's
-- scene stops it (stop_timer 0, :90071, well before it sets $028A at
-- :90262 -- so the watch ends at the house's exit, not at $028A).  A
-- counter at 0 before then is the collapse (_cc592e: "I'm losing my
-- grip...", GameOver): a lost attempt, said with what was left undone.
local clockOn = false
local lowest = nil                                  -- the lowest HP the house saw
local function guard()
  if clockOn and timer0() == 0 then
    error(string.format("LOST: the house's timer ran out at f%d on map %d (%d,%d) -- child %s; %s",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x028B) == 1 and "rescued" or "not rescued",
      whereLine()), 0)
  end
  -- her HP as the screen shows it: the battle's own table in a fight (she
  -- is entity 0, alone), her record on the field
  local hp = H.charHp(CELES)
  if H.battleLoadStarted() then
    local b, mx = H.readWord(0x3BF4), H.readWord(0x3C1C)
    hp = (mx > 0 and b <= mx) and b or hp
  end
  if clockOn and (lowest == nil or hp < lowest.hp) then
    lowest = { hp = hp, frame = H.frame, timer = timer0() }
  end
end

-- ---- the battles --------------------------------------------------------
-- Every battle the walkers fight ends in an [outcome] (M.battleOutcome);
-- each one's reward is asserted paid as the engine's own arithmetic says,
-- and the count of [outcome] lines is asserted against the runner's own
-- battle count (H.absorbGuardBattles), so a battle whose outcome was never
-- said is a red, not a silent gap.  Inside the house each battle's end
-- also carries the timer (the driver's [timer] line; rec.timerLeft).
local seen, tally, outcome0, battles0
local function tallyReset()
  tally = { won = 0, ["party left"] = 0, lost = 0, escaped = 0, forms = {}, order = {}, house = {} }
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
      if o.timerLeft then
        tally.house[#tally.house + 1] = string.format("%s %s", k, H.clockStr(o.timerLeft))
      end
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    if #H.outcomes > seen then
      seen = #H.outcomes
      H.log(string.format("[route] %s: %d battle(s) so far, %d [outcome] line(s) (%d won, %d the "
        .. "party left, %d monster escape(s)); %s; %s; %s", what, H.absorbGuardBattles - battles0,
        seen - outcome0, tally.won, tally["party left"], tally.escaped, whereLine(), supplies(), clock()))
    end
  end)
end

-- hold a direction onto an exit trigger until the map changes, paging any
-- dialog on the way (a shop's and the inn's way out)
local function holdOut(dir, dst, what)
  local hb = 0
  return H.seqStep({
    H.driveUntil(function() return map() == dst end, 900, {
      H.call(function()
        hb = hb + 1
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        H.setPad({ [dir] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(function()
      return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, what .. ": control", 5),
    H.waitFrames(20),
  })
end

-- Tzen's item shop (door (21,21) -> 307 (34,20), keeper (34,15), shop 54,
-- out by (34,21)), taken only when a supply is under the band: Potions to
-- the level x 1.5 plus the field care, Fenix Downs to the level.  Tzen
-- sells no Remedy or Tonic.
local function itemShop(what)
  local gil0 = 0
  return H.cond(function()
    local s = short()
    if not s then
      H.log(string.format("[tzen] %s: supplies at the band (potion %d >= %d, fenix %d >= %d): "
        .. "no shop", what, H.invCountOf(POTION), potionBand(), H.invCountOf(FENIX), level()))
    end
    return s
  end, {
    H.crossDoor(21, 21, MAP_ITEMSHOP, 34, 20, "Tzen item shop door 305(21,21)->307(34,20)"),
    H.shopTalk(34, 15, "Tzen item shop"),
    H.call(function()
      gil0 = H.gil()
      H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 54 ($0201)")
    end),
    H.buyItem(POTION, function() return math.max(0, potionBand() - H.invCountOf(POTION)) end,
      "POTION to the band"),
    H.buyItem(FENIX, function() return math.max(0, level() - H.invCountOf(FENIX)) end,
      "FENIX DOWN to the level"),
    H.call(function()
      H.log(string.format("[tzen] %s: bought: %s (spent %d GP)", what, supplies(), gil0 - H.gil()))
      H.assertEq(H.invCountOf(POTION) >= potionBand(), true, "Potions at the band")
      H.assertEq(H.invCountOf(FENIX) >= level(), true, "Fenix Downs at about the level")
    end),
    H.shopClose("Tzen item shop"),
    H.bagArrange({ POTION, FENIX, REMEDY, SOFT, TONIC }, { tag = "bag: combat items on top (Tzen)" }),
    H.navTo(34, 20, { maxFrames = 6000, playBattles = "tactical" }),
    holdOut("down", MAP_TZEN, "the item shop's (34,21) trigger -> Tzen 305"),
  }, {})
end

-- Tzen's inn (door (28,18) -> 308 (18,57), keeper (14,53), talk spot
-- (14,55) facing up, out by (18,58)), when anyone in the party is short.
-- While the town waits for help it is free (_cc5c8d: RestoreParty, no
-- choice); after Sabin joins it is 350 GP a night.
local function inn(what, price)
  return H.cond(function()
    local s = not whole(CELES) or (inParty(SABIN) and not whole(SABIN))
    if not s then H.log(string.format("[tzen] %s: the party is whole; no inn", what)) end
    return s
  end, {
    H.crossDoor(28, 18, MAP_INN, 18, 57, "Tzen inn door 305(28,18)->308(18,57)"),
    H.innRest({ spot = { 14, 55 }, face = "up", price = price, tag = "Tzen inn (" .. what .. ")" }),
    H.navTo(18, 57, { maxFrames = 6000, playBattles = "tactical" }),
    holdOut("down", MAP_TZEN, "the inn's (18,58) trigger -> Tzen 305"),
  }, {})
end

-- The walk still ahead to the house's exit, in frames, for the run rule:
-- the current leg's remaining steps (a plan from where the party stands,
-- re-read whenever it stands somewhere new on the house's field) plus the
-- later legs whole, the child's scene if she is not rescued yet, and the
-- links still to cross.
local legNo, ahead, aheadAt = 1, 0, nil
local function aheadFrames()
  if map() == MAP_HOUSE and not H.battleLoadStarted() and H.hasControl() and H.tileAligned() then
    local key = H.fieldX() * 256 + H.fieldY() + legNo * 65536
    if key ~= aheadAt then
      aheadAt = key
      local leg = HOUSE_LEGS[legNo]
      local p = leg and H.bfsPath(leg[1], leg[2]) or nil
      local steps = p and #p or (leg and leg[3] or 0)
      for i = legNo + 1, #HOUSE_LEGS do steps = steps + HOUSE_LEGS[i][3] end
      local links = legNo <= 1 and 2 or (legNo <= 3 and 1 or 0)
      ahead = (steps + 1) * STEP_FRAMES + links * LINK_FRAMES
        + (sw(0x028B) == 0 and CHILD_FRAMES or 0)
    end
  end
  return ahead
end

-- a walk inside the timed scene: the tactical driver fights what comes
-- (and runs from what the clock cannot cover: HOUSE_FIGHT_COST, the walk
-- ahead), and the clock is watched every frame (guard) and said at the
-- leg's end
local function houseLeg(n, what, arrive)
  local x, y = HOUSE_LEGS[n][1], HOUSE_LEGS[n][2]
  return H.seqStep({
    H.call(function() legNo, aheadAt = n, nil end),
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical",
      fight = { timedFightCost = HOUSE_FIGHT_COST, timedWalk = function() return aheadFrames() end },
      arrive = function() guard(); aheadFrames(); return arrive ~= nil and arrive() or false end }),
    H.release(),
    H.waitUntil(function() guard(); return H.hasControl() and H.tileAligned() end, 900,
      what .. ": control", 2),
    checkOutcomes(what),
    H.call(function() say("house", what) end),
  })
end

local houseIn, houseOut = nil, nil
H.run({ maxFrames = 200000 }, {
  -- ---- 0. cold Continue of wor-tzen-door-v1 ---------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the World of Ruin outside Tzen", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    H.assertEntryContract("wor-tzen-door-v1")
    tallyReset()
    clockOn, lowest, houseIn, houseOut = false, nil, nil, nil
    legNo, ahead, aheadAt = 1, 0, nil
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s, kit %s; %s", H.frame, H.worldId(),
      H.worldX(), H.worldY(), whereLine(), kit(CELES), supplies()))
  end),

  -- ---- 1. into Tzen, and the Light of Judgment ---------------------------------
  H.worldNavTo(TZEN_DOOR[1], TZEN_DOOR[2], { maxFrames = 20000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  checkOutcomes("the walk to Tzen's door"),
  H.waitUntil(function()
    return map() == MAP_TZEN and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "Tzen: control", 5),
  H.waitFrames(20),
  H.call(function()
    say("tzen", "in town")
    H.assertEq(sw(0x027D), 0, "the Light of Judgment not yet seen ($027D)")
  end),
  H.navTo(23, 25, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return sw(0x027D) == 1 end }),
  H.advanceStory(function()
    return sw(0x027D) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 12000, {}),
  H.waitFrames(20),
  H.call(function()
    say("tzen", "after the Light of Judgment")
    H.assertEq(sw(0x027D), 1, "the Light of Judgment ran ($027D, _cc583e)")
    H.assertEq(sw(0x066D), 1, "the child is shown in the house ($066D)")
    H.assertEq(H.eventTimerLive(), false, "no clock runs before (16,9)")
  end),

  -- ---- 2. the prep, before the clock --------------------------------------------
  H.cond(function() return sw(0x027C) == 0 end, {
    H.talkToObj(16, "the Seraphim seller (NPC_1)"),
    H.dialogChoice(0, { what = "the stone for 10 GP: Yes (dlg $0622)", maxFrames = 3000 }),
    H.advanceStory(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {}),
    H.call(function()
      say("tzen", "bought the stone")
      H.assertEq(sw(0x027C), 1, "the stone sold ($027C, _cc5e13)")
      H.assertEq(esperHeld(SRAPHIM), 1, "SERAPHIM held ($1A69 bit 21)")
    end),
  }, {}),
  itemShop("before the house"),
  inn("before the house", 0),
  H.cond(function() return HOUSE_BACK_GUARD end, {
    -- leaving the Relic screen runs the game's own Optimum on the hands:
    -- the Break Blade and a shield (build/attempts/wt/wor-sabin/lab/ws/lab_bg.log: after=11 5C)
    -- through the relic rule over the kit (H.relicKit), Petrify the threat
    -- (the HermitCrab's Rock): the Back Guard (unranked) stays put, the other
    -- slot goes to the guard covering Petrify and the most else
    H.relicKit(CELES, "CELES", { [4] = BACK_GUARD }, { tag = "CELES: the Back Guard for the house",
      threats = { s1 = 0x40, s2 = 0x00 } }),
  }, {}),
  H.call(function()
    say("tzen", "ready for the house, kit " .. kit(CELES))
    H.assertEq(whole(CELES), true, "CELES goes into the house whole")
    local function guards(id) return id == 0xFF and 0 or H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + 6) end
    H.assertEq((guards(H.readByte(c(CELES, 0x23))) | guards(H.readByte(c(CELES, 0x24)))) & 0x40, 0x40,
      "a relic CELES wears guards Petrify (the HermitCrab's Rock petrifies, and a statue is a lost fight alone)")
    if HOUSE_BACK_GUARD then
      H.assertEq(H.readByte(c(CELES, 0x23)) == BACK_GUARD or H.readByte(c(CELES, 0x24)) == BACK_GUARD, true,
        "CELES wears the Back Guard (no pincer, no back attack in the house)")
    end
  end),

  -- ---- 3. the clock starts at (16,9) ---------------------------------------------
  H.navTo(16, 9, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return sw(0x028C) == 1 or timer0() ~= 0 end }),
  H.advanceStory(function()
    return sw(0x028C) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, {}),
  H.call(function()
    local t = H.sceneTimer()
    H.assertEq(t ~= nil and t.slot == 0, true, "timer 0 runs through menus and battles (_cc58ff, :90010)")
    H.assertEq(t.endsBattle, true, "timer 0's expiry ends a battle (BANQUET)")
    H.assertEq(t.frames <= HOUSE_FRAMES and t.frames > HOUSE_FRAMES - 600, true,
      "timer 0 has just started from 21600")
    clockOn = true
    say("house", "the clock starts")
  end),
  H.crossDoor(16, 7, MAP_HOUSE, HOUSE_IN[1], HOUSE_IN[2], "the house door 305(16,7)->311(123,60)"),
  H.call(function()
    guard()
    houseIn = timer0()
    say("house", "in the house")
  end),

  -- ---- 4. the house ---------------------------------------------------------------
  houseLeg(1, "up by the link (102,53) -> (125,23)",
    function() return H.fieldY() < 40 end),
  H.call(function()
    H.assertEq(H.fieldX() == LINK_UP_TO[1] and H.fieldY() == LINK_UP_TO[2], true,
      "upstairs at (125,23)")
  end),
  houseLeg(2, "at the child's tile (117,12)"),
  H.faceAndHoldA("up", function() guard(); return sw(0x028B) == 1 end, 3000,
    "face up and hold A on (117,12) -- _cc5958"),
  H.release(),
  H.advanceStory(function()
    guard()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 3000, {}),
  H.call(function()
    H.assertEq(sw(0x028B), 1, "the child rescued ($028B, _cc5958)")
    H.assertEq(sw(0x066D), 0, "the child is hidden ($066D)")
    say("house", "the child is with her")
  end),
  houseLeg(3, "down by the link (126,22) -> (103,52)",
    function() return H.fieldY() > 40 end),
  H.call(function()
    H.assertEq(H.fieldX() == LINK_DOWN_TO[1] and H.fieldY() == LINK_DOWN_TO[2], true,
      "downstairs at (103,52)")
  end),
  houseLeg(4, "back at the door (123,60)"),
  H.driveUntil(function() guard(); return map() ~= MAP_HOUSE end, 900,
    { H.hold({ "down" }) }, "out by the exit (123,61)"),
  H.release(),
  H.call(function()
    houseOut = timer0()
    clockOn = false
    H.log(string.format("[house] f%d out of the house with the child: timer 0 at %s (%d frames) of "
      .. "6:00, %d frames spent inside (%s at the door in); lowest CELES HP inside %d (f%d, timer %s); "
      .. "house battles: %s; %s", H.frame, H.clockStr(houseOut), houseOut, houseIn - houseOut,
      H.clockStr(houseIn), lowest and lowest.hp or -1, lowest and lowest.frame or -1,
      lowest and H.clockStr(lowest.timer) or "-", #tally.house > 0 and table.concat(tally.house, ", ")
      or "none", whereLine()))
  end),

  -- ---- 5. Sabin joins ---------------------------------------------------------------
  H.advanceStory(function()
    return sw(0x028A) == 1 and map() == MAP_TZEN and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting()
  end, 20000, {}),
  H.waitFrames(30),
  H.call(function()
    say("tzen", "SABIN joined")
    H.assertEq(sw(0x028A), 1, "Sabin joined ($028A, :90262)")
    H.assertEq(sw(0x02F5), 1, "the joining finished ($02F5, :90282)")
    H.assertEq(H.eventTimerLive(), false, "timer 0 stopped (stop_timer 0, :90071)")
    H.assertEq(inParty(SABIN) and inParty(CELES), true, "SABIN and CELES in the party")
    H.assertEq(level(SABIN), math.max(26, level(CELES)), "SABIN joined at max(26, CELES's level) (norm_lvl)")
    H.assertEq(kit(SABIN):sub(4), "FF FF FF FF FF FF", "SABIN joined with nothing equipped")
  end),

  -- ---- 6. the town again: inn, shops, SABIN dressed ------------------------------------
  inn("after the house", 350),
  itemShop("after the house"),
  H.crossDoor(6, 22, MAP_WEAPON, 39, 50, "Tzen weapon shop door 305(6,22)->309(39,50)"),
  H.shopTalk(38, 43, "Tzen weapon shop"),
  H.call(function() H.assertEq(H.shopId(), SHOP_WEAPON, "the counter opened shop 52 ($0201)") end),
  H.buyItem(FIRE_KNUCKLE, function() return math.max(0, 2 - H.invCountOf(FIRE_KNUCKLE)) end,
    "FIRE KNUCKLE x2 (a pair on the Genji Glove)"),
  H.shopClose("Tzen weapon shop"),
  H.navTo(39, 50, { maxFrames = 6000, playBattles = "tactical" }),
  holdOut("down", MAP_TZEN, "the weapon shop's (39,51) trigger -> Tzen 305"),
  H.crossDoor(8, 17, MAP_ARMOR, 56, 51, "Tzen armor shop door 305(8,17)->310(56,51)"),
  H.shopTalk(58, 45, "Tzen armor shop"),
  H.call(function() H.assertEq(H.shopId(), SHOP_ARMOR, "the counter opened shop 53 ($0201)") end),
  H.buyItem(TIGER_MASK, function() return math.max(0, 1 - H.invCountOf(TIGER_MASK)) end, "TIGER MASK"),
  H.buyItem(POWER_SASH, function() return math.max(0, 1 - H.invCountOf(POWER_SASH)) end, "POWER SASH"),
  H.shopClose("Tzen armor shop"),
  H.navTo(56, 51, { maxFrames = 6000, playBattles = "tactical" }),
  holdOut("down", MAP_TZEN, "the armor shop's (56,52) trigger -> Tzen 305"),
  -- CELES's own kit back (gen_wor_tzen_door's: the Genji Glove, the
  -- ThunderBlade in the left hand, the Blizzard in the right), then
  -- SABIN's relics first: the second Fire Knuckle needs the Genji Glove on
  H.cond(function() return HOUSE_BACK_GUARD end, {
    H.relicKit(CELES, "CELES", { [4] = GENJI }, { tag = "CELES: the Genji Glove back",
      threats = { s1 = 0x40, s2 = 0x00 } }),
    H.equipKit(CELES, { { 1, THUNDERBLADE }, { 0, BLIZZARD } }, { tag = "CELES blades" }),
  }, {}),
  H.equipKit(SABIN, { { 4, GENJI }, { 5, BLACK_BELT } }, { tag = "SABIN relics" }),
  H.equipKit(SABIN, { { 0, FIRE_KNUCKLE }, { 1, FIRE_KNUCKLE }, { 2, TIGER_MASK }, { 3, POWER_SASH } },
    { tag = "SABIN gear" }),
  H.equipEsper(function() return (H.readByte(0x1850 + SABIN) >> 3) & 3 end, IFRIT,
    { tag = "IFRIT -> SABIN" }),
  H.call(function()
    say("tzen", "SABIN dressed")
    H.assertEq(kit(SABIN), string.format("%02X %02X %02X %02X %02X %02X %02X", IFRIT, FIRE_KNUCKLE,
      FIRE_KNUCKLE, TIGER_MASK, POWER_SASH, GENJI, BLACK_BELT), "SABIN wears IFRIT and his kit")
    H.assertEq(kit(CELES):sub(1, 17), "06 0E 0F 76 8F D1", "CELES wears the stretch's kit again: MADUIN, "
      .. "Blizzard + ThunderBlade, Gold Helmet, Gold Armor, Genji Glove")
    -- the other relic is the relic rule's (H.relicKit above): the Jewel
    -- Ring, or a guard covering Petrify and more (a Ribbon)
    local r5 = H.readByte(c(CELES, 0x24))
    H.assertEq(r5 ~= 0xFF and (H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + r5 * 30 + 6) & 0x40) ~= 0, true,
      string.format("CELES's other relic $%02X guards Petrify", r5))
  end),

  -- ---- 7. out to the World of Ruin map, and the save ------------------------------------
  -- the long exit (13,31) len 18 -> map 511: the parent map, where the
  -- party came in; (22,28)/(23,28) no longer bounce with $028A set
  H.navTo(23, 30, { maxFrames = 6000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ "down" }) }, "out of Tzen by the south edge"),
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
    H.log(string.format("[wor] out of Tzen f%d: world %d (%d,%d); %s; %s", H.frame, H.worldId(),
      H.worldX(), H.worldY(), whereLine(), supplies()))
    H.assertEq(H.worldId() == 1 and H.worldX() == SAVE_TILE[1] and H.worldY() == SAVE_TILE[2], true,
      "on the World of Ruin map at (131,179), outside Tzen")
  end),
  H.saveGame({ slot = 3, tag = "wor-sabin-v1 save" }),
  H.call(function()
    H.assertSavedSlotWorld(SAVE_TILE[1], SAVE_TILE[2], "wor-sabin-v1", 3, 1)
    H.assertExitContract("wor-sabin-v1")
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the stretch: %d battles (%s): %d won, %d the party left, %d monster "
      .. "escape(s); the house: in at %s, out at %s (%d frames of 6:00 left), lowest CELES HP %d; %s; %s",
      seen - outcome0, table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped,
      H.clockStr(houseIn), H.clockStr(houseOut), houseOut, lowest and lowest.hp or -1, whereLine(),
      supplies()))
    H.screenshot("wor_sabin")
  end),
  H.saveState("wor_sabin.mss"),
  H.logStep(function()
    return string.format("wor_sabin generated: CELES L%d and SABIN L%d on the World of Ruin at (%d,%d), outside Tzen, saved in slot 3",
      level(CELES), level(SABIN), H.worldX(), H.worldY())
  end),
})
