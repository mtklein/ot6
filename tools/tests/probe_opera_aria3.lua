-- probe_opera_aria3.lua -- boots opera_stage, fires the aria (step 97,7 -> map
-- 236), drives the three lyric forks {0,1,0}, then OBSERVES the post-fork state
-- (the flower dance): CELES pos, $0057/$0111/$01F0-2, NPCs.  Tight budgets.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local function menuOpen() return H.readByte(0x0059) ~= 0 end
local function dumpsw(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s | 56=%d 57=%d 58=%d 110=%d 111=%d 1F0=%d 1F1=%d 1F2=%d | cur=%d cnt=%d d3=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()), tostring(H.dialogWaiting()),
    sw(0x0056), sw(0x0057), sw(0x0058), sw(0x0110), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2),
    H.readByte(0x056e), H.readByte(0x056f), H.readByte(0x00d3)))
end
-- ride to a 2-way choice and pick `idx`; terminate once picked & choice closed
local function ariaFork(idx, what)
  local ph, confirmed = 0, false
  return H.driveUntil(function()
    if confirmed and H.readByte(0x056f) < 2 and not H.dialogWaiting() then return true end
    return sw(0x0111)==1 or (map()~=236 and map()~=238)  -- bail on success or fail-reset
  end, 15000, { H.call(function()
    ph=(ph+1)%8
    if H.frame % 300 == 0 then dumpsw("fork:"..what) end
    local maxc, cur = H.readByte(0x056f), H.readByte(0x056e)
    if maxc >= 2 then
      if cur < idx then H.setPad(ph<3 and {"down"} or {})
      elseif cur > idx then H.setPad(ph<3 and {"up"} or {})
      else H.setPad(ph<3 and {"a"} or {}); if ph<3 then confirmed=true end end
    else
      H.setPad(ph<4 and {"a"} or {})   -- advance narration / TEXT_ONLY / wait_song
    end
  end) }, what)
end

H.run({ maxFrames = 50000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),238,"boot 238"); dumpsw("boot") end),

  -- fire the aria: step onto (97,7); the event fades and loads map 236
  H.navTo(97, 7, { maxFrames=8000, arrive=function() return map()~=238 end }),
  H.waitUntil(function() return map()==236 end, 6000, "aria loaded map 236", 10),
  H.waitFrames(30),
  H.call(function() dumpsw("aria on 236"); H.screenshot("aria_236") end),

  -- the three forks
  ariaFork(0, "fork1(0)"),
  H.call(function() dumpsw("after fork1") end),
  ariaFork(1, "fork2(1)"),
  H.call(function() dumpsw("after fork2") end),
  ariaFork(0, "fork3(0)"),
  H.call(function() dumpsw("after fork3"); H.screenshot("aria_after_forks") end),

  -- OBSERVE the flower dance: log state for a while WITHOUT driving (see if it
  -- auto-advances, where CELES/NPCs are, whether control returns)
  (function() local n=0
    return H.driveUntil(function() return sw(0x0111)==1 or (map()~=236) end, 4000, {
      H.call(function() n=n+1
        if n % 120 == 0 then dumpsw("observe") end
        H.setPad({})   -- do NOT drive; observe
      end) }, "observe post-fork") end)(),
  H.call(function() dumpsw("post-observe"); H.screenshot("aria_flowerdance") end),
  H.logStep(function() return string.format("aria3 done f%d map=%d (%d,%d) 57=%d 111=%d", H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111)) end),
})
