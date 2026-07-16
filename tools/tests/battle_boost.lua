-- battle_boost: L/R boost-select in the battle menu, end to end.
--   R raises the active character's pending boost (cap 3, never past bp),
--   L lowers it, the party-window pip cell tracks live, and the boosted
--   action consumes the points (and skips that turn's +1 regen).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local actor
local cellSeen, cellFrames = {}, 0

-- sfx request counters: boost feedback must be audible. each request is an
-- inc (nonzero write) consumed by UpdateSfx's stz, so count nonzero writes.
local sfx = { ching = 0, click = 0, error = 0 }
local sfxRefs = {}
local function sfxWatch()
  sfxRefs[1] = emu.addMemoryCallback(function(addr, value)
    if value == 0 then return end
    if addr == 0x7e6281 then sfx.ching = sfx.ching + 1 end
  end, emu.callbackType.write, 0x7e6281, 0x7e6281)
  -- $94/$95 are direct-page writes: the cpu issues them in bank 0's wram
  -- mirror, so the callback must watch $000094, not $7e0094
  sfxRefs[2] = emu.addMemoryCallback(function(addr, value)
    if value == 0 then return end
    if addr == 0x000094 then sfx.click = sfx.click + 1 end
    if addr == 0x000095 then sfx.error = sfx.error + 1 end
  end, emu.callbackType.write, 0x000094, 0x000095)
end
local function sfxUnwatch()
  emu.removeMemoryCallback(sfxRefs[1], emu.callbackType.write, 0x7e6281, 0x7e6281)
  emu.removeMemoryCallback(sfxRefs[2], emu.callbackType.write, 0x000094, 0x000095)
end
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function()
    actor = H.readByte(0x62ca)
    H.log("active char slot: " .. actor)
    -- give the actor 3 bp so the cap is reachable
    H.writeByte(0x3e9c + actor*2, 3)
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
    sfxWatch()
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() H.assertEq(pend(actor), 1, "R raises pending to 1") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() H.assertEq(pend(actor), 3, "pending reaches 3") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 3, "cap: spend at most 3 (and never past bp)")
  end),
  -- live cell while boosting: the arrow-3 glyph, pulsing yellow/white, in
  -- BOTH window bands (rows 1+2r and 9+2r — the visible copy alternates).
  -- temporal sample (single frames can't see a pulse — or a strobe).
  H.waitUntil(function()
    local reg = H.readByte(0x897f)
    local base = ((reg - (reg % 4)) * 256) * 2
    local row
    for r = 0, 3 do if H.readByte(0x64d6 + r) == actor then row = r end end
    local lo = emu.readWord(base + (1 + row*2)*0x40 + 40, emu.memType.snesVideoRam)
    local hi = emu.readWord(base + (9 + row*2)*0x40 + 40, emu.memType.snesVideoRam)
    cellSeen[lo] = (cellSeen[lo] or 0) + 1
    if hi ~= lo then cellSeen[hi] = (cellSeen[hi] or 0) + 1 end
    cellFrames = cellFrames + 1
    return cellFrames >= 40
  end, 160, "arrow pulse sampled", 1),
  H.call(function()
    local parts = {}
    for w, n in pairs(cellSeen) do
      parts[#parts + 1] = string.format("%04x x%d", w, n)
    end
    H.log("boost cell words seen: " .. table.concat(parts, ", "))
    H.assertEq(cellSeen[0x216d] ~= nil, true, "arrow-3 in white seen")
    H.assertEq(cellSeen[0x296d] ~= nil, true, "arrow-3 in yellow seen (pulse alive)")
    for w in pairs(cellSeen) do
      H.assertEq(w == 0x216d or w == 0x296d, true,
        string.format("only arrow-3 words in the live cell, both bands (got %04x)", w))
    end
  end),
  H.pressButtons({ "l" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 2, "L lowers pending")
    sfxUnwatch()
    H.log(string.format("sfx: ching=%d click=%d error=%d",
      sfx.ching, sfx.click, sfx.error))
    H.assertEq(sfx.ching, 3, "each committed boost chings")
    H.assertEq(sfx.error, 1, "the denied 4th R buzzes")
    H.assertEq(sfx.click, 1, "L takeback clicks")
    H.screenshot("boost_selected")
  end),
  -- fire the boosted action; drive by menu state until it lands
  H.driveUntil(function() return bp(actor) ~= 3 end, 10000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "boosted action lands"),
  H.call(function()
    -- 3 bp - 2 spent, no regen on a boosted turn
    H.assertEq(bp(actor), 1, "boost consumed (3-2), regen skipped")
    H.assertEq(pend(actor), 0, "pending cleared after the action")
  end),
})
