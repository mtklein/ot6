-- probe_grind.lua -- INSTRUMENTATION (#132): thrust until over land, then land.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function landable() return (rd(0x1eb7) & 0x04) ~= 0 end
local function onFoot() return (H.readWord(0x1f64) & 0x2000) == 0 end  -- vehicle flag clear
local function snap(tag)
  H.log(string.format("f%-6d %-10s 1f64=%04X 1eb7=%02X shadow=(%d,%d) onfoot=%s",
    H.frame, tag, H.readWord(0x1f64), rd(0x1eb7), rd(0x1f62), rd(0x1f63), tostring(onFoot())))
end
H.run({ maxFrames = 12000 }, {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),
  H.pressButtons({ "a" }, 4), H.waitFrames(60),
  H.call(function() snap("aloft") end),
  -- thrust in a fixed heading until the shadow is over a landable tile
  H.driveUntil(function() return landable() end, 6000, {
    H.call(function()
      if H.frame % 200 == 0 then snap("seek") end
      H.setPad({ "a", "up" })       -- thrust forward+up
    end)
  }, "over land ($1eb7 bit2)"),
  H.release(), H.waitFrames(30), H.call(function() snap("over-land") end),
  -- now try to land: A-tap, then B, then Y, checking for the on-foot transition
  H.pressButtons({ "a" }, 2), H.waitFrames(40), H.call(function() snap("A") end),
  H.pressButtons({ "b" }, 4), H.waitFrames(40), H.call(function() snap("B") end),
  H.pressButtons({ "y" }, 4), H.waitFrames(40), H.call(function() snap("Y") end),
  H.logStep(function() return "done" end),
})
