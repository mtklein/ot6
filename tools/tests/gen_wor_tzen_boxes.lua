-- gen_wor_tzen_boxes.lua -- a branch beside gen_wor_sabin (#487, the monster boxes; wor-coverage.md section 12):
-- cold-Continue the `wor-tzen-door-v1` battery (CELES alone one step east of Tzen's door), into Tzen, the Light
-- of Judgment, the item shop and the inn as the line takes them, the Back Guard on, the house's 6:00 clock at
-- (16,9), and the house (map 311) by its two monster boxes: the one downstairs (102,49), up by the link, the child
-- (117,12), the one upstairs (111,12), down by the link and out; then Sabin's joining.  Each box is four Pm
-- Stalkers (event group 150, formation 211, L26), an event battle the clock runs through and a game over when
-- lost (TreasureMonster: _ca5ea9).  A box is opened when the time left covers its fight (BOX_FIGHT_COST), the
-- walk still ahead and a run from the random battles that walk can expect (BOX_RUN_COST each, one per BOX_STEPS
-- steps), as a player watching the clock would; otherwise it is said and left.  The line's six item
-- chests are the line's (gen_wor_sabin); this walk takes the boxes instead.  No leg boots what it leaves (the
-- state `wor_tzen_boxes`): the boxes pay 1,032 XP a box and no item, which the main line does not need, and the
-- house collapses behind Sabin's joining ($028A: _cc56da no longer draws it), so there is no later visit.
-- Every battle's [outcome] is asserted said, judged on the battle's own end reading, and paid as due.
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN = 6, 5
local BACK_GUARD = 0xE1
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local MAP_TZEN, MAP_HOUSE, MAP_ITEMSHOP, MAP_INN = 305, 311, 307, 308
local SHOP_ITEMS = 54
local TZEN_DOOR = { 130, 179 }
local HOUSE_IN = { 123, 60 }
local LINK_UP_TO, LINK_DOWN_TO = { 125, 23 }, { 103, 52 }
local FIELD_CARE_POTIONS = 6
local HOUSE_FRAMES = 21600
-- the house's random fights, for the driver's run rule (gen_wor_sabin's measure)
local HOUSE_FIGHT_COST = 4151
-- What a box's fight costs of the clock, from the frames left when the party weighs it to the frames left when
-- its fight is won (the box's window, the battle, its close): the worst of 49 box fights, 3614-5563 frames
-- (build/attempts/wt/v038-monster-boxes/tzen/: boxcost_tz.txt, 46 with the cost at 6000, "min 3614, median 4259,
-- max 5211"; tz2_k6_*, three with it at 5211, one of them 5563).  And the walk after it can meet a random
-- battle the clock no longer covers, which the run rule runs from: the longest run of the house's was 873 ticks
-- (the same sweeps' "PARTY LEFT" lines),
-- 1200 frames with the battle's open and close; one is expected every 45 steps (the house's rate: $0070 a step
-- halved, a battle every 44.8 steps on average, route_data.py map 311).  At the cost alone (5211 and no run) the
-- box upstairs was opened with 6938 frames left and the clock ran out at the door after a run (tz2_k6_s0: "LOST:
-- the house's timer ran out at f42939 on map 305 (15,9) -- child rescued").
local BOX_FIGHT_COST, BOX_RUN_COST, BOX_STEPS = 5563, 1200, 45
local BOX_FORM = 211
-- the boxes (TreasureProp 311; route-wor-sabin.md 3.4): the stand below each, faced up
local BOXES = {
  low = { stand = { 102, 50 }, face = "up", bit = 144, what = "the box downstairs (102,49)" },
  high = { stand = { 111, 13 }, face = "up", bit = 148, what = "the box upstairs (111,12)" },
}
-- the walk's stops in order, with the steps each walks from the one before (route_data.py field-path 311)
local HOUSE_LEGS = {
  { 102, 50, 43, box = "low" }, { 102, 53, 7, link = true }, { 117, 12, 26, child = true },
  { 111, 13, 7, box = "high" }, { 126, 22, 24, link = true }, { 123, 60, 43 },
}
local STEP_FRAMES, CHILD_FRAMES, LINK_FRAMES = 17, 150, 40

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch or CELES, 8)) end
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
  return H.charHp(ch) == H.charMaxHp(ch) and H.charMp(ch) == H.charMaxMp(ch) and H.charStatus1(ch) == 0
end
local function potionBand() return H.careStockPotions(level(), { spend = FIELD_CARE_POTIONS }) end
local function short() return H.invCountOf(POTION) < potionBand() or H.invCountOf(FENIX) < level() end

-- the clock (gen_wor_sabin's guard): a counter at 0 before the exit is the collapse, a lost attempt
local clockOn = false
local function guard()
  if clockOn and timer0() == 0 then
    error(string.format("LOST: the house's timer ran out at f%d on map %d (%d,%d) -- child %s; %s",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x028B) == 1 and "rescued" or "not rescued", whereLine()), 0)
  end
end

-- every battle's [outcome] said, on its own end reading, paid as due (gen_wor_sabin's checkOutcomes)
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
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own end reading",
        what, i - outcome0, o.form & 0x1FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x1FF, o.kind))
      tally[o.kind] = (tally[o.kind] or 0) + 1
      tally.escaped = tally.escaped + #o.escaped
      local k = string.format("$%03X", o.form & 0x1FF)
      if not tally.forms[k] then tally.order[#tally.order + 1] = k end
      tally.forms[k] = (tally.forms[k] or 0) + 1
      if o.timerLeft then tally.house[#tally.house + 1] = string.format("%s %s", k, H.clockStr(o.timerLeft)) end
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    seen = #H.outcomes
  end)
end

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
    H.waitUntil(function() return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15 end,
      2400, what .. ": control", 5),
    H.waitFrames(20),
  })
