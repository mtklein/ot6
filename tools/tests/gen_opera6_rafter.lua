-- gen_opera6_rafter.lua -- v0.5 Beat A step 6: opera_dance_done (map 238
-- {98,7}, $0111=1) -> the rafter chase -> generate ultros2_entry one
-- interaction before battle 104 (Ultros②, $012d, 6 shields, slash|pierce).
--
-- Measured route: touch Ultros's letter, return through the active theater to
-- alert the Impresario, ride the briefing, talk to the stage master, operate
-- the far-right switch, enter the left framework, and cross map 235 to Ultros.
--
-- The rat gates are played rather than switched off (issue #75).  The five rat
-- NPCs ({8,11} {11,15} {18,14} {21,7} {13,12}, switches $034C-$0350,
-- npc_prop.asm _235) used to be switched off before map 235 instantiated; now
-- they wander live.  Each is a no_react collision NPC whose event is
-- `battle 25`: a win despawns it and clears its switch, and a loss restarts
-- the chase (_caba0b).  The catwalk crossing fights whichever rats collide,
-- with the fight tapped like any encounter, inside the same 5-minute timer
-- (start_timer 0, 18000, event_main.asm:28736, counter at $1189; it ticks
-- through battles, and running it out fades to _caba09, which drops the
-- weight and restarts the opera, so the route stays short and rats that do
-- not collide are left alone).  The crossing itself is crossRafters on a
-- three-attempt ladder rather than a navTo, because the catwalk is one tile
-- wide, a rat parked on it leaves the goal with no path at all, and how many
-- rat fights the rats force decides whether the crossing fits the clock;
-- crossRafters' header has the measurements.  Before the entry point
-- generate, the script waits until no live rat stands within 4 tiles of
-- (14,7), so the banked state cannot boot into a rat collision under
-- battle_ultros2's immediate A-taps.
--
-- The facing is produced by input rather than poked: the old generator wrote
-- the object facing byte and $0743 to point the party at Ultros; now the last
-- action at the entry point is a short RIGHT press against his occupied tile
-- {15,7}, which is a blocked press that turns the party in place, and the
-- facing is asserted from RAM afterwards.  This file writes no emulated game
-- state.
--
-- Note: the WoB story encounter is `_cabf4b` -> battle 104.  Battle 134
-- belongs to the WoR Opera House dragon/weight event (`$0387=1`); older route
-- notes conflated the two.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright()>=15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function key(x,y) return y*256+x end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d)z%d ctl=%s | 58=%d 110=%d 111=%d 345=%d 355=%d 366=%d 387=%d 1B0=%d 1B4=%d A4=%d 2BA=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    tostring(H.hasControl()),
    sw(0x0058), sw(0x0110), sw(0x0111), sw(0x0345), sw(0x0355), sw(0x0366),
    sw(0x0387), sw(0x01B0), sw(0x01B4), sw(0x00A4), sw(0x02BA)))
end

