-- @suite slow
-- menu_esperdetail.lua -- the esper detail page shows the selected character's ladder on that esper (#328, plan
-- A: docs/design/esper-rework.md; skills.asm DrawEsperDetailMenu's tail) and never the dead learn-rate columns.
--
-- Played: Continue fire-out-v1 (TERRA, LOCKE and STRAGO seated; twelve stones owned), open X -> Skills -> the
-- leader -> Espers -> list -> a stone's detail page, through the real menu.  Visited: every owned stone in turn.
-- Asserted at cell level in the BG1 screen-B tilemap shadow the menu draws into (wBG1Tiles::ScreenB = $7e4049;
-- 2 bytes per cell, char then attribute, 64 bytes per row):
--   1. the caption at {13,15}: "Rank " r, a blank, the leader's Magic Points on the stone (four cells, leading
--      zeros blank), "/" and the next rung's cost (three cells), or four blanks at rank 5, then a pad; r and the
--      points are the live esper page's ($317C00) for the leader and that stone (Odin and Raiden share one);
--   2. the five rung rows (tilemap rows 17-25, cols 16-27): Ot6RungLabelTbl's twelve tiles for the stone's rung,
--      white (attribute $20) once the points reach the rung's cost (10 / 30 / 75 / 200 / 500), grey ($28) until;
--   3. no learn-rate colon or percent on the spell rows, and row 27 blank.
-- The play from power-on gives the leader some progress and leaves most rungs grey; the white branch is then
-- staged once (declared in state_write_waivers.txt): the leader's count on the first stone is set to 200
-- (rank 4) on the live page and the page revisited, so rows 1-4 read white, row 5 grey and the caption "Rank 4
-- 200/500".  That write is a mechanism expedient for the drawing, not play.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, Z99, SKILLCOLOR = 0x26, 0x4b, 0x99, 0x79
local ESPERS, GENJULIST = 0x1a69, 0x9d89
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local BG1B = 0x4049
local LIVE = 0x317C00
local COSTS = { 10, 30, 75, 200, 500 }
local BLANK, CH_COLON, CH_PCT, CH_SLASH = 0xff, 0xc1, 0xcd, 0xc0
local RANK = { 0x91, 0x9a, 0xa7, 0xa4, 0xff }     -- "Rank " (menu_text_en.inc OT6_GENJU_RANK)
local function digit(n) return 0xb4 + n end
local function st() return H.readByte(ZMENUSTATE) end
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end
local function attr(x, y) return H.readByte(BG1B + x * 2 + y * 64 + 1) end
local function sramW(a) local m = emu.memType.snesMemory; return emu.read(a, m) | (emu.read(a + 1, m) << 8) end
local function slotOf(e) if e < 12 then return e elseif e == 12 then return 11 else return e - 1 end end
local function rankOf(n) local r = 0; for _, c in ipairs(COSTS) do if n >= c then r = r + 1 end end; return r end
local LABELS = H.sym("Ot6RungLabelTbl") & 0x3FFFFF
local function label(e, k, i) return emu.read(LABELS + ((slotOf(e) * 5 + k) * 12) + i, emu.memType.snesPrgRom) end

local leader = nil
local function leaderOf()
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    if b ~= 0 and (b & 7) == cur and ((b >> 3) & 3) == 0 then return c end
  end
end
local function points(e) return sramW(LIVE + 0x10 + (leader * 26 + slotOf(e)) * 2) end

-- four digits, leading zeros blank, as HexToDec5's last four
local function digits(n, w)
  local s, t = string.format("%0" .. w .. "d", n), {}
  local lead = true
  for i = 1, w do
    local d = tonumber(s:sub(i, i))
    if lead and d == 0 and i < w then t[i] = BLANK else lead = false; t[i] = digit(d) end
  end
  return t
end

