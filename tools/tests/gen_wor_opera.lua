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
    -- the waiting members wander: chaseTalk re-plans its approach every step and stops on the prompt
    H.lazy(function() return H.chaseTalk(obj[2], 6000, obj[1] .. " in the cabin") end),
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
-- the Dirt Dragon's fight: STRAGO's lores, RELM's Ultima, Shell on the party (labs du_*: section 4)
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
  -- labs, route-wor-gogo.md section 4: the lores alone won 14 of 16 trials with TERRA seated, fl1_lore, and
  -- 18 of 20 with CELES, dc_lore)
  regroup(HUNT),
  H.gearDress({ tag = "gear for the dragon and the hunt" }),
  H.dressRelics({ { CELES, "CELES" }, { RELM, "RELM" }, { GOGO, "GOGO" }, { STRAGO, "STRAGO" } },
    { tag = "relics for the dragon and the hunt" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Opera House" }),
  H.call(function() H.log("[kit] " .. kitLine(HUNT)) end),
  liftOff(),
  H.call(function() H.log("[doom] aloft: " .. doomLine()) end),
  H.flyTo(OPERA_LANDING[1], OPERA_LANDING[2], { what = "the Falcon down by the Opera House", fight = FIGHT }),
  H.worldNavTo(OPERA_DOOR[1], OPERA_DOOR[2], { maxFrames = 3000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == 237 and not H.worldMode() end }),
  H.waitUntil(function() return map() == 237 and settled() end, 2400, "the Opera House: map 237", 1),
  H.call(function() say("route", "the Opera House (237)") end),
  -- the stage-left room's stair (237 (48,30): $0110 -> 231), and 231's east stair up to the catwalk (232)
  walkInto(48, 30, 231, "237 (48,30) -> 231"),
  walkInto(28, 24, 232, "231 (28,24) -> 232: the catwalk"),
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
