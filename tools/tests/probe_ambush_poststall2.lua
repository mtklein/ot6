-- probe_ambush_poststall2.lua -- issue #127, L->M: the post-ambush-WIN
-- field stall, take 2.  gen_thamasa_fire.lua's own live run (this pass)
-- confirmed the ambush is winnable for real (no GameOver fired, $050A
-- cleared cleanly) and captured build/states/ambush_won.mss right at that
-- moment (f21833).  This probe loads that state directly -- skipping the
-- ~22000-frame checkpoint boot/inn/fire/join/house-walk/fight setup -- and
-- installs WRITE watches (with the writing instruction's own PC) on every
-- register H.hasControl()/M.mapId() reads, to name the exact instruction
-- that corrupts them, per the STATUS header's own "instrumentation this
-- pass didn't build" gap.
local H = dofile("tools/tests/lib/ot6.lua")

H.loadState("build/states/ambush_won.mss.lua")

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pcOf()
  local s = emu.getState()
  return string.format("%02X:%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0)
end

local watches = {
  { name = "1f64(mapId)", lo = 0x7E1F64, hi = 0x7E1F65 },
  { name = "0084(ctlgate)", lo = 0x7E0084, hi = 0x7E0084 },
  { name = "0059(ctlgate)", lo = 0x7E0059, hi = 0x7E0059 },
  { name = "1eb9(ctlgate)", lo = 0x7E1EB9, hi = 0x7E1EB9 },
  { name = "0803(pobj)", lo = 0x7E0803, hi = 0x7E0804 },
  { name = "087c(movtbl0)", lo = 0x7E087C, hi = 0x7E087C },
  { name = "07fb(topcharptr)", lo = 0x7E07FB, hi = 0x7E07FC },
  { name = "1a6d(activeparty)", lo = 0x7E1A6D, hi = 0x7E1A6D },
  { name = "1850(TERRA)", lo = 0x7E1850, hi = 0x7E1850 },
  { name = "1857(STRAGO)", lo = 0x7E1857, hi = 0x7E1857 },
}
local hits = {}
for _, w in ipairs(watches) do
  emu.addMemoryCallback(function(addr, value)
    hits[#hits + 1] = string.format(
      "[watch] f%d pc=%s WROTE %s addr=$%06X val=$%02X",
      H.frame, pcOf(), w.name, addr, value)
    if #hits <= 400 then
      H.log(hits[#hits])
    end
  end, emu.callbackType.write, w.lo, w.hi)
end

local steps = {
  H.waitFrames(2),
  H.call(function()
    H.log(string.format(
      "[probe2] loaded ambush_won.mss: f%d map1f64=$%04X 0803=$%04X " ..
      "movByte=$%02X bright=%d ctl=%s",
      H.frame, H.readWord(0x1f64), H.readWord(0x0803),
      H.readByte(0x087c + H.readWord(0x0803)), bright(),
      tostring(H.hasControl())))
  end),
}
for i = 1, 3000 do
  steps[#steps + 1] = H.call(function()
    -- EXPERIMENT: pin $0803 (the party leader's object-block offset) back
    -- to 0 every frame once the game's own sort_obj_work recomputes it to
    -- the anomalous $07B0 seen live (a write-watch on $7E0803 traced that
    -- write to PC $C0:72A1/$C0:72A6, inside sort_obj_work's CheckOtherSlots
    -- loop -- event_main.asm's field-bank $C0 sort_obj implementation,
    -- roughly $C070B6-$C072D8).  $0803=0 is a value hasControl() DID read
    -- as valid (movByte=$02) for a real ~20-frame window right after the
    -- win, before this recompute clobbers it; testing whether re-pinning
    -- it recovers a walkable state once brightness also catches up.
    -- pin disabled this pass -- see the $1850/$07fb check below instead
    if H.frame % 20 == 0 then
      H.log(string.format(
        "[probe2 tick] f%d map1f64=$%04X 0803=$%04X 07fb=$%04X 1a6d=$%02X " ..
        "1850(T/L/St)=$%02X/$%02X/$%02X movByte=$%02X bright=%d ctl=%s " ..
        "algn=%s ev=%s dlg=%s",
        H.frame, H.readWord(0x1f64), H.readWord(0x0803),
        H.readWord(0x07fb), H.readByte(0x1a6d), H.readByte(0x1850),
        H.readByte(0x1851), H.readByte(0x1857),
        H.readByte(0x087c + H.readWord(0x0803)), bright(),
        tostring(H.hasControl()), tostring(H.tileAligned()),
        tostring(H.eventRunning()), tostring(H.dialogWaiting())))
    end
  end)
  steps[#steps + 1] = H.waitFrames(1)
end
steps[#steps + 1] = H.call(function()
  H.log(string.format("[probe2] DONE at f%d, %d total watch hits",
    H.frame, #hits))
end)

H.run({ maxFrames = 20000, allowGameOver = true }, steps)
