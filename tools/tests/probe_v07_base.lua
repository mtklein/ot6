-- probe_v07_base.lua -- v0.7 leg G->H route recon, part 2 (issue #31).
-- NOT a suite test.  The RESUME half of probe_v07_g2h.lua: it boots that
-- probe's v07q_base_land.mss waypoint (the Blackjack grounded at world
-- (163,194) with the cave party TERRA LOCKE EDGAR SABIN already seated) so
-- the base/cave stretch can be iterated without replaying the swap-room
-- drive and the two flights every time.  It measures:
--   1. disembark east, world (165,194) -> IMPERIAL BASE (map 377) at (6,17);
--   2. the entrance trigger row and the "No Imperial soldiers…" beat
--      (_cb2a5b, $0172) -- including the re-entry trap that leaves the
--      party without control while it stands on a trigger tile;
--   3. the base crossing to the east door 377 (31,12) -> world (167,194);
--   4. the pocket -> (169,194) -> 382 -> 383 -> BASEMENT 2 (map 385);
--   5. the timed floor's live tile-prop and reachability picture at the
--      entry tile, where the leg currently stops.
-- Mints v07q_pocket.mss and v07q_385_entry.mss.
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

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/v07q_base_land.mss.lua"),
  H.waitFrames(150),
  st("boot"),

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
