-- probe_cranes_wedge.lua -- rides the route to the reunion Cranes fight
-- (map 6) with instrumentation:
--   * at the battle's rising and falling edges it dumps the b-switch
--     block ($1dd1, where $40/$44/$45 live in bits 0/4/5, and $1dd2+),
--     the formation words, and the per-slot monster hp/shield table;
--   * once the ride goes quiet (no battle, no dialog, no control, no
--     position change for 400 frames) it dumps state every 600 frames,
--     up to 25 times: the event PC ($00e5-7), the control gates, the
--     choice cells ($056e/f), and the full object table;
--   * it also drives a held direction burst and a B tap, each logged.
-- Ends after the wedge dump cycle or on reaching map 219.

local H = dofile("tools/tests/lib/ot6.lua")

-- Timeline selector: "A" = the tactical fighter (heals at 45); "B" =
-- plain Fights, no items, no boost.  Edit here between runs.
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
          -- battle table reads 0 during teardown)
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
        -- stamped (sampled per frame; no watchpoints)
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
        -- Edge-A only: once the fight is over, edge-taps A through the
        -- whole post-Cranes scene, whether or not dlg is set.
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
