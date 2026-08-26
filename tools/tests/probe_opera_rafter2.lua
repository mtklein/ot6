-- probe_opera_rafter2.lua -- boots opera_dance_done (238 {98,7} $0111=1, $0345=1).
-- 238 {99,20}: envelope NPC (vis gate $0345=1) sets $0345=0, $0058=1 (Ultros
-- threatens; "tell the Impresario").  The Impresario (_cab724) is on map 234
-- {15,46}: with $0058=1 & $0110=0 he starts a 5-min timer (18000 frames,
-- expiry = Ultros wins) and sets $0110=1 $02BA=1 $02BC=1.
-- This probe drives to {99,20}, touches the envelope, then logs where control lands.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function ovis(i) return H.readByte(0x0867 + i*STRIDE) end
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d)z%d ctl=%s dlg=%s | 56=%d 57=%d 58=%d 110=%d 111=%d 345=%d 355=%d 366=%d 36F=%d 387=%d 2BA=%d 2BC=%d A4=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    tostring(H.hasControl()), tostring(H.dialogWaiting()),
    sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0110), sw(0x0111), sw(0x0345),
    sw(0x0355), sw(0x0366), sw(0x036F), sw(0x0387), sw(0x02BA), sw(0x02BC), sw(0x00A4)))
end
local function objscan(tag)
  for i=0,31 do
    if (ovis(i)&0x80)~=0 then
      H.log(string.format("  [obj %s] #%d (%d,%d) vis=%02X", tag, i, ox(i), oy(i), ovis(i)))
    end
  end
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    dumpsw("BOOT"); objscan("BOOT"); H.screenshot("rafter2_boot")
    for _,t in ipairs({{99,20},{99,18},{100,22},{98,20},{99,19}}) do
      local p=H.bfsPath(t[1],t[2])
      H.log(string.format("[bfs] (%d,%d): %s", t[1],t[2], p and (#p.." steps") or "no path"))
    end
  end),

  -- march down toward {99,20}, nudging x to 99, then bump down/A when adjacent
  (function() local hb=0
    return H.driveUntil(function() return sw(0x0058)==1 or map()~=238 end, 8000, {
      H.call(function() hb=hb+1
        if hb%60==0 then dumpsw("seek58") end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local x,y=H.fieldX(),H.fieldY()
        if x<99 and H.canStep(x,y,"right") then H.setPad({right=true}); return end
        if x>99 and H.canStep(x,y,"left") then H.setPad({left=true}); return end
        if y<19 and H.canStep(x,y,"down") then H.setPad({down=true}); return end
        -- at/near (99,19): bump down into the envelope at (99,20), plus A
        H.setPad(hb%2==0 and {"down"} or {"a"})
      end) }, "touch envelope -> $0058")
  end)(),
  H.waitFrames(60),
  H.call(function() dumpsw("AFTER-ENVELOPE"); objscan("AFTER-ENVELOPE"); H.screenshot("rafter2_env") end),
})