local function checkPage(e, tag)
  local p = points(e)
  local r = rankOf(p)
  H.log(string.format("[detail] %s: esper %d, the leader's points %d, rank %d", tag, e, p, r))
  H.assertEq(H.readByte(Z99), e, tag .. ": the page shows the stone asked for")
  -- 1. the caption
  for i = 1, 5 do H.assertEq(cell(12 + i, 15), RANK[i], string.format("%s: caption 'Rank ' cell %d", tag, i)) end
  H.assertEq(cell(18, 15), digit(r), tag .. ": the rank digit")
  H.assertEq(cell(19, 15), BLANK, tag .. ": blank after the rank")
  local pd = digits(p, 4)
  for i = 1, 4 do H.assertEq(cell(19 + i, 15), pd[i], string.format("%s: points digit %d (of %d)", tag, i, p)) end
  if r < 5 then
    H.assertEq(cell(24, 15), CH_SLASH, tag .. ": '/' before the next cost")
    local cd = digits(COSTS[r + 1], 3)
    for i = 1, 3 do H.assertEq(cell(24 + i, 15), cd[i], string.format("%s: next cost digit %d", tag, i)) end
  else
    for x = 24, 27 do H.assertEq(cell(x, 15), BLANK, tag .. ": no next cost at rank 5") end
  end
  -- 2. the rungs
  for k = 0, 4 do
    local y = 17 + 2 * k
    for i = 0, 11 do
      H.assertEq(cell(16 + i, y), label(e, k, i), string.format("%s: rung %d label tile %d", tag, k + 1, i))
    end
    local want = p >= COSTS[k + 1] and 0x20 or 0x28
    H.assertEq(attr(16, y) & 0x3C, want, string.format("%s: rung %d %s", tag, k + 1,
      want == 0x20 and "white (reached)" or "grey (not reached)"))
  end
  -- 3. the dead columns and row 27
  for y = 17, 25, 2 do
    for x = 12, 15 do
      H.assertEq(cell(x, y) ~= CH_COLON and cell(x, y) ~= CH_PCT, true,
        string.format("%s: no learn-rate colon or percent at {%d,%d}", tag, x, y))
    end
  end
  for x = 5, 27 do H.assertEq(cell(x, 27), BLANK, string.format("%s: row 27 blank at {%d,27}", tag, x)) end
end

local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return st() == ST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if ph >= 4 then H.setPad({}); return end
      local target
      for r = 0, 26 do if H.readByte(GENJULIST + r) == idx then target = r; break end end
      if not target then H.setPad({}); return end
      local row = H.readByte(ZCURSOR)
      local d = target - row
      if d % 2 ~= 0 then
        if row % 2 == 0 then H.setPad(row >= 26 and { up = true } or { right = true })
        else H.setPad({ left = true }) end
      else
        H.setPad(d > 0 and { down = true } or { up = true })
      end
    end),
    H.waitFrames(1),
  }, what)
end

local function visit(e, tag)
  return H.seqStep({
    listSeek(e, tag .. ": cursor on the stone"),
    H.driveUntil(function() return st() == ST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, tag .. ": the detail page"),
    H.waitFrames(30),
    H.call(function() checkPage(e, tag); H.screenshot("esperdetail_" .. tag) end),
    H.driveUntil(function() return st() == ST_LIST end, 600,
      { H.pressButtons({ "b" }, 3), H.waitFrames(12) }, tag .. ": back on the list"),
  })
end

local owned = {}
H.run({ maxFrames = 60000 }, {
  H.bootCheckpoint("fire-out-v1"),
  H.call(function()
    leader = leaderOf()
    H.assertEq(leader ~= nil and leader < 12, true, "a leader who can wear stones")
    for e = 0, 26 do
      if (H.readByte(ESPERS + (e >> 3)) >> (e & 7)) & 1 == 1 then owned[#owned + 1] = e end
    end
    H.assertEq(#owned >= 2, true, "the save owns stones to visit")
    H.assertEq(sramW(LIVE), 0x3145, "the live esper page is signed")
  end),
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2), H.waitFrames(6), H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function() H.assertEq(H.readByte(SKILLCOLOR), 0x20, "Espers row enabled") end),
  H.driveUntil(function() return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0 end, 600,
    { H.pressButtons({ "up" }, 2), H.waitFrames(6) }, "cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "esper list", 5),
  H.lazy(function()
    local steps = {}
    for _, e in ipairs(owned) do steps[#steps + 1] = visit(e, "e" .. e) end
    return H.seqStep(steps)
  end),
  -- the white branch, staged (see the header)
  H.call(function()
    local e = owned[1]
    local a = LIVE + 0x10 + (leader * 26 + slotOf(e)) * 2
    emu.write(a, 200 & 0xFF, emu.memType.snesMemory)
    emu.write(a + 1, 200 >> 8, emu.memType.snesMemory)
  end),
  H.lazy(function() return visit(owned[1], "staged_rank4") end),
  H.call(function()
    H.assertEq(rankOf(points(owned[1])), 4, "the staged count reads rank 4")
    H.log("[detail] PASS: every owned stone's page shows the leader's rank, points and five rungs")
  end),
})
