-- gen_minecart_entry.lua -- esper_tubes (map 274 {10,12}, $0068=1, LOCKE
-- alone) -> the lift trigger {20,13} -> map 266 -> Cid's "I'm going to
-- talk to the Emperor" scene -> map 272 {8,46} -> parked beside CID, one
-- A-press from the minecart.  Generates minecart_entry.mss.
--
-- The lift trigger is gated only on $0068=1.  It rides down, plays Cid's
-- decision, and lands on the minecart platform (map 272), which carries a
-- save point on {3,55}.

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
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

-- Exact single-tile stepping.
local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hold off while a scene controls
-- it, edge-A through dialogs.  Used to walk into a trigger whose scene then
-- takes over; the tap keeps the party from sliding past the tile.
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
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- Stop tapping once the party is on the target tile: the
        -- terminator needs 16 consecutive calm frames there, and a
        -- further tap would walk off it before the count completes.
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

local cid = nil
local verifyReq, verifyLoad = nil, nil

-- every tile the object map says is occupied inside a window
local function objDump(x0, x1, y0, y1, tag)
  local hits = {}
  for y = y0, y1 do
    for x = x0, x1 do
      if (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0 then
        hits[#hits + 1] = string.format("(%d,%d)", x, y)
      end
    end
  end
  H.log(string.format("[objects %s] occupied tiles in x %d..%d y %d..%d: %s",
    tag, x0, x1, y0, y1,
    #hits > 0 and table.concat(hits, " ") or "none"))
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/esper_tubes.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 274, "booted on map 274")
    H.assertEq(sw(0x0068), 1, "$0068 SET at boot")
    H.assertEq(sw(0x02F6), 0, "$02F6 CLEAR at boot -- CELES is gone")
    H.log(partyReport("esper_tubes"))
  end),

  H.navTo(20, 12, { maxFrames = 15000, playBattles = "tactical", arrive = function() return map() ~= 274 end }),
  tapInto("down", function() return map() ~= 274 end, 9000,
    "DOWN onto {20,13} -> the lift"),
  H.waitUntil(function() return map() == 272 end, 20000, "map 272 (the minecart platform)", 5),
  H.waitUntil(function() return map() == 272 and settled() end, 12000,
    "map 272 control", 5),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 272, "the minecart platform is map 272")
    H.assertEq(sw(0x0644), 1, "$0644 SET -- CID is on the platform")
    H.assertEq(sw(0x02BC), 0, "$02BC CLEAR -- the cutscene has not started")
    H.log(string.format("[272] control at (%d,%d) face=%d",
      H.fieldX(), H.fieldY(), H.readByte(0x087f + H.readWord(0x0803))))
    objDump(0, 20, 40, 60, "map 272")
    census("272", {
      { 3, 55, "the SAVE POINT" },
      { 9, 46, "CID after _cc7f43's reposition" },
      { 9, 51, "CID's npc_prop home tile" },
      { 8, 46, "the landing tile" },
    })
    H.log(partyReport("minecart platform"))
    H.screenshot("minecart_platform")
  end),

  H.navTo(4, 55, { maxFrames = 9000, playBattles = "tactical", careThreshold = 0.85, healPercent = 45, magic = { [6] = { spell = 2 } }, summon = { [6] = {} } }),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.fieldX() == 3 and H.fieldY() == 55 and sw(0x01BF) == 1
              and H.tileAligned() and not H.dialogWaiting()
              and not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        if H.dialogWaiting() then H.setPad({ "a" }); return end
        if H.fieldX() == 3 and H.fieldY() == 55 then H.setPad({}); return end
        H.setPad({ left = true })
      end),
    }, "onto the save tile 272 (3,55)")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the save-enable flow ran")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    H.assertExitContractPreSave("minecart-platform-v1")
    H.screenshot("minecart_save_point")
  end),

  -- 2. park beside CID.  His {9,51} is occupied by his own object, so the
  --    entry point is whichever of its four neighbours the live object
  --    map and tilemap leave open, resolved here rather than assumed.
  H.call(function()
    for _, c in ipairs({ { 9, 52, "up", 0 }, { 8, 51, "right", 1 },
                         { 10, 51, "left", 3 }, { 9, 50, "down", 2 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("[cid approach] (%d,%d) facing %s : %s",
        c[1], c[2], c[3], p and (#p .. " steps") or "NO PATH"))
      if p and not cid then cid = c end
    end
    assert(cid, "no reachable tile adjacent to CID at (9,51)")
    H.log(string.format("[cid approach] chose (%d,%d) facing %s",
      cid[1], cid[2], cid[3]))
  end),
  H.navTo(function() return cid[1] end, function() return cid[2] end,
    { maxFrames = 9000, playBattles = "tactical", careThreshold = 0.85, healPercent = 45, magic = { [6] = { spell = 2 } }, summon = { [6] = {} } }),   -- beside CID
  (function() local calm = 0
    return H.driveUntil(function()
      local ok = H.fieldX() == cid[1] and H.fieldY() == cid[2] and settled()
             and H.readByte(0x087f + H.readWord(0x0803)) == cid[4]
      calm = ok and calm + 1 or 0
      if calm >= 20 then H.setPad({}); return true end
      return false
    end, 4000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= cid[4] then
          H.setPad({ [cid[3]] = true })
        else
          H.setPad({})
        end
      end) }, "twenty settled frames facing CID")
  end)(),

  H.call(function()
    H.assertEq(map(), 272, "on map 272")
    H.assertEq(H.fieldX(), cid[1], "CID entry point x")
    H.assertEq(H.fieldY(), cid[2], "CID entry point y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), cid[4],
      "facing CID at (9,51)")
    H.assertEq(settled(), true, "the entry point is QUIET")
    H.assertEq(sw(0x02BC), 0, "$02BC CLEAR -- `cutscene TRAIN` has not run")
    H.assertEq(sw(0x0069), 0, "$0069 CLEAR -- the escape has not happened")
    H.log(string.format("[minecart_entry] f%d map=%d (%d,%d) face=%d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803))))
    H.log(partyReport("minecart_entry"))
    H.screenshot("minecart_entry")
  end),
  H.saveState("minecart_entry.mss"),
  -- Reload-verified: a calm capture does not imply a calm reload, so
  -- reload the parked moment and require it quiet.
  H.call(function() verifyReq = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(verifyReq, "generated-state verify: capture")
    verifyLoad = H.requestLoadState(verifyReq.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(verifyLoad, "generated-state verify: reload") end),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 272, "reload: still on map 272")
    H.assertEq(H.fieldX() == cid[1] and H.fieldY() == cid[2], true,
      "reload: still parked beside CID")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), cid[4],
      "reload: still facing CID")
    H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "reload: controllable at rest")
    H.assertEq(sw(0x02BC), 0, "reload: $02BC still CLEAR")
    H.log("generated-state verify: the reload stayed calm -- minecart_entry verified")
  end),
  H.logStep(function()
    return string.format("minecart_entry generated at frame %d -- map 272 "
      .. "(%d,%d) facing CID, one A-press from `cutscene TRAIN`",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
