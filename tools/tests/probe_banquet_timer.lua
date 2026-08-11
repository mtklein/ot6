-- probe_banquet_timer.lua -- banquet-timer destructive-bug probe, phase A
-- (issue #31; the route recon's first-named hazard).  Not a suite test.
--
-- Question measured: whether a save taken with the event timer live
-- round-trips.  A player inside the banquet's 4-minute window can walk
-- out of the castle (243 row y=31 -> 253 -> world, all ungated during
-- $007B=1) and world-save with the event timer live.
--
-- Staging: the banquet is 5 ungenerated steps downstream of
-- terra-returned-v1, so this probe does not reach it.  It cold-Continues
-- the terra-returned checkpoint (world (24,121), on foot at the parked
-- Blackjack) and hand-writes the timer-0 block exactly as
-- `start_timer 0, N, _cc8a96, {FIELD_VISIBLE, BANQUET,
-- MENU_BATTLE_VISIBLE}` would (EventCmd_a0, field/event.asm:3736-3757:
-- flags $72 = f|r|m + bank bits 2, ptr $028A96 = _cc8a96), plus switch
-- $007C=1 and score var 0 = 17 ($1FC2).  That staging tests the save/load
-- mechanism for a live banquet timer.  It says nothing about banquet
-- reachability, the castle-exit walk, or the dinner scene's behavior with
-- this party; those are separate claims (the exit rows are source-cited
-- in banquet-decode.md; the scene is only ridden to its first latch in
-- phase B).
--
-- Phase A measures:
--   A1  the world module does not tick timer 0 (no DecTimers call in
--       ff6/src/world/; measured here rather than only grepped);
--   A2  the menu does tick it (menu_common.asm:3466);
--   A3  the real Save UI (the same drive as gen_post_opera_checkpoint)
--       writes the timer block into the slot-3 save: PushTimers
--       (menu/save.asm:108) copies $1188-$119F to $1FA8,
--       CopyGameDataToSRAM copies $1600-$1FFF to SRAM.  Asserted by
--       reading the slot-3 bytes back at $307400+$9A8 and comparing the
--       flags and pointer byte for byte.
-- run.sh's OT6_CAPTURE_SRM then captures the battery for phase B
-- (probe_banquet_timer2.lua), which cold-boots it and watches the timer
-- resume, tick on a field map, and fire _cc8a96.
--
-- Run:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1 \
--   OT6_CAPTURE_SRM=build/states/banquet_timer_live.srm \
--   tools/tests/run.sh tools/tests/probe_banquet_timer.lua
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
local SAVE_SELECT = 0x14
local STAGE_FRAMES = 5400          -- 90s: room for the menu steps to tick
local SLOT3 = 0x307400             -- $306000 + SRAMSlotPtrs[3] ($1400)
local SLOT3_TIMER = SLOT3 + (0x1FA8 - 0x1600)
local SLOT3_VAR0  = SLOT3 + (0x1FC2 - 0x1600)

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function setSw(id, v)
  local a = 0x1E80 + (id >> 3)
  local m = 1 << (id & 7)
  local b = H.readByte(a)
  H.writeByte(a, v == 1 and (b | m) or (b & ~m))
end
local function timerCount() return H.readWord(0x1189) end
local function sram(off) return emu.read(off, emu.memType.snesMemory) end

local menuT0 = 0

H.run({ maxFrames = 30000 }, {
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3), the boot
  -- step probe_mp_universal measured: restores on foot at (24,121).
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world (parked Blackjack)", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("terra-returned-v1")
    H.assertEq(H.worldHasControl(), true, "world control at the checkpoint")
  end),

  -- Stage the live banquet timer and window state (see header for staging).
  H.call(function()
    H.writeByte(0x1188, 0x72)          -- pfrmxxee = 0111 0010
    H.writeWord(0x1189, STAGE_FRAMES)  -- counter
    H.writeByte(0x118B, 0x96)          -- _cc8a96 = CA0000 + $028A96
    H.writeByte(0x118C, 0x8A)
    H.writeByte(0x118D, 0x02)
    setSw(0x007C, 1)                   -- banquet window open
    setSw(0x013C, 0)                   -- dinner not yet fired
    H.writeWord(0x1FC2, 17)            -- score var 0 = 17 (witness)
    H.log(string.format("[stage] timer=%d flags=%02X ptr=%02X%02X%02X $007C=%d var0=%d",
      timerCount(), H.readByte(0x1188), H.readByte(0x118D),
      H.readByte(0x118C), H.readByte(0x118B), sw(0x007C), H.readWord(0x1FC2)))
  end),

  -- A1: the world module must not tick the timer (150 idle world frames).
  H.waitFrames(150),
  H.call(function()
    H.assertEq(timerCount(), STAGE_FRAMES,
      "A1: timer frozen on the world map (world module has no DecTimers)")
    H.log("[A1] 150 world frames, counter unchanged: PASS")
  end),

  -- A2: the menu does tick it (DecTimersMenuBattle, menu_common.asm:3466).
  H.repeatN(3, { H.pressButtons({ "x" }, 6), H.waitFrames(50) }),
  H.waitUntil(function() return H.readByte(0x59) ~= 0 end,
    500, "world menu open", 5),
  H.call(function() menuT0 = timerCount() end),
  H.waitFrames(120),
  H.call(function()
    local d = menuT0 - timerCount()
    H.log(string.format("[A2] menu ticked %d frames of timer in 120 frames", d))
    if d < 100 then
      error(string.format("A2: menu should tick the timer (~120), got %d", d))
    end
    H.screenshot("banquet_timer_menu")
  end),

  -- A3: real Save UI to slot 3 (gen_post_opera_checkpoint's drive, verbatim
  -- mechanics: zero the $307ff0 sentinel, enter the save selector the way
  -- the menu's own Save command does, confirm, watch the sentinel return).
  H.call(function()
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)
    H.assertEq(sram(0x307ff0), 0, "slot marker zeroed")
    H.writeByte(ZMENUSTATE, SAVE_SELECT_INIT)
  end),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    300, "save-slot selection", 5),
  H.call(function()
    H.writeByte(0x4b, 2)  -- zero-based cursor: slot 3
    H.writeWord(0x95, 0)
  end),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function() return sram(0x307ff0) == 3 end, 800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed (slot marker back to 3)"),
  H.waitFrames(60),

  -- verdict: whether the save carried the live timer
  H.call(function()
    local wf  = H.readByte(0x1188)
    local wc  = timerCount()
    local sf  = sram(SLOT3_TIMER + 0)
    local sc  = sram(SLOT3_TIMER + 1) + 256 * sram(SLOT3_TIMER + 2)
    local sp0 = sram(SLOT3_TIMER + 3)
    local sp1 = sram(SLOT3_TIMER + 4)
    local sp2 = sram(SLOT3_TIMER + 5)
    local sv0 = sram(SLOT3_VAR0) + 256 * sram(SLOT3_VAR0 + 1)
    H.log(string.format(
      "[A3] WRAM timer flags=%02X count=%d | SRAM slot3 flags=%02X count=%d ptr=%02X %02X %02X var0=%d",
      wf, wc, sf, sc, sp0, sp1, sp2, sv0))
    H.assertEq(sf, 0x72, "A3: saved timer flags byte ($72)")
    H.assertEq(sp0, 0x96, "A3: saved callback ptr low ($96)")
    H.assertEq(sp1, 0x8A, "A3: saved callback ptr mid ($8A)")
    H.assertEq(sp2, 0x02, "A3: saved callback bank bits ($02)")
    H.assertEq(sv0, 17, "A3: saved score var 0")
    if sc <= 0 or sc > STAGE_FRAMES then
      error(string.format("A3: saved counter %d out of range (0,%d]", sc, STAGE_FRAMES))
    end
    -- counter kept ticking after PushTimers snapshotted it
    if wc > sc then
      error(string.format("A3: live counter %d > saved %d (?)", wc, sc))
    end
    H.log("[A3] PushTimers carried the live timer into the slot-3 save: PASS")
  end),

  -- leave the menu so the shutdown battery flush is a settled world state
  H.repeatN(4, { H.pressButtons({ "b" }, 6), H.waitFrames(30) }),
  H.call(function()
    H.log(string.format("[done] menu=%02X counter=%d -- phase A complete; "
      .. "run.sh captures the battery for phase B", H.readByte(0x59), timerCount()))
  end),
})
