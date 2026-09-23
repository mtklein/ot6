-- gen_wor_start.lua -- the World of Ruin opening: from wor_landing (solo
-- CELES at Cid's bedside on the Solitary Island, map 397, the WoR flag
-- $00A4 set) to the first save the game allows after the island, on the
-- World of Ruin map where the raft lands.  Generates wor_start.mss, and
-- its capture run (OT6_CAPTURE_SRM) cuts the `wor-start-v1` battery.
--
-- The route (docs/design/wor-start.md has the measurements):
--   1. Dress CELES.  The WoR opening hands her over with every slot empty
--      (her escape kit went to the bag), and the menu costs Cid nothing:
--      his clock is timer 0 with the FIELD_ONLY flag ($1188 = $80), which
--      DecTimersMenuBattle skips.
--   2. The island save.  Off 396's west edge the island is a tile on the
--      World of Ruin map (76,239); the world map allows saving and Cid's
--      field clock stands still there.  A person who knows Cid can be lost
--      saves here first; so does this route (slot 3).
--   3. Save Cid by feeding him, the way a person does it: walk down onto
--      the fishing beach (396 row 14 -> 398 (4,2)), catch fish by facing
--      one from the shore and pressing A, walk back into the house (396
--      (8,6) -> 397) and talk to him from (99,38).  His health is event
--      var 7 ($1FD0): 120 at the landing, -1 each time the 64-frame field
--      timer fires (_ca533f), and every talk rerolls which of the four
--      fish swim (_ca534a, 50% each).  Eating: the NORMAL-speed fish +32,
--      the two SLOW ones +16 and -4, the SLOWER one -16 (_ca5370); he
--      recovers when fed above 256, and is lost if Celes walks into the
--      house with 30 or less (the map's init, _caf42d).
--      POLICY (visible cues only: a fish's swim speed, $0875): if the fast
--      fish is swimming, catch it, plus any slow fish that swims up beside
--      her on the way, plus a slow one still close when the fast one is
--      caught; if it is not, walk straight back and talk to him (the talk
--      is the reroll).  Never the slowest fish.  Measured, this recovers
--      him about 4 times in 5 from the island save (docs/design/
--      wor-start.md); a lost attempt reloads the island save and goes
--      again, bounded at 4 and every attempt logged.
--   4. His recovery scene reveals the stairs; walk down to the raft
--      (397 (85,51)) and talk to it: his farewell, the voyage, and the
--      landing on the World of Ruin map at (146,212).
--   5. Save through the real Save UI into slot 3 and assert the battery
--      holds that world save and the wor-start-v1 contract.
-- Nothing is written; every catch, talk and step is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES = 6
local MAP_HOUSE, MAP_ISLE, MAP_BEACH = 397, 396, 398
local OBJ_RAFT = 0x13                               -- npc_prop 397 record 4 (the raft)
local GFX_FISH = 0x3A                               -- include/gfx/map_sprite_gfx.inc FISH
local SPEED_FAST, SPEED_SLOW = 2, 1                 -- $0875: NORMAL 2, SLOW 1, SLOWER 0
local TALK_X, TALK_Y = 99, 38                       -- beside the bed, facing right
local LANDING_X, LANDING_Y = 146, 212               -- _ca5633: load_map 1, {146, 212}
local SLOW_AFTER_FAST = 240                         -- frames a slow fish is still chased after the fast one
local TRIP_CAP = 250

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function health() return H.readWord(0x1FD0) end          -- event var 7
local function objOn(i) return H.readByte(0x0867 + 0x29 * i) & 0xC0 == 0xC0 end
local function objSpeed(i) return H.readByte(0x0875 + 0x29 * i) end
local function isFish(i) return objOn(i) and H.readByte(0x0879 + 0x29 * i) == GFX_FISH end
local function objMap(x, y) return H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function cidWell() return sw(0x00B3) == 1 end              -- _ca5713
local function cidDead() return sw(0x00B4) == 1 end              -- _caf461
local function ready()
  return H.hasControl() and H.tileAligned() and bright() >= 15
    and not H.dialogWaiting() and not H.battleLoadStarted()
end

-- the cardinal steps, in a fixed order (no pairs(): string-key order is
-- not stable across Lua states, and a generator is bit-reproducible)
local DIRS = {
  { "up", 0, -1, 0 }, { "right", 1, 0, 1 }, { "down", 0, 1, 2 }, { "left", -1, 0, 3 },
}
local STEP = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

local trip, fed, caughtTrip, spreadLeft = 0, {}, {}, 0
local islandBlob, cidSaved, attemptLog, rolls, firstRoll = nil, false, {}, {}, nil
local function fishSet()
  local parts = {}
  for i = 0x10, 0x1F do
    if isFish(i) then
      parts[#parts + 1] = string.format("%02X:sp%d(%d,%d)", i, objSpeed(i), H.objX(i), H.objY(i))
    end
  end
  return #parts > 0 and table.concat(parts, " ") or "none"
end

-- walk onto an exit tile and through it without idling: stage on the tile
-- before it, hold the direction until the map changes, and hand on the
-- moment the new map is lit and controllable (Cid's clock runs on the
-- field; a person does not stand around at a door)
local function through(x, y, dir, dst, what)
  local d = STEP[dir]
  local from
  return H.seqStep({
    H.call(function() from = map() end),
    H.navTo(x - d[1], y - d[2], { maxFrames = 3000, playBattles = "tactical",
      arrive = function() return map() ~= from end }),
    H.driveUntil(function() return map() ~= from end, 600, {
      H.call(function() H.setPad({ [dir] = true }) end),
    }, what),
    H.release(),
    H.waitUntil(function() return map() == dst and ready() end, 900, what .. ": far side", 1),
  })
end

-- the tiles the party can stand on, flooded over canStep from where it is
-- (a list, walked in order, so ties break the same way every run)
local function reachable()
  local seen, list, q = {}, {}, { { H.fieldX(), H.fieldY() } }
  seen[H.fieldY() * 256 + H.fieldX()] = true
  local moves = { { "up", 0, -1 }, { "right", 1, 0 }, { "down", 0, 1 }, { "left", -1, 0 } }
  local head = 1
  while head <= #q do
    local c = q[head]; head = head + 1
    list[#list + 1] = c
    for _, m in ipairs(moves) do
      local nx, ny = c[1] + m[2], c[2] + m[3]
      if nx >= 0 and ny >= 0 and nx < 64 and ny < 64 and not seen[ny * 256 + nx]
         and H.canStep(c[1], c[2], m[1]) then
        seen[ny * 256 + nx] = true; q[#q + 1] = { nx, ny }
      end
    end
  end
  return seen, list
end

-- Fishing on 398.  A fish is caught the way CheckNPCs (field/player.asm)
-- activates any NPC: A held while the party faces the tile the object map
-- ($7E2000, object index * 2) puts the fish on.  The object map, not the
-- fish's pixel position: a swimming fish owns its destination tile from
-- the start of its move.
local function fishing()
  local seen, list, target, ph, fastCaughtAt, arrived = nil, nil, nil, 0, nil, nil
  local present = {}
  local function wanted(i)
    if not isFish(i) then return false end
    local sp = objSpeed(i)
    if sp >= SPEED_FAST then return true end
    if sp ~= SPEED_SLOW then return false end                    -- never the slowest
    -- a slow fish is worth a chase only beside the fast one's: while the
    -- fast fish swims, or for a moment after it is caught
    if fastCaughtAt then return H.frame - fastCaughtAt <= SLOW_AFTER_FAST end
    return true
  end
  local function fastSwimming()
    for i = 0x10, 0x1F do if isFish(i) and objSpeed(i) >= SPEED_FAST then return true end end
    return false
  end
  local function anyWanted()
    for i = 0x10, 0x1F do if wanted(i) then return true end end
    return false
  end
  local step = H.driveUntil(function()
    if not arrived or spreadLeft > 0 then return false end
    for i = 0x10, 0x1F do
      if present[i] and not objOn(i) then
        caughtTrip[#caughtTrip + 1] = string.format("%02X:sp%d@%d", i, present[i], H.frame - arrived)
        H.log(string.format("[cid] trip %d: caught fish %02X (speed %d) %d frames after arriving; health %d",
          trip, i, present[i], H.frame - arrived, health()))
        if present[i] >= SPEED_FAST then fastCaughtAt = H.frame end
        present[i] = nil
        if target == i then target = nil end
      end
    end
    -- the whole visit hangs on the fast fish: no fast fish, no chase
    if not fastCaughtAt and not fastSwimming() then return true end
    return not anyWanted()
  end, 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      if not arrived then
        arrived = H.frame
        seen, list = reachable()
        for i = 0x10, 0x1F do if isFish(i) then present[i] = objSpeed(i) end end
        H.log(string.format("[cid] trip %d: the beach at f%d, health %d, fish %s",
          trip, H.frame, health(), fishSet()))
      end
      -- a reloaded attempt's first look at the beach lingers (the ladder's
      -- spread, below): the fish swim on meanwhile, so the next reroll
      -- reads the field RNG somewhere else
      if spreadLeft > 0 then spreadLeft = spreadLeft - 1; H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local px, py = H.fieldX(), H.fieldY()
      -- a wanted fish on a tile beside her: turn to it, then A
      for _, d in ipairs(DIRS) do
        local o = objMap(px + d[2], py + d[3])
        if o < 0x80 and wanted(o >> 1) then
          if facing() ~= d[4] then H.setPad({ [d[1]] = true }); return end
          H.setPad(ph < 4 and { a = true, [d[1]] = true } or { [d[1]] = true })
          return
        end
      end
      -- otherwise close in: the fast fish first, then the nearest
      if not target or not wanted(target) then
        target = nil
        local bestKey
        for i = 0x10, 0x1F do
          if wanted(i) then
            local key = (objSpeed(i) >= SPEED_FAST and 0 or 1000)
              + math.abs(H.objX(i) - px) + math.abs(H.objY(i) - py)
            if not bestKey or key < bestKey then target, bestKey = i, key end
          end
        end
        if not target then H.setPad({}); return end
      end
      local ox, oy = H.objX(target), H.objY(target)
      local path
      for _, d in ipairs(DIRS) do                       -- a shore tile beside it
        local sx, sy = ox - d[2], oy - d[3]
        if seen[sy * 256 + sx] and not (sx == px and sy == py) then
          local p = H.bfsPath(sx, sy)
          if p and (not path or #p < #path) then path = p end
        end
      end
      if not path then                                  -- the standable tile nearest it
        local bt, bd
        for _, c in ipairs(list) do
          local dd = math.abs(c[1] - ox) + math.abs(c[2] - oy)
          if not bd or dd < bd then bt, bd = c, dd end
        end
        if bt and not (bt[1] == px and bt[2] == py) then path = H.bfsPath(bt[1], bt[2]) end
      end
      if path and #path > 0 then H.setPad({ [H.movePress(path[1])] = true }) else H.setPad({}) end
    end),
  }, "fishing")
  return H.withReset(step, function()
    seen, list, target, ph, fastCaughtAt, arrived, present = nil, nil, nil, 0, nil, nil, {}
  end)
end

-- talk to Cid in his bed from (99,38) facing right, and page his answer
-- (a feed, his health line, or -- fed above 256 -- the whole recovery
-- scene, which ends with control back at the bedside)
local function talkCid()
  local ph, calm, n, lastDlg = 0, 0, 0, -1
  return H.seqStep({
    H.call(function() ph, calm, n, lastDlg = 0, 0, 0, -1 end),
    H.navTo(TALK_X, TALK_Y, { maxFrames = 3000, playBattles = "tactical" }),
    H.driveUntil(function()
      n = H.eventRunning() and n + 1 or 0
      return n >= 6
    end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        if facing() ~= 1 then H.setPad({ right = true }); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "Cid: face him from the bedside, A"),
    H.driveUntil(function()
      calm = (ready() and not H.eventRunning()) and calm + 1 or 0
      return calm >= 4
    end, 9000, {
      H.call(function()
        ph = (ph + 1) % 16
        if H.dialogWaiting() then
          local dlg = H.readWord(0x00D0)
          if dlg ~= lastDlg then
            lastDlg = dlg
            H.log(string.format("[cid] trip %d: dialog $%04X, health %d", trip, dlg, health()))
          end
          H.assertEq(H.readByte(0x056F) < 2, true, "no choice prompt in Cid's answers")
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        H.setPad({})
      end),
    }, "Cid's answer"),
  })
end

local tripStart, healthBefore = 0, 0
local function seq(steps) return H.cond(function() return true end, steps) end

-- One feeding run: trip after trip until he recovers ($00B3) or Celes
-- walks into the house with his health at 30 or less and the map's init
-- marks him lost ($00B4 -- a person finds out by talking to him; the run
-- stops at the mark instead of riding the death scene).
local function feedCid()
  return H.driveUntil(function()
    if trip >= TRIP_CAP and not cidWell() and not cidDead() then
      error(string.format("Cid neither recovered nor lost after %d trips (health %d)", trip, health()), 0)
    end
    return cidWell() or cidDead()
  end, 400000, {
    H.call(function()
      trip = trip + 1; caughtTrip = {}; tripStart = H.frame; healthBefore = health()
    end),
    H.cond(function() return map() == MAP_HOUSE end,
      { through(100, 46, "down", MAP_ISLE, "the house door -> 396") }, {}),
    through(8, 14, "down", MAP_BEACH, "396 -> the beach 398"),
    fishing(),
    through(4, 1, "up", MAP_ISLE, "the beach -> 396"),
    through(8, 6, "up", MAP_HOUSE, "396 -> the house"),
    H.call(function()
      H.log(string.format("[cid] trip %d: home at f%d, health %d%s", trip, H.frame, health(),
        cidDead() and " -- LOST (30 or less entering the house)" or ""))
    end),
    H.cond(function() return not cidDead() end, { talkCid() }, {}),
    H.call(function()
      fed[#fed + 1] = string.format("%d:{%s}", trip, table.concat(caughtTrip, ","))
      if trip == 1 then
        -- the first reroll this attempt drew (spawn switches $0369-$036C)
        -- and where the field RNG stood ($1F6D): what the ladder's spread
        -- has to move for a reload to be a different draw
        firstRoll = string.format("%d%d%d%d rand $%02X", sw(0x369), sw(0x36A), sw(0x36B), sw(0x36C), H.readByte(0x1F6D))
      end
      H.log(string.format("[cid] trip %d done: %d frames, caught {%s}, health %d -> %d%s",
        trip, H.frame - tripStart, table.concat(caughtTrip, ", "), healthBefore, health(),
        cidWell() and " -- RECOVERED" or ""))
    end),
  }, "feeding Cid")
end

-- The ladder.  Every attempt starts from the island save; a lost one is
-- reloaded from its snapshot, the moment the save completed -- what a
-- person who loses him and reloads that save plays on from.  The reload
-- repeats the machine exactly, so a reloaded attempt lingers SPREAD
-- frames more per rung on its first look at the beach (a person after a
-- reload does not replay the same frames either); the fish swim on
-- meanwhile and move the field RNG, and the first reroll it draws is
-- asserted to differ from every earlier attempt's, so a ladder of losses
-- is that many different draws and not one draw replayed.  The attempt
-- lines are the record: a recovery on attempt n is a search-selected
-- result, not a rate (docs/design/wor-start.md has the measured rate).
local SPREAD = 23
local function cidAttempt(n)
  return H.cond(function() return cidSaved end, {}, {
    n > 1 and seq({
      (function()
        local req
        return seq({
          H.call(function() req = H.requestLoadState(islandBlob) end),
          H.waitFrames(2),
          H.call(function()
            H.checkReq(req, "reload the island save")
            H.log(string.format("[cid] attempt %d: the island save reloaded at f%d, health %d", n, H.frame, health()))
          end),
          H.waitFrames(60),
        })
      end)(),
    }) or seq({}),
    H.call(function()
      trip, fed, firstRoll = 0, {}, nil
      spreadLeft = (n - 1) * SPREAD
      H.log(string.format("[cid] attempt %d from the island save: health %d, the first look lingers %d frames",
        n, health(), spreadLeft))
    end),
    -- back onto (76,240), the world entrance into 396 (8,12)
    (function()
      local W = H.newWalkFighter("the island's entrance")
      return H.driveUntil(function()
        return map() == MAP_ISLE and ready()
      end, 3000, {
        H.call(function()
          if W.frame() then return end
          if not H.worldMode() then H.setPad({}); return end
          if not (H.worldHasControl() and H.worldAligned()) then H.setPad({}); return end
          if H.worldX() == 76 and H.worldY() == 240 then H.setPad({ up = true })
          elseif H.worldY() < 240 then H.setPad({ down = true })
          else H.setPad({ up = true }) end
        end),
      }, "onto the island's entrance (76,240)")
    end)(),
    feedCid(),
    H.call(function()
      if cidWell() then
        cidSaved = true
        attemptLog[#attemptLog + 1] = string.format("attempt %d: Cid RECOVERED on trip %d at f%d, first reroll %s",
          n, trip, H.frame, tostring(firstRoll))
      else
        attemptLog[#attemptLog + 1] = string.format("attempt %d: Cid LOST on trip %d at f%d (health %d entering the house), first reroll %s; fed %s",
          n, trip, H.frame, health(), tostring(firstRoll), table.concat(fed, " "))
        H.log("[cid] " .. attemptLog[#attemptLog])
      end
      for k = 1, n - 1 do
        if rolls[k] ~= nil and rolls[k] == firstRoll then
          error(string.format("attempt %d drew attempt %d's first reroll (%s): the reload's spread did not move the draw",
            n, k, firstRoll), 0)
        end
      end
      rolls[n] = firstRoll
    end),
  })
end

H.run({ maxFrames = 1700000 }, {
  H.loadState("build/states/wor_landing.mss.lua"),
  H.waitFrames(2),
  H.call(function()
    local c = 0x1600 + 37 * CELES
    local members = H.partyMembers()
    H.log(string.format("[wor] boot f%d: map %d (%d,%d), party %d, CELES L%d HP %d/%d MP %d, Cid health %d, timer 0 flags $%02X at $%04X, fish %d%d%d%d, tonic=%d potion=%d fenix=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), #members, H.readByte(c + 8), H.charHp(CELES),
      H.charMaxHp(CELES), H.charMp(CELES), health(), H.readByte(0x1188), H.readWord(0x118B),
      sw(0x369), sw(0x36A), sw(0x36B), sw(0x36C), H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0)))
    H.assertEq(map(), MAP_HOUSE, "wor_landing: Cid's house on the Solitary Island (397)")
    H.assertEq((H.readByte(0x1E94) >> 4) & 1, 1, "wor_landing: $00A4 set -- the World of Ruin")
    H.assertEq(#members == 1 and members[1] == CELES, true, "wor_landing: the party is Celes alone")
    H.assertEq(cidWell() or cidDead(), false, "wor_landing: Cid neither recovered nor lost yet")
    H.assertEq(H.readByte(0x1188), 0x80, "wor_landing: Cid's clock (timer 0, FIELD_ONLY) is running")
    H.assertEq(health() > 30 and health() <= 256, true, "wor_landing: Cid's health is between the two outcomes")
  end),

  -- ---- 1. dress CELES ---------------------------------------------------------
  -- Relics first: the Genji Glove opens her left hand to a second weapon
  -- (owner guideline: it stays on the boost-Fighter, and alone she is
  -- that), and the Czarina Ring beside it (item_prop_en.dat byte $0D = $03:
  -- Safe and Shell when her HP runs low, the Barrier Ring's $01 doubled --
  -- a solo's insurance).  Leaving the Relic screen with the Genji Glove
  -- changed runs the game's own Optimum on her gear (measured: 11 0E 76 8F,
  -- Break Blade / Blizzard / Gold Helmet / Gold Armor, the bag's strongest
  -- by item_prop_en.dat battle power and defense), so the gear session
  -- below only confirms it: each slot's ladder lists what Optimum picks
  -- first and the next-best in the bag after it.
  H.call(function() healthBefore = health() end),
  H.equipKit(CELES, { { 4, 0xD1 }, { 5, 0xC1 } }, { tag = "CELES relics" }),
  H.equipKit(CELES, { { 0, 0x11 }, { 0, 0x0F },
                      { 1, 0x0E }, { 1, 0x0F }, { 1, 0x5C },
                      { 2, 0x76 }, { 2, 0x6E },
                      { 3, 0x8F }, { 3, 0x89 } }, { tag = "CELES gear", ladder = true }),
  H.call(function()
    local c = 0x1600 + 37 * CELES
    H.log(string.format("[wor] CELES dressed: %02X %02X %02X %02X %02X %02X; Cid health %d before the menus, %d after",
      H.readByte(c + 0x1F), H.readByte(c + 0x20), H.readByte(c + 0x21), H.readByte(c + 0x22),
      H.readByte(c + 0x23), H.readByte(c + 0x24), healthBefore, health()))
    H.assertEq(H.readByte(c + 0x1F) ~= 0xFF, true, "CELES holds a weapon")
    H.assertEq(H.readByte(c + 0x22) ~= 0xFF, true, "CELES wears armor")
    H.assertEq(H.readByte(c + 0x23), 0xD1, "CELES wears the Genji Glove")
  end),

  -- ---- 2. the island save --------------------------------------------------------
  -- Off 396's west edge onto the island's own tile on the World of Ruin
  -- map (the opening's parent map, set_parent_map 1, {76, 240}; Celes
  -- arrives on (76,239), one north of the entrance back in).  The world
  -- map allows saving, and Cid's clock stands still there (the field
  -- timer runs in the field loop only: 600 frames on the island, health
  -- 114 -> 114, build/attempts/wt/wor-start/lab/probe_wor_islesave_1.log).
  -- A person who knows he can be lost saves here first: it is the first
  -- save the World of Ruin offers.
  through(100, 46, "down", MAP_ISLE, "the house door -> 396"),
  H.navTo(1, 7, { maxFrames = 3000, playBattles = "tactical" }),
  (function()
    local W = H.newWalkFighter("off the island's west edge")
    return H.driveUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned() and bright() >= 15
    end, 1800, {
      H.call(function()
        if W.frame() then return end
        H.setPad(H.worldMode() and {} or { left = true })
      end),
    }, "the island's tile on the World of Ruin map")
  end)(),
  H.call(function()
    H.log(string.format("[wor] the island on the world map: world %d at (%d,%d), Cid health %d",
      H.worldId(), H.worldX(), H.worldY(), health()))
    H.assertEq(H.worldId(), 1, "the island is on the World of Ruin map")
  end),
  H.saveGame({ slot = 3, tag = "the island save" }),
  H.call(function()
    local s = H.savedSlot()
    H.log(string.format("[saved] the island save: slot %d holds map %d ($%04X) world tile (%d,%d), Cid health %d",
      s.slot, s.map, s.mapWord, s.worldX, s.worldY, health()))
    H.assertEq(s.map == 1 and s.worldX == H.worldX() and s.worldY == H.worldY(), true,
      "the island save is the battery's slot 3")
  end),
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "the island save's snapshot")
        islandBlob = req.blob
        H.log(string.format("[cid] the island save's snapshot at f%d, health %d", H.frame, health()))
      end),
    })
  end)(),

  -- ---- 3. feed Cid, reloading the island save if he is lost ---------------
  cidAttempt(1), cidAttempt(2), cidAttempt(3), cidAttempt(4),
  H.call(function()
    for _, line in ipairs(attemptLog) do H.log("[cid] ladder: " .. line) end
    if not cidSaved then
      error(string.format("Cid died on all %d attempts from the island save; the attempt lines above "
        .. "are the finding (a lab candidate)", #attemptLog), 0)
    end
    H.log(string.format("[cid] Cid recovered on attempt %d, trip %d, at f%d, health %d ($00B3=%d $00B4=%d, timer 0 flags $%02X)",
      #attemptLog, trip, H.frame, health(), sw(0xB3), sw(0xB4), H.readByte(0x1188)))
    H.assertEq(cidDead(), false, "Cid is alive")
  end),

  -- ---- 4. the raft ---------------------------------------------------------------
  H.navTo(85, 50, { maxFrames = 6000, playBattles = "tactical" }),
  H.talkToObj(OBJ_RAFT, "the raft"),
  (function()
    local t, lastMap, lastDlg = 0, -1, -1
    return H.driveUntil(function()
      t = t + 1
      if map() ~= lastMap then
        lastMap = map()
        H.log(string.format("[wor] the voyage: map %d at f%d", lastMap, H.frame))
      end
      return H.worldMode() and H.worldId() == 1 and H.worldHasControl() and bright() >= 15
    end, 20000, {
      H.call(function()
        if H.dialogWaiting() then
          local dlg = H.readWord(0x00D0)
          if dlg ~= lastDlg then lastDlg = dlg; H.log(string.format("[wor] the voyage: dialog $%04X", dlg)) end
          H.assertEq(H.readByte(0x056F) < 2, true, "no choice prompt on the raft")
          H.setPad(t % 16 < 4 and { "a" } or {})
          return
        end
        H.setPad({})
      end),
    }, "Cid's farewell and the raft to the World of Ruin")
  end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end, 600, "landed", 1),
  H.call(function()
    H.log(string.format("[wor] landed: world %d at (%d,%d) f%d, CELES HP %d/%d",
      H.worldId(), H.worldX(), H.worldY(), H.frame, H.charHp(CELES), H.charMaxHp(CELES)))
    H.assertEq(H.worldId(), 1, "the World of Ruin map")
    H.assertEq(H.worldX() == LANDING_X and H.worldY() == LANDING_Y, true, "the raft's landing (146,212)")
    H.assertEq(sw(0xB3), 1, "Cid recovered ($00B3)")
  end),

  -- ---- 5. the first save after the island ------------------------------------
  H.saveGame({ slot = 3, tag = "wor-start-v1 save" }),
  H.call(function()
    -- what the battery holds (#218), read back from the slot's own copy of
    -- $1F64 and $1F60/$1F61: the World of Ruin map is map 1, where
    -- H.assertSavedSlotWorld expects the World of Balance's 0
    local s = H.savedSlot()
    H.log(string.format("[saved] wor-start-v1: slot %d holds map %d ($%04X) world tile (%d,%d)",
      s.slot, s.map, s.mapWord, s.worldX, s.worldY))
    H.assertEq(s.slot, 3, "wor-start-v1: the save went to slot 3")
    H.assertEq(s.map, 1, "wor-start-v1: saved on the World of Ruin map")
    H.assertEq(s.worldX, LANDING_X, "wor-start-v1: saved world x")
    H.assertEq(s.worldY, LANDING_Y, "wor-start-v1: saved world y")
    -- the boundary's own table (lib/ot6_contract.lua), which the WoR
    -- generators' cold Continue asserts as their entry contract
    H.assertExitContract("wor-start-v1")
    H.screenshot("wor_start")
  end),
  H.saveState("wor_start.mss"),
  H.logStep(function()
    return string.format("wor_start generated: Cid saved on trip %d, CELES on the World of Ruin at (%d,%d), saved in slot 3",
      trip, H.worldX(), H.worldY())
  end),
})
