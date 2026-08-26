-- @suite
-- battle_banner.lua -- temporal test: attack-name banners must not tear.
--
--   tools/tests/run.sh tools/tests/battle_banner.lua
--
-- Single-frame asserts cannot see flicker, so the invariant is checked on
-- every frame of the sequence. Vanilla builds its attack/special/esper
-- name-scratch string at $7E57D5 (GfxCmd_01/GfxCmd_11 and the swdtech and
-- esper loaders all write byte 0 nonzero). OT6_FONTDIRTY lives at $57B9,
-- and the dialogue-close re-lay is staged into six ~128-byte slices, each
-- gated on the live V counter.
--
-- Invariants, asserted across every frame from menu-open through the Fire
-- Beam banner and resolution:
--   1. the battle NMI's OT6 tail work and the following INIDISP write stay
--      inside vblank (scanline 225..261) on every frame;
--   2. a banner event happened in the window, seen as $57D5 changing from its
--      armed baseline. This is the positive control that the vanilla writer
--      ran;
--   3. OT6_FONTDIRTY ($57B9) stayed 0 throughout, so no re-lay was triggered;
--   4. right after the banner the under-monster HUD cells are still
--      painted in VRAM (shadow line vs tilemap word compare).
--
-- Instrument points (bank C1 exec callbacks; C1 offsets shift only if code
-- is inserted before the battle NMI in btlgfx_main.asm, and the smoke test
-- below fails if the hooks go quiet):
--   $C10BA7 BattleNMI entry   $C10C17 flush jsl   $C10C1B flush return
--   $C10CA4 first instruction after sta hINIDISP

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local vr = emu.memType.snesVideoRam
local FONTDIRTY = 0x57B9
local SHADOW = H.SHADOW         -- 6 lines x 14 bytes: cur,prev,5 cells

local armed = false
local rec = {}                  -- per-frame {f, nmi, fs, fe, id, fd}
local cur = nil
local maxFd = 0
local sawBanner = false         -- latched at NMI entry
local base57D5 = nil            -- $57D5 as the window opened: "banner
                                -- happened" is a change from this baseline

local function sl() return emu.getState()["ppu.scanline"] end

emu.addMemoryCallback(function()
  if not armed then return end
  cur = { f = H.frame, nmi = sl() }
  local fd = H.readByte(FONTDIRTY)
  if fd > maxFd then maxFd = fd end
  cur.fd = fd
  if H.readByte(0x57D5) ~= base57D5 then sawBanner = true end
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
  }, "battle load from entry point"),
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle to become active (screen rendering)", 30),
  H.waitFrames(240),

  -- arm the instrument: latch the name-scratch byte as it is, and detect
  -- the banner as a change from that baseline in the NMI watcher.
  H.call(function()
    base57D5 = H.readByte(0x57D5)
    H.log(string.format("armed: $57D5 baseline %02X", base57D5))
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

  -- the 16x16 anim-mode veil (battle_hudanim16) hides the hud while an
  -- animation holds battlefield bg3 in 16x16 tiles ($896F bit $40).  An
  -- enemy action can still be mid-effect after the fixed ride above, and
  -- its window would read $01EE where the self-heal check wants cells, so
  -- settle to 8x8 with the flush's repaint landed first.
  H.waitUntil(function()
    return H.readByte(0x896f) % 128 < 64 and H.fieldHudPresent()
  end, 600, "bg3 back to 8x8, hud repainted", 5),

  H.call(function()
    -- 0. the instrument ran
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

    -- 2. the window contained a banner (positive control)
    H.assertEq(sawBanner, true,
      "vanilla banner scratch $57D5 written during the window")

    -- 3. no font re-lay was triggered (no dialogue ran in this fight)
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
