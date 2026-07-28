-- probe_banquet_timer_cancel.lua -- companion to probe_banquet_timer:
-- does a NATURAL menu navigation (no ZMENUSTATE pokes) reproduce the
-- save-screen timer clobber, and does it happen even when the player
-- only LOOKS at the save screen and cancels without saving?
--
-- Staging identical to probe_banquet_timer (see its header for what the
-- staging can and cannot prove): terra-returned-v1 cold Continue, timer 0
-- hand-written to the live-banquet shape ($72 / _cc8a96), then:
--   1. open the world menu with X;
--   2. press UP once (main-menu cursor wraps to Save), then A -- the
--      ordinary player path into the save screen;
--   3. press B immediately (cancel, no save), B again to close the menu;
--   4. read the timer block back.
-- If $1188-$119F no longer holds $72/count/ptr, the SAVE SCREEN VISIT
-- ALONE corrupts a live event timer -- no save needed, no pokes involved.
-- NOT a suite test.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local STAGE = 5400
local function timerCount() return H.readWord(0x1189) end
local function blockHex()
  local s = ""
  for i = 0, 5 do s = s .. string.format("%02X ", H.readByte(0x1188 + i)) end
  return s
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.writeByte(0x1188, 0x72)
    H.writeWord(0x1189, STAGE)
    H.writeByte(0x118B, 0x96)
    H.writeByte(0x118C, 0x8A)
    H.writeByte(0x118D, 0x02)
    H.log("[stage] block: " .. blockHex())
  end),
  -- natural: X opens menu, UP wraps the cursor to Save, A enters
  H.repeatN(3, { H.pressButtons({ "x" }, 6), H.waitFrames(50) }),
  H.waitUntil(function() return H.readByte(0x59) ~= 0 end, 500, "menu", 5),
  H.waitFrames(30),
  H.call(function() H.log("[menu open] block: " .. blockHex()) end),
  H.pressButtons({ "up" }, 6), H.waitFrames(20),
  H.pressButtons({ "a" }, 6),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("[save screen] zstate=%02X block: %s",
      H.readByte(0x26), blockHex()))
    H.screenshot("banquet_timer_savescreen")
  end),
  -- cancel straight out, close the menu
  H.pressButtons({ "b" }, 6), H.waitFrames(60),
  H.pressButtons({ "b" }, 6), H.waitFrames(60),
  H.pressButtons({ "b" }, 6),
  H.waitUntil(function() return H.readByte(0x59) == 0 end, 600, "menu closed", 5),
  H.waitFrames(30),
  H.call(function()
    local f = H.readByte(0x1188)
    H.log(string.format("[verdict] after cancel-only save-screen visit: block: %s (count=%d)",
      blockHex(), timerCount()))
    if f == 0x72 then
      H.log("[verdict] timer SURVIVED the cancel-only visit")
    else
      H.log("[verdict] timer CORRUPTED by the save screen alone (no save, no pokes)")
    end
  end),
})
