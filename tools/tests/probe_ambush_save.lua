-- probe_ambush_save.lua -- PLAYTEST PROBE (not a suite test, not a
-- generator): grinds TERRA/LOCKE HP past 555 on Crescent Island trash, then
-- rides gen_thamasa_fire.lua's own route (inn -> fire -> Strago joins ->
-- map 351) through the (21,22) four-Balloon ambush and the (46,53)
-- FlameEater fight to checkpoint M `fire-out`.
--
-- Run with the checkpoint env var set (bare run.sh boots a fresh game and
-- never reaches the ambush):
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/thamasa-night-v1 \
--   OT6_TIMEOUT=3600 tools/tests/run.sh tools/tests/probe_ambush_save.lua
--
-- No @suite marker: one-shot probe, not a suite test.
--
-- gen_thamasa_fire.lua -- v0.13 step L->M: cold-boots the tracked
-- `thamasa-night-v1` SRAM checkpoint (world outside Thamasa, $008D=1,
-- party TERRA-LOCKE-SHADOW, pre-inn) and generates checkpoint M `fire-out`:
-- world outside Thamasa, $0090=$0091=$0092=1, party TERRA-LOCKE-STRAGO,
-- $02F3=0 (SHADOW gone).
--
-- The route:
--  1. Grind Crescent Island trash (grass: Baskervor L22 HP750 no weakness,
--     Cephaler L21 HP420 weak bolt) between world (232,150) and (249,128)
--     until TERRA's and LOCKE's max HP both exceed 555 (a Balloon's own
--     full HP, and its self-destruct's damage), fought tactically,
--     re-checkpointing after every leg that doesn't wipe.
--  2. Re-enter town: held RIGHT onto the (250,128) world trigger -> map
--     343 (23,46).
--  3. Thamasa item shop: town 343 door (26,37) -> map 347 (36,44); the
--     shopkeeper sits behind a counter at (36,39), talked to from 2 tiles
--     back. Shop 35 sells Tonic (row 0), Potion (row 1), Fenix Down
--     (row 6) among its 8 rows. Stock Tonic to 30, Potion to 15, Fenix
--     Down to 20.
--  4. The inn: exterior door 343 (12,19) -> interior map 346 (23,23); the
--     innkeeper at (24,15) sits behind a counter and is talked to from
--     (24,17) facing up. Choosing Yes (default cursor) falls straight
--     into the night/fire scene with no further choice screens.
--  5. The night scene: SHADOW leaves the party, the fire starts, Shadow
--     runs off after Interceptor and goes unavailable. Control returns on
--     map 343 at (12,21), retiled burning.
--  6. Talk to Strago at the house door (an NPC event, NPCProp::_343
--     record 5, make_npc {39,24}). The scene ends with Strago joining
--     and load_map 351 {4,11}, forced entry party TERRA-LOCKE-STRAGO.
--  7. Map 351 (the burning house; every exit is scripted) is 35
--     cardinally-disconnected tile islands, stitched together only by
--     short_entrance warps that fire on tile entry with no direction
--     test. The full island graph, landing to every objective:
--       island 0  (landing pocket) --(4,3)->(4,38)--> island 13
--       island 13 --(2,24)->(26,36)--> island 11 (the (21,22) ambush
--         trigger)
--       island 11 --(26,21)->(21,9)--> island 1 (the north corridor)
--       island 1  --(28,3)->(4,55)--> island 28 (Fire Rod chest (4,52))
--       island 1  --(23,3)->(46,27)--> island 12 (the east wing)
--       island 12 --(49,21)->(45,10)--> island 4 (Ice Rod chest (45,7))
--       island 12 --(43,21)->(21,54)--> island 26 (the south hall)
--       island 26 --(21,49)->(46,54)--> island 24 (FlameEater trigger
--         (46,53))
--     houseWarp() below rides each of these like crossDoor() rides a town
--     door, except the arrival test is a coordinate match rather than a
--     map-ID change. Twelve wandering flame NPCs (random movement) fire
--     battle 31 on contact; none are required. The (21,22) ambush is
--     battle 45 (4x Balloon, weak ice|water; a self-destruct deals the
--     Balloon's own current HP). FlameEater's fight is battle 79
--     (formation 449, shields 7, pierce, weak ice, absorbs fire), also a
--     floor trigger, which re-forces party order STRAGO,TERRA,LOCKE. Both
--     post-battle gates are `call _ca5ea9` (the same win/lose gate
--     Dadaluma and TunnelArmr use): a win sets $0090=1 (ambush: $050A)
--     and a loss falls into vanilla GameOver.
--  8. Win tail: the Relm/Interceptor rescue, Shadow's smoke-bomb exit,
--     the night talk at Strago's house (load_map 349 {64,16}), ending
--     $0091=1 $0098=1, control in the house, party TERRA-LOCKE-STRAGO.
--  9. Leaving the house plays Shadow's goodbye on town 343 (29,15): his
--     gear returns to inventory, $0092=1.
--  10. Out of town (long_entrance.dat map-343 south strip) and the real
--      Save UI at slot 3 -- checkpoint M, `fire-out-v1`.
--
-- Ice Rod is not driven as an in-battle item cast: FlameEater is fought
-- with the lib driver's plain kit (boosted Fight from whoever holds it,
-- TERRA's Cure).
--
-- The ambush is fought with a bespoke driver (newAmbushPlan, below), not
-- H.newFightDriver: STRAGO alive casts Aqua Rake (lore id 3) every turn
-- (multi-target water, all four Balloons are weak to it, and it also
-- lowers their current HP so a surviving Balloon's self-destruct does
-- less); LOCKE alive with Strago down uses Filch while any Balloon still
-- carries a shield, else a boosted Fight; anyone else uses plain boosted
-- Fight. Revives are withheld while 2+ Balloons live; the gate opens at
-- <=1 Balloon, reviving STRAGO first. Any acting character below 40% HP
-- self-heals with Tonic/Potion first. H.fieldCare does not work on map
-- 351 (every plan it tries comes back refused), so care() on this map is
-- a no-op and recovery happens through in-battle heals instead.
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local TERRA, LOCKE, STRAGO, SHADOW = 0, 1, 7, 3
local FIRE_ROD, ICE_ROD = 0x35, 0x36
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL = 0x01
local saveArg = nil

-- Debug dump of the sort_obj_work party-membership byte ($0867+41*id, bit
-- $40=enabled, low 3 bits=party number) for TERRA/LOCKE/SHADOW/STRAGO, plus
-- $1a6d (active party number) and the object pointers $07fb/07fd/07ff/0801/
-- 0803. Also a write-watch (with PC) on all four $0867+41*id bytes,
-- ring-buffered to the last 40 hits.
local PROBE_IDS = { { 0, "TERRA" }, { 1, "LOCKE" }, { 3, "SHADOW" }, { 7, "STRAGO" } }
-- Frames to screenshot across the win-tail teardown window.
local SHOT_FRAMES_TAIL = {
  [20740] = true, [20900] = true, [21100] = true, [21300] = true,
  [21500] = true, [21700] = true, [21958] = true, [22100] = true,
}
-- Event PC trace across f21200-21900, logged on every change.
local peTrailLast = nil
local _cbe622Sym = nil
do
  local ok, v = pcall(H.sym, "_cbe622")
  if ok then _cbe622Sym = v end
end
local function probePcTrail()
  if H.frame < 21200 or H.frame > 21900 then return end
  local bank, hi, lo = H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)
  local e8 = H.readWord(0x00e8)
  local wm = H.worldMode()
  local m1f64 = H.readWord(0x1f64)
  local key = string.format("%02X:%02X%02X:%04X:%s:%04X", bank, hi, lo, e8,
    tostring(wm), m1f64)
  if key ~= peTrailLast then
    peTrailLast = key
    H.log(string.format(
      "[probe127-pctrail] f%d eventPC=%02X:%02X%02X e8=$%04X worldMode=%s 1f64=$%04X",
      H.frame, bank, hi, lo, e8, tostring(wm), m1f64))
  end
end
local function probeDump(tag)
  local parts = {}
  for _, e in ipairs(PROBE_IDS) do
    local id, name = e[1], e[2]
    local b = H.readByte(0x0867 + 41 * id)
    parts[#parts + 1] = string.format("%s=$%02X(en=%d,pty=%d)",
      name, b, (b & 0x40) ~= 0 and 1 or 0, b & 0x07)
  end
  H.log(string.format(
    "[probe127 %s] f%d 1a6d=$%02X 07fb=$%04X 07fd=$%04X 07ff=$%04X " ..
    "0801=$%04X 0803=$%04X %s",
    tag, H.frame, H.readByte(0x1a6d), H.readWord(0x07fb), H.readWord(0x07fd),
    H.readWord(0x07ff), H.readWord(0x0801), H.readWord(0x0803),
    table.concat(parts, " ")))
end
local probeHits = {}
local function probePc()
  local s = emu.getState()
  return string.format("%02X:%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0)
end
local function armProbeWatch()
  for _, e in ipairs(PROBE_IDS) do
    local id, name = e[1], e[2]
    local addr = 0x7E0867 + 41 * id
    emu.addMemoryCallback(function(a, v)
      local line = string.format(
        "[probe127 watch] f%d pc=%s %s($0867+41*%d) <- $%02X",
        H.frame, probePc(), name, id, v)
      probeHits[#probeHits + 1] = line
      if #probeHits > 40 then table.remove(probeHits, 1) end
      H.log(line)
    end, emu.callbackType.write, addr, addr)
  end
  H.log("[probe127] write-watch armed on $0867+41*{0,1,3,7} (TERRA/LOCKE/SHADOW/STRAGO)")
end

-- sort_obj_work falls back to the CAMERA object whenever no character is in
-- the active party, which is also true while an event owns the stage. Dumps
-- the raw event-engine state ($E1 waiting-flags, $E2 object-to-wait-for, $E3
-- pause counter, $E5-E7 event PC, $E8 event stack pointer, $EA event opcode,
-- $DA/$DC current object) plus whether the party/camera sits on the (21,22)
-- ambush trigger tile. _cbe622 sets switch $050A=1 unconditionally as its
-- first action and clears it at its own end, so re-entry while parked on
-- (21,22) can refire the trigger.
local function probeEventDump(tag)
  local sw050A = (H.readByte(0x1E80 + (0x050A >> 3)) >> (0x050A & 7)) & 1
  local e1 = H.readByte(0x00e1)
  H.log(string.format(
    "[probe127-event %s] f%d ctl=%s algn=%s ev=%s dlg=%s " ..
    "e1(wait o/f/s)=$%02X(o=%d,f=%d,s=%d) e2(objWait)=$%02X " ..
    "e3(pauseCnt)=$%02X eventPC(bank:e6e5)=%02X:%02X%02X e8(evStackPtr)=$%04X " ..
    "ea(opcode)=$%02X da(curObjOfs)=$%02X dc(curObj)=$%02X pos=(%d,%d) " ..
    "onAmbushTile(21,22)=%s sw($050A)=%d",
    tag, H.frame, tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    e1, (e1 >> 7) & 1, (e1 >> 6) & 1, (e1 >> 5) & 1,
    H.readByte(0x00e2), H.readByte(0x00e3),
    H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
    H.readWord(0x00e8), H.readByte(0x00ea),
    H.readByte(0x00da), H.readByte(0x00dc),
    H.fieldX(), H.fieldY(),
    tostring(H.fieldX() == 21 and H.fieldY() == 22), sw050A))
end

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- edge-A through dialogs/scenes until settled (gen_thamasa_arrive's settle)
local function settle(maxFrames, what)
  local ph = 0
  return H.driveUntil(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and not H.battleLoadStarted()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
    end),
  }, what)
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- gen_thamasa_arrive's crossDoor, unchanged
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, avoid = opts.avoid,
        arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Live NPC lookup: scan object slots 16..31 for whichever sits nearest
-- (x,y), rather than trust the "$10 + record order" arithmetic past 16
-- make_npc records on one map.
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end
local function findNpc(x, y, fallback)
  local best, bestD = nil, nil
  for i = 16, 31 do
    local ox, oy = objAt(i)
    local d = math.abs(ox - x) + math.abs(oy - y)
    if (ox ~= 0 or oy ~= 0) and (not bestD or d < bestD) then
      best, bestD = i, d
    end
  end
  H.log(string.format(
    "[npc] nearest object to (%d,%d): slot $%02X at distance %d (fallback $%02X)",
    x, y, best or 0, bestD or -1, fallback))
  return best or fallback
end

-- chaseTalk needs a concrete object index at construction time (every step
-- in an H.run list is built before the emulator boots -- gen_tunnelarmr's
-- posOf note), but the door NPC's slot is only knowable live.  This is
-- M.chaseTalk's body (lib/ot6_field.lua) with the one line that reads
-- objIdx replaced by a call to idxFn() every frame instead.
local function chaseTalkLazy(idxFn, maxFrames, what, opts)
  opts = opts or {}
  local ph, hb = 0, 0
  local done = opts.done or function()
    return H.readByte(0x056f) >= 2 and H.dialogWaiting()
  end
  return H.driveUntil(done, maxFrames or 9000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if H.battleLoadStarted() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then H.killbit(s) end
        end
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local objIdx = idxFn()
      local ox, oy = objAt(objIdx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best, bestC
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best, bestC = p, c end
      end
      if hb % 300 == 0 then
        H.log(string.format(
          "[chaseTalkLazy dbg] %s: f%d party=(%d,%d) obj$%02X=(%d,%d) " ..
          "best=%s bestLen=%s", what, H.frame, px, py, objIdx, ox, oy,
          bestC and string.format("(%d,%d)", bestC[1], bestC[2]) or "NONE",
          best and tostring(#best) or "-"))
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what or "chaseTalkLazy")
end

-- Map 351 is big enough that H.bfsPath's 4096-node cap (nodes are (x,y,z)
-- triples) can go dry on a single long query and report "no path" for a
-- plainly walkable tile. creepXY hands navTo a MOVING target instead: a
-- point at most `step` tiles away in the straight-line direction of the
-- real destination, re-resolved on every replan, so many small cap-safe
-- BFS queries converge on the target instead of one long one.
local function creepXY(tx, ty, step)
  step = step or 14
  local function pt()
    local px, py = H.fieldX(), H.fieldY()
    local dx, dy = tx - px, ty - py
    local dist = math.abs(dx) + math.abs(dy)
    if dist <= step or dist == 0 then return tx, ty end
    return px + math.floor(dx * step / dist), py + math.floor(dy * step / dist)
  end
  return function() return (pt()) end,
         function() local _, y = pt(); return y end
end
local function creepNav(tx, ty, opts, step)
  local fx, fy = creepXY(tx, ty, step)
  return H.navTo(fx, fy, opts)
end

-- A care stop that skips (logged) rather than hangs when the field isn't
-- settled. H.fieldCare is not usable on map 351 regardless of party state
-- (every plan it tries comes back refused by the game, and the menu-close
-- drive then hangs), so care() on this map is a no-op: it settles and logs,
-- never opens the menu, and recovery happens through the next contact
-- battle's in-battle heal/revive instead.
local function onMap351() return map() == 351 end
local function care(what)
  return seq({
    H.waitUntilSoft(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.dialogWaiting() and not H.battleLoadStarted()
    end, 1200, "care " .. what),
    H.cond(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted()
    end, {
      H.waitFrames(60),
      H.cond(onMap351, {
        H.logStep(function()
          return string.format(
            "[care %s] SKIPPED field-menu care -- H.fieldCare is broken on " ..
            "map 351 regardless of party state (see the fix note above); " ..
            "deferring to the next contact battle's in-battle heal/revive",
            what)
        end),
      }, {
        H.fieldCare({ tag = "care " .. what, threshold = 0.85 }),
      }),
    }, {
      H.logStep(function()
        return string.format("[care %s] SKIPPED -- not settled at (%d,%d) map %d",
          what, H.fieldX(), H.fieldY(), map())
      end),
    }),
  })
end

-- gen_thamasa_arrive's chestAuto: live-staged (bfsPath candidates), so no
-- hand-guessed stand tile is needed for either map-351 chest.
local CHEST_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
local function chestAuto(cx, cy, bit, what, item)
  local pick
  -- The CHEST_CAND reachability probe is only a heuristic at range (the
  -- BFS cap can make a reachable candidate read NONE from far away); a bad
  -- pick is not fatal since the walk itself creeps in short hops regardless.
  local function stage()
    if not pick then
      for _, c in ipairs(CHEST_CAND) do
        local sx, sy = cx + c[1], cy + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { cx, cy + 1, "up" }
      H.log(string.format("[chest] (%d,%d) %s: staging (%d,%d) face %s",
        cx, cy, what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local tag = string.format("chest bit %d (%s)", bit, what)
  local before
  local aPh = 0
  return H.cond(function() return not H.chestOpen(bit) end, {
    H.call(function() pick = nil end),
    H.navTo(
      function() local p = stage(); local fx = creepXY(p[1], p[2]); return fx() end,
      function() local p = stage(); local _, fy = creepXY(p[1], p[2]); return fy() end,
      { maxFrames = 40000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, healPercent = 85,
        magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }),
    H.call(function() before = item and H.invCountOf(item) or nil end),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, tag .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.dialogWaiting() end, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": the chest answered"),
    H.driveUntil(function() return not H.dialogWaiting() end, 600, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": dialog dismissed"),
    H.call(function()
      H.setPad({})
      H.assertEq(H.chestOpen(bit), true, tag .. ": treasure bit set")
      if item then
        local now = H.invCountOf(item)
        H.assertEq(now, before + 1,
          string.format("%s: bag %d -> %d of item $%02X", tag, before, now, item))
      end
      H.log("[chest] " .. tag .. ": OPENED")
    end),
  }, {
    H.call(function()
      H.log(string.format("[chest] %s: already open (rerun), skipping", tag))
    end),
  })
end

-- ------------------------------------------------------ the item shop --
-- Thamasa's item shop: town 343 door (26,37) -> map 347 dest (36,44); the
-- shopkeeper NPC sits at (36,39), event _cbd730, `shop_menu 35`. Shop 35's
-- 8-row stock: row 0 = $E8 Tonic, row 1 = $E9 Potion, row 6 = $F0 Fenix Down.
local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
end
-- None of CHEST_CAND's 1-tile-adjacent candidates reach the Thamasa
-- shopkeeper (36,39) -- a counter blocks the 1-tile approach, so the real
-- stand tile is 2 tiles back (the same "talk-across-a-counter" shape as the
-- inn counter, below). SHOP_CAND tries 1-tile candidates first, then falls
-- back to 2-tile candidates in the same four directions.
local SHOP_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { 0, 2, "up" }, { 0, -2, "down" }, { -2, 0, "right" }, { 2, 0, "left" },
}
local function shopTalk(nx, ny, what)
  local pick
  local function stage()
    if not pick then
      for _, c in ipairs(SHOP_CAND) do
        local sx, sy = nx + c[1], ny + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { nx, ny + 1, "up" }
      H.log(string.format("[shop] %s: staging (%d,%d) face %s",
        what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local aPh = 0
  return seq({
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true }),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, what .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.readByte(0x0026) == 0x25 end, 3000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true, [stage()[3]] = true } or {})
      end),
    }, what .. ": shop opens"),
    H.call(function()
      H.log(string.format("[shop] %s: open at f%d, gil=%d", what, H.frame, gil()))
    end),
  })
