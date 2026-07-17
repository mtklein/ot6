-- battle_banner.lua -- TEMPORAL gate: attack-name banners must not tear.
--
--   tools/tests/run.sh tools/tests/battle_banner.lua
--
-- The bug this pins down (single-frame asserts cannot see flicker, so the
-- invariant is checked on EVERY frame of the sequence): vanilla builds its
-- attack/special/esper name-scratch string at $7E57D5 (ram_res w7e57d5,128;
-- GfxCmd_01/GfxCmd_11 and the swdtech/esper loaders all write byte 0
-- nonzero), and OT6_FONTDIRTY used to live on that exact byte.  Every named
-- banner then spuriously triggered the full ~46-scanline font re-lay in the
-- NMI tail, blowing ~30 scanlines past the end of vblank -- VRAM writes into
-- active display, INIDISP/HDMA setup landing mid-frame: the user-visible
-- screen flash/tear.  probe_banner measured end-of-flush at scanline 292
-- (vblank ends at 262) on banner frames vs 248 +/- 5 quiet.
--
-- The fix under test: OT6_FONTDIRTY relocated to $57B9 (write-watcher
-- verified spare byte), and the legit dialogue-close re-lay staged into six
-- ~128-byte slices, each gated on the live V counter.
--
-- Invariants, asserted across every frame from menu-open through the Fire
-- Beam banner and resolution:
--   1. the battle NMI's OT6 tail work and the following INIDISP write stay
--      inside vblank (scanline 225..261) on EVERY frame;
--   2. a real banner event happened in the window ($57D5 went nonzero --
--      the positive control that we exercised the vanilla writer);
--   3. OT6_FONTDIRTY ($57B9) stayed 0 throughout (no spurious re-lay);
--   4. right after the banner the under-monster HUD cells are still
--      painted in VRAM (shadow line vs tilemap word compare).
--
-- Instrument points (bank C1 exec callbacks; C1 offsets shift only if code
-- is inserted before the battle NMI in btlgfx_main.asm -- the smoke test
-- below fails loudly if the hooks go quiet):
--   $C10BA7 BattleNMI entry   $C10C17 flush jsl   $C10C1B flush return
--   $C10CA4 first instruction after sta hINIDISP

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local vr = emu.memType.snesVideoRam
local FONTDIRTY = 0x57B9
local SHADOW = 0x5762           -- 6 lines x 14 bytes: cur,prev,5 cells

local armed = false
local rec = {}                  -- per-frame {f, nmi, fs, fe, id, fd}
local cur = nil
local maxFd = 0
local sawBanner = false         -- latched at NMI entry: the pre-relocation
                                -- flush cleared $57D5 every NMI, so a
                                -- main-thread poll can never see it

local function sl() return emu.getState()["ppu.scanline"] end

emu.addMemoryCallback(function()
  if not armed then return end
  cur = { f = H.frame, nmi = sl() }
  local fd = H.readByte(FONTDIRTY)
  if fd > maxFd then maxFd = fd end
  cur.fd = fd
  if H.readByte(0x57D5) ~= 0 then sawBanner = true end
  rec[#rec + 1] = cur
end, emu.callbackType.exec, 0xC10BA7, 0xC10BA7)

emu.addMemoryCallback(function()
  if armed and cur then cur.fs = sl() end
end, emu.callbackType.exec, 0xC10C17, 0xC10C17)

emu.addMemoryCallback(function()
  if armed and cur then cur.fe = sl() end
end, emu.callbackType.exec, 0xC10C1B, 0xC10C1B)

emu.addMemoryCallback(function()
  if armed and cur then cur.id = sl() end
end, emu.callbackType.exec, 0xC10CA4, 0xC10CA4)

-- VRAM word at a bg3 tilemap word address (byte access, lo|hi)
local function vramWord(wordAddr)
  return emu.read(wordAddr * 2, vr) | (emu.read(wordAddr * 2 + 1, vr) << 8)
end

H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle to become active (screen rendering)", 30),
  H.waitFrames(240),

  -- arm the instrument, and zero vanilla's name-scratch byte so "a banner
  -- happened" is detectable (vanilla always writes it before reading)
  H.call(function()
    H.writeByte(0x57D5, 0)
    armed = true
  end),

  -- MagiTek Fire Beam: command, ability, confirm target
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.pressButtons({ "a" }, 6),

  -- a named banner must appear (Fire Beam's own, or an enemy special's)
  H.waitUntil(function() return sawBanner end, 600,
    "banner name-scratch write ($57D5)", 1),
  H.call(function() H.screenshot("banner_live") end),
  -- ride through the banner, effect art, damage, and recovery
  H.waitFrames(200),
  H.call(function() armed = false end),

  H.call(function()
    -- 0. the instrument actually ran
    H.assertEq(#rec >= 250, true, "instrument recorded >=250 frames (got " ..
      #rec .. ")")

    -- 1. every frame's tail work inside vblank (no wrap into scanline 0+)
    local bad = 0
    local worstFe, worstId = 0, 0
    for _, r in ipairs(rec) do
      for _, k in ipairs({ "nmi", "fs", "fe", "id" }) do
        local v = r[k]
        if v == nil or v < 225 or v > 261 then
          bad = bad + 1
          if bad <= 5 then
            H.log(string.format("VIOLATION f=%d %s=%s (nmi=%s fs=%s fe=%s id=%s fd=%02X)",
              r.f, k, tostring(v), tostring(r.nmi), tostring(r.fs),
              tostring(r.fe), tostring(r.id), r.fd or 0))
          end
        end
      end
      if r.fe and r.fe > worstFe then worstFe = r.fe end
      if r.id and r.id > worstId then worstId = r.id end
    end
    H.log(string.format("frames=%d worst flush-end=%d worst post-inidisp=%d (vblank 225..261)",
      #rec, worstFe, worstId))
    H.assertEq(bad, 0, "every NMI tail write inside vblank")

    -- 2. the window really contained a banner (positive control)
    H.assertEq(sawBanner, true,
      "vanilla banner scratch $57D5 written during the window")

    -- 3. no spurious font re-lay (no dialogue ran in this fight)
    H.assertEq(maxFd, 0, "OT6_FONTDIRTY stayed clear through the banners")

    -- 4. HUD self-heal: every enabled shadow line's first cell is live in
    --    the bg3 tilemap right after the banner sequence
    local checked = 0
    for line = 0, 5 do
      local base = SHADOW + line * 14
      local addr = H.readWord(base)
      if addr ~= 0 then
        local want = H.readWord(base + 4)
        local got = vramWord(addr)
        H.assertEq(got, want,
          string.format("hud line %d cell 0 present at vram $%04X", line, addr))
        checked = checked + 1
      end
    end
    H.assertEq(checked >= 1, true, "at least one hud line enabled (got " ..
      checked .. ")")
    H.assertEq(H.screenLooksAlive(), true, "screen alive after banner")
  end),
})
