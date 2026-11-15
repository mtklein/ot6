-- @suite slow savestate=wob_train_specter
-- battle_breakwob_siegfried.lua -- the Phantom Train's Siegfried's authored row in play: from the graph's capture
-- `wob_train_specter` (SABIN, CYAN and SHADOW in the compartment car, map 153, beside the monster box they just
-- won), the party goes back through the hallway's doors, as gen_wob_train_specter does, until the
-- compartment it lands in reaches (5,26), and steps north onto (5,25), the trigger of `_cbb7f8`
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

-- the compartment car's doors (gen_wob_train_specter's tables): the compartments' own exits back to the hallway
-- (map 151), the hallway's compartment doors, which land by the car's $017E, and every trigger to keep off
local MAP_HALL = 151
local ROOM_EXITS = { { 23, 29 }, { 23, 12 }, { 8, 29 } }
local HALL_DOORS = { { 19, 7 }, { 9, 7 }, { 19, 7 }, { 9, 7 } }
local HALL_TRIGGERS = { { 26, 8 }, { 26, 9 }, { 1, 8 }, { 1, 9 }, { 19, 7 }, { 9, 7 } }
local ROOM_TRIGGERS = { { 23, 29 }, { 23, 12 }, { 8, 29 }, { 5, 25 }, { 8, 9 }, { 8, 12 } }
local function settled() return H.hasControl() and H.tileAligned() and not H.battleLoadStarted() end
local function onFoot() return map() == 153 and H.bfsPath(5, 26) ~= nil end
local doorsTried = {}
-- one try: from a compartment that does not reach (5,26), out to the hallway and in at the next door
local function tryDoor(door)
  return H.cond(function() return not onFoot() end, {
    H.cond(function() return map() == 153 end, {
      H.lazy(function()
        for _, t in ipairs(ROOM_EXITS) do
          if H.bfsPath(t[1], t[2]) then
            return H.navTo(t[1], t[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
              arrive = function() return map() == MAP_HALL end })
          end
        end
        error(string.format("153: no way back to the hallway from (%d,%d)", H.fieldX(), H.fieldY()), 0)
      end),
      H.advanceStory(function() return map() == MAP_HALL and settled() end, 6000,
        { playBattles = "tactical", fight = FIGHT }),
      H.navTo(4, 8, { maxFrames = 3000, avoid = HALL_TRIGGERS }),
    }, {}),
    H.crossDoor(door[1], door[2], 153, -1, -1, string.format("the hallway's door 151 (%d,%d) -> 153", door[1],
      door[2]), { fight = FIGHT }),
    H.advanceStory(function() return map() == 153 and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
    H.call(function()
      doorsTried[#doorsTried + 1] = string.format("(%d,%d) -> 153 (%d,%d)%s", door[1], door[2], H.fieldX(),
        H.fieldY(), onFoot() and ": (5,26) on foot" or "")
      H.log("[siegfried] hallway door " .. doorsTried[#doorsTried])
    end),
  }, {})
end

H.run({ maxFrames = 80000 }, {
  H.loadState(STATE),
  H.call(function()
    H.assertEq(map(), 153, "wob_train_specter stands in the compartment car (map 153)")
    H.assertEq((H.readByte(0x1E80 + (0x187 >> 3)) >> (0x187 & 7)) & 1, 0, "Siegfried's event has not run ($0187)")
    emu.addEventCallback(watch, emu.eventType.startFrame)
  end),
  tryDoor(HALL_DOORS[1]), tryDoor(HALL_DOORS[2]), tryDoor(HALL_DOORS[3]), tryDoor(HALL_DOORS[4]),
  H.call(function()
    H.assertEq(onFoot(), true, "(5,26), south of Siegfried's trigger, is on foot (doors tried: "
      .. table.concat(doorsTried, "; ") .. ")")
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
