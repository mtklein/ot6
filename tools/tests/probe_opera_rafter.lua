-- probe_opera_rafter.lua -- boot opera_dance_done (map 238 {98,7} $0111=1);
-- observe the post-aria state and what triggers the rafter chase.  Dump switches
-- + position; walk LEFT/around A-mashing to see if Ultros (_cabf31 dlg $04C8,
-- $0058=1) fires, tracking map/switch changes.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s | 57=%d 58=%d 111=%d 345=%d 355=%d 366=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()), tostring(H.dialogWaiting()),
    sw(0x0057), sw(0x0058), sw(0x0111), sw(0x0345), sw(0x0355), sw(0x0366)))
end
H.run({ maxFrames = 8000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),238,"boot 238"); dumpsw("BOOT"); H.screenshot("rafter_boot") end),
  -- bfs reachability probe from here
  H.call(function()
    for _,t in ipairs({{97,7},{90,7},{98,10},{100,20},{99,20}}) do
      local p=H.bfsPath(t[1],t[2])
      H.log(string.format("[bfs] (%d,%d): %s", t[1],t[2], p and (#p.." steps") or "no path"))
    end
  end),
  -- walk left + A-mash, watch for the Ultros/rafter trigger
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0058)==1 or map()~=238 end, 5000, {
      H.call(function() hb=hb+1
        if hb%60==0 then dumpsw("walk") end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if hb%20<12 then H.setPad({"left"}) elseif hb%20<16 then H.setPad({"a"}) else H.setPad({"up"}) end
      end) }, "seek Ultros trigger") end)(),
  H.waitFrames(30),
  H.call(function() dumpsw("AFTER-WALK"); H.screenshot("rafter_afterwalk") end),
  H.logStep(function() return string.format("rafter probe f%d map=%d (%d,%d) 58=%d 355=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0058), sw(0x0355)) end),
})
