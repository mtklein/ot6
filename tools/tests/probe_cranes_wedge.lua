-- probe_cranes_wedge.lua -- read-only instrument (issue #75, phase-2
-- wall): measures what the post-Cranes map-6 event waits for.
--
-- gen_terra_returned_checkpoint's first input-driven run (9c4SgDmR) fought the
-- Cranes for ~11000 frames, ended the battle with the party alive, and
-- then wedged on map 6 (15,7), with ev=true / ctl=false / dlg=false, for
-- 30000+ frames under advanceStory's tap-A patience.  This probe rides
-- the same route with instrumentation:
--   * at the battle's rising and falling edges it dumps the b-switch
--     block ($1dd1, where $40/$44/$45 live in bits 0/4/5, and $1dd2+),
--     the formation words, and the per-slot monster hp/shield table,
--     so the cause of the fight ending is measured rather than inferred;
--   * once the ride goes quiet (no battle, no dialog, no control, no
--     position change for 600 frames) it dumps the sfigaro-stall
--     instrument every 600 frames: the event PC ($00e5-7), the control
--     gates, the choice cells ($056e/f), and the full object table, which
--     records what the event is doing;
--   * it also probes the two inputs advanceStory never gives: a held
--     direction burst and a B tap, each logged, in case the scene is a
--     walk-out or a menu the tap-A model cannot see.
-- Ends after the wedge dump cycle or on reaching map 219.
-- Not a suite test; no fixture output.
--
-- ==================== SUPERSEDED (2026-08-10, evening) ===================
-- The "unwinnable as tuned" conclusion below is withdrawn: it was a
-- loadout bug rather than a balance problem.  Every wipe in this record
-- was fought with Thunder Blades (the game's Optimum power pick) into a
-- lightning-absorbing Crane, so the party healed and charged the boss on
-- each swing.  With the vanilla playbook (Bismark/Shiva/Carbunkl worn,
-- daggers, back rows, focus-fire) the fight falls on attempt 1:
-- probe_cranes_water, PASS f19772.  The measurements below remain an
-- accurate record of what those configurations did; only the conclusion
-- drawn from them was wrong.
-- ==================== Corrected verdict (2026-08-10, final) ==============
-- The earlier RESOLVED note in this header claimed the wedge was "a
-- drivable A-press, not a product bug".  That was wrong, and the error is
-- recorded here: the "scene" the edge-A run drove to completion was the
-- game over sequence.  The trace's post-fight addresses CCE56E..CCE5xx
-- sit inside .proc GameOver (event_main.asm:113054, cc/e566), and the
-- CC9AEB "SavePoint" loop at the end is the continue flow rather than a
-- deck save point.  What happens, measured across five runs:
--
--   * the Cranes' AI scripts (AIScript::_269/_270) contain no end_battle,
--     so the fight ends by kill or wipe only, plus a 60s repeating
--     Magnitude8 timer and charge counters fed by absorbed elements;
--   * every input-driven configuration tried wipes: tactical/heal45 at ~f8400
--     (timeline B, plain fights: wiped with both Cranes at full hp);
--     tactical/heal45+bank1 wiped ~f6800-8400 across trajectories after
--     chipping at best 1800->1095/sh5 on Crane0; the terra6 gen run
--     wiped ~f+7500 (party 143/43/203/39 at f+5700, Crane0 1357/sh5);
--   * the wipe closes the battle (battle CLOSED, both Cranes alive), and
--     GameOver restores the party to full persistent HP, so the reads
--     that looked like "scripted end, party survives at full HP" were
--     the game-over restore rather than survival;
--   * the CB40E8 hold (~1800 frames, advances on A, no dialog flag) is a
--     beat inside the wipe -> GameOver handoff, so the "drivable input"
--     was the player pressing through the death screen.
--
-- Chip pace against survival: when attacking, the fighter chips ~440hp
-- and 1 shield per ~5700 frames on one Crane, so a win needs ~40-60k
-- battle frames sustained, and no tried healing configuration survives
-- past ~8400.  Survival rather than damage is the binding constraint.
--
-- The product/balance finding for the dispatch: bosses-wob.md 16 names
-- the Cranes' elemental key as water ("the elemental key here is
-- water"), and the mandated party at this point (LOCKE/SABIN/EDGAR/
-- TERRA, natural magic only, fire-lean) has no water access of any kind.
-- The fight's designed counter is unobtainable by the party that must
-- fight it; the owner's playtest stopped at Ifrit/Shiva, so no human has
-- crossed this in OT6.  Whether that is intended difficulty or a tuning
-- gap is an owner call; the July checkpoint passed only because the
-- battle-clear write ended the fight in 3 frames.
--
-- Harness note: several earlier "Mesen crashes" during these runs were
-- run.sh's 600s wall-clock cap (OT6_TIMEOUT raises it); the timeout message
-- says so when it happens.

