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
-- ============================ MEASURED (2026-08-10) ======================
-- THE CRANES FIGHT is scripted-end, NOT a required kill.  Both Cranes are
-- on stage at once (010D 1800hp/sh6 + 010E 2300hp/sh6 = 4100hp behind 12
-- shields), and the battle ENDS ON ITS OWN after ~7400 frames with BOTH
-- ALIVE (measured: Crane0 chipped to ~1095/sh5, Crane1 UNTOUCHED at
-- 2300/sh6 -- the shared fighter only ever targets the lower slot).  So
-- winning is not the gate; the party survives and the scene proceeds.
--
-- THE MAP-6 WEDGE is a frozen event, and it is NOT any of the waits the
-- interpreter's main loop knows how to hold on (event.asm:88-124):
--   evPC=CB40E8 (20 bytes past _ObjEnd4456 -- object-script territory),
--   $e0=F0 $e1=00 $e2=01  -> waitObj=NO (not object/fade/scroll: $e1 bit7
--     is the object wait, bit6 fade, bit5 scroll, all clear),
--   $ba=2 $d3=0, $056e/f=0 (no choice up), dlg=false, ctl=false,
--   ev=true, batt=false, party stacked at (15,7), object 6 frozen at
--   (10,8) -- nothing moves across 600-frame samples.
-- All three inputs advanceStory never gives were probed round-robin at
-- the wedge -- a held DOWN burst, a B tap, a long A hold -- and NONE
-- changed evPC or any cell.  So it is not a hidden dialog or a walk-out
-- the tap-A model missed.
--
-- OPEN: the exact CB40E8 opcode and why it loops in place with no wait
-- flag set is unresolved from static reading (the LoROM-mapped bytes did
-- not disassemble cleanly, and CB40E8 sits in object-script DATA past an
-- _ObjEnd label -- so the field may be executing an object script whose
-- own PC is the frozen value, distinct from the main event interpreter).
-- This wants a live Mesen debugger step or the dispatch's call, not more
-- static guessing -- reported as a finding.  The honest Cranes fight's
-- ~7400-frame duration (vs a kill-bit's ~3 frames) is the one thing that
-- changed versus every prior green run of this scene, so the leading
-- hypothesis is a scene-timing desync the long fight introduces.
local H = dofile("tools/tests/lib/ot6.lua")

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
    local F = H.newFightDriver("cranes probe", { tactical = true,
      boost = true, bank = 1, items = true, healPercent = 45, cadence = 12 })
    local ph, battN, wasBatt = 0, 0, false
    local quiet, lastX, lastY, lastDump = 0, -1, -1, 0
    local wedgeDumps, pokes = 0, 0
    return H.driveUntil(function()
      return map() == 219 or wedgeDumps >= 12
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
        if quiet > 600 and H.frame - lastDump >= 600 then
          lastDump = H.frame
          wedgeDumps = wedgeDumps + 1
          dump("wedge " .. wedgeDumps)
          -- probe the inputs advanceStory never gives, one per cycle:
          -- a direction burst, then B, then A held longer, round-robin
          pokes = pokes + 1
          local kind = pokes % 3
          if kind == 1 then
            H.log("[wedge] probing a held DOWN burst")
            H.setPad({ down = true })
            return
          elseif kind == 2 then
            H.log("[wedge] probing a B tap")
            H.setPad({ b = true })
            return
          else
            H.log("[wedge] probing a long A hold")
            H.setPad({ a = true })
            return
          end
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "the instrumented reunion/Cranes ride")
  end)(),
  H.call(function()
    dump("END")
    H.log(string.format("[end] map=%d -- %s", map(),
      map() == 219 and "REACHED THE FLASHBACK (no wedge with this config)"
      or "wedge dumps exhausted; see the evPC/obj lines"))
    H.screenshot("cranes_wedge_end")
  end),
})