-- rat bookkeeping: NPC_9..NPC_13 ride objects 24..28 (NPC_n = object
-- n+15, gen_moogle's measured map), gates $034C..$0350 in list order.
-- A rat is live while its gate switch is still set.
local function ratLine()
  local t = {}
  for k = 0, 4 do
    local obj = 24 + k
    local ox = H.readWord(0x086a + 0x29 * obj) >> 4
    local oy = H.readWord(0x086d + 0x29 * obj) >> 4
    t[#t + 1] = string.format("%d%s@(%d,%d)", k,
      sw(0x034C + k) == 1 and "+" or "-", ox, oy)
  end
  return table.concat(t, " ")
end
local function ratNear(x, y, r)
  for k = 0, 4 do
    if sw(0x034C + k) == 1 then
      local obj = 24 + k
      local ox = H.readWord(0x086a + 0x29 * obj) >> 4
      local oy = H.readWord(0x086d + 0x29 * obj) >> 4
      if math.abs(ox - x) + math.abs(oy - y) < r then return true end
    end
  end
  return false
end

-- crossRafters: walk to (tx,ty) on map 235 with the five rats live.
--
-- Why this is not a navTo.  The rafters are one tile wide from end to end:
-- measured 2026-08-13 by dumping the tile properties of every tile on map
-- 235, the only route from the left framework to Ultros is the single chain
-- col 6 -> (7,12) -> col 8 -> row 16 -> col 11 -> row 18 -> col 13 -> row 15
-- -> col 19 -> row 12 -> col 11 -> row 7, with no second way round at any
-- point.  A live rat standing on any tile of it therefore disconnects the
-- goal, because the passability model refuses a tile an object occupies
-- (lib/ot6_field.lua:395), and navTo can only wait: its no-path branch idles
-- 45 frames and re-searches, 20 times, and then fails.  Measured on the run
-- that reported `navTo: no path (6,12)->(14,7)`: bfsPath answered nil for
-- more than 600 consecutive frames with rats sitting at (8,15) and (14,12),
-- two tiles of that chain, so the 900-frame allowance is the whole margin.
--
-- What this does instead.  Same BFS, re-planned on every tile-aligned frame
-- (the `corridor` shape above), and three things navTo does not do:
--
--   * it dodges, taking a step only onto a tile no live rat is standing
--     next to, because standing next to one buys a fight (below);
--   * when the goal is unreachable it waits, and backs off if a rat has come
--     within two tiles, because a wandering rat usually steps off the
--     corridor on its own -- median 75 frames over 81 measured blockages,
--     though the tail runs to 1250;
--   * and when waiting has not worked for `patience` frames it goes and
--     stands beside the nearest reachable live rat on purpose.  A rat is a
--     collision-activated object and `CheckCollosions` fires its event as
--     soon as a character stands on any of the four tiles around it
--     (ff6/src/field/obj.asm:4035-4055, reached from the per-object update
--     at :4361); the event is `battle 25`, and a win despawns the rat and
--     clears its gate.  So a corridor a rat will not leave is cleared by
--     fighting the rat, which is what the chase is built out of, and it
--     terminates: there are five rats and each is removed for good.
--
-- The fights are driven by the tactical fight driver rather than by blind
-- A-taps, which is what the crossing used to do through navTo's
-- `playBattles=true`.  That was measured on 2026-08-13 and it is not a
-- style point: three rat fights tapped blind ran about 3200 frames each,
-- more than half of the chase's whole 18000-frame timer, and they left
-- LOCKE dead at 0/353 in the banked entry point, which
-- `tools/audit_party_hp.py` fails.
local RAT_GATE0, RAT_OBJ0 = 0x034C, 24
-- the eight moves M.bfsPath can return, and what each does to (x,y)
local DELTA8 = { up = {0,-1}, right = {1,0}, down = {0,1}, left = {-1,0},
                 upright = {1,-1}, downright = {1,1},
                 downleft = {-1,1}, upleft = {-1,-1} }
local function ratXY(k)
  local obj = RAT_OBJ0 + k
  return H.readWord(0x086a + 0x29 * obj) >> 4,
         H.readWord(0x086d + 0x29 * obj) >> 4
end
-- `res` is a one-field table the caller reads afterwards: res.ok is true only
-- if the party is standing on the goal.  The two ways to fail -- the chase
-- clock running out, and a lost rat fight, which is a wipe -- both end the
-- drive quietly with res.ok false, because the caller is a three-attempt
-- ladder that reloads and tries again from a different rat arrangement.
-- `hold` is that ladder's stagger: the aligned frames to stand still before
-- setting off, which is what leaves the rats somewhere else next attempt.
local function crossRafters(tx, ty, maxF, patience, hold, res, what)
  local hb, stuck, clearing, battN, wipeN = 0, 0, 0, 0, 0
  local refusedN, held, lost = 0, 0, nil
  local fight = H.newFightDriver("rafters",
    { tactical = true, boost = true, items = true, healPercent = 70,
      healer = 0x01 })
  -- Try the run for 60 frames, then fight it out.  Running would have been
  -- the cheap answer, and it would still have cleared the corridor: the
  -- rat's event is `battle 25` followed by `if_b_switch $40` -> hide_obj +
  -- switch=0 (event_main.asm:30200-30208), that command jumps when the bit
  -- is CLEAR (field/event.asm:4053-4060), and the bit is battle switch $40,
  -- which only a loss sets (HANDOFF records the chain; LoseBattle is
  -- battle_main.asm:16040-16042).  A run is not a loss, so a run would take
  -- the despawn branch.
  --
  -- Measured 2026-08-13, and the pack refuses it: $b1 read $06 -- bit 1
  -- can't-run plus bit 2 harder-to-run -- for 3000 consecutive battle frames
  -- with battle type 0, so not a pincer, while the per-character run
  -- counters stalled at 5,2,2 against a difficulty of 6 and nobody left.
  -- What is kept is newFlee's own refusal test (lib/ot6_field.lua:218-256;
  -- it is local to that file, so it is open-coded here): hold L+R, and hand
  -- the fight to the tactical driver once the flag has held 60 frames.
  local function battleFrame()
    if battN <= 3 then refusedN = 0 end
    refusedN = ((H.readByte(0x00b1) & 0x02) ~= 0) and refusedN + 1 or 0
    if battN == 10 or battN % 600 == 3 then
      H.log(string.format("cross battle f+%d $b1=%02X type=%d $2f4b=%02X " ..
        "running=%d difficulty=%d counters=%d,%d,%d refused=%d",
        battN, H.readByte(0x00b1), H.readByte(0x201f), H.readByte(0x2f4b),
        H.readByte(0x2f45), H.readByte(0x3a3b), H.readByte(0x3d70),
        H.readByte(0x3d72), H.readByte(0x3d74), refusedN))
    end
    if refusedN >= 60 or battN > 1200 then fight.frame(); return end
    H.setPad({ l = true, r = true })
  end
  return H.driveUntil(function()
    if H.fieldX() == tx and H.fieldY() == ty
       and H.hasControl() and H.tileAligned() then
      res.ok = true
      H.setPad({})
      return true
    end
    if lost then H.setPad({}); return true end
    return false
  end, maxF, { H.call(function()
    hb = hb + 1
    if hb % 600 == 0 then
      H.log(string.format("cross f%d (%d,%d) z%d timer=%d bfs=%s stuck=%d cleared=%d rats: %s",
        H.frame, H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3,
        H.readWord(0x1189), H.bfsPath(tx, ty) and "path" or "nil",
        stuck, clearing, ratLine()))
    end
    -- the chase's own clock is the real budget, not maxFrames: running it out
    -- fades to _caba09, drops the weight and restarts the opera, and every
    -- assertion after this point would then be describing a different scene.
    if H.readWord(0x1189) == 0 and not lost then
      local live = 0
      for k = 0, 4 do if sw(RAT_GATE0 + k) == 1 then live = live + 1 end end
      lost = "the chase clock ran out"
      H.log(string.format("cross: the rafter timer ran out at (%d,%d) with %d " ..
        "rats still live -- the weight drops and the opera restarts, so this " ..
        "attempt is over", H.fieldX(), H.fieldY(), live))
      H.setPad({}); return
    end
    -- wipe canary, the same shape and the same 300-frame debounce as the one
    -- lib/ot6_field.lua:151 arms inside navTo (it is local to that file).  A
    -- wipe here reads as a frozen walker otherwise; see HANDOFF.
    wipeN = H.partyWiped() and wipeN + 1 or 0
    if wipeN >= 300 and not lost then
      lost = "a lost rat fight"
      H.log("cross: THE PARTY IS WIPED -- every member has read 0 hp for 300 " ..
        "consecutive frames.  A lost rat fight restarts the chase (_caba0b), " ..
        "so this attempt is over rather than this being a stuck walker.")
      H.setPad({}); return
    end
    if lost then H.setPad({}); return end
    -- battle/dialog are debounced 3 frames for navTo's reason: both signals
    -- live in RAM the field module also writes, and acting on a one-frame
    -- ghost taps A on the open field.
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN == 0 then fight.idle() end
    if battN >= 3 then battleFrame(); return end
    if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
    if battN > 0 then H.setPad({}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    if held < hold then held = held + 1; H.setPad({}); return end
    -- Dodging, which is the expensive part of this map.  A rat fires its
    -- fight from its own update as soon as a character stands on one of the
    -- four tiles around it (obj.asm:4035-4055), so a step that lands next to
    -- a rat buys a fight, and the fights are what overruns the chase clock:
    -- measured 2026-08-13, one rat fight runs about 2500 frames of an
    -- 18000-frame timer, and four of them ran two of four trial crossings out
    -- of time.  So the walk only takes a step onto a tile no live rat is
    -- standing next to, and otherwise holds still, or backs off if a rat has
    -- come within two tiles.  Waiting costs the clock far less than fighting.
    local function ratDist(x, y)
      local d = 99
      for k = 0, 4 do
        if sw(RAT_GATE0 + k) == 1 then
          local rx, ry = ratXY(k)
          local m = math.abs(rx - x) + math.abs(ry - y)
          if m < d then d = m end
        end
      end
      return d
    end
    local x, y = H.fieldX(), H.fieldY()
    -- back off: the neighbour (or standing still) that is furthest from every
    -- live rat, used only when one is close enough to reach us next step
    local function backOff()
      local bestMv, bestD = nil, ratDist(x, y)
      for _, mv in ipairs({ "up", "right", "down", "left",
                            "upright", "downright", "downleft", "upleft" }) do
        local d = DELTA8[mv]
        if H.canStep(x, y, mv) then
          local nd = ratDist(x + d[1], y + d[2])
          if nd > bestD then bestMv, bestD = mv, nd end
        end
      end
      if bestMv then H.setPad({ [H.movePress(bestMv)] = true })
      else H.setPad({}) end
    end
    local plan = H.bfsPath(tx, ty)
    if plan then
      if stuck > 0 then
        H.log(string.format("cross: path reopened at f%d after %d frames blocked",
          H.frame, stuck))
      end
      stuck = 0
      if #plan == 0 then H.setPad({}); return end
      local d = DELTA8[plan[1]]
      local nx, ny = x + d[1], y + d[2]
      if ratDist(nx, ny) >= 2 or (nx == tx and ny == ty) then
        H.setPad({ [H.movePress(plan[1])] = true })
      else
        backOff()                    -- next tile is beside a rat: do not buy it
      end
      return
    end
    stuck = stuck + 1
    if ratDist(x, y) <= 2 then backOff(); return end
    if stuck < patience then H.setPad({}); return end
    -- A rat has been parked on the one-tile-wide corridor for `patience`
    -- frames and is not wandering off, so the only way past is through it:
    -- walk up beside it, take the fight, and the win despawns it.
    local best
    for k = 0, 4 do
      if sw(RAT_GATE0 + k) == 1 then
        local rx, ry = ratXY(k)
        for _, d in ipairs({ {0,-1}, {1,0}, {0,1}, {-1,0} }) do
          local p = H.bfsPath(rx + d[1], ry + d[2])
          if p and (not best or #p < #best) then best = p end
        end
      end
    end
    if stuck == patience then
      clearing = clearing + 1
      H.log(string.format("cross: blocked %d frames at (%d,%d); taking the fight " ..
        "with the rat in the way (%s), rats: %s", stuck, x, y,
        best and (#best .. " steps away") or "none reachable", ratLine()))
    end
    if best and #best > 0 then H.setPad({ [H.movePress(best[1])] = true })
    else H.setPad({}) end          -- already beside it: the collision fires
  end) }, what)
end

-- rideScene: the gen_zozo5_ramuh stall-safe cutscene rider.  The stall counter
-- is gated on hasControl() rather than eventRunning(); see issue #3.  v0.5
-- cutscenes require this.
local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly = 0, 0, -1, -1
  return H.driveUntil(function() local d=pred(); if d then H.setPad({}) end; return d end,
    maxFrames, { H.call(function()
      aPh=(aPh+1)%8
      local x,y=H.fieldX(),H.fieldY(); local moving=(x~=lx or y~=ly); lx,ly=x,y
      if H.battleLoadStarted() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if H.dialogWaiting() then stallN=0; H.setPad(aPh<4 and {"a"} or {}); return end
      if not moving and not H.hasControl() then stallN=stallN+1 else stallN=0 end
      if stallN>=180 then H.setPad(aPh<4 and {"a"} or {}); return end
      H.setPad({})
    end) }, what)
end

-- corridor: hand-coded per-tile direction table, canStep-gated on the live z,
-- pulsed so no press outlives its step (gen_opera5_dance's `corridor`).
local function corridor(TBL, tx, ty, maxF, doneFn, what)
  local hb=0
  return H.driveUntil(function()
    if doneFn and doneFn() then return true end
    return H.fieldX()==tx and H.fieldY()==ty and H.hasControl() and H.tileAligned()
  end, maxF, { H.call(function() hb=hb+1
    if hb%120==0 then dumpsw("["..what.."]") end
    if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then H.setPad({}); return end
    local x,y=H.fieldX(),H.fieldY()
    for _,mv in ipairs(TBL[key(x,y)] or {}) do
      if H.canStep(x,y,mv) then H.setPad({[H.movePress(mv)]=true}); return end
    end
    H.setPad({})
  end) }, what)
end

-- bump an on-contact (no_react) NPC at (tx,ty) from approach tile (sx,sy).
local function bumpInto(sx, sy, dir, pred, maxF, what)
  local ph=0
  return H.cond(function() return true end, {
    H.navTo(sx, sy, { maxFrames=12000, playBattles=true }),
    H.driveUntil(pred, maxF, { H.call(function() ph=(ph+1)%16
      if H.battleLoadStarted() then
        H.setPad(ph % 8 < 4 and { "a" } or {})   -- fought, not write-cleared
        return
      end
      if ph<8 then H.setPad({[dir]=true}) elseif ph<12 then H.setPad({"a"}) else H.setPad({}) end
    end) }, what),
  })
end

local function toDoor(tx,ty,bumpDir,destMap,what)
  return H.cond(function() return true end, {
    H.navTo(tx,ty,{maxFrames=18000,playBattles=true,arrive=function() return map()==destMap end}),
    (function() local n=0 return H.driveUntil(function() return map()==destMap end,3000,{
      H.call(function()
        n=n+1
        if H.dialogWaiting() then H.setPad(n%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(n%16<10 and {[bumpDir]=true} or {})
      end)
    },what) end)(),
    H.waitUntil(function() return map()==destMap and settled() end,3000,what.." settled",5),
  })
end

-- The crossing's three-attempt ladder.  Attempt 1 runs from where the walk
-- already stands; 2 and 3 reload the tile it was standing on and hold still
-- for a different number of frames before setting off.  Standing still is
-- what moves the rats: they are RANDOM-movement NPCs, so a different number
-- of frames of the field RNG puts them somewhere else by the time the party
-- starts walking.
local crossed = { ok = false }
-- Arrival alone is not enough: the generated entry point still needs time to
-- turn toward Ultros and let a nearby rat wander clear before it is safe to
-- bank.  Keep enough clock here for that short settling phase, otherwise the
-- ladder should spend its next seed instead of accepting a technically
-- successful but brittle crossing.
local MIN_CROSS_TIMER = 900
local catwalkBlob = nil                -- captured on the catwalk, below
local function crossAttempt(n, hold)
  local loadReq
  return H.cond(function() return not crossed.ok end, {
    H.call(function()
      H.log(string.format("[rafters] crossing attempt %d of 3, standing still %d frames first",
        n, hold))
    end),
    -- attempts past the first rewind to the tile the walk stepped onto.  The
    -- rewind is gen_vargas's: capture once with H.requestSaveState and reload
    -- the blob in memory, because H.loadState only reaches savestates
    -- compose.py inlined before the run (lib/ot6.lua:293-300).
    H.cond(function() return n > 1 end, {
      H.call(function() loadReq = H.requestLoadState(catwalkBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(loadReq, "attempt " .. n .. ": catwalk reload")
      end),
      H.waitFrames(90),                -- the settle every other reload uses
    }, {}),
    crossRafters(14, 7, 25000, 900, hold, crossed,
      string.format("cross the rafters to Ultros (attempt %d)", n)),
    H.call(function()
      if crossed.ok and H.readWord(0x1189) < MIN_CROSS_TIMER then
        H.log(string.format("[rafters] attempt %d reached Ultros with only %d " ..
          "frames left; reserving the next rat arrangement for a safer entry",
          n, H.readWord(0x1189)))
        crossed.ok = false
      end
      H.log(string.format("[rafters] attempt %d %s at (%d,%d), timer %d left, rats: %s",
        n, crossed.ok and "ARRIVED" or "did not arrive",
        H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
    end),
  })
end

H.run({ maxFrames = 250000 }, {
  H.loadState("build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    -- Boot invariants (the only lines this file can guarantee until
    -- opera_dance_done can be generated).
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    H.assertEq(sw(0x0111), 1, "$0111 SET -- the aria is solved (opera_dance_done)")
    H.assertEq(sw(0x0058), 0, "$0058 CLEAR -- Ultros has not dropped in yet")
    H.assertEq(sw(0x0345), 1, "$0345 SET -- the ENVELOPE (Ultros) is at 238 {99,20}")
    dumpsw("BOOT"); H.screenshot("rafter_boot")
  end),

  -- The opera field menu exposes only LOCKE even though EDGAR and SABIN join
  -- its battles.  Kirin turns his otherwise idle MP into ~200-HP Cures; he
  -- is the designated healer in crossRafters, leaving EDGAR's Tools and
  -- SABIN's Blitzes uninterrupted instead of having all three spend turns
  -- on 50-HP Tonics while the rat pack deals 90-218 damage per round.
  H.equipEsper(0, 0x11, { tag = "KIRIN -> LOCKE for the rafters" }),
  H.call(function()
    H.log(string.format("[prep] esper wear: LOCKE=%02X EDGAR=%02X SABIN=%02X CELES=%02X",
      H.readByte(0x1600 + 37 * 0x01 + 0x1E),
      H.readByte(0x1600 + 37 * 0x04 + 0x1E),
      H.readByte(0x1600 + 37 * 0x05 + 0x1E),
      H.readByte(0x1600 + 37 * 0x06 + 0x1E)))
    H.assertEq(H.readByte(0x1600 + 37 * 0x01 + 0x1E), 0x11,
      "LOCKE wears KIRIN for Cure in the rat fights")
  end),

  -- Step 1: walk into the envelope at {99,20} -> _cabf31 -> $0058=1.
  bumpInto(99, 19, "down", function() return sw(0x0058)==1 or map()~=238 end, 6000,
    "touch the envelope -> $0058"),
  rideScene(function() return H.hasControl() and not H.dialogWaiting() end, 4000,
    "ride Ultros's threat dialog"),
  H.call(function()
    H.assertEq(sw(0x0058), 1, "$0058 SET -- Ultros threatened the opera")
    dumpsw("AFTER-ENVELOPE"); H.screenshot("rafter_ultros_dropped")
  end),
  -- Checkpoint: a cheap replay point for the steps below.
  H.saveState("ultros_dropped.mss"),

  -- Step 2 (measured): 238 stage door -> 237, then the audience-floor step
  -- trigger at {72,30}.  Since $0057=1, _ca5f48 loads map 233 (the active-opera
  -- variant of the theater), whose IMPRESARIO is still _cab724 at {15,46}.
  -- Stand above him at {15,45} and talk; the long 5-minute briefing lands on
  -- map 231 and sets $0110.
  toDoor(100,23,"down",237,"stage -> opera house"),
  H.navTo(72,30,{maxFrames=12000,playBattles=true,arrive=function() return map()==233 end}),
  H.waitUntil(function() return map()==233 and settled() end,3000,"active theater settled",5),
  H.navTo(15,45,{maxFrames=12000,playBattles=true}),
  (function() local n=0 return H.driveUntil(function()
    return sw(0x0110)==1 or H.dialogWaiting()
  end,3000,{H.call(function()
    n=n+1
    H.setPad(n%12<6 and {"down","a"} or {})
  end)},"talk active-opera impresario") end)(),
  rideScene(function() return sw(0x0110)==1 and map()==231 and settled() end,18000,
    "ride the 5-minute briefing"),
  H.call(function()
    H.assertEq(map(),231,"briefing lands in the active theater (231)")
    H.assertEq(sw(0x0110),1,"$0110 SET -- rafter timer armed")
    dumpsw("AFTER-BRIEFING")
  end),
  H.saveState("rafter_briefing.mss"),

  -- Step 3: stage master, far-right switch, then the newly-opened far-left
  -- framework.  The room landings and stairs are Z-split, so the short raw
  -- presses below are measured joins around otherwise ordinary navTo steps.
  H.navTo(28,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"right room",3),
  H.driveUntil(function() return H.fieldY()==35 end,300,{H.hold({"up"})},"leave right landing"),
  H.driveUntil(function() return H.fieldY()==34 end,300,{H.hold({"up"})},"right stair 1"),
  H.driveUntil(function() return H.fieldX()==113 end,300,{H.hold({"left"})},"right stair 2"),
  H.driveUntil(function() return H.fieldY()==32 end,500,{H.hold({"up"})},"right stair 3"),
  H.driveUntil(function() return H.fieldX()==114 end,300,{H.hold({"right"})},"right stair 4"),
  H.driveUntil(function() return H.fieldX()>=117 and H.fieldY()<=29 end,800,{
    H.call(function()
      if H.dialogWaiting() then H.setPad({"a"})
      elseif H.hasControl() then H.setPad({"up","right"})
      else H.setPad({}) end
    end)},"reach stage master"),
  H.driveUntil(function() return sw(0x01B4)==1 end,1000,{
    H.call(function() H.setPad({"right","a"}) end)},"talk stage master"),
  H.navTo(120,28,{maxFrames=1500,playBattles=true}),
  H.driveUntil(function() return sw(0x0355)==0 end,500,{
    H.call(function() H.setPad({"up","a"}) end)},"operate far-right switch"),
  H.navTo(114,37,{maxFrames=3000,playBattles=true,arrive=function() return map()==231 end}),
  H.waitUntil(function() return map()==231 and settled() end,1000,"return theater",3),
  H.navTo(28,27,{maxFrames=500,playBattles=true}),
  H.navTo(4,24,{maxFrames=6000,playBattles=true,arrive=function() return map()==232 end}),
  H.waitUntil(function() return map()==232 and settled() end,1000,"left room",3),
  H.driveUntil(function() return H.fieldY()==13 end,500,{H.hold({"up"})},"leave left landing"),
  H.navTo(117,5,{maxFrames=2500,playBattles=true}),
  -- The five rat gates stay live (see the header).  A rat collision fires
  -- battle 25; crossRafters drives that fight tactically, and a win despawns
  -- the rat and clears its gate.
  H.navTo(117,3,{maxFrames=6000,playBattles=true,arrive=function() return map()==235 end}),
  H.waitUntil(function() return map()==235 and settled() end,1500,"framework",3),
  H.call(function() H.log("[rats] on 235: " .. ratLine()) end),
  H.navTo(6,16,{maxFrames=30000,playBattles=true}),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()<=10 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({up=true}) end) }, "climb framework") end)(),
  (function() local hb=0
    return H.driveUntil(function() return H.fieldY()>=11 end,12000,{
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({down=true}) end) }, "step onto rafters") end)(),

  H.call(function()
    H.log(string.format("[rafters] on the catwalk at (%d,%d), timer %d frames left, rats: %s",
      H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
  end),
  -- The crossing, on a three-attempt ladder.  It is a ladder because the
  -- crossing's cost is dominated by rat fights it cannot avoid or run from,
  -- and how many of them the rats force is luck: measured 2026-08-13 across
  -- four rat arrangements from this same tile, two crossings met two fights
  -- and finished with 5487 and 3424 frames of the chase clock to spare, and
  -- two met four and ran the clock out inside the last few tiles.  A fight
  -- runs about 2500-3400 frames of an 18000-frame timer and the pack cannot
  -- be run from (see battleFrame), so there is no version of this walk that
  -- always fits.  Each attempt reloads this tile and stands still for a
  -- different number of frames first, which leaves the five wandering rats
  -- somewhere else, and the ladder stops at the first attempt that arrives.
  (function() local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "catwalk capture")
        catwalkBlob = req.blob
        H.log(string.format("[rafters] captured the catwalk tile for the ladder (%d bytes)",
          #catwalkBlob))
      end),
    }) end)(),
  crossAttempt(1, 0),
  crossAttempt(2, 233),
  crossAttempt(3, 601),
  H.call(function()
    H.assertEq(crossed.ok, true,
      "the rafters were crossed with safe clock margin within three attempts")
  end),
  -- face Ultros by input: his NPC occupies {15,7}, so a short RIGHT press
  -- is a blocked step that turns the party in place
  H.hold({ "right" }), H.waitFrames(6), H.release(), H.waitFrames(6),
  H.call(function()
    H.assertEq(H.fieldX()==14 and H.fieldY()==7, true,
      "still at (14,7) -- the blocked press did not step")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1,
      "facing RIGHT at Ultros (EVENT_DIR 1), earned by the blocked press")
  end),
  -- the banked state must not boot into a rat collision: wait until no
  -- live rat stands within 4 tiles of the entry point (they wander off; the
  -- timer has headroom for this wait, and the log shows the positions)
  (function() local calm=0
    return H.driveUntil(function()
      calm = (settled() and not ratNear(14,7,4)) and calm+1 or 0
      return calm >= 20
    end, 9000, { H.call(function()
      if H.battleLoadStarted() then H.setPad(H.frame%8<4 and {"a"} or {}); return end
      H.setPad({}) end) }, "a rat-free, settled entry point") end)(),
  H.call(function()
    H.assertEq(map(),235,"Ultros entry point is on rafters map 235")
    H.assertEq(sw(0x02BC),1,"rafter timer is active at the entry point")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing RIGHT")
    -- battle_ultros2 boots this state and taps A into _cabf4b, which is what
    -- stops the timer (event_main.asm:29616-29617).  A few frames is all that
    -- ride needs, but a state banked with the clock nearly out would drop the
    -- weight mid-test, so the floor is asserted here rather than discovered
    -- there.  Measured 2026-08-13 across three rat fields: 3095, 5986 and
    -- 6410 frames left at this point.
    H.assertEq(H.readWord(0x1189) >= 600, true,
      string.format("the rafter timer has room left at the entry point (%d frames)",
        H.readWord(0x1189)))
    -- and nobody is banked hurt: the crossing's rat fights are real fights,
    -- and the blind-A version of this route shipped LOCKE dead at 0/353.
    H.assertPartyStanding("the Ultros entry point")
    H.log("[rats] at generation: " .. ratLine())
    dumpsw("ULTROS2-ENTRY")
  end),
  H.saveState("ultros2_entry.mss"),
  H.logStep(function()
    return string.format("gen_opera6_rafter: catwalk traversal banked the Ultros 2 entry point at f%d", H.frame)
  end),
})
