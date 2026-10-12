-- @suite savestate=minecart_entry slow
-- battle_esperstats_wor.lua -- the twelve World of Ruin stones' while-worn
-- stat packages (#418), in battle.
--
-- Same instrument as battle_esperstats.lua and battle_esperstats_tube6.lua:
-- reload the fixture, equip stones through the real field menu
-- (H.equipEsper: Skills -> character -> Espers -> list -> detail -> A), ride
-- the minecart into its first scripted fight, and read the four battle-side
-- effective stats ($3b2c vigor*2, $3b19 speed, $3b40 stamina, $3b41
-- mag.pwr), which Ot6EsperStatMod bumps out of Ot6EsperStatTbl in
-- UpdateEquipBattle.  Each member's deltas are against the BASE ride for the
-- same character, with no stone worn.  Vigor is stored doubled, so an
-- authored +2 reads +4 and a -2 reads -4.
--
-- The packages asserted are docs/design/magicite.md's ("World of Ruin
-- Espers", the Stat vig/spd/stm/mag column), written out below rather than
-- read from the ROM, so a wrong row in the table fails here.
--
-- Isolation arm (declared in state_write_waivers.txt).  This fixture is in
-- the World of Balance, where the party owns none of the twelve, so one
-- write ORs their twelve bits into the owned-esper field $1A69..$1A6C; the
-- party's worn stones are bared as battle_esperstats_tube6 does, so BASE is
-- the no-stone state.  Everything after that is menu input: the bits only
-- put the stones on the list.  This is a mechanism test of the table's
-- twelve rows, not play: on the route, Palidor and Fenrir arrive in v0.27
-- and the rest later (magicite.md, "When each stone arrives").
--
-- The party is LOCKE, SABIN and EDGAR, so each ride carries three stones,
-- one per member: four rides cover the twelve.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/minecart_entry.mss.lua"

-- esper indices (GenjuProp order) and their packages: vig, spd, stm, mag
local PACKAGE = {
  [4]  = { "Terrato",  0, -3,  4,  6 },
  [9]  = { "Palidor",  2,  4,  0,  0 },
  [10] = { "Tritoch",  0,  3, -3,  7 },
  [11] = { "Odin",     4,  4, -2,  0 },
  [12] = { "Raiden",   6,  4, -3,  0 },
  [13] = { "Bahamut",  3,  0, -3,  7 },
  [14] = { "Alexandr", 4, -3,  6,  0 },
  [15] = { "Crusader", 3,  3,  3,  3 },
  [16] = { "Ragnarok", 5,  0, -3,  5 },
  [24] = { "Fenrir",   0,  6, -3,  4 },
  [25] = { "Starlet",  0,  4, -3,  6 },
  [26] = { "Phoenix", -2,  2,  6,  0 },
}
local RIDES = {
  { 9, 24, 4 },      -- the v0.27 pair, and Terrato (the old no-mod row)
  { 10, 11, 12 },
  { 13, 14, 15 },
  { 16, 25, 26 },
}

local ESPERS = 0x1a69            -- owned-esper bitfield, 27 bits
local STAM, MAGPWR, SPEED, VIGOR = 0x3b40, 0x3b41, 0x3b19, 0x3b2c
local function rec(c) return 0x1600 + 37 * c end
local ESPER_OFF = 0x1E

local function partyChars()
  local t, cur = {}, H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    if b ~= 0 and (b & 0x07) == cur then t[#t + 1] = c end
  end
  return t
end
local function posOf(c) return (H.readByte(0x1850 + c) >> 3) & 3 end
local function charAt(p)
  for _, c in ipairs(partyChars()) do
    if posOf(c) == p then return c end
  end
  return nil
end

local R = {}                     -- R[tag][char] = { stam, mag, spd, vig, worn }

local function rideAndMeasure(tag)
  return {
    H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(26),
    }, "A to CID -> the ride's first battle (" .. tag .. ")"),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle active (" .. tag .. ")", 30),
    H.waitFrames(240),
    H.call(function()
      R[tag] = {}
      for _, c in ipairs(partyChars()) do
        local t = nil
        for s = 0, 3 do
          if H.readByte(0x3ed8 + s * 2) == c then t = s end
        end
        H.assertEq(t ~= nil, true,
          string.format("[%s] char %d is in the battle", tag, c))
        R[tag][c] = {
          stam = H.readByte(STAM + t * 2),
          mag  = H.readByte(MAGPWR + t * 2),
          spd  = H.readByte(SPEED + t * 2),
          vig  = H.readByte(VIGOR + t * 2),
          worn = H.readByte(rec(c) + ESPER_OFF),
        }
        local r = R[tag][c]
        H.log(string.format("[%s] char %d slot=%d worn=$%02x stam=%d mag=%d spd=%d vig*2=%d",
          tag, c, t, r.worn, r.stam, r.mag, r.spd, r.vig))
      end
    end),
  }
