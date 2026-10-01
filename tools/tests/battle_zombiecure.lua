-- @suite savestate=tomb_zombie
-- battle_zombiecure.lua -- the fight driver cures a Zombied member in
-- battle with Revivify (#263), measured in play rather than staged.
--
-- The exposure is the route's own: Darill's Tomb, where four of five
-- species Zombie a member (route-wor-falcon 3.5).  A zombied member reads
-- 0 HP without the Wound bit; the ATB-full check hands its turns to the
-- engine (battle_main @0941's list carries ZOMBIE), no Fenix Down lands on
-- it (#245), and a won battle pays it nothing.  Before the cure line the
-- driver left it so to the battle's end and the field care's Revivify
-- cleared it afterwards: gen_wor_tomb's first runs paid "char 6 +0 (due
-- 0)" and "char 9 +0 (due 0)" beside "+1383 (due 1383)" for the standing
-- pair (build/attempts/wt/wor-tomb/dev/run2.log).  The cure line
-- (Driver:cureFor) finds the bag's item whose STATUS1 record carries the
-- bit (M.statusCure: Revivify, $F1) and plans it on the zombie at the
-- round's care turn.
--
-- The fixture, tomb_zombie (gen_tomb_zombie), is the frame a Zombie lands
-- on a member in a battle in the tomb's grave room, with another member
-- standing.  From there the battle is fought out with navTo's driver
-- (H.advanceStory, playBattles="tactical"), and the test asserts:
--   * the driver said `[status] ... is under ZOMBIE` for the zombie;
--   * it planned `cure entity <e>'s Zombie with $F1`;
--   * the bit cleared while the battle was up;
--   * the battle was won and paid the once-zombied member its share.
-- ZOMBIE_CURE is the lever (opts.zombieCure); a copy with it false is the
-- negative control and goes red at the first of those it breaks.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/tomb_zombie.mss.lua"
local ZOMBIE_CURE = true
local ST1 = 0x3EE4

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

local Z, o0, cleared = nil, nil, nil
local function up() return H.battleLoadStarted() and H.monstersPresent() > 0 end
emu.addEventCallback(function()
  if Z == nil or cleared or not up() then return end
  local s1 = H.readByte(ST1 + Z.e * 2)
  if (s1 & 0x02) == 0 then
    cleared = H.frame
    H.log(string.format("[zombiecure] f%d entity %d's Zombie cleared in battle, %d frames after the fixture "
      .. "(STATUS1 $%02X, HP %d)", H.frame, Z.e, H.frame - Z.f, s1, H.readWord(0x3BF4 + Z.e * 2)))
  end
end, emu.eventType.startFrame)

local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.call(function()
    H.assertEq(up(), true, "tomb_zombie stands in a battle")
    for e = 0, 3 do
      local s1 = H.readByte(ST1 + e * 2)
      if Z == nil and (s1 & 0x02) ~= 0 and (s1 & 0x80) == 0 and H.readWord(0x3C1C + e * 2) > 0 then
        Z = { e = e, char = H.readByte(0x3ED8 + e * 2), f = H.frame }
      end
    end
    H.assertEq(Z ~= nil, true, "a member stands Zombied in tomb_zombie (STATUS1 $02 without the Wound bit)")
    o0 = #H.outcomes
    H.log(string.format("[zombiecure] f%d entity %d (char %d) is Zombied; the cure line %s", H.frame, Z.e,
      Z.char, ZOMBIE_CURE and "on" or "OFF (negative control)"))
  end),
  H.advanceStory(function() return #H.outcomes > o0 and H.hasControl() end, 50000,
    { playBattles = "tactical", fight = { zombieCure = ZOMBIE_CURE } }),
  H.call(function()
    local o = H.outcomes[o0 + 1]
    H.assertEq(said(string.format("entity %d char %d is under ZOMBIE", Z.e, Z.char)), true,
      string.format("the driver said [status] ... is under ZOMBIE for entity %d", Z.e))
    H.assertEq(said(string.format("cure entity %d's Zombie with $F1", Z.e)), true,
      string.format("the driver planned a Revivify on the Zombied entity %d", Z.e))
    H.assertEq(cleared ~= nil, true, string.format("entity %d's Zombie cleared while the battle was up", Z.e))
    H.assertEq(o.kind, "won", "the battle was won")
    H.assertEq((o.got[Z.e] or 0) > 0 and o.got[Z.e] == (o.share[Z.e] or -1), true, string.format(
      "the battle paid the once-Zombied entity %d its share (got %s, due %s)", Z.e, tostring(o.got[Z.e]),
      tostring(o.share[Z.e])))
    H.log(string.format("PASSED: entity %d (char %d) Zombied at the fixture, Revivified in battle at f%d, "
      .. "the battle won and its share paid (%d)", Z.e, Z.char, cleared, o.got[Z.e]))
  end),
})