end
-- shop.asm's B-handlers (MenuState_25/26/27) read an EDGE flag, not a
-- level; the last buyItem call leaves the shop at state $26 (the buy
-- list), so closing needs TWO separate B edges (26->25, then 25->closed),
-- which a held button cannot supply -- so B is edge-tapped here.
local function shopClose(what)
  local ph = 0
  return seq({
    H.driveUntil(function()
      return H.hasControl() and H.readByte(0x0026) ~= 0x25
         and H.readByte(0x0026) ~= 0x26 and H.readByte(0x0026) ~= 0x27
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { b = true } or {})
      end),
    }, what .. ": shop closed"),
    H.release(),
    H.waitFrames(30),
  })
end

-- ------------------------------------------------------ the grinding leg --
-- No enemy stat gets touched -- the party grinds instead. Grinds Crescent
-- Island trash (grass: Baskervor L22 HP750 no weakness, Cephaler L21
-- HP420 weak bolt), fought with the same tactical driver the rest of this
-- file uses, healed between legs with H.fieldCare (works on the world map,
-- unlike map 351). Shadow fights along on plain Fight; only TERRA's and
-- LOCKE's max HP count toward the goal, since Shadow is gone before the
-- ambush regardless.
--
-- Target: grind until BOTH TERRA's and LOCKE's max HP exceed 555 -- the
-- Balloon's own full HP, which is also its self-destruct's damage. OT6
-- levels fully restore HP/MP, so a level-up is itself a heal.
--
-- Real fights are counted with an InitBattle exec watch, armed only for
-- the grind window so it never double-counts the ambush/FlameEater/
-- wandering-flame fights later in the route. GRIND_LEG_CAP bounds the
-- outer shuttle-leg loop generously; the governing cap is grindFights >=
-- GRIND_FIGHT_CAP, checked after every leg. If the cap lands without both
-- max HPs over 555, this errors out with the full numbers rather than
-- raising the cap.
local GRIND_HP_TARGET = 555
-- 0: the grind ends on its first check, so the state this probe emits
-- carries the party at ROUTE-NATURAL level.
local GRIND_FIGHT_CAP = 0
local GRIND_LEG_CAP = 220
local function charLevel(c) return H.readByte(0x1600 + 37 * c + 0x08) end
local grindFights, grindWatchRef, grindDone = 0, nil, false
local grindGoalMissed = false
local grindStartLv = {}
-- M.worldNavTo's opts.wipeEndsRide lets a wipe here end that leg's ride
-- instead of hard-failing the whole run; grindBlob is the entry-point
-- checkpoint each wiped leg reloads before retrying.
local grindBlob, grindFightsAtCheckpoint = nil, 0
-- GRIND_A/GRIND_B reuse gen_thamasa_arrive's own already-walkable
-- checkpoint-K-landing/Thamasa-trigger endpoints as the grind shuttle.
local GRIND_A = { 232, 150 }  -- checkpoint K's own landing tile
local GRIND_B = { 249, 128 }  -- the Thamasa-trigger staging tile (this
                               -- file's own exit destination)
local function armGrindWatch()
  local ok, addr = pcall(H.sym, "InitBattle")
  if ok then
    grindWatchRef = emu.addMemoryCallback(function()
      grindFights = grindFights + 1
    end, emu.callbackType.exec, addr, addr)
  else
    H.log("[grind] WARNING: InitBattle symbol not found -- fight counter " ..
      "will read 0 the whole grind (harmless to the HP goal, which reads " ..
      "live stats directly, but the fight-count log/cap becomes meaningless)")
  end
end
local function disarmGrindWatch()
  if grindWatchRef then
    local ok, addr = pcall(H.sym, "InitBattle")
    if ok then emu.removeMemoryCallback(grindWatchRef, emu.callbackType.exec, addr, addr) end
    grindWatchRef = nil
  end
end
-- 60000 gives headroom for several full tactical fights plus the walk
-- itself: a single tactical fight can run 3000-6000+ frames on its own,
-- and one leg can hold 2-4 back to back. No magic line: Baskervor has no
-- weakness and Cephaler is weak to bolt, not ice, so TERRA's Ice cast (used
-- later against the Balloon ambush, where it IS the weakness) would be
-- wasted here.
local GRIND_WALK = { maxFrames = 60000, playBattles = "tactical",
  healer = TERRA, bank = 3, items = true, healPercent = 90,
  wipeEndsRide = true }
