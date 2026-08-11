-- probe_moogle_rotation.lua -- plays the WHOLE Moogle defense with real
-- input by squad rotation (issue #75, marshal-investigation).  Zero state
-- writes;  input is walking, Y-switching, and tap-A fighting -- a human's
-- toolkit.
--
-- The strategy under test (from the measured geometry + march scripts):
--   * every march funnels into the tail (15,17)->(15,16)->(14,16)->
--     (14,15)->(14,14)->(14,13); a guard that completes it fires the
--     game-over exec at (14,13), so the choke (14,14) must be manned
--   * (15,15) is on NO march path (guards cut the corner (15,16)->
--     (14,16)) and the mound parks (13,13)/(15,13) are off-path too --
--     so a 2-step aside + 2-step walk-in swaps the goalie between waves
--   * party 1 (LOCKE+3) proved it wins exactly two waves by tap-A and
--     wipes on its third (pilot 41fcf8f), so: P1 waves 1-2, P2 (MOG+3)
--     waves 3-4, P3 waves 5-6, then the healthiest party takes the
--     Marshal (battle 6 = Marshal + 2 Lobos)
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

-- party rosters as character ids (char block $1600 + 37*c, +9 HP +B max)
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

-- name every fight + who is fighting it, from outside the step machine
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

-- tap Y (with the CheckChangeParty press-release latch) until the party
-- leader offset says the target party is active
local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1200, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
end

local function calmish(n)
  local cnt = 0
  return function()
    cnt = (H.hasControl() and H.tileAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end

-- one wave: hands-off/tap-A until this guard's despawn switch clears
local function wave(n, mask)
  return H.seqStep({
    logGuards("pre-wave " .. n),
    H.advanceStory(function()
      return (H.readByte(0x1f41) & mask) == 0
    end, 18000, { playBattles = true }),
    logPools("post-wave " .. n),
    H.waitUntil(calmish(20), 1800, "calm after wave " .. n),
  })
end

-- the Marshal's post + activation (gen_moogle's pokeStep, input-driven)
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

  -- P1 holds the choke for waves 1-2 (it starts there)
  wave(1, 0x04),
  wave(2, 0x08),

  -- swap A: P1 aside to the off-path (15,15); P2 to the choke
  logGuards("swap A start"),
  H.navTo(15, 15, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(2),
  H.navTo(14, 14, { maxFrames = 4000, playBattles = true }),
  logGuards("swap A done"),
  logPools("swap A done"),

  wave(3, 0x10),
  wave(4, 0x20),

  -- swap B: P2 back up to its mound park (13,13); P3 to the choke
  logGuards("swap B start"),
  H.navTo(13, 13, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(3),
  H.navTo(14, 14, { maxFrames = 4000, playBattles = true }),
  logGuards("swap B done"),
  logPools("swap B done"),

  wave(5, 0x40),
  wave(6, 0x80),
  H.logStep(function()
    return string.format("all six waves down at f%d; corridor open", H.frame)
  end),
  logPools("waves complete"),

  -- Marshal: send MOG's party (P2) if its pool is at least P3's, else P3.
  -- P3 stands at the choke, P2 parks at (13,13); either walks the now
  -- guard-free corridor to (15,39) and pokes him.
  H.cond(function()
    local c2 = poolOf(2)
    local c3 = poolOf(3)
    H.log(string.format("marshal pick: P2=%d P3=%d -> %s", c2, c3,
      c2 >= c3 and "P2" or "P3"))
    return c2 >= c3
  end, {
    ySwitchTo(2),
  }, {}),
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