end

-- the line's item shop and inn stops (gen_wor_sabin's), before the clock
local function itemShop(what)
  return H.cond(function() return short() end, {
    H.crossDoor(21, 21, MAP_ITEMSHOP, 34, 20, "Tzen item shop door 305(21,21)->307(34,20)"),
    H.shopTalk(34, 15, "Tzen item shop"),
    H.call(function() H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 54 ($0201)") end),
    H.buyItem(POTION, function() return math.max(0, potionBand() - H.invCountOf(POTION)) end, "POTION to the band"),
    H.buyItem(FENIX, function() return math.max(0, level() - H.invCountOf(FENIX)) end, "FENIX DOWN to the level"),
    H.shopClose("Tzen item shop"),
    H.bagArrange({ POTION, FENIX, REMEDY, SOFT, TONIC }, { tag = "bag: combat items on top (Tzen)" }),
    H.navTo(34, 20, { maxFrames = 6000, playBattles = "tactical" }),
    holdOut("down", MAP_TZEN, "the item shop's (34,21) trigger -> Tzen 305"),
    H.call(function() say("tzen", what .. ": the item shop") end),
  }, {})
end
local function inn(what)
  return H.cond(function() return not whole(CELES) end, {
    H.crossDoor(28, 18, MAP_INN, 18, 57, "Tzen inn door 305(28,18)->308(18,57)"),
    H.innRest({ spot = { 14, 55 }, face = "up", price = 0, tag = "Tzen inn (" .. what .. ")" }),
    H.navTo(18, 57, { maxFrames = 6000, playBattles = "tactical" }),
    holdOut("down", MAP_TZEN, "the inn's (18,58) trigger -> Tzen 305"),
  }, {})
end

-- the walk still ahead to the exit, in frames, from where the party stands (gen_wor_sabin's aheadFrames,
-- without the boxes' fights: a box is weighed when the party stands below it)
local legNo, ahead, aheadAt = 1, 0, nil
local function stepsAhead(from)
  local steps, links = 0, 0
  for i = from, #HOUSE_LEGS do
    local l = HOUSE_LEGS[i]
    steps = steps + l[3]
    if l.link then links = links + 1 end
  end
  return steps, links
end
local function walkAhead(from)
  local steps, links = stepsAhead(from)
  return steps * STEP_FRAMES + links * LINK_FRAMES + (sw(0x028B) == 0 and CHILD_FRAMES or 0)
end
local function aheadFrames()
  if map() == MAP_HOUSE and not H.battleLoadStarted() and H.hasControl() and H.tileAligned() then
    local key = H.fieldX() * 256 + H.fieldY() + legNo * 65536
    if key ~= aheadAt then
      aheadAt = key
      local leg = HOUSE_LEGS[legNo]
      local p = leg and H.bfsPath(leg[1], leg[2]) or nil
      ahead = ((p and #p or (leg and leg[3] or 0)) + 1) * STEP_FRAMES + walkAhead(legNo + 1)
        + (leg and leg.link and LINK_FRAMES or 0)
    end
  end
  return ahead
end

local boxes = {}                                    -- what each box came to: "opened" or "left"
-- a box, from the tile below it: opened when the clock covers its fight and the walk after it, its battle
-- played out by the tactical driver (an event battle: fought, never run from), then the bit and the win asserted
local function box(o, after)
  local n0
  return H.cond(function()
    local runs = stepsAhead(after) // BOX_STEPS
    local left, need = timer0(), BOX_FIGHT_COST + walkAhead(after) + runs * BOX_RUN_COST
    local go = left >= need
    H.log(string.format("[box] %s: %d frames left, its fight ~%d + %d of walk ahead + %d run(s) of %d = %d: %s",
      o.what, left, BOX_FIGHT_COST, walkAhead(after), runs, BOX_RUN_COST, need,
      go and "opened" or "LEFT SHUT (the clock cannot cover it)"))
    if not go then boxes[#boxes + 1] = o.what .. " left" end
    return go
  end, {
    H.call(function()
      H.assertEq(H.chestOpen(o.bit), false, o.what .. ": its bit " .. o.bit .. " is clear")
      n0 = #H.outcomes
    end),
    H.faceAndHoldA(o.face, function() guard(); return H.battleLoadStarted() end, 3000,
      o.what .. ": face " .. o.face .. ", A (Monster-in-a-box!, EventCmd_8e)"),
    H.release(),
    H.advanceStory(function()
      guard()
      return H.chestOpen(o.bit) and not H.battleLoadStarted() and map() == MAP_HOUSE and H.hasControl()
        and H.tileAligned() and not H.dialogWaiting()
    end, 60000, { playBattles = "tactical",
      fight = { timedFightCost = HOUSE_FIGHT_COST, timedWalk = function() return aheadFrames() end } }),
    checkOutcomes(o.what),
    H.call(function()
      H.assertEq(H.chestOpen(o.bit), true, string.format("311: %s (bit %d) is open", o.what, o.bit))
      local last = H.outcomes[#H.outcomes]
      H.assertEq(#H.outcomes > n0 and (last.form & 0x1FF) == BOX_FORM and last.kind == "won", true,
        string.format("%s: its battle (formation %d, Pm Stalker x4) was won", o.what, BOX_FORM))
      boxes[#boxes + 1] = o.what .. " opened"
      H.log(string.format("[chest] chest bit %d (%s): OPENED, formation %d won", o.bit, o.what, BOX_FORM))
      say("box", o.what .. ": won")
    end),
  }, {})
end

local function houseLeg(n, what, arrive)
  local x, y = HOUSE_LEGS[n][1], HOUSE_LEGS[n][2]
  local o = HOUSE_LEGS[n].box and BOXES[HOUSE_LEGS[n].box]
  return H.seqStep({
    H.call(function() legNo, aheadAt = n, nil end),
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical",
      fight = { timedFightCost = HOUSE_FIGHT_COST, timedWalk = function() return aheadFrames() end },
      arrive = function() guard(); aheadFrames(); return arrive ~= nil and arrive() or false end }),
    H.release(),
    H.waitUntil(function() guard(); return H.hasControl() and H.tileAligned() end, 900, what .. ": control", 2),
    checkOutcomes(what),
    o and box(o, n + 1) or H.call(function() end),
    H.call(function() say("house", what) end),
  })
end

local houseIn, houseOut = nil, nil
H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-tzen-door-v1"),
  H.call(function()
    tallyReset()
    clockOn, houseIn, houseOut, boxes = false, nil, nil, {}
    legNo, ahead, aheadAt = 1, 0, nil
    say("wor", "boot")
    H.assertEq(inParty(CELES) and not inParty(SABIN), true,
      "CELES alone in the party (gen_wor_tzen_door's save, before Sabin joins)")
  end),
  -- @@setup-end

  -- into Tzen, and the Light of Judgment
  H.worldNavTo(TZEN_DOOR[1], TZEN_DOOR[2], { maxFrames = 20000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  checkOutcomes("the walk to Tzen's door"),
  H.waitUntil(function() return map() == MAP_TZEN and H.hasControl() and H.tileAligned() and bright() >= 15 end,
    2400, "Tzen: control", 5),
  H.waitFrames(20),
  H.call(function()
    say("tzen", "in town")
    H.assertEq(sw(0x027D), 0, "the Light of Judgment not yet seen ($027D)")
    H.assertEq(sw(0x028A), 0, "the house still stands, Sabin not yet joined ($028A)")
  end),
  H.navTo(23, 25, { maxFrames = 6000, playBattles = "tactical", arrive = function() return sw(0x027D) == 1 end }),
  H.advanceStory(function()
    return sw(0x027D) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 12000, {}),
  H.waitFrames(20),
  H.call(function() H.assertEq(sw(0x027D), 1, "the Light of Judgment ran ($027D, _cc583e)") end),

  -- the prep, before the clock (the line's)
  itemShop("before the house"),
  inn("before the house"),
  H.relicKit(CELES, "CELES", { [4] = BACK_GUARD }, { tag = "CELES: the Back Guard for the house",
    threats = { s1 = 0x40, s2 = 0x00 } }),
  H.call(function()
    say("tzen", "ready for the house")
    H.assertEq(whole(CELES), true, "CELES goes into the house whole")
    H.assertEq(H.readByte(c(CELES, 0x23)) == BACK_GUARD or H.readByte(c(CELES, 0x24)) == BACK_GUARD, true,
      "CELES wears the Back Guard (no pincer, no back attack in the house)")
  end),

  -- the clock starts at (16,9)
  H.navTo(16, 9, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return sw(0x028C) == 1 or timer0() ~= 0 end }),
  H.advanceStory(function()
    return sw(0x028C) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, {}),
  H.call(function()
    local t = H.sceneTimer()
    H.assertEq(t ~= nil and t.slot == 0, true, "timer 0 runs through menus and battles (_cc58ff, :90010)")
    H.assertEq(t.frames <= HOUSE_FRAMES and t.frames > HOUSE_FRAMES - 600, true, "timer 0 has just started from 21600")
    clockOn = true
    say("house", "the clock starts")
  end),
  H.crossDoor(16, 7, MAP_HOUSE, HOUSE_IN[1], HOUSE_IN[2], "the house door 305(16,7)->311(123,60)"),
  H.call(function()
    guard()
    houseIn = timer0()
    for _, o in pairs(BOXES) do H.assertEq(H.chestOpen(o.bit), false, o.what .. " is shut (bit " .. o.bit .. ")") end
    say("house", "in the house")
  end),

  -- the house: the box downstairs, up, the child, the box upstairs, down, out
  houseLeg(1, "below the box downstairs (102,50)"),
  houseLeg(2, "up by the link (102,53) -> (125,23)", function() return H.fieldY() < 40 end),
  H.call(function()
    H.assertEq(H.fieldX() == LINK_UP_TO[1] and H.fieldY() == LINK_UP_TO[2], true, "upstairs at (125,23)")
  end),
  houseLeg(3, "at the child's tile (117,12)"),
  H.faceAndHoldA("up", function() guard(); return sw(0x028B) == 1 end, 3000, "face up and hold A on (117,12) -- _cc5958"),
  H.release(),
  H.advanceStory(function() guard(); return H.hasControl() and H.tileAligned() and not H.dialogWaiting() end, 3000, {}),
  H.call(function()
    H.assertEq(sw(0x028B), 1, "the child rescued ($028B, _cc5958)")
    say("house", "the child is with her")
  end),
  houseLeg(4, "below the box upstairs (111,13)"),
  houseLeg(5, "down by the link (126,22) -> (103,52)", function() return H.fieldY() > 40 end),
  H.call(function()
    H.assertEq(H.fieldX() == LINK_DOWN_TO[1] and H.fieldY() == LINK_DOWN_TO[2], true, "downstairs at (103,52)")
  end),
  houseLeg(6, "back at the door (123,60)"),
  H.driveUntil(function() guard(); return map() ~= MAP_HOUSE end, 900, { H.hold({ "down" }) }, "out by the exit (123,61)"),
  H.release(),
  H.call(function()
    houseOut = timer0()
    clockOn = false
    H.log(string.format("[house] f%d out of the house with the child: timer 0 at %s (%d frames) of 6:00, %d frames "
      .. "spent inside; house battles: %s; boxes: %s; %s", H.frame, H.clockStr(houseOut), houseOut, houseIn - houseOut,
      #tally.house > 0 and table.concat(tally.house, ", ") or "none", table.concat(boxes, ", "), whereLine()))
  end),

  -- Sabin joins
  H.advanceStory(function()
    return sw(0x028A) == 1 and map() == MAP_TZEN and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 20000, {}),
  H.waitFrames(30),
  H.call(function()
    say("tzen", "SABIN joined")
    H.assertEq(sw(0x028A), 1, "Sabin joined ($028A, :90262)")
    H.assertEq(inParty(SABIN) and inParty(CELES), true, "SABIN and CELES in the party")
    H.assertEq(#boxes, 2, "both boxes weighed")
  end),
  H.saveState("wor_tzen_boxes.mss"),
  H.logStep(function()
    return string.format("wor_tzen_boxes generated: CELES L%d and SABIN L%d in Tzen; boxes: %s", level(CELES),
      level(SABIN), table.concat(boxes, ", "))
  end),
})