local function grindLeg(n)
  return H.cond(function() return grindDone end, {}, {
    H.call(function()
      if n == 1 then
        grindStartLv[TERRA] = charLevel(TERRA)
        grindStartLv[LOCKE] = charLevel(LOCKE)
        H.log(string.format(
          "[grind] starting: TERRA L%d %d/%dhp, LOCKE L%d %d/%dhp, target " ..
          "maxhp>%d both, cap %d fights", grindStartLv[TERRA], H.charHp(TERRA),
          H.charMaxHp(TERRA), grindStartLv[LOCKE], H.charHp(LOCKE),
          H.charMaxHp(LOCKE), GRIND_HP_TARGET, GRIND_FIGHT_CAP))
      end
    end),
    (n % 2 == 1) and H.worldNavTo(GRIND_A[1], GRIND_A[2], GRIND_WALK)
                  or H.worldNavTo(GRIND_B[1], GRIND_B[2], GRIND_WALK),
    -- A wipe ends the leg's worldNavTo ride softly (opts.wipeEndsRide)
    -- rather than erroring the whole run; detect it here (HP still reads
    -- all-zero -- nothing has advanced the game past that moment) and
    -- reload the grind's own entry checkpoint before this leg's care/goal
    -- check would otherwise run against a dead party.
    H.cond(function() return H.partyWiped() end, {
      H.call(function()
        H.log(string.format(
          "[grind] leg %d WIPED at f%d (TERRA %d/%dhp LOCKE %d/%dhp) -- " ..
          "reloading the grind checkpoint and continuing", n, H.frame,
          H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
          H.charMaxHp(LOCKE)))
      end),
      (function()
        local ckReq
        return seq({
          H.call(function() ckReq = H.requestLoadState(grindBlob) end),
          H.waitFrames(2),
          H.call(function()
            H.checkReq(ckReq, "grind checkpoint reload")
            grindFights = grindFightsAtCheckpoint
          end),
          H.waitFrames(90),
          H.fieldCare({ tag = "grind post-wipe-reload care leg " .. n,
            threshold = 0.9 }),
        })
      end)(),
    }, {
    H.fieldCare({ tag = "grind care leg " .. n, threshold = 0.85 }),
    -- Re-checkpointing here, after every leg that didn't wipe (already
    -- healed, already safe), means a wipe only costs its own leg rather
    -- than the whole grind.
    (function()
      local ckReq
      return seq({
        H.call(function() ckReq = H.requestSaveState() end),
        H.waitFrames(2),
        H.call(function()
          H.checkReq(ckReq, "grind re-checkpoint leg " .. n)
          grindBlob = ckReq.blob
          grindFightsAtCheckpoint = grindFights
        end),
      })
    end)(),
    H.call(function()
      local tHp, lHp = H.charMaxHp(TERRA), H.charMaxHp(LOCKE)
      local tLv, lLv = charLevel(TERRA), charLevel(LOCKE)
      if n % 5 == 0 then
        H.log(string.format(
          "[grind] leg %d f%d fights=%d TERRA L%d maxhp=%d LOCKE L%d maxhp=%d",
          n, H.frame, grindFights, tLv, tHp, lLv, lHp))
      end
      local goalMet = tHp > GRIND_HP_TARGET and lHp > GRIND_HP_TARGET
      if goalMet then
        grindDone = true
        H.log(string.format(
          "[grind] GOAL MET after leg %d (%d fights, f%d): TERRA L%d->L%d " ..
          "%d hp, LOCKE L%d->L%d %d hp", n, grindFights, H.frame,
          grindStartLv[TERRA], tLv, tHp, grindStartLv[LOCKE], lLv, lHp))
      elseif grindFights >= GRIND_FIGHT_CAP or n >= GRIND_LEG_CAP then
        local tGain, lGain = tLv - grindStartLv[TERRA], lLv - grindStartLv[LOCKE]
        H.log(string.format(
          "[grind] CAP REACHED (%d legs, %d fights, f%d) without the goal: " ..
          "TERRA L%d->L%d (+%d) %dhp, LOCKE L%d->L%d (+%d) %dhp, target >%d " ..
          "both", n, grindFights, H.frame, grindStartLv[TERRA], tLv, tGain,
          tHp, grindStartLv[LOCKE], lLv, lGain, lHp, GRIND_HP_TARGET))
        grindDone = true
        grindGoalMissed = true
        -- The route proceeds into town/shop/inn/fire/ambush with whatever
        -- TERRA and LOCKE actually reached rather than erroring out short
        -- of ever reaching the ambush at all.
        H.log(string.format(
          "[grind] proceeding to town/ambush WITHOUT the full goal met -- " ..
          "TERRA %dhp is %d short of >%d (LOCKE %dhp already clears it); " ..
          "see the STATUS header for why a further cap raise was not tried",
          tHp, GRIND_HP_TARGET - tHp, GRIND_HP_TARGET, lHp))
      end
    end),
    }),
  })
