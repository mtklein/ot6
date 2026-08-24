-- probe_jidoor_shop.lua -- from the banked wob_jidoor_town fixture: buy
-- the caster relics and win Golem + Zoneseek at the Auction House
-- (#133 items 2 and 5).
--
-- Doors in Jidoor are bump entrances (probe_jidoor_town's bfs scout):
-- the walkable approach is the tile below, pushing UP -- relic shop
-- (5,26)->room 202, Auction House (26,28)->room 200.  Exits are the
-- mirrored step-through on the way out.
--
-- The auction (event _cb4e47, WoB arm _cb4ecc): talking to the
-- auctioneer at (19,24) with $006B=1 starts a randomly-drawn lot;
-- always-A rides every choice at its default row 0 ("Bid!"), which wins
-- whatever was drawn: junk (Cherub Down 1500 / 10000 / rarely bigger) or
-- the espers -- Golem tops out at 20000, Zoneseek at 10000.  $01F0=1
-- marks the day's auction done, so each round leaves the room and
-- re-enters.  The loop stops when the owned-esper bitfield ($1a69, 27
-- bits) grows by 2, or when gil drops under the reserve for the
-- remaining legs (Sraphim 3000 + Tzen relics ~26000).
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function gil() return H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16) end
local function espers()
  local n = 0
  for i = 0, 3 do
    local b = H.readByte(0x1a69 + i)
    while b > 0 do n = n + (b & 1); b = b >> 1 end
  end
  return n
end
local espers0 = nil
local function mapIs(m) return (H.mapId() & 0x1ff) == m end

local function bump(x, y, dir, destMap, tag)
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee" }),
    H.driveUntil(function() return mapIs(destMap) end, 600,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(50),
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
-- Find a reachable tile near the keeper at runtime (counters block the
-- adjacent tile -- measured: room 202's (54,17) has no path), walk there,
-- then press toward the keeper with A until the shop options open.
local function approachTalk(nx, ny, name)
  local tile, dir = nil, "up"
  local phase = 0
  return {
    H.call(function()
      local cands = {
        {nx,ny+1,"up"},{nx,ny+2,"up"},{nx,ny+3,"up"},
        {nx-1,ny+1,"up"},{nx+1,ny+1,"up"},
        {nx-1,ny,"right"},{nx+1,ny,"left"},{nx-2,ny,"right"},{nx+2,ny,"left"},
      }
      for _, c in ipairs(cands) do
        if H.bfsPath(c[1], c[2]) or
           (H.fieldX() == c[1] and H.fieldY() == c[2]) then
          tile, dir = { c[1], c[2] }, c[3]
          H.log(string.format("[%s] talk tile (%d,%d) facing %s", name,
            c[1], c[2], dir))
          return
        end
      end
      error(name .. ": no reachable talk tile near (" .. nx .. "," .. ny .. ")")
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 6000 }),
    H.driveUntil(function() return H.readByte(0x26) == 0x25 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { [dir] = true, a = true } or { [dir] = true })
      end),
    }, name .. ": shop options open"),
  }
end
local function closeShop(name)
  local phase = 0
  return H.driveUntil(function() return H.hasControl() end, 3000, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(phase < 4 and { "b" } or {})
    end),
  }, name .. ": shop closed")
end

-- one auction lot, ridden with default-row A; ends when control returns
local function auctionRound(i)
  local aPhase, sawDlg, calm = 0, false, 0
  return {
    H.navTo(19, 25, { maxFrames = 6000, playBattles = "flee" }),
    H.driveUntil(function() return H.dialogWaiting() end, 1200, {
      H.call(function() H.setPad(H.frame % 16 < 4 and { "up", "a" } or { "up" }) end),
    }, "auction " .. i .. ": auctioneer talks"),
    -- ride the lot on default-row A; "done" needs 90 calm frames because
    -- the scene pass_offs/pass_ons the party and the control flag reads
    -- live between beats (advanceStory's measured lesson)
    H.driveUntil(function() return calm >= 90 end, 12000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then
          sawDlg = true
          calm = 0
          H.setPad(aPhase < 4 and { "a" } or {})
        else
          if sawDlg and H.hasControl() and not H.eventRunning() then
            calm = calm + 1
          else
            calm = 0
          end
          H.setPad({})
        end
      end),
    }, "auction " .. i .. ": lot ridden to the end"),
    H.call(function()
      H.log(string.format("auction %d done: gil=%d espers=%d", i, gil(), espers()))
    end),
    -- leave and re-enter so the next lot can run ($01F0); the arrival
    -- tile (18,25) is provably pathable, the exit is the step below it
    H.navTo(18, 25, { maxFrames = 6000, playBattles = "flee" }),
    H.driveUntil(function() return mapIs(198) end, 600,
      { H.call(function() H.setPad({ down = true }) end) },
      "auction " .. i .. ": back to town"),
    H.waitFrames(50),
  }
end

local steps = {
  H.loadState("build/states/wob_jidoor_town.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    espers0 = espers()
    H.log(string.format("boot: gil=%d espers=%d", gil(), espers0))
  end),
  -- relic shop 23
  bump(5, 26, "up", 202, "into the relic shop"),
  approachTalk(54, 16, "relics"),
  H.buyItem(0xc3, 3, function() return 2 end, "Earrings x2"),
  H.buyItem(0xe3, 5, function() return 1 end, "Sniper Sight"),
  closeShop("relics"),
  H.call(function()
    H.log(string.format("relics: gil=%d earrings=%d sniper=%d",
      gil(), H.invCountOf(0xc3), H.invCountOf(0xe3)))
  end),
  bump(54, 22, "down", 198, "out of the relic shop"),
  -- the auction: up to 8 lots, stop when both espers land or gil floor
  bump(26, 28, "up", 200, "into the Auction House"),
}
for i = 1, 8 do
  steps[#steps + 1] = H.cond(function()
    return espers() < espers0 + 2 and gil() >= 33000
  end, flatten({
    auctionRound(i),
    H.cond(function() return espers() < espers0 + 2 and gil() >= 33000 end,
      flatten({ bump(26, 28, "up", 200, "re-enter for lot " .. (i + 1)) }), {}),
  }), {})
end
steps[#steps + 1] = H.call(function()
  H.log(string.format("AUCTION RESULT: gil=%d espers %d -> %d (%s)",
    gil(), espers0, espers(),
    espers() >= espers0 + 2 and "Golem+Zoneseek won" or "INCOMPLETE"))
  H.screenshot("auction_result")
end)
steps[#steps + 1] = H.saveState("wob_jidoor_done.mss")
steps[#steps + 1] = H.logStep(function() return "done" end)
H.run({ maxFrames = 120000 }, flatten(steps))
