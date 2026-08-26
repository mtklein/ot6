-- probe_ambush_stall.lua -- one-shot live probe of the post-ambush field-
-- control stall in gen_thamasa_fire.lua (map 351, the (21,22) scripted
-- ambush, battle 45).  Boot/inn/fire/join/warp/ambush steps are copied
-- from gen_thamasa_fire.lua's own route, then instrumented with
-- high-resolution register logging, directional-hold movement tests using
-- H.hold()+H.waitFrames() (H.repeatN(n,{H.call(...)}) never consumes a
-- real frame and cannot be used for this), and a capped field-menu-open
-- attempt, in place of the generator's plain `H.waitUntil(hasControl...)`.
--
-- No @suite marker: one-shot measurement, not a suite test.
--
-- Map 351 (the burning house; every exit is scripted) is 35 cardinally-
-- disconnected tile islands, stitched together only by short_entrance
-- warps that fire on tile entry with no direction test.  The full island
-- graph, landing to every objective:
--   island 0  (landing pocket + "north room") --(4,3)->(4,38)--> island 13
--   island 13 --(2,24)->(26,36)--> island 11 (the (21,22) ambush trigger)
--   island 11 --(26,21)->(21,9)--> island 1 (the north corridor)
--   island 1  --(28,3)->(4,55)--> island 28 (Fire Rod chest (4,52))
--   island 1  --(23,3)->(46,27)--> island 12 (the east wing)
--   island 12 --(49,21)->(45,10)--> island 4 (Ice Rod chest (45,7))
--   island 12 --(43,21)->(21,54)--> island 26 (the south hall)
--   island 26 --(21,49)->(46,54)--> island 24 (FlameEater trigger (46,53))
-- houseWarp() below rides each of these like crossDoor() rides a town
-- door, except the arrival test is a coordinate match rather than a
-- map-ID change.
--
-- gen_thamasa_fire.lua -- v0.13 step L->M: cold-boots the tracked
-- `thamasa-night-v1` SRAM checkpoint (world outside Thamasa, $008D=1,
-- party TERRA-LOCKE-SHADOW, pre-inn) and generates checkpoint M
-- `fire-out`: world outside Thamasa, $0090=$0091=$0092=1, party
-- TERRA-LOCKE-STRAGO, $02F3=0 (SHADOW gone).
--
-- The route:
--  1. Re-enter town: held RIGHT onto the (250,128) world trigger -> map
--     343 (23,46).
--  2. The inn: exterior door 343 (12,19) -> interior map 346 (23,23);
--     the innkeeper at (24,15) offers a night's stay.  Choosing Yes falls
--     straight into the night/fire scene with no further choice screens.
--  3. The night scene: SHADOW leaves the party, the fire starts, Shadow
--     runs off after Interceptor and goes unavailable.  Control returns
--     on map 343 at (12,21), retiled burning.
--  4. Talk to Strago at the house door (an NPC event, NPCProp::_343
--     record 5, make_npc {39,24}).  The scene ends with Strago joining
--     and load_map 351 {4,11}, forced entry party TERRA-LOCKE-STRAGO.
--  5. Map 351: two chests (Fire Rod bit 104 (4,52), Ice Rod bit 105
--     (45,7)); twelve wandering flame NPCs fire battle 31 on contact; a
--     scripted four-Balloon ambush sits on the (21,22) floor trigger;
--     FlameEater's fight is also a floor trigger, (46,53), which
--     re-forces party order STRAGO,TERRA,LOCKE before `battle 79`.  The
--     post-battle gate for both is the same win/lose gate Dadaluma and
--     TunnelArmr use: a win sets $0090=1 (ambush: $050A) and a loss falls
--     into vanilla GameOver.
--  6. Win tail: the Relm/Interceptor rescue, Shadow's smoke-bomb exit,
--     the night talk at Strago's house (load_map 349 {64,16}), ending
--     $0091=1 $0098=1, control in the house, party TERRA-LOCKE-STRAGO.
--  7. Leaving the house plays Shadow's goodbye on town 343 (29,15):
--     his gear returns to inventory, $0092=1.
--  8. Out of town (long_entrance.dat map-343 south strip) and the real
--     Save UI at slot 3 -- checkpoint M, `fire-out-v1`.
--
-- Ice Rod is not driven as an in-battle item cast: FlameEater is fought
-- with the lib driver's plain kit (boosted Fight from whoever holds it,
-- TERRA's Cure).
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local TERRA, LOCKE, STRAGO, SHADOW = 0, 1, 7, 3
local FIRE_ROD, ICE_ROD = 0x35, 0x36
local ICE_SPELL = 0x01
local saveArg = nil

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

