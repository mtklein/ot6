-- gen_mrf_kefka.lua -- mrf_263 (map 263, {22,18}) -> the {24,18} ride
-- down to {40,30} -> the {40,32} trigger -> Kefka's esper-drain scene ->
-- $005F=1.  Generates mrf_kefka.mss.
--
-- {24,18}'s trigger is ungated and rides the party down to {40,30}.  The
-- trigger row {40,32}/{41,32}/{42,32} is guarded `if_switch $005F=1,
-- EventReturn` and falls into the scene where Kefka drains the espers,
-- ending with $005F=1.
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

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/mrf_263.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 263, "booted on map 263")
    H.assertEq(H.fieldX(), 22, "boot x")
    H.assertEq(H.fieldY(), 18, "boot y")
    H.assertEq(sw(0x005F), 0, "$005F CLEAR at boot")
    H.assertEq(H.bfsPath(40, 32), nil,
      "CONTROL: the Kefka trigger row (40,32) is NO-PATH on foot from here")
    H.log(partyReport("mrf_263"))
  end),

  H.openChest{ stand = { 15, 55 }, face = "left", bit = 89,
               what = "Gold Helmet", nav = { playBattles = "flee" } },
  H.openChest{ stand = { 33, 57 }, face = "left", bit = 93,
               what = "Gold Armor", nav = { playBattles = "flee" } },
  H.openChest{ stand = { 43, 46 }, face = "left", bit = 92,
               what = "Tent", nav = { playBattles = "flee" } },

  -- 1. two steps east onto {24,18} -> the ride -> {40,30}
  H.navTo(23, 18, { maxFrames = 12000, playBattles = "flee" }),
  tapInto("right", function() return H.fieldX() == 40 and H.fieldY() == 30 end,
    12000, "RIGHT onto {24,18} -> the ride -> (40,30)"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 263, "still on map 263 after the ride")
    H.assertEq(H.fieldX(), 40, "ride exit x (_cc75d0 pos {40,26} + DOWN 4)")
    H.assertEq(H.fieldY(), 30, "ride exit y")
    H.log(string.format("[ride] landed at (%d,%d)", H.fieldX(), H.fieldY()))
    census("after the ride", {
      { 40, 32, "the Kefka trigger row _cc7431" },
      { 37, 44, "the chute to map 264 _cc7581" },
      { 42, 41, "_cc78e0 lift" },
      { 49, 48, "_cc7905" },
      { 24, 18, "back to the ride" },
    })
    H.screenshot("mrf_ride")
  end),

  -- 2. south onto the trigger row -> the esper-drain scene -> $005F=1
  tapInto("down", function() return sw(0x005F) == 1 end, 20000,
    "DOWN onto {40,32} -> Kefka drains the espers -> $005F"),
  H.waitUntil(settled, 6000, "control back after the esper drain", 5),
  H.waitFrames(90),

  H.call(function()
    H.assertEq(map(), 263, "still on map 263 after the scene")
    H.assertEq(sw(0x005F), 1, "$005F SET -- Kefka has drained the espers")
    H.log(string.format("[mrf_kefka] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("mrf_kefka"))
    H.screenshot("mrf_kefka")
  end),
  H.saveState("mrf_kefka.mss"),

  H.call(function()
    census("mrf_kefka", {
      { 36, 44, "the chute to map 264 _cc7565" },
      { 37, 44, "_cc7581" },
      { 38, 44, "_cc7573" },
      { 42, 41, "_cc78e0 lift" },
      { 49, 48, "_cc7905" },
      { 40, 32, "the Kefka row (now inert, $005F=1)" },
    })
  end),
  H.logStep(function()
    return string.format("mrf_kefka generated at frame %d -- map 263 (%d,%d), $005F=1",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
