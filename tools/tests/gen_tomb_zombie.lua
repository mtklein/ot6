-- gen_tomb_zombie.lua -- a battle in Darill's Tomb at the moment a Zombie
-- lands on a party member: the fixture battle_zombiecure plays on.
--
-- From wor_tomb (CELES, SABIN, EDGAR and SETZER on the tomb's save point,
-- 300 (122,14)), up through (122,7) into the grave's room, 299 (100,28),
-- whose pool (field group 150: PowerDemon; Exoray x3; Mad Oscar + Exoray)
-- holds the tomb's Zombie-casters (the PowerDemon's Soul Out, the Exoray's
-- DoomPollen; route-wor-falcon 3.5).  The party paces the room between
-- (100,26) and (100,17), the grave's tile (100,14) kept off the plan,
-- fighting with navTo's playBattles="tactical" driver, until a Zombie
-- lands on a member in a battle with another member standing; the frame
-- it lands, the whole machine is captured (H.requestSaveState) and
-- emitted as tomb_zombie.mss, and the run ends once that battle is over.
--
-- Which battle that is depends on the draw: the encounter order is save
-- data and the landing is the monster's roll.  Measured on this pacing
-- (build/attempts/wt/wor-tomb/zombie/lab/grave15_s*.log): 9 landings over
-- 60 battles at seed shifts 0, 7, 13 and 21, none in shift 21's 15.  CAP
-- bounds the walk at 40 battles (at 0.15 a battle, all 40 miss about once
-- in 700), and a run that meets none fails at that assertion with every
-- formation fought named.  Reads only; every step is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/wor_tomb.mss.lua"
local CAP = 40
local ST1 = 0x3EE4

local o0 = nil
local landed, req, emitted = nil, nil, false
local inBattle = false
emu.addEventCallback(function()
  if o0 == nil or landed then return end
  inBattle = H.battleLoadStarted() and H.monstersPresent() > 0
  if not inBattle then return end
  local standing = 0
  for e = 0, 3 do
    local s1 = H.readByte(ST1 + e * 2)
    if H.readWord(0x3C1C + e * 2) > 0 and H.readWord(0x3BF4 + e * 2) > 0 and (s1 & 0xC2) == 0 then
      standing = standing + 1
    end
  end
  for e = 0, 3 do
    local s1 = H.readByte(ST1 + e * 2)
    if (s1 & 0x02) ~= 0 and (s1 & 0x80) == 0 and H.readWord(0x3C1C + e * 2) > 0 and standing >= 1 then
      landed = { e = e, f = H.frame, battle = #H.outcomes - o0 + 1, char = H.readByte(0x3ED8 + e * 2),
                 form = H.readWord(0x11E0) }
      req = H.requestSaveState()
      H.log(string.format("[tomb_zombie] f%d battle %d (group $%04X): Zombie lands on entity %d (char %d), "
        .. "%d member(s) standing; capturing", H.frame, landed.battle, landed.form, e, landed.char, standing))
      return
    end
  end
end, emu.eventType.startFrame)

H.run({ maxFrames = 300000 }, {
  H.loadState(STATE),
  H.call(function()
    o0 = #H.outcomes
    H.assertEq(H.mapId() & 0x1ff, 300, "wor_tomb stands in Darill's Tomb B3 (map 300)")
  end),
  H.crossDoor(122, 7, 299, 100, 28, "the east room (122,7) -> the grave's room (100,28)"),
  (function()
    local wp = 1
    local WPS = { { 100, 26 }, { 100, 17 } }
    return H.withReset(H.driveUntil(function()
      if landed and req and req.done and not emitted then
        emitted = true
        H.assertEq(req.ok, true, "the capture at the landing")
        H.emitBlob("tomb_zombie.mss", req.blob)
        H.log(string.format("[tomb_zombie] emitted tomb_zombie.mss (%d bytes)", #req.blob))
      end
      if emitted and not (H.battleLoadStarted() and H.monstersPresent() > 0) then return true end
      return not landed and #H.outcomes - o0 >= CAP
    end, 290000, {
      H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
        { maxFrames = 20000, playBattles = "tactical", avoid = { { 100, 14 }, { 100, 29 } } }),
      H.call(function() wp = wp % #WPS + 1 end),
    }, "pacing the grave's room"), function() wp = 1 end)
  end)(),
  H.call(function()
    local forms = {}
    for i = o0 + 1, #H.outcomes do
      forms[#forms + 1] = string.format("$%03X %s", H.outcomes[i].form & 0x1FF, H.outcomes[i].kind)
    end
    H.log(string.format("[tomb_zombie] %d battle(s) fought: %s", #H.outcomes - o0, table.concat(forms, ", ")))
    H.assertEq(emitted, true, string.format("a Zombie landed on a member with another standing within %d "
      .. "battles (fought: %s)", CAP, table.concat(forms, ", ")))
  end),
  H.logStep(function()
    return string.format("tomb_zombie generated: battle %d, entity %d (char %d) Zombied at f%d",
      landed.battle, landed.e, landed.char, landed.f)
  end),
})
