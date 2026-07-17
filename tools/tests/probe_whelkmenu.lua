-- probe_whelkmenu.lua -- MINIMAL REPRO of the pre-existing garbled-menu
-- bug in battles that open with a scripted battle dialog. Enter the
-- Whelk fight (gen_whelk's drive; it opens with "VICKS: Hold it!"),
-- edge-tap A only until the first menu appears, then NEVER touch the
-- pad again; screenshot the untouched menu -> whelkmenu_untouched.png
-- shows garbage-staged rows. Reproduced on the pre-M3 committed ROM
-- too (this is not an M3 regression); tracked as a separate task. The
-- M3 probes work around it by driving Fight via berserk, not menus.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end
local aPhase = 0
H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return whelk() end, 2200, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if whelk() then H.setPad({}); return end
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),
  H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 4000, {
    H.call(function()
      -- edge-tap A on a sparse cadence to advance the opening dialogs
      local n = (H.vars.mn or 0) + 1
      H.vars.mn = n
      H.setPad(n % 60 < 4 and { "a" } or {})
    end),
  }, "first menu opens"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(300),
  H.call(function()
    H.screenshot("whelkmenu_untouched")
    H.log(string.format("menu=%02x holder=%d state=%02x",
      H.readByte(0x7bca), H.readByte(0x62CA), H.readByte(0x7bc2)))
  end),
})
