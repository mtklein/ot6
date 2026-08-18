-- @manual probe: the voyage's back half, booted from the night-window
-- scratch state the first gen_voyage run cut (albrook_night_scratch.mss:
-- control on the port map 332, $0084/$0085 set, night unslept).  Exists so
-- the inn leg and the ship legs can be iterated at ~4 minutes a try instead
-- of replaying the 8-minute front half; gen_voyage is the product, this is
-- the instrument.  Route and helpers are gen_voyage.lua's, verbatim.
--
-- The scratch is NOT a fixture and does not live in build/states (the
-- audits ask for undeclared files there to be deleted).  To run this probe,
-- put a copy there first: gen_voyage emits albrook_night_scratch.mss on
-- every run, so either copy it out of a retained gen_voyage workspace
-- (build/test-runs/crescent_landing.*/artifacts/) or run gen_voyage by hand
-- through tools/tests/run.sh, whose unfiltered publish includes it.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/albrook_night_scratch.mss.lua"

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function partyCount()
  local n = 0
  for c = 0, 15 do if partyOf(c) ~= 0 then n = n + 1 end end
  return n
end

-- Verified-step world grinder (gen_banquet_done's, unchanged; consumes a
-- plan entry only when the party lands on it).  An encounter on the grind
-- is fled with the real L+R run, which is the design for world encounters
-- (issue #75); this terrain's packs fled clean across gen_banquet_done's
-- much longer I->J grind.
local function worldGrind(tx, ty, what)
  local plan, idx, ph, hb = nil, 1, 0, -600
  local step = nil
  local DW = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        plan = nil; step = nil
        H.setPad({ l = true, r = true }); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then
        plan = nil; step = nil; H.setPad({}); return
      end
      if not H.worldAligned() then return end   -- hold through the glide
      local x, y = H.worldX(), H.worldY()
      if step then
        if x == step.tx and y == step.ty then
          step = nil; idx = idx + 1               -- landed: next entry
        elseif x ~= step.fx or y ~= step.fy then
          plan = nil; step = nil                  -- drifted: replan
        else
          step.held = step.held + 1
          if step.held > 90 then                  -- press provably dead
            plan = nil; step = nil; H.setPad({}); return
          end
          H.setPad({ [step.dir] = true }); return
        end
      end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[grind] NO PATH (%d,%d)->(%d,%d) f%d",
              x, y, tx, ty, H.frame))
          end
          H.setPad({}); return
        end
      end
      local dir = plan[idx]
      local d = DW[dir]
      step = { dir = dir, fx = x, fy = y,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, held = 0 }
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- unconditional held walk (dialogs absorbed; a battle, none of which can
-- roll on these maps, is fled with the real L+R run)
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

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- edge-A through dialogs until settled
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