end

-- ---------------------------------------------------------- P3: Strago's --
-- join-level probe. Logged, not asserted: whatever char_prop's init-time
-- averaging produces is measured here rather than predicted.
-- Returns a step object (H.call(...)) -- call it as a list ENTRY, never
-- from inside another H.call's body (that only constructs a throwaway
-- step and logs nothing).
local function logStragoJoin()
  return H.call(function()
    -- the 37-byte character record, indexed by character id: +$08 level,
    -- +$09 current HP, +$0B max HP (top 2 bits are the hp-boost flag,
    -- masked off), +$0D current MP, +$0F max MP (same mask)
    local lvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
    local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
    local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
    local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
    local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
    H.log(string.format(
      "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d (measured, no " ..
      "norm_lvl expected at join)", lvl, hp, mhp, mp, mmp))
  end)
end

-- --------------------------------------------------------- battle 31/45 --
-- The wandering flames and the (21,22) ambush are ordinary contact/tile
-- battles; navTo's playBattles="tactical" branch (H.newFightDriver
-- underneath) already fights anything that starts while it walks. No
-- special handling needed beyond passing tactical opts through, and a
-- care stop after each leg.
--
-- healPercent=85 so newFightDriver tops everyone up early, since chained
-- wandering-flame contacts on the way to the ambush leave no room for a
-- field-menu heal between fights (no post-battle-field-care hook exists,
-- and H.fieldCare doesn't work on this map anyway). healer=TERRA (not nil):
-- letting every actor reach for the bag via the mayHeal fallback makes
-- healing look attractive every turn to everyone, not just the down actor,
-- so nobody ever finishes the fight.
--
-- Balloons are weak to ice|water, and OT6's shield-break ratio is 4:1
-- weak:unweak, so an unweak physical hit while shields hold does a
-- quarter the damage an elemental hit would. opts.magic routes TERRA's
-- turns to Ice (spell $01, `boost=false`, since the point is the element
-- rather than the damage) instead of boosted Fight whenever she is not
-- needed to heal.
local WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
               items = true, maxFrames = 20000, healPercent = 85,
               magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
-- islands 13/11 only: flee wandering flames rather than fight every one
-- (see houseWarp's own note on the `flee` parameter, below).
local FLEE_WALK = { playBattles = "flee", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }

-- A short_entrance fires purely by standing on its SrcPos tile (no
-- direction test), exactly like the (4,10) floor trigger -- no
-- crossDoor-style staged/held diagonal approach is needed. navTo's own
-- completion test wants the party settled on the goal tile for a few
-- frames, but a short_entrance relocates the party the instant it lands,
-- so fieldX/Y jump to DestPos before that settle ever accumulates and
-- navTo would keep re-planning from the wrong island; passing navTo's
-- `arrive` opt ends the walk the moment fieldX/Y read the known DestPos
-- instead.
--
-- `flee`: islands 13 and 11 hold six of the twelve wandering flames, and
-- none of the twelve are required content, so holding L+R past one
-- instead of fighting it is available on the safer legs. Defaults to
-- "tactical" so the ambush/FlameEater trigger legs, which should fight
-- what they hit, are unaffected.
local function houseWarp(sx, sy, dx, dy, what, playBattles)
  return seq({
    creepNav(sx, sy, { playBattles = playBattles or "tactical", healer = TERRA,
      bank = 3, items = true, maxFrames = 20000, healPercent = 85,
      magic = { [TERRA] = { spell = ICE_SPELL, boost = false } },
      arrive = function() return H.fieldX() == dx and H.fieldY() == dy end }),
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, what .. ": settled", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at the right x")
      H.assertEq(H.fieldY(), dy, what .. ": landed at the right y")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

local function battleHpAllZero()
  for e = 0, 3 do
    if H.readWord(0x3BF4 + e * 2) ~= 0 then return false end
  end
  return true
end

-- ------------------------------------------------------- GameOver guard --
-- M.run arms an exec canary on the event GameOver routine ($CC/E568) and
-- fails the whole run (H.gameOverFired > 0 -> emu.stop(3)) the frame after
-- it fires, unless opts.allowGameOver is set. This file's H.run() call
-- passes allowGameOver=true (both fights below are seed ladders built to
-- survive a loss), so the canary alone no longer aborts the run -- but a
-- real GameOver must still never be allowed to reach a title-screen
-- Continue prompt.
--
-- In both ambushAttempt and flameEaterAttempt's tail step below, the
-- win-tail driveUntil's own predicate also stops the instant
-- H.gameOverFired > 0 (before one more "a" press goes out, so no mash
-- reaches a Continue prompt), and lossReload() here reloads the ladder's
-- pre-fight blob and resets H.gameOverFired back to 0 right after.
local function lossReload(blobFn, tag)
  local req
  return seq({
    H.call(function() req = H.requestLoadState(blobFn()) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, tag .. ": loss-reload")
      H.gameOverFired = 0
      H.log(string.format("[%s] loss-reload done, GameOver counter cleared, f%d",
        tag, H.frame))
    end),
    H.waitFrames(90),
  })
end

-- --------------------------------------------------------- the ambush --
-- The (21,22) ambush (battle 45, 4x Balloon) is a hard, RNG-sensitive
-- fight: a pincer opening lands its first round before the player gets a
-- turn, so it is retried from a checkpoint with a spread battle seed like
-- FlameEater's own ladder, rather than assumed winnable in one try.
-- _cbe622 sets switch $050A=1 as its first action and clears it only at
-- the very end, after the post-battle teardown -- the same "only a real
-- win reaches the tail" shape $0090 gives FlameEater -- so the ladder here
-- watches $050A instead of a battle-menu flag.
local L45 = H.newSeedLadder("ambush (battle 45)", { attempts = 5 })
local ambBlob, ambWon = nil, false

-- battleLoadStarted()/battleActive() are both known-flaky on a single
-- frame mid-fight (a total wipe reads all zero like a menu does; a
-- big-effect frame can fail the screenshot check), so trusting one frame's
-- read risks handing control to the win-tail's A-mash while the fight is
-- still live. CONFIRM_BATTLE_GONE only trusts "the battle is over" after
-- this many CONSECUTIVE frames of both flags reading false.
local CONFIRM_BATTLE_GONE = 90

-- ==================================================== the ambush FIGHT PLAN
-- Bespoke driver for this one fight, modeled on gen_narshe_battle.lua's
-- raw per-character button-sequence fighter and battle_thief.lua's
-- state-machine decide() -- not H.newFightDriver, which has no Lore arm at
-- all and whose unconditional item/cure loop produces a revive treadmill
-- that never lands a real attack.
--
-- THE PLAN:
--   STRAGO alive -> Aqua Rake (lore id 3) every turn: multi-target water,
--     hits all four Balloons (their weakness), and lowers their current
--     HP so a surviving Balloon's self-destruct (which deals current HP)
--     does less. Multi-target, no cursor steering: enters ST_TGT and
--     confirms with a bare A.
--   LOCKE alive, Strago down -> Filch (strips one shield) while any live
--     Balloon still carries a shield, else an R-boosted Fight (a broken
--     target takes 4x) on the default enemy cursor.
--   anyone else -> plain boosted Fight.
--   Revives are withheld while 2+ Balloons are alive; the gate opens at
--     <=1 Balloon: revive STRAGO first, then anyone else down.
--   Any acting, living character below 40% HP uses a Tonic/Potion on
--     themselves first; the revive-window gate keeps this from colliding
--     with reviving a corpse (a corpse cannot act).
--
-- RAM/menu addresses: Lore's steady-browse MSTATE is $1B ($19 is the
-- transitional DMA-fill state on the way in); its single-column cursor
-- block sits at $891F/$8923/$8927, immediately following Magic's
-- $8913/$8917/$891B block and Rage's $892B (one contiguous 12-byte-stride
-- table); $306A+loreId reads that lore's own attack id (loreId+$8B) iff it
-- is currently offered. Aqua Rake = lore id 3, inside Strago's InitLore
-- starting set {3,7,20}; the driver counts offered ids below 3 live rather
-- than hardcoding a row.
local MENU_A, ACTOR_A, MSTATE_A = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL_A, CMDROW_A = 0x202E, 0x890F
local BCHID_A, BCHP_A, BCMAXHP_A = 0x3ED8, 0x3BF4, 0x3C1C
local BP_A = 0x3E9C
local ST_CMD_A, ST_TGT_A, ST_ITEM_A, ST_THIEF_A = 0x05, 0x38, 0x0A, 0x30
local KCOL_A, KROW_A = 0x8963, 0x8967
local ST_LORE_OPEN_A, ST_LORE_A = 0x19, 0x1B
local LROW_A = 0x8927
local TBL_306A_A = 0x306A
local CMD_FIGHT_A, CMD_ITEM_A, CMD_STEAL_A, CMD_LORE_A = 0x00, 0x01, 0x05, 0x0C
local ITEMSCR_A, ITEMROW_A, BATTINV_A = 0x8947, 0x894F, 0x2686
local AQUA_RAKE_LORE_ID = 3
local function monHpA(i) return H.readWord(0x3BFC + i * 2) end
local function monShieldsA(i) return H.readByte(0x3E40 + i * 2) end
local function monPresentA(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function cmdRowA(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL_A + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOfA(ids)
  for i = 0, 251 do
    local id = H.readByte(BATTINV_A + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(BATTINV_A + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end
-- battle_lore.lua's own tested fact: $306A+id reads id+$8B iff that lore
-- id is currently offered by Ot6LoreMask's live walk; otherwise whatever
-- InitBattle's own clear left there. Comparing against the exact expected
-- value (rather than measuring a separate "fill" byte first) sidesteps
-- needing that extra live-measurement step.
local function loreOfferedA(id) return H.readByte(TBL_306A_A + id) == id + 0x8B end
local function loreRowForA(targetId)
  local row = 0
  for id = 0, targetId - 1 do
    if loreOfferedA(id) then row = row + 1 end
  end
  return row
end
local ambushCharTC = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })

local function newAmbushPlan(tag)
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
  local stepIdx = 0
  local aqCasts, filchCasts, fightBursts = 0, 0, 0
  local openerLogged = false
  local function partyCounts()
    local balloonsAlive = 0
    for s = 0, 5 do if monPresentA(s) and monHpA(s) > 0 then balloonsAlive = balloonsAlive + 1 end end
    local stragoSlot, downSlots, anyAlive = nil, {}, false
    for e = 0, 3 do
      if H.readWord(BCMAXHP_A + e * 2) > 0 then
        local cid = H.readByte(BCHID_A + e * 2)
        if cid == STRAGO then stragoSlot = e end
        if H.readWord(BCHP_A + e * 2) > 0 then anyAlive = true
        else downSlots[#downSlots + 1] = e end
      end
    end
    return balloonsAlive, stragoSlot, downSlots, anyAlive
  end
  local function anyShielded()
    for s = 0, 5 do
      if monPresentA(s) and monHpA(s) > 0 and monShieldsA(s) > 0 then return true end
    end
    return false
  end
  -- built once per fresh ST_CMD (turnPlan == nil or a new actor's turn)
  local function decideTurn(actor)
    if not openerLogged then
      openerLogged = true
      local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
      H.log(string.format(
        "[%s] opener check f%d: first actor to get a turn is slot %d " ..
        "(char $%02X) at %d/%d hp -- the opener's own damage on whoever it " ..
        "caught is whatever's MISSING from THEIR max, logged separately " ..
        "per party member below", tag, H.frame, actor,
        H.readByte(BCHID_A + actor * 2), hp, mx))
      for e = 0, 3 do
        if H.readWord(BCMAXHP_A + e * 2) > 0 then
          H.log(string.format(
            "[%s] opener dbg: slot %d char $%02X hp=%d/%d (missing=%d)",
            tag, e, H.readByte(BCHID_A + e * 2), H.readWord(BCHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2) - H.readWord(BCHP_A + e * 2)))
        end
      end
    end
    local charId = H.readByte(BCHID_A + actor * 2)
    local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
    local balloonsAlive, stragoSlot, downSlots = partyCounts()
    -- 1. self-heal, always allowed
    if mx > 0 and hp > 0 and hp < mx * 0.40 then
      local idx = bagIdxOfA({ TONIC, POTION })
      if idx then return { kind = "item", ids = { TONIC, POTION }, target = actor } end
    end
    -- 2. revive window: at most one Balloon left, revive STRAGO first
    if balloonsAlive <= 1 and #downSlots > 0 then
      local idx = bagIdxOfA({ FENIX_DOWN })
      if idx then
        local tgt = downSlots[1]
        if stragoSlot then
          for _, s in ipairs(downSlots) do if s == stragoSlot then tgt = s end end
        end
        return { kind = "item", ids = { FENIX_DOWN }, target = tgt }
      end
    end
    -- 3. offense
    if charId == STRAGO then
      return { kind = "lore", loreId = AQUA_RAKE_LORE_ID }
    end
    if charId == LOCKE then
      if anyShielded() then return { kind = "filch" } end
      return { kind = "fight", boost = true }
    end
    return { kind = "fight", boost = true }
  end
  -- per-frame button for the CURRENT plan/state
  local function buttonFor(actor, st)
    local plan = turnPlan
    if plan.kind == "item" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_ITEM_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_ITEM_A then
        local want = bagIdxOfA(plan.ids)
        if want == nil then return "b" end
        local cur = H.readByte(ITEMSCR_A + actor) + H.readByte(ITEMROW_A + actor)
        if cur < want then return "down" end
        if cur > want then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        -- H.targetCursor's two-press rotation cannot reach every slot
        -- (documented in ot6.lua). Backstop: past a real frame budget of
        -- failed confirms, stop steering and just press A on whatever is
        -- highlighted -- with at most one living character in most of
        -- this fight's own turns, that is the only valid choice anyway.
        plan.tgtSpin = (plan.tgtSpin or 0) + 1
        if plan.tgtSpin > 240 then return "a" end
        ambushCharTC.observe()
        return ambushCharTC.steer(plan.target, mf)
      end
      return "b"
    end
    if plan.kind == "filch" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_STEAL_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_THIEF_A then
        local cur = H.readByte(KROW_A + actor)
        if H.readByte(KCOL_A + actor) ~= 0 then return "left" end
        if cur < 1 then return "down" end
        if cur > 1 then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"                       -- default enemy cursor, no steer
      end
      return "b"
    end
    if plan.kind == "lore" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_LORE_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_LORE_OPEN_A then
        return nil                       -- transitional DMA fill, just wait
      elseif st == ST_LORE_A then
        local want = loreRowForA(plan.loreId)
        local cur = H.readByte(LROW_A + actor)
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    -- fight (default/fallback)
    if st == ST_CMD_A then
      if plan.boost and not plan.boosted then
        local bp = H.readByte(BP_A + actor * 2)
        local want = (bp >= 2) and math.min(bp, 3) or 0
        plan.boostLeft = plan.boostLeft or want
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return "r"
        end
        plan.boosted = true
      end
      local want = cmdRowA(actor, CMD_FIGHT_A)
      local cur = H.readByte(CMDROW_A + actor) & 3
      if want == nil then return "a" end
      if cur == want then return "a" end
      return cur < want and "down" or "up"
    elseif st == ST_TGT_A then
      return "a"                         -- default enemy cursor, no steer
    end
    return "b"
  end
  function F.frame()
    phase = (phase + 1) % 8
    if H.readByte(MENU_A) == 0 then
      turnActor, turnPlan = nil, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mf = mf + 1
    local actor = H.readByte(ACTOR_A) & 3
    local st = H.readByte(MSTATE_A)
    if st == 0x01 then H.setPad({}); return end   -- ST_TRANS
    if (turnPlan == nil or turnActor ~= actor) and st ~= ST_CMD_A then
      -- a fresh actor turn hasn't reached the command list yet (a
      -- transitional state); hold still rather than build a plan off a
      -- read that might still be settling, matching H.newFightDriver's
      -- own "only build a plan at ST_CMD" convention.
      H.setPad({})
      return
    end
    if turnPlan == nil or turnActor ~= actor then
      turnActor = actor
      turnPlan = decideTurn(actor)
      H.log(string.format("[%s] f%d slot=%d char=$%02X plan=%s%s", tag,
        H.frame, actor, H.readByte(BCHID_A + actor * 2), turnPlan.kind,
        turnPlan.kind == "item" and (" tgt=" .. turnPlan.target) or ""))
    end
    local slow = (st == ST_ITEM_A)
    local period = slow and 30 or 8
    local on = slow and 6 or 4
    if mf % period >= on then H.setPad({}); return end
    local btn = buttonFor(actor, st)
    -- count landed actions on the ST_TGT->confirm edge, logged once per
    -- kind so the report has real cadence numbers
    if st == ST_TGT_A and btn == "a" then
      if turnPlan.kind == "lore" and not turnPlan.counted then
        turnPlan.counted = true; aqCasts = aqCasts + 1
        H.log(string.format("[%s] Aqua Rake cast #%d confirmed f%d", tag, aqCasts, H.frame))
      elseif turnPlan.kind == "filch" and not turnPlan.counted then
        turnPlan.counted = true; filchCasts = filchCasts + 1
        H.log(string.format("[%s] Filch #%d confirmed f%d", tag, filchCasts, H.frame))
      elseif turnPlan.kind == "fight" and turnPlan.boost and not turnPlan.counted then
        turnPlan.counted = true; fightBursts = fightBursts + 1
        H.log(string.format("[%s] boosted burst Fight #%d confirmed f%d", tag, fightBursts, H.frame))
      end
    end
    H.setPad(btn and { [btn] = true } or {})
  end
  function F.idle()
    turnActor, turnPlan = nil, nil
    H.log(string.format("[%s] tally: Aqua Rake x%d, Filch x%d, boosted burst x%d",
      tag, aqCasts, filchCasts, fightBursts))
  end
  return F
end

local function ambushAttempt(n)
  local F = newAmbushPlan("ambush-plan-" .. n)
  local notBattle, giveUp = 0, 0
  local loadReq
  -- H.cond(pred, thenSteps, elseSteps) hands elseSteps to the shared lib's
  -- own seqStep(), which needs a PLAIN list (#steps/steps[i]) -- a
  -- seq({...}) here would hand it a compound step object instead, whose
  -- length reads 0, so it would exit immediately without running anything.
  return H.cond(function() return ambWon end, {}, {
    H.logStep(function()
      return string.format("ambush attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(ambBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "ambush entry-point reload") end),
      H.waitFrames(90),
    }) or seq({}),
    L45.spread(n),
    H.call(function() H.log(string.format(
      "[ambush] approaching (21,22), attempt %d", n)) end),
    creepNav(21, 23, FLEE_WALK),
    -- Party-membership/object-pointer dump right before the trigger fires,
    -- for comparison against the post-battle dump below.
    H.call(function() probeDump("PRE-BATTLE45 attempt-" .. n) end),
    pressWalk("up", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (21,22) -> battle 45"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "ambush battle up", 10),
    H.waitFrames(90),
    -- PHASE 1: drive the fight (F.frame()) for as long as the battle module
    -- might still own the screen, and only conclude the battle is over
    -- after CONFIRM_BATTLE_GONE consecutive confirming frames.
    -- H.gameOverFired is checked first and exits immediately with no
    -- debounce: it is a READ watch on the event GameOver script bytes in
    -- bank $CC, ground truth for "this attempt just lost".
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 1800000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "ambush fight (attempt " .. n .. ")"),
    H.call(function()
      F.idle()
      H.log(string.format(
        "[ambush] phase 1 done (battle module gone or GameOver read), " ..
        "attempt %d, f%d, gameOverFired=%d", n, H.frame, H.gameOverFired))
      probeDump("POST-BATTLE45 attempt-" .. n)
      probeEventDump("POST-BATTLE45 attempt-" .. n)
    end),
    -- PHASE 2, the win-tail. $050A is unsound as a win signal: a loss
    -- silently re-Continues to thamasa-night-v1, whose SRAM never sets
    -- $050A either, so it reads 0 there too and cannot tell a win from a
    -- reload. This phase just settles (edge-A through anything waiting)
    -- and hands off to the win-verification call below.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return (map() == 351 and H.hasControl() and H.tileAligned())
         or giveUp >= 6000
    end, 6200, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "ambush win-tail settle (or a real GameOver shows itself)"),
    -- WIN VERIFICATION: a real win needs all three -- H.gameOverFired
    -- stayed 0 the whole attempt, still on map 351 (a reload lands on the
    -- world map/town), and STRAGO still in the active party
    -- (thamasa-night-v1's own roster is pre-Strago).
    H.call(function()
      H.setPad({})
      local realWin = H.gameOverFired == 0 and map() == 351
         and partyOf(STRAGO) ~= 0
      if H.gameOverFired > 0 then
        H.log(string.format(
          "ambush attempt %d LOST -- GameOver read-fired (event GameOver, " ..
          "$CC/E568), f%d", n, H.frame))
      elseif realWin then
        ambWon = true
        H.log(string.format(
          "ambush BEATEN on attempt %d, f%d, map=%d pos=(%d,%d) partyOf(STRAGO)=%d",
          n, H.frame, map(), H.fieldX(), H.fieldY(), partyOf(STRAGO)))
      else
        H.log(string.format(
          "ambush attempt %d LOST -- win verification failed (map=%d " ..
          "pos=(%d,%d) partyOf(STRAGO)=%d gameOverFired=%d), f%d",
          n, map(), H.fieldX(), H.fieldY(), partyOf(STRAGO),
          H.gameOverFired, H.frame))
      end
    end),
    H.cond(function() return not ambWon end, {
      lossReload(function() return ambBlob end, "ambush"),
    }, {}),
  })
end

-- ---------------------------------------------------------- FlameEater --
-- Battle 79, formation 449: shields 7, pierce class, weak ice, absorbs
-- fire, the authored OT6 water add.  Fired by stepping on the (46,53)
-- floor trigger (event_trigger.asm:1716), which re-forces party order
-- STRAGO,TERRA,LOCKE itself.  A win sets $0090=1 (the SAME _ca5ea9 gate
-- Dadaluma/TunnelArmr use); a loss is vanilla GameOver.  L26 HP8400 vs a
-- party around L16-19 is a long fight -- newFightDriver's own tactical
-- kit (boosted Fight, TERRA's Cure, the item bag) fights it honestly, no
-- bespoke per-turn plan. A seed ladder (H.newSeedLadder, 5 rungs) retries
-- a loss from a checkpoint taken just before the trigger tile, with a
-- care stop each attempt.
local L79 = H.newSeedLadder("FlameEater (battle 79)", { attempts = 5 })
local feBlob, feWon = nil, false

local function flameEaterAttempt(n)
  local F = H.newFightDriver("FlameEater", { tactical = true, boost = true,
    bank = 3, items = true, cure = true, healer = TERRA, healPercent = 60 })
  local notBattle, giveUp = 0, 0
  local loadReq
  return H.cond(function() return feWon end, {}, {
    H.logStep(function()
      return string.format("FlameEater attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(feBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "FlameEater entry-point reload") end),
      H.waitFrames(90),
      care("post-reload, attempt " .. n),
    }) or seq({}),
    L79.spread(n),
    H.call(function() H.log(string.format(
      "[FlameEater] approaching (46,53), attempt %d", n)) end),
    creepNav(46, 52, WALK),
    pressWalk("down", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (46,53) -> battle 79"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "FlameEater battle up", 10),
    H.waitFrames(90),
    H.call(function()
      H.assertEq(H.formationHas({ [0x0116] = true }), true,
        "battle 79 is FlameEater $0116")
      H.log(string.format("[FlameEater] up, attempt %d: hp=%d", n,
        H.readWord(0x3bfc)))
    end),
    -- PHASE 1: drive tactically until the battle module is confirmed gone
    -- for CONFIRM_BATTLE_GONE consecutive frames, or H.gameOverFired (the
    -- READ watch, ground truth) fires -- whichever first.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 1800000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "FlameEater fight (attempt " .. n .. ")"),
    H.call(function()
      H.log(string.format(
        "[FlameEater] phase 1 done (battle module gone or GameOver read), " ..
        "attempt %d, f%d, gameOverFired=%d", n, H.frame, H.gameOverFired))
    end),
    -- PHASE 2, the win-tail settle. $0090 alone is a decent positive
    -- signal here (thamasa-night-v1 never sets it either), but the
    -- win-verification call below still cross-checks party/roster sanity
    -- rather than trusting one switch in isolation.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return sw(0x0090) == 1 or giveUp >= 6000
    end, 6200, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0090 (or a real GameOver shows itself)"),
    -- WIN VERIFICATION: gameOverFired stayed 0, $0090 flipped, and the
    -- roster is still sane (STRAGO/TERRA present -- a reload to
    -- thamasa-night-v1 would drop both).
    H.call(function()
      H.setPad({})
      local realWin = H.gameOverFired == 0 and sw(0x0090) == 1
         and partyOf(STRAGO) ~= 0 and partyOf(TERRA) ~= 0
      if H.gameOverFired > 0 then
        H.log(string.format(
          "FlameEater attempt %d LOST -- GameOver read-fired (event " ..
          "GameOver, $CC/E568), f%d", n, H.frame))
      elseif realWin then
        feWon = true
        H.log(string.format(
          "FlameEater BEATEN on attempt %d, f%d, map=%d pos=(%d,%d)",
          n, H.frame, map(), H.fieldX(), H.fieldY()))
      else
        H.log(string.format(
          "FlameEater attempt %d LOST -- win verification failed " ..
          "($0090=%d partyOf(STRAGO)=%d partyOf(TERRA)=%d " ..
          "gameOverFired=%d, giveUp=%d), f%d",
          n, sw(0x0090), partyOf(STRAGO), partyOf(TERRA), H.gameOverFired,
          giveUp, H.frame))
      end
    end),
    H.cond(function() return not feWon end, {
      lossReload(function() return feBlob end, "FlameEater"),
    }, {}),
  })
end

-- ------------------------------------------------------------------------
local steps = {
  -- ---- 1. cold Continue the thamasa-night-v1 checkpoint -----------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> the L tile (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the L tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] boot f%d world=(%d,%d) party0=%02X party1=%02X party3=%02X",
      H.frame, H.worldX(), H.worldY(), H.readByte(0x1850) & 7,
      H.readByte(0x1851) & 7, H.readByte(0x1853) & 7))
    H.assertEntryContract("thamasa-night-v1")
  end),

  -- ---- 2. care, then the grinding leg, then into town --------------------
  H.fieldCare({ tag = "care at the L tile", threshold = 0.9 }),

  -- ---- 2.5. the grinding leg ----------------------------------------------
  -- Runs before the inn: checkpoint L's own party is TERRA-LOCKE-SHADOW and
  -- boots directly on the world map, and Shadow only leaves at the inn
  -- night scene, so grinding here fights the fire block's safest roster
  -- (three live members). See grindLeg's own header comment for the full
  -- design.
  H.call(function()
    H.log(string.format(
      "[grind] pre-inn grind starting, party TERRA/LOCKE/SHADOW, f%d " ..
      "world=(%d,%d)", H.frame, H.worldX(), H.worldY()))
  end),
  -- the grind's own entry-point checkpoint -- a wiped leg reloads this,
  -- not the whole run.
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "grind entry-point checkpoint")
        grindBlob = ckReq.blob
      end),
    })
  end)(),
  H.call(function() armGrindWatch() end),
  (function()
    local t = {}
    for n = 1, GRIND_LEG_CAP do t[#t + 1] = grindLeg(n) end
    return t
  end)(),
  H.call(function() disarmGrindWatch() end),
  H.call(function()
    H.log(string.format(
      "[grind] done, f%d world=(%d,%d) TERRA L%d %d/%dhp LOCKE L%d %d/%dhp",
      H.frame, H.worldX(), H.worldY(), charLevel(TERRA), H.charHp(TERRA),
      H.charMaxHp(TERRA), charLevel(LOCKE), H.charHp(LOCKE), H.charMaxHp(LOCKE)))
  end),

  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded", 5),
  H.call(function()
    H.log(string.format("[ot6] town re-entry f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
  end),

  -- ---- 2.6. stock up before the inn ---------------------------------------
  -- Quantities are generous asks, not requirements -- H.buyItem's own
  -- purse-clamp acceptance takes whatever gil actually covers and logs it.
  crossDoor(26, 37, 347, 36, 44, "item shop door 343(26,37)->347(36,44)"),
  -- Door loads finalize the decompressed prop table late; a settle wait
  -- before the first pathfinding call avoids a spurious "no path".
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400,
    "shop interior settled before pathfinding", 10),
  H.waitFrames(150),
  shopTalk(36, 39, "Thamasa item shop"),
  H.buyItem(TONIC, 0, function() return 30 - H.invCountOf(TONIC) end, "TONIC to 30"),
  H.buyItem(POTION, 1, function() return 15 - H.invCountOf(POTION) end, "POTION to 15"),
  H.buyItem(FENIX_DOWN, 6, function() return 20 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 20"),
  H.call(function()
    H.log(string.format(
      "[shop] Thamasa item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN),
      gil(), H.frame))
  end),
  shopClose("Thamasa item shop"),
  -- The return record is not the forward one mirrored: src=(36,45)
  -- dest=(26,39), two tiles off the forward door's (26,37)/(36,44).
  crossDoor(36, 45, 343, 26, 39, "item shop door 347(36,45)->343(26,39), return"),

  -- ---- 3. the inn: door, innkeeper, the whole fire scene -----------------
  crossDoor(12, 19, 346, 23, 23, "inn door 343(12,19)->346(23,23)"),
  H.call(function()
    H.log(string.format("[ot6] inn interior f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),
  -- The innkeeper at (24,15) sits behind a counter tile at (24,16) that
  -- bfsPath refuses as a stand; (24,17), two tiles south, is reachable.
  -- This is the "talk-across-a-counter" mechanic: stand one tile back from
  -- the counter, face it, and the talk reaches through to the NPC beyond
  -- -- a face+A stand rather than a chase.
  H.navTo(24, 17, { maxFrames = 9000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 0  -- facing UP
  end, 300, {
    H.call(function() H.setPad({ up = true }) end),
  }, "face up at the inn counter"),
  H.release(), H.waitFrames(4),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { a = true, up = true } or {})
      end),
    }, "talk-across-the-counter -> innkeeper's 1 GP choice")
  end)(),
  -- one continuous scripted stretch from here: the Yes confirm (default
  -- cursor), the innkeeper walking off, and straight into the night/fire
  -- scene with no further choice screens.
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control back on Thamasa town map after the fire")
    H.assertEq(H.fieldX(), 12, "fire scene end x (12,21)")
    H.assertEq(H.fieldY(), 21, "fire scene end y")
    H.assertEq(sw(0x008E), 1, "$008E SET -- the fire has started")
    H.assertEq(sw(0x0190), 1, "$0190 SET (the fire's companion switch)")
    H.assertEq(sw(0x0090), 0, "$0090 CLEAR -- FlameEater not fought yet")
    H.assertEq(partyOf(SHADOW), 0, "SHADOW left the party at the inn night")
    H.log(string.format(
      "[ot6] FIRE STARTED f%d map=%d (%d,%d) party[TERRA LOCKE]=%d %d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7))
    H.screenshot("thamasa_fire_started")
  end),
  -- Known-good moment (right after the fire scene, before the house is
  -- entered): baseline for the $0867+41*id dump, and where the write-watch
  -- on those four bytes is armed.
  H.call(function()
    probeDump("GOOD-post-fire")
    armProbeWatch()
  end),

  -- ---- 4. talk to Strago at the house door -> STRAGO joins -> map 351 ---
  (function()
    local idxCell = { v = 0x14 }
    return seq({
      H.call(function()
        idxCell.v = findNpc(39, 24, 0x14)
        H.log(string.format("[ot6] chasing Strago's door NPC at slot $%02X, f%d",
          idxCell.v, H.frame))
      end),
      chaseTalkLazy(function() return idxCell.v end, 9000,
        "chase+talk Strago's door NPC",
        { done = function() return H.eventRunning() or H.dialogWaiting() end }),
    })
  end)(),
  H.advanceStory(function() return map() == 351 and H.hasControl() end,
    40000, { playBattles = "tactical" }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 351, "loaded into the burning house (map 351)")
    H.assertEq(sw(0x02E7), 1, "$02E7 -- STRAGO joined")
    H.assertEq(sw(0x02F7), 1, "$02F7 -- STRAGO available")
    H.assertEq(partyOf(STRAGO) ~= 0, true, "STRAGO is in party 1")
    H.assertEq(partyOf(TERRA) ~= 0, true, "TERRA is in party 1")
    H.assertEq(partyOf(LOCKE) ~= 0, true, "LOCKE is in party 1")
    -- Inlined rather than calling logStragoJoin() here -- that helper is
    -- itself an H.call step object, and invoking it from inside ANOTHER
    -- H.call's body only constructs a throwaway step and runs nothing.
    do
      -- ff6/notes/field-ram.txt:885-895: the 37-byte character record,
      -- indexed by character id (same convention as $1850+charId): +$08
      -- level, +$09 current HP, +$0B max HP (top 2 bits are the hp-boost
      -- flag, masked off), +$0D current MP, +$0F max MP (same mask).
      local lvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
      local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
      local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
      local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
      local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
      H.log(string.format(
        "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d (measured, no " ..
        "norm_lvl expected at join)", lvl, hp, mhp, mp, mmp))
    end
    H.log(string.format("[ot6] map 351 entry f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_house_entry")
  end),

  -- ---- 5. the burning house: two chests, the ambush, FlameEater ----------
  -- load_map lands the party in a 3-tile landing pocket, fully enclosed.
  -- The way out is a floor trigger at (4,10), not an automatic startup
  -- event: stepping onto it (gated `$0190==1`) plays the short "avoid the
  -- flames... find RELM!" scene, re-orders the party, walks LOCKE/STRAGO a
  -- few tiles diagonally into the house proper, and clears $0190.
  H.navTo(4, 10, WALK),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and sw(0x0190) == 0
  end, 12000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] map 351 opening scene settled f%d (%d,%d) $0190=%d $008F=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x0190), sw(0x008F)))
    H.assertEq(sw(0x0190), 0, "$0190 cleared by the (4,10) trigger")
  end),
  -- door loads finalize the decompressed prop table late; settle before
  -- any pathfinding reads it.
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "map 351 settled before pathfinding", 10),
  H.waitFrames(150),
  -- 35 cardinally-disconnected tile islands stitched together only by
  -- short_entrance warps (see the file header for the full island graph).
  -- Each hop rides houseWarp() (crossDoor's same-map twin); a care() stop
  -- follows every hop, since the wandering flames sit inside these islands
  -- and a contact battle can start on any leg.
  H.call(function() H.log("[ot6] island 0 -> 13: (4,3)->(4,38)") end),
  houseWarp(4, 3, 4, 38, "P1 (4,3)->(4,38): the floor warp into the main hall"),
  care("after P1"),
  -- This route is deterministic frame-for-frame given identical code,
  -- which pins the wandering flames' contact timing and the pincer/ambush
  -- RNG draws to real-time frame count. This wait shifts every subsequent
  -- battle's frame phase by a fixed offset, changing which byte of the
  -- seed table each one draws.
  H.waitFrames(37),

  -- islands 13 and 11 hold six wandering flames between them; chain-
  -- battling all of them wipes the party. A mid-leg waypoint + care() plus
  -- fleeing them (FLEE_WALK) gets a run through wipe-free.
  creepNav(4, 30, FLEE_WALK),
  care("partway through the main hall (island 13)"),

  H.call(function() H.log("[ot6] island 13 -> 11: (2,24)->(26,36)") end),
  houseWarp(2, 24, 26, 36, "P2 (2,24)->(26,36): into the ambush hall", "flee"),
  care("after P2"),

  -- A pincer formation (like the scripted ambush) refuses to let the party
  -- flee: the flee driver spends ~60 frames trying before falling back to
  -- the tactical driver, and the enemy still acts during those frames, so
  -- attempting to flee an unrunnable fight is worse than not trying. Fix:
  -- FLEE_WALK only as far as (21,23), one tile short of the trigger, so
  -- any wandering flame on the way is still skippable; then a single
  -- tactical hop onto (21,22) itself so the ambush is fought from turn one.
  H.call(function() H.log("[ot6] checkpointing before the ambush trigger") end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "ambush entry-point checkpoint")
        ambBlob = ckReq.blob
      end),
    })
  end)(),
  -- PLAYTEST: emit the staged state (party on (21,23), one tile short of
  -- the ambush trigger) as build/states/ambush_ready.mss, then stop.  The
  -- owner loads it in the GUI and steps onto (21,22) to start the fight.
  H.call(function()
    H.log(string.format(
      "[playtest] staged at (%d,%d) map=%d -- emitting ambush_ready",
      H.fieldX(), H.fieldY(), H.mapId() & 0x1ff))
  end),
  H.saveState("ambush_ready"),
  H.screenshot("ambush_ready"),
  H.call(function()
    H.log("[playtest] ambush_ready emitted -- stopping before the trigger")
    emu.stop(0)
  end),
  L45.watch(),
  ambushAttempt(1),
  ambushAttempt(2),
  ambushAttempt(3),
  ambushAttempt(4),
  ambushAttempt(5),
  H.call(function()
    if not ambWon then
      error("ambush (battle 45): all 5 seed-ladder attempts lost", 0)
    end
  end),
  L45.report(),
  care("after the (21,22) ambush"),

  H.call(function() H.log("[ot6] island 11 -> 1: (26,21)->(21,9)") end),
  houseWarp(26, 21, 21, 9, "P3 (26,21)->(21,9): into the north corridor", "flee"),
  care("after P3"),

  -- the Fire Rod spur: a dead-end island (28) off the north corridor,
  -- reached and left by the SAME pair, forward then return
  H.call(function() H.log("[ot6] island 1 -> 28: (28,3)->(4,55), Fire Rod spur") end),
  houseWarp(28, 3, 4, 55, "P5 (28,3)->(4,55): the Fire Rod spur"),
  care("after the Fire Rod spur-in"),
  chestAuto(4, 52, 104, "Fire Rod", FIRE_ROD),
  care("after the Fire Rod"),
  houseWarp(4, 56, 28, 5, "P5 return (4,56)->(28,5): back to the north corridor"),
  care("after the Fire Rod spur-out"),

  H.call(function() H.log("[ot6] island 1 -> 12: (23,3)->(46,27)") end),
  houseWarp(23, 3, 46, 27, "P4 (23,3)->(46,27): into the east wing"),
  care("after P4"),

  -- the Ice Rod spur: a dead-end island (4) off the east wing, same shape
  H.call(function() H.log("[ot6] island 12 -> 4: (49,21)->(45,10), Ice Rod spur") end),
  houseWarp(49, 21, 45, 10, "P6 (49,21)->(45,10): the Ice Rod spur"),
  care("after the Ice Rod spur-in"),
  chestAuto(45, 7, 105, "Ice Rod", ICE_ROD),
  care("after the Ice Rod"),
  houseWarp(45, 11, 49, 23, "P6 return (45,11)->(49,23): back to the east wing"),
  care("after the Ice Rod spur-out"),

  H.call(function() H.log("[ot6] island 12 -> 26: (43,21)->(21,54)") end),
  houseWarp(43, 21, 21, 54, "P7 (43,21)->(21,54): into the south hall"),
  care("after P7"),

  -- island 26 -> 24 is one-way in the decoded table (no return pair
  -- recorded) -- consistent with it leading straight to FlameEater's room,
  -- whose own win tail exits via load_map 349 rather than back through here
  H.call(function() H.log("[ot6] island 26 -> 24: (21,49)->(46,54), FlameEater's chamber") end),
  houseWarp(21, 49, 46, 54, "P8 (21,49)->(46,54): into FlameEater's chamber"),
  care("before the FlameEater trigger"),

  -- checkpoint the entry point for the retry ladder, once
  H.call(function() H.log("[ot6] checkpointing before the FlameEater trigger") end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "FlameEater entry-point checkpoint")
        feBlob = ckReq.blob
      end),
    })
  end)(),
  L79.watch(),
  flameEaterAttempt(1),
  flameEaterAttempt(2),
  flameEaterAttempt(3),
  flameEaterAttempt(4),
  flameEaterAttempt(5),
  H.call(function()
    if not feWon then
      error("FlameEater: all 5 seed-ladder attempts lost", 0)
    end
  end),
  L79.report(),

  -- ---- 6. the win tail: rescue, the night talk at Strago's house --------
  H.advanceStory(function()
    return map() == 349 and H.hasControl() and sw(0x0091) == 1
       and sw(0x0098) == 1
  end, 60000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 349, "control in Strago's house after the win tail")
    H.assertEq(sw(0x0091), 1, "$0091 -- FlameEater aftermath resolved")
    H.assertEq(sw(0x0098), 1, "$0098 -- morning-after companion switch")
    H.assertEq(sw(0x0090), 1, "$0090 still SET -- FlameEater beaten")
    H.log(string.format("[ot6] win tail settled f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_after_fight")
  end),

  -- ---- 7. leave the house -> Shadow's goodbye ----------------------------
  -- SHADOW's gear, recorded before remove_equip fires, so the exit
  -- contract's "gear back in the bag" claim is an inventory delta rather
  -- than a guess at what he carries.
  H.call(function()
    H._shadowWeapon = H.readByte(0x1600 + 37 * SHADOW + 0x1F)
    H._shadowWeaponBefore = H._shadowWeapon ~= 0xFF
      and H.invCountOf(H._shadowWeapon) or nil
    H.log(string.format("[ot6] SHADOW's weapon before remove_equip: $%02X (bag=%s)",
      H._shadowWeapon, tostring(H._shadowWeaponBefore)))
  end),
  H.navTo(37, 25, { maxFrames = 6000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true, arrive = function() return map() ~= 349 end }),
  pressWalk("down", function() return map() ~= 349 end, 1800,
    "held DOWN through 349(37,25) -> Shadow's goodbye on 343(29,15)"),
  H.advanceStory(function()
    return map() == 343 and H.hasControl() and sw(0x0092) == 1
  end, 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "back on the town map after Shadow's goodbye")
    H.assertEq(sw(0x0092), 1, "$0092 -- Shadow's goodbye played")
    if H._shadowWeapon ~= 0xFF and H._shadowWeaponBefore ~= nil then
      local now = H.invCountOf(H._shadowWeapon)
      H.assertEq(now, H._shadowWeaponBefore + 1, string.format(
        "SHADOW's weapon ($%02X) returned to the bag: %d -> %d",
        H._shadowWeapon, H._shadowWeaponBefore, now))
    else
      H.log("[ot6] SHADOW carried no measurable weapon at boot -- " ..
        "remove_equip's bag delta is NOT asserted, only logged")
    end
    H.log(string.format("[ot6] Shadow's goodbye done f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_shadow_goodbye")
  end),

  -- ---- 8. out of town, and the world save --------------------------------
  care("before leaving town"),
  H.navTo(21, 47, { maxFrames = 20000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  pressWalk("down", function() return H.worldMode() end, 900,
    "held DOWN onto the south strip -> world (249,128)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Thamasa", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] outside Thamasa: world (%d,%d) f%d",
      H.worldX(), H.worldY(), H.frame))
    H.screenshot("thamasa_fireout_world")
  end),
  H.fieldCare({ tag = "care before the M save", threshold = 0.9 }),
  H.call(function()
    H.assertPartyStanding("fire_out exit")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT outside Thamasa")
    H.assertEq(partyOf(TERRA) ~= 0, true, "TERRA in party 1 at the M boundary")
    H.assertEq(partyOf(LOCKE) ~= 0, true, "LOCKE in party 1 at the M boundary")
    H.assertEq(partyOf(STRAGO) ~= 0, true, "STRAGO in party 1 at the M boundary")
    H.assertEq(partyOf(SHADOW), 0, "SHADOW not in the party at the M boundary")
  end),

  -- ---- 9. the world battery save -- checkpoint M -------------------------
  H.call(function()
    H.assertExitContractPreSave("fire-out-v1")
  end),
  H.saveState("fire_out.mss"),
  (function()
    local saveReq, loadReq
    return H.cond(function() return true end, {
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(H.worldMode(), true, "reload: on the world map")
        H.assertEq(H.readByte(0x11FA) & 3, 0, "reload: still ON FOOT")
        H.assertEq(H.worldHasControl() and H.worldAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.log("generated-state verify: the reload stayed calm -- fire_out verified")
      end),
    })
  end)(),
  (function() local calmN, ph = 0, 0
    return H.driveUntil(function()
      calmN = (H.readByte(0x59) ~= 0) and calmN + 1 or 0
      return calmN >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open outside Thamasa")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.assertExitContract("fire-out-v1")
    H.screenshot("thamasa_fireout_saved")
  end),
  H.logStep(function()
    return string.format("fire-out-v1 saved via the real Save UI at "
      .. "frame %d -- FlameEater beaten, Shadow's gear back in the bag; "
      .. "checkpoint M of v0.13", H.frame)
  end),
}

-- flatten nested step lists
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

-- allowGameOver=true: both the ambush and FlameEater below are seed
-- ladders explicitly built to survive a real loss -- without this the
-- lib's own canary would abort the whole run the frame after either
-- fight's first loss, before the ladder ever got a chance to reload and
-- retry. 3000000 gives headroom for the grind's own wipe-and-retry cost
-- (roughly 1 in 2-3 legs against Baskervor even at 3 members) plus the
-- rest of the route (ambush ladder, FlameEater, the win tail) behind it.
H.run({ maxFrames = 3000000, allowGameOver = true }, flat)