-- edge-A through dialogs/scenes until settled
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
-- (x,y).
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

-- chaseTalk needs a concrete object index at construction time, but the
-- door NPC's slot is only knowable live.  This is M.chaseTalk's body with
-- the one line that reads objIdx replaced by a call to idxFn() every
-- frame instead.
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

-- H.bfsPath's node cap can go dry on a single long query, so creepXY
-- hands navTo a MOVING target: a function that always names a point at
-- most `step` tiles away in the straight-line direction of the real
-- destination, and the real destination once within `step`.  navTo
-- re-resolves tx()/ty() on every replan, so this converges on the real
-- target through many small (cheap, cap-safe) BFS queries instead of one
-- long one.
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
local function creepNav(tx, ty, opts)
  local fx, fy = creepXY(tx, ty)
  return H.navTo(fx, fy, opts)
end

-- a care stop that skips (logged) rather than hangs when the field isn't
-- settled.  H.fieldCare does not work on map 351 regardless of party
-- state, so care() here settles and logs but never opens the menu; all
-- recovery on this map happens through the next contact battle's
-- in-battle heal/revive instead.
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

-- chestAuto: live-staged (bfsPath candidates), so no hand-guessed stand
-- tile is needed for either map-351 chest.
local CHEST_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
local function chestAuto(cx, cy, bit, what, item)
  local pick
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

-- Strago's join-level probe: logged, not asserted.
-- Returns a step object (H.call(...)) -- call it as a list ENTRY, never
-- from inside another H.call's body (that only constructs a throwaway
-- step and logs nothing).
local function logStragoJoin()
  return H.call(function()
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
  end)
end

-- --------------------------------------------------------- battle 31/45 --
-- The wandering flames and the (21,22) ambush are ordinary contact/tile
-- battles; navTo's playBattles="tactical" branch already fights anything
-- that starts while it walks, with a care stop after each leg.
--
-- healPercent=85 keeps newFightDriver topping everyone up early per-fight
-- rather than waiting for TERRA (the healer) to drop, which would stop
-- all further in-battle healing.  healer stays TERRA rather than nil: a
-- shared mayHeal policy makes healing look attractive to every actor every
-- turn, not just the down actor's own fallback case, so the fight never
-- finishes.
--
-- Balloons are weak to ice|water, and OT6's shield-break ratio is 4:1
-- weak:unweak, so an unweak physical hit while shields hold does a
-- quarter the damage an elemental hit would.  opts.magic routes TERRA's
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

-- Map 351's internal short_entrance warps fire purely by standing on
-- their SrcPos tile, with no direction test, exactly like the (4,10)
-- floor trigger this file already rides with a plain H.navTo/creepNav --
-- no crossDoor-style staged/held diagonal approach is needed.
--
-- A short_entrance relocates the party the instant it lands tile-aligned
-- on SrcPos, so fieldX/Y jump to DestPos before navTo's own calm/settle
-- completion test can accumulate; passing navTo's `arrive` opt ends the
-- walk-to-SrcPos step the moment fieldX/Y read the known DestPos instead
-- of waiting on that race.
--
-- `flee`: islands 13 and 11 hold six of the twelve wandering flames
-- between them, and none of the twelve are required content, so holding
-- L+R (playBattles="flee") past a wandering flame instead of fighting it
-- avoids fights this route does not need to survive.  Defaults to
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

-- --------------------------------------------------------- the ambush --
-- The (21,22) ambush (battle 45, 4x Balloon) is a pincer whose opening
-- round lands before the player gets a turn, so it is retried from a
-- checkpoint with a spread battle seed like FlameEater's own ladder below
-- rather than assumed winnable in one try.  $050A is set as the event's
-- first action and cleared only after post-battle teardown on a real win,
-- the same "only a real win reaches the tail" shape $0090 gives
-- FlameEater, so the ladder here watches $050A instead of a battle-menu
-- flag.
local L45 = H.newSeedLadder("ambush (battle 45)", { attempts = 5 })
local ambBlob, ambWon = nil, false

