-- probe_moogle_stations.lua -- the Moogle defense played with real input:
-- pre-position all three squads at separate interception stations before
-- the marches arrive. Zero writes; walking, Y-taps, and tap-A only.
--
-- The first ~2000 frames of the defense are quiet (wave 1 needs ~2100
-- field-frames to arrive), and the march scripts split by arm:
--   east loop  (20,19..23):        NPC_4 and NPC_9    -> P3 parks (20,20)
--   west loop  (10,19..23):        NPC_7 and NPC_8    -> P2 parks (10,21)
--   middle column + tail (15,y):   NPC_5 and NPC_6    -> P1 keeps (14,14)
-- Collisions auto-engage the collided party, so once parked, tap-A rides
-- every fight. The choke stays manned throughout because an
-- unintercepted march ends in the GameOver exec at (14,13).
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local PARTY = {
  [1] = { 1, 2, 3, 4 },     -- LOCKE KUPEK KUPOP KUMAMA
  [2] = { 10, 5, 6, 7 },    -- MOG KUKU KUTAN KUPAN
  [3] = { 8, 9, 11, 12 },   -- KUSHU KURIN KURU KAMOG
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
    H.log(string.format("%s f%d pools: %s active=%d $1F41=%02X", tag, H.frame,
      table.concat(s, "  "), H.readByte(0x1a6d), H.readByte(0x1f41)))
  end)
end

local function logGuards(tag)
  return H.call(function()
    local s = {}
    for i = 19, 24 do
      s[#s + 1] = string.format("(%d,%d)",
        H.readWord(0x086a + 0x29 * i) >> 4, H.readWord(0x086d + 0x29 * i) >> 4)
    end
    H.log(string.format("%s f%d guards %s", tag, H.frame, table.concat(s, " ")))
  end)
end

local fightN = 0
emu.addEventCallback(function()
  fightN = H.battleLoadStarted() and fightN + 1 or 0
  if fightN == 3 then
    local w = H.formationWords()
    local hp = H.partyHp()
    H.log(string.format(
      "fight up f%d party=%d (%04X %04X %04X) hp %d/%d/%d/%d",
      H.frame, H.readByte(0x1a6d), w[1], w[2], w[3],
      hp[1], hp[2], hp[3], hp[4]))
  end
end, emu.eventType.startFrame)

local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
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

H.run({ maxFrames = 140000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  logPools("boot"),
  logGuards("boot"),

  -- ------------------------------------------------ deployment (quiet) --
  -- P1 vacates the choke so P2/P3 can leave the mound (its (13,13)/(15,13)
  -- parks have no other exit), then everyone walks to station and P1
  -- returns to the choke.
  -- P3 first: its east station is the earliest one a march reaches
  -- (NPC_4 passes (20,20) around field-frame ~1400; the west arm's first
  -- guard needs ~1800; the choke ~2100)
  H.navTo(15, 15, { maxFrames = 2500, playBattles = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, playBattles = true }),
  logGuards("P3 at east station"),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, playBattles = true }),
  logGuards("P2 at west station"),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, playBattles = true }),
  logGuards("deployed"),
  logPools("deployed"),

  -- ---------------------------------------------------- the wave phase --
  -- hands off; collisions engage whichever squad each march runs into,
  -- tap-A wins each fight, the win path despawns that guard.
  H.advanceStory(function()
    return (H.readByte(0x1f41) & 0xFC) == 0
  end, 60000, { playBattles = true }),
  H.logStep(function()
    return string.format("all six waves down at f%d", H.frame)
  end),
  logPools("waves complete"),
  logGuards("waves complete"),

  -- ------------------------------------------------------- the Marshal --
  -- the healthier of P2/P3 walks the emptied corridor and engages him
  H.cond(function()
    local c2 = poolOf(2)
    local c3 = poolOf(3)
    H.log(string.format("marshal pick: P2=%d P3=%d -> %s", c2, c3,
      c2 >= c3 and "P2" or "P3"))
    return c2 >= c3
  end, { ySwitchTo(2) }, { ySwitchTo(3) }),
  H.navTo(MX, MY - 1, {
    arrive = function()
      return defenseWon()
          or (marshalAdjacent() and H.hasControl() and H.tileAligned())
    end,
    maxFrames = 15000, playBattles = true,
  }),
  H.logStep(function()
    return string.format("beside the Marshal at (%d,%d) f%d",
      H.fieldX(), H.fieldY(), H.frame)
  end),
  pokeStep(),
  H.cond(function() return H.battleLoadStarted() end, {
    H.fightBattle(30000),
  }, {}),
  H.call(function()
    H.assertEq(defenseWon(), true, "defense won (switch $0631 cleared)")
    H.log(string.format("MARSHAL DOWN at f%d", H.frame))
  end),
  logPools("victory"),
})
