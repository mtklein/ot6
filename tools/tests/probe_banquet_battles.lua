-- probe_banquet_battles.lua -- live formation verification for the
-- banquet's event battles 26/27/30 (issue #31; the v0.6 Shiva precedent
-- says offline battle_monsters decodes are not evidence on their own).
--
-- STAGING: boots dadaluma_doorstep.mss (a quiet field map with control)
-- and forces each event battle exactly the way EventBattle does
-- (field/event.asm:1910-1942): battle index -> $11e0, map-default bg ->
-- $11e2, blur/sfx flags -> $078a, then $56=1.  Groups 26/27/30 map 1:1
-- to battles 408/418/157 with no 1/4 alternate (event_battle_group.dat),
-- so skipping UpdateBattleGrpRng loses nothing.  This proves formation
-- CONTENTS and the clean-win b-switch state; it proves nothing about the
-- banquet field scripts around the battles (those are source-cited in
-- banquet-decode.md) or about difficulty for the real leg party (the
-- fixture party here is the v0.6 Zozo four, and wins are kill-bit).
-- NOT a suite test.
local H = dofile("tools/tests/lib/ot6.lua")

local CASES = {
  { grp = 26, battle = 408, name = "Mega Armor x1 ($102)" },
  { grp = 27, battle = 418, name = "Commando x1 ($0c7)" },
  { grp = 30, battle = 157, name = "Sp Forces x3 ($0c2)" },
}

local function bsw(n)  -- field-side battle switch (after $3eb4->$1dc9 copy)
  return (H.readByte(0x1dc9 + (n >> 3)) >> (n & 7)) & 1
end

local steps = {}
for _, c in ipairs(CASES) do
  steps[#steps + 1] = H.loadState("build/states/dadaluma_doorstep.mss.lua")
  steps[#steps + 1] = H.waitFrames(90)
  steps[#steps + 1] = H.call(function()
    H.assertEq(H.hasControl(), true, c.name .. ": field control before force")
    H.writeWord(0x11e0, c.battle)
    H.writeByte(0x11e2, H.readByte(0x0522) & 0x7f)  -- map default battle bg
    H.writeByte(0x11e3, 0)
    H.writeByte(0x078a, 0)
    H.writeByte(0x56, 1)
    H.log(string.format("[force] group %d -> battle %d (%s)", c.grp, c.battle, c.name))
  end)
  steps[#steps + 1] = H.waitUntil(function() return H.battleLoadStarted() end,
    1500, c.name .. ": battle loads", 5)
  steps[#steps + 1] = H.waitFrames(150)
  steps[#steps + 1] = H.call(function()
    local w = {}
    for i = 0, 5 do w[i + 1] = string.format("%04X", H.readWord(0x3F46 + i * 2)) end
    local hp = {}
    for m = 0, 5 do hp[m + 1] = H.readWord(0x3BFC + m * 2) end
    H.log(string.format("[%s] formation words: %s", c.name, table.concat(w, " ")))
    H.log(string.format("[%s] monster HP rows: %d %d %d %d %d %d",
      c.name, table.unpack(hp)))
    H.log(string.format("[%s] battle type $2f48=%04X aux $2f4a=%04X",
      c.name, H.readWord(0x2f48), H.readWord(0x2f4a)))
    H.screenshot(string.format("banquet_battle_%d", c.grp))
  end)
  steps[#steps + 1] = H.clearBattle(9000)
  steps[#steps + 1] = H.waitFrames(90)
  steps[#steps + 1] = H.call(function()
    H.log(string.format(
      "[%s] after kill-bit win: b_switch $40=%d $44=%d $45=%d ($1dd1=%02X)",
      c.name, bsw(0x40), bsw(0x44), bsw(0x45), H.readByte(0x1dd1)))
    H.assertEq(bsw(0x40), 0, c.name .. ": $40 clear on a clean win")
    H.assertEq(bsw(0x44), 0, c.name .. ": $44 clear on a clean win")
    H.assertEq(bsw(0x45), 0, c.name .. ": $45 clear on a clean win")
  end)
end

H.run({ maxFrames = 60000 }, steps)
