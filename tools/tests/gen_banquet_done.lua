-- gen_banquet_done.lua -- v0.7 LEG I->J (issue #31), and the generator
-- that cuts battery anchor J, `banquet-done-v1`.
--
-- The leg (banquet-decode.md is the script; sealed-gate-recon.md §1 legs
-- 5-6 the route): cold-Continue the tracked `vector-crash-v1` battery
-- (boundary I -- world (83,238), standing ON the dead Blackjack; NO A
-- press on the boot tile, it re-enters the wreck -- addenda SS3.5),
-- assert its contract, then:
--   1. the ~117-step world grind to the Vector trigger (120,187) -- the
--      $0079=1 path loads post-attack Vector 253 at (32,61);
--   2. the castle: 253 (28,1) -> 243 (15,29), the (8,18) escort
--      ($013A=1, $062F=1, opens the (15,8) door), 250 (23,33) (map-init
--      opens the {22,29} door, $013B=1), the dais (54,16);
--   3. THE WINDOW (banquet-decode §5.2 step 2): face-UP+A starts
--      _cc8490 -- $007C=1, var0=0, start_timer 0,14400.  Talk to all 24
--      scoring soldiers (§3 census; eleven wander -- H.chaseTalk against
--      extracted object indices) and win the four fights (battles 26/27,
--      kill-bit -- a kill-bit win leaves $40/$44/$45 CLEAR, measured
--      §5.4).  Per fight: species at $3F46, $1dd1 & $31 == 0, var0 +6.
--      Every soldier step also terminates on $013C=1 = the window died
--      first: that is a loud, named failure carrying var0/timer -- the
--      §8 feasibility measurement -- never a quietly lower tier;
--   4. the expiry (wherever the party stands), map 5, the dinner 251;
--   5. THE Q&A driven to the full 93 (§5.2 steps 4-6): hometowns/jail/
--      inexcusable/one-of-us (+5 each), the three questions exactly once
--      (+2 each, q0 first), Espers +5, recall q0 +5, the rest break, the
--      troopers' challenge (battle 30 inside its own 7200 timer, +5
--      clean), begin-again, "war's truly over" +5, accompany-Yes +3;
--   6. the Leo intro, the roster rewrite -- party FORCED to TERRA+LOCKE,
--      availability rewritten wholesale, equipment of the benched
--      returned to inventory, $007D=1, control back on 251;
--   7. the messenger at 250 (23,12): all four tiers paid ($0276/77/78,
--      Tintinabar, Charm Bangle -- var0==93 asserted BEFORE the scene,
--      the score receipt), $0238=1, var0 back to 0;
--   8. out: 250 (22..24,34) -> 243 -> south rows (11-19,31) -> 253
--      (29,2) -> the (30,63) world exit -> world (120,188);
--   9. the world battery save on that tile -- boundary J,
--      `banquet-done-v1` (the recon §2.2 table's own name for it).
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses -- BEFORE boot -- any OT6_SRAM_ANCHOR whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function timerCount() return H.readWord(0x1189) end
local function var0() return H.readWord(0x1fc2) end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- VERIFIED-STEP world grinder.  The shared grind-and-replan idiom
-- (gen_vector_doorstep's) consumes one plan entry per ALIGNED FRAME, and
-- the party sits aligned for several frames before each press latches --
-- on straight lines the wasted entries agree in direction and nothing
-- shows, but every TURN of a long path desyncs the plan and forces a
-- 60000-node replan.  Measured on this leg's ~117-step grind (run 4,
-- 2026-07-28): ~139 frames/tile, a (73,221)<->(73,222) oscillation with
-- plan lengths jumping 86->93, and the emulator dragged to ~40fps by the
-- per-replan BFS.  This version consumes an entry only when the party
-- LANDS on that entry's destination tile (navTo's rule, worldized): one
-- BFS per leg plus one per battle return, 16 frames/tile.
local function worldGrind(tx, ty, what)
  local plan, idx, ph, hb = nil, 1, 0, -600
  local step = nil
  local DW = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); plan = nil; step = nil
        H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then
        plan = nil; step = nil; H.setPad({}); return
      end
      if not H.worldAligned() then return end   -- hold through the glide
      local x, y = H.worldX(), H.worldY()
      if step then
        if x == step.tx and y == step.ty then
          step = nil; idx = idx + 1               -- landed: next entry
        elseif x ~= step.fx or y ~= step.fy then
          plan = nil; step = nil                  -- drifted: replan
        else
          step.held = step.held + 1
          if step.held > 90 then                  -- press provably dead
            plan = nil; step = nil; H.setPad({}); return
          end
          H.setPad({ [step.dir] = true }); return
        end
      end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[grind] NO PATH (%d,%d)->(%d,%d) f%d",
              x, y, tx, ty, H.frame))
          end
          H.setPad({}); return
        end
      end
      local dir = plan[idx]
      local d = DW[dir]
      step = { dir = dir, fx = x, fy = y,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, held = 0 }
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- unconditional held walk (dialogs/battles absorbed)
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- The DAIS is a face-UP+A trigger the party must be STANDING ON: the
-- gate is `$01B4=0 or $01B0=0 or $007C=1 -> EventReturn` (_cc8490,
-- event_main.asm:97243-97247) -- $01B0 = facing up, $01B4 = A HELD.
-- M.tapLever is the wrong drive here: it releases A after 8 frames and
-- then only holds UP, so the gate reads A clear forever (measured, stage
-- run 9: 9000 frames, no latch).  What makes facing-up work without
-- walking off the tile is the GESTAHL NPC standing at (54,15) -- the
-- $062E object (npc_prop map-250 record 5), which blocks the step the
-- same way gen_sabin_train's upA holds into a wall.  So: stand on
-- (54,16), hold UP+A, with a 2-frame A release every 8 so the edge
-- re-arms.
local function holdUpA(swId, maxFrames, what)
  local n = 0
  return H.driveUntil(function() return sw(swId) == 1 end, maxFrames, {
    H.call(function()
      n = n + 1
      if H.dialogWaiting() then H.setPad(n % 8 < 4 and { "a" } or {}); return end
      H.setPad(n % 8 < 6 and { up = true, a = true } or { up = true })
    end),
  }, what)
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

