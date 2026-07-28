-- probe_v07_g2h.lua -- v0.7 leg G->H route recon, part 1 (issue #31).
-- NOT a suite test.  Boots the v07p_world_out.mss waypoint (world (84,34),
-- $0076=1, ship parked at (84,36)) and measures the leg's new idioms:
--   1. re-board the parked ship (walk onto its tile, A = board+liftoff);
--   2. X in flight -> the Blackjack deck (map 6 (16,6)); the interior
--      chain 6 (20,6) -> 7 (40,11) -> (40,18) -> the swap room (50,51+);
--   3. the party-swap drive: chase-talk the wandering TERRA NPC (obj $16,
--      make_npc {58,58} $0477), answer the $0528 "Change party members?"
--      choice with YES (index 1 -- blind A would answer NO), then drive
--      party_menu 1, NO_RESET, {LOCKE, CELES} to TERRA LOCKE EDGAR SABIN
--      (issue #31's cave four; SETZER benched);
--   4. back up to the deck, wheel LEFT+A, fly to the base pass, land
--      (163,194), walk east into map 377, ride the no-soldiers beat,
--      cross to the east door, world pocket, into the cave;
--   5. 382 -> 383 -> the 385 doorstep, where it dumps the timed floor's
--      live BFS picture and stops.
-- Mints v07q_*.mss waypoints for the next iteration round.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end

local function st(tag)
  return H.call(function()
    H.log(string.format(
      "[%s] $1f64=%04X world=(%d,%d) ship=(%d,%d) field=(%d,%d) map=%d",
      tag, H.readWord(0x1f64), H.worldX(), H.worldY(), shipX(), shipY(),
      H.fieldX(), H.fieldY(), map()))
    H.screenshot("v07q_" .. tag)
  end)
end

local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); plan = nil; H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function flyTo(tx, ty)
  local calm, hb = 0, -300
  return H.driveUntil(function()
    local on = shipX() == tx and shipY() == ty
    calm = on and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      if H.frame - hb >= 300 then
        hb = H.frame
        H.log(string.format("[fly] f%d ship=(%d,%d) $c2=%02X",
          H.frame, shipX(), shipY(), H.readByte(0xc2)))
      end
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty))
end

-- chase-talk a wandering NPC object: walk adjacent (re-planned per aligned
-- frame), face it, edge A+dir; plain dialogs advanced with edge-A; STOPS the
-- moment a CHOICE list is up ($056F>=2) so blind A can never answer it.
local function chaseTalk(idx, maxFrames, what)
  local ph = 0
  local DELTA = { up = { 0, -1 }, right = { 1, 0 },
                  down = { 0, 1 }, left = { -1, 0 } }
  return H.driveUntil(function()
    return H.readByte(0x056f) >= 2 and H.dialogWaiting()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local ox, oy = objAt(idx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      -- not adjacent: BFS one step toward any neighbor of the object
      local best
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best = p end
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what)
end

-- drive the current choice dialog to idx and confirm (the zozo3 idiom)
local function choicePick(idxIn, donePred, maxFrames, what)
  local ph = 0
  return H.driveUntil(donePred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if donePred() then H.setPad({}); return end
      local idx = type(idxIn) == "function" and idxIn() or idxIn
      local d3, maxc, cur =
        H.readByte(0x00d3), H.readByte(0x056f), H.readByte(0x056e)
      if maxc >= 2 then
        if cur < idx then H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then H.setPad(ph < 3 and { "up" } or {})
        else H.setPad(ph < 3 and { "a" } or {}) end
      elseif d3 == 1 then
        H.setPad(ph < 3 and { "a" } or {})
      else
        H.setPad({})
      end
    end),
  }, what)
end

