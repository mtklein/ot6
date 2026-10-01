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
-- on a member in a battle in the tomb's grave room with a turn to spare:
-- another standing member's command window opens while the zombie stands,
-- and the battle is still up SPARE frames after it.  From there the battle
-- is fought out with navTo's driver (H.advanceStory, playBattles=
-- "tactical"), and the test asserts:
--   * the precondition, by name (a window, and the battle up SPARE frames
--     after it), so a fixture without a turn to spare fails there and not
--     at the property;
--   * the driver said `[status] ... is under ZOMBIE` for the zombie;
--   * it planned `cure entity <e>'s Zombie with $F1`;
--   * the bit cleared while the battle was up, and the battle's own item
--     list ($2686, five bytes a row: id, ..., count at +3, the list the
--     Item menu shows) read one Revivify fewer after the cure was planned
--     and before the battle ended: the cure is the one spent;
--   * the battle was won and paid the once-zombied member its share, unless
--     it went down again after the cure (a second landing or a fall: said).
-- ZOMBIE_CURE is the lever (opts.zombieCure); a copy with it false is the
-- negative control and goes red at the first of those it breaks (the
-- mutants that prove each assertion can fail are in
-- build/attempts/wt/wor-tomb/review/).
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/tomb_zombie.mss.lua"
local ZOMBIE_CURE = true
local SPARE = 900
local BAG_ITEM = H.REVIVIFY
local ST1, MENU, ACTOR, BATTINV = 0x3EE4, 0x7BCA, 0x62CA, 0x2686

local lines = {}
local rawLog = H.log
local planned = nil       -- the frame the driver first planned the cure on the zombie
local Z = nil
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  if Z and not planned and tostring(msg):find(string.format("cure entity %d's Zombie with $F1", Z.e), 1, true) then
    planned = H.frame
  end
  return rawLog(msg)
end

local function up() return H.battleLoadStarted() and H.monstersPresent() > 0 end
local function bag(id)
  local n = 0
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id then n = n + H.readByte(BATTINV + i * 5 + 3) end
  end
  return n
end
local o0, cleared, window, lastUp, bag0, spent, again = nil, nil, nil, nil, nil, {}, nil
emu.addEventCallback(function()
  if Z == nil or not up() then return end
  lastUp = H.frame
  local b = bag(BAG_ITEM)
  -- (the list reads 0 as the battle hands back -- "42 -> 0" -- which is
  -- the hand-back, not a use: a reading of 0 is not counted)
  if bag0 and b > 0 and b < (spent.last or bag0) then
    spent[#spent + 1] = H.frame
    H.log(string.format("[zombiecure] f%d the battle's item list: $%02X %d -> %d", H.frame, BAG_ITEM,
      spent.last or bag0, b))
  end
  spent.last = b
  if cleared then
    -- a second landing, or a fall, after the cure: the battle may end with
    -- the member down again, and its share is then not the cure's to pay
    local s1 = H.readByte(ST1 + Z.e * 2)
    if not again and ((s1 & 0xC2) ~= 0 or H.readWord(0x3BF4 + Z.e * 2) == 0) then
      again = H.frame
      H.log(string.format("[zombiecure] f%d entity %d is down again after the cure (STATUS1 $%02X, HP %d)",
        H.frame, Z.e, s1, H.readWord(0x3BF4 + Z.e * 2)))
    end
    return
  end
  local s1 = H.readByte(ST1 + Z.e * 2)
  if (s1 & 0x02) == 0 then
    cleared = H.frame
    H.log(string.format("[zombiecure] f%d entity %d's Zombie cleared in battle, %d frames after the fixture "
      .. "(STATUS1 $%02X, HP %d)", H.frame, Z.e, H.frame - Z.f, s1, H.readWord(0x3BF4 + Z.e * 2)))
  elseif not window and H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) ~= Z.e then
    window = H.frame
    H.log(string.format("[zombiecure] f%d entity %d's command window opens with entity %d Zombied", H.frame,
      H.readByte(ACTOR) & 3, Z.e))
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
    bag0 = bag(BAG_ITEM)
    H.assertEq(bag0 > 0, true, string.format("the battle's item list holds $%02X", BAG_ITEM))
    H.log(string.format("[zombiecure] f%d entity %d (char %d) is Zombied; $%02X x%d in the battle's list; "
      .. "the cure line %s", H.frame, Z.e, Z.char, BAG_ITEM, bag0, ZOMBIE_CURE and "on" or "OFF (negative control)"))
  end),
  H.advanceStory(function() return #H.outcomes > o0 and H.hasControl() end, 50000,
    { playBattles = "tactical", fight = { zombieCure = ZOMBIE_CURE } }),
  H.call(function()
    local o = H.outcomes[o0 + 1]
    H.assertEq(window ~= nil, true, string.format("the precondition: another standing member's command window "
      .. "opened while entity %d stood Zombied", Z.e))
    H.assertEq((lastUp or 0) - window >= SPARE, true, string.format("the precondition: the battle was still up "
      .. "%d frames after that window (up until f%s, the window f%d)", SPARE, tostring(lastUp), window))
    H.assertEq(said(string.format("entity %d char %d is under ZOMBIE", Z.e, Z.char)), true,
      string.format("the driver said [status] ... is under ZOMBIE for entity %d", Z.e))
    H.assertEq(said(string.format("cure entity %d's Zombie with $F1", Z.e)), true,
      string.format("the driver planned a Revivify on the Zombied entity %d", Z.e))
    H.assertEq(cleared ~= nil, true, string.format("entity %d's Zombie cleared while the battle was up", Z.e))
    -- the battle's item list ($2686) is the one the Item menu shows: it
    -- reads one fewer from the next menu after a use, not on the use's own
    -- frame (measured: a clear at f459, the list 40 -> 39 at f624,
    -- build/attempts/wt/wor-tomb/review/zfix/suite_k1_s21.log)
    local after = nil
    for _, f in ipairs(spent) do if planned and f >= planned and f <= (lastUp or 0) then after = after or f end end
    H.assertEq(after ~= nil, true, string.format("the battle's item list lost a $%02X after the cure was planned "
      .. "(f%s) and before the battle ended (f%s): the cure is the one spent (%d decrement(s), the first at f%s)",
      BAG_ITEM, tostring(planned), tostring(lastUp), #spent, tostring(spent[1])))
    H.assertEq(o.kind, "won", "the battle was won")
    local paid = (o.got[Z.e] or 0) > 0 and o.got[Z.e] == (o.share[Z.e] or -1)
    H.assertEq(paid or again ~= nil, true, string.format(
      "the battle paid the once-Zombied entity %d its share (got %s, due %s), or it went down again after the "
      .. "cure (%s)", Z.e, tostring(o.got[Z.e]), tostring(o.share[Z.e]), again and ("f" .. again) or "no"))
    H.log(string.format("PASSED: entity %d (char %d) Zombied at the fixture, the cure planned at f%d, the Zombie "
      .. "cleared at f%d, the list one fewer at f%d, the battle won, %s", Z.e, Z.char, planned, cleared, after,
      paid and string.format("its share paid (%d)", o.got[Z.e])
        or string.format("down again at f%d after the cure: share %d", again, o.got[Z.e] or 0)))
  end),
})
