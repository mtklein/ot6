-- probe_water_rondo.lua -- take MOG down the Serpent Trench and learn
-- Water Rondo (#133 item 4).
--
-- Boots from wob_mog_done.mss (Mog just recruited on the Narshe cliff).
-- Route: walk the cliff chain back down (23 -> 22 -> 21 -> town), out to
-- the world, board the ship at the Narshe doorstep, fly to Crescent
-- Mountain (world door (214,148), approach column (214,149..152), land
-- on the west plain), enter 167 -> door (25,26) -> cave 168, step the
-- dive trigger (8,11) ("Jump? (Why not?)" -- the post-scenario $0041 arm,
-- A-only ride per the choice-menu lesson), then ride the trench: battles
-- fought tactically; Mog aboard learns the water-terrain dance when he
-- wins there.  Ends at Nikeah; saves wob_rondo_done.mss.
--
-- If the join left Mog OUT of the active party, the deck party-change
-- would be needed first; the probe asserts his party byte early so that
-- shows up as a loud clear failure rather than a silent no-learn.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function dances() return H.readByte(0x1D4C) end

local CAND = { {210,148},{209,148},{210,147},{211,148},{208,149},{209,150},{207,148} }
local DIRS = { "up", "down", "left", "right" }
local cal = {}
local mode = "calib"
local calI, calT, calX, calY = 1, 0, 0, 0
local rhyT, candI, landed = 0, 1, false
local function target()
  local c = CAND[candI]
  return c[1] * 4096 + 2048, c[2] * 4096 + 2048
end
local function bestDir(ex, ey)
  local best, bestDot = nil, 0
  for _, d in ipairs(DIRS) do
    local v = cal[d]
    if v then
      local dot = v.x * ex + v.y * ey
      if dot > bestDot then best, bestDot = d, dot end
    end
  end
  return best
end
local function flyFrame()
  if mode == "calib" then
    local d = DIRS[calI]
    if calT == 0 then calX, calY = fineX(), fineY() end
    calT = calT + 1
    if calT <= 30 then H.setPad({ y = true, [d] = true }); return end
    if calT <= 45 then H.setPad({}); return end
    cal[d] = { x = (fineX() - calX) / 30, y = (fineY() - calY) / 30 }
    calI, calT = calI + 1, 0
    if calI > #DIRS then mode = "travel" end
    return
  end
  if mode == "travel" then
    local wx, wy = target()
    local ex, ey = wx - fineX(), wy - fineY()
    if math.abs(ex) < 4096 and math.abs(ey) < 4096 then
      mode, rhyT = "rhythm", 0
      H.setPad({})
      return
    end
    local d = bestDir(ex, ey)
    if not d then error("no usable strafe direction") end
    H.setPad({ y = true, [d] = true })
    return
  end
  if mode == "rhythm" then
    rhyT = rhyT + 1
    if rhyT <= 10 then
      local wx, wy = target()
      local d = bestDir(wx - fineX(), wy - fineY())
      H.setPad(d and { y = true, [d] = true } or {})
      return
    end
    if rhyT <= 22 then H.setPad({}); return end
    if rhyT <= 28 then H.setPad({ b = true }); return end
    H.setPad({})
    if rd(0x20) ~= 1 and H.worldHasControl() then landed = true; return end
    if rhyT - 28 >= 480 then
      candI = candI + 1
      if candI > #CAND then error("every landing candidate bounced") end
      mode = "travel"
    end
    return
  end
end
local function edgeRow(x, y, dir, destMap, tag)
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 1200,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(60),
  }
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
local d0 = nil
local tactical = H.newFightDriver("rondo", { tactical = true, boost = true,
  items = true, healPercent = 55 })