-- ------------------------- party menu driver (gen_kefka_won's, verbatim) --
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
local function cursorCell()
  return H.readByte(0x004b) + H.readByte(0x004a) + H.readByte(0x005a)
end
local function decode(cell)
  if cell < 0x10 then
    return { area = "pool", col = cell % 8, row = cell >= 8 and 1 or 0 }
  end
  local b = cell - 0x10
  return { area = "party", col = b >> 1, row = b & 1 }
end
local function stepToward(cur, tgt)
  local c, t = decode(cur), decode(tgt)
  if c.area == "pool" and t.area == "party" then return "down"
  elseif c.area == "party" and t.area == "pool" then return "up"
  elseif c.area == "pool" then
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
  else
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
  end
  return nil
end
local function menuAct(tgtIn, btn, doneState, what)
  local phase, settled = 0, 0
  local function tgt() return type(tgtIn) == "function" and tgtIn() or tgtIn end
  return H.driveUntil(function()
    return mst() == doneState and cursorCell() == tgt() and settled >= 8
  end, 4000, {
    H.call(function()
      phase = (phase + 1) % 10
      if mst() == doneState then
        settled = settled + 1
        H.setPad({})
        return
      end
      settled = 0
      if mst() == 0x69 then H.setPad({}); return end
      local cur = cursorCell()
      if cur ~= tgt() then
        local b = stepToward(cur, tgt())
        if not b then H.setPad({}); return end
        H.setPad(phase < 4 and { [b] = true } or {})
        return
      end
      H.setPad(phase < 4 and { [btn] = true } or {})
    end),
  }, what)
end
-- find the pool cell holding charId at runtime (NO_RESET layouts vary)
local function cellOf(charId)
  for c = 0, 0x13 do
    if cell9d(c) == charId then return c end
  end
  return nil
end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

H.run({ maxFrames = 150000 }, {
  H.loadState("build/states/v07p_world_out.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(H.worldX(), 84, "boot x (Narshe exit spawn)")
    H.assertEq(H.worldY(), 34, "boot y")
    H.assertEq(sw(0x0076), 1, "$0076 SET -- the mission meeting stands")
  end),

  -- 1. walk onto the parked ship (84,36) and board with A
  worldGrind(84, 36, "walk onto the parked ship tile (84,36)"),
  st("on_ship_tile"),
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function() return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0 end,
    600, "liftoff (E0/E2 zeroed in flight)", 5),
  H.waitFrames(240),
  st("airborne"),

  -- 2. X -> the deck; deck door -> interior -> swap room
  H.pressButtons({ "x" }, 8),
  H.waitUntil(landed(6, 20), 1800, "the Blackjack deck (map 6)", 1),
  H.waitFrames(30),
  st("deck"),
  -- the deck door (20,6) sits on the spawn row; a straight held-RIGHT walk
  -- fires it (run 1: navTo(20,7) BFS'd straight through the door tile)
  pressWalk("right", function() return map() == 7 end, 900,
    "held RIGHT along row 6 -> deck door (20,6) -> map 7"),
  H.waitUntil(landed(7, 10), 1200, "map 7 landing", 1),
  H.call(function()
    H.log(string.format("[map7] at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.navTo(40, 17, { maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldY() >= 45 and H.tileAligned()
  end, 900, "stairs (40,18) -> the swap room (50,51)"),
  H.waitFrames(45),
  st("swap_room"),
  H.call(function()
    for i = 0x10, 0x22 do
      local x, y = objAt(i)
      if x > 0 or y > 0 then
        H.log(string.format("[obj %02X] at (%d,%d)", i, x, y))
      end
    end
  end),

  -- 3. chase-talk TERRA (obj $16), YES on $0528, drive the party menu
  chaseTalk(0x16, 9000, "chase-talk the TERRA NPC"),
  H.call(function()
    H.log(string.format("[choice] $056E=%d $056F=%d",
      H.readByte(0x056e), H.readByte(0x056f)))
    H.screenshot("v07q_choice")
  end),
  choicePick(1, function()
    return menuUp() and mst() == 0x2d and H.readByte(0x0200) == 4
  end, 3000, "YES -> the party menu"),
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu at $2d", 5),
  H.waitFrames(20),
  H.call(function()
    local pool = {}
    for c = 0, 0x13 do pool[#pool + 1] = string.format("%02X", cell9d(c)) end
    H.log("[assign] cells 0..13: " .. table.concat(pool, " "))
  end),
  -- dynamic assigns: TERRA, EDGAR, SABIN into party cells; LOCKE should
  -- already be there (NO_RESET pre-fill).  Cells logged above; the drive
  -- below reads them fresh.
  (function()
    local steps = {}
    -- run 2 measured: party_menu 1, NO_RESET, {LOCKE, CELES} opens with ALL
    -- FOUR party cells EMPTY (pool 00 01 02 04 05 09 0B -- TERRA LOCKE CYAN
    -- EDGAR SABIN SETZER GAU); the {LOCKE, CELES} list pre-fills nothing.
    local wanted = { { 0x00, "TERRA" }, { 0x01, "LOCKE" },
                     { 0x04, "EDGAR" }, { 0x05, "SABIN" } }
    for _, w in ipairs(wanted) do
      local charId, name = w[1], w[2]
      local src, dst
      steps[#steps + 1] = H.waitUntil(function() return mst() == 0x2d end, 900,
        name .. ": menu ready", 5)
      steps[#steps + 1] = H.call(function()
        src = cellOf(charId)
        assert(src and src < 0x10, name .. " not in the pool")
        dst = nil
        for c = 0x10, 0x13 do
          if cell9d(c) == 0xFF then dst = c; break end
        end
        assert(dst, "no empty party cell for " .. name)
        H.log(string.format("[assign] %s: pool %d -> party $%02X", name, src, dst))
      end)
      steps[#steps + 1] = menuAct(function() return src end, "a", 0x2e,
        name .. ": pick")
      steps[#steps + 1] = menuAct(function() return dst end, "a", 0x2d,
        name .. ": drop")
      steps[#steps + 1] = H.call(function()
        H.assertEq(cell9d(dst), charId, name .. " in the party cell")
      end)
    end
    return H.seqStep(steps)
  end)(),
  H.waitUntil(function() return mst() == 0x2d end, 600, "menu at $2d for commit", 5),
  H.pressButtons({ "start" }, 6),
  H.waitUntil(function() return not menuUp() end, 1200, "menu closed", 5),
  H.waitUntil(landed(7, 20), 3000, "back on map 7 after update_party", 1),
  H.call(function()
    H.log(string.format("[swapped] at (%d,%d) party: TERRA=%d LOCKE=%d "
      .. "EDGAR=%d SABIN=%d SETZER=%d CELES=%d", H.fieldX(), H.fieldY(),
      partyOf(0x00), partyOf(0x01), partyOf(0x04), partyOf(0x05),
      partyOf(0x09), partyOf(0x06)))
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    H.assertEq(partyOf(0x02), 0, "CYAN benched")
    H.assertEq(partyOf(0x0B), 0, "GAU benched")
    H.assertEq(partyOf(0x04), 1, "EDGAR in party 1")
    H.assertEq(partyOf(0x05), 1, "SABIN in party 1")
    H.assertEq(partyOf(0x09), 0, "SETZER benched")
    H.screenshot("v07q_swapped")
  end),
  H.saveState("v07q_swapped.mss"),

  -- 4. back to the deck and the wheel; fly to the base pass.  The commit
  -- reloads map 7 at (40,16) (measured run 2 -- the $0246 branch reads
  -- BACKWARD from the source: the live chain takes the {40,16} load), one
  -- step below the (40,10) door corridor.
  H.navTo(40, 11, { maxFrames = 6000 }),
  pressWalk("up", function() return map() == 6 end, 900,
    "door (40,10) -> the deck"),
  H.waitUntil(landed(6, 10), 1200, "deck again", 1),
  H.navTo(14, 6, { maxFrames = 6000, calmFrames = 8 }),
  -- THE WHEEL NOW ASKS.  _caf532 (event_main.asm:36118) is facing-LEFT+A
  -- gated ($01B3/$01B4); on the FIRST takeoff ($0170=0) it lifts off
  -- silently -- which is why gen_terra_returned_anchor's bare LEFT+A hold
  -- worked -- but that takeoff SET $0170, so from here on it opens
  -- dlg $052A "0: (Lift-off) / 1: (Not just yet)" (_caf56e, :36145) and a
  -- held A only yields the one edge that opens it.  Measured run 3: the
  -- bare hold timed out with the choice list on screen.
  (function() local ph = 0
    return H.driveUntil(function()
      return H.readByte(0x056f) >= 2 or H.worldMode()
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a", "left" } or { left = true })
      end),
    }, "LEFT+A on the wheel -> the lift-off choice")
  end)(),
  H.call(function()
    H.log(string.format("[wheel] $056E=%d $056F=%d worldMode=%s",
      H.readByte(0x056e), H.readByte(0x056f), tostring(H.worldMode())))
  end),
  -- 2 choices = dlg $052A (Lift-off at 0); 3 = dlg $0527 (Lift-off at 1,
  -- the post-Floating-Continent form, $009E -- not this chain, but cheap)
  choicePick(function() return H.readByte(0x056f) >= 3 and 1 or 0 end,
    function() return H.worldMode() end, 3000, "(Lift-off)"),
  H.release(),
  H.waitFrames(150),
  flyTo(163, 194),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(0xc2) & 0x02, 0, "(163,194) landable under the ship")
  end),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
    1200, "grounded at the base pass", 10),
  H.waitFrames(120),
  st("base_grounded"),
  H.saveState("v07q_base_land.mss"),

  -- 5. disembark EAST and walk into the base
  (function() local ph = 0
    return H.driveUntil(function()
      return H.worldX() == 164 and H.worldY() == 194 and H.worldAligned()
    end, 1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ right = true }) end),
    }, "step off RIGHT to (164,194)")
  end)(),
  H.release(), H.waitFrames(30),
  pressWalk("right", function() return not H.worldMode() and map() == 377 end,
    900, "(165,194) -> IMPERIAL BASE (377)"),
  H.waitUntil(landed(377, 10), 2400, "base landing", 1),
  st("base_in"),
  -- THE ENTRANCE TRIGGER ROW IS A RE-ENTRY TRAP.  (6,16)/(7,17)/(6,18) all
  -- run _cb25d6 (event_trigger.asm:1806-1809), which on this state reaches
  -- _cb2a5b (event_main.asm:44575) -- the "That's odd… No Imperial
  -- soldiers…" beat, $0172-latched -- and then EventReturns on every later
  -- frame the party STANDS on a trigger tile.  Measured run 4: the party
  -- ended the scene ON (6,16) and hasControl() never held again, so navTo
  -- BFS'd zero steps for 20000 frames.  Same class as the save-tile and
  -- BIG_SWITCH traps: leave the tile with an UNCONDITIONAL held press.
  --
  -- NOTE for the recon (§1 leg 2): _cb25d6's FIRST `if_switch $01A0=1`
  -- (:44009) is NOT "Terra in the party" -- _cac5c1 (:30515-30588) is a
  -- party-COUNT encoder that rewrites $01A0-$01A3 to (count-1) in the
  -- PARTY_CHARS case, so :44009 means "party of ONE" and routes to the
  -- solo-Terra bounce _cb2606.  The Terra gate is the SECOND read, after
  -- :44010's `set_case PARTY_CHARS` restores the per-character case.
  -- The landing tile (6,17) is NOT a trigger (measured run b1: 20000 idle
  -- frames with control held and $0172 clear); the triggers are the three
  -- tiles AROUND it.  One held RIGHT steps onto (7,17) and fires the beat.
  pressWalk("right", function() return sw(0x0172) == 1 end, 20000,
    "held RIGHT onto (7,17) -> the no-soldiers beat -> $0172"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[base scene] $0172=%d at (%d,%d)",
      sw(0x0172), H.fieldX(), H.fieldY()))
  end),
  pressWalk("right", function()
    return H.fieldX() >= 9 and H.tileAligned() and H.hasControl()
  end, 2400, "held RIGHT off the entrance trigger row"),
  H.waitFrames(45),
  H.navTo(30, 12, { maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  H.call(function()
    H.log(string.format("[base] crossed to (%d,%d); $0172=%d",
      H.fieldX(), H.fieldY(), sw(0x0172)))
  end),
  pressWalk("right", function() return H.worldMode() end, 900,
    "east door (31,12) -> world (167,194)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 2400, "world pocket", 5),
  st("pocket"),
  H.saveState("v07q_pocket.mss"),

  -- 6. into the cave: (169,194) -> 382 -> 383 -> the 385 doorstep
  worldGrind(168, 194, "pocket walk -> (168,194)"),
  pressWalk("right", function() return not H.worldMode() and map() == 382 end,
    900, "(169,194) -> CAVE TO THE SEALED GATE (382)"),
  H.waitUntil(landed(382, 10), 2400, "382 landing", 1),
  st("cave382"),
  H.navTo(31, 42, { maxFrames = 15000,
    arrive = function() return map() == 383 end }),
  pressWalk("down", function() return map() == 383 end, 900,
    "door (31,43) -> BASEMENT 1 (383)"),
  H.waitUntil(landed(383, 10), 2400, "383 landing", 1),
  st("cave383"),
  H.navTo(53, 57, { maxFrames = 20000,
    arrive = function() return map() == 385 end }),
  pressWalk("down", function() return map() == 385 end, 900,
    "door (53,58) -> BASEMENT 2 (385), the timed floor"),
  H.waitUntil(landed(385, 10), 2400, "385 landing", 1),
  st("cave385"),
  H.saveState("v07q_385_entry.mss"),

  -- 7. the timed floor's live picture: BFS from the entry to the exit door
  H.call(function()
    H.log(string.format("[385] at (%d,%d) $01F0=%d $01F1=%d $01F5=%d $01F6=%d",
      H.fieldX(), H.fieldY(), sw(0x01F0), sw(0x01F1), sw(0x01F5), sw(0x01F6)))
    local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
      left = { -1, 0 }, upright = { 1, -1 }, downright = { 1, 1 },
      downleft = { -1, 1 }, upleft = { -1, -1 } }
    local plan = H.bfsPath(13, 13)
    if not plan then
      H.log("[385] NO PATH (1,2)->(13,13) in the unarmed state")
    else
      local x, y = H.fieldX(), H.fieldY()
      local tiles = { string.format("(%d,%d)", x, y) }
      for _, mv in ipairs(plan) do
        local d = DELTA[mv]
        x, y = x + d[1], y + d[2]
        tiles[#tiles + 1] = string.format("(%d,%d)", x, y)
      end
      H.log("[385] unarmed BFS path: " .. table.concat(tiles, " "))
    end
    -- per-tile walkability rows for the whole room (live tilemap)
    for y = 0, 15 do
      local row = {}
      for x = 0, 16 do
        local p1 = H.readByte(0x7E7600 + H.maptile(x, y))
        row[#row + 1] = string.format("%02X", p1)
      end
      H.log(string.format("[385 p1 y=%02d] %s", y, table.concat(row, " ")))
    end
  end),
  H.logStep(function()
    return string.format("G->H part-1 probe complete at frame %d", H.frame)
  end),
})
