-- probe_grind.lua -- INSTRUMENTATION (#132): does B over c2-landable actually land?
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function canLand() return (rd(0xc2) & 0x02) == 0 end
local function snap(tag)
  H.log(string.format("f%-6d %-10s 1f64=%04X c2=%02X 19=%02X e7=%02X e0=%02X e2=%02X worldctrl=%s",
    H.frame, tag, H.readWord(0x1f64), rd(0xc2), rd(0x19), rd(0xe7), rd(0xe0), rd(0xe2),
    tostring(H.worldHasControl())))
end
local clear = 0
H.run({ maxFrames = 12000 }, {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),
  H.pressButtons({ "a" }, 4), H.waitFrames(80),
  -- fly until landable & settled, hold position, press B, watch ALL land signals
  H.driveUntil(function()
    clear = canLand() and (clear + 1) or 0
    return clear >= 20            -- landable and stable for 20 frames
  end, 9000, { H.call(function() H.setPad(canLand() and {} or { "a", "up" }) end) }, "settled over land"),
  H.call(function() snap("settled") end),
  H.pressButtons({ "b" }, 3), H.waitFrames(20), H.call(function() snap("B+20") end),
  H.waitFrames(60), H.call(function() snap("B+80") end),
  H.waitFrames(120), H.call(function() snap("B+200") end),
  H.logStep(function() return "done" end),
})
