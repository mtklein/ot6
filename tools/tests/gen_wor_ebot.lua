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
local function links(doors)
  local out = {}
  for _, d in ipairs(doors) do
    for _, dir in ipairs({ "up", "down", "left", "right" }) do out[#out + 1] = { d[1], d[2], dir, d[3], d[4] } end
  end
  return out
end
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function lv(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function supplies()
  return string.format("potion=%d tincture=%d fenix=%d remedy=%d revivify=%d tent=%d gil=%d", H.invCountOf(POTION),
    H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(REVIVIFY), H.invCountOf(TENT),
    H.gil())
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s; %s; %s", tag, H.frame, what, pos, H.partiesLine(), supplies()))
end
local function kitLine(members)
  local t = {}
  for _, ch in ipairs(members) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d kit %s", NAMES[ch], lv(ch), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
-- walk onto (x, y) until the map reads dst (gen_wor_relm's)
local function walkInto(x, y, dst, what, avoid)
  local function there() return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15 end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
      }, {}),
    }),
    H.waitUntil(there, 1200, what .. ": control on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- off a field map's edge onto the world map (gen_wor_locke's outToWorld)
local function outToWorld(dir, what)
  local n = 0
  return H.seqStep({
    H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ dir }) }, what),
    H.release(),
    H.withReset(H.waitUntil(function()
      local ok = H.worldSettled() and H.worldAligned() and H.worldPassable(H.worldX(), H.worldY())
      n = ok and n + 1 or 0
      return n >= 30
    end, 2400, what .. ": back on the World of Ruin map"), function() n = 0 end),
    H.call(function() say("wor", what) end),
  })
end
-- onto a world door until its field map holds the screen
local function enterFrom(door, dst, what)
  return H.seqStep({
    H.worldNavTo(door[1], door[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst and not H.worldMode() end }),
    H.waitUntil(function() return map() == dst and settled() end, 2400, what .. ": map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- boarding: on foot on the parked airship's tile, A boards (gen_wor_locke's)
local function board()
  local n, ph = 0, 0
  local drv = H.fightDriverFor("board", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local battleFrames = 0
  local function offTile()
    return not H.battleLoadStarted() and H.worldSettled() and not H.aboardAirship()
      and (H.worldX() ~= H.readByte(0x1F62) or H.worldY() ~= H.readByte(0x1F63))
  end
  return H.withReset(H.driveUntil(function()
    n = H.airshipControl() and n + 1 or 0
    return n >= 30
  end, 30000, {
    H.cond(offTile, {
      H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    }, {}),
    H.call(function()
      if H.battleLoadStarted() then
        battleFrames = battleFrames + 1
        if battleFrames >= 3 then drv.frame() end
        return
      end
      if battleFrames > 0 then drv.idle() end
      ph = (ph + 1) % 16
      if H.aboardAirship() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, "board the Falcon"), function() n, ph, battleFrames = 0, 0, 0 end)
end
-- the cabin's waiting members (map 12) each ask "Change party members?"
-- (_caf59d); NPC_n is object $10 + n - 1, shown by its switch
-- (gen_wor_locke's regroup)
local CABIN_NPCS = { { "TERRA", 0x10, 0x0388 }, { "CYAN", 0x12, 0x038B }, { "SABIN", 0x15, 0x038D },
  { "CELES", 0x16, 0x038E }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 } }
local function regroup(members)
  local obj = nil
  local function pickTalker()
    obj = nil
    for _, n in ipairs(CABIN_NPCS) do
      local ox, oy = H.objX(n[2]), H.objY(n[2])
      local reach = H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy) or H.bfsPath(ox, oy - 1)
      if obj == nil and sw(n[3]) == 1 and reach then obj = n end
    end
    return obj
  end
  return H.seqStep({
    board(),
    H.withReset((function()
      local ph = 0
      return H.driveUntil(function() return map() == MAP_DECK and settled() end, 2400, {
        H.call(function()
          ph = (ph + 1) % 16
          H.setPad((H.airshipControl() and ph < 4) and { "x" } or {})
        end),
      }, "X: to the Falcon's deck (map 11)")
    end)(), function() end),
    walkInto(24, 8, MAP_CABIN, "the deck -> the cabin (map 12)"),
    H.call(function() pickTalker() end),
    H.cond(function() return obj == nil end, {
      H.navTo(23, 44, { maxFrames = 3000, arrive = function() return H.fieldY() < 40 end }),
      H.waitUntil(function() return settled() and H.fieldY() < 40 end, 1200, "up the cabin's stairs", 1),
      H.call(function() pickTalker() end),
    }, {}),
    H.call(function()
      H.assertEq(obj ~= nil, true, "a member waits in the cabin to talk to")
      H.log(string.format("[regroup] talking to %s (obj $%02X, show-switch $%04X)", obj[1], obj[2], obj[3]))
    end),
    H.lazy(function() return H.talkToObj(obj[2], obj[1] .. " in the cabin") end),
    H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
    H.partySelect(members, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      local n = 0
      for ch = 0, 13 do if partyOf(ch) == 1 then n = n + 1 end end
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch), 1, string.format("%s is in party 1 after the regroup", NAMES[ch]))
      end
      H.assertEq(n, #members, "party 1 holds exactly the regroup's members")
      say("regroup", "after the menu")
    end),
  })
end
-- lift off from the deck's wheel (_caf532: face left, A held on (15,8))
local function liftOff()
  return H.seqStep({
    H.navTo(15, 8, { maxFrames = 3000 }),
    H.faceAndHoldA("left", function() return H.dialogWaiting() end, 1200, "the Falcon's wheel (11 (15,8)): face left, A"),
    H.release(),
    H.dialogChoice(0, { inBattle = false, what = "the wheel: (Lift-off)", tag = "the wheel" }),
  })
end
-- the key of every battle (reads only)
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d party %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map(), H.activeParty()))
    end, emu.callbackType.exec, addr, addr)
  end)
