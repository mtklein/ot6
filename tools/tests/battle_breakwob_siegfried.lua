-- @suite slow savestate=wob_train_specter
-- battle_breakwob_siegfried.lua -- the Phantom Train's Siegfried's authored row in play: from the graph's capture
-- `wob_train_specter` (SABIN, CYAN and SHADOW in the compartment car, map 153, beside the monster box they just
-- won), the party goes round through the hallway and the front cars to the west compartment (the route is
-- below), walks to (5,26) and steps north onto (5,25), the trigger of `_cbb7f8`
-- (event_trigger.asm: map 153, facing up; the event runs once, $0187), which starts `battle 109`, formation 479,
-- Siegfried $131 alone.  The library's fight driver plays it.  docs/design/break-coverage-wob.md section 17 is
-- the design; battle_breakwob_events checks the row as ROM bytes.
--
-- Asserted from the engine's cells (gauge $3e40+2s, max $3e41+2s, broken timer $3e90+2s, species $57c0+2s):
--   1. Siegfried opens with his authored gauge, 2 (the floor gave him 2 of slash alone);
--   2. the party breaks him (CYAN's katana, SHADOW's blade: slash and pierce);
--   3. the fight is won (a wipe raises).
-- Nothing writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wob_train_specter.mss.lua"

local SIEGFRIED, ROW = 0x131, 2
local SH_CUR, SH_MAX, BRK, SPECIES, PRESENT, MONHP = 0x3E40, 0x3E41, 0x3E90, 0x57C0, 0x3AA8, 0x3BFC
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
local function map() return H.mapId() & 0x1FF end

local W = { slots = {}, opened = false, done = false }
local function watch()
  if not H.battleLoadStarted() then
    if W.opened and not W.done then W.done = true end
    return
  end
  if W.done or H.monstersPresent() == 0 then return end
  for s = 0, 5 do
    if (H.readByte(PRESENT + s * 2) & 1) == 1 and H.readWord(SPECIES + s * 2) ~= 0xFFFF then
      local r = W.slots[s]
      if r == nil then
        r = { sp = H.readWord(SPECIES + s * 2), open = H.readByte(SH_MAX + s * 2) }
        W.slots[s] = r
        H.log(string.format("[siegfried] slot %d: species $%03X opens with %d of %d shield(s), %d hp", s, r.sp,
          H.readByte(SH_CUR + s * 2), r.open, H.readWord(MONHP + s * 2)))
      end
      local t = H.readByte(BRK + s * 2)
      if r.broke == nil and t ~= 0 and t ~= 0xFF then
        r.broke = H.frame
        H.log(string.format("[siegfried] slot %d ($%03X) BROKEN at f%d, %d hp left", s, r.sp, H.frame,
          H.readWord(MONHP + s * 2)))
      end
    end
  end
  W.opened = true
end

-- The compartment car (map 153) has three compartments, and which one a hallway door (map 151) opens on is the
-- car's $017E (_cba6bd/_cba6ca, event_main.asm:62592-62605): with it set, as the capture has it, (19,7) lands at
-- (23,11) and (9,7) at (23,28), the box's compartment; with it clear, (19,7) lands at (8,28), the west
-- compartment that holds (5,25).  The hallway's east door (26,8) clears it on the way out to the front cars
-- (_cba7b1 -> _cba7d9: map 141 (67,8)), and the front cars' passenger door (59,8) leads back in without setting it.
-- So: out of the box's compartment to the hallway, east to the front cars, back in, and through (19,7).
local MAP_CARS, MAP_HALL = 141, 151
local ROOM_EXITS = { { 23, 29 }, { 23, 12 }, { 8, 29 } }
local HALL_TRIGGERS = { { 1, 8 }, { 1, 9 }, { 19, 7 }, { 9, 7 } }
local CAR_DOORS = { { 91, 8 }, { 100, 8 }, { 109, 8 }, { 103, 8 }, { 116, 8 }, { 82, 8 }, { 75, 8 },
  { 66, 8 }, { 38, 8 }, { 31, 7 }, { 48, 8 } }
