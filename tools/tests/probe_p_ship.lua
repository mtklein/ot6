-- @manual
-- probe_p_ship.lua -- where is the Blackjack at checkpoint P?  Cold-Continue
-- thamasa-done-v1, log the live ship registers ($34/$38, tile = >>4), the
-- saved landing bytes $1f62/$1f63, the vehicle byte $20 and $1f64, take a
-- lit screenshot, then one A press in place and the same reads again.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function dump(tag)
  H.log(string.format("[%s] party=(%d,%d) ship$34/$38=(%d,%d) $1f62/63=(%d,%d) $20=%02X $1f64=%04X $11F3=%02X world=%s ctrl=%s",
    tag, H.worldX(), H.worldY(), H.readWord(0x34) >> 4, H.readWord(0x38) >> 4,
    H.readByte(0x1f62), H.readByte(0x1f63), rd(0x20), H.readWord(0x1f64),
    H.readByte(0x11F3), tostring(H.worldMode()), tostring(H.worldHasControl())))
end
H.run({ maxFrames = 12000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "cold Continue to the world", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() dump("at P"); H.screenshot("p_ship_before") end),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return t >= 700 end, 800, {
      H.call(function()
        if t <= 10 then H.setPad({ up = true })
        elseif t == 120 then H.screenshot("p_at127")
        elseif t > 150 and t <= 158 then H.setPad({ left = true })   -- face west (blocked: turn only)
        elseif t > 200 and t <= 208 then H.setPad({ a = true })      -- talk/board toward the ship
        elseif t > 400 and t <= 408 then H.setPad({ up = true })     -- face north
        elseif t > 450 and t <= 458 then H.setPad({ a = true })
        else H.setPad({}) end
        if t % 30 == 0 or t == 210 or t == 460 then
          H.log(string.format("[step t=%d] map=%d $1f64=%04X $20=%02X $E0=%02X $E2=%02X world=%s ctrl=%s pos=(%d,%d) $11F3=%02X",
            t, H.mapId() & 0x3ff, H.readWord(0x1f64), rd(0x20), H.readByte(0xe0), H.readByte(0xe2),
            tostring(H.worldMode()), tostring(H.worldHasControl()), H.worldX(), H.worldY(), H.readByte(0x11F3)))
        end
        if t == 300 then H.screenshot("p_afterLeft") end
        if t == 600 then H.screenshot("p_afterRight") end
      end),
    }, "UP, LEFT, RIGHT, watched")
  end)(),
  H.logStep(function() return "done" end),
})