-- Passive scene rider: pages dialogs with A, commits a naming menu with
-- START ($59 ~= 0 is the menu-up flag; name_menu suspends the field module,
-- gen_edgar's commitName finding), and otherwise waits for `done`.  Used
-- for every scripted stretch between talks: the sails, the deck scenes,
-- and the landing tail.
local function rideScene(done, maxFrames, what)
  local ph = 0
  return H.driveUntil(done, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.worldMode() then H.setPad({}); return end  -- scripted sail: hands off
      if H.readByte(0x59) ~= 0 then
        H.setPad(ph < 4 and { "start" } or {}); return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end  -- no choice
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- Walk to a character/NPC object's open neighbour, edge-A to talk, then
-- ride the scene it opens (dialog paging + naming-menu START) until `done`.
-- H.chaseTalk's chassis with the rideScene branches folded in; the voyage's
-- scenes carry no choices (read end to end, :68091-69190), so a choice
-- window parks the pad and the step times out loudly rather than picking
-- something silently.  When no adjacent tile is reachable the rider falls
-- back to counter talk (gen_kolts's item-shop idiom): stand two tiles away
-- in line, face the NPC, and tap A -- CheckNPCs reaches through the one
-- impassable counter tile (ff6/src/field/player.asm:188-200).  The Albrook
-- innkeeper is that class of NPC.
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function talkRide(objIdx, done, maxFrames, what)
  local ph = 0
  local function objAt(idx)
    local off = 0x29 * idx
    return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
  end
  return H.driveUntil(done, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.worldMode() then H.setPad({}); return end  -- scripted sail: hands off
      if H.readByte(0x59) ~= 0 then
        H.setPad(ph < 4 and { "start" } or {}); return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
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
      local best
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best = p end
      end
      if not best then
        -- counter talk: no adjacent tile reachable
        if (dx == 0 and math.abs(dy) == 2) or (dy == 0 and math.abs(dx) == 2) then
          local dir = (dx == 2 and "right") or (dx == -2 and "left")
                   or (dy == 2 and "down") or "up"
          if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE[dir] then
            H.setPad({ [dir] = true }); return
          end
          H.setPad(ph < 4 and { "a" } or {}); return
        end
        for _, c in ipairs({ { ox, oy + 2 }, { ox - 2, oy },
                             { ox + 2, oy }, { ox, oy - 2 } }) do
          local p = H.bfsPath(c[1], c[2])
          if p and (not best or #p < #best) then best = p end
        end
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what)
end


-- --------------------------------------------------------------------------
local steps = {
  H.loadState(STATE),
  H.waitFrames(60),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 1800, "control on the port map (scratch boot)", 5),
  H.call(function()
    H.assertEq(map(), 332, "scratch boots on the port map")
    H.assertEq(sw(0x0085), 1, "the night window is live")
    H.assertEq(sw(0x0087), 0, "the night is unslept")
  end),

  -- out of the port, through the gate, to the inn (the bump door)
  H.navTo(22, 1, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return map() == 323 end }),
  H.waitUntil(landed(323, 10), 2400, "back in Albrook at the gate", 1),
  H.navTo(43, 27, { maxFrames = 6000, playBattles = "flee" }),
  pressWalk("up", function()
    return H.fieldY() <= 24 and H.tileAligned()
  end, 900, "held UP through the gate row into town"),
  H.release(),
  H.waitFrames(30),
  H.navTo(54, 13, { maxFrames = 20000, playBattles = "flee" }),
  H.driveUntil(function() return map() == 325 end, 1200, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "bump the inn door (54,12) -> 325"),
  H.release(),
  H.waitUntil(landed(325, 10), 2400, "the inn", 1),
  H.call(function()
    H.log(string.format("[probe] inn arrival (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  talkRide(0x10, function() return sw(0x0087) == 1 end, 40000,
    "the innkeeper -> the free night -> $0087"),
  settle(6000, "night scene tail settles"),
  H.waitUntil(landed(325, 10), 3000, "morning in the lodging", 1),
  H.call(function()
    H.assertEq(sw(0x0087), 1, "$0087 -- the night was slept")
    H.log(string.format("[probe] morning at 325 (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.navTo(58, 57, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return map() == 323 end }),
  H.waitUntil(landed(323, 10), 2400, "out of the inn", 1),
  H.call(function()
    H.assertEq(H.fieldX(), 54, "inn exit lands (54,14)")
    H.assertEq(H.fieldY(), 14, "inn exit y")
  end),

  -- back to the pier; the voyage
  H.navTo(43, 25, { maxFrames = 20000, playBattles = "flee" }),
  pressWalk("down", function() return map() == 332 end, 1200,
    "held DOWN through the gate -> the port again"),
  H.waitUntil(landed(332, 10), 2400, "the port, morning", 1),
  talkRide(0x13, function() return sw(0x0083) == 1 end, 20000,
    "LEO -> 'Right...let's go' ($0083)"),
  rideScene(function()
    return map() == 332 and not H.worldMode() and partyCount() == 1
       and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and bright() >= 15
  end, 40000, "sail 1 + deck scenes -> TERRA alone on the night deck"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(partyCount(), 1, "TERRA alone for the night watch")
  end),
  talkRide(0x21, function() return sw(0x0086) == 1 end, 60000,
    "LEO at (8,13) -> the night talk, the Shadow scene, sail 2 ($0086)"),
  rideScene(landed(332, 10), 12000, "day deck control"),
  H.waitFrames(30),
  talkRide(0x22, function() return sw(0x0089) == 1 end, 12000,
    "LEO at (12,14) -> the split briefing ($0089)"),
  settle(3000, "briefing settles"),
  talkRide(0x1D, function()
    return H.worldMode() and H.worldX() == 232 and H.worldY() == 150
       and H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 60000, "LOCKE at (10,14) -> the landing at world (232,150)"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(partyCount(), 3, "party COUNT is three")
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    H.assertEq(partyOf(0x03), 1, "SHADOW in party 1")
    H.assertEq(sw(0x02F3), 1, "SHADOW available")
    H.assertEq(sw(0x02FB), 1, "GAU still available (no refusal on this chain)")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT at the landing")
    H.log(string.format(
      "[probe] LANDED at (%d,%d): $0083=%d $0086=%d $0089=%d $02FB=%d",
      H.worldX(), H.worldY(), sw(0x0083), sw(0x0086), sw(0x0089), sw(0x02FB)))
    H.screenshot("probe_voyage_landing")
  end),
  H.logStep(function()
    return string.format(
      "probe: the voyage back half played scratch -> landing at frame %d",
      H.frame)
  end),
}

local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 200000 }, flat)