local ROOM_TRIGGERS = { { 23, 29 }, { 23, 12 }, { 8, 29 }, { 5, 25 }, { 8, 9 }, { 8, 12 } }
local function settled() return H.hasControl() and H.tileAligned() and not H.battleLoadStarted() end
local function sw17E() return (H.readByte(0x1E80 + (0x17E >> 3)) >> (0x17E & 7)) & 1 end
local function onFoot() return map() == 153 and H.bfsPath(5, 26) ~= nil end
local function arriveOn(m)
  return H.advanceStory(function() return map() == m and settled() end, 6000,
    { playBattles = "tactical", fight = FIGHT })
end

H.run({ maxFrames = 80000 }, {
  H.loadState(STATE),
  H.call(function()
    H.assertEq(map(), 153, "wob_train_specter stands in the compartment car (map 153)")
    H.assertEq((H.readByte(0x1E80 + (0x187 >> 3)) >> (0x187 & 7)) & 1, 0, "Siegfried's event has not run ($0187)")
    emu.addEventCallback(watch, emu.eventType.startFrame)
  end),
  H.cond(function() return not onFoot() end, {
    H.lazy(function()
      for _, t in ipairs(ROOM_EXITS) do
        if H.bfsPath(t[1], t[2]) then
          return H.navTo(t[1], t[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
            arrive = function() return map() == MAP_HALL end })
        end
      end
      error(string.format("153: no way back to the hallway from (%d,%d)", H.fieldX(), H.fieldY()), 0)
    end),
    arriveOn(MAP_HALL),
    H.navTo(26, 8, { maxFrames = 4000, playBattles = "tactical", fight = FIGHT, avoid = HALL_TRIGGERS,
      arrive = function() return map() == MAP_CARS end }),
    arriveOn(MAP_CARS),
    H.call(function()
      H.assertEq(sw17E(), 0, "the hallway's east door cleared $017E (_cba7d9)")
      H.log(string.format("[siegfried] the front cars at (%d,%d), $017E clear", H.fieldX(), H.fieldY()))
    end),
    H.navTo(59, 8, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = CAR_DOORS,
      arrive = function() return map() == MAP_HALL end }),
    arriveOn(MAP_HALL),
    H.navTo(19, 8, { maxFrames = 3000, avoid = HALL_TRIGGERS }),
    H.crossDoor(19, 7, 153, 8, 28, "the hallway's door 151 (19,7) -> 153 (8,28)", { fight = FIGHT }),
    arriveOn(153),
  }, {}),
  H.call(function()
    H.log(string.format("[siegfried] in the compartment car at (%d,%d), $017E=%d", H.fieldX(), H.fieldY(), sw17E()))
    H.assertEq(onFoot(), true, "(5,26), south of Siegfried's trigger, is on foot")
  end),
  H.navTo(5, 26, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = ROOM_TRIGGERS }),
  -- step north onto the trigger (it fires facing up), then ride the event and the fight
  H.driveUntil(function() return H.eventRunning() or H.battleLoadStarted() end, 600, {
    H.call(function() H.setPad({ up = true }) end),
  }, "the step onto (5,25)"),
  H.release(),
  H.advanceStory(function() return W.done end, 30000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    local r = nil
    for _, x in pairs(W.slots) do if x.sp == SIEGFRIED then r = x end end
    H.assertEq(r ~= nil, true, "battle 109 dealt Siegfried $131")
    H.assertEq(r.open, ROW, "Siegfried's gauge as he opens (his Ot6ShieldTbl row)")
    H.assertEq(r.broke ~= nil, true, "the party broke Siegfried")
    H.log("[siegfried] the row holds in play: two shields, broken by the party")
  end),
})
