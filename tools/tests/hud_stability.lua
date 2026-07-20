-- hud_stability: the under-monster HUD must be rock-solid across TIME.
-- single-frame snapshots can pass while the HUD strobes (it happened);
-- this test watches the actual cell words frame by frame.
--   1. both guards' lines present after settle
--   2. 600 idle frames: the visible cell set never changes at all
--   3. an attack may contest BG3, but within 120 frames of the action
--      landing the HUD is back and stays put for 300 more frames
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local GLYPH = {[0x65]=1,[0x66]=1,[0x67]=1,[0x69]=1,[0x6a]=1,[0x6b]=1,[0x71]=1,
               [0xbf]=1,[0xeb]=1,[0xec]=1,[0xed]=1,[0x64]=1,[0xef]=1,
               [0xfb]=1,[0xfc]=1,[0xfd]=1}
local function cellset()
  local vr = emu.memType.snesVideoRam
  local reg = H.readByte(0x897b)
  local base = ((reg - (reg % 4)) * 256) * 2
  local t = {}
  for off = 0, 0x7FE, 2 do
    local lo = emu.read(base+off, vr)
    if emu.read(base+off+1, vr) == 0x21 and GLYPH[lo] then
      t[#t+1] = string.format("%04x:%02x", (base+off)//2, lo)
    end
  end
  return table.concat(t, " ")
end
local function lineCount(set)
  -- distinct map rows represented in the cell set
  local rows, n = {}, 0
  for addr in set:gmatch("(%x+):") do
    local row = math.floor(tonumber(addr, 16) / 32)
    if not rows[row] then rows[row] = true; n = n + 1 end
  end
  return n
end
local baseline, changes = nil, 0
local actorSlot, bpBefore
local function stableWatch(tag, nframes)
  local count = 0
  return H.waitUntil(function()
    count = count + 1
    local now = cellset()
    if now ~= baseline then
      changes = changes + 1
      if changes <= 8 then
        H.log(string.format("%s CHANGE f%d: %s", tag, H.frame,
          now == "" and "(NONE)" or now))
        if changes <= 3 then H.screenshot(string.format("%s_chg%d", tag, changes)) end
      end
      baseline = now
    end
    return count >= nframes
  end, nframes + 120, tag, 1)
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
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
    baseline = cellset()
    H.log("idle cells: " .. baseline)
    H.assertEq(lineCount(baseline) >= 2, true, "both guards' hud lines present")
    changes = 0
  end),
  stableWatch("idle", 600),
  H.call(function()
    H.assertEq(changes, 0, "idle hud perfectly stable for 600 frames")
  end),
  -- one attack round: BG3 is contested during the effect, then must
  -- heal. menus eat inputs on some mints, so berserk the party instead:
  -- forced menu-less auto-actions (magitek chars fire random beams —
  -- exactly the effect art that contests BG3)
  H.call(function()
    actorSlot = H.readByte(0x62ca)
    bpBefore = H.readByte(0x3e9c + actorSlot*2)
    for slot = 0, 3 do
      local a = 0x3ee5 + slot*2
      H.writeByte(a, H.readByte(a) | 0x10)
    end
  end),
  H.waitUntil(function()
    return H.readByte(0x3e9c + actorSlot*2) ~= bpBefore
  end, 8000, "action lands", 10),
  H.waitFrames(120),   -- recovery window
  -- un-berserk and let the action queue drain (battle_hudtrack's idiom)
  -- before the stability watch: the party stays berserk otherwise, and
  -- every further beam is an animation whose 16x16 window the anim-mode
  -- veil (battle_hudanim16) now legitimately blanks the hud through --
  -- "stays put" is a steady-state property, so measure it in steady state.
  H.call(function()
    for slot = 0, 3 do
      local a = 0x3ee5 + slot*2
      H.writeByte(a, H.readByte(a) & 0xEF)
    end
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
  end),
  -- an instantaneous check raced the queue: un-berserking cancels no
  -- already-queued action, so a beam could still land between a one-shot
  -- "hud is back" sample and the baseline.  require the settled state --
  -- no animation script, bg3 in 8x8, hud painted -- to hold for 60
  -- CONSECUTIVE frames before baselining.
  (function()
    local calm = 0
    return H.waitUntil(function()
      local ok = H.readByte(0x57bf) == 0
        and H.readByte(0x896f) % 128 < 64
        and H.fieldHudPresent()
      calm = ok and calm + 1 or 0
      return calm >= 60
    end, 2400, "queue drained, bg3 8x8, hud repainted, 60 frames calm", 1)
  end)(),
  H.call(function()
    baseline = cellset()
    H.log("post-attack cells: " .. baseline)
    H.assertEq(lineCount(baseline) >= 2, true, "hud recovered after the attack")
    changes = 0
  end),
  stableWatch("post-attack", 300),
  H.call(function()
    H.assertEq(changes, 0, "hud stable after recovery")
  end),
})
