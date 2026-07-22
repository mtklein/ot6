-- probe_opera_ariafire.lua -- boots opera_stage (238, $0056=1), steps onto the
-- aria trigger (97,7), and rides the narration to the FIRST lyric fork, logging
-- the choice-dialog state ($056e cursor / $056f count / $00d3).  TIGHT budgets.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s | 56=%d 57=%d 58=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | 056e=%d 056f=%d 00d3=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()), tostring(H.dialogWaiting()),
    sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2),
    H.readByte(0x056e), H.readByte(0x056f), H.readByte(0x00d3)))
end

H.run({ maxFrames = 40000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),238,"boot 238"); dumpsw("boot") end),

  -- step onto the aria trigger (97,7); the aria fades + loads map 236
  H.navTo(97, 7, { maxFrames=6000, arrive=function() return map()~=238 or not H.hasControl() end }),
  H.call(function() dumpsw("aria-triggered") end),

  -- ride the narration (edge-A) until a CHOICE appears ($056f>=2) or map settles on 236
  (function() local aPh,last=0,-1
    return H.driveUntil(function()
      if map()~=last then last=map(); H.log(string.format("[fire] f%d map=%d ctl=%s dlg=%s 056f=%d", H.frame, map(), tostring(H.hasControl()), tostring(H.dialogWaiting()), H.readByte(0x056f))) end
      return H.readByte(0x056f) >= 2 or sw(0x0111)==1
    end, 12000, {
      H.call(function() aPh=(aPh+1)%8
        if H.frame % 240 == 0 then dumpsw("ride") end
        if menuOpen() then H.setPad(aPh<4 and {"start"} or {}); return end
        if H.dialogWaiting() then H.setPad(aPh<4 and {"a"} or {}); return end
        -- flag-less stall: tap A to advance TEXT_ONLY pages
        H.setPad(aPh<4 and {"a"} or {})
      end) }, "ride to first fork")
  end)(),
  H.call(function() dumpsw("FORK-1 up"); H.screenshot("aria_fork1") end),
  H.logStep(function() return string.format("ariafire done f%d map=%d 056f=%d 111=%d", H.frame, map(), H.readByte(0x056f), sw(0x0111)) end),
})
