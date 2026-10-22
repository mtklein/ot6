-- gen_water_rondo.lua -- the World of Balance detour that teaches MOG Water
-- Rondo (#428), played the first time the airship is the party's own:
-- cold-boot narshe-mission-v1 (world (84,34), the Blackjack parked at
-- (84,36)) and
--   1. Narshe: the Lone Wolf chase, resolved in MOG's favour.  _ccd3ce
--      fires as the party walks into the elder's house (30 (79,17)); the
--      chase runs 20 (49,37) -> 20 (38,20) -> 21 (31,22) ("Persistent,
--      aren't you!") -> north through the mines (21 (30,20) -> 43, 43
--      (113,45) -> 41, 41 (57,21) -> 41, 41 (18,51) -> 21, 21 (24,10) ->
--      41, 41 (117,12) -> 21) -> 22 -> 23 (22,20), the cliff, and 23 (9,18)
--      "Halt!".  The party stands through the 240-frame timer (_ccd52d:
--      "Kupo!!", both fall to the ledges) and talks to MOG (_ccd5df, obj
--      28 on the west ledge): MOG joins ($02FA, $029F) and the Gold Hairpin
--      (_ccd594, the wolf's ledge) is given up.
--   2. Back out of Narshe the way the chase came, aboard the Blackjack,
--      and MOG seated in the swap room (SETZER benched).
--   3. Nikeah (116,61): the stable (173, _ca8fb4) rents a chocobo, which is
--      ridden east and south through the Doma region to Barren Falls (world
--      (185,93); the bird cannot enter it, so B dismounts beside it).
--   4. Barren Falls 166 -> 155 -> 156: face up onto row 10 (_cbc03f, $01B0
--      facing up), "Jump?" yes; with $003F set the leap lands on the Veldt,
--      world (192,106) (_cbc1fb).
--   5. Across the Veldt to Crescent Mountain (214,148) -> 167 (25,26) ->
--      168, and the (8,11) "Jump?" (_cbc84d, gated on $0041 alone): the
--      dive _ca8ae3, battles 19/20/21 on the UNDERWATER background, which
--      teaches MOG Water Rondo ($1D4C bit 5) when he fights one.
--   6. Nikeah again (187, _ca8be3), out to the world beside the Blackjack,
--      and the world save: `water-rondo-v1`.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, EDGAR, SABIN, SETZER, MOG = 0x01, 0x04, 0x05, 0x09, 0x0A
local GOLD_HAIRPIN = 0xCD
local WATER_RONDO = 0x20            -- $1D4C bit 5 (dance_name: Water Rondo)
local MOG_LEDGE_OBJ = 28            -- 23's MOG (npc_prop.asm:1494) after the fall

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function inParty(c) return partyOf(c) ~= 0 end
local function settled() return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting() end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end
local function dances() return H.readByte(0x1D4C) end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function partyLine()
  local p = {}
  for ch = 0, 13 do if inParty(ch) then p[#p + 1] = string.format("%02X", ch) end end
  return table.concat(p, " ")
end

local function lazy(build)
  local step = nil
  return {
    tick = function()
      if step == nil then step = build() end
      return step:tick()
    end,
    reset = function()
      if step and step.reset then step:reset() end
      step = nil
    end,
  }
end

local function here(what)
  return H.call(function()
    H.log(string.format("[wr] f%d %s: map %d (%d,%d) party %s", H.frame, what, map(), H.fieldX(), H.fieldY(),
      partyLine()))
  end)
end

-- a scripted beat: A through its dialogs (START through a naming menu) until
-- pred holds with the party settled
local function story(pred, maxF, what)
  local ph = 0
  return H.withReset(H.seqStep({
    H.driveUntil(function() return pred() and settled() end, maxF, {
      H.call(function()
        ph = (ph + 1) % 16
        if H.readByte(0x0059) ~= 0 then H.setPad(ph < 6 and { "start" } or {}); return end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, what),
    H.release(),
    here(what),
  }), function() ph = 0 end)
end

-- the same through a scene that ends on the world map
local function storyWorld(maxF, what)
  local ph = 0
  return H.withReset(H.seqStep({
    H.driveUntil(function() return H.worldMode() and bright() >= 15 end, maxF, {
      H.call(function()
        ph = (ph + 1) % 16
        if not H.worldMode() and H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, what),
    H.release(),
  }), function() ph = 0 end)
end

local function walk(x, y, arrive)
  return H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", arrive = arrive })
end
-- the first reachable of `cands` (a long entrance's tiles), to arrive
local function walkAny(cands, arrive, what)
  return lazy(function()
    for _, t in ipairs(cands) do
      if H.bfsPath(t[1], t[2]) then
        H.log(string.format("[wr] %s: via (%d,%d)", what, t[1], t[2]))
        return walk(t[1], t[2], arrive)
      end
    end
    H.screenshot("wr_noway")
    error(string.format("%s: none of the entrance tiles is reachable from (%d,%d)", what, H.fieldX(), H.fieldY()), 0)
  end)
end
-- a door in a wall: stand below it and walk up into it
local function held(dir, pred, maxF, what)
  return H.seqStep({
    H.withReset(H.driveUntil(pred, maxF, { H.call(function() H.setPad({ [dir] = true }) end) }, what),
      function() end),
    H.release(),
  })
end
-- onto map m by a short entrance on (x, y), then control there
local function via(x, y, m, what)
  return H.seqStep({
    walk(x, y, function() return map() == m end),
    H.waitUntil(function() return map() == m and settled() end, 2400, what, 5),
    here(what),
  })
end
local function viaAny(cands, m, what)
  return H.seqStep({
    walkAny(cands, function() return map() == m end, what),
    H.waitUntil(function() return map() == m and settled() end, 2400, what, 5),
    here(what),
  })
end

-- held walk through trigger tiles (dialogs absorbed, battles fought)
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  local W = H.newWalkFighter("pressWalk: " .. what)
  return H.withReset(H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if W.frame() then return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what), function() ph = 0 end)
end

-- grind-and-replan world walker (gen_gate_cave_save's)
local function worldGrind(tx, ty, what)
  local plan, idx = nil, 1
  local W = H.newWalkFighter(what)
  return H.withReset(H.driveUntil(function()
    return H.offWorld() or (H.worldX() == tx and H.worldY() == ty and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      if W.frame() then plan = nil; return end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what), function() plan, idx = nil, 1 end)
end

local function flyTo(tx, ty)
  local calm, hb = 0, -300
  return H.withReset(H.driveUntil(function()
    calm = (shipX() == tx and shipY() == ty) and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      if H.frame - hb >= 300 then
        hb = H.frame
        H.log(string.format("[fly] f%d ship=(%d,%d)", H.frame, shipX(), shipY()))
      end
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty)), function() calm, hb = 0, -300 end)
end

local function choicePick(idxIn, donePred, maxFrames, what)
  return H.dialogChoice(idxIn, {
    ready = "count", on = 3, maxFrames = maxFrames, what = what, tag = what,
    done = function() return donePred() end,
    idle = function(ph) H.setPad(H.readByte(0x00d3) == 1 and ph < 3 and { "a" } or {}) end,
  })
end

local function landed(m, n)
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned() and bright() >= 15 and not H.battleLoadStarted()
      and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 20)
  end
end

-- ---- gear (gen_wor_narshe's): the bag's best where it beats what is worn --
local IP = nil
local function ip(id, off)
  IP = IP or (H.sym("ItemProp") & 0x3FFFFF)
  return H.readRomByte(IP + id * 30 + off)
end
local function wearable(ch, id)
  local mask = ip(id, 1) | (ip(id, 2) << 8)
  return (mask >> H.charActor(ch)) & 1 == 1
end
local function guard(id) return (id == 0xFF) and 0 or (ip(id, 0x14) + ip(id, 0x15)) end
local function bestInBag(ch, kind)
  local best, bs = nil, -1
  for s = 0, 255 do
    local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
    if id ~= 0xFF and n > 0 and (ip(id, 0) & 7) == kind and wearable(ch, id) then
      local sc = kind == 1 and ip(id, 0x14) or guard(id)
      if sc > bs then best, bs = id, sc end
    end
  end
  return best, bs
end
local function dressFromBag(ch, name)
  return lazy(function()
    local items = {}
    for _, sl in ipairs({ { 0, 1 }, { 1, 3 }, { 2, 4 }, { 3, 2 } }) do
      local cur = H.readByte(c(ch, 0x1F + sl[1]))
      local id, sc = bestInBag(ch, sl[2])
      local cs = (cur == 0xFF) and -1 or (sl[2] == 1 and ip(cur, 0x14) or guard(cur))
      if id and sc > cs then items[#items + 1] = { sl[1], id } end
      H.log(string.format("[kit] %s slot %d: wears $%02X (%d), the bag's best $%02X (%d)", name, sl[1], cur, cs,
        id or 0xFF, sc or -1))
    end
    if #items == 0 then return H.call(function() end) end
    return H.equipKit(ch, items, { tag = name .. " from the bag" })
  end)
end

-- ---- the chocobo (world/move.asm: bit $0001 of WorldTileProp stops it) ----
local function chocoPass(x, y) return (H.worldTileProp(x & 0xFF, y & 0xFF) & 0x0001) == 0 end
local function chocoBfs(sx, sy, goal)
  local prev = { [sy * 256 + sx] = -1 }
  local q, qi = { { sx, sy } }, 1
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    if goal(x, y) then
      local path, k = {}, y * 256 + x
      while k ~= -1 do table.insert(path, 1, { k % 256, k // 256 }); k = prev[k] end
      return path
    end
    for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
      local nx, ny = (x + d[1]) & 0xFF, (y + d[2]) & 0xFF
      local k = ny * 256 + nx
      if prev[k] == nil and chocoPass(nx, ny) then prev[k] = y * 256 + x; q[#q + 1] = { nx, ny } end
    end
  end
  return nil
end
-- ride the bird along the live BFS to a tile beside (gx, gy): A/up goes
-- forward and left/right steer (_ccd2e4's lesson); the heading is the word
-- at $73 (flyTo's reading, less 270); the bird aims at the path point three
-- past the nearest one
local function chocoRide(gx, gy, what)
  local path, stuck, lastT = nil, 0, nil
  local function there()
    local x, y = H.airshipTile()
    return path ~= nil and x == path[#path][1] and y == path[#path][2]
  end
  return H.withReset(H.seqStep({
    H.driveUntil(function() return there() end, 30000, {
      H.call(function()
        local x, y = H.airshipTile()
        if path == nil then
          path = chocoBfs(x, y, function(tx, ty) return math.abs(tx - gx) + math.abs(ty - gy) <= 1 end)
          if path == nil then error(string.format("%s: no chocobo path from (%d,%d)", what, x, y), 0) end
          H.log(string.format("[wr] %s: a %d-step chocobo path from (%d,%d)", what, #path - 1, x, y))
        end
        local t = x .. "," .. y
        if t == lastT then stuck = stuck + 1 else stuck, lastT = 0, t end
        if stuck >= 600 then
          H.screenshot("wr_chocobo_stuck")
          error(string.format("%s: the chocobo stopped at (%d,%d) for 600 frames (f%d)", what, x, y, H.frame), 0)
        end
        local k, bd = 1, 1e9
        for n, pt in ipairs(path) do
          local d = math.abs(pt[1] - x) + math.abs(pt[2] - y)
          if d < bd then k, bd = n, d end
        end
        local wp = path[math.min(k + 3, #path)]
        local px, py = H.airshipPos()
        local bearing = math.deg(math.atan(-(wp[2] + 0.5 - py), wp[1] + 0.5 - px))
        local err = ((bearing - (H.readWord(0x73) - 270)) + 180) % 360 - 180
        local pad = {}
        if math.abs(err) < 60 then pad.up = true end
        if math.abs(err) > 6 then pad[err > 0 and "left" or "right"] = true end
        H.setPad(pad)
      end),
    }, what),
    H.release(),
  }), function() path, stuck, lastT = nil, 0, nil end)
end

-- ---- the dive (gen_sabin_trench's ride driver) -----------------------------
local rideLost, rideWipeN = nil, 0
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end
local function ride(dir, pred, what, budget, choiceWant)
  local phase, hb, battN = 0, -900, 0
  local C = H.newChoice(choiceWant or 0, { ready = "pass", tag = what })
  -- Aspik first: its retaliation answers a non-Fight hit with Giga Volt
  -- (gen_sabin_trench's measurement)
  local F = H.newFightDriver("trench " .. what, { tactical = true,
    boost = true, bank = 3, items = true, healPercent = 60, cadence = 12,
    focus = { { species = 0x0059 } } })
  return H.driveUntil(function() return rideLost ~= nil or pred() end, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if not rideLost then
        local wiped = H.partyWipedInBattle()
        if not wiped and map() == 2 then
          local sane, alive = 0, 0
          for e = 0, 2 do
            local mx = H.readWord(0x3c1c + e * 2)
            if mx > 0 and mx < 10000 then
              sane = sane + 1
              if H.readWord(0x3bf4 + e * 2) > 0 then alive = alive + 1 end
            end
          end
          wiped = sane >= 3 and alive == 0
        end
        rideWipeN = wiped and rideWipeN + 1 or 0
        if (H.gameOverFired or 0) > 0 then
          rideLost = string.format("GAME OVER counted by the canary at f%d during %s (map=%d)", H.frame, what, map())
          H.log("[wr] LOST -- " .. rideLost)
          H.setPad({})
          return
        end
        if rideWipeN >= 90 then
          rideLost = string.format("wiped mid-ride at f%d during %s (map=%d)", H.frame, what, map())
          H.log("[wr] LOST -- " .. rideLost)
          H.setPad({})
          return
        end
      end
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("[trench:%s] f%d map=%d b=%s dances=$%02X", what, H.frame, map(),
          tostring(inBattle()), dances()))
      end
      if inBattle() or H.battleLoadStarted() then
        if battN == 0 then
          H.log(string.format("[trench:%s] battle up f%d -- fighting it (MOG in: %s)", what, H.frame,
            tostring(inParty(MOG))))
        end
        battN = battN + 1
        F.frame()
        return
      end
      if battN > 0 then F.idle() end
      battN = 0
      -- the ride map: hold the direction and read no field-owned cells
      if map() == 2 and dir then
        H.setPad({ [dir] = true })
        return
      end
      if C.frame(phase) then return end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

local diveBlob, diveDone = nil, false
local function diveCheckpoint()
  local ckReq
  return H.seqStep({
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "dive checkpoint")
      diveBlob = ckReq.blob
      H.log(string.format("[wr] dive checkpoint captured (%d bytes) f%d", #diveBlob, H.frame))
    end),
  })
end
local function diveAttempt(n)
  local ldReq
  return H.cond(function() return not diveDone end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function() return string.format("[wr] dive ATTEMPT %d -- reloading (%s)", n, tostring(rideLost)) end),
      H.call(function() ldReq = H.requestLoadState(diveBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ldReq, "dive attempt " .. n)
        H.gameOverFired = 0
      end),
      H.waitFrames(60 + (n - 1) * 17),
    }, {}),
    H.call(function() rideLost, rideWipeN = nil, 0; H.gameOverFired = 0 end),
    -- (8,11): "Jump?" (_cbc84d), option 0, then the dive; LEFT held is the
    -- mainline at both arrow windows
    walk(8, 10),
    (function()
      local frames = 0
      return ride("down", function()
        frames = frames + 1
        if frames > 55000 and rideLost == nil then
          rideLost = string.format("dive attempt %d deadline (55000 frames, map=%d)", n, map())
          H.log("[wr] LOST -- " .. rideLost)
        end
        return map() == 187
      end, "the jump and the dive a" .. n, 60000, 0)
    end)(),
    H.call(function()
      if rideLost == nil and map() == 187 then
        diveDone = true
        H.log(string.format("[wr] dive attempt %d LANDED at Nikeah f%d, dances $%02X", n, H.frame, dances()))
      elseif rideLost == nil then
        rideLost = string.format("dive attempt %d ended off-Nikeah (map=%d) f%d", n, map(), H.frame)
        H.log("[wr] " .. rideLost)
      end
    end),
  }, {})
end

H.run({ maxFrames = 400000, allowGameOver = true }, {
  -- narshe-mission-v1 pins its tile through ram cells, not a world field,
  -- so the Continue is gen_gate_cave_save's
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "cold Continue to the narshe-mission world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("narshe-mission-v1") end),
  H.call(function()
    H.log(string.format("[wr] boot: world (%d,%d), the Blackjack at (%d,%d); party %s; dances $%02X; "
      .. "$0239=%d $02FA=%d $029F=%d $0041=%d $003F=%d", H.worldX(), H.worldY(), H.readByte(0x1F62),
      H.readByte(0x1F63), partyLine(), dances(), sw(0x239), sw(0x2FA), sw(0x29F), sw(0x41), sw(0x3F)))
    H.assertEq(sw(0x0239), 0, "$0239 clear: Lone Wolf has not been seen (_ccd3ce)")
    H.assertEq(sw(0x02FA), 0, "MOG is not yet available")
    H.assertEq(sw(0x0041), 1, "$0041 set: the trench's (8,11) jump is open (_cbc84d)")
    H.assertEq(sw(0x003F), 1, "$003F set: the Barren Falls leap lands on the Veldt (_cbc1fb)")
    H.assertEq(dances() & WATER_RONDO, 0, "Water Rondo not yet known")
  end),

  -- ---- 1. Narshe: the Lone Wolf chase ----------------------------------------
  held("up", function() return not H.worldMode() and map() == 20 end, 1200, "(84,33) -> Narshe (map 20)"),
  H.waitUntil(function() return map() == 20 and settled() end, 1800, "Narshe control", 5),
  walk(52, 38),
  held("up", function() return map() == 30 end, 600, "the door (52,37) -> the elder's house (30 (79,17))"),
  -- _ccd3ce runs on the arrival tile itself
  story(function() return map() == 30 and sw(0x0239) == 1 end, 4000, "Lone Wolf is made (_ccd3ce)"),
  H.call(function() H.screenshot("wr_wolf_made") end),
  walk(79, 18, function() return map() == 20 end),
  H.waitUntil(function() return map() == 20 and settled() end, 1800, "Narshe again", 5),
  walk(49, 37, function() return sw(0x023A) == 1 end),
  story(function() return sw(0x023A) == 1 end, 3000, "G'heh (20 (49,37), _ccd424)"),
  walk(38, 20, function() return sw(0x023B) == 1 end),
  story(function() return sw(0x023B) == 1 end, 3000, "the wolf runs north (20 (38,20), _ccd456)"),
  viaAny({ { 36, 1 }, { 35, 1 }, { 37, 1 }, { 38, 1 } }, 21, "map 21"),
  walk(31, 22, function() return sw(0x023C) == 1 end),
  story(function() return sw(0x023C) == 1 end, 3000, "Persistent, aren't you! (21 (31,22), _ccd48a)"),
  -- north through the mines
  held("up", function() return map() == 43 end, 600, "21 (30,20) -> the mine 43"),
  H.waitUntil(function() return map() == 43 and settled() end, 1800, "map 43", 5),
  via(113, 45, 41, "43 (113,45) -> 41 (58,11)"),
  walk(57, 21, function() return H.fieldY() > 40 end),
  H.waitUntil(function() return map() == 41 and settled() end, 1800, "41 (57,21) -> 41 (25,58)", 5),
  via(18, 51, 21, "41 (18,51) -> 21 (36,25)"),
  via(24, 10, 41, "21 (24,10) -> 41 (108,12)"),
  via(117, 12, 21, "41 (117,12) -> 21 (32,10)"),
  viaAny({ { 35, 1 }, { 36, 1 }, { 37, 1 }, { 34, 1 } }, 22, "21 -> 22 (19,39)"),
  viaAny({ { 19, 1 }, { 20, 1 }, { 18, 1 }, { 21, 1 } }, 23, "22 -> 23 (25,31), the cliff"),
  walk(22, 20, function() return sw(0x023D) == 1 end),
  story(function() return sw(0x023D) == 1 end, 3000, "the wolf holds MOG (23 (22,20), _ccd4a8)"),
  H.call(function() H.screenshot("wr_wolf_cliff") end),
  -- "Halt!" (_ccd4fe) starts the 240-frame timer; standing still lets it run
  -- out (_ccd52d) -- a step back onto (8,19)/(10,19)/(9,20) is _ccd523, which
  -- stops it
  walk(9, 18, function() return sw(0x023E) == 1 end),
  story(function() return sw(0x023F) == 1 end, 3000, "Kupo!! -- the fall (_ccd52d)"),
  H.call(function()
    H.log(string.format("[wr] after the fall: MOG (obj %d) at (%d,%d), the wolf (obj 27) at (%d,%d); Gold Hairpins %d",
      MOG_LEDGE_OBJ, H.objX(MOG_LEDGE_OBJ), H.objY(MOG_LEDGE_OBJ), H.objX(27), H.objY(27), H.invCountOf(GOLD_HAIRPIN)))
    H.vars.hairpins = H.invCountOf(GOLD_HAIRPIN)
    H.screenshot("wr_wolf_fallen")
  end),
  H.talkToObj(MOG_LEDGE_OBJ, "MOG on the west ledge (_ccd5df)", 1200),
  H.release(),
  story(function() return sw(0x029F) == 1 and sw(0x02FA) == 1 end, 20000, "MOG joins"),
  H.call(function()
    H.assertEq(sw(0x02FA), 1, "MOG is available ($02FA, _ccd5df)")
    H.assertEq(sw(0x029F), 1, "$029F: MOG waits aboard (the WoR meeting reads it)")
    H.assertEq(H.invCountOf(GOLD_HAIRPIN), H.vars.hairpins, "the Gold Hairpin was given up (_ccd594 not run)")
    H.log(string.format("[wr] MOG joined: L%d, party %s", H.readByte(c(MOG, 8)), partyLine()))
    H.screenshot("wr_mog_joined")
  end),

  -- ---- 2. out of Narshe the way the chase came -------------------------------
  viaAny({ { 24, 32 }, { 25, 32 }, { 23, 32 }, { 26, 32 } }, 22, "23 -> 22"),
  viaAny({ { 17, 41 }, { 18, 41 }, { 16, 41 }, { 19, 41 } }, 21, "22 -> 21 (36,2)"),
  via(31, 10, 41, "21 (31,10) -> 41 (116,12)"),
  via(107, 12, 21, "41 (107,12) -> 21 (23,10)"),
  via(37, 25, 41, "21 (37,25) -> 41 (19,51)"),
  walk(25, 59, function() return H.fieldY() < 40 end),
  H.waitUntil(function() return map() == 41 and settled() end, 1800, "41 (25,59) -> 41 (57,23)", 5),
  via(57, 11, 43, "41 (57,11) -> 43 (112,45)"),
  via(108, 60, 21, "43 (108,60) -> 21 (31,22)"),
  viaAny({ { 25, 52 }, { 26, 52 }, { 24, 52 }, { 27, 52 }, { 23, 52 }, { 28, 52 } }, 20, "21 -> Narshe 20 (38,2)"),
  walk(18, 61, function() return H.worldMode() end),
  pressWalk("down", function() return H.worldMode() end, 1200, "Narshe's south edge -> the world"),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() and bright() >= 15 end, 2400,
    "the world outside Narshe", 5),

  -- ---- 3. aboard: MOG seated in the swap room --------------------------------
  worldGrind(84, 36, "onto the parked Blackjack (84,36)"),
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function() return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0 end, 900,
    "liftoff (the flight view zeroes $E0/$E2)", 5),
  H.waitFrames(240),
  H.pressButtons({ "x" }, 8),
  H.waitUntil(landed(6, 20), 1800, "the Blackjack deck (map 6)", 1),
  H.waitFrames(30),
  pressWalk("right", function() return map() == 7 end, 900, "deck door (20,6) -> map 7"),
  H.waitUntil(landed(7, 10), 1200, "map 7", 1),
  H.navTo(40, 17, { playBattles = "tactical", maxFrames = 9000 }),
  pressWalk("down", function() return H.fieldY() >= 45 and H.tileAligned() end, 900,
    "stairs (40,18) -> the swap room"),
  H.waitFrames(45),
  H.chaseTalk(0x20, 9000, "chase-talk MOG in the swap room (map 7 NPC_17)"),
  choicePick(1, function() return H.readByte(0x0059) ~= 0 and H.readByte(0x0026) == 0x2d end, 3000,
    "YES -> the party menu"),
  H.waitUntil(function() return H.readByte(0x0026) == 0x2d end, 900, "the party menu", 5),
  H.waitFrames(20),
  H.partySelect({ LOCKE, EDGAR, SABIN, MOG }, { tag = "swap room" }),
  H.waitUntil(landed(7, 20), 3000, "map 7 after the party menu", 1),
  H.call(function()
    H.assertEq(inParty(MOG), true, "MOG seated")
    H.assertEq(inParty(SETZER), false, "SETZER benched")
    H.log(string.format("[wr] seated: %s", partyLine()))
  end),
  dressFromBag(MOG, "MOG"),
  H.navTo(40, 11, { playBattles = "tactical", maxFrames = 6000 }),
  pressWalk("up", function() return map() == 6 end, 900, "door (40,10) -> the deck"),
  H.waitUntil(landed(6, 10), 1200, "the deck again", 1),
  H.navTo(14, 6, { playBattles = "tactical", maxFrames = 6000, calmFrames = 8 }),
  (function() local ph = 0
    return H.driveUntil(function() return H.readByte(0x056f) >= 2 or H.worldMode() end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a", left = true } or { left = true })
      end),
    }, "LEFT+A on the wheel -> the lift-off choice")
  end)(),
  choicePick(function() return H.readByte(0x056f) >= 3 and 1 or 0 end, function() return H.worldMode() end, 3000,
    "(Lift-off)"),
  H.release(),
  H.waitFrames(150),

  -- ---- 4. Nikeah: the chocobo stable ----------------------------------------
  flyTo(116, 61),
  H.release(),
  H.waitFrames(60),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end, 1200, "the Blackjack grounds", 10),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.worldX(), 116, "grounded at Nikeah x")
    H.assertEq(H.worldY(), 61, "grounded at Nikeah y")
  end),
  worldGrind(117, 61, "world (117,61) -> Nikeah"),
  H.waitUntil(function() return map() == 169 and settled() end, 2400, "Nikeah (map 169)", 5),
  H.navTo(23, 21, { maxFrames = 8000, arrive = function() return map() == 173 end }),
  H.navTo(23, 20, { maxFrames = 3000, arrive = function() return map() == 173 end }),
  H.waitUntil(function() return map() == 173 and settled() end, 2400, "Nikeah's stable (map 173)", 5),
  -- the keeper (85,45) faces right across the counter (86,45): talk from (87,45)
  H.navTo(87, 45, { maxFrames = 3000 }),
  H.faceAndHoldA("left", function() return H.dialogWaiting() end, 600, "the chocobo keeper across the counter"),
  H.release(),
  H.call(function() H.vars.gil = H.gil() end),
  H.dialogChoice(0, { inBattle = false, what = "Chocobo ride? Yes (_ca8fb4)", tag = "the stable" }),
  -- "Wanna know how to ride a chocobo?" (_ccd2e4) and out onto the world
  storyWorld(6000, "the ride out (load_map 511, CHOCOBO)"),
  H.waitUntil(function() return H.worldMode() and bright() >= 15 and H.readByte(0x0020) == 2 end, 1200,
    "riding the chocobo ($20 = 2)", 5),
  H.call(function()
    local x, y = H.airshipTile()
    H.log(string.format("[wr] riding from (%d,%d); the ride cost %d gil", x, y, H.vars.gil - H.gil()))
    H.screenshot("wr_chocobo")
  end),

  -- ---- 5. the ride to Barren Falls, the leap to the Veldt ---------------------
  chocoRide(185, 93, "east and south through the Doma region to Barren Falls"),
  H.withReset(H.driveUntil(function() return H.readByte(0x0020) ~= 2 end, 600, {
    H.call(function() H.setPad(H.frame % 16 < 4 and { "b" } or {}) end) }, "B: dismount"), function() end),
  H.release(),
  H.waitWorldSettled("dismounted beside Barren Falls", 900, 30),
  H.call(function() H.log(string.format("[wr] f%d dismounted at (%d,%d)", H.frame, H.worldX(), H.worldY())) end),
  H.worldNavTo(185, 93, { maxFrames = 3000, playBattles = "tactical", arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == 166 and settled() end, 2400, "Barren Falls (map 166)", 5),
  via(7, 4, 155, "166 (7,4) -> 155 (11,11)"),
  via(10, 4, 156, "155 (10,4) -> 156 (15,20), the cliff over the falls"),
  walk(13, 11),
  -- facing up onto row 10 ($01B0) asks "Jump?" (_cbc03f)
  pressWalk("up", function() return H.dialogWaiting() and H.readByte(0x056f) >= 2 end, 600, "up onto (13,10)"),
  H.release(),
  H.dialogChoice(0, { inBattle = false, what = "Jump? (Why not?)", tag = "the falls" }),
  storyWorld(6000, "the leap (_cbc058 -> _cbc1fb)"),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldAligned() and bright() >= 15 end,
    2400, "the Veldt", 5),
  H.call(function()
    H.log(string.format("[wr] f%d on the Veldt at (%d,%d)", H.frame, H.worldX(), H.worldY()))
    H.screenshot("wr_veldt")
  end),

  -- ---- 6. Crescent Mountain and the Serpent Trench ---------------------------
  H.worldNavTo(214, 148, { maxFrames = 30000, playBattles = "tactical", arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == 167 and settled() end, 2400, "Crescent Mountain (map 167)", 5),
  here("Crescent Mountain"),
  via(25, 26, 168, "167 (25,26) -> 168 (8,9)"),
  H.fieldCare({ tag = "pre-dive care", threshold = 0.95 }),
  H.call(function() H.assertEq(inParty(MOG), true, "MOG dives with the party") end),
  diveCheckpoint(),
  diveAttempt(1),
  diveAttempt(2),
  diveAttempt(3),
  H.call(function()
    if not diveDone then
      error(string.format("the dive did not reach Nikeah on any of 3 staggered attempts -- last: %s",
        tostring(rideLost)), 0)
    end
  end),
  H.waitUntil(function() return map() == 187 and settled() end, 8000, "Nikeah's dock (187)", 5),
  H.call(function()
    H.log(string.format("[wr] f%d Nikeah's dock at (%d,%d): dances $%02X", H.frame, H.fieldX(), H.fieldY(), dances()))
    H.assertEq(dances() & WATER_RONDO, WATER_RONDO, "MOG knows Water Rondo ($1D4C bit 5)")
    H.screenshot("wr_nikeah_dock")
  end),

  -- ---- 7. out to the Blackjack, and the save ---------------------------------
  H.navTo(16, 2, { maxFrames = 8000, playBattles = "tactical" }),
  pressWalk("up", function() return map() == 169 end, 900, "the dock's north edge -> Nikeah town 169"),
  H.waitUntil(function() return map() == 169 and settled() end, 3000, "Nikeah town", 5),
  H.navTo(1, 35, { playBattles = "tactical", maxFrames = 20000, arrive = function() return H.worldMode() end }),
  pressWalk("left", function() return H.worldMode() end, 1200, "Nikeah's x=0 column -> the world (116,61)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 2400, "the world beside the Blackjack", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[wr] f%d world (%d,%d), the Blackjack at (%d,%d); party %s; dances $%02X", H.frame,
      H.worldX(), H.worldY(), H.readByte(0x1F62), H.readByte(0x1F63), partyLine(), dances()))
    H.screenshot("wr_beside_the_blackjack")
  end),
  -- care before the save, as a player does at a save: the trench's last
  -- battle can fell a member (v0.35's chain: EDGAR saved at 0/821 HP,
  -- audit_party_hp), and the Continue would start with him down
  H.fieldCare({ tag = "before the water-rondo-v1 save" }),
  H.call(function()
    for s = 0, 15 do
      if (H.readByte(0x1850 + s) & 7) == 1 then
        local o = 0x1600 + s * 37
        H.assertEq(H.readWord(o + 0x09) > 0 and (H.readByte(o + 0x14) & 0xC2) == 0, true,
          string.format("char %d stands at the save (HP %d/%d)", H.readByte(o), H.readWord(o + 0x09), H.readWord(o + 0x0B)))
      end
    end
  end),
  H.saveState("water_rondo.mss"),
  H.saveAtCheckpoint("water-rondo-v1"),
})