end

local function driveSteps(tag, stones)
  local steps = {
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(function() return H.hasControl() end, 600,
      "field control (" .. tag .. ")", 5),
    -- the isolation arm (header): own the twelve, bare the party
    H.call(function()
      -- bits: 4 Terrato; 9..15; 16 Ragnarok; 24..26
      for i, m in ipairs({ 0x10, 0xFE, 0x01, 0x07 }) do
        H.writeByte(ESPERS + i - 1, H.readByte(ESPERS + i - 1) | m)
      end
      for _, c in ipairs(partyChars()) do
        local worn = H.readByte(rec(c) + ESPER_OFF)
        if worn ~= 0xff then
          H.writeByte(rec(c) + ESPER_OFF, 0xff)
          H.log(string.format("[%s] char %d wore stone $%02X -> bared for the measure",
            tag, c, worn))
        end
      end
      H.log(string.format("[%s] [isolation arm] $1a69 = %02x %02x %02x %02x", tag,
        H.readByte(ESPERS), H.readByte(ESPERS + 1), H.readByte(ESPERS + 2),
        H.readByte(ESPERS + 3)))
      H.assertEq(#partyChars(), 3, "[" .. tag .. "] the party is three (LOCKE SABIN EDGAR)")
    end),
  }
  for p, e in ipairs(stones or {}) do
    steps[#steps + 1] = H.equipEsper(p - 1, e,
      { tag = string.format("%s: %s -> pos %d", tag, PACKAGE[e][1], p - 1) })
  end
  steps[#steps + 1] = H.call(function()
    for p, e in ipairs(stones or {}) do
      local c = charAt(p - 1)
      H.assertEq(H.readByte(rec(c) + ESPER_OFF), e,
        string.format("[%s] char %d (pos %d) wears %s", tag, c, p - 1, PACKAGE[e][1]))
    end
  end)
  for _, s in ipairs(rideAndMeasure(tag)) do steps[#steps + 1] = s end
  return steps
end

local function checkRide(tag)
  return H.call(function()
    local b, r = R.base, R[tag]
    for c, m in pairs(r) do
      local pk = PACKAGE[m.worn]
      H.assertEq(pk ~= nil, true,
        string.format("[%s] char %d wears one of the twelve ($%02x)", tag, c, m.worn))
      local want = { vig = 2 * pk[2], spd = pk[3], stam = pk[4], mag = pk[5] }
      for _, k in ipairs({ "vig", "spd", "stam", "mag" }) do
        H.assertEq(m[k], b[c][k] + want[k], string.format(
          "[%s] %s on char %d: %s %d -> %d (want %+d)",
          tag, pk[1], c, k, b[c][k], m[k], want[k]))
      end
      H.log(string.format("[%s] %s: vig*2 %+d spd %+d stm %+d mag %+d -- as planned",
        tag, pk[1], m.vig - b[c].vig, m.spd - b[c].spd, m.stam - b[c].stam,
        m.mag - b[c].mag))
    end
  end)
end

-- ------------------------------------------------------------- compose run --
local all = { H.waitFrames(20) }
local function add(list) for _, s in ipairs(list) do all[#all + 1] = s end end

add(driveSteps("base", nil))
add({ H.call(function()
  for c, m in pairs(R.base) do
    H.assertEq(m.worn, 0xff, string.format("[base] char %d wears no stone", c))
    -- the 0..255 clamp must not touch a delta: no base under 8, no vigor*2
    -- over 255 - 2*6
    for _, k in ipairs({ "vig", "spd", "stam", "mag" }) do
      H.assertEq(m[k] >= 8 and m[k] <= 255 - 12, true,
        string.format("[base] char %d %s %d is clear of the clamp", c, k, m[k]))
    end
  end
end) })
for i, stones in ipairs(RIDES) do
  local tag = "ride" .. i
  add(driveSteps(tag, stones))
  add({ checkRide(tag) })
end

add({ H.call(function()
  H.log("[esperstats-wor] all twelve World of Ruin stones carry their planned "
    .. "stat packages in battle")
end) })

H.run({ maxFrames = 120000 }, all)   -- 5 rides, each a reload + menu equips + ride-in
