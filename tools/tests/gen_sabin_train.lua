-- gen_sabin_train.lua -- leg 8 of SABIN's scenario: the Phantom Train,
-- boarding to the Ghost Train's fall.  Mints:
--   train_done.mss   World of Balance (178,93), on foot, $003A/$003B set,
--                    SABIN+CYAN+SHADOW -- the Baren Falls leg builds here.
--
-- THE MAZE, as measured (probe_train, probe_train2, probe_train3 -- the
-- floods and the trap forensics live in their headers and commits):
--
--  * The train is TWO exterior side-view strips (142 rear, 141 front) and a
--    handful of interior maps REUSED per physical car -- 145 plays car A
--    ($017E=$0180=0), car B ($017E=1) and car C ($0180=1); $0506/$0507/
--    $0509 pick each car's ghost cast.  $017E/$0180 are car bookkeeping
--    written by every door handler, not a puzzle.  The door "gates"
--    $01B0-$01B4 are UpdateCtrlFlags' live facing/A bits
--    (field/event.asm:5416), so levers/valves fire on facing-up+A.
--  * The forward walk is plain floor: car A's west door lands 142 (66,8)
--    and the y=8 strip reaches (58,8) = car B's east door.  (The old
--    "isolated cluster" claim was measured only from the EAST pocket.)
--  * Car C is entered by its SIDE door, 142 (41,8) facing up (_cba67d:
--    $0180=1, $0509=1).  Walking in fires _cbb399, which RELOCATES the trap
--    ghost from (3,6) to the south door; talking to it at (26,9) facing
--    down runs _cbb265: $017C=1, battle 47, and a hard load to the mob
--    surround at 142 (41,9).  Roof at x=40, west to (34,5) = SABIN's jump
--    (lands (12,8)), mob catch at (11,8) ($0182), car 149 at (10,8).
--  * 149's east vestibule (x=27-31) holds the lever at (28,5).  Pull ONE:
--    $0183, the detach cinematic, hard landing 141 (117,8).  Pull TWO
--    (after re-entering) is the maze's last secret: _cbb7c7 sets $017F and
--    re-tiles the x=26 column -- the inner door between vestibule and car.
--  * From 141 (108,8) THE STRIP IS THE ROUTE: lanes y=8/y=9 weave under
--    the door pockets, the roof (y=5, ladders x=60/65/76/81) bridges the
--    two ground gaps, and no car interior is entered (wrapping tile props
--    poison the BFS).  Waypoints dodge the unguarded door triggers;
--    (55,8)'s ghost-leave event is a measured no-op for a ghostless party.
--  * Engineer door 141 (38,8) accepts entry only from (38,9) facing up.
--    Valves (7,7)/(9,7) toggle $0184/$0186; SHUT/OPEN/SHUT is the
--    smokestack's guard.  (32,7) facing-up+A -> _cbb9d4 -> battle 68.
--
-- THE FIGHT IS FOUGHT FOR REAL: seed rows asserted (GHOSTTRAIN $0106 seeds
-- 6/6 shields with class row $04 = OT6_BLUDG off Ot6ShieldTbl, weakElem $25
-- keeps vanilla fire|bolt|holy), then SABIN's AuraBolt (holy $20) takes a
-- shield and reveals the element, his Pummel (OT6_BLUDG) takes another and
-- reveals the class -- both driven as real pad edges through the Blitz code
-- window, battle_vargas's idiom.  Party HP is pinned per frame and the
-- train is then clamped to 1 hp so the engine's own next swing ends it:
-- the win bit $40 is earned (its event tail is _ca5ea9 -- a kill-bit here
-- is a GameOver-park, measured).  Scripted battle 47 runs the same way.
--
-- THE RIDE OUT: victory scene -> the souls' station (Cyan's family) ->
-- map 137 with a 1200-frame timer -> auto-exit to the world at (178,93),
-- SHADOW steps out for the graveside beat and rejoins before the exit
-- (_cbbedd/_cbbee5).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/forest_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

