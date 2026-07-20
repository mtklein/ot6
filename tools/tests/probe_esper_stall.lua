-- probe_esper_stall.lua -- issue #3's instrument, rebuilt for the HONEST
-- chain (the spike_doorstep it used to boot is gone; kefka_doorstep is the
-- real thing).  Replays 632af69's tap-A-at-everything win tail and traces
-- every wait the tail is made of, ending at the wedge that killed it.
--
-- WHAT THE TRACE SHOWS (measured 2026-07-20, this probe + the listing):
--
--  1. f~3500-5600: event PC parked at $CCBEBA = the resume address after
--     `battle 78` ($CCBEB7, bytes 4D 4E FF -- event_main.asm:106707).
--     Battle 78 = group $4E -> formation 448 = TRITOCH_MORPH ($0115) alone
--     vs TERRA alone; its AI is `battle_event $12 / end_battle` on its
--     first main turn (ai_script.asm:5077), so it ENDS ITSELF -- its
--     battle-event text advanced by the taps.  battleLoadStarted() is
--     blind to the whole fight (TERRA alone leaves party battle-HP slot 0
--     at $FFFF), and battle text never raises field $00BA/$00D3: that pair
--     of blindspots is why the ORIGINAL advanceStory drive -- which taps
--     nothing it cannot see -- parked here forever, and why the stall was
--     misread as "dialogs without dialog flags".  Under blind taps this
--     wait clears in ~2100 frames.
--  2. Field dialogs park the PC at $CA0001 (WaitDlg) with $BA=1: the
--     flags DO work; taps clear them.  The map-0 vehicle flight and the
--     Arvis walk need nothing.
--  3. f~11100: THE WEDGE.  party_menu 1, RESET at _cacb9f
--     (event_main.asm:31284, called from _ccc1b5): $59=$81, and the blind
--     taps wander INTO the menu -- the screenshot shows a character's
--     Status page -- where A never exits and Start is never pressed.  The
--     script's own completion latches stay clear ($0602/$010B/$0048=0,
--     asserted below) while the pre-menu switch block ran ($02F1=1): the
--     event is alive inside the menu call, one commit short of done.
--
-- gen_kefka_won drives all three waits deliberately and mints past them.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/kefka_doorstep.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

H.run({ maxFrames = 20000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "A into KEFKA"),
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down")
  end)(),
  -- 632af69's recipe, verbatim: tap A at everything, kill-bit anything
  -- battleLoadStarted can see (battle 78 it cannot).  Trace the parks.
  (function()
    local aPh, wedgeN = 0, 0
    return H.driveUntil(function()
      wedgeN = H.readByte(0x0059) == 0x81 and wedgeN + 1 or 0
      return wedgeN >= 600
    end, 16000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.frame % 300 == 0 then
          H.log(string.format(
            "[ride] f%d map=%d PC=%02X%02X%02X $ba=%d $59=%02X zap=%04X",
            H.frame, map(),
            H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
            H.readByte(0x00ba), H.readByte(0x0059), H.readWord(0x57C0)))
        end
        if H.battleLoadStarted() and H.monstersPresent() > 0 then
          killBitAll()
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the party-menu wedge ($59=$81 for 600 straight frames)")
  end)(),
  H.call(function()
    H.log(string.format(
      "[wedge] f%d map=%d PC=%02X%02X%02X $59=%02X $26=%02X $0200=%02X",
      H.frame, map(),
      H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
      H.readByte(0x0059), H.readByte(0x0026), H.readByte(0x0200)))
    -- the tail's own progress latches, blind taps' high-water mark:
    H.assertEq(sw(0x0139), 1, "battle-won latch set (the win itself stands)")
    H.assertEq(sw(0x02F1), 1, "the split-up switch block ran (dlg $0385 passed)")
    H.assertEq(sw(0x0602), 0, "$0602 CLEAR -- the post-menu stretch never ran")
    H.assertEq(sw(0x010B), 0, "$010B CLEAR -- ditto")
    H.assertEq(sw(0x0048), 0, "$0048 CLEAR -- ditto")
    H.screenshot("esper_stall")
  end),
})