-- edge-A through dialogs until settled
local function settle(maxFrames, what)
  local ph = 0
  return H.driveUntil(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and not H.battleLoadStarted()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
    end),
  }, what)
end

-- ---- the window circuit (banquet-decode §3 census + §5.2 order) ----------
local expect = 0
local function ckTimer(name)
  return H.call(function()
    H.log(string.format("[circuit] %-28s timer=%5d var0=%2d f%d",
      name, timerCount(), var0(), H.frame))
  end)
end

local function soldier(objIdx, latch, what)
  expect = expect + 1
  local want = expect
  return {
    H.chaseTalk(objIdx, 12000, what, {
      done = function() return sw(latch) == 1 or sw(0x013C) == 1 end,
    }),
    H.call(function()
      if sw(0x013C) == 1 and sw(latch) == 0 then
        error(string.format(
          "WINDOW EXPIRED during %s: var0=%d of 44, frame %d",
          what, var0(), H.frame), 0)
      end
      H.assertEq(sw(latch), 1, what .. ": latch set")
      H.assertEq(var0(), want, what .. ": var0 (+1 talk)")
    end),
    ckTimer(what),
  }
end

local function fightSoldier(objIdx, latch, species, what)
  expect = expect + 6
  local want = expect
  return {
    H.chaseTalk(objIdx, 18000, what, {
      done = function() return sw(latch) == 1 or sw(0x013C) == 1 end,
    }),
    H.call(function()
      if sw(0x013C) == 1 and sw(latch) == 0 then
        error(string.format(
          "WINDOW EXPIRED during %s: var0=%d of 44, frame %d",
          what, var0(), H.frame), 0)
      end
      H.assertEq(sw(latch), 1, what .. ": latch set")
      local w, found = H.formationWords(), false
      for i = 1, 6 do if w[i] == species then found = true end end
      H.assertEq(found, true, string.format(
        "%s: species $%03X in the formation words", what, species))
      H.assertEq(H.readByte(0x1dd1) & 0x31, 0,
        what .. ": clean win -- b-switches $40/$44/$45 all clear")
      H.assertEq(var0(), want, what .. ": var0 (+1 talk, +5 clean)")
    end),
    ckTimer(what),
  }
