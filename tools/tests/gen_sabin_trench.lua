-- gen_sabin_trench.lua -- leg 11, the last of SABIN's scenario: Crescent
-- Mountain, the Serpent Trench, and the Nikeah ferry.  Mints:
--   sabin_done.mss   map 9 (the scenario hub), $0044=1 -- SABIN's scenario
--                    complete, the hub's "Choose a scenario…kupo!" spoken,
--                    the party dissolved to the hub's MOG cursor
--                    (_caad4c, event_main.asm:26626: every character
--                    char_party 0, SCENARIO_MOG in -- the same shape
--                    locke_done ends in).
--
-- THE ROUTE:
--   world (214,149) -> step onto (214,148) -> map 167 (12,25), Crescent
--   Mountain.  Walking UP crosses (12,22) -> _cbc228: the helmet scene --
--   it and every variant gate on $01AB = GAU IN PARTY (and $0041/$0184
--   clear; the train's ending cleared $0184) -- GAU dives for the
--   breathing helmet, "$0041=1" opens the trench.  Then (25,26) -> 168
--   (8,9); the (8,11)/(9,11) row asks "Jump?" ($0041 gate) -- option 0 --
--   and _cbc866's jump runs _ca8ae3: the DIVE.
--
--   THE TRENCH IS A VEHICLE SCRIPT on world map 2 (load_map 2 {117,120}
--   AIRSHIP + set_script_mode VEHICLE, :21163).  move_vehicle commands
--   drive the ride; the player exists only at the two show_arrows windows,
--   where $01B7 ($1EB6 bit 7) picks the branch: LEFT sets it (mainline),
--   RIGHT clears it (detour through the mid-cave 175).  There is no
--   neutral default, so LEFT is held through the whole ride.  Battles
--   19/20/21 fire mid-script with no _ca5ea9 tail -- kill-bit is safe (the
--   vehicle script resumes via PopDP).  $ed climbs monotonically per
--   segment (logged as the progress signal).
--
--   Arrival _ca8be3 (:21288): world walk-on, then Nikeah 187 (24,11).
--   The ferry clerk is NPC (17,15); dlg $032A's OPTION 1 ("Hop aboard?")
--   is the arc's single option-1 prompt -- option 0 loops the dialog
--   forever.  _ca8d22 sails the ship, replays 187 {14,16} for the
--   "stone's throw from Narshe" beat, sets $0044=1 and calls _caad4c: the
--   hub.  (The reunion if_all needs $0021+$001E+$0044 in ONE playthrough;
--   the honest chain has only $0044, so the hub speaks and hands control
--   back -- the stacked replays are where the reunion fires.)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/gau_joined.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

local function settle(toMap, what, budget)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, budget or 6000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[trench] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

-- ride driver with choice steering and trench battle handling
local function ride(dir, pred, what, budget, choiceWant)
  local phase, hb = 0, -900
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "[trench:%s] f%d map=%d (%d,%d) ctl=%s $ed=%04X b=%s dlg=%s "..
          "ch=%d/%d $01B7=%d $0041=%d $0044=%d", what, H.frame, mapIdx(),
          H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          H.readWord(0xed), tostring(inBattle()),
          tostring(H.dialogWaiting()), H.readByte(CH_SEL),
          H.readByte(CH_MAX), (H.readByte(0x1EB6) >> 7) & 1, sw(0x41),
          sw(0x44)))
      end
      if inBattle() or H.battleLoadStarted() then
        if H.monstersPresent() > 0 then
          for s = 0, 5 do
            if monPresent(s) then
              H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
            end
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end
      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the world at Crescent's door")
    H.assertEq(inParty(11), true, "GAU aboard -- the helmet scene's gate")
    H.assertEq(sw(0x41), 0, "$0041 clear -- trench not yet open")
  end),

  -- step into Crescent Mountain
  H.worldNavTo(214, 148, { maxFrames = 4000,
    arrive = function() return not H.worldMode() end }),
  settle(167, "Crescent 167"),

  -- up into (12,22): the helmet scene (GAU + the diving helmet, $0041)
  H.call(function()
    H.log(string.format("[trench] gates: $0184=%d $01AB(par)=%s", sw(0x184),
      tostring(inParty(11))))
    local MOVES = { "up", "down", "left", "right" }
    local DELTA = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0} }
    local sx, sy = H.fieldX(), H.fieldY()
    local seen = { [sy * 256 + sx] = true }
    local q, qi = { { sx, sy } }, 1
    while qi <= #q and qi <= 2000 do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for _, dir in ipairs(MOVES) do
        if H.canStep(x, y, dir) then
          local d = DELTA[dir]
          local k = (y + d[2]) * 256 + (x + d[1])
          if not seen[k] then seen[k] = true; q[#q+1] = { x+d[1], y+d[2] } end
        end
      end
    end
    local rows = {}
    for k in pairs(seen) do
      local y, x = k >> 8, k & 0xFF
      rows[y] = rows[y] or {}
      rows[y][#rows[y]+1] = x
    end
    local ys = {}
    for y in pairs(rows) do ys[#ys+1] = y end
    table.sort(ys)
    for _, y in ipairs(ys) do
      table.sort(rows[y])
      H.log(string.format("  167 y=%d x=%s", y,
        table.concat(rows[y], ",")))
    end
  end),
  H.navTo(12, 23, { maxFrames = 8000 }),
  -- (12,22) runs a PRELIMINARY beat (GAU scampers ahead; the party is
  -- re-parked at (12,17)); the $0041 helmet scene proper is _cbc5fb's
  -- tail, triggered at (25,17)
  (function()
    local sceneSeen = false
    return ride("up", function()
      if not H.hasControl() then sceneSeen = true end
      return sceneSeen and H.hasControl() and H.tileAligned()
         and mapIdx() == 167
    end, "the (12,22) beat", 15000)
  end)(),
  H.navTo(25, 18, { maxFrames = 12000, arrive = function()
    return sw(0x41) == 1 or (H.fieldX() == 25 and H.fieldY() == 18
       and H.hasControl() and H.tileAligned()) end }),
  ride("up", function()
    return sw(0x41) == 1 and H.hasControl() and H.tileAligned()
  end, "helmet scene", 25000),
  H.call(function()
    H.assertEq(sw(0x41), 1, "$0041 -- the trench is open")
    H.log(string.format("[trench] post-helmet: map=%d (%d,%d)", mapIdx(),
      H.fieldX(), H.fieldY()))
  end),

  -- the helmet scene's tail IS the dive (its `if_switch $0127=0, _ca8ae3`
  -- runs straight into the vehicle script -- measured: map 2 mid-ride the
  -- frame control checks resume).  Hold LEFT through the whole ride
  -- (mainline at both arrow windows), kill-bit battles 19/20/21, land at
  -- Nikeah 187.
  ride("left", function() return mapIdx() == 187 end,
    "the trench ride", 60000),
  settle(187, "Nikeah", 8000),
  H.call(function()
    H.assertEq(mapIdx(), 187, "landed in Nikeah")
    H.log(string.format("[trench] Nikeah at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("trench_nikeah")
  end),

  -- the ferry clerk at (17,15): option 1 boards
  H.navTo(17, 16, { maxFrames = 8000 }),
  (function()
    local phase = 0
    return H.driveUntil(function()
      return H.readByte(CH_MAX) >= 2 and H.dialogWaiting()
    end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { "up", "a" } or { "up" })
      end),
    }, "ferry prompt open")
  end)(),
  ride(nil, function()
    return sw(0x44) == 1 and mapIdx() == 9 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, "board + sail + the hub", 40000, 1),

  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 9, "back at the scenario hub, map 9")
    H.assertEq(sw(0x44), 1, "$0044 -- SABIN's scenario is COMPLETE")
    H.assertEq(sw(0x3A), 1, "$003A still set (the train fought)")
    H.assertEq(inParty(5), false, "SABIN dissolved into the hub pool")
    H.log(string.format("[sabin_done] f%d map=%d (%d,%d)", H.frame,
      mapIdx(), H.fieldX(), H.fieldY()))
    H.screenshot("sabin_done")
  end),
  H.saveState("sabin_done.mss"),
  H.logStep(function()
    return string.format("sabin_done minted at frame %d -- the scenario arc "..
      "closes at the hub", H.frame)
  end),
})
