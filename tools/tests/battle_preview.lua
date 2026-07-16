-- battle_preview: the un-made choice telegraphs its boost. With 2 BP
-- pending, opening Terra's magic list renders "Fire 3" in Fire's row
-- (Ot6PreviewList_ext folds the render-scoped id) while cost and
-- selection stay on base Fire.
--   asserts: with pending=2 the open list shows Fire's name with a '3';
--   screenshot for the eyeball record.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local terra
local clicks, clickRef

local function findTerra()
  for slot = 0, 3 do
    if H.readByte(0x3ed8 + slot*2) == 0 then return slot end
  end
end

-- "Fire" followed by a '3' within 3 cells, in the ability-list staging
-- rows (map rows 32+; rendered rows persist, but a '3' only appears
-- there when the folded name rendered)
local function fire3InList()
  local vr = emu.memType.snesVideoRam
  for w = 0x400, 0x51c do
    local base = (0x7800 + w) * 2
    if emu.read(base, vr) == 0x85 and emu.read(base+2, vr) == 0xa2 and
       emu.read(base+4, vr) == 0xab and emu.read(base+6, vr) == 0x9e then
      for k = 4, 7 do
        if emu.read(base + k*2, vr) == 0xb7 then return true end
      end
    end
  end
  return false
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function()
    terra = findTerra()
    H.log("terra is slot " .. terra)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)  -- stop the guards
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
  end),
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == terra
  end, 10000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= terra then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "terra's menu up"),
  -- back out of any list a stray entry-mash A opened, then rig the boost
  H.pressButtons({ "b" }, 6), H.waitFrames(24),
  H.pressButtons({ "b" }, 6), H.waitFrames(24),
  H.call(function()
    H.writeByte(0x3e9c + terra*2, 3)
    H.writeByte(0x3e9d + terra*2, 2)
    clicks = 0
    clickRef = emu.addMemoryCallback(function(addr, value)
      if value ~= 0 then clicks = clicks + 1 end
    end, emu.callbackType.write, 0x000094, 0x000094)
  end),
  -- one verified cursor step down: MagiTek -> Magic
  H.driveUntil(function() return clicks >= 1 end, 1200, {
    H.call(function() if clicks == 0 then H.setPad({ "down" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "cursor on Magic"),
  H.call(function()
    emu.removeMemoryCallback(clickRef, emu.callbackType.write, 0x000094, 0x000094)
  end),
  -- open the list until the folded preview is actually rendered
  H.driveUntil(function() return fire3InList() end, 2400, {
    H.call(function() if not fire3InList() then H.setPad({ "a" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "list shows Fire 3 preview"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(fire3InList(), true, "boosted list previews Fire 3")
    H.assertEq(pend(terra), 2, "still just a preview: boost not consumed")
    H.screenshot("preview_list")
  end),
})
