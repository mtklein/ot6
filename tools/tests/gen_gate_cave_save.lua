-- gen_gate_cave_save.lua -- cuts battery checkpoint `gate-cave-save-v1`
-- at the only interior save point in the Sealed Gate cave section, map
-- 386 (74,53), off 384 (64,10).

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

-- the map-385 phaseWalk spec (hurt-tile lists)
local function spec385(over)
  local s = {
    switches = { a = 0x01F5, b = 0x01F6 },
    period = 158,
    region = { w = 17, h = 16 },
    hurt = {
      a = { {7,2},{9,2},{9,4},{5,5},{6,5},{9,5},{13,5},{13,6},{5,7},
            {11,7},{13,7},{14,7},{5,8},{12,9},{6,10},{14,10},{10,11} },
      b = { {4,2},{5,2},{6,2},{5,3},{7,3},{8,3},{9,3},{11,4},{11,5},
            {3,7},{10,8},{11,8},{12,8},{13,8},{14,8},{7,9},{10,9},{9,11} },
      always = { {15,10} },
    },
  }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

-- grind-and-replan world walker
local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        plan = nil; H.setPad({ l = true, r = true }); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- unconditional held walk (dialogs/battles absorbed); for trigger tiles
-- and scripted stretches where control flickers
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function flyTo(tx, ty)
  local calm, hb = 0, -300
  return H.driveUntil(function()
    calm = (shipX() == tx and shipY() == ty) and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      if H.frame - hb >= 300 then
        hb = H.frame
        H.log(string.format("[fly] f%d ship=(%d,%d) $c2=%02X",
          H.frame, shipX(), shipY(), H.readByte(0xc2)))
      end
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty))
end

-- drive the current choice dialog to idx and confirm
local function choicePick(idxIn, donePred, maxFrames, what)
  local ph = 0
  return H.driveUntil(donePred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if donePred() then H.setPad({}); return end
      local idx = type(idxIn) == "function" and idxIn() or idxIn
      local d3, maxc, cur =
        H.readByte(0x00d3), H.readByte(0x056f), H.readByte(0x056e)
      if maxc >= 2 then
        if cur < idx then H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then H.setPad(ph < 3 and { "up" } or {})
        else H.setPad(ph < 3 and { "a" } or {}) end
      elseif d3 == 1 then
        H.setPad(ph < 3 and { "a" } or {})
      else
        H.setPad({})
      end
    end),
  }, what)
end

-- ------------------------- party menu driver --------------------------
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
local function cursorCell()
  return H.readByte(0x004b) + H.readByte(0x004a) + H.readByte(0x005a)
end
local function decode(cell)
  if cell < 0x10 then
    return { area = "pool", col = cell % 8, row = cell >= 8 and 1 or 0 }
  end
  local b = cell - 0x10
  return { area = "party", col = b >> 1, row = b & 1 }
end
local function stepToward(cur, tgt)
  local c, t = decode(cur), decode(tgt)
  if c.area == "pool" and t.area == "party" then return "down"
  elseif c.area == "party" and t.area == "pool" then return "up"
  elseif c.area == "pool" then
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
  else
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
  end
  return nil
end
local function menuAct(tgtIn, btn, doneState, what)
  local phase, settled = 0, 0
  local function tgt() return type(tgtIn) == "function" and tgtIn() or tgtIn end
  return H.driveUntil(function()
    return mst() == doneState and cursorCell() == tgt() and settled >= 8
  end, 4000, {
    H.call(function()
      phase = (phase + 1) % 10
      if mst() == doneState then
        settled = settled + 1
        H.setPad({})
        return
      end
      settled = 0
      if mst() == 0x69 then H.setPad({}); return end
      local cur = cursorCell()
      if cur ~= tgt() then
        local b = stepToward(cur, tgt())
        if not b then H.setPad({}); return end
        H.setPad(phase < 4 and { [b] = true } or {})
        return
      end
      H.setPad(phase < 4 and { [btn] = true } or {})
    end),
  }, what)
end
local function cellOf(charId)
  for c = 0, 0x13 do
    if cell9d(c) == charId then return c end
  end
  return nil
end

