-- @manual
-- probe_fieldcare_tonic.lua -- #152: what does an explicit fieldCare reach
-- for outside battle when the bag holds Tonics?  Boots n024_won (the
-- Magitek Factory, map 273, the party gen_esper_tubes walks to the tube
-- room from), walks the (25,52) leg with battles fought and NO automatic
-- care until at least one random has been fought, then runs the very
-- fieldCare call gen_esper_tubes makes before battle 72.  Reads and pad
-- presses only.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/n024_won.mss.lua"
local battles, inBattle = 0, false
emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then inBattle = true; battles = battles + 1 end
  if not live and inBattle then inBattle = false end
end, emu.eventType.startFrame)

local function roster(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c), H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  H.log(string.format("[care probe] %s: %s | tonic=%d potion=%d", tag, table.concat(out, "  "),
    H.invCountOf(0xE8), H.invCountOf(0xE9)))
end

local sx, sy
local function leg(tx, ty)
  return H.navTo(tx, ty, { maxFrames = 8000, playBattles = "tactical", care = false,
    arrive = function() return battles >= 1 and not H.battleLoadStarted() and H.hasControl() end })
end

H.run({ maxFrames = 120000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() end, 1200, "field control", 5),
  H.call(function()
    sx, sy = H.fieldX(), H.fieldY()
    H.log(string.format("[care probe] start on map %d at (%d,%d)", H.mapId() & 0x3ff, sx, sy))
    roster("at boot")
  end),
  H.repeatN(3, {
    H.cond(function() return battles == 0 end, { leg(25, 52) }, {}),
    H.cond(function() return battles == 0 end,
      { leg(function() return sx end, function() return sy end) }, {}),
  }),
  H.waitFrames(60),
  H.call(function() roster(string.format("after %d battle(s), before care", battles)) end),
  H.fieldCare({ tag = "care before battle 72", threshold = 0.95 }),
  H.call(function() roster("after care") end),
})