-- battle model (battle_vargas's map)
local GHOSTTRAIN = 0x0106
local OT6_BLUDG, HOLY = 0x04, 0x20
local PUMMEL, AURABOLT = 0x5D, 0x5E
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_BLITZ = 0x05, 0x3D
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

local gSlot, sabinE = nil, nil          -- found at battle-up, asserted

local function swDump(tag)
  H.log(string.format(
    "[train %s] map=%d (%d,%d) $0039=%d $017C=%d $017E=%d $017F=%d "..
    "$0180=%d $0182=%d $0183=%d $0184=%d $0185=%d $0186=%d $003A=%d $003B=%d",
    tag, mapIdx(), H.fieldX(), H.fieldY(), sw(0x39), sw(0x17C), sw(0x17E),
    sw(0x17F), sw(0x180), sw(0x182), sw(0x183), sw(0x184), sw(0x185),
    sw(0x186), sw(0x3A), sw(0x3B)))
end

-- scripted train fights ("real"): pin the party, clamp the monsters to
-- 1 hp, tap A -- the engine's own swing ends it and the win bit ($40,
-- _ca5ea9's gate) is earned.  Random trash ("killbit"): the house idiom.
local function driveBattle(mode, phase)
  if mode == "real" then
    pinParty()
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1
         and H.readWord(MHP(s)) > 1 then
        H.writeWord(MHP(s), 1)
      end
    end
  else
    if H.monstersPresent() > 0 then
      for s = 0, 5 do
        if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
          H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
        end
      end
    end
  end
  H.setPad(phase < 4 and { "a" } or {})
end

local function holdDrive(dir, pred, what, budget, fightMode)
  local phase, hb = 0, -600
  return H.driveUntil(pred, budget or 15000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("drive[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle())))
      end
      if inBattle() or H.battleLoadStarted() then
        driveBattle(fightMode or "killbit", phase); return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- facing-up+A until pred: the lever/valve/switch idiom ($01B0/$01B4 are
-- live facing/A bits, re-checked every aligned frame)
local function upA(pred, what, budget)
  local phase = 0
  return H.driveUntil(pred, budget or 3000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(phase < 4 and { "up", "a" } or { "up" })
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 4000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function() swDump(what) end),
  }, {})
end

-- keep everyone swinging except when SABIN's own command window is up
local aPh = 0
local function tapUnlessSabin()
  pinParty()
  aPh = (aPh + 1) % 8
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == sabinE then
    H.setPad({})
  else
    H.setPad(aPh < 4 and { "a" } or {})
  end
end

-- one Blitz as real pad edges (battle_vargas's driver): SABIN's command
-- list -> DOWN to Blitz -> A -> the code -> A.  The list-wait also
-- un-sticks a lingering code window (a rejected code can leave SABIN's
-- menu open, which tapUnlessSabin would hands-off forever).
local function blitz(code, name)
  local steps = {
    H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == sabinE
         and H.readByte(MSTATE) == ST_CMD
    end, 12000, { H.call(function()
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == sabinE
         and H.readByte(MSTATE) == ST_BLITZ then
        aPh = (aPh + 1) % 8
        pinParty()
        H.setPad(aPh < 4 and { "b" } or {})   -- back out of a stale window
      else
        tapUnlessSabin()
      end
    end), H.waitFrames(1) },
      name .. ": SABIN's command list"),
    H.waitFrames(10),
    H.pressButtons({ "down" }, 4), H.waitFrames(8),
    H.pressButtons({ "a" }, 4), H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(MSTATE), ST_BLITZ,
        name .. ": the blitz code window is open (menu state $3d)")
    end),
  }
  for _, b in ipairs(code) do
    steps[#steps + 1] = H.pressButtons(b, 4)
    steps[#steps + 1] = H.waitFrames(5)
  end
  steps[#steps + 1] = H.pressButtons({ "a" }, 4)
  steps[#steps + 1] = H.waitFrames(8)
  return H.cond(function() return true end, steps)
end

-- drive one chip to the gauge, retrying the blitz if a cast misses or a
-- code is rejected: each attempt is the real input, and the loop's exit
-- is the ENGINE's gauge write, never a poke.
local function chip(code, name, want)
  local seq = {}
  for attempt = 1, 4 do
    local waited = 0
    seq[#seq + 1] = H.cond(function()
      return H.readByte(SH(gSlot)) > want
    end, {
      H.logStep(function()
        return string.format("[b68] %s attempt %d (shields=%d)",
          name, attempt, H.readByte(SH(gSlot)))
      end),
      blitz(code, name .. " #" .. attempt),
      H.driveUntil(function()
        waited = waited + 1
        return H.readByte(SH(gSlot)) <= want or waited > 2400
      end, 3000, { H.call(tapUnlessSabin), H.waitFrames(1) },
        name .. " #" .. attempt .. " resolve-or-retry"),
      H.call(function()
        H.log(string.format(
          "[b68] %s #%d: shields=%d last=$%02X menu=%d actor=%d mstate=$%02X",
          name, attempt, H.readByte(SH(gSlot)), H.readByte(0x3410),
          H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE)))
      end),
    }, {})
  end
  return H.cond(function() return true end, seq)
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 145, "boot aboard the train, map 145")
    H.assertEq(sw(0x38), 1, "$0038 set -- train discovered")
    H.assertEq(sw(0x39), 0, "$0039 clear -- not yet departed")
    swDump("start")
  end),

  -- ---- rear half ----
  holdDrive("down", function() return sw(0x39) == 1 end, "departure", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "post-departure", 5),
  H.navTo(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "A west exit", 4000),
  settle(142, "west pocket (66,8)"),
  holdDrive("left", function() return mapIdx() == 145 end, "-> car B", 4000),
  settle(145, "car B"),
  H.call(function() H.assertEq(sw(0x17E), 1, "$017E -- this 145 is car B") end),
  H.navTo(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "B west exit", 4000),
  settle(142, "pocket (50,8)"),
  H.navTo(41, 8, { maxFrames = 8000, arrive = function()
    return mapIdx() == 145 or (H.fieldX() == 41 and H.fieldY() == 8
       and H.hasControl() and H.tileAligned()) end }),
  holdDrive("up", function() return mapIdx() == 145 and sw(0x180) == 1 end,
    "-> car C", 4000),
  settle(145, "car C"),
  H.call(function() H.assertEq(sw(0x509), 1, "$0509 -- car C's ghost cast") end),
  holdDrive("up", function()
    return sw(0x3D) == 1 and H.hasControl() and H.tileAligned()
  end, "bait the follower ghost", 4000),
  H.navTo(26, 9, { maxFrames = 3000 }),
  (function()
    local phase = 0
    return H.driveUntil(function() return sw(0x17C) == 1 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "down", "a" } or { "down" })
      end),
    }, "talk to the trap ghost")
  end)(),
  holdDrive("down", function()
    return mapIdx() == 142 and H.hasControl() and H.tileAligned()
       and not inBattle() and bright() >= 15
  end, "battle 47 + mob scene", 30000, "real"),
  H.navTo(40, 8, { maxFrames = 4000 }),
  holdDrive("up", function()
    return H.fieldY() <= 6 and H.hasControl() and H.tileAligned()
  end, "roof climb", 15000),
  holdDrive("up", function()
    return H.fieldY() == 5 and H.hasControl() and H.tileAligned()
  end, "roof top", 4000),
  holdDrive("left", function()
    return H.fieldX() <= 13 and H.hasControl() and H.tileAligned()
  end, "SABIN's jump", 30000),
  holdDrive("down", function()
    return H.fieldY() >= 8 and H.hasControl() and H.tileAligned()
  end, "down to the strip", 6000),
  holdDrive("left", function() return mapIdx() == 149 end,
    "mob catch + car 149", 30000),
  settle(149, "car 149 vestibule"),
  H.navTo(28, 5, { maxFrames = 6000 }),
  upA(function() return sw(0x183) == 1 end, "detach lever", 3000),
  holdDrive("down", function()
    return mapIdx() == 141 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "detach cinematic", 30000),
  H.call(function()
    swDump("detached")
    H.assertEq(sw(0x183), 1, "$0183 -- rear cars detached")
  end),

  -- ---- front half: the second pull, then the strip ----
  holdDrive("left", function() return mapIdx() == 149 end, "re-enter 149", 4000),
  settle(149, "vestibule again"),
  H.navTo(28, 5, { maxFrames = 6000 }),
  upA(function() return sw(0x17F) == 1 end, "second pull -- inner door", 3000),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    2000, "post second pull", 5),
  H.navTo(2, 7, { maxFrames = 10000 }),
  holdDrive("left", function() return mapIdx() == 141 end, "149 west exit", 4000),
  settle(141, "pocket (108,8)"),
  H.navTo(101, 9, { maxFrames = 4000 }),
  H.navTo(90, 9, { maxFrames = 4000 }),
  H.navTo(84, 8, { maxFrames = 3000 }),
  H.navTo(83, 9, { maxFrames = 2000 }),
  H.navTo(81, 9, { maxFrames = 2000 }),
  H.navTo(81, 6, { maxFrames = 2000 }),
  H.navTo(76, 5, { maxFrames = 3000 }),
  H.navTo(76, 7, { maxFrames = 2000 }),
  H.navTo(76, 9, { maxFrames = 2000 }),
  H.navTo(74, 9, { maxFrames = 2000 }),
  H.navTo(74, 8, { maxFrames = 2000 }),
  H.navTo(67, 8, { maxFrames = 3000 }),
  H.navTo(67, 9, { maxFrames = 2000 }),
  H.navTo(65, 9, { maxFrames = 2000 }),
  H.navTo(65, 6, { maxFrames = 2000 }),
  H.navTo(60, 5, { maxFrames = 3000 }),
  H.navTo(60, 8, { maxFrames = 2000 }),
  H.navTo(60, 9, { maxFrames = 2000 }),
  H.navTo(58, 9, { maxFrames = 2000 }),
  H.navTo(52, 8, { maxFrames = 4000 }),
  H.navTo(51, 9, { maxFrames = 2000 }),
  H.navTo(45, 9, { maxFrames = 3000 }),
  H.navTo(45, 8, { maxFrames = 2000 }),
  H.navTo(38, 9, { maxFrames = 3000 }),
  holdDrive("up", function() return mapIdx() == 146 end,
    "engineer entrance", 3000),
  settle(146, "engineer's room"),
  H.navTo(7, 7, { maxFrames = 5000 }),
  upA(function() return sw(0x184) == 1 end, "valve 1 SHUT", 3000),
  H.navTo(9, 7, { maxFrames = 3000 }),
  upA(function() return sw(0x186) == 1 end, "valve 3 SHUT", 3000),
  H.call(function()
    swDump("valves")
    H.assertEq(sw(0x184), 1, "$0184 -- valve 1 shut")
    H.assertEq(sw(0x185), 0, "$0185 -- valve 2 open")
    H.assertEq(sw(0x186), 1, "$0186 -- valve 3 shut")
  end),
  H.navTo(8, 13, { maxFrames = 5000, arrive = function()
    return mapIdx() == 141 end }),
  settle(141, "outside again"),
  H.navTo(32, 7, { maxFrames = 8000 }),
  upA(function() return sw(0x3A) == 1 end, "smokestack switch", 4000),

  -- ---- BATTLE 68: the Ghost Train, fought for real ----
  H.waitUntil(function() return H.battleLoadStarted() end, 3000, "battle 68 up"),
  H.waitUntil(function()
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then return true end
    end
    return false
  end, 1200, "GHOSTTRAIN in the formation", 5),
  H.waitFrames(120),
  H.call(function()
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then gSlot = s end
    end
    for e = 0, 3 do
      if H.readByte(0x3ED8 + e * 2) == 0x05 then sabinE = e end
    end
    H.assertEq(gSlot ~= nil, true, "GHOSTTRAIN found in a monster slot")
    H.assertEq(sabinE ~= nil, true, "SABIN found in a party entity")
    local lv = H.readByte(0x3B18 + sabinE * 2)
    H.log(string.format("[b68] ghosttrain slot %d, SABIN entity %d lv %d",
      gSlot, sabinE, lv))
    H.assertEq(lv >= 6, true, "SABIN level 6+ -- AuraBolt learned")
    -- the authored row, live: this is the runtime proof of GhostTrain's
    -- 6-shield OT6_BLUDG entry in Ot6ShieldTbl
    H.assertEq(H.readByte(SH(gSlot)), 6, "GHOSTTRAIN seeds 6 shields")
    H.assertEq(H.readByte(SMX(gSlot)), 6, "GHOSTTRAIN max shields 6")
    H.assertEq(H.readByte(WKC(gSlot)), OT6_BLUDG,
      "GHOSTTRAIN's class row is OT6_BLUDG")
    H.assertEq(H.readByte(WKE(gSlot)) & HOLY, HOLY,
      "holy in the weak byte (vanilla fire|bolt|holy)")
    H.assertEq(H.readByte(RVE(gSlot)), 0, "nothing revealed yet (elements)")
    H.assertEq(H.readByte(RVC(gSlot)), 0, "nothing revealed yet (classes)")
    H.screenshot("train_b68_up")
  end),

  -- AURABOLT: holy takes a shield and reveals the element
  chip({ { "down" }, { "down", "left" }, { "left" } }, "AURABOLT", 5),
  H.call(function()
    H.assertEq(H.readByte(0x3410), AURABOLT,
      "the resolved skill was AuraBolt ($5e)")
    H.assertEq(H.readByte(SH(gSlot)), 5, "AURABOLT took a shield: 6 -> 5")
    H.assertEq(H.readByte(RVE(gSlot)) & HOLY, HOLY, "holy revealed")
    H.log(string.format("[b68] after AURABOLT shields=%d revE=$%02X revC=$%02X",
      H.readByte(SH(gSlot)), H.readByte(RVE(gSlot)), H.readByte(RVC(gSlot))))
  end),

  -- PUMMEL: bludgeon takes a shield and reveals the class
  chip({ { "left" }, { "right" }, { "left" } }, "PUMMEL", 4),
  H.call(function()
    H.assertEq(H.readByte(0x3410), PUMMEL,
      "the resolved skill was Pummel ($5d)")
    H.assertEq(H.readByte(SH(gSlot)), 4, "PUMMEL took a shield: 5 -> 4")
    H.assertEq(H.readByte(RVC(gSlot)) & OT6_BLUDG, OT6_BLUDG,
      "the bludgeon class revealed")
    H.log(string.format("[b68] after PUMMEL shields=%d revE=$%02X revC=$%02X",
      H.readByte(SH(gSlot)), H.readByte(RVE(gSlot)), H.readByte(RVC(gSlot))))
    H.screenshot("train_b68_chipped")
  end),

  -- finish: clamp the train to 1 hp, the party's own swings end it
  H.driveUntil(function() return not inBattle() end, 20000, {
    H.call(function()
      pinParty()
      if H.readWord(MHP(gSlot)) > 1 then H.writeWord(MHP(gSlot), 1) end
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the Ghost Train falls"),

  -- ---- the ride out: victory scene, the station, the timer, the world ----
  (function()
    local phase, hb = 0, -900
    return H.driveUntil(function()
      return H.worldMode() and H.worldHasControl()
    end, 60000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.frame - hb >= 900 then
          hb = H.frame
          H.log(string.format("ride f%d map=%d world=%s dlg=%s $003B=%d",
            H.frame, mapIdx(), tostring(H.worldMode()),
            tostring(H.dialogWaiting()), sw(0x3B)))
        end
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "ride the ending to the world map")
  end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end,
    3000, "world control", 5),
  H.waitUntil(function() return bright() >= 15 end, 1200, "world fade", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the World of Balance")
    H.assertEq(H.worldX(), 178, "world x=178")
    H.assertEq(H.worldY(), 93, "world y=93")
    H.assertEq(sw(0x3A), 1, "$003A set -- the Ghost Train fought")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train ride is over")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(inParty(3), true, "SHADOW in the party (rejoined, $018D dance)")
    H.log(string.format("[train_done] f%d world (%d,%d)",
      H.frame, H.worldX(), H.worldY()))
    H.screenshot("train_done")
  end),
  H.saveState("train_done.mss"),
  H.logStep(function()
    return string.format("train_done minted at frame %d world (%d,%d)",
      H.frame, H.worldX(), H.worldY())
  end),
})
