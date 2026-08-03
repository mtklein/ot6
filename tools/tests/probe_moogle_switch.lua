-- probe_moogle_switch.lua -- Y-party-switching mechanics + march timing at
-- defense-live (issue #75, marshal-investigation).  Input is button presses
-- only (Y taps -- the mechanic a human player uses); ZERO writes.
--   1. tap Y three times, logging the party-leader object offset $0803 and
--      the leader position after each: does control cycle 1 -> 2 -> 3 -> 1,
--      instantly, no menu?
--   2. then hands off: watch the six guard marches (objects 19..24) every
--      300 frames until the first collision battle engages, and log the
--      formation words + monster ids of that wave battle.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local function snap(tag)
  return H.call(function()
    H.log(string.format("%s: $0803=%04X (obj %d) pos=(%d,%d) ctl=%s algn=%s",
      tag, H.readWord(0x0803), H.readWord(0x0803) // 0x29,
      H.fieldX(), H.fieldY(), tostring(H.hasControl()),
      tostring(H.tileAligned())))
  end)
end

local function guards(tag)
  return H.call(function()
    local s = {}
    for i = 19, 24 do
      s[#s + 1] = string.format("(%d,%d)",
        H.readWord(0x086a + 0x29 * i) >> 4, H.readWord(0x086d + 0x29 * i) >> 4)
    end
    H.log(string.format("%s f%d guards %s $1F41=%02X", tag, H.frame,
      table.concat(s, " "), H.readByte(0x1f41)))
  end)
end

local battN = 0

H.run({ maxFrames = 20000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  snap("boot"),
  guards("boot"),
  H.pressButtons({ "y" }, 6), H.waitFrames(40), snap("after Y x1"),
  H.pressButtons({ "y" }, 6), H.waitFrames(40), snap("after Y x2"),
  H.pressButtons({ "y" }, 6), H.waitFrames(40), snap("after Y x3"),
  guards("post-switch"),
  -- hands off until the first wave collides with whoever holds the choke
  H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 3
  end, 16000, {
    H.call(function() H.setPad({}) end),
    guards("watch"),
    H.waitFrames(300),
  }, "first wave collision"),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("wave battle up f%d: form %04X %04X %04X %04X %04X %04X",
      H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
    local ids = H.monsterIds()
    H.log(string.format("monster ids: %04X %04X %04X %04X %04X %04X",
      ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]))
    local hp = H.partyHp()
    H.log(string.format("party battle HP: %d %d %d %d", hp[1], hp[2], hp[3], hp[4]))
  end),
})