local H = dofile("tools/tests/lib/ot6.lua")

-- Timeline selector for the divergence experiment: "A" = the tactical
-- fighter (heals at 45, the wedging timeline); "B" = plain Fights, no
-- items, no boost, which gives the largest contrast in fight shape and
-- duration on the same route.  Edit here between runs; the evPC
-- transition trace below shows the difference.
local TIMELINE = "B"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function dump(tag)
  local po = H.readWord(0x0803)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) bright=%d | evPC=%02X%02X%02X $ba=%d $d3=%d "
    .. "$056e=%d $056f=%d $1dd1=%02X $1dd2=%02X $0059=%02X mvType=%02X "
    .. "| $e0=%02X $e1=%02X $e2=%02X waitObj=%s waitAct=%02X "
    .. "ctl=%s algn=%s dlg=%s ev=%s batt=%s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
    H.readByte(0x00ba), H.readByte(0x00d3),
    H.readByte(0x056e), H.readByte(0x056f),
    H.readByte(0x1dd1), H.readByte(0x1dd2),
    H.readByte(0x0059), H.readByte(0x087c + po),
    H.readByte(0x00e0), H.readByte(0x00e1), H.readByte(0x00e2),
    ((H.readByte(0x00e1) & 0x80) ~= 0) and "YES" or "no",
    H.readByte(0x087c + H.readByte(0x00e2) * 0x29),
    tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.dialogWaiting()), tostring(H.eventRunning()),
    tostring(H.battleLoadStarted())))
  local objs = {}
  for i = 0, 31 do
    local x = H.readWord(0x086a + 0x29 * i) >> 4
    local y = H.readWord(0x086d + 0x29 * i) >> 4
    local live = H.readByte(0x0868 + 0x29 * i)
    if live ~= 0 then
      objs[#objs + 1] = string.format("%d:(%d,%d,%02X)", i, x, y, live)
    end
  end
  H.log("[" .. tag .. "] objs " .. table.concat(objs, " "))
end

local function battleDump(tag)
  local w = H.formationWords()
  local mons = {}
  for m = 0, 5 do
    mons[#mons + 1] = string.format("%d:%04X hp=%d sh=%d fld=%d",
      m, H.readWord(0x57C0 + m * 2), H.readWord(0x3BFC + m * 2),
      H.readByte(0x3E40 + m * 2), H.readByte(0x3AA8 + m * 2) & 1)
  end
  H.log(string.format(
    "[%s] f%d form=%04X %04X %04X %04X | party %d/%d/%d/%d | "
    .. "$1dd1=%02X $3ebc=%02X",
    tag, H.frame, w[1], w[2], w[3], w[4],
    H.readWord(0x3BF4), H.readWord(0x3BF6),
    H.readWord(0x3BF8), H.readWord(0x3BFA),
    H.readByte(0x1dd1), H.readByte(0x3ebc)))
  H.log("[" .. tag .. "] slots " .. table.concat(mons, " | "))
end

H.run({ maxFrames = 200000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on map 240 (n128_won)")
    dump("boot")
  end),

  -- the same route the checkpoint gen drives: to (54,40), held LEFT onto the
  -- reunion trigger, then the ride
  H.navTo(54, 40, { playBattles = "flee", maxFrames = 25000 }),
  (function() local ph = 0
    return H.driveUntil(function() return map() == 6 end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); return
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "held LEFT onto the reunion trigger -> the Blackjack deck")
  end)(),
  H.release(),

  -- the instrumented ride: tactical fighter, with battle-edge dumps and
  -- the wedge instrument
  (function()
    local F = H.newFightDriver("cranes probe",
      TIMELINE == "A"
        and { tactical = true, boost = true, bank = 1, items = true,
              healPercent = 45, cadence = 12 }
        or  { tactical = false, boost = false, items = false, cadence = 12 })
    local ph, battN, wasBatt = 0, 0, false
    local quiet, lastX, lastY, lastDump = 0, -1, -1, 0
    local wedgeDumps, pokes = 0, 0
    local tracing, lastPC, traceN, ctlHold, rearmed = false, nil, 0, 0, nil
    return H.driveUntil(function()
      if map() == 219 then H.log("[verdict] STORY CONTINUES (flashback)"); return true end
      if tracing and battN >= 3 then
        rearmed = (rearmed or 0) + 1
        if rearmed == 1 then H.log("[verdict] BATTLE RE-TRIGGERED (retry loop)") end
      end
      return wedgeDumps >= 25
    end, 180000, {
      H.call(function()
        ph = (ph + 1) % 8
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN == 3 and not wasBatt then
          wasBatt = true
          battleDump("battle OPEN")
        end
        if wasBatt and battN == 0 then
          wasBatt = false
          battleDump("battle CLOSED")
          dump("post-battle")
          -- the party's module-independent hp (the $1600 table; the
          -- battle table reads 0 during teardown, HANDOFF trap 1) is a
          -- candidate scene input
          local hp = {}
          for c = 0, 13 do
            local b = H.readByte(0x1850 + c)
            if b ~= 0 and (b & 0x07) == H.readByte(0x1A6D) then
              hp[#hp + 1] = string.format("c%d=%d/%d", c,
                H.readWord(0x1600 + 37 * c + 9), H.readWord(0x1600 + 37 * c + 11))
            end
          end
          H.log("[post-battle] persistent party hp: " .. table.concat(hp, " "))
          tracing = true
        end
        -- The trace: every evPC transition from fight close onward, frame
        -- stamped (sampled per frame; HANDOFF trap 1, no watchpoints)
        if tracing then
          local pc = H.readByte(0x00e7) * 65536 + H.readByte(0x00e6) * 256
                   + H.readByte(0x00e5)
          if pc ~= lastPC then
            traceN = traceN + 1
            if traceN <= 400 or traceN % 50 == 0 then
              H.log(string.format("[trace %d] f%d evPC %06X -> %06X ($e1=%02X)",
                traceN, H.frame, lastPC or 0, pc, H.readByte(0x00e1)))
            end
            lastPC = pc
          end
        end
        if battN >= 3 then
          if battN % 600 == 0 then battleDump("battle") end
          F.frame()
          return
        end
        if battN > 0 then F.idle(); H.setPad({}); return end
        F.idle()
        -- wedge detection: no battle, no control, position frozen
        local x, y = H.fieldX(), H.fieldY()
        if x == lastX and y == lastY and not H.hasControl()
           and not H.dialogWaiting() then
          quiet = quiet + 1
        else
          quiet = 0
        end
        lastX, lastY = x, y
        if quiet > 400 and H.frame - lastDump >= 600 then
          lastDump = H.frame
          wedgeDumps = wedgeDumps + 1
          dump("quiet " .. wedgeDumps)
        end
        -- Edge-A only: once the fight is over, edge-tap A through the whole
        -- post-Cranes scene, whether or not dlg is set.  If this reaches
        -- 219 or returns control, the button-gated beat is an ordinary A
        -- wait that advanceStory's patience skipped, and the gen fix is an
        -- edge-A ride.
        if tracing then
          H.setPad(ph < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "the instrumented reunion/Cranes ride")
  end)(),
  H.call(function()
    dump("END")
    H.log(string.format("[end] map=%d ctl=%s (%d,%d) $01B5=%d $01BF=%d $006B=%d "
      .. "$01C2=%d -- %s", map(), tostring(H.hasControl()),
      H.fieldX(), H.fieldY(), sw(0x01B5), sw(0x01BF), sw(0x006B), sw(0x01C2),
      map() == 219 and "REACHED THE FLASHBACK"
      or (H.hasControl() and "CONTROL RETURNED on this map -- the ride must walk on from here"
      or "no control -- genuinely stuck")))
    H.screenshot("cranes_wedge_end")
  end),
})
