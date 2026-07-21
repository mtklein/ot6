-- @suite
-- battle_preview: the un-made choice telegraphs its boost. With 2 BP
-- pending, opening Terra's magic list renders "Fire 3" in Fire's row
-- (Ot6PreviewList_ext folds the render-scoped id) while cost and
-- selection stay on base Fire.
--   asserts: with pending=2 the open list shows Fire's name with a '3';
--   screenshot for the eyeball record.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local terra, sawFold


local function findTerra()
  for slot = 0, 3 do
    if H.readByte(0x3ed8 + slot*2) == 0 then return slot end
  end
end

-- Fire's rendered tier in the ability-list staging rows (map rows 32+).
-- Names render spaces as $fe and pad with $ff: "Fire 2" = F,i,r,e,$fe,$b6
-- and plain "Fire" = F,i,r,e,$ff… — cell 4 being a true pad ($ff) also
-- cleanly excludes the magitek list's stale "Fire Beam" rows (space+B).
local function fireTier()
  local vr = emu.memType.snesVideoRam
  for w = 0x400, 0x51c do
    local base = (0x7800 + w) * 2
    if emu.read(base, vr) == 0x85 and emu.read(base+2, vr) == 0xa2 and
       emu.read(base+4, vr) == 0xab and emu.read(base+6, vr) == 0x9e then
      local digit = nil
      for k = 4, 6 do
        local c = emu.read(base + k*2, vr)
        if c == 0xb6 then digit = 2 end
        if c == 0xb7 then digit = 3 end
      end
      if digit then return digit end
      if emu.read(base + 8, vr) == 0xff then return 1 end
    end
  end
  return 0
end
local function fire3InList() return fireTier() == 3 end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
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
  H.call(function()
    H.writeByte(0x3e9c + terra*2, 3)
    H.writeByte(0x3e9d + terra*2, 2)
  end),
  -- the cursor's start row and any stray-open list are mint-dependent, so
  -- walk by goal: close whatever's open, step one row, open, and check
  -- for the folded name — converges from any start state within a lap
  H.driveUntil(function() return fire3InList() end, 4000, {
    H.call(function() if not fire3InList() then H.setPad({ "b" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
    H.call(function() if not fire3InList() then H.setPad({ "down" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
    H.call(function() if not fire3InList() then H.setPad({ "a" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(34),
  }, "list shows Fire 3 preview"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(fire3InList(), true, "boosted list previews Fire 3")
    H.assertEq(pend(terra), 2, "still just a preview: boost not consumed")
    H.screenshot("preview_list")
  end),
  -- the list is still open: R/L must re-fold the names in place
  H.driveUntil(function() return fireTier() == 2 end, 1200, {
    H.call(function() if fireTier() ~= 2 then H.setPad({ "l" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "L re-folds to Fire 2, live"),
  H.driveUntil(function() return fireTier() == 1 end, 1200, {
    H.call(function() if fireTier() ~= 1 then H.setPad({ "l" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "L re-folds to base Fire, live"),
  H.driveUntil(function() return fireTier() == 3 end, 1200, {
    H.call(function() if fireTier() ~= 3 then H.setPad({ "r" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "R climbs back to Fire 3, live"),
  H.waitFrames(30),   -- let the final 4-line staging cycle finish
  H.call(function()
    H.assertEq(pend(terra), 2, "round trip landed back on 2 pending")
    H.assertEq(fireTier(), 3, "and the settled list reads Fire 3")
    H.screenshot("preview_live")
    emu.addMemoryCallback(function(addr, value)
      if value == 0x09 or value == 0x2f then sawFold = true end
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- the menu must still be fully functional: confirm the (re-folded)
  -- fire and a target, and the fold lands at execution
  H.driveUntil(function() return pend(terra) == 0 end, 4000, {
    H.call(function() if pend(terra) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "cast lands after live re-folds"),
  H.waitFrames(60),
  H.call(function()
    -- the cursor rests wherever the walk left it: Cure and Fire both
    -- fold, and either tier-3 executing proves the post-refold cast
    H.assertEq(sawFold, true, "a re-folded spell executed at tier 3")
  end),
})
