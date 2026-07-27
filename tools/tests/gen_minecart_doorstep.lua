-- gen_minecart_doorstep.lua -- v0.6 leg 12: esper_tubes (map 274 {10,12},
-- $0068=1, LOCKE alone) -> the lift trigger {20,13} -> map 266 -> Cid's
-- "I'm going to talk to the Emperor" scene -> map 272 {8,46} -> parked
-- beside CID, one A-press from the minecart.  Mints minecart_doorstep.
--
-- _cc7f43 (event_main.asm:96313) is gated only on `$0068=1`, which leg 11
-- banked, so walking onto {20,13} is enough.  It rides the lift down
-- (`load_map 266, {7,0}`, :96341), plays Cid's decision (dlg $057E) and
-- ends `load_map 272, {8,46}, RIGHT` + `player_ctrl_on` (:96406-96457) --
-- the minecart platform, which carries a SAVE POINT on {3,55}
-- (event_trigger.asm:1211, npc_prop.asm:12434).
--
-- THE MINECART IS LAUNCHED BY TALKING TO CID, not by a trigger.  Map 272's
-- ONLY event trigger is the save point; the ride hangs off NPC_1, CID at
-- {9,51} behind switch $0644 with event _cc8022 (npc_prop.asm:12419 ->
-- event_main.asm:96463), whose tail is
--     switch $02BC=1 / cutscene TRAIN / call _ca5ea9 / ...
--     load_map 240, {64,13}
-- (:96579-96586).  This leg banks the doorstep in front of him and dumps
-- the live object map so the parking tile is measured rather than read off
-- an obj_script.
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

-- Exact single-tile stepping (see gen_vector_sneak.lua for the measurement).
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


local cid = nil

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

  -- 1. onto {20,13} -> the lift -> map 266 -> map 272.
  --    The trigger is stepped onto with an explicit DOWN tap rather than a
  --    navTo whose goal IS the trigger tile: navTo terminates on the party
  --    coming to rest, and a tile that loads a map is one it never rests
  --    on.  (Before #22 this leg had a second reason -- a downward navTo
  --    step overshot by a tile, so navTo "arrived" at {20,13} from {20,14}
  --    and the map never changed, measured at 219 frames.  That half is
  --    fixed in the library now; the doorstep-then-tap shape is not a
  --    workaround, it is how a trigger tile is entered.)
  H.navTo(20, 12, { maxFrames = 15000, arrive = function() return map() ~= 274 end }),
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

  -- 2. park beside CID.  His {9,51} is occupied by his own object, so the
  --    doorstep is whichever of its four neighbours the live object map and
  --    tilemap leave open -- resolved here rather than read off an
  --    obj_script, because _cc7f43's tail repositions him and the recon's
  --    {9,46} is NO PATH from the landing.
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
    { maxFrames = 9000 }),                 -- beside CID
  (function() local calm = 0
    return H.driveUntil(function()
      local ok = H.fieldX() == cid[1] and H.fieldY() == cid[2] and settled()
             and H.readByte(0x087f + H.readWord(0x0803)) == cid[4]
      calm = ok and calm + 1 or 0
      if calm >= 20 then H.setPad({}); return true end
      return false
    end, 4000, {
      H.call(function()
        if H.battleLoadStarted() then killBitAll(); H.setPad({ "a" }); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= cid[4] then
          H.setPad({ [cid[3]] = true })
        else
          H.setPad({})
        end
      end) }, "twenty settled frames facing CID")
  end)(),

  H.call(function()
    H.assertEq(map(), 272, "on map 272")
    H.assertEq(H.fieldX(), cid[1], "CID doorstep x")
    H.assertEq(H.fieldY(), cid[2], "CID doorstep y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), cid[4],
      "facing CID at (9,51)")
    H.assertEq(settled(), true, "the doorstep is QUIET")
    H.assertEq(sw(0x02BC), 0, "$02BC CLEAR -- `cutscene TRAIN` has not run")
    H.assertEq(sw(0x0069), 0, "$0069 CLEAR -- the escape has not happened")
    H.log(string.format("[minecart_doorstep] f%d map=%d (%d,%d) face=%d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803))))
    H.log(partyReport("minecart_doorstep"))
    H.screenshot("minecart_doorstep")
  end),
  H.saveState("minecart_doorstep.mss"),
  H.logStep(function()
    return string.format("minecart_doorstep minted at frame %d -- map 272 "
      .. "(%d,%d) facing CID, one A-press from `cutscene TRAIN`",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
