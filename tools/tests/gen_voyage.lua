-- gen_voyage.lua -- v0.12: segment 7 of docs/design/sealed-gate-route.md,
-- boundary J -> boundary K (the v0.7 stop line).  Cold-Continue the tracked
-- `banquet-done-v1` battery (world (120,188), the Vector exit tile), then
-- play the whole voyage with controller input: the 33-step world walk to
-- Albrook, the port, the pier scene, the Albrook night window, "Right...
-- let's go", the two sail scenes with the Terra/Leo and Shadow
-- conversations, and the landing on Crescent Island at world (232,150),
-- party TERRA - LOCKE - SHADOW.  Ends with the world battery save through
-- the real Save UI -- boundary K, `crescent-landing-v1`.
--
-- The route, with the mechanism each beat rides (all cited from
-- ff6/src/event/event_main.asm unless said otherwise):
--
--  1. World walk (120,188) -> (137,203), the tile one west of the Albrook
--     gate, then held RIGHT onto the (138,203) short entrance -> 323 (2,17)
--     (world-0 ShortEntrance records; gen_vector_entry used the same door
--     from the same tile).  Encounters on the walk are fled with the real
--     L+R run, the same design gen_banquet_done's I->J grind used on this
--     terrain, after a care stop at the boot tile.
--  2. Albrook 323: the port gate triggers at (43,26)/(45,26) are no-ops
--     with $007D=1 (`_cc62f2/_cc632d` first line each), and the (43,29)
--     long entrance (len 3, decoded from trigger/long_entrance.dat) drops
--     into the port, map 332 (22,2).  Maps 323/325/332 cannot draw a
--     random battle (map_prop.dat +5 bit 7 clear, audit_encounters.py), so
--     every navTo below spells playBattles="flee" as intent only.
--  3. The Gau question, measured rather than assumed.  The survey
--     (sealed-gate-route.md section 1 seg 7) says GAU follows and refuses to
--     board at 332 (10,10)/(11,10) with `$02FB=0`.  The trigger's own guard
--     says otherwise for THIS chain: `set_case PARTY_CHARS` (:67906) fills
--     case bits from the char objects' party fields (EventCmd_de,
--     ff6/src/field/event.asm:4308-4348), and the banquet tail forced the
--     party to TERRA+LOCKE with `char_party GAU, 0` (:99089), so case bit
--     $01AB reads 0 and the trigger returns before the scene (:67907-67910).
--     GAU's post-banquet presence is an NPC standing in Vector 253 at
--     (41,13) whose talk script is flavor + delete_obj, no join (_cc929f).
--     So this generator rests on (10,10) to give the trigger its chance,
--     logs the guard inputs, and the exit contract pins the derived answer:
--     $02FB stays 1.  If the game disagrees, the contract diff names it.
--  4. The pier scene: talk LEO at 332 (12,15) (NPC record 3 -> obj $13,
--     npc_prop.asm:14419) -> _cbcc84: Celes+Shadow intro.  On a chain that
--     never met Shadow ($000B=0) this includes `name_menu SHADOW` (:68222),
--     the one beat a dialog rider cannot A through: START commits the
--     default name (gen_edgar's commitName finding), so the talk rider
--     below presses START whenever a menu is up ($59 ~= 0).  The scene ends
--     with `$0084=1 $0085=1` (:68350-68351) and control back -- the night
--     window.
--  5. THE NIGHT-WINDOW MEASUREMENT (the survey's open question 7): leave
--     Albrook mid-window, out the west long entrance to world (137,203),
--     verify world control, read $0084/$0085/$0087 and the save-enable
--     flag $0201 bit7 (raw read, no menu), run a real H.fieldCare there
--     (the world-menu round trip gen_sabin_gau's overworld care proved),
--     then walk back in and finish the sequence.  The sequence completing
--     after the excursion IS the answer; a wedge fails a named step here.
--  6. The night: the inn door 323 (54,12) -> 325 (58,56) (ShortEntrance),
--     innkeeper at (56,51) (obj $10, npc_prop.asm:14199) -> _cc614a: with
--     $0085=1 && $0087=0 the stay is free ("General Leo told us about
--     you"), the Locke/Celes night scene plays, and control returns on 325
--     (55,39) with $0087=1 (:91497).  Out the (58,57) trigger -> 323
--     (54,14) (_cc60d2).
--  7. Back to the port; LEO again -> _cbce36 "Right...let's go", $0083=1
--     (:68379), the scripted sail (world ship script :68390-68402), the
--     deck scenes, and TERRA alone on the night deck ($0507, `party_chars
--     TERRA` :68488).
--  8. LEO at (8,13) (obj $21) -> _cbcefc: the Terra/Leo conversation, the
--     Shadow scene, Locke's seasickness, the second sail (:68963), and the
--     day deck with $0086=1 (:69018).  No dialog in the scene is a choice;
--     the rider only pages.
--  9. LEO at (12,14) (obj $22) -> _cbd1f3: the split briefing, $0089=1.
-- 10. LOCKE at (10,14) (obj $1D) -> _cbd209: "Let's go", SHADOW joins
--     (`create_obj SHADOW`, `char_party SHADOW, 1`, `$02F3=1`, `norm_lvl`,
--     max_hp/max_mp, :69154-69163), `set_b_switch $4B`, and the landing
--     sail ends at world (232,150) facing UP (:69180-69188), controllable.
--     The Thamasa trigger at (250,128) is 40+ encounter-active steps away
--     and is NOT approached; the stop line is the landing tile itself.
--
-- The Save-UI block at the end is gen_banquet_done's, unchanged in shape:
-- savestate first (the world menu does not unwind on B, measured twice),
-- reload-verify, then the pad-driven slot-3 save with the read-only
-- CopyGameDataToSRAM exec hook as the receipt.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function partyCount()
  local n = 0
  for c = 0, 15 do if partyOf(c) ~= 0 then n = n + 1 end end
  return n
end

-- Verified-step world grinder (gen_banquet_done's, unchanged; consumes a
-- plan entry only when the party lands on it).  An encounter on the grind
-- is fled with the real L+R run, which is the design for world encounters
-- (issue #75); this terrain's packs fled clean across gen_banquet_done's
-- much longer I->J grind.
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
        plan = nil; step = nil
        H.setPad({ l = true, r = true }); return
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

-- unconditional held walk (dialogs absorbed; a battle, none of which can
-- roll on these maps, is fled with the real L+R run)
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

-- Passive scene rider: pages dialogs with A, commits a naming menu with
-- START ($59 ~= 0 is the menu-up flag; name_menu suspends the field module,
-- gen_edgar's commitName finding), and otherwise waits for `done`.  Used
-- for every scripted stretch between talks: the sails, the deck scenes,
-- and the landing tail.
local function rideScene(done, maxFrames, what)
  local ph = 0
  return H.driveUntil(done, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.worldMode() then H.setPad({}); return end  -- scripted sail: hands off
      if H.readByte(0x59) ~= 0 then
        H.setPad(ph < 4 and { "start" } or {}); return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end  -- no choice
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- Walk to a character/NPC object's open neighbour, edge-A to talk, then
-- ride the scene it opens (dialog paging + naming-menu START) until `done`.
-- H.chaseTalk's chassis with the rideScene branches folded in; the voyage's
-- scenes carry no choices (read end to end, :68091-69190), so a choice
-- window parks the pad and the step times out loudly rather than picking
-- something silently.  When no adjacent tile is reachable the rider falls
-- back to counter talk (gen_kolts's item-shop idiom): stand two tiles away
-- in line, face the NPC, and tap A -- CheckNPCs reaches through the one
-- impassable counter tile (ff6/src/field/player.asm:188-200).  The Albrook
-- innkeeper is that class of NPC.
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function talkRide(objIdx, done, maxFrames, what)
  local ph = 0
  local function objAt(idx)
    local off = 0x29 * idx
    return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
  end
  return H.driveUntil(done, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.worldMode() then H.setPad({}); return end  -- scripted sail: hands off
      if H.readByte(0x59) ~= 0 then
        H.setPad(ph < 4 and { "start" } or {}); return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local ox, oy = objAt(objIdx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best = p end
      end
      if not best then
        -- counter talk: no adjacent tile reachable
        if (dx == 0 and math.abs(dy) == 2) or (dy == 0 and math.abs(dx) == 2) then
          local dir = (dx == 2 and "right") or (dx == -2 and "left")
                   or (dy == 2 and "down") or "up"
          if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE[dir] then
            H.setPad({ [dir] = true }); return
          end
          H.setPad(ph < 4 and { "a" } or {}); return
        end
        for _, c in ipairs({ { ox, oy + 2 }, { ox - 2, oy },
                             { ox + 2, oy }, { ox, oy - 2 } }) do
          local p = H.bfsPath(c[1], c[2])
          if p and (not best or #p < #best) then best = p end
        end
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what)
end

-- --------------------------------------------------------------------------
local steps = {
  -- ---- the cold Continue and the entry contract (issue #25) ---------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function() local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 120 and H.worldY() == 188
    end
    return H.driveUntil(function()
      return atSite() and bright() >= 15
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> J-tile world load (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the J tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEntryContract("banquet-done-v1")
  end),

  -- ---- 1. care, then the world walk to Albrook ------------------------------
  -- Care first: the walk can draw encounters and a party that enters a
  -- fight low may never get a turn back (HANDOFF, the healPercent bullet).
  -- The 60 quiet frames before the menu are this wave's landing-window
  -- rule: a menu must never open inside the encounter roll's ~15-frame
  -- window after a walk segment (gen_sabin_gau's worldWalkFight precedent).
  H.waitFrames(60),
  H.fieldCare({ tag = "care at the J tile", threshold = 0.9 }),
  worldGrind(137, 203, "the J->K world walk -> (137,203), west of Albrook"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned()
  end, 2400, "at the Albrook approach", 5),
  pressWalk("right", function() return not H.worldMode() end, 900,
    "held RIGHT onto (138,203) -> Albrook 323 (2,17)"),
  H.waitUntil(landed(323, 10), 2400, "Albrook", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX(), 2, "Albrook arrival x (world short entrance)")
    H.assertEq(H.fieldY(), 17, "Albrook arrival y")
    H.assertEq(sw(0x007D), 1, "$007D -- the port stands open")
    H.screenshot("voyage_albrook")
  end),

  -- ---- 2. through the port gate ---------------------------------------------
  -- The gate triggers (43,26)/(45,26) are EventReturn no-ops with $007D=1
  -- and a held press skips walk-over triggers anyway (gen_banquet_done's
  -- (23,12) finding); the (43,29) long entrance fires in motion like every
  -- entrance.  One held DOWN crosses both.
  H.navTo(43, 25, { maxFrames = 20000, playBattles = "flee" }),
  pressWalk("down", function() return map() == 332 end, 1200,
    "held DOWN through the gate onto (43,29) -> the port 332 (22,2)"),
  H.waitUntil(landed(332, 10), 2400, "the port", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX(), 22, "port arrival x")
    H.assertEq(H.fieldY(), 2, "port arrival y")
  end),

  -- ---- 3. the Gau trigger, given its chance ---------------------------------
  -- Rest ON (10,10) (event triggers fire at rest, not in motion) and log
  -- everything the guard reads.  The derived answer is that it returns
  -- without the scene on this chain (header note 3); the settle absorbs
  -- the refusal scene if the derivation is wrong, and the log plus the
  -- exit contract's $02FB row report which way it went.
  H.navTo(10, 10, { maxFrames = 12000, calmFrames = 4, playBattles = "flee" }),
  H.call(function()
    H.log(string.format(
      "[gau] resting on (10,10): $02FB=%d $0637=%d $009D=%d $1850[GAU]=%02X",
      sw(0x02FB), sw(0x0637), sw(0x009D), H.readByte(0x1850 + 0x0B)))
  end),
  settle(6000, "the (10,10) rest settles (refusal scene, if any, absorbed)"),
  H.call(function()
    H.log(string.format("[gau] after the rest: $02FB=%d (1 = no refusal ran)",
      sw(0x02FB)))
  end),

  -- ---- 4. the pier scene ----------------------------------------------------
  talkRide(0x13, function() return sw(0x0085) == 1 end, 40000,
    "LEO at (12,15) -> the pier scene -> $0085"),
  settle(6000, "pier scene tail settles"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0084), 1, "$0084 -- the night window opened")
    H.assertEq(sw(0x0085), 1, "$0085 -- the night window opened")
    H.assertEq(sw(0x0087), 0, "$0087 CLEAR -- the night not yet slept")
    H.assertEq(map(), 332, "control back on the port map")
    H.screenshot("voyage_night_window")
  end),
  -- Dev scratch state: the night window live, control on the port map.
  -- Not a fixture: no graph edge, no stamp, never a suite boot (the
  -- banquet_dinner_scratch precedent).  A probe that wants to poke at the
  -- window (e.g. the mid-window Save-UI drive this generator deliberately
  -- does not risk) boots this.
  H.saveState("albrook_night_scratch.mss"),

  -- ---- 5. the night-window measurement (survey open question 7) -------------
  -- Out of the port: the (21,1)/(22,1) triggers load 323 (44,28)
  -- (_cbc87a).  navTo rests on the tile and the arrive predicate is the
  -- map change itself, the shape gen_banquet_done used for its world exit.
  H.navTo(22, 1, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return map() == 323 end }),
  H.waitUntil(landed(323, 10), 2400, "back in Albrook at the gate", 1),
  H.call(function()
    H.assertEq(H.fieldX(), 44, "gate-side arrival x (44,28)")
    H.assertEq(H.fieldY(), 28, "gate-side arrival y")
  end),
  H.navTo(43, 27, { maxFrames = 6000, playBattles = "flee" }),
  pressWalk("up", function()
    return H.fieldY() <= 24 and H.tileAligned()
  end, 900, "held UP through the gate row into town"),
  H.release(),
  H.waitFrames(30),
  H.navTo(1, 17, { maxFrames = 20000, playBattles = "flee" }),
  pressWalk("left", function() return H.worldMode() end, 900,
    "held LEFT onto the x=0 column -> world (137,203), MID-WINDOW"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15 and H.worldX() == 137 and H.worldY() == 203
  end, 3600, "world control outside Albrook mid-window", 5),
  H.waitFrames(60),
  H.call(function()
    -- THE MEASUREMENT.  The window switches held across the town exit, and
    -- the party is controllable on the world map.  Save availability is
    -- structural rather than sampled: the world menu writes $0201 = $80
    -- unconditionally when it opens (ff6/src/world/world_start.asm:423-424;
    -- the world map saves anywhere), and the care stop below opens that
    -- menu mid-window and closes it, which is the demonstration.  $0201
    -- itself is a multi-owner menu parameter cell (shop number, character
    -- number, menu flags -- trap 1), so it is NOT read raw here; the first
    -- run of this generator did read it raw, got a stale $02, and mislabeled
    -- it as the save-enable bit.
    H.log(string.format(
      "== NIGHT-WINDOW MEASUREMENT: on the world mid-window at (%d,%d): "
      .. "$0084=%d $0085=%d $0087=%d, world control held ==",
      H.worldX(), H.worldY(), sw(0x0084), sw(0x0085), sw(0x0087)))
    H.assertEq(sw(0x0084), 1, "mid-window: $0084 held across the town exit")
    H.assertEq(sw(0x0085), 1, "mid-window: $0085 held across the town exit")
    H.screenshot("voyage_midwindow_world")
  end),
  -- A real menu round trip mid-window: fieldCare opens the world menu, does
  -- whatever the party needs (the fled walk's damage, if any), and closes
  -- it through careClose's world-mode predicate (gen_sabin_gau's overworld
  -- precedent).  Its log lines are the round-trip receipt.
  H.fieldCare({ tag = "mid-window care on the world map", threshold = 0.9 }),
  pressWalk("right", function() return not H.worldMode() end, 900,
    "held RIGHT back into Albrook mid-window"),
  H.waitUntil(landed(323, 10), 2400, "Albrook again, window still open", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0085), 1, "back in town: $0085 still set")
    H.assertEq(sw(0x0087), 0, "back in town: the night still unslept")
  end),

  -- ---- 6. the night at the inn ----------------------------------------------
  -- The inn door (54,12) is a bump door: a wall until CheckDoor runs, so
  -- it is entered with a held press, never a navTo whose goal it is
  -- (gen_kolts's (44,30) finding; the first run of this generator aimed
  -- navTo at the door tile and BFS correctly said "no path").
  H.navTo(54, 13, { maxFrames = 20000, playBattles = "flee" }),
  H.driveUntil(function() return map() == 325 end, 1200, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "bump the inn door (54,12) -> 325"),
  H.release(),
  H.waitUntil(landed(325, 10), 2400, "the inn", 1),
  H.call(function()
    H.assertEq(H.fieldX(), 58, "inn arrival x (58,56)")
    H.assertEq(H.fieldY(), 56, "inn arrival y")
  end),
  talkRide(0x10, function() return sw(0x0087) == 1 end, 40000,
    "the innkeeper -> the free night -> $0087"),
  settle(6000, "night scene tail settles"),
  H.waitUntil(landed(325, 10), 3000, "morning in the lodging", 1),
  H.call(function()
    H.assertEq(sw(0x0087), 1, "$0087 -- the night was slept")
    H.log(string.format("[voyage] morning at 325 (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),
  H.navTo(58, 57, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return map() == 323 end }),
  H.waitUntil(landed(323, 10), 2400, "out of the inn", 1),
  H.call(function()
    H.assertEq(H.fieldX(), 54, "inn exit lands (54,14)")
    H.assertEq(H.fieldY(), 14, "inn exit y")
  end),

  -- ---- 7. back to the pier; "Right...let's go"; sail 1 ----------------------
  H.navTo(43, 25, { maxFrames = 20000, playBattles = "flee" }),
  pressWalk("down", function() return map() == 332 end, 1200,
    "held DOWN through the gate -> the port again"),
  H.waitUntil(landed(332, 10), 2400, "the port, morning", 1),
  talkRide(0x13, function() return sw(0x0083) == 1 end, 20000,
    "LEO -> 'Right...let's go' ($0083)"),
  rideScene(function()
    return map() == 332 and not H.worldMode() and partyCount() == 1
       and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and bright() >= 15
  end, 40000, "sail 1 + deck scenes -> TERRA alone on the night deck"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0083), 1, "$0083 -- the voyage began")
    H.assertEq(partyCount(), 1, "TERRA alone for the night watch")
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.screenshot("voyage_night_deck")
  end),

  -- ---- 8. the Terra/Leo conversation, Shadow, sail 2 ------------------------
  talkRide(0x21, function() return sw(0x0086) == 1 end, 60000,
    "LEO at (8,13) -> the night talk, the Shadow scene, sail 2 ($0086)"),
  rideScene(landed(332, 10), 12000, "day deck control"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0086), 1, "$0086 -- the second sail arrived")
    H.screenshot("voyage_day_deck")
  end),

  -- ---- 9. the split briefing ------------------------------------------------
  talkRide(0x22, function() return sw(0x0089) == 1 end, 12000,
    "LEO at (12,14) -> the split briefing ($0089)"),
  settle(3000, "briefing settles"),

  -- ---- 10. the landing ------------------------------------------------------
  talkRide(0x1D, function()
    return H.worldMode() and H.worldX() == 232 and H.worldY() == 150
       and H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 60000, "LOCKE at (10,14) -> the landing at world (232,150)"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(partyCount(), 3, "party COUNT is three (#21 control)")
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    H.assertEq(partyOf(0x03), 1, "SHADOW in party 1")
    H.assertEq(sw(0x02F3), 1, "$02F3 -- SHADOW available (:69160)")
    H.assertEq(sw(0x007A), 1, "$007A -- the airship is still dead")
    H.log(string.format(
      "[voyage] landed: $02FB=%d $0637=%d $0084=%d $0085=%d $0087=%d "
      .. "$0089=%d $11FA=%02X",
      sw(0x02FB), sw(0x0637), sw(0x0084), sw(0x0085), sw(0x0087),
      sw(0x0089), H.readByte(0x11FA)))
    H.screenshot("voyage_crescent_landing")
  end),
  -- Care at the stop line so the checkpoint ships a clean party (SHADOW
  -- arrives max_hp'd by the script; TERRA/LOCKE carry whatever the voyage
  -- left).  No world step has been taken on Crescent, so no encounter can
  -- have rolled; the 60-frame coast above still respects the landing rule.
  H.fieldCare({ tag = "care at the landing", threshold = 0.9 }),
  H.call(function()
    -- The same four conditions as tools/audit_party_hp.py, asserted here
    -- because this generator also cuts a tracked checkpoint (the
    -- gen_narshe_mission precedent).
    H.assertPartyStanding("crescent_landing exit")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT at the K tile")
  end),

  -- ---- 11. the world battery save -- boundary K -----------------------------
  H.call(function()
    H.assertExitContractPreSave("crescent-landing-v1")
  end),
  -- The step's savestate is generated here, before the menu (the world menu
  -- does not unwind on B, measured -- gen_narshe_mission)
  H.saveState("crescent_landing.mss"),
  -- Reload-verified (gen_sabin_gau's pattern): a calm capture does not
  -- imply a calm reload, so reload the parked moment and require the
  -- consumer's boot to find it quiet.
  (function()
    local saveReq, loadReq
    return H.cond(function() return true end, {
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(H.worldMode(), true, "reload: on the world map")
        H.assertEq(H.worldX() == 232 and H.worldY() == 150, true,
          "reload: still on the K tile (232,150)")
        H.assertEq(H.readByte(0x11FA) & 3, 0, "reload: still ON FOOT")
        H.assertEq(H.worldHasControl() and H.worldAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.log("generated-state verify: the reload stayed calm -- crescent_landing verified")
      end),
    })
  end)(),

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
    }, "world menu open at the K tile")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- The input-driven save receipt (issue #75): a read-only exec hook on
    -- the real CopyGameDataToSRAM entry captures the slot argument.
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  -- The pad-driven save (save-drive rule, tools/tests/README.md): UP wraps
  -- the main-menu cursor to Save (row 6), A enters the save-slot menu, the
  -- cursor is steered to slot 3 against its live cell, and A confirms
  -- through any overwrite prompt.  No pokes, no witness seeding.
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
    -- the codex witness cells are read, never seeded: the battery carries
    -- whatever the chain earned
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.assertExitContract("crescent-landing-v1")
    H.screenshot("voyage_saved")
  end),
  H.logStep(function()
    return string.format("crescent-landing-v1 saved via the real Save UI at "
      .. "frame %d -- the voyage played end to end, night window measured "
      .. "safe to leave; boundary K of the v0.7 range", H.frame)
  end),
}

-- flatten nested step lists
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 300000 }, flat)