end
-- a walk over a map's floor and its doors
local function walk(x, y, what, avoid, arrive)
  return H.seqStep({
    H.lazy(function()
      return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
        fight = FIGHT, avoid = avoid, arrive = arrive })
    end),
    H.call(function() say("route", what) end),
  })
end
-- a chest from whichever side of it the party can reach (gen_wor_ragnarok's)
local function chestAt(cx, cy, bit, what, item)
  return H.lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      local legs = H.bfsReach(nil, nil, nil, LINKS[map()] or {}, cx + o[1], cy + o[2])
      if legs then
        return H.seqStep({
          walk(cx + o[1], cy + o[2], what .. ": beside it"),
          H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what, item = item,
            nav = { fight = FIGHT } }),
        })
      end
    end
    error(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end
-- ---- the Gogo arc's helpers ----
-- Doom Gaze's two cells ($0B00..$0B07: x, y in four-tile cells, world/init.asm @86a6; ctrl.asm @6f1d
-- checks the first two while A is held in the air) and whether it is beaten ($1DD2 bit 0) and its HP
-- ($1DD3, the battle's $3EBE saved)
local function doomLine()
  return string.format("Doom Gaze cells (%d,%d) (%d,%d) [tiles (%d,%d) (%d,%d)]; beaten $1DD2.0=%d; hp $1DD3=%d",
    H.readByte(0x0B00), H.readByte(0x0B02), H.readByte(0x0B04), H.readByte(0x0B06),
    H.readByte(0x0B00) * 4, H.readByte(0x0B02) * 4, H.readByte(0x0B04) * 4, H.readByte(0x0B06) * 4,
    H.readByte(0x1DD2) & 1, H.readWord(0x1DD3))
end
-- pace between the tile the party stands on and a passable neighbour until done(), the world walker
-- playing the battles; spare: species words the walker leaves to the engine (no input)
local function pace(done, budget, what, spare)
  local A, B, n0 = nil, nil, nil
  return H.seqStep({
    H.call(function()
      local x, y = H.worldX(), H.worldY()
      A, B, n0 = { x, y }, nil, #H.outcomes
      for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) then B = { bx, by } end
      end
      H.assertEq(B ~= nil, true, what .. ": a passable tile beside (" .. x .. "," .. y .. ")")
      H.log(string.format("[pace] %s: pacing (%d,%d) <-> (%d,%d)", what, A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function()
      if done() then return true end
      if H.battleLoadStarted() or not H.worldMode() or not H.worldSettled() then return false end
      H.assertEq(#H.outcomes - n0 < budget, true, string.format("%s: done within %d battles", what, budget))
      return false
    end, 900000, {
      H.cond(function() return H.worldMode() and not done() end, {
        H.worldNavTo(function() return B[1] end, function() return B[2] end,
          { maxFrames = 20000, playBattles = "tactical", fight = FIGHT, spare = spare,
            arrive = function() return done() end }),
        H.call(function()
          A, B = B, A
          H.log(string.format("[pace] %s: %d battle(s)", what, #H.outcomes - n0))
        end),
      }, { H.call(function() H.setPad({}) end) }),
    }, what),
  })
end
local function objLine(o0, o1)
  local t = {}
  for o = o0 or 0x10, o1 or 0x14 do t[#t + 1] = string.format("$%02X(%d,%d)", o, H.objX(o), H.objY(o)) end
  return table.concat(t, " ")
end
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