-- ------------------------------------------------------------ TERRA's kit --
-- TERRA rejoins the party in the swap room holding nothing; this is the
-- first moment she can be equipped.  $0E Blizzard (slash, ice) matches
-- this area's weakness; $6A Hair Band and $84 LeatherArmor are the bag's
-- spares.  Her shield and relic rows stay empty (no spares in the bag).
local EMPTY = 0xFF
local CH_TERRA = 0
local function gear(c, off) return H.readByte(0x1600 + 37 * c + off) end
local function ordOf(c) return (H.readByte(0x1850 + c) >> 3) & 0x03 end

-- Fill one empty gear slot from the bag.  Both guards matter:
-- H.equipWeapon's list seek walks pre-filtered menu rows, so a missing
-- item times out rather than failing cleanly, and an occupied slot must
-- not be overwritten.  Slot n's byte is +$1F+n (R-Hand, L-Hand, Helmet,
-- Armor, Relic 1, Relic 2).
local function fill(c, pos, slot, id, tag)
  return H.cond(function()
    return gear(c, 0x1F + slot) == EMPTY and H.invCountOf(id) > 0
  end, { H.equipWeapon(pos, id, { slot = slot, tag = tag }) }, {})
end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the narshe-mission world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900,
    "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("narshe-mission-v1")
    H.assertEq(H.worldX(), 84, "boot world x (the Narshe exit spawn)")
    H.assertEq(H.worldY(), 34, "boot world y")
    H.assertEq(H.readByte(0x1F62), 84, "the Blackjack is parked at (84,.) -- $1F62")
    H.assertEq(H.readByte(0x1F63), 36, "the Blackjack is parked at (.,36) -- $1F63")
  end),

  -- ---- 1. board + lift off, X to the deck, down to the swap room --------
  worldGrind(84, 36, "walk onto the parked ship tile (84,36)"),
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function()
    return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
  end, 900, "liftoff (the flight view zeroes $E0/$E2)", 5),
  H.waitFrames(240),
  H.pressButtons({ "x" }, 8),
  H.waitUntil(landed(6, 20), 1800, "the Blackjack deck (map 6)", 1),
  H.waitFrames(30),
  pressWalk("right", function() return map() == 7 end, 900,
    "held RIGHT along row 6 -> deck door (20,6) -> map 7"),
  H.waitUntil(landed(7, 10), 1200, "map 7 landing", 1),
  H.navTo(40, 17, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldY() >= 45 and H.tileAligned()
  end, 900, "stairs (40,18) -> the swap room (50,51)"),
  H.waitFrames(45),

  -- ---- 2. seat TERRA: chase-talk, YES, the party menu --------------------
  H.chaseTalk(0x16, 9000, "chase-talk the wandering TERRA NPC"),
  choicePick(1, function()
    return menuUp() and mst() == 0x2d and H.readByte(0x0200) == 4
  end, 3000, "YES on $0528 -> the party menu"),
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu at $2d", 5),
  H.waitFrames(20),
  (function()
    local steps = {}
    local wanted = { { 0x00, "TERRA" }, { 0x01, "LOCKE" },
                     { 0x04, "EDGAR" }, { 0x05, "SABIN" } }
    for _, w in ipairs(wanted) do
      local charId, name = w[1], w[2]
      local src, dst
      steps[#steps + 1] = H.waitUntil(function() return mst() == 0x2d end,
        900, name .. ": menu ready", 5)
      steps[#steps + 1] = H.call(function()
        src = cellOf(charId)
        assert(src and src < 0x10, name .. " not in the pool")
        dst = nil
        for c = 0x10, 0x13 do
          if cell9d(c) == 0xFF then dst = c; break end
        end
        assert(dst, "no empty party cell for " .. name)
      end)
      steps[#steps + 1] = menuAct(function() return src end, "a", 0x2e,
        name .. ": pick")
      steps[#steps + 1] = menuAct(function() return dst end, "a", 0x2d,
        name .. ": drop")
      steps[#steps + 1] = H.call(function()
        H.assertEq(cell9d(dst), charId, name .. " in the party cell")
      end)
    end
    return H.seqStep(steps)
  end)(),
  H.waitUntil(function() return mst() == 0x2d end, 600,
    "menu at $2d for commit", 5),
  H.pressButtons({ "start" }, 6),
  H.waitUntil(function() return not menuUp() end, 1200, "menu closed", 5),
  H.waitUntil(landed(7, 20), 3000, "back on map 7 after update_party", 1),
  H.call(function()
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1 (the base's hard gate)")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    H.assertEq(partyOf(0x04), 1, "EDGAR in party 1")
    H.assertEq(partyOf(0x05), 1, "SABIN in party 1")
    H.assertEq(partyOf(0x09), 0, "SETZER benched")
    H.screenshot("step_gh_swapped")
  end),

  -- ---- 2b. TERRA's kit, the moment she is seated -------------------------
  -- The char-select row is asserted rather than assumed: H.equipWeapon
  -- seeks the cursor to a fixed row, the party's order field ($1850 bits
  -- 3-4), so a party seated in a different order would dress the wrong
  -- character.
  H.call(function()
    H.assertEq(ordOf(CH_TERRA), 0, "TERRA is char-select row 0")
    H.log(string.format("[kit] TERRA gear before: %02X %02X %02X %02X",
      gear(CH_TERRA, 0x1F), gear(CH_TERRA, 0x20), gear(CH_TERRA, 0x21),
      gear(CH_TERRA, 0x22)))
  end),
  -- Strongest-first ladder: the EMPTY-slot guard makes the first present
  -- weapon land and every later rung skip.  The fighting lineage's bag
  -- may lack the Blizzard (a fled-route chest), but the Cranes fix freed
  -- LOCKE's ThunderBlade, and every rung is mask-valid for TERRA.
  fill(CH_TERRA, 0, 0, 0x0E, "TERRA Blizzard"),
  fill(CH_TERRA, 0, 0, 0x0F, "TERRA ThunderBlade"),
  fill(CH_TERRA, 0, 0, 0x0B, "TERRA RegalCutlass"),
  fill(CH_TERRA, 0, 0, 0x0A, "TERRA MithrilBlade"),
  fill(CH_TERRA, 0, 0, 0x01, "TERRA MithrilKnife"),
  fill(CH_TERRA, 0, 0, 0x00, "TERRA Dirk"),
  -- The cave's pool is the coverage table's "spirits: bludgeon-immune,
  -- arcane-elemental" -- four fights of unmoved sh4 proved no physical
  -- class chips here, and the Ninjas ABSORB fire.  The keys the party
  -- can field: RAMUH's Bolt on TERRA and SHIVA's Ice on SABIN (worn
  -- since the terra-returned cut; re-equipped only if lost, because an
  -- A on a worn stone REMOVES it).
  H.cond(function() return gear(CH_TERRA, 0x1E) ~= 0x00 end, {
    H.equipEsper(function() return ordOf(CH_TERRA) end, 0x00,
      { tag = "RAMUH -> TERRA (Bolt for the spirits)" }),
  }, {}),
  H.cond(function() return gear(5, 0x1E) ~= 0x02 end, {
    H.equipEsper(function() return ordOf(5) end, 0x02,
      { tag = "SHIVA -> SABIN (Ice for the spirits)" }),
  }, {}),
  fill(CH_TERRA, 0, 2, 0x6A, "TERRA Hair Band"),
  fill(CH_TERRA, 0, 3, 0x84, "TERRA LeatherArmor"),
  H.waitUntil(landed(7, 10), 2400, "map 7 control back after the equip stop", 1),
  H.call(function()
    -- The exit contract for the kit.  Without it an equip stop that
    -- silently did nothing and one that worked report the same green.
    H.assertEq(gear(CH_TERRA, 0x1F) ~= EMPTY, true,
      "TERRA leaves the swap room holding a weapon")
    H.log(string.format("[kit] TERRA gear after:  %02X %02X %02X %02X",
      gear(CH_TERRA, 0x1F), gear(CH_TERRA, 0x20), gear(CH_TERRA, 0x21),
      gear(CH_TERRA, 0x22)))
  end),

  -- ---- 3. wheel, fly to the base pass, walk the base, into the cave ------
  H.navTo(40, 11, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 6000 }),
  pressWalk("up", function() return map() == 6 end, 900,
    "door (40,10) -> the deck"),
  H.waitUntil(landed(6, 10), 1200, "deck again", 1),
  H.navTo(14, 6, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 6000, calmFrames = 8 }),
  -- $0170 is SET on this chain, so the wheel opens dlg $052A and only an
  -- EDGE of A opens it -- LEFT+A edges until the choice list is up
  (function() local ph = 0
    return H.driveUntil(function()
      return H.readByte(0x056f) >= 2 or H.worldMode()
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a", left = true } or { left = true })
      end),
    }, "LEFT+A on the wheel -> the lift-off choice")
  end)(),
  choicePick(function() return H.readByte(0x056f) >= 3 and 1 or 0 end,
    function() return H.worldMode() end, 3000, "(Lift-off)"),
  H.release(),
  H.waitFrames(150),
  flyTo(163, 194),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(0xc2) & 0x02, 0,
      "(163,194) landable under the ship")
  end),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
    1200, "grounded at the base pass", 10),
  H.waitFrames(120),
  (function() local ph = 0
    return H.driveUntil(function()
      return H.worldX() == 164 and H.worldY() == 194 and H.worldAligned()
    end, 1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ right = true }) end),
    }, "step off RIGHT to (164,194)")
  end)(),
  H.release(), H.waitFrames(30),
  pressWalk("right", function() return not H.worldMode() and map() == 377 end,
    900, "(165,194) -> IMPERIAL BASE (377)"),
  H.waitUntil(landed(377, 10), 2400, "base landing", 1),
  pressWalk("right", function() return sw(0x0172) == 1 end, 20000,
    "held RIGHT onto (7,17) -> the no-soldiers beat -> $0172"),
  H.waitFrames(60),
  pressWalk("right", function()
    return H.fieldX() >= 9 and H.tileAligned() and H.hasControl()
  end, 2400, "held RIGHT off the entrance trigger row"),
  H.waitFrames(45),
  H.navTo(30, 12, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("right", function() return H.worldMode() end, 900,
    "east door (31,12) -> world (167,194)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 2400, "world pocket", 5),
  worldGrind(168, 194, "pocket walk -> (168,194)"),
  pressWalk("right", function() return not H.worldMode() and map() == 382 end,
    900, "(169,194) -> CAVE TO THE SEALED GATE (382)"),
  H.waitUntil(landed(382, 10), 2400, "382 landing", 1),
  H.fieldCare({ tag = "care entering the gate cave (382)", threshold = 0.85 }),
  H.openChest{ stand = { 36, 40 }, face = "up", bit = 122, what = "Assassin",
               nav = { playBattles = "flee" } },
  H.navTo(31, 42, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 15000,
    arrive = function() return map() == 383 end }),
  pressWalk("down", function() return map() == 383 end, 900,
    "door (31,43) -> BASEMENT 1 (383)"),
  H.waitUntil(landed(383, 10), 2400, "383 landing", 1),
  H.fieldCare({ tag = "care in BASEMENT 1 (383)", threshold = 0.85 }),
  H.openChest{ stand = { 48, 57 }, face = "up", bit = 123, what = "Tempest",
               nav = { playBattles = "flee" } },
  H.navTo(53, 57, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 20000,
    arrive = function() return map() == 385 end }),
  pressWalk("down", function() return map() == 385 end, 900,
    "door (53,58) -> BASEMENT 2 (385), the timed floor"),
  H.waitUntil(landed(385, 10), 2400, "385 landing", 1),
  H.call(function()
    H.assertEq(H.fieldX(), 1, "385 entry x")
    H.assertEq(H.fieldY(), 2, "385 entry y")
  end),

  -- ---- 4. the timed floor -------------------------------------------------
  pressWalk("right", function() return H.fieldX() >= 3 end,
    1800, "held RIGHT onto the cycle-A arming trigger (3,2)"),
  H.waitUntil(function() return sw(0x01F0) == 1 end, 900,
    "cycle A armed ($01F0)", 2),
  H.phaseWalk(3, 7, spec385({ maxFrames = 20000,
    what = "phaseWalk to the Coin Toss chest stand (3,7)" })),
  H.openChest{ stand = { 3, 7 }, face = "down", bit = 133, what = "Coin Toss",
               nav = { playBattles = "flee", calmFrames = 4 } },
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() == 4 and H.fieldY() == 7 and H.tileAligned()
    end, 600, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ right = true })
      end),
    }, "step off the hurt-in-B stand -> (4,7)")
  end)(),
  H.phaseWalk(11, 3, spec385({ maxFrames = 20000,
    what = "phaseWalk across row 2 to the cycle-B trigger (11,3)" })),
  H.waitUntil(function() return sw(0x01F1) == 1 end, 900,
    "cycle B armed ($01F1)", 2),
  H.phaseWalk(14, 3, spec385({ maxFrames = 20000,
    avoid = { { 3, 2 }, { 10, 2 } },
    what = "phaseWalk east to the X-Potion chest stand (14,3)" })),
  H.openChest{ stand = { 14, 3 }, face = "down", bit = 134, what = "X-Potion",
               nav = { playBattles = "flee" } },
  H.phaseWalk(13, 12, spec385({ maxFrames = 30000,
    avoid = { { 3, 2 }, { 10, 2 } },
    what = "phaseWalk down the east half to (13,12)" })),
  pressWalk("down", function() return map() == 384 end, 2400,
    "held DOWN onto (13,13) -> BASEMENT 3 (map 384)"),
  H.waitUntil(landed(384, 10), 2400, "384 landing", 1),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.fieldX(), 26, "384 landing x")
    H.assertEq(H.fieldY(), 8, "384 landing y")
    H.screenshot("step_gh_384")
  end),
  -- BASEMENT 3 is the longest, encounter-heaviest leg (290 pre-lever tiles);
  -- enter it topped up, and top up again mid-way (after the Ether) so the
  -- south loop to the save door cannot bleed anyone out.
  H.fieldCare({ tag = "care entering BASEMENT 3 (384)", threshold = 0.85 }),

  H.openChest{ stand = { 29, 22 }, face = "down", bit = 124, what = "Ether",
               nav = { playBattles = "flee", maxFrames = 20000 } },
  H.fieldCare({ tag = "care mid-BASEMENT 3, before the save-door loop",
                threshold = 0.85 }),
  H.navTo(62, 11, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 30000 }),
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x0173) == 1 end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); return
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad(ph < 4 and { "up", "a" } or { "up" })
      end),
    }, "face-UP+A on (62,11) -> $0173 (the save-room door)")
  end)(),
  H.waitFrames(60),
  H.navTo(64, 11, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 9000 }),
  pressWalk("up", function() return map() == 386 end, 1200,
    "held UP onto the save-room door (64,10) -> map 386"),
  H.waitUntil(landed(386, 10), 2400, "386 landing", 1),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.fieldX(), 73, "386 arrival x (short entrance 384 (64,10))")
    H.assertEq(H.fieldY(), 58, "386 arrival y")
  end),
  H.openChest{ stand = { 77, 53 }, face = "up", bit = 68, what = "Tent",
               nav = { playBattles = "flee" } },
  H.fieldCare({ tag = "care before the gate-cave save", threshold = 0.95 }),
  H.navTo(74, 54, { playBattles = "flee", careThreshold = 0.85, healPercent = 45, magic = { [0] = { spell = 2 }, [5] = { spell = 1 } }, maxFrames = 9000 }),
  (function()
    local phase, n, ph, calm = 0, 0, 0, 0
    local function calmPred()
      return H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted()
    end
    local function pred()
      return H.fieldX() == 74 and H.fieldY() == 53 and sw(0x01BF) == 1
    end
    return H.driveUntil(function()
      calm = (pred() and calmPred()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); phase = 0; return
        end
        if H.dialogWaiting() then
          H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
        end
        if phase == 0 then
          H.setPad({})
          if pred() then return end
          if calmPred() then phase, n = 1, 0 end
          return
        end
        if phase == 1 then
          n = n + 1
          H.setPad({ up = true })
          if n >= 8 then phase, n = 2, 0 end
          return
        end
        H.setPad({})
        n = n + 1
        if n >= 24 then phase = 0 end
      end),
    }, "tap UP onto the save point (74,53) -> $01BF")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the SavePoint script ran")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch")
    H.assertExitContractPreSave("gate-cave-save-v1")

    H.assertPartyStanding("gate-cave-save-v1 exit")
    H.screenshot("step_gh_save_tile")
  end),
  -- THE STEP'S SAVESTATE IS GENERATED HERE, on the save tile, before the menu
  H.saveState("gate_cave_save.mss"),

  -- ---- 6. the real Save UI, slot 3 ---------------------------------------
  -- $0059 alone blips nonzero on a save tile (the SavePoint re-entry); a
  -- real menu is 30 consecutive frames of it.
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) ~= 0) and calm + 1 or 0
      return calm >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "field menu open on the save tile")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
  end),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) == 0) and calm + 1 or 0
      return calm >= 30
    end, 900, {
      H.pressButtons({ "b" }, 4), H.waitFrames(20),
    }, "field menu closed")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertExitContract("gate-cave-save-v1")
    H.screenshot("step_gh_saved")
  end),
  H.logStep(function()
    return string.format("gate-cave-save-v1 saved via the real Save UI at "
      .. "frame %d -- map 386 (74,53), slot 3; boundary H of the v0.7 range",
      H.frame)
  end),
})
