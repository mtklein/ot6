-- battle_hudclobber: a battle dialogue must never leave the under-enemy HUD
-- drawing from blanked glyph tiles -- junk over and around the enemies.
--
-- THE BUG (owner sighting, v0.2+): "showing up every once in a while during
-- battle, drawing over and around the enemies, maybe comprising break icons
-- amongst other things that look like junk memory, but not exclusively."
-- ROOT CAUSE: window_mess_open_init (_c142e4, btlgfx_main.asm:9264) opens a
-- battle dialog by ClearDlgGfxBuf-ing the whole small font and re-uploading it
-- to vram $5800 (SmallFontGfx, four TfrDlgTextGfx passes), which zeroes OT6's
-- borrowed HUD glyph tiles ($64-$79, $eb-$fd -- all blank in the vanilla
-- font).  Only the dialog CLOSE (_c143b9) re-flags the OT6 re-lay; the OPEN
-- does not, and the window keeps re-uploading as it prints.  So from a dialog
-- opening until its close re-lay finishes -- and for the WHOLE fight when the
-- script never issues a close -- the HUD map still points at those now-blank
-- tiles, and the shield/break/'?' cells render as junk.  Reproduced in the
-- Narshe Magitek-flashback fight (battle 115, Kefka's "Uwee, hee, hee!"): the
-- HUD drew from blanked tiles ~5000/9000 frames (probe_moogfont / _moogjunk).
--
-- THE FIX (Ot6BgHudFlush_ext veil): while a dialog window is up (w7e64d5) or a
-- font re-lay is in flight (OT6_FONTDIRTY), the flush writes vanilla's $01ee
-- fill over the HUD lines instead of their cells -- the same veil an entry/
-- exit animation gets -- so the HUD is cleanly hidden (never junk) and repaints
-- once the tiles are whole.
--
-- THE INVARIANT, asserted every frame of a fight that opens a dialogue: NO bg3
-- field-map cell may hold an OT6 glyph char whose tile data is, that frame,
-- clobbered (!= its bank-F0 source).  Positive control so a quiet pass can't
-- hide a regression: the dialogue must actually have clobbered the tiles
-- (tileDirty frames > 0) -- else the hazard was never exercised.
--
-- Frontier-gated on moogle_doorstep.mss (make frontier), the battle_vargas
-- pattern.
--   tools/tests/run.sh tools/tests/battle_hudclobber.lua   (needs moogle_doorstep.mss)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/moogle_doorstep.mss.lua"
local VR, ROM = emu.memType.snesVideoRam, emu.memType.snesPrgRom

-- OT6 glyph cells + their rom source (glyphCanary's signature scan)
local allCells, claimed = {}, {}
local function findRom()
  local function findSig(sig)
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do if emu.read(base+i-1, ROM) ~= sig[i] then hit = false break end end
      if hit then return base end
    end
  end
  local ic = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  local bg = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(ic ~= nil and bg ~= nil, true, "OT6 glyph data found in rom")
  for k,c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do allCells[c]=ic+(k-1)*16; claimed[c]=true end
  for k=1,16 do local c=emu.read(bg-17+k,ROM); allCells[c]=bg+(k-1)*16; claimed[c]=true end
  claimed[0xbf]=true                     -- '?' (vanilla's own glyph; a HUD char)
end
local function tileClobbered(cell)
  local rb = allCells[cell]; if not rb then return false end
  for i=0,15 do if emu.read(0xB000+cell*16+i, VR) ~= emu.read(rb+i, ROM) then return true end end
  return false
end
local function fieldBaseW() local r=H.readByte(0x897b); return (r-(r%4))*256 end
-- (junk cells this frame, whether any OT6 tile is clobbered this frame)
local function scan()
  local dirty = {}
  local anyDirty = false
  for c in pairs(allCells) do if tileClobbered(c) then dirty[c]=true; anyDirty=true end end
  if not anyDirty then return 0, false end
  local bw, n = fieldBaseW(), 0
  for w=0,0x3ff do
    local lo,hi = emu.read((bw+w)*2,VR), emu.read((bw+w)*2+1,VR)
    if (hi&0x01)==1 and claimed[lo] and dirty[lo] then n=n+1 end
  end
  return n, true
end

-- scanline instrument (battle_banner's pinned C1 exec hooks): the dialogue's
-- font re-lay slices run on the same NMIs as the (veiled) line flush, so this
-- fight also exercises the flush-timing invariant -- assert it stays in vblank.
local armed = false
local rec, cur = {}, nil
local function sl() return emu.getState()["ppu.scanline"] end
local function norm(v) if v == nil then return -1 end return (v < 100) and v + 262 or v end
emu.addMemoryCallback(function() if armed then cur = { fe = -1, id = -1 }; rec[#rec+1] = cur end end,
  emu.callbackType.exec, 0xC10BA7, 0xC10BA7)
emu.addMemoryCallback(function() if armed and cur then cur.fe = sl() end end,
  emu.callbackType.exec, 0xC10C1B, 0xC10C1B)
emu.addMemoryCallback(function() if armed and cur then cur.id = sl() end end,
  emu.callbackType.exec, 0xC10CA4, 0xC10CA4)

local junkFrames, tileDirtyFrames, maxJunk, worstFrame = 0, 0, 0, -1
local worstFe, worstId, spillFrames = 0, 0, 0
local function sample()
  local r = rec[#rec]
  if r then
    local fe, id = norm(r.fe), norm(r.id)
    if fe > worstFe then worstFe = fe end
    if id > worstId then worstId = id end
    if fe > 261 or id > 261 then spillFrames = spillFrames + 1 end
  end
  local j, td = scan()
  if td then tileDirtyFrames = tileDirtyFrames + 1 end
  if j > 0 then
    junkFrames = junkFrames + 1
    if j > maxJunk then maxJunk, worstFrame = j, H.frame end
    if junkFrames <= 3 then
      H.log(string.format("VIOLATION f=%d %d hud cell(s) render a clobbered tile "
        .. "(w7e64d5=%02x veil=%02x fontdirty=%02x)", H.frame, j,
        H.readByte(0x64d5), H.readByte(0x57be), H.readByte(0x57b9)))
      H.screenshot(string.format("hudclobber_junk_f%d", H.frame))
    end
  end
end

H.run({ maxFrames=24000 }, {
  H.waitFrames(20), H.loadState(STATE), H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 12000, {
    H.hold({"up"}), H.waitFrames(12), H.release(), H.waitFrames(2),
    H.pressButtons({"a"},4), H.waitFrames(6),
  }, "the Narshe flashback fight starts"),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle up", 10),
  H.waitFrames(120),
  H.call(function()
    findRom()
    H.log("[hudclobber] formation " ..
      string.format("%04X %04X %04X %04X %04X %04X", table.unpack(H.formationWords())))
    H.assertEq(H.monstersPresent() > 0, true, "a live formation (enemies present)")
    armed = true
  end),
  -- ride the fight, tapping A to advance Kefka's dialogue (which clobbers the
  -- font), sampling the invariant every frame
  (function()
    local f=0
    return H.driveUntil(function() f=f+1; return f>5000 end, 5300, {
      H.call(function()
        if H.readByte(0x7bca)~=0 and f%40<4 then H.setPad({"a"})
        elseif H.dialogWaiting() and f%20<3 then H.setPad({"a"}) else H.setPad({}) end
        sample()
      end),
      H.waitFrames(1),
    }, "dialogue fight soak")
  end)(),
  H.call(function()
    armed = false
    H.log(string.format("[hudclobber] frames sampled, tileDirtyFrames=%d junkFrames=%d maxJunk=%d",
      tileDirtyFrames, junkFrames, maxJunk))
    H.log(string.format("[hudclobber] NMI tail: worstFlushEnd=%d worstPostInidisp=%d spillFrames=%d (records=%d)",
      worstFe, worstId, spillFrames, #rec))
    -- (a) the flush + INIDISP stay in vblank even with a re-lay slice on the
    -- same NMI as the veiled line flush (the disproven-but-guarded timing hazard)
    H.assertEq(#rec >= 500, true, "scanline instrument recorded the fight (got " .. #rec .. ")")
    H.assertEq(spillFrames, 0, string.format(
      "every NMI tail stayed in vblank [<=261] (worstFlushEnd=%d worstPostInidisp=%d)",
      worstFe, worstId))
    -- positive control: the dialogue really did blank our tiles (hazard armed)
    H.assertEq(tileDirtyFrames > 200, true,
      "the battle dialogue clobbered the OT6 glyph tiles (tileDirtyFrames=" ..
      tileDirtyFrames .. ") -- else this fight never exercised the hazard")
    -- THE INVARIANT: never draw the HUD from a clobbered tile
    H.assertEq(junkFrames, 0, string.format(
      "the HUD never rendered break/shield/icon glyphs from blanked tiles "
      .. "(junkFrames=%d, worst %d cells at f%d)", junkFrames, maxJunk, worstFrame))
    H.screenshot("hudclobber_final")
  end),
})
