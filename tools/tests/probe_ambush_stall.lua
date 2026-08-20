-- probe_ambush_stall.lua -- one-shot live probe of issue #127's post-
-- ambush "field-control stall" in gen_thamasa_fire.lua (map 351, the
-- (21,22) scripted ambush, battle 45). Boot/inn/fire/join/warp/ambush
-- steps are copied verbatim from gen_thamasa_fire.lua up through the
-- [ambush dbg] diagnostic dump (same convention as probe_thamasa_house_
-- map.lua: no second real caller yet to justify a lib promotion), then
-- replaces the generator's own (failing) `H.waitUntil(hasControl...)`
-- with unconditional, frame-accurate instrumentation: high-resolution
-- register logging, directional-hold movement tests using H.hold()+
-- H.waitFrames() (NOT H.repeatN(n,{H.call(...)}) -- that idiom never
-- consumes a real frame, see take 1's note below), and a capped field-
-- menu-open attempt.
--
-- Run with the checkpoint env var set (bare run.sh boots a fresh game and
-- never reaches the ambush):
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/thamasa-night-v1 \
--   OT6_TIMEOUT=1800 tools/tests/run.sh tools/tests/probe_ambush_stall.lua
--
-- Verdict (full detail in gen_thamasa_fire.lua's own STATUS header):
-- this is a real engine interaction, not a stuck predicate. See that
-- header for the frame-by-frame evidence and the screenshots this probe
-- produced (build/states/shots/stall_probe3_*.png).
--
-- No -- @suite marker: one-shot measurement, not a suite test.
--
-- ---------------------------------------------------------------------
-- The rest of this file down to "EXPERIMENT (issue #127 stall probe..."
-- is gen_thamasa_fire.lua's own header/body as it stood earlier this pass
-- (kept for context on the route this probe rides through to reach the
-- ambush); the generator's CURRENT header has since been updated with
-- this probe's findings and may read slightly differently.
-- ---------------------------------------------------------------------
--
-- STATUS 2026-08-19 (this pass): the previous pass's mystery is SOLVED.
-- The "one-way relocation" at (4,3)->(4,38) is not a scripted event or an
-- engine tile-fall at all: it is an ordinary SAME-MAP short_entrance
-- record (src=(4,3) map=351 dest=(4,38), flags $01;
-- ff6/src/field/trigger/short_entrance.dat offset $167a, decoded by hand
-- against short_entrance.inc's ITEM_SIZE=6 layout). event_trigger.asm's
-- map-351 block (3 records: (4,10)/(21,22)/(46,53)) and npc_prop.asm's
-- (20 make_npc records, all decoded, coordinates below) between them
-- explain NOTHING south of the landing pocket, because the mechanism
-- neither of those tables can express (a same-map warp) lives in a THIRD
-- table this pass had not yet read. Map 351's short_entrance block runs
-- $167a..$16e0 (17 records = one landing-pocket exit plus 8 forward/return
-- pairs). Decoded and cross-checked against a live grid dump (a new probe,
-- tools/tests/probe_thamasa_house_map.lua, boots the checkpoint, rides the
-- same verified boot/inn/fire/join/  (4,10)-trigger sequence, then reads
-- the LIVE decompressed tile-property tables ($7E7600/$7E7700 through the
-- BG1 tilemap byte, i.e. exactly what H.canStep/H.bfsPath already read)
-- across the whole 64x64 map in one pass -- no walking, so no bfsPath
-- node-cap risk): the map is NOT one contiguous floor. It is 35 separate
-- cardinally-disconnected tile islands (a Python flood fill over the dump
-- confirms zero walkable path between any two of them), stitched together
-- ONLY by the 8 short_entrance pairs. This is why the old plan's
-- navTo(1,0) "explore the north room" reasoning was doomed regardless of
-- BFS cap size: there IS no walkable route from the landing pocket to
-- (4,52)/(21,22)/(45,7)/(46,53) at all, by design (the burning-house
-- "each room is its own pocket, doors do the connecting" structure, same
-- idea as the town's long/short entrances, just entirely internal to one
-- map ID). The full island graph, landing to every objective:
--   island 0  (landing pocket + "north room", the (4,10) trigger lands
--              here) --(4,3)->(4,38)--> island 13 (return via (4,39) or
--              (5,39)->(4,5))
--   island 13 --(2,24)->(26,36)--> island 11 (the (21,22) AMBUSH trigger
--              lives here; return via (26,37)->(2,26))
--   island 11 --(26,21)->(21,9)--> island 1 (the north corridor; return
--              via (21,10)->(26,23))
--   island 1  --(28,3)->(4,55)--> island 28 (FIRE ROD chest (4,52) is
--              here, a dead-end spur; return via (4,56)->(28,5))
--   island 1  --(23,3)->(46,27)--> island 12 (the east wing; return via
--              (46,28)->(23,5))
--   island 12 --(49,21)->(45,10)--> island 4 (ICE ROD chest (45,7) is
--              here, a dead-end spur; return via (45,11)->(49,23))
--   island 12 --(43,21)->(21,54)--> island 26 (the south hall; return via
--              (21,55)->(43,23))
--   island 26 --(21,49)->(46,54)--> island 24 (FLAMEEATER trigger (46,53)
--              is here; no return recorded -- one-way into the boss room,
--              consistent with the win tail's own load_map 349 exit)
-- houseWarp() below rides each of these exactly like crossDoor() rides a
-- town door, except the arrival test is a coordinate match rather than a
-- map-ID change (src map == dest map == 351 for all of them, so
-- crossDoor's own "map() ~= startMap" test would never fire here).
-- This solves the KO risk the previous pass flagged too: the "contact
-- battle at (4,38)" that cost TERRA and STRAGO both KO'd was not caused by
-- the relocation itself (there is no such coupling) -- it was an ordinary
-- wandering-flame contact fought blind by navTo's own tactical driver
-- while pathing toward a target it could never reach; walking each island
-- deliberately (with a care() stop at every warp) should not change the
-- flame encounter rate but keeps healing current between them, per the
-- task's "care between chained fights" rule and #128's healer-lock note.
-- Everything through Strago's join and the map-351 load at (4,11) remains
-- VERIFIED per the prior pass (build/test-runs/fire_out.*). The house
-- graph above is decoded from source + a live grid probe but the walk
-- through it, the FlameEater fight, and the win tail below are being run
-- for the first time this pass; see the caller's final report for the
-- live result.
--
-- gen_thamasa_fire.lua -- v0.13 step L->M (issue #127, "the Thamasa wave"):
-- docs/design/thamasa-route.md section 1, segment 2-4 (the Thamasa fire
-- block).  Cold-boots the tracked `thamasa-night-v1` SRAM checkpoint
-- (world outside Thamasa, $008D=1, party TERRA-LOCKE-SHADOW, pre-inn) the
-- way gen_vector_crash cold-boots `gate-cave-save-v1`: this state is a
-- checkpoint= graph entry, not a prev= savestate link, so every run starts
-- from the real Continue screen.  Generates checkpoint M `fire-out`: world
-- outside Thamasa, $0090=$0091=$0092=1, party TERRA-LOCKE-STRAGO,
-- $02F3=0 (SHADOW gone).
--
-- The route (event_main.asm citations from docs/design/thamasa-route.md
-- section 1 segments 2-4, cross-checked live against the disassembly --
-- see the SURVEY CORRECTIONS below):
--
--  1. Re-enter town the same way K->L did: held RIGHT onto the (250,128)
--     world trigger -> map 343 (23,46).
--  2. The inn.  SURVEY CORRECTION: the survey names no coordinates for the
--     inn door or the innkeeper.  Decoded live from the disassembly rather
--     than guessed: short_entrance.dat's map-343 block has a record
--     src=(12,19) -> map 90+256=346 dest=(23,23) (the "+256" offset is
--     measured against the already-known Strago's-house record,
--     src=(29,13) -> map 93+256=349 dest=(37,24), which matches
--     thamasa-route.md exactly).  So the inn's exterior door is 343
--     (12,19) -> interior map 346 (23,23), and NPCProp::_346's first
--     record (obj $10, the "$10 + record order" rule gen_thamasa_arrive's
--     Strago talk already relies on) is the innkeeper at (24,15), event
--     _cbd73f: "1 GP per night. Why not relax for a spell? 0: Yes / 1: No"
--     (dlg $079D, since $008D=1 and $007D=1 by the time L is reached).
--     Choosing Yes (the default cursor position, so plain edge-A works)
--     runs _cbd7ac: take_gil 1, the innkeeper walks off-screen, and since
--     $008D=1 it falls straight into _cbdcc7 -- the whole night/fire scene
--     -- with NO further choice screens.  So this is one advanceStory-style
--     drive from the Yes confirm to control settling back on map 343.
--  3. The night scene (_cbdcc7, :70419): SHADOW leaves the party
--     (char_party SHADOW,0 :70456), the fire starts, $0190=1 $008E=1
--     (:70634-70635), Shadow runs off after Interceptor and goes
--     unavailable ($02F3=0 :70653).  Control returns on map 343 at
--     (12,21), retiled burning (mod_bg_tiles under $008E && !$0090).
--  4. Talk to Strago at the house door.  This is an NPC event, NOT the
--     (29,13) tile door: NPCProp::_343 record 5 (index 4, 0-based;
--     make_npc {39,24}, $0508, event _cbde30) -- so obj $10+4 = $14.
--     Discovered live (findNpc below) rather than trusted blind, because
--     map 343 carries far more than 16 make_npc records across its many
--     switch-gated variants and the "$10 + order" rule is unverified past
--     16 entries on this specific map.
--     The scene ends with Strago joining (char_party STRAGO,1 + $02E7=1
--     $02F7=1, :71790-71801) and load_map 351 {4,11} (:71852), forced
--     entry party TERRA-LOCKE-STRAGO (:71874).
--  5. Map 351, the burning house (event-only; every exit is scripted).
--     Two chests, visible on the walk (chest_visibility.py / the #84
--     rule): Fire Rod bit 104 (4,52), Ice Rod bit 105 (45,7) -- decoded
--     live from treasure_prop.dat (audit_chests.py's own table), not
--     guessed.  Twelve wandering flame NPCs (make_npc ... set_npc_movement
--     RANDOM, npc_prop.asm:15717-15860) fire battle 31 (formation 158/159,
--     Balloon x3/x6) on contact; a scripted four-Balloon ambush sits on
--     the (21,22) FLOOR TRIGGER (event_trigger.asm:1715, not an NPC).
--     FlameEater's fight is ALSO a floor trigger, (46,53)
--     (event_trigger.asm:1716, _cbe767) -- there is no FlameEater sprite
--     record in NPCProp::_351 at all, so the previous plan's assumption of
--     a contact-talk NPC there was wrong; it fires on tile entry like the
--     ambush.  The trigger's own script re-forces party order
--     STRAGO,TERRA,LOCKE (party_chars STRAGO,TERRA,LOCKE, :72101) right
--     before `battle 79` (:72124), and the post-battle gate is
--     `call _ca5ea9` -- the SAME win/lose gate Dadaluma and TunnelArmr use
--     (a real win sets $0090=1 at :72129 and despawns the trigger NPC; a
--     loss falls into vanilla GameOver), so the ladder below watches
--     $0090 rather than any battle-menu flag.
--  6. Win tail: the Relm/Interceptor rescue, Shadow's smoke-bomb exit, the
--     night talk at Strago's house (load_map 349 {64,16} :72613), ending
--     $0091=1 $0098=1 (:73000-73001), control in the house, party
--     TERRA-LOCKE-STRAGO.
--  7. Leaving the house through 349 (37,25) (event_trigger.asm:1708,
--     gated $0091 && !$0092) plays Shadow's goodbye on town 343 (29,15):
--     remove_equip SHADOW (:73018, his gear returns to inventory),
--     $0092=1 (:73302).  This MUST run before the town is left, per the
--     task brief -- it is the last chance this segment gets at it.
--  8. Out of town the way K->L measured it (long_entrance.dat map-343
--     south strip, src (19,48) len 6, landing world (249,128)) and the
--     real Save UI at slot 3 -- checkpoint M, `fire-out-v1`.
--
-- Ice Rod: not driven as an in-battle item cast this pass.  newFightDriver
-- has no generic "cast an item's attached spell" branch (only the named
-- Tonic/Potion/Fenix Down heal line and the Tools/Blitz skill lines), and
-- building a bespoke Item->target steer for one rod cast was cut for scope
-- -- the chest is opened and carried, but FlameEater is fought with the
-- lib driver's plain kit (boosted Fight from whoever holds it, TERRA's
-- Cure).  This is the "verify what the engine supports" question the task
-- flagged as open; it stays open.  Filed rather than guessed at.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
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
-- make_npc records on one map (see the header's survey correction).
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

-- MEASURED (2026-08-19): map 351 is big enough that H.bfsPath's 4096-node
-- cap (nodes are (x,y,z) triples; ot6_field.lua:503) goes dry on a single
-- long query -- the Fire Rod's stand ((4,52), ~40 tiles straight down the
-- entry shaft) came back "no path" even though the shaft is a plain
-- corridor, the same trap gen_tunnelarmr's header documents for map 75
-- ("long BFS queries... run the 4096-node cap dry and answer 'no path' for
-- tiles that are plainly walkable"; its fix there is a chain of short
-- hand-placed waypoints).  Map 351 has no waypoint table here, so instead
-- of hard-coding one, creepXY hands navTo a MOVING target: a function that
-- always names a point at most `step` tiles away in the straight-line
-- direction of the real destination, and the real destination once within
-- `step`.  navTo re-resolves tx()/ty() on every replan, so this is a
-- continuous short-hop pursuit that converges on the real target through
-- many small (cheap, cap-safe) BFS queries instead of one long one.
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
-- settled -- zozo4's climbCare rule, needed on map 351's scripted stretches
-- MEASURED (2026-08-19): H.fieldCare is not usable AT ALL on map 351,
-- regardless of party state. First measured with TERRA and STRAGO both
-- KO'd: opening the field menu worked (the roster log printed fine), but
-- every plan the policy tried -- Fenix Down revives, a Tonic top-up on
-- LOCKE who was alive the whole time -- came back "REFUSED by the game",
-- and the drive that presses B to close the menu afterward timed out at
-- 2400 frames (hasControl() never returned). Retested with the WHOLE party
-- alive but hurt (102/345, 397/397, 217/434) in case this was a revival-
-- only edge case: SAME result -- a plain Cure cast and a plain Tonic use
-- were BOTH refused, and the menu-close hang happened again regardless.
-- So this is not about who is dead; H.fieldCare cannot act on this map at
-- all. Filed, not chased further (root cause is in shared library
-- territory, out of scope for this generator -- see the spawned follow-up
-- task). In-battle Fenix Down/Cure via newFightDriver's #128 mayHeal
-- fallback DOES work here (measured repeatedly, live) so care() on this
-- map is now a no-op: it settles and logs, never opens the menu, and all
-- recovery happens through the next contact battle instead.
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
  -- NOTE (2026-08-19): the CHEST_CAND reachability probe below is only a
  -- heuristic at range -- H.bfsPath's 4096-node cap can make a genuinely
  -- reachable candidate read NONE from far away (see creepXY's header) --
  -- so a bad pick here is not fatal; the walk itself creeps in short hops
  -- regardless of which candidate was chosen.
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

-- ---------------------------------------------------------- P3: Strago's --
-- join-level probe (the survey's join-level question -- no norm_lvl at
-- join, per thamasa-route.md finding 3.  Logged, not asserted: whatever
-- char_prop's init-time averaging produces is measured here rather than
-- predicted).
-- NOTE: returns a step object (H.call(...)) -- call it as a list ENTRY,
-- never from inside another H.call's body (that only constructs a
-- throwaway step and logs nothing; measured the hard way, see the STATUS
-- note at the top of this file).  The one live call site inlines this
-- instead, for exactly that reason.
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
-- battles; navTo's playBattles="tactical" branch (H.newFightDriver
-- underneath) already fights anything that starts while it walks.  No
-- special handling needed beyond passing tactical opts through, and a care
-- stop after each leg per the task's "care between chained fights" note.
--
-- MEASURED (2026-08-19): the default healPercent=55 was NOT enough.  A live
-- run wiped the party approaching the (21,22) ambush -- creepNav(21,22,...)
-- chained 4-5 wandering-flame contact battles back to back inside ISLAND
-- 11 alone (three flames live there per npc_prop.asm, and the corridor from
-- P2's landing (26,36) to the ambush tile crosses all of them) with no
-- care() stop possible in between (they're random-movement contacts, not
-- plannable waypoints), so chip damage from each fight carried into the
-- next; by the time the scripted 4x-Balloon ambush (battle 45) started the
-- party was already down to ~65-90% and TERRA -- the designated healer --
-- was the FIRST to drop, which stops all further in-battle healing (the
-- exact risk the task brief named: "TERRA the healer DIED in the prior
-- session's one deep run"). Raising healPercent so newFightDriver tops
-- everyone up much earlier per-fight is the only lever available inside a
-- single navTo call (no post-battle-field-care hook exists).
--
-- FURTHER MEASURED (2026-08-19): even with healPercent=85 and mid-leg
-- waypoints (below), island 13 alone burned all 3 Fenix Downs and still
-- wiped -- H.fieldCare turned out to be non-functional on this map (see
-- care()'s own note), so once the bag ran dry there was no recovery left
-- at all. Tried healer=nil (letting every actor reach for the bag from
-- turn one, not just TERRA once she falls, per #128's mayHeal fallback)
-- expecting more resilience; it backfired live -- monhp sat at 555/555
-- UNCHANGED for 3300+ straight frames while the whole party did nothing
-- but heal/revive each other in a loop, because mayHeal now made healing
-- look attractive to everyone every turn instead of only the down actor's
-- own fallback case, so nobody ever finished the fight and the bag drained
-- for zero progress. Reverted to healer=TERRA (the #128 fallback alone,
-- not a blanket policy, is the correct amount of sharing) -- the real fix
-- for this segment is smaller waypoint chunks (below), not who is allowed
-- to open the bag.
-- MEASURED (2026-08-19): the fights themselves are slow, not just chained.
-- Live battle logs sat at "monhp=0/sh0,555/sh1,555/sh1,0/sh0" -- two
-- Balloons at full HP -- for 3000+ straight frames with the party fighting
-- the whole time, i.e. plain boosted Fight was landing near zero net
-- damage. The design doc's own finding (thamasa-route.md's Balloon row):
-- weak to ice|water, and OT6's shield-break ratio is 4:1 weak:unweak
-- (ot6_break.asm:1487-1497, cited in newFightDriver's own boost comment) --
-- an unweak physical hit while shields hold is doing a QUARTER the damage
-- an elemental hit would. opts.magic routes TERRA's turns to Ice (spell
-- $01, `boost=false` per newFightDriver's own note: "what a caller wants
-- when the point is the element rather than the damage") instead of
-- boosted Fight whenever she is not needed to heal; if she does not know
-- Ice yet at this join level the driver's own fallback (spellCell finds
-- nothing -> falls through to Tools/Fight) keeps this harmless to try.
local WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
               items = true, maxFrames = 20000, healPercent = 85,
               magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
-- islands 13/11 only: flee wandering flames rather than fight every one
-- (see houseWarp's own note on the `flee` parameter, below).
local FLEE_WALK = { playBattles = "flee", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }

-- Map 351's internal short_entrance warps (STATUS header): a short_entrance
-- fires purely by standing on its SrcPos tile (ff6/src/field/entrance.asm's
-- CheckShortEntrance compares the live position against SrcPos with no
-- direction test), exactly like the (4,10) floor trigger this file already
-- rides with a plain H.navTo/creepNav -- no crossDoor-style staged/held
-- diagonal approach is needed.
--
-- Two dead ends on the way to this shape, both MEASURED, worth keeping so a
-- third pass doesn't retry them:
-- (1) crossDoor-style staging (reasoning: src map == dest map == 351, so
--     crossDoor's own "map() ~= startMap" arrival test can't fire here) --
--     worked for P1, then failed on P2 with "no path (4,38)->(2,25)" even
--     though the SAME bfsPath call had just approved that candidate when
--     staging picked it.
-- (2) plain `creepNav(sx, sy, WALK)` with no `arrive` override -- this is
--     what actually explains (1)'s ghost failure too. navTo's own
--     completion test wants the party CALM (settled, tileAligned) ON the
--     goal tile for up to 48 frames (ot6_field.lua's calmWant*3 rule,
--     "the party has control OR has been on the goal tile long enough
--     regardless"); a short_entrance instead relocates the party the
--     INSTANT it lands tile-aligned on SrcPos, so fieldX/Y jump to DestPos
--     before calm ever accumulates. navTo's driveUntil never reports
--     "done", so it keeps re-planning -- now FROM the post-warp island,
--     TOWARD a source tile on an island that same warp is the only link
--     to, which of course has "no path". Live evidence: P1's own
--     creepNav(4,3,...) got the party to (4,38) (the warp fired -- visible
--     in the log as the FAIL's own "no path (4,38)->(4,24)" source
--     coordinate, (4,24) being creepXY's fresh waypoint FROM (4,38) TOWARD
--     the now-unreachable (4,3)) and then hard-failed retrying anyway.
-- The fix: pass navTo's own `arrive` opt (an OR'd alternate stop
-- condition, ot6_field.lua:698) so the walk-to-SrcPos step ends the moment
-- fieldX/Y read the KNOWN DestPos, sidestepping the calm/settle race
-- entirely rather than waiting on it.
--
-- `flee`: islands 13 and 11 (the stretch this file's own STATUS/WALK notes
-- above document wiping the party even with healPercent=85 and mid-leg
-- waypoints) hold six of the twelve wandering flames between them, and
-- none of the twelve are required content -- the doc's own words, "A
-- fought flame is hidden+deleted for the rest of the visit", describes an
-- optional contact, not a gate. holding L+R (playBattles="flee") past a
-- wandering flame instead of fighting it is available and unused content
-- on the safer legs, and here it directly avoids fights this route does
-- not need to survive. Defaults to "tactical" (unchanged behavior) so
-- callers on calmer islands, and the ambush/FlameEater trigger legs which
-- SHOULD fight what they hit, are unaffected.
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
-- MEASURED (2026-08-19): the (21,22) ambush (battle 45, 4x Balloon,
-- formation 158/159's bigger sibling per event_main.asm:71993) is NOT
-- survivable by preparation alone. Every live attempt -- full HP entering
-- the fight or not, flee-mode-preserved or worn down -- read partyhp with
-- TERRA and STRAGO ALREADY at 0 on the very first logged battle frame
-- (f+1, menu=82, before the tactical driver has thrown a single input):
-- a pincer opening apparently lands its first round before the player
-- gets a turn, and losing two of three members to it is not something
-- healPercent or a well-timed care() stop can prevent -- there is no
-- frame to act on. This is exactly the shape the FlameEater seed ladder
-- below already solves: a hard, RNG-sensitive fight, retried from a
-- checkpoint with a spread battle seed rather than assumed winnable in
-- one try. event_main.asm's own _cbe622 sets switch $050A=1 as its first
-- action and clears it only at the very end, after the post-battle
-- teardown (`hide_obj`/`delete_obj` the ambush NPCs, `fade_in`) -- the
-- SAME "only a real win reaches the tail" shape $0090 gives FlameEater --
-- so the ladder here watches $050A instead of a battle-menu flag, exactly
-- as FlameEater's own header explains for $0090.
local L45 = H.newSeedLadder("ambush (battle 45)", { attempts = 5 })
local ambBlob, ambWon = nil, false

local function ambushAttempt(n)
  local F = H.newFightDriver("ambush", { tactical = true, boost = true,
    bank = 3, items = true, cure = true, healer = TERRA, healPercent = 85,
    magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } })
  local dead, giveUp = 0, 0
  local loadReq
  -- BUG FOUND LIVE (2026-08-19): H.cond(pred, thenSteps, elseSteps) hands
  -- elseSteps to the shared lib's own seqStep(), which needs a PLAIN list
  -- (#steps/steps[i]) -- passing seq({...}) here instead of the bare
  -- {...} hands seqStep a COMPOUND step object (a {tick=,reset=} table
  -- with no integer part), so #that is 0 and seqStep's tick() loop exits
  -- immediately as "done" without ever running a single inner step. The
  -- five ambushAttempt() calls below all silently no-op'd this way on the
  -- first live run that reached them -- no log line from inside this
  -- function ever printed, straight from L45.watch() to the final "all 5
  -- attempts lost" error. flameEaterAttempt (below) has the EXACT SAME
  -- `H.cond(pred, {}, seq({...}))` shape and is presumably broken the
  -- same way -- consistent with this file's own prior STATUS header, which
  -- said FlameEater "has NEVER been reached by a live run and is
  -- unverified": nothing had exercised the bug before either. Fixed here
  -- (bare {...}, matching every OTHER H.cond call in this file, e.g.
  -- care()'s own) and in flameEaterAttempt.
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
  -- was `seq({...})` here -- ambushAttempt's header explains the bug this
  -- hid (seqStep needs a plain list, not a pre-wrapped compound step); a
  -- bare {...} is the fix, same as every other H.cond call in this file.
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
  -- MEASURED (2026-08-19, this generator's own probe pass): the innkeeper
  -- at (24,15) sits behind a counter tile at (24,16) that bfsPath refuses
  -- as a stand (it is solid), while (24,17) -- two tiles south, the far
  -- side of the counter -- IS reachable (bfsPath len 7 from the door
  -- landing).  This is the Dadaluma note's "talk-across-a-counter"
  -- mechanic (CheckNPCs' extension, player.asm @478e): stand one tile back
  -- from the counter, face it, and the talk reaches through to the NPC
  -- beyond.  chaseTalk's "walk directly adjacent" model does not fit a
  -- counter NPC (it was built for wandering NPCs on open floor), so this is
  -- a face+A stand rather than a chase.
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
    -- P3 (issue #127): inlined rather than calling logStragoJoin() here --
    -- that helper is itself an H.call step object, and invoking it from
    -- inside ANOTHER H.call's body only constructs a throwaway step and
    -- runs nothing (measured: no [P3] line ever appeared in a real run
    -- that reached this point).  logStragoJoin is left in place as a
    -- standalone step for a future caller; this inlines its body.
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
  -- MEASURED (2026-08-19): the load_map lands the party in a 3-tile
  -- landing pocket ((4,10)-(4,11)-(4,12); prop1=$F7, fully solid, on all
  -- three other sides -- bfsPath confirmed the enclosure before this fix).
  -- The way out is a FLOOR TRIGGER at (4,10) (event_trigger.asm:1714,
  -- _cbe5e4), not an automatic startup event: stepping onto it (gated
  -- `$0190==1`, true here) plays the short "avoid the flames... find
  -- RELM!" scene, re-orders the party, walks LOCKE/STRAGO a few tiles
  -- diagonally into the house proper, and clears $0190.  Ridden with
  -- advanceStory like every other scripted stretch.
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
  -- door loads finalize the decompressed prop table LATE (gen_zozo2's
  -- measured rule, reused by gen_zozo4's door()); settle before any
  -- pathfinding reads it.
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "map 351 settled before pathfinding", 10),
  H.waitFrames(150),
  -- The house graph, decoded from ff6/src/field/trigger/short_entrance.dat
  -- offset $167a (17 records, map 351 -> map 351) and cross-checked against
  -- a live full-map tile-property dump (probe_thamasa_house_map.lua): 35
  -- cardinally-disconnected tile islands stitched together ONLY by these
  -- warps.  See the STATUS header for the full island graph.  Each hop
  -- rides houseWarp() (crossDoor's same-map twin); a care() stop follows
  -- every hop, per the task's "care between chained fights" rule -- the
  -- wandering flames sit inside these islands (12 of them, all decoded
  -- from npc_prop.asm), so a contact battle can start on any leg.
  H.call(function() H.log("[ot6] island 0 -> 13: (4,3)->(4,38)") end),
  houseWarp(4, 3, 4, 38, "P1 (4,3)->(4,38): the floor warp into the main hall"),
  care("after P1"),
  -- MEASURED (2026-08-19): this whole route is deterministic frame-for-
  -- frame given identical code (P1 lands at (4,38) on the exact same frame,
  -- 10534, across half a dozen otherwise-different attempts), which means
  -- the wandering flames' contact timing and the pincer/ambush RNG draws
  -- are ALSO pinned by real-time frame count, not luck -- a plain re-run
  -- with no code change reproduces the same wipe every time. A battle
  -- seed ladder (H.newSeedLadder, the FlameEater pattern below) is the
  -- correct tool for this but needs a save/reload-on-loss loop, which
  -- needs the wipe to be caught rather than hard-erroring the whole run
  -- (M.run's own pcall stops the process on the first error() -- there is
  -- no per-step retry); building that around H.navTo's built-in wipe
  -- canary (a hard error by design, ot6_field.lua's wipeCanary) was out of
  -- scope for this pass. This single extra wait is the cheap version of
  -- the same idea: shifting every subsequent battle's frame phase by a
  -- fixed offset changes which byte of the seed table each one draws
  -- (spread()'s own docs: "Replaces H.waitFrames((n-1)*37)"), without
  -- needing the full ladder machinery.
  H.waitFrames(37),

  -- MEASURED (2026-08-19): island 13 (three wandering flames,
  -- (2,29)/(5,31)/(4,35)) and island 11 (three more,
  -- (17,34)/(22,25)/(17,27)) chain-battled the party WIPED on multiple live
  -- runs -- 4-5 contact fights back to back with no field-menu heal between
  -- them (only newFightDriver's in-battle threshold heal, which can't act
  -- once the healer is down, AND H.fieldCare turned out to be broken on
  -- this map, see care()'s note) burned all 3 Fenix Downs and then had
  -- nothing left when the LAST survivor also went down. Two things
  -- together got a live run past this stretch: a mid-leg waypoint + care()
  -- (halving the run of chained fights between real heals; (4,30) and
  -- (24,29) are plain confirmed-walkable tiles from the grid dump, nothing
  -- special about the coordinates) AND fleeing the wandering flames
  -- (FLEE_WALK) on every leg through these two islands rather than fighting
  -- every one -- none of the twelve flames are required content (see
  -- houseWarp's own note on `flee`).
  creepNav(4, 30, FLEE_WALK),
  care("partway through the main hall (island 13)"),

  H.call(function() H.log("[ot6] island 13 -> 11: (2,24)->(26,36)") end),
  houseWarp(2, 24, 26, 36, "P2 (2,24)->(26,36): into the ambush hall", "flee"),
  care("after P2"),

  -- MEASURED (2026-08-19): a (24,29) mid-leg waypoint was tried here too
  -- (matching island 13's), but bfsPath came back "no path (26,36)-
  -- >(24,29)" on a live run -- the offline flood fill that suggested it was
  -- walkable used undirected reachability (any nonzero exit nibble), which
  -- overlooks one-way exit-bit walls the live engine enforces; the earlier
  -- P2 fix (see the STATUS header's dead-end #1) hit the same false-
  -- positive-connectivity trap. Dropped rather than re-guessed: flee mode
  -- already got P2 through island 13 wipe-free and much faster (16621 vs
  -- 35999 frames on the same leg pre-flee), so island 11's own P2->ambush
  -- stretch goes straight there without a waypoint that isn't real.
  -- MEASURED (2026-08-19): with the (24,29) waypoint gone, this leg went
  -- straight back to fighting every wandering flame between (26,36) and
  -- (21,22) (WALK is tactical) and wiped again, right where the earlier
  -- attempts did. FLEE_WALK here too: the flames along the way are still
  -- optional, and the SCRIPTED ambush itself, once triggered by stepping
  -- on (21,22), should be exactly the "unrunnable formation" flee mode's
  -- own fallback describes -- when running fails for M.FLEE_CAP frames it
  -- hands off to the SAME tactical driver WALK would have used, so in
  -- theory the ambush still gets fought properly.  MEASURED live: it does
  -- NOT work out that way for a formation flee refuses outright.  The log:
  -- "flee: this formation refuses the run ($b1 bit 1 held 60 frames -- a
  -- pincer, or a monster nobody runs from) after 62 frames; fighting it
  -- out instead" -- and by the time the fallback took over, partyhp was
  -- already 0,5,0,0 on the very FIRST logged battle frame.  A pincer
  -- (party surrounded) apparently still lets the enemy act during the ~60
  -- frames flee spends standing still trying to run, so attempting to flee
  -- an unrunnable ambush is worse than not trying -- it eats a full round
  -- of free damage before the tactical driver ever gets a turn. Fix:
  -- FLEE_WALK only as far as (21,23), one tile short of the trigger (a
  -- confirmed-walkable staging tile from the grid dump), so any wandering
  -- flame on the way there is still skippable; then a single tactical
  -- WALK hop onto (21,22) itself so the ambush is fought from turn one,
  -- never attempted-and-refused.
  -- MEASURED (2026-08-19): staging at (21,23) and stepping onto (21,22)
  -- tactically (below) fixed the "flee refuses the ambush and eats a free
  -- round" problem, but the ambush itself still wiped the party outright --
  -- see ambushAttempt's own header for the evidence (TERRA and STRAGO both
  -- read 0 hp on the battle's very first frame, before the driver ever
  -- acted). No amount of pre-fight preparation moves that number; this is
  -- the same "hard, luck-sensitive fight" shape FlameEater already has a
  -- seed ladder for, so it gets one too, checkpointed here.
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
  -- MEASURED (2026-08-19): right after a win, a live run read (14,3792)
  -- map=0 -- neither a real map-351 tile nor a real map id -- and NEITHER
  -- a passive settle wait (3600 frames) NOR advanceStory's active A-taps
  -- (60000 frames, matching FlameEater's own win-tail budget) ever saw
  -- hasControl() return -- the position and every flag (ctl/algn/dlg/
  -- batt/ev all false or stuck) stayed byte-for-byte identical from f17665
  -- to past f55465, 37000+ frames with zero change. That rules out "just a
  -- slow scene"; something is not re-initializing after this specific
  -- battle's teardown. This diagnostic dump reads the exact fields
  -- H.hasControl() gates on ($1eb9 bit7, $0084, $0059, the movement
  -- nibble at $087c+pobj(), $0803 itself which fieldX/Y/the movement
  -- nibble all index through) to name which one is stuck, for the
  -- follow-up pass -- filed rather than chased further here (see the
  -- caller's final report).
  H.call(function()
    H.log(string.format(
      "[ambush dbg] $0803=$%04X $1eb9=$%02X $0084=$%02X $0059=$%02X " ..
      "movByte=$%02X map1f64=$%04X f%d",
      H.readWord(0x0803), H.readByte(0x1eb9), H.readByte(0x0084),
      H.readByte(0x0059), H.readByte(0x087c + H.readWord(0x0803)),
      H.readWord(0x1f64), H.frame))
  end),

  -- ===================== EXPERIMENT (issue #127 stall probe, take 3) =====
  -- Take 2 found a real but SHORT hasControl()==true window (roughly
  -- dump+20f..dump+120f: movByte=$02, position sane) followed by a relapse
  -- into a bogus state (movByte=$E9, pxY=60672 -- not a real map
  -- coordinate) that outlasted the rest of that probe (260+ frames with
  -- zero pixel displacement under held input), yet a menu-open (X) attempt
  -- issued entirely inside the bogus window still worked (ZMENUSTATE hit
  -- $05). This take: (1) high-resolution (every 5 real frames) logging of
  -- EVERY hasControl() component plus tileAligned/bright/$050A across 600
  -- real frames, to see whether $050A re-arms (the standing-on-a-floor-
  -- trigger re-entry flicker ot6_field.lua's phaseWalk header documents:
  -- "a stood-on trigger tile re-enters its script every frame") or whether
  -- this is a one-shot glitch; (2) a movement test fired INSIDE the first
  -- good window (~dump+25f) instead of after a long delay, since take 2's
  -- movement test accidentally landed entirely in the bad window and so
  -- never actually tested whether the party can walk while genuinely
  -- controllable.
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
