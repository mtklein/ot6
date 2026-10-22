-- gen_wor_ebot.lua -- the Gogo arc's third leg (docs/design/route-wor-gogo.md):
-- Continue the `wor-gogo-v1` battery (STRAGO, RELM, GOGO and TERRA beside
-- the Falcon by Thamasa), the Falcon to Ebot's Rock (world (249,223) ->
-- map 405, its mouth open: $019A), its holes and their random rooms (404)
-- until the party holds the coral the hungry chest wants (_cb7107: more
-- than 21 at once), the chest fed ($01F9), Hidon (405 (23,5): event battle
-- 94, Hidon and four Hidonites; a game over when lost: the runner retries
-- from the leg's boot) and the scene after it in Strago's house, Thamasa's
-- item counter, and the save beside the Falcon there: the `wor-ebot-v1`
-- battery, the next leg's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MAP_DECK, MAP_CABIN, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 11, 12, 349, 344, 347
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local SHOP_ITEMS = 74
local links = H.doorLinks
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, bright, sw, lv, settled = K.map, K.bright, K.sw, K.lv, K.settled
local say, kitLine, board, watches, walk = K.say, K.kitLine, K.board, K.watches, K.walk
local doomLine = K.doomLine

-- ---- Ebot's Rock (405, 404): holes, coral and the hungry chest ----
-- A hole (route_data map 404/405 triggers) warps the party to a random spot (_cb6ef9 -> _cb6f0e: 404 at
-- one of nine, or 405 (7,8), (7,21), (23,21)); landing in 404 redraws its rooms at random (_cb6fbe:
-- $01F1-$01F8), which decides which of its five coral chests (the invisible NPC_1..5, _cb7446 .. ; $01FA-$01FE,
-- cleared with every map load) can be reached.  A chest gives 1, 2, 3 or 5 coral (_cb7418: var 7, $1FD0).
-- The hungry chest (405 (23,17), _cb70c7 at (23,19)) lets the party by when fed more than 21 at once with
-- STRAGO in the party (_cb7107, _cb7141).
local EBOT_HOLES = { [404] = { { 3, 6 }, { 15, 4 }, { 25, 5 }, { 3, 16 }, { 18, 16 }, { 26, 17 }, { 4, 27 }, { 14, 28 },
  { 28, 27 } }, [405] = { { 8, 9 }, { 7, 15 }, { 23, 22 } } }
local CORAL_NEED = 22
-- every hole on the live map: a walk steps around them (one underfoot warps the party and redraws the
-- rooms); the walk's own target is exempt (navTo's avoid)
local function holesHere() return EBOT_HOLES[map()] or {} end
local function coral() return H.readWord(0x1FD0) end
local function ebotWhere(tag)
  H.log(string.format("[ebot] %s: map %d (%d,%d); coral %d; rooms $01F1-$01F8 %d%d%d%d%d%d%d%d; chests $01FA-$01FE "
    .. "%d%d%d%d%d", tag, map(), H.fieldX(), H.fieldY(), coral(), sw(0x1F1), sw(0x1F2), sw(0x1F3), sw(0x1F4),
    sw(0x1F5), sw(0x1F6), sw(0x1F7), sw(0x1F8), sw(0x1FA), sw(0x1FB), sw(0x1FC), sw(0x1FD), sw(0x1FE)))
