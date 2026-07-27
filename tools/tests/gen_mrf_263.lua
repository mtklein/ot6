-- gen_mrf_263.lua -- v0.6 leg 5: mrf_chute (MAGITEK FACTORY map 262,
-- {10,45}) -> the RIGHT conveyor at {11,45} -> {20,45} -> the scripted
-- transition at {22,53} -> map 263, the factory's lower floor.  Mints
-- mrf_263.
--
-- MEASURED at (10,45) (census in gen_mrf_chute's log): 123 tiles reachable,
-- and of every waypoint the route needs only two are among them --
-- {11,45} (_cc78d0, 1 step) and {6,31} (_cc76a7, the lift back UP, 18
-- steps).  {22,53}, {22,54}, {10,54}, {12,60}, {15,60}, {21,27}, {4,22}
-- and {9,22} are all NO PATH.  So the lower half of map 262 is a chain of
-- scripted rides, exactly as docs/design/vector-route-recon.md §8 hazard 3
-- predicted, and this leg rides the next link.
--
-- _cc78d0 (event_main.asm:95182), on {11,45}, is ungated -- no $01B5
-- latch, no facing gate -- and runs
--     layer 2 / speed FAST / move RIGHT 8 / jump_low / move RIGHT 1 / layer 0
-- i.e. {11,45} -> {20,45}, then `player_ctrl_on`.
--
-- _cc7651 (event_main.asm:94789), on {22,53}, walks SLOT_1 DOWN_LEFT and
-- falls into _cc7666 (:94805), which walks it further and then
-- `load_map 263, {16,9}, DOWN, STARTUP_EVENT` before walking it again on
-- the new map: DOWN 6 -> {16,15}, RIGHT 3 -> {19,15}, DOWN_RIGHT 2 ->
-- {21,17}, jump_low DOWN_RIGHT -> {22,18}, `player_ctrl_on`.  So the
-- expected landing is map 263 at {22,18}; the assertion below is the first
-- live confirmation of that read.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hands off while a scene owns
-- it, edge-A through dialogs.  Used to walk INTO a trigger whose scene then
-- takes over -- the tap keeps the party from sliding past the tile.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- STOP TAPPING once we are where we were going.  The terminator
        -- wants 16 consecutive calm frames on the target, and an eager tap
        -- walks straight off it before the count gets there: the first
        -- version of this rode the chute correctly to (10,45) and then
        -- tapped itself to (10,46) and timed out.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end


H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/mrf_chute.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK FACTORY", "booted in the MAGITEK FACTORY")
    H.assertEq(map(), 262, "booted on map 262")
    H.assertEq(H.fieldX(), 10, "boot x -- below the chute")
    H.assertEq(H.fieldY(), 45, "boot y")
    -- Positive control: the conveyor's landing tile and the {22,53}
    -- transition must both be NO-PATH on foot right now.  If either ever
    -- becomes walkable this leg is walking a route it claims to ride.
    H.assertEq(H.bfsPath(20, 45), nil,
      "CONTROL: (20,45) is NO-PATH on foot -- the {11,45} conveyor is the way across")
    H.assertEq(H.bfsPath(22, 53), nil,
      "CONTROL: (22,53) is NO-PATH on foot from below the chute")
    H.log(partyReport("mrf_chute"))
  end),

  -- 1. one RIGHT step onto {11,45} -> the conveyor -> {20,45}
  tapInto("right", function() return H.fieldX() == 20 and H.fieldY() == 45 end,
    9000, "RIGHT onto the {11,45} conveyor -> (20,45)"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 262, "still on map 262 after the conveyor")
    H.assertEq(H.fieldX(), 20, "conveyor exit x (obj_script move list)")
    H.assertEq(H.fieldY(), 45, "conveyor exit y")
    H.log(string.format("[conveyor] landed at (%d,%d)", H.fieldX(), H.fieldY()))
    census("after the conveyor", {
      { 22, 53, "the scripted 263 transition _cc7651" },
      { 22, 54, "its twin _cc765f" },
      { 10, 54, "_cc7682 lift down" },
      { 12, 60, "short entrance -> 263 (12,7)" },
      { 15, 60, "long entrance -> 263 (15,9)" },
      { 21, 27, "_cc781b" },
      { 11, 45, "back onto the conveyor" },
    })
    H.screenshot("mrf_conveyor")
  end),

  -- 2. across to {22,52} and one tapped DOWN onto {22,53} -> map 263
  H.navTo(22, 52, { maxFrames = 20000,
    arrive = function() return map() == 263 end }),
  H.navTo(22, 52, { maxFrames = 9000 }),   -- above the 263 transition
  tapInto("down", function() return map() == 263 end, 12000,
    "DOWN onto {22,53} -> the scripted transition to map 263"),
  H.waitUntil(function() return map() == 263 and settled() end,
    9000, "map 263 control", 5),
  H.waitFrames(90),

  H.call(function()
    H.assertEq(map(), 263, "the factory lower floor is map 263")
    H.assertEq(H.fieldX(), 22, "263 landing x (_cc7666 obj_script)")
    H.assertEq(H.fieldY(), 18, "263 landing y")
    H.assertEq(sw(0x005F), 0, "$005F CLEAR -- Kefka's esper drain is still ahead")
    H.log(string.format("[mrf_263] f%d map=%d title=%q (%d,%d)",
      H.frame, map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.log(partyReport("mrf_263"))
    H.screenshot("mrf_263")
  end),
  H.saveState("mrf_263.mss"),

  H.call(function()
    census("mrf_263", {
      { 36, 44, "the chute to map 264 _cc7565" },
      { 37, 44, "_cc7581" },
      { 38, 44, "_cc7573" },
      { 40, 32, "_cc7431" },
      { 41, 32, "_cc73e1" },
      { 42, 32, "_cc7409" },
      { 24, 17, "_cc75bb" },
      { 24, 18, "_cc75c9" },
      { 42, 41, "_cc78e0 lift" },
      { 49, 48, "_cc7905" },
      { 12, 6, "short entrance -> 262 (12,59)" },
      { 18, 5, "long entrance -> 262 (11,61)" },
    })
  end),
  H.logStep(function()
    return string.format("mrf_263 minted at frame %d -- map 263 (%d,%d)",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
