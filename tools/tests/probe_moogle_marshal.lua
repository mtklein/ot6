-- probe_moogle_marshal.lua -- how close does the honest Marshal fight get,
-- and what honest levers remain?  (issue #75, marshal-investigation)
--
-- probe_moogle_stations (plain tap-A) and probe_moogle_boosted (naive
-- R/A/A) both cleared the six waves 2-2-2 and then LOST battle 6 with P2
-- around 330-364/543.  This run replays the stations plan and then
-- instruments the Marshal fight: party HP and monster HP (battle HP
-- table slots 4..9) every 240 frames, so the loss (or win) carries its
-- margin.  It also dumps the party's item inventory at defense-live --
-- if the players are carrying Tonics/Potions, menu healing before the
-- fight is an honest lever this route has not pulled yet.  The battle
-- driver here presses R once per ~half-second and A thrice, a gentler
-- boost cadence than probe_moogle_boosted's.  Zero writes.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local PARTY = {
  [1] = { 1, 2, 3, 4 },
  [2] = { 10, 5, 6, 7 },
  [3] = { 8, 9, 11, 12 },
}
local LEADER_OFF = { [1] = 0x0029, [2] = 0x019A, [3] = 0x0148 }

local function poolOf(p)
  local cur, max = 0, 0
  for _, c in ipairs(PARTY[p]) do
    cur = cur + H.readWord(0x1609 + 37 * c)
    max = max + (H.readWord(0x160b + 37 * c) & 0x3fff)
  end
  return cur, max
end

local function logPools(tag)
  return H.call(function()
    local s = {}
    for p = 1, 3 do
      local c, m = poolOf(p)
      s[#s + 1] = string.format("P%d %d/%d", p, c, m)
    end
    H.log(string.format("%s f%d pools: %s $1F41=%02X", tag, H.frame,
      table.concat(s, "  "), H.readByte(0x1f41)))
  end)
end

local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
end

local function plainDrive(pred, maxFrames, what)
  local phase, battN, dlgN = 0, 0, 0
  return H.driveUntil(function()
    local done = pred()
    if done then H.setPad({}) end
    return done
  end, maxFrames, {
    H.call(function()
      phase = (phase + 1) % 8
      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 or dlgN >= 3 then
        H.setPad(phase < 4 and { "a" } or {})
      else
        H.setPad({})
      end
    end),
  }, what)
end

local MX, MY = 15, 40
local aPhase = 0
local function defenseWon()
  return (H.readByte(0x1f46) & 0x02) == 0
end
local function marshalAdjacent()
  local dx, dy = MX - H.fieldX(), MY - H.fieldY()
  return math.abs(dx) + math.abs(dy) == 1
end
local function pokeStep()
  local battN = 0
  return H.driveUntil(function()
    battN = (H.battleLoadStarted() and H.monstersPresent() > 0)
        and battN + 1 or 0
    return defenseWon() or battN >= 3
  end, 900, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if not (H.hasControl() and marshalAdjacent()) then H.setPad({}); return end
      local dx, dy = MX - H.fieldX(), MY - H.fieldY()
      local dir = dx == 1 and "right" or dx == -1 and "left"
               or dy == 1 and "down" or "up"
      if aPhase < 2 then H.setPad({ [dir] = true })
      elseif aPhase < 6 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
  }, "battle 6 engages")
end

-- the instrumented Marshal driver: gentle boost cadence + HP telemetry.
-- Runs until the battle module is gone AND stays gone 240 frames (a wipe
-- zeroes the HP table early -- the debounce keeps telemetry flowing
-- through the Annihilated screen so the ending is on the record).
local function marshalFight(maxFrames)
  local phase, calm, tel = 0, 0, 0
  return H.driveUntil(function()
    calm = (not H.battleLoadStarted()) and calm + 1 or 0
    return defenseWon() or calm >= 240
  end, maxFrames, {
    H.call(function()
      phase = (phase + 1) % 32
      tel = tel + 1
      if tel % 240 == 0 then
        local hp = H.partyHp()
        local m = {}
        for i = 4, 9 do m[#m + 1] = tostring(H.readWord(0x3BF4 + i * 2)) end
        H.log(string.format("m6 f%d party %d/%d/%d/%d mons %s",
          H.frame, hp[1], hp[2], hp[3], hp[4], table.concat(m, "/")))
      end
      -- A on anything that is not a live battle (dialogs, Annihilated)
      if not H.battleLoadStarted() then
        H.setPad(phase % 8 < 4 and { "a" } or {})
        return
      end
      if phase < 4 then H.setPad({ "r" })
      elseif phase < 6 then H.setPad({})
      elseif phase < 10 then H.setPad({ "a" })
      elseif phase < 12 then H.setPad({})
      elseif phase < 16 then H.setPad({ "a" })
      elseif phase < 18 then H.setPad({})
      elseif phase < 22 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
  }, "Marshal fight (instrumented)")
end

H.run({ maxFrames = 140000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  logPools("boot"),
  -- inventory at defense-live: item ids $1869+i, counts $1969+i
  H.call(function()
    local n = 0
    for i = 0, 254 do
      local id = H.readByte(0x1869 + i)
      local qty = H.readByte(0x1969 + i)
      if id ~= 0xFF and qty > 0 then
        H.log(string.format("item slot %d: id=%02X qty=%d", i, id, qty))
        n = n + 1
      end
    end
    H.log("inventory: " .. n .. " occupied slots")
  end),

  -- stations deployment (east first), plain tap-A storm
  H.navTo(15, 15, { maxFrames = 2500, honest = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, honest = true }),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, honest = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, honest = true }),
  logPools("deployed"),
  plainDrive(function()
    return (H.readByte(0x1f41) & 0xFC) == 0
  end, 60000, "all six waves"),
  logPools("waves complete"),

  ySwitchTo(2),
  H.navTo(MX, MY - 1, {
    arrive = function()
      return defenseWon()
          or (marshalAdjacent() and H.hasControl() and H.tileAligned())
    end,
    maxFrames = 15000, honest = true,
  }),
  logPools("pre-marshal"),
  pokeStep(),
  marshalFight(30000),
  H.call(function()
    H.log(string.format("marshal outcome: defenseWon=%s at f%d",
      tostring(defenseWon()), H.frame))
  end),
  logPools("aftermath"),
})
