-- probe_chest250.lua -- #84 scratch probe, not a fixture and not registered.
-- Boots banquet_done (world (120,188), everything paid, $0238 set), walks
-- back into Vector and the castle to map 250, crosses the {22,29} doorway
-- into the corridor, and measures walkability to the two bit-77/78 chests at
-- (24,48) Back Guard and (25,48) X-Potion: a canStep dump plus bfsPath
-- lengths to the candidate stand tiles.  This approximates the generator's
-- own post-messenger stretch (same switch set; the map re-init here runs
-- with $0238 already 1, which the post-messenger moment does not -- noted in
-- the report).
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

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
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 10)
  end
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/banquet_done.mss.lua"),
  H.waitFrames(60),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 1800, "world control at the J tile", 5),
  pressWalk("up", function() return not H.worldMode() end, 900,
    "step onto the Vector trigger (120,187)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253", 1),
  H.waitFrames(30),
  H.navTo(28, 2, { maxFrames = 30000, playBattles = "flee" }),
  pressWalk("up", function() return map() == 243 end, 900,
    "castle door 253 (28,1) -> 243"),
  H.waitUntil(landed(243, 10), 2400, "castle antechamber 243", 1),
  H.navTo(15, 9, { maxFrames = 12000, playBattles = "flee" }),
  pressWalk("up", function() return map() == 250 end, 900,
    "door 243 (15,8) -> 250 (23,33)"),
  H.waitUntil(landed(250, 10), 2400, "250 entry", 1),
  H.call(function()
    H.log(string.format("[probe250] entered 250 at (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),
  H.navTo(23, 30, { maxFrames = 6000, playBattles = "flee" }),
  pressWalk("up", function()
    return H.fieldY() <= 28 and H.tileAligned()
  end, 900, "held UP through the {22,29} doorway"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe250] corridor side at (%d,%d)",
      H.fieldX(), H.fieldY()))
    for _, t in ipairs({ { 15, 22, "below the (15,21) alcove door" },
                         { 15, 23, "the alcove-exit landing" },
                         { 23, 12, "the messenger tile" } }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[probe250] corridor -> (%d,%d) %-28s : %s",
        t[1], t[2], t[3], p and (#p .. " steps") or "NO PATH"))
    end
  end),
  -- through the (15,21) same-map door into the alcove (ShortEntrance:
  -- 250 (15,21) -> 250 (24,52); the exit is (24,53) -> (15,23))
  H.navTo(15, 22, { maxFrames = 9000, playBattles = "flee" }),
  pressWalk("up", function()
    return H.fieldY() >= 45 and H.tileAligned()
  end, 900, "held UP onto (15,21) -> the chest alcove"),
  H.release(),
  H.waitUntil(landed(250, 10), 2400, "the chest alcove", 1),
  H.call(function()
    H.log(string.format("[probe250] alcove side at (%d,%d)",
      H.fieldX(), H.fieldY()))
    for _, c in ipairs({ { 24, 48 }, { 25, 48 } }) do
      local CX, CY = c[1], c[2]
      H.log(string.format("[probe250] -- around chest (%d,%d) --", CX, CY))
      for y = CY - 4, CY + 6 do
        local row = {}
        for x = CX - 6, CX + 6 do
          local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
            or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
          row[#row + 1] = (x == CX and y == CY) and "C" or (r and "." or "#")
        end
        H.log(string.format("[walk] y=%2d %s", y, table.concat(row)))
      end
    end
    for _, t in ipairs({ { 24, 49, "below 77, face up" },
                         { 25, 49, "below 78, face up" },
                         { 24, 52, "the door landing" },
                         { 24, 53, "the exit tile" } }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[probe250] stand (%d,%d) %-20s : %s", t[1], t[2],
        t[3], p and (#p .. " steps") or "NO PATH"))
    end
  end),
  -- and back out through (24,53) -> (15,23), proving the round trip
  H.navTo(24, 52, { maxFrames = 3000, playBattles = "flee" }),
  pressWalk("down", function()
    return H.fieldY() <= 30 and H.tileAligned()
  end, 900, "held DOWN onto (24,53) -> back to the corridor (15,23)"),
  H.release(),
  H.waitUntil(landed(250, 10), 2400, "back in the corridor", 1),
  H.call(function()
    H.log(string.format("[probe250] round trip done at (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),
})