H.run({ maxFrames = 120000 }, flatten({
  H.loadState("build/states/wob_mog_done.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    d0 = dances()
    H.log(string.format("boot: dances=%02X mog-party=%d $2FA=%d map=%d (%d,%d)",
      d0, H.readByte(0x1850 + 10) & 0x07, sw(0x2FA),
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
    H.assertEq(sw(0x2FA) == 1, true, "MOG is recruited (cliff join done)")
  end),
  -- down the cliffs: 23 -> 22 -> 21 -> town -> world.  bfs mismodels
  -- map 23 right after the join scene (the party reads as a 1-tile
  -- island at (10,17)), so the first hop is a blind waypoint walk along
  -- the known corridor, no pathfinder involved.
  (function()
    local wps = { {10,18},{12,18},{13,19},{13,20},{24,20},{25,21},{25,31},{25,33} }
    local wi, t, wt = 1, 0, 0
    return H.driveUntil(function() return mapIs(22) end, 12000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        local wp = wps[wi]
        if not wp then H.setPad({ down = true }); return end
        local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
        wt = wt + 1
        if (dx == 0 and dy == 0) or wt > 900 then
          wi, wt = wi + 1, 0
          H.setPad({})
          return
        end
        local d = math.abs(dx) >= math.abs(dy)
          and (dx > 0 and "right" or "left")
          or (dy > 0 and "down" or "up")
        H.setPad({ [d] = true })
      end),
    }, "blind descent 23 -> 22")
  end)(),
  H.waitFrames(60),
  -- 22 -> 21 top-right.  A nudge first: the party's z is stale right
  -- after a teleport and bfs reads the map as a tiny island until one
  -- real step normalizes it.
  (function()
    local function nudge(dir, n)
      return { H.hold({ dir }), H.waitFrames(n or 250), H.release(),
               H.waitFrames(20) }
    end
    local function doorHop(x, y, avoid, destPred, dir, tag)
      local t = 0
      return {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "flee",
          arrive = destPred, avoid = avoid }),
        H.driveUntil(destPred, 2000, {
          H.call(function()
            t = t + 1
            if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {})
            else H.setPad({ [dir] = true }) end
          end),
        }, tag),
        H.waitFrames(50),
        H.call(function()
          H.log(string.format("[%s] map %d (%d,%d)", tag, H.mapId() & 0x1ff,
            H.fieldX(), H.fieldY()))
        end),
      }
    end
    -- the descent retraces the mine chain: 21's top-right component has
    -- no walk link to town (tile-prop verified), so back through 41/43.
    return flatten({
      nudge("down"),
      doorHop(16, 40, nil, function() return mapIs(21) end, "down", "22 -> 21 top"),
      nudge("down"),
      doorHop(31, 10, nil, function() return mapIs(41) end, "up",
        "21 -> 41 corridor"),
      nudge("left"),
      doorHop(107, 12, { {117,12} }, function() return mapIs(21) end, "up",
        "corridor -> 21 ledge side"),
      nudge("down"),
      doorHop(37, 25, { {24,10} }, function() return mapIs(41) end, "down",
        "21 ledge -> 41 west"),
      nudge("down"),
      doorHop(25, 59, { {18,51} },
        function() return mapIs(41) and H.fieldX() > 50 end, "down",
        "41 west -> shaft"),
      nudge("down"),
      doorHop(57, 11, { {57,21} }, function() return mapIs(43) end, "up",
        "shaft -> 43"),
      -- 43: west off the ledge back to the entry column, then down it
      H.hold({ "left" }), H.waitFrames(1200), H.release(), H.waitFrames(30),
      nudge("down"),
      doorHop(108, 59, nil, function() return mapIs(21) end, "down",
        "43 -> 21 chase"),
      nudge("down"),
      doorHop(24, 52, nil, function() return mapIs(20) end, "down",
        "21 -> town"),
    })
  end)(),
  H.navTo(38, 61, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "out to the world"),
  H.waitFrames(60),
  -- board and fly to Crescent Mountain
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard"),
  H.waitFrames(150),
  -- ============ deck party-change: bench Relm, seat MOG ============
  -- X in flight opens the deck (map 6); door (20,6) -> interior (map 7,
  -- (40,11)) where map-init _caf47c stands the reserve roster up.  Talk
  -- to a roster NPC -> char line -> "Change party members?" (0 No/1 Yes,
  -- so down-then-A) -> the swap UI ($26 in 2c..2f, probe_iaf's decode).
  H.driveUntil(function() return not H.worldMode() and (H.mapId() & 0x1ff) == 6 end,
    1500, { H.call(function() H.setPad(H.frame % 12 < 3 and { x = true } or {}) end) },
    "deck via X"),
  H.waitFrames(90),
  H.navTo(20, 6, { maxFrames = 4000,
    arrive = function() return mapIs(7) end }),
  H.driveUntil(function() return mapIs(7) end, 900,
    { H.call(function() H.setPad({ up = true }) end) }, "into the interior"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("interior at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("interior")
  end),
  (function()
    local function menuState() local s = H.readByte(0x26); return s >= 0x2c and s <= 0x2f end
    local function idx() return H.readByte(0x4b) + H.readByte(0x4a) + H.readByte(0x5a) end
    local function charAt(i) return rd(0x7e9d89 + i) end
    local function mogSeated() return (H.readByte(0x1850 + 10) & 0x07) ~= 0 end
    local function firstEmptyGroupSlot()
      for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
        if charAt(i) == 0xFF then return i end
      end
      return nil
    end
    local function relmGroupSlot()
      for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
        if charAt(i) == 8 then return i end
      end
      return nil
    end
    local phase = 0
    local function tap(btn) phase = (phase + 1) % 9
      H.setPad(phase < 3 and { [btn] = true } or {}) end
    local function tapB(btn) phase = (phase + 1) % 9
      H.setPad(phase < 3 and { btn } or {}) end
    local t, scanDir, scanT = 0, "right", 0
    local held = nil                        -- who the cursor is carrying
    -- the talk spots: near the interior spawn; face-press A around the
    -- room, riding whatever answers
    local spots = { {40,12,"down"},{39,11,"left"},{41,11,"right"},{40,11,"up"},
                    {38,12,"left"},{42,12,"right"},{40,14,"down"},{37,11,"up"},
                    {43,11,"up"},{40,16,"down"} }
    local si = 1
    local walker = nil
    return H.driveUntil(function()
      return mogSeated() and not menuState() and H.hasControl()
        and not H.dialogWaiting()
    end, 20000, {
      H.call(function()
        t = t + 1
        if menuState() then
          walker = nil
          local s = H.readByte(0x26)
          if s == 0x2d then                       -- browsing
            if relmGroupSlot() then               -- 1: grab Relm
              if H.readByte(0x4a) ~= 0x10 then tap("down")
              else
                local tgt = relmGroupSlot()
                local cc, cr = (idx() >> 1) & 1, idx() & 1
                local tc, tr = (tgt >> 1) & 1, tgt & 1
                if cc < tc then tap("right") elseif cc > tc then tap("left")
                elseif cr < tr then tap("down") elseif cr > tr then tap("up")
                else held = "relm"; tapB("a") end
              end
            elseif firstEmptyGroupSlot() then     -- 3: grab Mog in reserve
              if H.readByte(0x4a) ~= 0 then tap("up")
              elseif charAt(idx()) ~= 0x0A then
                scanT = scanT + 1
                if scanT > 360 then scanDir = scanDir == "right" and "left" or "right"; scanT = 0 end
                tap(scanDir)
              else held = "mog"; tapB("a") end
            else                                  -- 5: full group -> confirm
              tapB("start")
            end
          elseif s == 0x2e then                   -- holding someone
            if held == "relm" then                -- 2: drop her in reserve
              if H.readByte(0x4a) ~= 0 then tap("up")
              elseif charAt(idx()) ~= 0xFF then
                scanT = scanT + 1
                if scanT > 360 then scanDir = scanDir == "right" and "left" or "right"; scanT = 0 end
                tap(scanDir)
              else tapB("a") end
            else                                  -- 4: place Mog in the group
              if H.readByte(0x4a) ~= 0x10 then tap("down")
              else
                local tgt = firstEmptyGroupSlot()
                if not tgt then tapB("b")
                else
                  local cc, cr = (idx() >> 1) & 1, idx() & 1
                  local tc, tr = (tgt >> 1) & 1, tgt & 1
                  if cc < tc then tap("right") elseif cc > tc then tap("left")
                  elseif cr < tr then tap("down") elseif cr > tr then tap("up")
                  else tapB("a") end
                end
              end
            end
          else tapB("b") end
          return
        end
        if H.dialogWaiting() then
          walker = nil
          -- choice-bearing dialogs put the cursor on row 0 ("No"); one
          -- down edge then A edges picks "Yes" (harmless on plain text)
          local ph = t % 32
          if ph < 3 then H.setPad({ down = true })
          elseif ph >= 8 and ph < 11 then H.setPad({ "a" })
          else H.setPad({}) end
          return
        end
        if not H.hasControl() then H.setPad({}); return end
        -- walking: face-press A at the next talk spot
        if walker == nil then
          local s = spots[si]
          si = si % #spots + 1
          walker = { x = s[1], y = s[2], dir = s[3], stage = 0, st = 0 }
        end
        local w = walker
        w.st = w.st + 1
        if w.stage == 0 then
          local dx, dy = w.x - H.fieldX(), w.y - H.fieldY()
          if dx == 0 and dy == 0 then w.stage = 1; w.st = 0
          elseif w.st > 600 then walker = nil
          else
            local d = math.abs(dx) > math.abs(dy)
              and (dx > 0 and "right" or "left")
              or (dy > 0 and "down" or "up")
            H.setPad({ [d] = true })
          end
        else
          if w.st < 3 then H.setPad({ [w.dir] = true })
          elseif w.st < 12 then H.setPad({})
          elseif w.st < 16 then H.setPad({ "a" })
          elseif w.st < 60 then H.setPad({})
          else walker = nil end
        end
      end),
    }, "MOG seated via the deck party-change")
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("party bytes: mog=%02X relm=%02X",
      H.readByte(0x1850 + 10), H.readByte(0x1850 + 8)))
    H.screenshot("party_changed")
  end),
  -- back to the deck and the wheel: Lift-off
  H.navTo(40, 10, { maxFrames = 4000,
    arrive = function() return mapIs(6) end }),
  H.driveUntil(function() return mapIs(6) end, 900,
    { H.call(function() H.setPad({ up = true }) end) }, "back on deck"),
  H.waitFrames(60),
  H.navTo(15, 8, { maxFrames = 2000,
    arrive = function() return H.dialogWaiting() end }),
  (function()
    local t = 0
    return H.driveUntil(function() return rd(0x20) == 1 end, 3000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then
          -- dlg $0527 (FC/Lift-off/Not yet): down once then A edges;
          -- dlg $052A (Lift-off/Not yet): A edges pick row 0 = Lift-off
          local three = H.readWord(0x00d0) == 0x0527
          local ph = t % 32
          if three and ph < 3 then H.setPad({ down = true })
          elseif ph >= 8 and ph < 11 then H.setPad({ "a" })
          else H.setPad({}) end
        else
          H.setPad(t % 24 < 3 and { up = true, a = true } or { up = true })
        end
      end),
    }, "Lift-off")
  end)(),
  H.waitFrames(150),
  -- ============ end deck party-change ============
  H.driveUntil(function() return landed end, 20000,
    { H.call(flyFrame) }, "landed at Crescent Mountain"),
  H.waitFrames(60),
  H.worldNavTo(214, 149, { maxFrames = 8000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() end, 900,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { up = true, a = true } or { up = true }) end) },
    "Crescent Mountain loads"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(mapIs(167), true, "inside Crescent Mountain (map 167)")
  end),
  -- into the cave and off the ledge
  H.navTo(25, 25, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(168) end }),
  H.driveUntil(function() return mapIs(168) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "into the dive cave"),
  H.waitFrames(60),
  -- the dive: step (8,11), ride the "Jump?" choice A-only
  (function()
    local t, talked = 0, false
    return {
      H.navTo(8, 11, { maxFrames = 6000, playBattles = "flee",
        arrive = function() return H.dialogWaiting() end }),
      H.driveUntil(function() return H.worldMode() end, 4000, {
        H.call(function()
          t = t + 1
          if H.dialogWaiting() then talked = true end
          if talked then
            H.setPad(t % 24 < 3 and { "a" } or {})
          else
            H.setPad({})
          end
        end),
      }, "dove into the Serpent Trench"),
    }
  end)(),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("riding the trench: worldId=%d", H.readWord(0x1f64) & 0xFF))
    H.screenshot("trench_ride")
  end),
  -- ride it out: battles fought tactically, forks left alone, until the
  -- ride ends (back on a field map = Nikeah, or the WoB world)
  (function()
    local battN, hb = 0, -600
    return H.driveUntil(function()
      local w = H.readWord(0x1f64)
      return (w & 0x1ff) >= 3 and not H.battleActive()
    end, 40000, {
      H.call(function()
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN == 0 then tactical.idle() end
        if H.frame - hb >= 900 then
          hb = H.frame
          H.log(string.format("  trench f%d w=%04X dances=%02X",
            H.frame, H.readWord(0x1f64), dances()))
        end
        if battN >= 3 then tactical.frame(); return end
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "the trench ride ends")
  end)(),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("RONDO RESULT: dances %02X -> %02X map=%d (%d,%d)",
      d0, dances(), H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
    H.screenshot("rondo_done")
    H.assertEq(dances() ~= d0, true,
      "Mog learned a dance on the water (Water Rondo)")
  end),
  H.saveState("wob_rondo_done.mss"),
  H.logStep(function() return "done" end),
}))
