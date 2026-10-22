-- gen_wor_opera.lua -- the Gogo arc's fourth leg (docs/design/route-wor-gogo.md):
-- Continue the `wor-ebot-v1` battery (STRAGO, RELM, GOGO and TERRA beside
-- the Falcon by Thamasa), the cabin (CELES, RELM, GOGO, STRAGO: the four for
-- the Dirt Dragon and Doom Gaze both), the Falcon to the Opera House (world
-- (31,183) -> map 237), the stage-left room's way up (237 (48,30) -> 231 ->
-- 232: the catwalk), the stage master, the switch that drops the party onto
-- the stage where the Dirt Dragon sits ($0387: event battle 134; a game over
-- when lost: the runner retries from the leg's boot), back aboard, Doom Gaze
-- flown down in the sky until it falls (its HP carries from meeting to
-- meeting; DoomGazeDefeated: Bahamut), and the save beside the Falcon by the
-- Opera House: the `wor-opera-v1` battery, the next arc's boot.
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
local map, sw, lv, settled, say = K.map, K.sw, K.lv, K.settled, K.say
local outToWorld = K.outToWorld
local kitLine, walkInto, board, regroup, liftOff = K.kitLine, K.walkInto, K.board, K.regroup, K.liftOff
local watches, doomLine = K.watches, K.doomLine

-- ---- Doom Gaze in the sky ----
-- Every airship start rolls Doom Gaze two cells of four tiles by four ($0B00/$0B02, $0B04/$0B06: world/init.asm
-- @86a6, from RNGTbl at $1F6D), and flying with A held over either one draws its battle (world/ctrl.asm @6ee8:
-- event group 93, formation 463) until it is beaten ($1DD2 bit 0).  Its HP carries from meeting to meeting
-- ($3EBE -> $1DD3: battle_main.asm @2ce4, @49c4); it flees on its fourth turn (AIScript _285).  A player who
-- knows where it waits (read with full power, TESTING.md) flies through its cell.
local function s16(v) return v >= 0x8000 and v - 0x10000 or v end
local function wrapDelta(d) return ((d + 128) % 256) - 128 end
local function wrapAngle(a) return ((a + 180) % 360) - 180 end
local function doomCells()
  return { { H.readByte(0x0B00), H.readByte(0x0B02) }, { H.readByte(0x0B04), H.readByte(0x0B06) } }
end
local function doomBeaten() return (H.readByte(0x1DD2) & 1) == 1 end
-- fly at full thrust through the nearer of Doom Gaze's two cells until a battle opens (or `maxFrames` of
-- flying pass), steering as flyTo steers
local function flyThrough(what, maxFrames)
  local flown, bn, cell = 0, 0, nil
  return H.withReset(H.driveUntil(function()
    return H.battleLoadStarted() or flown > (maxFrames or 6000)
  end, (maxFrames or 6000) + 2000, {
    H.call(function()
      if not H.airshipControl() then H.setPad({}); return end
      flown = flown + 1
      local x, y = H.airshipPos()
      if cell == nil or flown % 120 == 1 then
        local best, bestD = nil, 1e9
        for _, cc in ipairs(doomCells()) do
          local tx, ty = cc[1] * 4 + 2, cc[2] * 4 + 2
          local dx, dy = wrapDelta(tx - x), wrapDelta(ty - y)
          local d = dx * dx + dy * dy
          if d < bestD then best, bestD = { tx, ty, cc[1], cc[2] }, d end
        end
        if cell == nil or best[3] ~= cell[3] or best[4] ~= cell[4] then
          H.log(string.format("[doom] %s: f%d flying through cell (%d,%d) (tile (%d,%d)) from (%.1f,%.1f)", what,
            H.frame, best[3], best[4], best[1], best[2], x, y))
        end
        cell = best
      end
      local dx, dy = wrapDelta(cell[1] - x), wrapDelta(cell[2] - y)
      local heading = H.readWord(0x73) - 270
      local rate = s16(H.readWord(0x29))
      local bearing = math.deg(math.atan(-dy, dx))
      local err = wrapAngle(bearing - heading)
      local coast = rate * math.abs(rate) / (2 * 16 * 256)
      local resid = wrapAngle(err - coast)
      local pad = { "a" }
      if math.abs(resid) > 2 then pad[#pad + 1] = resid > 0 and "left" or "right" end
      H.setPad(pad)
    end),
  }, what), function() flown, bn, cell = 0, 0, nil end)
end
-- the hunt: fly through Doom Gaze's cell, fight what comes (the walks' driver), and again, until it is
-- beaten or `meetings` battles have passed; logs each meeting's HP
local function doomHunt(meetings, what)
  local met, hp0 = 0, nil
  local drv = H.fightDriverFor("doom", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local bn = 0
  return H.seqStep({
    H.call(function() hp0 = H.readWord(0x1DD3); H.log("[doom] " .. what .. ": " .. doomLine()) end),
    H.repeatN(meetings, {
      H.cond(function() return not doomBeaten() end, {
        H.waitUntil(function() return H.airshipControl() end, 3000, what .. ": the pilot's controls", 5),
        flyThrough(what, 8000),
        H.call(function()
          met = met + 1
          local w = H.formationWords()
          H.log(string.format("[doom] %s: meeting %d at f%d (%04X %04X)", what, met, H.frame, w[1], w[2]))
        end),
        -- the battle, then the world (or the deck's scene when it falls: DoomGazeDefeated) until the pilot
        -- has the controls again
        H.withReset(H.driveUntil(function()
          return not H.battleLoadStarted() and (H.airshipControl() or (doomBeaten() and H.worldMode()
            and H.worldSettled() and not H.aboardAirship()))
        end, 200000, {
          H.call(function()
            bn = H.battleLoadStarted() and bn + 1 or 0
            if bn >= 3 then drv.frame(); return end
            if bn == 0 then drv.idle() end
            H.setPad((H.dialogWaiting() and H.frame % 8 < 4) and { "a" } or {})
          end),
        }, what .. ": the meeting and back aloft"), function() bn = 0 end),
        H.call(function()
          H.log(string.format("[doom] %s: after meeting %d: hp %d (%d at the hunt's start); beaten %s; %s", what, met,
            H.readWord(0x1DD3), hp0, tostring(doomBeaten()), H.partiesLine()))
        end),
        -- the care between meetings is on the deck (X from the controls; the menu, then the wheel)
        H.cond(function() return not doomBeaten() end, {
          H.withReset((function()
            local ph = 0
            return H.driveUntil(function() return map() == MAP_DECK and settled() end, 2400, {
              H.call(function()
                ph = (ph + 1) % 16
                H.setPad((H.airshipControl() and ph < 4) and { "x" } or {})
              end),
            }, "X: to the Falcon's deck (map 11)")
          end)(), function() end),
          H.fieldCare({ threshold = 0.9, tag = "care on the deck after Doom Gaze" }),
          liftOff(),
        }, {}),
      }, {}),
    }),
  })
end
-- the Opera House: its door (31,183), the Falcon down on (30,182) (out of the house the party stands on
-- (31,182), beside it)
local OPERA_DOOR, OPERA_LANDING = { 31, 183 }, { 30, 182 }
-- the hunt's four (route-wor-gogo.md section 7, the Doom Gaze lab): CELES for TERRA, and the cabin's gear
-- care, which hands RELM the brush (special: Doom Gaze's key)
local HUNT = { CELES, RELM, GOGO, STRAGO }
-- the Dirt Dragon's kit, swapped on at the catwalk and off for Doom Gaze: { {char, slot, item} } (slot 3
-- armor, 5 the second relic).  A Cherub Down on each of the four: its Float is the relic's, so the dragon's
-- 50 Gs, which strips a cast Float, leaves it, and its earth (Quake $15, Magnitude8, Slide) misses; and the
-- bag's Gaia Gear (absorbs earth) on STRAGO.  From one snapshot at the switch, sixty trials an arm, a fresh
-- driver a trial (build/attempts/wt/v036-route/lab/kit_*; dtally.py, dact.py, fight_report.py): the leg's
-- ward relics 60 of 60, 1.62 deaths a fight; the Cherub Downs 60 of 60, 0.19, the party's Float kept after
-- all 136 of the dragon's 50 Gs and its Quakes taking 0 HP (37 of them); the Gaia Gear 60 of 60, 1.07; both
-- 60 of 60, 0.05, 21 distinct keys.  The four Cherub Downs come from Jidoor's relic counter on the way
-- (jidoorStop); each piece must be on its member after the swap
local DRAGON_KIT = { { CELES, 5, 0xBC }, { RELM, 5, 0xBC }, { GOGO, 5, 0xBC }, { STRAGO, 5, 0xBC },
  { STRAGO, 3, 0x8D } }
local kitHeld = {}
local function dragonKit(tag)
  local steps = {}
  for _, m in ipairs(DRAGON_KIT) do
    steps[#steps + 1] = H.lazy(function()
      local cur = H.readByte(0x1600 + 37 * m[1] + 0x1F + m[2])
      if cur == m[3] then return H.call(function() end) end
      H.assertEq(H.invCountOf(m[3]) > 0, true, string.format("item $%02X in the bag for %s %s", m[3], NAMES[m[1]], tag))
      kitHeld[#kitHeld + 1] = { m[1], m[2], cur }
      return H.equipKit(m[1], { { m[2], m[3] } }, { tag = string.format("%s: $%02X %s", NAMES[m[1]], m[3], tag) })
    end)
  end
  steps[#steps + 1] = H.call(function()
    H.log("[kit] " .. tag .. ": " .. kitLine(HUNT))
    for _, m in ipairs(DRAGON_KIT) do
      H.assertEq(H.readByte(0x1600 + 37 * m[1] + 0x1F + m[2]), m[3],
        string.format("%s wears $%02X in slot %d %s", NAMES[m[1]], m[3], m[2], tag))
    end
  end)
  return H.seqStep(steps)
end
local function dragonKitBack(tag)
  return H.lazy(function()
    local steps = {}
    for _, h in ipairs(kitHeld) do
      if h[3] ~= 0xFF then
        steps[#steps + 1] = H.equipKit(h[1], { { h[2], h[3] } }, { tag = NAMES[h[1]] .. ": back " .. tag })
      end
    end
    steps[#steps + 1] = H.call(function() H.log("[kit] " .. tag .. ": " .. kitLine(HUNT)) end)
    return H.seqStep(steps)
  end)
end
-- Jidoor's relic counter (198 (5,25) -> 202, the keeper (54,16), shop 79): a Cherub Down for each of the
-- four, then out by the town's south edge and aboard
local JIDOOR_DOOR, JIDOOR_LANDING = { 35, 156 }, { 36, 156 }
local function jidoorStop()
  return H.seqStep({
    H.flyTo(JIDOOR_LANDING[1], JIDOOR_LANDING[2], { what = "the Falcon down by Jidoor", fight = FIGHT }),
    H.worldNavTo(JIDOOR_DOOR[1], JIDOOR_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == 198 and not H.worldMode() end }),
    H.waitUntil(function() return map() == 198 and settled() end, 2400, "Jidoor: map 198", 1),
    H.crossDoor(5, 25, 202, 54, 22, "Jidoor -> its relic shop (202)", { fight = FIGHT }),
    H.shopTalk(54, 16, "Jidoor's relic counter", { fight = FIGHT }),
    H.call(function() H.assertEq(H.shopId(), 79, "Jidoor's relic counter is shop 79") end),
    H.buyItem(0xBC, function() return math.max(0, 4 - H.invCountOf(0xBC)) end, "CHERUB DOWN for each of the four"),
    H.shopClose("Jidoor's relic counter"),
    H.call(function() H.assertEq(H.invCountOf(0xBC) >= 4, true, "four Cherub Downs in the bag") end),
    H.crossDoor(54, 23, 198, 5, 27, "the relic shop -> Jidoor", { fight = FIGHT }),
    H.navTo(16, 62, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    outToWorld("down", "out of Jidoor"),
    board(),
    H.call(function() say("shop", "Jidoor's Cherub Downs") end),
  })
end
-- the Dirt Dragon's fight: STRAGO's lores, RELM's Ultima, Shell on the party (labs du_*, dx_*, sweep so2:
-- section 4).  No Dischord: from the same snapshot the fight with it won 49 of 60 trials and without it 55
-- of 60, and it lost every trial of one key the plain fight won (#460; build/attempts/wt/v036-route/lab/
-- dd_dis*, dd_ward*: 'be70:xxxx', 'be70:WWWW')
local DRAGON_FIGHT = { nukeLore = { 0x03, 0x04 }, magic = { [RELM] = { spell = 0x14 } },
  buffVs = { [0x14C] = { 0x25 } } }
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-ebot-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ STRAGO, RELM, GOGO, TERRA }))
  end),
  -- @@setup-end

  -- ---- 1. the Opera House: the catwalk ------------------------------------------------------------------
  -- @@stage opera
  -- the cabin first: CELES takes TERRA's seat for the Dirt Dragon and for Doom Gaze both (the Dirt Dragon
  -- labs, route-wor-gogo.md section 4: the lores alone won 18 of 20 trials with TERRA seated, fl1_lore, and
  -- 18 of 20 with CELES, dc_lore; one cabin stop serves both fights)
  regroup(HUNT),
  H.gearDress({ tag = "gear for the dragon and the hunt" }),
  H.dressRelics({ { CELES, "CELES" }, { RELM, "RELM" }, { GOGO, "GOGO" }, { STRAGO, "STRAGO" } },
    { tag = "relics for the dragon and the hunt" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Opera House" }),
  -- the battle heals on top of the bag: the Elixir sat at row 106, and the walk to it held RELM's turn in
  -- the Item list for 1,100 frames of the dragon's opening Quakes (sweep so3_k3_s7: "item steer: row 0 ->
  -- 106")
  H.bagArrange({ POTION, FENIX, 0xEA, 0xEE, 0xEC, REMEDY, TINCTURE }, { tag = "bag: the battle heals on top" }),
  H.call(function() H.log("[kit] " .. kitLine(HUNT)) end),
  liftOff(),
  jidoorStop(),
  H.call(function() H.log("[doom] aloft: " .. doomLine()) end),
  H.flyTo(OPERA_LANDING[1], OPERA_LANDING[2], { what = "the Falcon down by the Opera House", fight = FIGHT }),
  H.worldNavTo(OPERA_DOOR[1], OPERA_DOOR[2], { maxFrames = 3000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == 237 and not H.worldMode() end }),
  H.waitUntil(function() return map() == 237 and settled() end, 2400, "the Opera House: map 237", 1),
  H.call(function() say("route", "the Opera House (237)") end),
  -- the stage-left room's stair (237 (48,30): $0110 -> 231), and 231's east stair up to the catwalk (232)
  walkInto(48, 30, 231, "237 (48,30) -> 231"),
  walkInto(28, 24, 232, "231 (28,24) -> 232: the catwalk"),
  dragonKit("for the Dirt Dragon"),
  H.fieldCare({ threshold = 1.0, tag = "before the Dirt Dragon" }),

  -- ---- 2. the Dirt Dragon --------------------------------------------------------------------------------
  -- @@stage dragon
  -- the stage master (232 (118,29), _cab455) steps aside when spoken to ($01F0) and names the far switch;
  -- the switch (118,27) (_cab497: facing up, A) drops the party through the stage, where the dragon sits
  -- ($0387: battle 134)
  H.navTo(117, 29, { maxFrames = 3000 }),
  H.faceAndHoldA("right", function() return H.dialogWaiting() end, 600, "the stage master (232 (118,29))"),
  H.release(),
  H.advanceStory(function() return sw(0x01F0) == 1 and settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
  H.navTo(118, 27, { maxFrames = 3000 }),
  -- the dragon hits hard with its tusks, casts earth (Quake, Magnitude8, Slide) and keeps its vanilla wind
  -- and water: STRAGO, RELM and GOGO step to the back row (blows taken halved); STRAGO's lores Aqua Rake and
  -- Aero are his first reach (and GOGO's, through his Lore row), RELM casts her Ultima, and Shell goes on
  -- each member (DRAGON_FIGHT).  Its 50 Gs strips Float, so the Float line is left out of this fight
  -- (route-wor-gogo.md section 4)
  H.setRows({ [STRAGO] = true, [RELM] = true, [GOGO] = true }),
  H.waitUntil(function() return H.hasControl() end, 600, "control after the rows", 1),
  H.saveState("wor_opera_switch.mss"),
  -- (the switch's own tile re-runs its script under the party, control one frame in four: done is the
  -- drop's map load, _cab497's load_map 231, not a frame without control)
  H.faceAndHoldA("up", function() return map() ~= 232 or H.battleLoadStarted() end, 900,
    "the catwalk's switch (232 (118,27)): face up, A"),
  H.release(),
  H.advanceStory(function() return sw(0x0387) == 0 and map() == 237 and settled() end, 300000,
    { playBattles = "tactical", fight = DRAGON_FIGHT }),
  H.call(function() say("story", "the Dirt Dragon beaten ($0387 clear)") end),
  H.fieldCare({ tag = "after the Dirt Dragon" }),
  H.saveState("wor_opera_dragon.mss"),

  -- ---- 3. Doom Gaze ----------------------------------------------------------------------------------------
  -- @@stage doom
  H.navTo(60, 51, { maxFrames = 6000 }),
  H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ "down" }), H.waitFrames(4) }, "out of the Opera House"),
  H.release(),
  H.waitWorldSettled("out of the Opera House", 1800, 30),
  H.call(function() say("wor", "out of the Opera House") end),
  H.worldNavTo(OPERA_LANDING[1], OPERA_LANDING[2], { maxFrames = 3000, playBattles = "tactical", fight = FIGHT,
    avoid = { OPERA_DOOR } }),
  -- the second relics back for Doom Gaze
  dragonKitBack("for the hunt"),
  H.fieldCare({ threshold = 1.0, tag = "before the hunt" }),
  H.call(function() H.log("[kit] " .. kitLine(HUNT)) end),
  board(),
  doomHunt(20, "Doom Gaze"),
  H.call(function()
    H.log("[doom] " .. doomLine())
    H.assertEq(doomBeaten(), true, "Doom Gaze beaten ($1DD2 bit 0) within 20 meetings")
  end),
  H.saveState("wor_opera_doom.mss"),

  -- ---- 4. the save -----------------------------------------------------------------------------------------
  -- @@stage save
  H.waitUntil(function() return H.airshipControl() end, 6000, "the pilot's controls after Doom Gaze", 5),
  H.flyTo(OPERA_LANDING[1], OPERA_LANDING[2], { what = "the Falcon down by the Opera House", fight = FIGHT }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine(HUNT))
  end),
  H.saveAtCheckpoint("wor-opera-v1"),
  H.saveState("wor_opera.mss"),
  H.logStep(function()
    return string.format("wor_opera generated: CELES L%d, RELM L%d, GOGO L%d and STRAGO L%d beside the Falcon by the "
      .. "Opera House, world (%d,%d), saved in slot 3", lv(CELES), lv(RELM), lv(GOGO), lv(STRAGO), H.worldX(),
      H.worldY())
  end),
})