end

local function hop(x, y, pred, what, maxF)
  return {
    H.navTo(x, y, { maxFrames = maxF or 20000, arrive = pred }),
    H.waitUntil(function()
      return pred() and H.tileAligned() and bright() >= 15
         and not H.dialogWaiting() and not H.battleLoadStarted()
    end, 2400, what .. " (landing)", 1),
    H.waitFrames(20),
    ckTimer(what),
  }
end

-- ---- the Q&A choice machinery (gen_zozo3_clock's cursor cells) -----------
local function picks(targets, done, maxFrames, what)
  local ph, ti, wasUp = 0, 0, false
  return H.driveUntil(function()
    local d = done()
    if d then H.setPad({}) end
    return d
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); wasUp = false; return
      end
      local up = H.readByte(0x056f) >= 2
      if up and not wasUp then ti = ti + 1 end
      wasUp = up
      if up then
        local idx = targets[math.min(ti, #targets)]
        local cur = H.readByte(0x056e)
        if cur < idx then H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then H.setPad(ph < 3 and { "up" } or {})
        else H.setPad(ph < 3 and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

local function atLeast(n) return function() return var0() >= n end end
local function ckVar(name, want)
  return H.call(function()
    H.assertEq(var0(), want, name .. ": var0")
    H.log(string.format("[qa] %-28s var0=%2d f%d", name, var0(), H.frame))
  end)
end

-- --------------------------------------------------------------------------
local steps = {
  -- ---- the cold Continue and the ENTRY CONTRACT (issue #25) ---------------
  -- worldMode() reads true at the title screen too (stage probe run 1),
  -- so the A presses are gated on brightness (menus lit, load fades dark)
  -- and disarmed forever once the world is up AT (83,238): the boot tile
  -- is the wreck and one stray A walks back inside (addenda SS3.5).
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function() local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 83 and H.worldY() == 238
    end
    return H.driveUntil(function()
      return atSite() and bright() >= 15
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> crash-site world load (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the crash site", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEntryContract("vector-crash-v1")
  end),

  -- ---- 1. the grind to Vector ----------------------------------------------
  worldGrind(120, 188, "the I->J world grind -> (120,188)"),
  pressWalk("up", function() return not H.worldMode() end, 900,
    "step onto the Vector trigger (120,187)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253 (post-attack)", 1),
  H.waitFrames(30),

  -- ---- 2. the castle and the dais ------------------------------------------
  H.navTo(28, 2, { maxFrames = 30000 }),
  pressWalk("up", function() return map() == 243 end, 900,
    "castle door 253 (28,1) -> 243 (15,29)"),
  H.waitUntil(landed(243, 10), 2400, "castle antechamber 243", 1),
  -- (8,18) is a stood-on trigger; dlg $06A6 blocks and player_ctrl_on
  -- returns MID-script, so stepOff does both jobs (probe run 5's lesson)
  H.navTo(8, 18, { maxFrames = 12000, calmFrames = 4 }),
  H.stepOff({ "right", "down", "up" }, 6000,
    "escort: A through $06A6, step off (8,18)"),
  H.waitUntil(function() return sw(0x013A) == 1 end, 3000,
    "the escort ran ($013A)", 5),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x062F), 1, "$062F -- the soldier population is up")
  end),
  H.navTo(15, 9, { maxFrames = 12000 }),
  pressWalk("up", function() return map() == 250 end, 900,
    "door 243 (15,8) -> 250 (23,33)"),
  H.waitUntil(landed(250, 10), 2400, "250 first entry", 1),
  H.call(function()
    H.assertEq(sw(0x013B), 1, "$013B -- 250 map-init opened the {22,29} door")
  end),
  H.navTo(54, 17, { maxFrames = 30000 }),
  H.call(function()
    H.assertEq(sw(0x007C), 0, "$007C clear at the dais")
    H.screenshot("leg_ij_dais")
  end),

  -- ---- 3. the window --------------------------------------------------------
  -- tapLever returns at $007C (:97418); the timer starts two lines later
  -- and the tail still runs.  The dais is a stood-on trigger afterwards,
  -- so the ride-out is stepOff (A through dialogs, walk off on control).
  holdUpA(0x007C, 9000, "dais face-UP+A -> _cc8490 -> $007C=1"),
  H.release(),
  H.stepOff({ "down", "left", "right" }, 20000,
    "ride the Gestahl/Cid scene; step off the dais trigger"),
  H.waitUntil(landed(250, 10), 9000, "control with the window live", 1),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(sw(0x007C), 1, "$007C SET -- the window is live")
    H.assertEq(H.readByte(0x1188) ~= 0, true, "timer 0 flags live ($1188)")
    H.assertEq(var0(), 0, "var0 zeroed at the window start")
    H.log(string.format("[window] timer=%d f%d", timerCount(), H.frame))
  end),

  -- the west hall four
  soldier(0x13, 0x021A, "250 (25,18) talk"),
  soldier(0x12, 0x0219, "250 (21,18) talk"),
  soldier(0x10, 0x0217, "250 (21,24) talk"),
  soldier(0x11, 0x0218, "250 (25,24) talk"),
  -- stairs (15,21) -> (24,52), lower west
  hop(15, 21, function() return H.fieldY() >= 40 end, "stairs -> (24,52)"),
  soldier(0x1F, 0x0227, "250 (9,49) talk [wander]"),
  -- door (9,52) -> 244
  hop(9, 52, function() return map() == 244 end, "door -> 244"),
  soldier(0x24, 0x0220, "244 (11,23) talk"),
  soldier(0x28, 0x0225, "244 (10,17) talk [wander]"),
  soldier(0x26, 0x0222, "244 (16,14) talk"),
  soldier(0x27, 0x0223, "244 (20,14) talk"),
  soldier(0x25, 0x0221, "244 (25,23) talk"),
  -- door (23,19) -> 250 (65,52); battle 27 at (51,50)
  hop(23, 19, function() return map() == 250 end, "door -> 250 (65,52)"),
  fightSoldier(0x1E, 0x0226, 0x0c7, "250 (51,50) BATTLE 27"),
  -- door (51,53) -> 252
  hop(51, 53, function() return map() == 252 end, "door -> 252"),
  soldier(0x15, 0x022E, "252 (40,54) talk"),
  soldier(0x10, 0x021B, "252 (40,56) talk [wander]"),
  soldier(0x13, 0x021E, "252 (37,57) talk [wander]"),
  fightSoldier(0x14, 0x022D, 0x0c7, "252 (42,57) BATTLE 27 [wander]"),
  soldier(0x12, 0x021D, "252 (42,56) talk [wander]"),
  soldier(0x11, 0x021C, "252 (42,52) talk [wander]"),
  -- exit (35,48) -> 250 (51,52); the lower-east pair
  hop(35, 48, function() return map() == 250 end, "252 exit -> 250 (51,52)"),
  soldier(0x19, 0x021F, "250 (98,51) talk [wander]"),
  fightSoldier(0x20, 0x0228, 0x0c7, "250 (110,51) BATTLE 27 [wander]"),
  -- stairs (97,47) -> (115,22); the upper-east pair
  hop(97, 47, function() return H.fieldY() <= 30 end, "stairs -> (115,22)"),
  soldier(0x22, 0x022A, "250 (115,16) talk [wander]"),
  soldier(0x21, 0x0229, "250 (120,13) talk [wander]"),
  -- stairs (101,16) -> (37,14); down to 243
  hop(101, 16, function() return H.fieldX() <= 60 end, "stairs -> (37,14)"),
  hop(22, 34, function() return map() == 243 end, "door -> 243"),
  fightSoldier(0x17, 0x022B, 0x102, "243 (12,14) BATTLE 26"),
  soldier(0x18, 0x022C, "243 (18,14) talk"),
  soldier(0x16, 0x0224, "243 (8,18) talk"),
  H.call(function()
    H.assertEq(var0(), 44, "the window maximum: var0 == 44")
    H.assertEq(sw(0x013C), 0, "44 landed IN-window ($013C still clear)")
    H.log(string.format("[window COMPLETE] timer=%d left f%d",
      timerCount(), H.frame))
    H.screenshot("leg_ij_window_44")
  end),

  -- ---- 4. the expiry and the dinner ----------------------------------------
  H.release(),
  (function() local ph = 0
    return H.driveUntil(function()
      return map() == 251 and H.readByte(0x056f) >= 2 and H.dialogWaiting()
    end, 40000, {
      H.call(function()
        ph = (ph + 1) % 8
        if sw(0x013C) == 1 and H.dialogWaiting()
           and H.readByte(0x056f) < 2 then
          H.setPad(ph < 4 and { "a" } or {})
        else
          H.setPad({})
        end
      end),
    }, "expiry -> map 5 -> the dinner table -> the toast choice")
  end)(),
  H.call(function()
    H.assertEq(map(), 251, "the dinner table (map 251)")
    H.assertEq(var0(), 44, "var0 carried into dinner")
  end),

  -- ---- 5. the Q&A to 93 -----------------------------------------------------
  picks({ 2 }, atLeast(49), 6000, "toast: hometowns (+5)"),
  ckVar("toast", 49),
  picks({ 0 }, atLeast(54), 6000, "Kefka: jail (+5)"),
  ckVar("kefka", 54),
  picks({ 1 }, atLeast(59), 6000, "Doma: inexcusable (+5)"),
  ckVar("doma", 59),
  picks({ 1 }, atLeast(64), 6000, "Celes: one of us (+5)"),
  ckVar("celes", 64),
  picks({ 0 }, atLeast(66), 6000, "first question: q0 (+2)"),
  H.call(function()
    H.assertEq(sw(0x0231), 1, "$0231 -- q0 recorded as asked-first")
  end),
  picks({ 0, 1 }, atLeast(68), 6000, "one more -> q1 (+2)"),
  ckVar("q1", 68),
  picks({ 0, 2 }, atLeast(70), 6000, "one more -> q2 (+2)"),
  ckVar("q2", 70),
  picks({ 1, 0 }, atLeast(75), 9000, "Espers: gone too far (+5)"),
  ckVar("espers", 75),
  picks({ 0 }, atLeast(80), 9000, "recall: q0 was first (+5)"),
  ckVar("recall", 80),
  -- the rest break and the challenge
  picks({ 0 }, function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and H.readByte(0x056f) < 2
  end, 9000, "rest break: yes -> control on the floor"),
  H.waitFrames(30),
  H.chaseTalk(0x12, 9000, "chase the trooper at 251 (76,16)"),
  picks({ 0 }, function() return sw(0x0237) == 1 end, 15000,
    "challenge: Sure -> battle 30 -> clean win (+5)"),
  H.call(function()
    local w, found = H.formationWords(), 0
    for i = 1, 6 do if w[i] == 0x0c2 then found = found + 1 end end
    H.assertEq(found >= 1, true, "battle 30: Sp Forces ($0c2) formation")
    H.assertEq(H.readByte(0x1dd1) & 0x31, 0,
      "battle 30 clean win -- $40/$44/$45 clear")
    H.assertEq(var0(), 85, "challenge +5")
  end),
  settle(3000, "challenge tail settles"),
  -- back to the table
  H.navTo(80, 20, { maxFrames = 9000, calmFrames = 4 }),
  H.waitUntil(function() return H.readByte(0x056f) >= 2 end, 1200,
    "'Shall we begin again?'", 5),
  picks({ 0, 1 }, atLeast(90), 12000, "begin again + wish: war's over (+5)"),
  ckVar("wish", 90),
  picks({ 0 }, atLeast(93), 9000, "accompany: Yes on the first ask (+3)"),
  ckVar("accompany", 93),

  -- ---- 6. the Leo intro and the roster rewrite ------------------------------
  H.advanceStory(function()
    return sw(0x007D) == 1 and map() == 251 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, 60000),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x007D), 1, "$007D -- the banquet tail ran")
    H.assertEq(var0(), 93, "var0 == 93 held through the rewrite")
    local n = 0
    for c = 0, 15 do if partyOf(c) ~= 0 then n = n + 1 end end
    H.assertEq(n, 2, "party COUNT is two (#21 control, inverted)")
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    H.screenshot("leg_ij_two")
  end),

  -- ---- 7. the messenger -----------------------------------------------------
  H.navTo(80, 26, { maxFrames = 9000 }),
  pressWalk("down", function() return map() == 250 end, 900,
    "251 door row -> 250 (53,11)"),
  H.waitFrames(30),
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the (53,11) trigger tile"),
  H.navTo(23, 12, { maxFrames = 20000, calmFrames = 4 }),
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x0238) == 1 end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
      end),
    }, "the messenger -> $0238=1")
  end)(),
  settle(3000, "messenger tail settles"),
  H.call(function()
    H.assertEq(sw(0x0238), 1, "$0238 -- the rewards paid")
    H.assertEq(sw(0x0276), 1, "$0276 -- South Figaro withdrawal")
    H.assertEq(sw(0x0277), 1, "$0277 -- Doma withdrawal (>=50)")
    H.assertEq(sw(0x0278), 1, "$0278 -- base weapons unlock (>=67)")
    H.assertEq(var0(), 0, "var0 zeroed by the messenger")
    H.screenshot("leg_ij_messenger")
  end),

  -- ---- 8. out of the castle, out of Vector ----------------------------------
  -- (23,12) is a stood-on trigger after $0238 latches: step off first
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the messenger trigger tile"),
  H.navTo(23, 33, { maxFrames = 20000 }),
  pressWalk("down", function() return map() == 243 end, 1200,
    "door 250 (22..24,34) -> 243 (15,10)"),
  H.waitUntil(landed(243, 10), 2400, "243 on the way out", 1),
  H.navTo(15, 30, { maxFrames = 12000 }),
  pressWalk("down", function() return map() == 253 end, 1200,
    "south rows -> 253 (29,2)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253 on the way out", 1),
  H.navTo(30, 62, { maxFrames = 30000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "253 (30,63) world exit -> world (120,188)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Vector", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.worldX(), 120, "anchor-J tile x")
    H.assertEq(H.worldY(), 188, "anchor-J tile y")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT at the J tile")
    H.screenshot("leg_ij_j_tile")
  end),

  -- ---- 9. the world battery save -- boundary J ------------------------------
  H.call(function()
    H.assertExitContractPreSave("banquet-done-v1")
  end),
  -- THE LEG'S SAVESTATE IS MINTED HERE, BEFORE THE MENU (the world menu
  -- does not unwind on B -- addenda SS1.7)
  H.saveState("banquet_done.mss"),

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
    }, "world menu open at the J tile")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- world save legal at (120,188)")
    emu.write(TEMP_ELEM, 0x01, emu.memType.snesMemory)
    emu.write(TEMP_CLASS, 0x01, emu.memType.snesMemory)
    emu.write(0x316810 + ULTROS2, 0x01, emu.memType.snesMemory)
    emu.write(0x316990 + ULTROS2, 0x01, emu.memType.snesMemory)
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)   -- the #29 sentinel
    H.writeByte(ZMENUSTATE, SAVE_SELECT_INIT)
  end),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    300, "save-slot selection", 5),
  H.call(function()
    H.writeByte(0x4b, 2) -- zero-based cursor: deterministic slot 3
    H.writeWord(0x95, 0) -- slot-3 display cache: treat it as empty
  end),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function()
    return emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM rewrote the zeroed slot marker"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertExitContract("banquet-done-v1")
    H.screenshot("leg_ij_saved")
  end),
  H.logStep(function()
    return string.format("banquet-done-v1 saved via the real Save UI at "
      .. "frame %d -- var0 ran the full 93; boundary J of the v0.7 band",
      H.frame)
  end),
}

-- flatten nested step lists (soldier/fightSoldier/hop return lists)
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 400000 }, flat)
