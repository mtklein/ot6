-- probe_v07_gatescene3.lua -- the H->I tail dry run, part 3 (issue #31).  NOT a
-- suite test.  Boots v07i_384_west.mss (party (4,37), the west side of
-- BASEMENT 3) and drives the whole scripted stretch the recon could only
-- read: the gate door (held UP from (10,28) onto the (9..11,27) long
-- entrance), the _cb39ca scene with battles 121/122 (spare -- never
-- kill-bitted), the $0079 tail, the post-gate west census (does the
-- _cb2aa6 retile open (5,43)?), the shortcut to 382, the world pocket,
-- the base re-cross with battle 123 and the crash flight, the wreck's
-- deck, the map-7 hatch, and the world crash site -- measuring at each
-- boundary what the vector-crash-v1 contract needs: switches, ship cells
-- $1F62/$1F63, on-foot state, and the A-tap airship-dead check.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local DUMMY = 0x017b

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

local function reach(tag, goals)
  local sx, sy = H.fieldX(), H.fieldY()
  local seen = { [sy * 256 + sx] = true }
  local q, qi = { { sx, sy } }, 1
  local D = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
              left = { -1, 0 } }
  while qi <= #q and #q < 20000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for m, d in pairs(D) do
      if H.canStep(x, y, m) then
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and nx < 128 and ny >= 0 and ny < 64
           and not seen[ny * 256 + nx] then
          seen[ny * 256 + nx] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  H.log(string.format("[%s] flood from (%d,%d): %d tiles", tag, sx, sy, #q))
  for _, g in ipairs(goals) do
    H.log(string.format("[%s] %s (%d,%d): %s", tag, g[3], g[1], g[2],
      seen[g[2] * 256 + g[1]] and "REACHABLE" or "no"))
  end
  return seen
end

local function dumpReach(tag, seen, x0, x1, y0, y1)
  for y = y0, y1 do
    local r = {}
    for x = x0, x1 do
      r[#r + 1] = seen[y * 256 + x] and "#" or "."
    end
    H.log(string.format("[%s y=%02d] %s", tag, y, table.concat(r)))
  end
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
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

local function landed(m, n)
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 15)
  end
end

local function partyLine(tag)
  H.log(string.format("[%s] party T=%d L=%d E=%d S=%d Se=%d", tag,
    partyOf(0), partyOf(1), partyOf(4), partyOf(5), partyOf(9)))
end

H.run({ maxFrames = 240000 }, {
  H.loadState("build/states/v07i_postgate.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted post-gate")
    H.assertEq(sw(0x0079), 1, "$0079 stands")
  end),


  -- ---- the shortcut out -----------------------------------------------
  H.navTo(5, 42, { maxFrames = 20000,
    arrive = function() return map() == 382 end }),
  pressWalk("down", function() return map() == 382 end, 1200,
    "held DOWN onto the (5,43) shortcut -> 382 (31,41)"),
  H.waitUntil(landed(382, 10), 2400, "382 via the shortcut", 5),
  H.call(function()
    H.log(string.format("[382] landed (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- the mouth is the (25,37)/(25,38) pair: (25,37) is the world entry's
  -- landing, (25,38) the exit tile (short-entrance decode); approach the
  -- landing tile and step DOWN out
  H.navTo(25, 37, { maxFrames = 15000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "held DOWN onto the mouth exit (25,38) -> world (169,194)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 2400, "the world pocket", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[pocket] world (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- ---- the base re-cross, battle 123, the crash ------------------------
  worldGrind(167, 194, "pocket walk -> (167,194)"),
  pressWalk("left", function() return not H.worldMode() and map() == 377 end,
    900, "(166,194) -> base east door"),
  H.waitUntil(landed(377, 10), 2400, "base east landing", 5),
  H.call(function() partyLine("base re-cross") end),
  H.navTo(9, 17, { maxFrames = 20000 }),
  pressWalk("left", function() return not H.hasControl() or map() ~= 377 end,
    2400, "held LEFT into the west trigger row -> _cb280f"),
  (function() local t0 = nil
    return H.seqStep({
      H.call(function() t0 = H.frame end),
      H.advanceStory(function()
        return map() == 6 and sw(0x007A) == 1 and H.hasControl()
           and H.tileAligned() and bright() >= 15
      end, 120000, { spare = { DUMMY } }),
      H.call(function()
        H.log(string.format("[crash] scene+flight+deck took %d frames",
          H.frame - t0))
      end),
    })
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[wreck] map=%d (%d,%d) $007A=%d $007B=%d $01BA=%d "
      .. "$0242=%d $0246=%d $0176=%d", map(), H.fieldX(), H.fieldY(),
      sw(0x007A), sw(0x007B), sw(0x01BA), sw(0x0242), sw(0x0246),
      sw(0x0176)))
    partyLine("wreck deck")
    H.log(string.format("[wreck] ship cells $1F62/63=(%d,%d) parent "
      .. "$1F69=%02X%02X pos $1F6B=(%d,%d)", H.readByte(0x1F62),
      H.readByte(0x1F63), H.readByte(0x1F6A), H.readByte(0x1F69),
      H.readByte(0x1F6B), H.readByte(0x1F6C)))
    H.screenshot("v07gs_wreck")
  end),

  -- ---- off the wreck ----------------------------------------------------
  pressWalk("right", function() return map() == 7 end, 1800,
    "held RIGHT along the deck -> door (20,6) -> map 7"),
  H.waitUntil(landed(7, 10), 2400, "map 7 landing", 5),
  -- the hatch (8,36) is reached through the interior stair-teleports
  -- (short-entrance decode): (40,18) -> (50,51), then (50,62) -> (10,30)
  H.navTo(40, 17, { maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldY() >= 45 and H.tileAligned()
  end, 900, "stairs (40,18) -> (50,51)"),
  H.waitFrames(30),
  H.navTo(50, 61, { maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldY() <= 35 and H.tileAligned()
  end, 900, "stairs (50,62) -> (10,30)"),
  H.waitFrames(30),
  H.navTo(8, 36, { maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("up", function() return H.worldMode() end, 1200,
    "held UP onto the hatch (8,36) -> world on foot"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 3600, "world at the crash site", 5),
  H.waitFrames(45),
  H.call(function()
    H.log(string.format("[crash site] world (%d,%d) $1F62/63=(%d,%d) "
      .. "$11FA=%02X $11F3=%02X $1F60/61=(%d,%d)",
      H.worldX(), H.worldY(), H.readByte(0x1F62), H.readByte(0x1F63),
      H.readByte(0x11FA), H.readByte(0x11F3),
      H.readByte(0x1F60), H.readByte(0x1F61)))
    H.screenshot("v07gs_crashsite")
  end),
  -- A-tap: the dead airship must not lift off
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(30) }),
  H.call(function()
    H.log(string.format("[a-tap] world (%d,%d) $E0=%02X $E2=%02X "
      .. "$11FA=%02X worldMode=%s", H.worldX(), H.worldY(),
      H.readByte(0xe0), H.readByte(0xe2), H.readByte(0x11FA),
      tostring(H.worldMode())))
    H.assertEq(H.readByte(0xe0) ~= 0 or H.readByte(0xe2) ~= 0, true,
      "no liftoff -- the airship is dead")
  end),
  -- can we walk onto the wreck's tile?
  (function() local n = 0
    return H.driveUntil(function()
      n = n + 1
      return n >= 90
    end, 200, { H.call(function() H.setPad({ up = true }) end) },
      "try UP toward the wreck tile")
  end)(),
  H.call(function()
    H.setPad({})
    H.log(string.format("[wreck-step] world (%d,%d) $11FA=%02X",
      H.worldX(), H.worldY(), H.readByte(0x11FA)))
  end),
  H.saveState("v07i_crash_site.mss"),
  H.logStep(function()
    return string.format("gate scene + crash dry run complete at frame %d",
      H.frame)
  end),
})
