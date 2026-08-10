-- probe_cranes_wedge.lua -- READ-ONLY instrument (issue #75, phase-2
-- wall): what does the post-Cranes map-6 event actually WAIT for?
--
-- gen_terra_returned_anchor's first honest run (9c4SgDmR) fought the
-- Cranes for ~11000 frames, ended the battle with the party alive, and
-- then wedged on map 6 (15,7) -- ev=true / ctl=false / dlg=false -- for
-- 30000+ frames under advanceStory's tap-A patience.  This probe rides
-- the same route with instrumentation:
--   * at the battle's rising and falling edges it dumps the b-switch
--     block ($1dd1 -- $40/$44/$45 live in bits 0/4/5 -- and $1dd2+),
--     the formation words, and the per-slot monster hp/shield table,
--     so the END CAUSE of the fight is measured, not guessed;
--   * once the ride goes quiet (no battle, no dialog, no control, no
--     position change for 600 frames) it dumps the sfigaro-stall
--     instrument every 600 frames: the event PC ($00e5-7), the control
--     gates, the choice cells ($056e/f), and the full object table --
--     whatever the event is doing, its PC and objects say so;
--   * it also probes the two inputs advanceStory never gives: a HELD
--     direction burst and a B tap, each logged, in case the scene is a
--     walk-out or a menu the tap-A model cannot see.
-- Ends after the wedge dump cycle or on reaching map 219.
-- NOT a suite test; no fixture output.
--
-- ============================ RESOLVED (2026-08-10) ======================
-- NOT a product bug, NOT off the rails: a DRIVABLE input the ride was
-- missing.  Three runs bisected it (logs are the record):
--
--   * THE CRANES FIGHT is scripted-end, party survives at FULL HP
--     (persistent $1600 table reads c1/c4/c5/c9 all full; the battle
--     table's 0/0/0/0 is teardown, HANDOFF trap 1).  Both Cranes stay
--     alive (010D 1095/sh5, 010E untouched 2300/sh6) -- winning is not
--     the gate.
--   * THE POST-CRANES SCENE HAS AN A-GATED BEAT.  Left alone (no input)
--     the event parks and holds for 13000+ measured frames (f12565 ->
--     f25499, unchanged).  A round-robin poke run, and then a PURE
--     EDGE-A run, both ADVANCE it -- edge-A alone carries the whole
--     scene through to CC9AEB = SavePoint (_cc9aeb, event_main.asm) on
--     the map-6 Blackjack DECK.  So the beat is an ordinary A wait that
--     does NOT raise the dialog flag ($056f=0, dlg=false), which is
--     exactly why advanceStory's honest="tactical" patience -- it only
--     taps A when dlg=true -- holds neutral and wedges there.
--   * THE SCENE'S ENDPOINT is the deck save point, control RETURNED
--     (SavePoint EventReturns with $01B5 set; hasControl() flickers on
--     the save tile, the documented anchor-gen pattern).  The gen's ride
--     pred (map==219) and its whole downstream route assume the party
--     lands on map 219 directly; the real control-return is on MAP 6,
--     and the flashback (219) is reached later through the deck's own
--     scripted sequence (load_map 219 at event_main.asm:24258, gated
--     behind object moves + a wait_obj).
--
-- THE FIX (gen-side, terra_returned_anchor's ride): replace the
-- advanceStory(map==219) patience with an EDGE-A drive through the
-- post-Cranes scene, terminate it on control-return at the deck (position
-- + $01B5, never raw hasControl), then re-derive the downstream route
-- from map 6 forward.  That route re-authoring (deck -> 219 trigger, then
-- the rest) is follow-on measurement; this probe nails the missing input
-- and the true endpoint.  No game-side change.

local H = dofile("tools/tests/lib/ot6.lua")

-- TIMELINE KNOB for the divergence experiment: "A" = the tactical fighter
-- (heals at 45, the wedging timeline); "B" = plain Fights, no items, no
-- boost -- maximum honest contrast in fight shape/duration, same route.
-- Edit here between runs; the evPC transition trace below is the diff.
local TIMELINE = "A"

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

  -- the same route the anchor gen drives: to (54,40), held LEFT onto the
  -- reunion trigger, then the ride
  H.navTo(54, 40, { honest = "flee", maxFrames = 25000 }),
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
    local tracing, lastPC, traceN, ctlHold = false, nil, 0, 0
    return H.driveUntil(function()
      if map() == 219 then return true end
      if H.hasControl() and H.tileAligned() then
        ctlHold = ctlHold + 1
        if ctlHold >= 60 then return true end
      else
        ctlHold = 0
      end
      return wedgeDumps >= 30
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
          -- the party's MODULE-INDEPENDENT hp (the $1600 table -- the
          -- battle table reads 0 during teardown, HANDOFF trap 1) is a
          -- prime scene-input candidate
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
        -- THE TRACE: every evPC transition from fight close on, frame
        -- stamped (sampled per frame -- HANDOFF trap 1, never watchpoints)
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
        -- PURE EDGE-A: once the fight is over, edge-tap A through the whole
        -- post-Cranes scene, whether or not dlg is set.  If this reaches
        -- 219 or returns control, the button-gated beat is an ordinary A
        -- wait advanceStory's patience skipped, and the gen fix is an
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
