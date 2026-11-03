-- gen_wor_tomb_b1_hunt.lua -- a branch beside gen_wor_tomb (#502, wor-coverage.md section 11.9): Continue the
-- `wor-kohlingen-v1` battery (CELES, SABIN, EDGAR and SETZER on the world map east of Kohlingen's door), walk to
-- Darill's Tomb as gen_wor_tomb does, open its door with SETZER in the party, go down its stairs to B1 (298) and
-- lap there until each formation of B1's pool (field group 149) is won: 244 (Orog x2) and 245 (Orog, PowerDemon
-- x2; 16/256), which the line's walk across B1 did not meet, with 246 (Osteosaur) (K.hunt).  Nothing boots what
-- it leaves (the state `wor_tomb_b1_hunt`); B3's and the grave room's pools are gen_wor_tomb_hunt's, from the
-- tomb's save point.
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, SABIN, CELES, SETZER = 4, 5, 6, 9
local NAMES = { [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES", [SETZER] = "SETZER" }
local FOUR = { CELES, SABIN, EDGAR, SETZER }
local MAP_DOOR, MAP_B1 = 297, 298
local TOMB_TILE = { 25, 52 }
local FIGHT = {}

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, watches, walkInto, sw = K.map, K.say, K.kitLine, K.watches, K.walkInto, K.sw
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function control(what)
  return H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
  end, 3000, what, 5)
end
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
local B1_149 = { [244] = "Orog x2", [245] = "Orog, PowerDemon x2", [246] = "Osteosaur" }

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("wor-kohlingen-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    -- the leg's hard dependency: the tomb's door opens only with SETZER in the party (_ca3f83 reads $01A9)
    H.assertEq(inParty(SETZER), true, "SETZER is in the party for the tomb's door ($01A9, _ca3f83): gen_wor_kohlingen's")
  end),
  -- @@setup-end
  H.fieldCare({ tag = "care at the boot", threshold = H.CARE_BEFORE_FIGHTS }),
  H.worldNavTo(TOMB_TILE[1], TOMB_TILE[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_DOOR end, 2400, "Darill's Tomb: map 297", 5),
  control("Darill's Tomb: control"),
  -- the door: the step-on trigger (8,10) draws the stairs (7,8) ($00CB) (gen_wor_tomb's)
  H.navTo(8, 10, { maxFrames = 3000, arrive = function() return sw(0x00CB) == 1 end }),
  H.advanceStory(function()
    return sw(0x00CB) == 1 and map() == MAP_DOOR and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting() and bright() >= 15
  end, 6000, {}),
  H.call(function()
    H.assertEq(sw(0x00CB), 1, "the tomb's door is open ($00CB, _ca3f83)")
    say("tomb", "the door opened")
  end),
  walkInto(7, 8, MAP_B1, "the stairs (7,8) -> B1 (13,12)"),
  H.saveState("wor_tomb_b1_hunt_b1.mss"),
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: B1 (group 149)" }),
  -- @@stage hunt
  K.hunt({ what = "Darill's Tomb B1 (group 149)", lap = { { 13, 16 }, { 13, 17 } }, forms = B1_149, won = won,
    avoid = { { 13, 10 }, { 13, 24 } } }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: B1 (group 149)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_tomb_b1_hunt.mss"),
  H.logStep(function()
    return string.format("wor_tomb_b1_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(),
      H.fieldY(), wonLine())
  end),
})
