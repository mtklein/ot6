-- @suite savestate=vargas_won
-- battle_auraband: several characters' boost auras at once stay inside the
-- PPU's scanline sprite budget (#445 review; ot6_aura.asm, Ot6AuraHalo).
--
-- The PPU draws at most 32 sprites and 34 8-pixel slivers on a line and
-- drops slivers past that, the lowest-index sprites' first: a character's
-- own body goes see-through before the halo copies behind it.  The v0.32
-- review measured two neighbours at 3 BP reaching 40 slivers on a line
-- before the halo had a budget (build/attempts/wt/review-v032-boost-aura/).
--
-- A mechanism test, not play: in a real battle reached by play (vargas_won,
-- the party of four, a Kolts ledge encounter), it writes the pending boost
-- of the characters a case names (a declared state-write waiver: holding
-- four boosts at once needs four queued boosted actions, which the queue
-- seldom holds), then reads the OAM the PPU is given for 24 frames and
-- asserts, on every line above $97 (where FF6 overflows lines on purpose to
-- hide sprites behind the menu window, OAM entries 115-123):
--   1. at most 32 sprites and 34 slivers on the line;
--   2. every seated character keeps its two body sprites;
--   3. every boosted character glows (colour 1 on Ot6AuraOutline's 3 BP row);
--   4. one boosted character at a time wears the halo (has copies), the
--      rest the glow; and the halo shows.
-- Cases: each pair of vertical neighbours at 3 BP, then all four at 3 BP.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"
local OAM, CG = emu.memType.snesSpriteRam, emu.memType.snesCgRam
local FLOOR = 0x97
local function map() return H.mapId() & 0x1ff end

local seated = {}
local function setPending(slots)
  local on = {}
  for _, s in ipairs(slots) do on[s] = true end
  for _, s in ipairs(seated) do H.writeByte(0x3e9d + s * 2, on[s] and 3 or 0) end
end

-- per line sprites and slivers (the reviewer's count: 16x16 small, 32x32
-- large, x clipped to the screen), and each slot's body+copy entries
local function scan()
  local spr, til = {}, {}
  for l = 0, 223 do spr[l], til[l] = 0, 0 end
  local entries = {}
  for i = 0, 127 do
    local x, y = emu.read(i * 4, OAM), emu.read(i * 4 + 1, OAM)
    local t, a = emu.read(i * 4 + 2, OAM), emu.read(i * 4 + 3, OAM)
    local hb = (emu.read(512 + (i >> 2), OAM) >> ((i & 3) * 2)) & 3
    if hb & 1 == 1 then x = x - 256 end
    local w = (hb & 2 == 2) and 32 or 16
    if x > -w and x < 256 then
      for dy = 0, w - 1 do
        local l = (y + dy) & 0xff
        if l < 224 then
          spr[l] = spr[l] + 1
          til[l] = til[l] + (math.min(x + w, 256) - math.max(x, 0) + 7) // 8
        end
      end
    end
    if (t & 0xf1) == 0 and (a & 0x0f) == 8 + (t >> 2) * 2 and y < 0xe0 then
      local s = t >> 2
      entries[s] = (entries[s] or 0) + 1
    end
  end
  local worstS, worstT, ls, lt = 0, 0, 0, 0
  for l = 0, FLOOR - 1 do
    if spr[l] > worstS then worstS, ls = spr[l], l end
    if til[l] > worstT then worstT, lt = til[l], l end
  end
  return worstS, ls, worstT, lt, entries
end

local function outline3()
  local base, row = H.sym("Ot6AuraOutline") & 0x3FFFFF, {}
  for i = 0, 4 do row[H.readRomWord(base + (10 + i) * 2)] = true end
  return row
end

local function case(name, slots)
  local worst = { s = 0, t = 0 }
  local copies, shown = {}, 0
  return H.repeatN(1, {
    H.call(function()
      setPending(slots)
      H.log(string.format("[band] %s: pending 3 on slot(s) %s", name, table.concat(slots, ",")))
    end),
    H.waitFrames(10),
    H.repeatN(24, {
      H.call(function()
        local on = {}
        for _, s in ipairs(slots) do on[s] = true end
        for _, s in ipairs(seated) do
          H.assertEq(H.readByte(0x3e9d + s * 2), on[s] and 3 or 0,
            string.format("%s: slot %d's pending boost held", name, s))
        end
        local S, ls, T, lt, ent = scan()
        if S > worst.s then worst.s, worst.sl = S, ls end
        if T > worst.t then worst.t, worst.tl = T, lt end
        H.assertEq(S <= 32, true, string.format("%s: at most 32 sprites on a line above $%02X (line %d has %d)",
          name, FLOOR, ls, S))
        H.assertEq(T <= 34, true, string.format("%s: at most 34 slivers on a line above $%02X (line %d has %d)",
          name, FLOOR, lt, T))
        local row, now = outline3(), 0
        for _, s in ipairs(seated) do
          if on[s] and (ent[s] or 0) > 2 then now = now + 1 end
        end
        H.assertEq(now <= 1, true, string.format("%s: one character at a time wears the halo (%d do)", name, now))
        if now == 1 then shown = shown + 1 end
        for _, s in ipairs(seated) do
          local n = ent[s] or 0
          H.assertEq(n >= 2, true, string.format("%s: slot %d keeps its two body sprites (%d)", name, s, n))
          if on[s] then
            copies[s] = math.max(copies[s] or 0, n - 2)
            local c1 = emu.readWord(((12 + s) * 16 + 1) * 2, CG)
            if not row[c1] then
              error(string.format("%s: slot %d's colour 1 $%04x is not on the 3 BP outline row", name, s, c1), 0)
            end
          end
        end
      end),
      H.waitFrames(1),
    }),
    H.call(function() H.screenshot("auraband_" .. name:gsub("[^%w]+", "_")) end),
    H.waitFrames(4),
    H.call(function()
      local t = {}
      for _, s in ipairs(slots) do
        t[#t + 1] = string.format("slot %d %d", s, copies[s] or 0)
      end
      H.assertEq(shown > 0, true, name .. ": the halo shows (a boosted character has copies)")
      H.log(string.format("[band] %s: worst %d sprites (line %d), %d slivers (line %d) above $%02X; copies: %s",
        name, worst.s, worst.sl or -1, worst.t, worst.tl or -1, FLOOR, table.concat(t, ", ")))
      setPending({})
    end),
    H.waitFrames(8),
  })
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control"),
  (function()
    local waited, lane = 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    local m0
    return H.driveUntil(function()
      waited = waited + 1
      m0 = m0 or map()
      if H.battleLoadStarted() then H.setPad({}) return true end
      if map() ~= m0 then error("paced off map " .. m0 .. " (now " .. map() .. ")", 0) end
      return waited >= 12000
    end, 12600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "an encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) ~= 0xff then seated[#seated + 1] = s end
    end
    H.assertEq(#seated, 4, "precondition: four characters seated (vargas_won's party)")
    local S, ls, T, lt = scan()
    H.screenshot("auraband_no_boost")   -- (taken on the next drawn frame)
    H.assertEq(T <= 34, true, "precondition: with no boost every line above the floor is within 34 slivers")
    H.log(string.format("[band] no boost: worst %d sprites (line %d), %d slivers (line %d) above $%02X",
      S, ls, T, lt, FLOOR))
  end),
  case("slots 0+1", { 0, 1 }),
  case("slots 1+2", { 1, 2 }),
  case("slots 2+3", { 2, 3 }),
  case("all four", { 0, 1, 2, 3 }),
  H.call(function() H.log("[band] every case inside the budget") end),
})