end
-- step onto a hole and ride the warp until the party stands with control somewhere else: the warp fades
-- the screen out (_cb6ef9), so a hole is taken once the party has been beside it and the screen has gone
-- dark; a battle on the way (the walk's) leaves it lit
local function hole(x, y, what)
  local m0, near, dark = nil, false, false
  local function gone()
    if m0 == nil then return false end
    local d = math.abs(H.fieldX() - x) + math.abs(H.fieldY() - y)
    if map() == m0 and d <= 1 then near = true end
    if near and bright() == 0 and not H.battleLoadStarted() then dark = true end
    return dark and (map() ~= m0 or d > 1)
  end
  return H.seqStep({
    H.call(function() m0, near, dark = map(), false, false end),
    H.navTo(x, y, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, arrive = gone, avoid = holesHere() }),
    H.advanceStory(function() return gone() and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
    H.call(function() ebotWhere(what) end),
  })
end
local function reach(x, y) return H.bfsReach(nil, nil, nil, {}, x, y) ~= nil end
-- the side of an object the party can stand on to talk to it
-- the side of a coral chest (an invisible NPC on a chest tile) the party can reach without crossing a hole,
-- and the way it faces from there
local function talkSide(ox, oy)
  for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
    if H.bfsReach(nil, nil, nil, {}, ox + o[1], oy + o[2], holesHere()) then return { ox + o[1], oy + o[2], o[3] } end
  end
  return nil
end
-- one move of the coral hunt: a coral chest within reach, else a hole within reach (the nearest)
local function coralMove(what)
  if map() == 404 then
    for i = 0, 4 do
      local o = 0x10 + i
      local ox, oy = H.objX(o), H.objY(o)
      local side = (sw(0x1FA + i) == 0 and not (ox == 0 and oy == 0)) and talkSide(ox, oy) or nil
      if side then
        local c0 = coral()
        return H.seqStep({
          H.navTo(side[1], side[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = holesHere() }),
          H.faceAndHoldA(side[3], function() return H.dialogWaiting() or not H.hasControl() end, 600,
            string.format("coral chest $%02X (404 (%d,%d)): face %s, A", o, ox, oy, side[3])),
          H.release(),
          H.advanceStory(function() return settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
          H.call(function()
            H.log(string.format("[ebot] %s: coral chest $%02X at (%d,%d): %d -> %d coral", what, o, ox, oy, c0, coral()))
          end),
        })
      end
    end
  end
  local best, bestD = nil, 1e9
  for _, h in ipairs(EBOT_HOLES[map()] or {}) do
    local p = H.bfsPath(h[1], h[2])
    if p and #p < bestD and H.bfsReach(nil, nil, nil, {}, h[1], h[2], holesHere()) then best, bestD = h, #p end
  end
  H.assertEq(best ~= nil, true, string.format("%s: a hole within reach of map %d (%d,%d)", what, map(), H.fieldX(),
    H.fieldY()))
  return hole(best[1], best[2], string.format("%s: the hole (%d,%d)", what, best[1], best[2]))
end
-- holes and coral chests until the party holds `need` coral and stands where the hungry chest is in reach
local function coralHunt(need, what, budget)
  local moves = 0
  local function done() return coral() >= need and map() == 405 and reach(23, 19) end
  return H.seqStep({
    H.repeatN(budget or 80, {
      H.cond(function() return not done() end, {
        H.call(function() moves = moves + 1 end),
        H.lazy(function()
          if coral() >= need and map() == 405 and not reach(23, 19) then
            -- enough coral: holes until the chest's room
            local best, bestD = nil, 1e9
            for _, h in ipairs(EBOT_HOLES[405]) do
              local p = H.bfsPath(h[1], h[2])
              if p and #p < bestD and H.bfsReach(nil, nil, nil, {}, h[1], h[2], holesHere()) then best, bestD = h, #p end
            end
            return hole(best[1], best[2], what .. ": toward the chest")
          end
          return coralMove(what)
        end),
      }, {}),
    }),
    H.call(function()
      ebotWhere(what .. string.format(" after %d moves", moves))
      H.assertEq(done(), true, string.format("%s: %d coral and the chest in reach within %d moves", what, need,
        budget or 80))
    end),
  })
end
-- Ebot's Rock: the mouth (249,223), the Falcon down on (250,224); Thamasa (gen_wor_phoenix's)
local EBOT_DOOR, EBOT_LANDING = { 249, 223 }, { 250, 224 }
local THAMASA_DOOR = { 251, 230 }
-- Hidon's scene parks the Falcon by Thamasa (event_main.asm :54632, airship_pos {250, 231}); the leg saves on
-- its tile
local FALCON_AFTER = { 250, 231 }
-- Hidon's formation (464: route_data species): Hidon and its four Hidonites, one of which drinks every
-- element ($160)
local HIDON_SPECIES = { 0x123, 0x126, 0x160, 0x161, 0x162 }
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-gogo-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ STRAGO, RELM, GOGO, TERRA }))
  end),
  -- @@setup-end

  -- ---- 1. Ebot's Rock: the holes and the coral ---------------------------------------------------------
  -- @@stage coral
  board(),
  H.call(function() H.log("[doom] aloft: " .. doomLine()) end),
  H.flyTo(EBOT_LANDING[1], EBOT_LANDING[2], { what = "the Falcon down by Ebot's Rock", fight = FIGHT }),
  H.worldNavTo(EBOT_DOOR[1], EBOT_DOOR[2], { maxFrames = 3000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == 405 and not H.worldMode() end }),
  H.waitUntil(function() return map() == 405 and settled() end, 2400, "Ebot's Rock: map 405", 1),
  H.call(function() say("route", "Ebot's Rock (405)") end),
  -- the first hole (7,15) sets the party by the hungry chest (_cb6ec6, $0181); every hole after it is random
  hole(7, 15, "405 (7,15): the first hole"),
  coralHunt(CORAL_NEED, "the coral hunt", 80),

  -- ---- 2. the hungry chest --------------------------------------------------------------------------------
  -- @@stage chest
  -- the trigger (23,19) (_cb70c7) turns the party to the chest and asks; fed, it hops away ($01F9)
  H.navTo(23, 20, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, avoid = holesHere() }),
  H.navTo(23, 19, { maxFrames = 600, arrive = function() return H.dialogWaiting() or not H.hasControl() end }),
  H.dialogChoice(0, { inBattle = false, what = "Hand over some Coral? Sure.", tag = "the hungry chest" }),
  H.advanceStory(function() return sw(0x01F9) == 1 and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() ebotWhere("the chest fed ($01F9)") end),
  H.saveState("wor_ebot_fed.mss"),

  -- ---- 3. Hidon --------------------------------------------------------------------------------------------
  -- @@stage hidon
  H.navTo(23, 8, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.navTo(23, 7, { maxFrames = 1200, playBattles = "tactical", fight = FIGHT, arrive = function() return sw(0x01FC) == 1 end }),
  H.advanceStory(function() return sw(0x01FC) == 1 and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() ebotWhere("Hidon in sight ($01FC)") end),
  -- a Hidonite drinks every element: weapons none of the five absorbs (the absorb guard's own reads)
  H.absorbSafeArms({ STRAGO, RELM, GOGO, TERRA }, HIDON_SPECIES, { tag = "arms for Hidon" }),
  H.fieldCare({ threshold = 1.0, tag = "before Hidon" }),
  H.saveState("wor_ebot_hidon.mss"),
  H.navTo(23, 6, { maxFrames = 1200 }),
  H.faceAndHoldA("up", function() return H.battleLoadStarted() or H.dialogWaiting() or not H.hasControl() end, 600,
    "Hidon (405 (23,5)): face up, A"),
  H.release(),
  H.advanceStory(function() return map() == MAP_HOUSE and settled() end, 300000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "Hidon beaten: Strago's house")
    H.assertEq(sw(0x019C), 1, "Hidon beaten ($019C)")
  end),
  H.saveState("wor_ebot_after.mss"),

  -- ---- 4. Thamasa and the save ---------------------------------------------------------------------------
  -- @@stage save
  walk(37, 24, "Strago's house: the hall, by the door"),
  H.navTo(37, 25, { maxFrames = 3000, arrive = function() return map() ~= MAP_HOUSE end }),
  H.waitUntil(function() return map() == MAP_THAMASA and settled() end, 2400, "Thamasa: map 344", 1),
  H.crossDoor(26, 37, MAP_THAMASA_ITEMS, 36, 44, "Thamasa's item shop door 344 (26,37) -> 347", { fight = FIGHT }),
  H.shopTalk(36, 39, "Thamasa's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 74 ($0201)") end),
  H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 40 })
    - H.invCountOf(POTION)) end, "POTION to the band"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(TINCTURE, function() return math.max(0, -(-H.activeTopLevel() // 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the band"),
  H.buyItem(REMEDY, function() return math.max(0, 10 - H.invCountOf(REMEDY)) end, "REMEDY to 10"),
  H.shopClose("Thamasa's item shop"),
  H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Thamasa)" }),
  H.call(function() say("shop", "Thamasa") end),
  H.crossDoor(36, 45, MAP_THAMASA, 26, 39, "Thamasa's item shop -> the street", { fight = FIGHT }),
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) }, "off Thamasa's edge"),
  H.release(),
  H.waitWorldSettled("out of Thamasa", 1800, 30),
  H.worldNavTo(FALCON_AFTER[1], FALCON_AFTER[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.waitFrames(90),
  H.worldNavTo(FALCON_AFTER[1], FALCON_AFTER[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine({ STRAGO, RELM, GOGO, TERRA }))
  end),
  H.saveAtCheckpoint("wor-ebot-v1"),
  H.saveState("wor_ebot.mss"),
  H.logStep(function()
    return string.format("wor_ebot generated: STRAGO L%d, RELM L%d, GOGO L%d and TERRA L%d beside the Falcon by "
      .. "Thamasa, world (%d,%d), saved in slot 3", lv(STRAGO), lv(RELM), lv(GOGO), lv(TERRA), H.worldX(), H.worldY())
  end),
})
