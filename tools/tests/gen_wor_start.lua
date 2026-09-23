-- gen_wor_start.lua -- Cid saved, the raft, and the first save after the
-- Solitary Island: cold-Continue the `wor-island-v1` battery (CELES on the
-- island's own World of Ruin tile (76,239), Cid not yet fed), feed Cid
-- until he recovers, ride his recovery scene, the raft and the voyage, and
-- save on the World of Ruin map where the raft lands.  Generates
-- wor_start.mss, and its capture run (OT6_CAPTURE_SRM) cuts the
-- `wor-start-v1` battery.
--
-- The route (docs/design/wor-start.md has the measurements):
--   1. Back onto (76,240), the island's way in (-> 396 (8,12)).
--   2. Feed Cid, the way a person does it: down onto the fishing beach
--      (396 row 14 -> 398 (4,2)), catch fish by facing one from the shore
--      and pressing A, back into the house (396 (8,6) -> 397) and talk to
--      him from (99,38).  His health is event var 7 ($1FD0), -1 each time
--      the 64-frame field timer fires (_ca533f); every talk rerolls which
--      of the four fish swim (_ca534a, 50% each) and feeds him what Celes
--      holds: the NORMAL-speed fish +32, the two SLOW ones +16 and -4, the
--      SLOWER one -16 (_ca5370).  He recovers when fed above 256, and is
--      lost if Celes walks into the house with 30 or less (_caf42d).
--      POLICY (visible cues only: a fish's swim speed, $0875), the lab's
--      pick: the fast fish when it swims, and a slow one beside it; no
--      fast fish, straight back to Cid for the next reroll (see POLICY
--      below).
--   3. A lost Cid is a lost attempt: the body raises "LOST: ...", which the
--      segment runner files as class `lost` and retries from the boot
--      checkpoint like a wipe (bounded, `[retry]` lines, audit_retries).
--      The draw a retry meets is moved by the runner's seed shift, idled
--      on the fishing beach after the first visit's catches (the boot
--      point, below), where the fish swim and spend the field RNG the
--      talk's reroll reads; each attempt logs its first draw beside any
--      earlier failed attempt's.
--   4. His recovery scene reveals the stairs; walk down to the raft
--      (397 (85,51)) and talk to it: his farewell, the voyage, and the
--      landing on the World of Ruin map at (146,212).
--   5. Save through the real Save UI into slot 3 and assert the battery
--      holds that world save and the wor-start-v1 contract.
-- Nothing is written; every catch, talk and step is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- The fishing policy.  The lab (tools/tests/fishlab.py, docs/design/
-- wor-start.md "The lab") played each of these from this checkpoint, on
-- the search shifts and again on held-out ones; "near" ships: like "all"
-- it recovers Cid on nearly every draw this generator meets, held-out ones
-- included, and it loses less than "all" when the talk's rolls are fair
-- coins (a model of a person's timing): "all" leans on the RNG path this
-- generator's fixed timing walks (the doc has the numbers).
--   "near"      the fast fish if it swims, plus a slow fish that swims up
--               beside her on the way, plus a slow one still within
--               SLOW_AFTER_FAST frames once the fast one is caught; no fast
--               fish: straight back to Cid (the talk is the reroll)
--   "fast"      the fast fish only
--   "fastslow"  the fast fish, then every slow fish, however long it takes
--   "all"       every fish but the slowest, whether or not the fast one swims
--   "allnear"   "near" while the fast fish swims; every slow fish when it
--               does not
--   "wait"      "near", but stand at WAIT_SPOT and let the fish come
-- Never the slowest fish (-16) under any of them.
local POLICY = "near"
local SLOW_AFTER_FAST = 240
local WAIT_SPOT = { 8, 12 }   -- the land-edge tile beside the fast fish's two likeliest shore tiles

local CELES = 6
local MAP_HOUSE, MAP_ISLE, MAP_BEACH = 397, 396, 398
local OBJ_RAFT = 0x13                               -- npc_prop 397 record 4 (the raft)
local GFX_FISH = 0x3A                               -- include/gfx/map_sprite_gfx.inc FISH
local SPEED_FAST, SPEED_SLOW = 2, 1                 -- $0875: NORMAL 2, SLOW 1, SLOWER 0
local TALK_X, TALK_Y = 99, 38                       -- beside the bed, facing right
local LANDING_X, LANDING_Y = 146, 212               -- _ca5633: load_map 1, {146, 212}
local CATCH_GIVEUP = 2400                           -- frames on one fish before leaving it
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

local trip, fed, caughtTrip, firstDraw = 0, {}, {}, nil
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
  local seen, list, target, tStart, ph, fastSeen, fastCaughtAt, arrived =
    nil, nil, nil, 0, 0, false, nil, nil
  local present, skip = {}, {}
  local function wanted(i)
    if not isFish(i) or skip[i] then return false end
    local sp = objSpeed(i)
    if sp >= SPEED_FAST then return true end
    if sp ~= SPEED_SLOW then return false end                    -- never the slowest
    if POLICY == "fast" then return false end
    if POLICY == "all" or POLICY == "fastslow" then return true end
    -- "allnear" with no fast fish swimming: every slow fish
    if POLICY == "allnear" and not fastSeen then return true end
    -- "near" / "wait" / "allnear": a slow fish is worth it only beside the
    -- fast one's catch: while the fast fish swims, or for a moment after it
    -- is caught
    if fastCaughtAt then return H.frame - fastCaughtAt <= SLOW_AFTER_FAST end
    return true
  end
  local function anyWanted()
    for i = 0x10, 0x1F do if wanted(i) then return true end end
    return false
  end
  local step = H.driveUntil(function()
    if not arrived then return false end
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
    if target and H.frame - tStart > CATCH_GIVEUP then
      H.log(string.format("[cid] trip %d: left fish %02X after %d frames", trip, target, H.frame - tStart))
      skip[target] = true; target = nil
    end
    -- no fast fish: the visit is over (the talk rerolls), except under "all"
    -- and "allnear"
    if POLICY ~= "all" and POLICY ~= "allnear" and not fastSeen then return true end
    -- standing and waiting has the same patience as chasing one fish
    if POLICY == "wait" and H.frame - arrived > CATCH_GIVEUP then
      H.log(string.format("[cid] trip %d: left the spot after %d frames", trip, H.frame - arrived))
      return true
    end
    return not anyWanted()
  end, 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      if not arrived then
        arrived = H.frame
        seen, list = reachable()
        for i = 0x10, 0x1F do
          if isFish(i) then
            present[i] = objSpeed(i)
            if objSpeed(i) >= SPEED_FAST then fastSeen = true end
          end
        end
        H.log(string.format("[cid] trip %d: the beach at f%d, health %d, fish %s",
          trip, H.frame, health(), fishSet()))
      end
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
      if POLICY == "wait" then
        -- stand on the spot and let them come
        if px == WAIT_SPOT[1] and py == WAIT_SPOT[2] then H.setPad({}); return end
        local p = H.bfsPath(WAIT_SPOT[1], WAIT_SPOT[2])
        H.setPad(p and #p > 0 and { [H.movePress(p[1])] = true } or {})
        return
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
        tStart = H.frame
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
    seen, list, target, tStart, ph, fastSeen, fastCaughtAt, arrived = nil, nil, nil, 0, 0, false, nil, nil
    present, skip = {}, {}
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

-- this attempt's first draw, the moment the first talk has rerolled: the
-- spawn switches it set ($0369-$036C), where the field RNG index stood
-- ($1F6D, field/reset.asm Rand) and Cid's health after the feed.  Logged,
-- and compared with every earlier failed attempt's (its LOST line carries
-- it) -- a record, not a gate: the same first draw can still play on
-- differently (the runner's shifted idle moves the fish that walk the RNG
-- afterwards; the lab's near shifts 483 and 490 drew `roll 1100 rand $EC
-- health 132` and one recovered Cid while the other lost him), so the
-- runner's shifted attempts are the variation.
local function noteFirstDraw()
  firstDraw = string.format("roll %d%d%d%d rand $%02X health %d", sw(0x369), sw(0x36A),
    sw(0x36B), sw(0x36C), H.readByte(0x1F6D), health())
  local same = {}
  for _, f in ipairs(H.attemptFailures()) do
    if tostring(f.msg):match("first draw %[(.-)%]") == firstDraw then same[#same + 1] = tostring(f.attempt) end
  end
  H.log(string.format("[cid] first draw: %s%s", firstDraw, #same > 0 and string.format(
    " (the same first draw as failed attempt %s; the continuation can still differ)",
    table.concat(same, ", ")) or ""))
end

local tripStart, healthBefore, beachMarked = 0, 0, false
local function bright15() return bright() >= 15 end
-- maxFrames: one attempt's budget, more than twice the slowest the lab saw:
-- under "near" Cid recovered by f82,915 at most (62 trips;
-- docs/design/wor-start.md).
-- bootFallback = false: the boot point is marked on the beach after the
-- first visit (below), whenever that visit ends: f2314 under this policy,
-- just inside the runner's own 2400-frame fallback, but a visit that waits
-- longer (the lab's "wait": past f2400) would be pre-empted by the
-- fallback mid-visit, and every shift would then play one draw.
-- retries: the runner's default 3 for a segment.
H.run({ maxFrames = 200000, bootFallback = false }, {
  -- ---- 0. cold Continue of wor-island-v1 -----------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the island's World of Ruin tile", 10),
  H.waitUntil(bright15, 900, "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    -- The entry contract WITHOUT the boot mark: a seed shift idled here, on
    -- the world map, leaves the first draw as it was (measured: shifts
    -- 0/15/30/45 all drew "roll 1010 rand $BC health 139", though they
    -- went on to recover Cid on trips 37/42/37/54;
    -- docs/design/wor-start.md "What varies the draw").  The boot point is
    -- on the beach instead (below).
    H.assertContract("wor-island-v1", "entry")
    local c = 0x1600 + 37 * CELES
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), CELES L%d HP %d/%d MP %d, Cid health %d, timer 0 $%02X/%d, fish %d%d%d%d, rand $%02X, policy %s",
      H.frame, H.worldId(), H.worldX(), H.worldY(), H.readByte(c + 8), H.charHp(CELES),
      H.charMaxHp(CELES), H.charMp(CELES), health(), H.readByte(0x1188), H.readWord(0x1189),
      sw(0x369), sw(0x36A), sw(0x36B), sw(0x36C), H.readByte(0x1F6D), POLICY))
    H.assertEq(health() > 30 and health() <= 256, true, "wor-island-v1: Cid's health is between the two outcomes")
  end),

  -- ---- 1. back onto the island ----------------------------------------------------
  (function()
    local W = H.newWalkFighter("the island's entrance")
    return H.driveUntil(function()
      return map() == MAP_ISLE and ready()
    end, 3000, {
      H.call(function()
        if W.frame() then return end
        if not H.worldMode() then H.setPad({}); return end
        if not (H.worldHasControl() and H.worldAligned()) then H.setPad({}); return end
        H.setPad(H.worldY() < 240 and { down = true } or { up = true })
      end),
    }, "onto the island's entrance (76,240)")
  end)(),

  -- ---- 2. feed Cid -----------------------------------------------------------------
  H.driveUntil(function()
    if cidDead() then
      error(string.format("LOST: Cid died -- health %d as Celes walked into the house on trip %d; "
        .. "first draw [%s]; fed %s", health(), trip, tostring(firstDraw), table.concat(fed, " ")), 0)
    end
    if trip >= TRIP_CAP and not cidWell() then
      error(string.format("Cid neither recovered nor lost after %d trips (health %d)", trip, health()), 0)
    end
    return cidWell()
  end, 180000, {
    H.call(function()
      trip = trip + 1; caughtTrip = {}; tripStart = H.frame; healthBefore = health()
    end),
    H.cond(function() return map() == MAP_HOUSE end,
      { through(100, 46, "down", MAP_ISLE, "the house door -> 396") }, {}),
    through(8, 14, "down", MAP_BEACH, "396 -> the beach 398"),
    fishing(),
    -- the boot point: this attempt's seed shift idles here, on the beach
    -- after the first visit's catches, a beat before the walk back.  The
    -- fish and the bird walk the field RNG ($1F6D) while Celes stands
    -- there, and the next talk's reroll reads it.  An idle earlier (at the
    -- Continue, or on first reaching the beach) leaves the first draw as
    -- it was -- the first catch waits on the fish, which swim on the map's
    -- own clock -- though not the rest of the run
    -- (docs/design/wor-start.md "What varies the draw")
    H.cond(function() return not beachMarked end, {
      H.call(function()
        beachMarked = true
        H.bootMark(string.format("the fishing beach 398 after trip 1's catches (health %d, rand $%02X)",
          health(), H.readByte(0x1F6D)))
      end),
    }, {}),
    through(4, 1, "up", MAP_ISLE, "the beach -> 396"),
    through(8, 6, "up", MAP_HOUSE, "396 -> the house"),
    H.call(function()
      H.log(string.format("[cid] trip %d: home at f%d, health %d%s", trip, H.frame, health(),
        cidDead() and " -- LOST (30 or less entering the house)" or ""))
    end),
    H.cond(function() return not cidDead() end, { talkCid() }, {}),
    H.call(function()
      fed[#fed + 1] = string.format("%d:{%s}", trip, table.concat(caughtTrip, ","))
      if trip == 1 and not cidDead() then noteFirstDraw() end
      H.log(string.format("[cid] trip %d done: %d frames, caught {%s}, health %d -> %d%s",
        trip, H.frame - tripStart, table.concat(caughtTrip, ", "), healthBefore, health(),
        cidWell() and " -- RECOVERED" or ""))
    end),
  }, "feeding Cid"),
  H.call(function()
    H.log(string.format("[cid] Cid recovered on trip %d at f%d, health %d ($00B3=%d $00B4=%d, timer 0 flags $%02X), policy %s, first draw [%s]",
      trip, H.frame, health(), sw(0xB3), sw(0xB4), H.readByte(0x1188), POLICY, tostring(firstDraw)))
    H.assertEq(cidDead(), false, "Cid is alive")
  end),

  -- ---- 3. the raft ---------------------------------------------------------------
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

  -- ---- 4. the first save after the island ------------------------------------
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