local function ambushAttempt(n)
  local F = H.newFightDriver("ambush", { tactical = true, boost = true,
    bank = 3, items = true, cure = true, healer = TERRA, healPercent = 85,
    magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } })
  local dead, giveUp = 0, 0
  local loadReq
  -- H.cond(pred, thenSteps, elseSteps) hands elseSteps to the shared
  -- lib's own seqStep(), which needs a plain list, not a pre-wrapped
  -- compound step (seq({...})).
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
    pressWalk("up", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (21,22) -> battle 45"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "ambush battle up", 10),
    H.waitFrames(90),
    H.driveUntil(function()
      if battleHpAllZero() and not H.hasControl() and H.eventRunning() then
        dead = dead + 1
      else
        dead = 0
      end
      return (not H.battleLoadStarted() and not H.battleActive()) or dead >= 300
    end, 1800000, {
      H.call(function()
        if dead > 0 then H.setPad({}); return end
        if H.battleLoadStarted() or H.battleActive() then F.frame(); return end
        F.idle()
      end),
    }, "ambush fight (attempt " .. n .. ")"),
    H.call(function()
      H.log(string.format("[ambush] battle torn down or wiped, attempt %d, f%d",
        n, H.frame))
    end),
    -- the win tail clears $050A; a loss goes to vanilla GameOver and never does
    H.driveUntil(function()
      giveUp = giveUp + 1
      return sw(0x050A) == 0 or giveUp >= 3000
    end, 3200, {
      H.call(function()
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail clears $050A (or the loss shows itself)"),
    H.call(function()
      H.setPad({})
      if sw(0x050A) == 0 then
        ambWon = true
        H.log(string.format("ambush BEATEN on attempt %d, f%d", n, H.frame))
      else
        H.log(string.format("ambush attempt %d LOST (0x050A still set after " ..
          "teardown), f%d", n, H.frame))
      end
    end),
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
-- bespoke per-turn plan (the Aqua Rake/Ice Rod optimizations are filed,
-- not built -- see the header).  A seed ladder (H.newSeedLadder, 5 rungs
-- like gen_sabin_train's battle 68) retries a loss from a checkpoint taken
-- just before the trigger tile, with a care stop each attempt.
local L79 = H.newSeedLadder("FlameEater (battle 79)", { attempts = 5 })
local feBlob, feWon = nil, false

local function flameEaterAttempt(n)
  local F = H.newFightDriver("FlameEater", { tactical = true, boost = true,
    bank = 3, items = true, cure = true, healer = TERRA, healPercent = 60 })
  local dead, giveUp = 0, 0
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
    H.driveUntil(function()
      if battleHpAllZero() and not H.hasControl() and H.eventRunning() then
        dead = dead + 1
      else
        dead = 0
      end
      return (not H.battleLoadStarted() and not H.battleActive()) or dead >= 300
    end, 1800000, {
      H.call(function()
        if dead > 0 then H.setPad({}); return end
        if H.battleLoadStarted() or H.battleActive() then F.frame(); return end
        F.idle()
      end),
    }, "FlameEater fight (attempt " .. n .. ")"),
    H.call(function()
      H.log(string.format("[FlameEater] battle torn down or wiped, attempt %d, f%d",
        n, H.frame))
    end),
    -- the win tail flips $0090; a loss goes to vanilla GameOver and never does
    H.driveUntil(function()
      giveUp = giveUp + 1
      return sw(0x0090) == 1 or giveUp >= 3000
    end, 3200, {
      H.call(function()
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0090 (or the loss shows itself)"),
    H.call(function()
      H.setPad({})
      if sw(0x0090) == 1 then
        feWon = true
        H.log(string.format("FlameEater BEATEN on attempt %d, f%d", n, H.frame))
      else
        H.log(string.format("FlameEater attempt %d LOST (no $0090 after " ..
          "teardown), f%d", n, H.frame))
      end
    end),
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

  -- ---- 2. care, then back into town --------------------------------------
  H.fieldCare({ tag = "care at the L tile", threshold = 0.9 }),
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

  -- ---- 3. the inn: door, innkeeper, the whole fire scene -----------------
  crossDoor(12, 19, 346, 23, 23, "inn door 343(12,19)->346(23,23)"),
  H.call(function()
    H.log(string.format("[ot6] inn interior f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),
  -- The innkeeper at (24,15) sits behind a counter tile at (24,16), which
  -- is solid; (24,17), two tiles south on the far side of the counter, is
  -- the reachable stand.  This is a talk-across-a-counter NPC, so it is a
  -- face+A stand rather than a chase.
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
  -- cursor), the innkeeper walking off, and (since $008D=1) straight into
  -- the night/fire scene with no further choice screens (see header).
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
    -- inlined rather than calling logStragoJoin(): that helper is itself
    -- an H.call step object, and invoking it from inside ANOTHER H.call's
    -- body only constructs a throwaway step and runs nothing.
    do
      -- the 37-byte character record, indexed by character id: +$08
      -- level, +$09 current HP, +$0B max HP (top 2 bits are the hp-boost
      -- flag, masked off), +$0D current MP, +$0F max MP (same mask)
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
  -- The load_map lands the party in a 3-tile landing pocket, fully solid
  -- on all three other sides.  The way out is a floor trigger at (4,10),
  -- not an automatic startup event: stepping onto it (gated `$0190==1`)
  -- plays the short "avoid the flames... find RELM!" scene, re-orders the
  -- party, walks LOCKE/STRAGO into the house proper, and clears $0190.
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
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "map 351 settled before pathfinding", 10),
  H.waitFrames(150),
  -- Each hop rides houseWarp() (crossDoor's same-map twin); a care() stop
  -- follows every hop, since wandering flames sit inside these islands and
  -- a contact battle can start on any leg.
  H.call(function() H.log("[ot6] island 0 -> 13: (4,3)->(4,38)") end),
  houseWarp(4, 3, 4, 38, "P1 (4,3)->(4,38): the floor warp into the main hall"),
  care("after P1"),
  -- Shifts every subsequent battle's frame phase by a fixed offset, which
  -- changes which byte of the seed table each one draws.
  H.waitFrames(37),

  -- A mid-leg waypoint plus care() (halving the run of chained fights
  -- between real heals) and fleeing the wandering flames (FLEE_WALK)
  -- through islands 13 and 11 avoids the chain-battle wipe these two
  -- islands otherwise produce.
  creepNav(4, 30, FLEE_WALK),
  care("partway through the main hall (island 13)"),

  H.call(function() H.log("[ot6] island 13 -> 11: (2,24)->(26,36)") end),
  houseWarp(2, 24, 26, 36, "P2 (2,24)->(26,36): into the ambush hall", "flee"),
  care("after P2"),

  -- A pincer formation refuses to be fled at all (flee mode falls back to
  -- fighting only after standing still trying to run for ~60 frames, which
  -- costs a free round of enemy damage first), so the walk stages at
  -- (21,23), one tile short of the ambush trigger, and takes a single
  -- tactical hop onto (21,22) so the ambush is fought from turn one.
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
  -- Right after a win, position and control flags can stall at a
  -- non-map-351 read with hasControl() never returning.  This diagnostic
  -- dump reads the exact fields H.hasControl() gates on ($1eb9 bit7,
  -- $0084, $0059, the movement nibble at $087c+pobj(), $0803 itself which
  -- fieldX/Y/the movement nibble all index through) to name which one is
  -- stuck.
  H.call(function()
    H.log(string.format(
      "[ambush dbg] $0803=$%04X $1eb9=$%02X $0084=$%02X $0059=$%02X " ..
      "movByte=$%02X map1f64=$%04X f%d",
      H.readWord(0x0803), H.readByte(0x1eb9), H.readByte(0x0084),
      H.readByte(0x0059), H.readByte(0x087c + H.readWord(0x0803)),
      H.readWord(0x1f64), H.frame))
  end),

  -- ===================== EXPERIMENT (stall probe) =====
  -- High-resolution (every 5 real frames) logging of every hasControl()
  -- component plus tileAligned/bright/$050A across 600 real frames, to
  -- see whether $050A re-arms or this is a one-shot glitch; a movement
  -- test fired inside the first good window (~dump+25f) to test whether
  -- the party can walk while genuinely controllable.
  H.call(function()
    H.log(string.format("[probe3] EXPERIMENT START f%d", H.frame))
    H.screenshot("stall_probe3_start")
  end),

  -- Phase A1: short passive stretch to reach the known-good window, at
  -- high (every-frame) resolution so the good window's true start/end
  -- frame is pinned exactly.
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      local po = H.readWord(0x0803)
      H.log(string.format(
        "[probe3] f+%d (f%d): hC=%s tA=%s br=%d 1eb9=$%02X 0084=$%02X " ..
        "0059=$%02X movByte=$%02X pxX=$%04X pxY=$%04X 050A=%d ev=%s",
        n, H.frame, tostring(H.hasControl()), tostring(H.tileAligned()),
        bright(), H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059),
        H.readByte(0x087c + po), H.readWord(0x086a + po),
        H.readWord(0x086d + po), sw(0x050A), tostring(H.eventRunning())))
      return n >= 35
    end, 40, { H.call(function() H.setPad({}) end) }, "probe3 phase A1 (35f @1)")
  end)(),

  -- Phase B: movement test INSIDE the good window (dump+~35f onward).
  (function()
    local dirs = { "up", "down", "left", "right" }
    local out = {}
    for _, d in ipairs(dirs) do
      out[#out + 1] = H.call(function()
        local po = H.readWord(0x0803)
        H._pbX, H._pbY = H.readWord(0x086a + po), H.readWord(0x086d + po)
        H._pbHC = H.hasControl()
      end)
      out[#out + 1] = H.hold({ [d] = true })
      out[#out + 1] = H.waitFrames(20)
      out[#out + 1] = H.call(function()
        local po = H.readWord(0x0803)
        local ax, ay = H.readWord(0x086a + po), H.readWord(0x086d + po)
        H.log(string.format(
          "[probe3] IN-WINDOW hold %s x20 REAL frames: px (%d,%d) -> " ..
          "(%d,%d) delta=(%d,%d) hasControl before=%s after=%s movByte=$%02X f%d",
          d, H._pbX, H._pbY, ax, ay, ax - H._pbX, ay - H._pbY,
          tostring(H._pbHC), tostring(H.hasControl()),
          H.readByte(0x087c + po), H.frame))
      end)
      out[#out + 1] = H.release()
      out[#out + 1] = H.waitFrames(5)
    end
    return seq(out)
  end)(),
  H.call(function() H.screenshot("stall_probe3_after_inwindow_moves") end),

  -- Phase A2: continue passive (zero-input) logging every 5 real frames out
  -- to +600 total from EXPERIMENT START, to see whether the bad window is a
  -- one-shot glitch or a repeating re-trigger (watch $050A for a re-arm).
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      if n % 5 == 0 then
        local po = H.readWord(0x0803)
        H.log(string.format(
          "[probe3] passive f+%d: hC=%s tA=%s br=%d movByte=$%02X " ..
          "pxX=$%04X pxY=$%04X 050A=%d ev=%s map1f64=$%04X",
          n, tostring(H.hasControl()), tostring(H.tileAligned()), bright(),
          H.readByte(0x087c + po), H.readWord(0x086a + po),
          H.readWord(0x086d + po), sw(0x050A), tostring(H.eventRunning()),
          H.readWord(0x1f64)))
      end
      return n >= 560
    end, 600, { H.call(function() H.setPad({}) end) }, "probe3 phase A2 (560f)")
  end)(),

  H.call(function() H.screenshot("stall_probe3_after_passive2") end),

  -- Phase C: field menu attempt at the very end, for completeness.
  H.call(function()
    H._pZmBefore = H.readByte(0x26)
    H.log(string.format("[probe3] menu attempt: ZMENUSTATE before=$%02X f%d",
      H._pZmBefore, H.frame))
  end),
  (function()
    local ph, n = 0, 0
    return H.driveUntil(function()
      n = n + 1
      return H.readByte(0x26) == 0x05 or n >= 300
    end, 320, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { "x" } or {})
      end),
    }, "probe3 field menu open attempt (capped, non-fatal)")
  end)(),
  H.release(),
  H.waitFrames(10),
  H.call(function()
    H.log(string.format(
      "[probe3] menu attempt result: ZMENUSTATE $%02X -> $%02X f%d",
      H._pZmBefore, H.readByte(0x26), H.frame))
    H.screenshot("stall_probe3_after_menu_try")
  end),

  H.call(function()
    local po = H.readWord(0x0803)
    H.log(string.format(
      "[probe3] EXPERIMENT END f%d hasControl=%s movByte=$%02X pxX=$%04X " ..
      "pxY=$%04X map1f64=$%04X map()=%d 050A=%d",
      H.frame, tostring(H.hasControl()), H.readByte(0x087c + po),
      H.readWord(0x086a + po), H.readWord(0x086d + po), H.readWord(0x1f64),
      map(), sw(0x050A)))
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

H.run({ maxFrames = 900000 }, flat)
