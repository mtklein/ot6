-- probe_banquet_castle.lua -- I->J leg development (issue #31): the LIVE
-- castle census with the window OPEN, from banquet_window.mss.
--
-- WHY THIS EXISTS: the pre-banquet census (probe_banquet_interior) found
-- the 250 entry to be a 131-tile pocket with the west and east columns
-- severed at (16,30) and (30,30).  Those two tiles carry the $0630
-- "Emperor Gestahl waits inside" servant NPCs, and _cc8490 clears $0630
-- one line before it sets $007C (event_main.asm:97415) -- so the castle
-- opens exactly when the window starts, and every route census taken
-- before the dais is worthless for the circuit.  This probe measures the
-- component the CIRCUIT actually runs in.
--
-- Also measures the WINDOW BUDGET directly: the timer at boot, and the
-- timer after a single measured soldier talk, which is the per-soldier
-- cost the ≥90 feasibility verdict is built from.
--
--   tools/tests/run.sh tools/tests/probe_banquet_castle.lua
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function timerCount() return H.readWord(0x1189) end
local function var0() return H.readWord(0x1fc2) end

local function floodDump(tag)
  return H.call(function()
    local MOVES = { "up", "right", "down", "left",
                    "upright", "downright", "downleft", "upleft" }
    local D = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
                left = { -1, 0 }, upright = { 1, -1 },
                downright = { 1, 1 }, downleft = { -1, 1 },
                upleft = { -1, -1 } }
    local sx, sy = H.fieldX(), H.fieldY()
    local seen = { [sy * 256 + sx] = true }
    local q, qi = { { sx, sy } }, 1
    while qi <= #q and #q < 6000 do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for _, m in ipairs(MOVES) do
        if H.canStep(x, y, m) then
          local nx, ny = x + D[m][1], y + D[m][2]
          local k = ny * 256 + nx
          if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
        end
      end
    end
    local minx, maxx, miny, maxy = 999, 0, 999, 0
    for k in pairs(seen) do
      local y, x = k >> 8, k & 0xFF
      if x < minx then minx = x end
      if x > maxx then maxx = x end
      if y < miny then miny = y end
      if y > maxy then maxy = y end
    end
    H.log(string.format(
      "== flood [%s] map %d from (%d,%d): %d tiles, x %d..%d y %d..%d ==",
      tag, map(), sx, sy, #q, minx, maxx, miny, maxy))
  end)
end

-- every circuit goal, as the ADJACENT tile a talk is issued from (the
-- soldier itself stands on its tile and blocks it)
local GOALS = {
  { 21, 25, "250 hall SW (21,24)" }, { 25, 25, "250 hall SE (25,24)" },
  { 21, 19, "250 hall NW (21,18)" }, { 25, 19, "250 hall NE (25,18)" },
  { 15, 21, "250 stairs (15,21) -> (24,52)" },
  { 31, 21, "250 stairs (31,21) -> (81,59)" },
  { 23, 9, "250 stairs (23,9) -> (54,34)" },
  { 9, 14, "250 door (9,14) -> 252" },
  { 37, 14, "250 stairs (37,14) -> (101,16)" },
  { 9, 9, "250 stairs (9,9) -> (14,60)" },
  { 37, 9, "250 stairs (37,9) -> (60,61)" },
  { 53, 9, "250 door (53,9) -> 251" },
  { 101, 10, "250 stairs (101,10) -> (120,23)" },
  { 115, 22, "250 stairs (115,22) -> (97,49)" },
  { 97, 47, "250 stairs (97,47) -> (115,21)" },
  { 51, 53, "250 door (51,53) -> 252" },
  { 9, 52, "250 door (9,52) -> 244" },
  { 65, 53, "250 door (65,53) -> 244" },
  { 54, 16, "250 the dais" },
  { 22, 34, "250 exit row -> 243" },
  { 23, 12, "250 messenger tile" },
  { 9, 50, "250 (9,49) soldier adj" },
  { 52, 50, "250 (51,50) BATTLE 27 adj" },
  { 97, 51, "250 (98,51) soldier adj" },
  { 109, 51, "250 (110,51) BATTLE 27 adj" },
  { 115, 17, "250 (115,16) soldier adj" },
  { 119, 13, "250 (120,13) soldier adj" },
}

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        for sl = 0, 5 do
          if H.readByte(0x3aa8 + sl * 2) % 2 == 1 then
            H.writeByte(0x3eec + sl * 2, H.readByte(0x3eec + sl * 2) | 0x80)
          end
        end
        H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function census(tag)
  return H.call(function()
    H.log(string.format("== census [%s] map %d from (%d,%d) timer=%d ==",
      tag, map(), H.fieldX(), H.fieldY(), timerCount()))
    for _, t in ipairs(GOALS) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[%s] (%3d,%3d) %-34s %s", tag, t[1], t[2], t[3],
        p and ("reach " .. #p) or "NO"))
    end
  end)
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/banquet_window.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x007C), 1, "boot: window live")
    H.assertEq(sw(0x013C), 0, "boot: dinner not fired")
    H.log(string.format("[boot] map=%d (%d,%d) timer=%d var0=%d "
      .. "$0630=%d $0634=%d",
      map(), H.fieldX(), H.fieldY(), timerCount(), var0(),
      sw(0x0630), sw(0x0634)))
  end),
  floodDump("tower"),
  census("tower"),

  -- MEASURED (this probe, run 1): control returns INSIDE the throne
  -- tower -- a 199-tile pocket, x48..60 y9..35 -- whose only ways out are
  -- the (53,9)/(55,9) doors to 251 and the (53,35) len-3H long entrance
  -- back to the corridor at (23,11).  The circuit therefore starts by
  -- leaving the tower southward.
  H.navTo(53, 34, { maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldX() < 40 and H.tileAligned()
  end, 1200, "held DOWN onto (53,35) -> the corridor (23,11)"),
  H.release(),
  H.waitFrames(45),
  H.call(function()
    H.log(string.format("[tower-exit] now at (%d,%d) timer=%d",
      H.fieldX(), H.fieldY(), timerCount()))
  end),
  floodDump("corridor-open"),
  census("corridor-open"),

  -- ---- the per-soldier COST measurement, the feasibility input ------------
  -- walk to the nearest hall soldier and talk: frames from control to
  -- latch, which is what 24 of must fit in 14400.
  H.call(function()
    H.log(string.format("[cost] before: timer=%d frame=%d",
      timerCount(), H.frame))
  end),
  H.chaseTalk(0x13, 4000, "250 (25,18) talk [cost sample 1]", {
    done = function() return sw(0x021A) == 1 or sw(0x013C) == 1 end,
  }),
  H.call(function()
    H.log(string.format("[cost] after 1 talk: timer=%d var0=%d frame=%d",
      timerCount(), var0(), H.frame))
  end),
  H.chaseTalk(0x12, 4000, "250 (21,18) talk [cost sample 2]", {
    done = function() return sw(0x0219) == 1 or sw(0x013C) == 1 end,
  }),
  H.call(function()
    H.log(string.format("[cost] after 2 talks: timer=%d var0=%d frame=%d",
      timerCount(), var0(), H.frame))
  end),
  H.chaseTalk(0x10, 4000, "250 (21,24) talk [cost sample 3]", {
    done = function() return sw(0x0217) == 1 or sw(0x013C) == 1 end,
  }),
  H.chaseTalk(0x11, 4000, "250 (25,24) talk [cost sample 4]", {
    done = function() return sw(0x0218) == 1 or sw(0x013C) == 1 end,
  }),
  H.call(function()
    H.log(string.format(
      "[cost] after 4 hall talks: timer=%d var0=%d frame=%d "
      .. "(consumed %d timer ticks)",
      timerCount(), var0(), H.frame, 14400 - timerCount()))
    H.screenshot("bq_castle_after4")
  end),
  H.saveState("banquet_hall4.mss"),
  census("after-4-talks"),
})
