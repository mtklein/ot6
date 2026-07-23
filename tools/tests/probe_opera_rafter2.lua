-- probe_opera_rafter2.lua -- Beat A rafter-chase recon, leg 1 (Ultros drop-in).
-- Boots opera_dance_done (238 {98,7} $0111=1, $0345=1).  MECHANISM (measured
-- from ff6/src/event, event_main.asm + npc_prop.asm + event_trigger.asm):
--  * 238 {99,20}: ENVELOPE NPC (vis gate $0345=1) event _cabf31 -> dlg
--    $04C8/$04C9, sets $0345=0, $0058=1 (Ultros threatens; "tell the
--    Impresario").  no_react NPC: fires on contact/bump.
--  * IMPRESARIO (_cab724) lives on MAP 234 {15,46}.  With $0058=1 & $0110=0 he
--    runs _cab744 -> the 5-min cutscene -> $0110=1 $02BA=1 $02BC=1 +
--    start_timer 0,18000,_caba09 (expiry = Ultros wins).  Reached 238->237->234.
-- This probe: dump boot, object-scan 238, drive to {99,20}, touch the envelope,
-- confirm $0058=1; then log where control lands.  Recon only.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
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
  H.loadState("/Users/mtklein/ot6/build/states/opera_dance_done.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 238, "boot on the stage (map 238)")
    dumpsw("BOOT"); objscan("BOOT"); H.screenshot("rafter2_boot")
    for _,t in ipairs({{99,20},{99,18},{100,22},{98,20},{99,19}}) do
      local p=H.bfsPath(t[1],t[2])
      H.log(string.format("[bfs] (%d,%d): %s", t[1],t[2], p and (#p.." steps") or "no path"))
    end
  end),

  -- Leg 1: reach {99,20} and touch the envelope.  March down toward it, nudging
  -- x to 99, then bump down/A when adjacent.
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
        -- at/near (99,19): bump DOWN into the envelope at (99,20) + A
        H.setPad(hb%2==0 and {"down"} or {"a"})
      end) }, "touch envelope -> $0058")
  end)(),
  H.waitFrames(60),
  H.call(function() dumpsw("AFTER-ENVELOPE"); objscan("AFTER-ENVELOPE"); H.screenshot("rafter2_env") end),
})
