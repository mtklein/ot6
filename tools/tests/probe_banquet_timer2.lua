-- probe_banquet_timer2.lua -- banquet-timer destructive-bug probe, phase B.
-- Cold-boots the battery that probe_banquet_timer_save.lua captured (a
-- NATURAL slot-3 save with a live staged banquet timer: flags $72,
-- counter ~5089, callback _cc8a96) and answers the reset/load half:
--
--   B1  Continue restores the timer block byte-for-byte (PopTimers,
--       menu/save.asm:121-128, called from LoadSavedGame :27) -- modulo
--       the frames the load menu itself already ticked;
--   B2  the world map still does not tick the restored timer;
--   B3  entering any FIELD map resumes the countdown (DecTimers,
--       field/reset.asm:98);
--   B4  expiry fires the saved callback: _cc8a96 stops the timer, sets
--       $013C, and teleports the party into the dinner sequence (map 5
--       "That evening..." then map 251) FROM WHEREVER THE PARTY STANDS --
--       here, a town the real banquet never visits.  (The counter is
--       FORCED to 240 after B3 to bound the wait; the CheckTimer path
--       taken is identical for any counter value -- field/event.asm
--       CheckTimer only compares against zero.)
--
-- Staging honesty: this run boots a STAGED battery (see
-- probe_banquet_timer.lua's header).  It proves the save/reset/load
-- mechanism for a live banquet timer end-to-end; it does not prove the
-- banquet window itself is reachable or that the full dinner scene is
-- coherent with this party -- the ride stops at the first dinner latch.
-- Run:
--   OT6_SRAM_ANCHOR=build/states/banquet-timer-live-anchor \
--   tools/tests/run.sh tools/tests/probe_banquet_timer2.lua
-- NOT a suite test.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function timerCount() return H.readWord(0x1189) end
local function sram(off) return emu.read(off, emu.memType.snesMemory) end
local function map() return H.mapId() & 0x1ff end
local function blockHex(base)
  local s = ""
  for i = 0, 5 do s = s .. string.format("%02X ", H.readByte(base + i)) end
  return s
end

local sramCount, fieldT0 = 0, 0

H.run({ maxFrames = 60000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue of the staged live-timer battery", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),

  -- B1: PopTimers restored the live timer
  H.call(function()
    sramCount = sram(0x307400 + 0x9A8 + 1) + 256 * sram(0x307400 + 0x9A8 + 2)
    H.log(string.format("[B1] battery block count=%d | WRAM block: %s(count=%d) $007C=%d $013C=%d var0=%d",
      sramCount, blockHex(0x1188), timerCount(), sw(0x007C), sw(0x013C),
      H.readWord(0x1FC2)))
    H.assertEq(H.readByte(0x1188), 0x72, "B1: restored flags $72")
    H.assertEq(H.readByte(0x118B), 0x96, "B1: restored ptr low")
    H.assertEq(H.readByte(0x118C), 0x8A, "B1: restored ptr mid")
    H.assertEq(H.readByte(0x118D), 0x02, "B1: restored ptr bank bits")
    -- $007C lives at $1E8F, inside the $1600-$1FFF block CopyGameDataToSRAM
    -- copies wholesale, so switch persistence needs no measurement; the
    -- staging battery (probe_banquet_timer_save) never set it, so it reads
    -- 0 here.  Logged above, not asserted.
    H.assertEq(sw(0x013C), 0, "B1: dinner not yet fired")
    H.assertEq(H.readWord(0x1FC2), 17, "B1: score var 0 survived")
    local c = timerCount()
    if c <= 0 or c > sramCount then
      error(string.format("B1: restored counter %d outside (0,%d]", c, sramCount))
    end
    H.log(string.format("[B1] PASS (load menu ticked %d frames)", sramCount - c))
  end),

  -- B2: still frozen on the world map
  H.call(function() fieldT0 = timerCount() end),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(timerCount(), fieldT0, "B2: world map does not tick the timer")
    H.log("[B2] PASS")
  end),

  -- B3: walk into the nearest field map (world (26,131) -> map 198).
  -- The battery keeps the terra-returned anchor's aboard bit in the
  -- $1f64/$1f65 save-block cells, so Continue resumes with stale world
  -- position regs ($E0/$E2 read (0,128) -- the gen_kolts lesson); the
  -- B-tap disembark guard plus a few raw steps re-initialize them before
  -- coordinate navigation (probe_mp_universal's boot pattern).
  (function()
    local ph2 = 0
    local function onFoot()
      return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
    end
    return H.driveUntil(function()
      return onFoot() and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark guard")
  end)(),
  H.release(),
  H.waitFrames(30),
  -- a few raw steps south to force real movement (re-seeds $E0/$E2)
  H.hold({ "down" }), H.waitFrames(60), H.release(), H.waitFrames(20),
  H.call(function()
    H.log(string.format("[B3] after raw steps world=(%d,%d), walking to the (26,132) doorstep",
      H.worldX(), H.worldY()))
  end),
  -- the BFS route crosses the (26,131) entrance tile itself, so the town
  -- entry happens mid-plan; `arrive` terminates the walk the moment the
  -- world is left (otherwise worldNavTo keeps driving inside the field map)
  (function()
    return H.worldNavTo(26, 132, { maxFrames = 30000,
      arrive = function() return not H.worldMode() end })
  end)(),
  H.release(),
  H.waitUntil(function() return H.hasControl() end, 1200, "field control", 10),
  H.call(function()
    H.log(string.format("[B3] entered field map %d at (%d,%d), timer=%d",
      map(), H.fieldX(), H.fieldY(), timerCount()))
    fieldT0 = timerCount()
  end),
  H.waitFrames(120),
  H.call(function()
    local d = fieldT0 - timerCount()
    H.log(string.format("[B3] field ticked %d frames of timer in 120 frames", d))
    if d < 100 then
      error(string.format("B3: field module should tick the timer (~120), got %d", d))
    end
    H.log("[B3] PASS")
  end),

  -- B4: bound the wait, then let it expire and fire _cc8a96
  H.call(function()
    H.writeWord(0x1189, 240)
    H.log("[B4] counter forced to 240 to bound the wait (mechanism unchanged)")
  end),
  H.waitUntil(function() return sw(0x013C) == 1 end, 2400,
    "timer expiry fires _cc8a96 ($013C set)", 5),
  H.call(function()
    H.log(string.format("[B4] callback fired: $013C=1, map=%d, timer flags=%02X count=%d",
      map(), H.readByte(0x1188), timerCount()))
  end),
  -- ride only to the dinner hall load: mash A through "That evening..."
  (function()
    local ph = 0
    return H.driveUntil(function() return map() == 251 end, 6000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { a = true } or {})
      end),
    }, "dinner sequence reaches map 251")
  end)(),
  H.release(),
  H.call(function()
    H.log(string.format("[B4] PASS: dinner hall loaded (map=%d) from a staged save/reset/load cycle", map()))
    H.screenshot("banquet_timer_dinner")
  end),
})
