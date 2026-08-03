-- probe_moogle_boosted.lua -- stations deployment + BOOSTED fighting
-- (issue #75, marshal-investigation).  probe_moogle_stations proved the
-- wave phase (three squads at three interception stations, two waves
-- each, all six down by ~f14.6k) and then lost the Marshal to plain
-- tap-A at 330/543.  This run upgrades every fight to the honest tactic
-- a human uses on a hard fight in OT6: spend boost.  The pad cycle in
-- battle is R (raise pending boost -- characters open with 1 bp and
-- regen 1 per unboosted turn, Ot6InitBP/Ot6ActionEnd), then A-A to
-- confirm the boosted Fight; R presses outside a command menu click
-- harmlessly.  Zero writes, buttons only.
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
    H.log(string.format("%s f%d pools: %s active=%d $1F41=%02X", tag, H.frame,
      table.concat(s, "  "), H.readByte(0x1a6d), H.readByte(0x1f41)))
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

-- the boosted battle pad: R to raise pending boost, A-A to walk the
-- command menu; edge-pressed on a 24-frame cycle.  Outside battle: A on
-- dialogs, neutral otherwise (advanceStory's frame discipline).
local function boostedDrive(pred, maxFrames, what)
  local phase = 0
  local battN, dlgN = 0, 0
  return H.driveUntil(function()
    local done = pred()
    if done then H.setPad({}) end
    return done
  end, maxFrames, {
    H.call(function()
      phase = (phase + 1) % 24
      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 then
        if phase < 4 then H.setPad({ "r" })
        elseif phase < 6 then H.setPad({})
        elseif phase < 10 then H.setPad({ "a" })
        elseif phase < 12 then H.setPad({})
        elseif phase < 16 then H.setPad({ "a" })
        elseif phase < 18 then H.setPad({})
        elseif phase < 22 then H.setPad({ "a" })
        else H.setPad({}) end
        return
      end
      if dlgN >= 3 then
        H.setPad(phase % 8 < 4 and { "a" } or {})
        return
      end
      H.setPad({})
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

H.run({ maxFrames = 140000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  logPools("boot"),

  -- deployment, east arm first (NPC_4 passes (20,20) ~f1400)
  H.navTo(15, 15, { maxFrames = 2500, honest = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, honest = true }),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, honest = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, honest = true }),
  logPools("deployed"),

  -- the storm, boosted
  boostedDrive(function()
    return (H.readByte(0x1f41) & 0xFC) == 0
  end, 60000, "all six waves (boosted)"),
  logPools("waves complete"),

  -- Marshal: healthier of P2/P3, boosted
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
    maxFrames = 15000, honest = true,
  }),
  pokeStep(),
  boostedDrive(function()
    return not H.battleLoadStarted()
  end, 30000, "Marshal fight (boosted)"),
  H.call(function()
    H.assertEq(defenseWon(), true, "defense won (switch $0631 cleared)")
    H.log(string.format("MARSHAL DOWN HONESTLY (boosted) at f%d", H.frame))
  end),
  logPools("victory"),
})
