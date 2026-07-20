-- battle_hudtrail: cells the under-enemy hud ABANDONS must hold vanilla's
-- $01EE fill -- never a priority-set word -- so an animation's bg3-16x16
-- window can't render them.
--
-- THE BUG (the owner's v0.3 sighting, surviving all three prior hud fixes:
-- fly-in gate, dialogue font-clobber veil, 16x16 anim veil): "white flash
-- in combat ... at the START of the fight, before anyone has made any
-- attacks ... as the enemies are appearing ... too quick to get a
-- screenshot."  Reliable on the Lete River forced fight (event battle
-- group 8), BOTH die rolls: formation 35 (Pterodon x2) and formation 37
-- (Nautiloid+Exocite+Pterodon).
--
-- MECHANISM (probe_lete_entrance, frame-exact on the fixed-main image):
-- this entrance SLIDES the shown monsters in.  The hud anchors track the
-- slide, so every live line's cur address walks sideways across the field
-- map, and each step one-shot-blanks the abandoned cells.  The blank word
-- was $21FF: priority-SET char $1FF -- invisible in 8x8 (a blank font
-- cell), but the same slide holds $896F=$59 (bg3 16x16 + priority), and a
-- 16x16 map cell renders char n plus n+1/n+$10/n+$11: $1FF pulls tiles
-- $200/$20F/$210, past the font page into animation gfx, at top priority.
-- 63-92 abandoned cells accumulate over the slide (map dumps in the probe
-- log) and render as a full-width band of white junk over the entering
-- monsters for the effect's last ~15 frames -- one quarter second, gone
-- when the effect's own cleanup refills the buffer.  The anim veil
-- (battle_hudanim16's fix) covers only LIVE cells; abandoned cells were
-- nobody's.
--
-- THE FIX: the flush's one-shot blank writes $01EE -- the word vanilla
-- holds in every field cell it did not draw, priority-clear, safe in both
-- tile modes.  An abandoned cell is word-identical to one never touched.
--
-- THE GATE, frontier-gated on rapids_start.mss: ride into the forced
-- fight (no menu input -- the flash is before any turn), track every cell
-- a hud line abandons, and assert on every mid-battle bg3-16x16 frame
-- that no abandoned cell holds a priority-set word ($21FF or otherwise)
-- -- each must read exactly $01EE or have been reclaimed/rewritten by
-- vanilla.  Rides the cur-cell invariant along (no painted glyph at cur
-- while 16x16 -- battle_hudanim16's clause, here on the entrance).
-- Positive controls: the slide abandoned >= 20 cells inside the 16x16
-- window, >= 10 veiled entry frames, >= 20 16x16 frames sampled, the hud
-- paints after settle, glyphCanary.  Pre-fix: 63+ violations in the first
-- slide.  Post-fix: zero.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/rapids_start.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom
local CH_MAX = 0x056F

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- OT6-claimed glyph chars from rom (battle_flyin's technique)
local claimed = nil
local function claimedCharSet()
  local function findSig(sig)
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base + i - 1, ROM) ~= sig[i] then hit = false break end
      end
      if hit then return base end
    end
    return nil
  end
  local bg = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                      0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(bg ~= nil, true, "OT6 bg glyph data found in rom")
  local set = { [0xbf] = true }
  for _, c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do set[c] = true end
  for k = 1, 16 do set[emu.read(bg - 17 + k, ROM)] = true end
  return set
end

-- ---------------------------------------------------------- the watcher --
local prevSpans, abandoned, nAbandoned = {}, {}, 0
local frames16, veiled16, veilFrames = 0, 0, 0
local trailViol, curViol = 0, 0
local abandonedIn16 = 0
local shownEdge = false
local violShots = 0
local function watchFrame()
  -- track abandoned cells (a line moved or disabled since last frame)
  local live = {}
  for s = 0, 5 do
    local cur = H.readWord(H.shadowLine(s))
    if cur ~= 0 then
      for k = 0, 4 do live[cur + k] = true end
    end
    local old = prevSpans[s]
    if old and old ~= 0 and old ~= cur and nAbandoned < 3000 then
      for k = 0, 4 do
        if not abandoned[old + k] then
          abandoned[old + k] = true
          nAbandoned = nAbandoned + 1
        end
      end
    end
    prevSpans[s] = cur
  end
  for a in pairs(live) do abandoned[a] = nil end

  if H.readByte(0x57be) ~= 0 then veilFrames = veilFrames + 1 end
  if H.readByte(0x201e) ~= 0 then shownEdge = true end

  local m2105 = H.readByte(0x896f)
  if (m2105 & 0x40) == 0 then return end
  frames16 = frames16 + 1

  -- THE INVARIANT: no abandoned cell priority-set while bg3 is 16x16
  local nAb = 0
  for a in pairs(abandoned) do
    nAb = nAb + 1
    local lo = emu.read(a * 2, VR)
    local hi = emu.read(a * 2 + 1, VR)
    if (hi & 0x20) ~= 0 then
      trailViol = trailViol + 1
      if trailViol <= 6 then
        H.log(string.format(
          "VIOLATION: abandoned cell %04x holds priority-set %02x%02x on a "
          .. "16x16 frame (2105=%02x)", a, hi, lo, m2105))
      end
      if violShots < 3 then
        violShots = violShots + 1
        H.screenshot(string.format("hudtrail_viol%d", violShots))
      end
    end
  end
  if nAb > abandonedIn16 then abandonedIn16 = nAb end

  -- ride-along: battle_hudanim16's cur-cell clause on the entrance
  for s = 0, 5 do
    local cur = H.readWord(H.shadowLine(s))
    if cur ~= 0 then
      local veiled = true
      for k = 0, 4 do
        local lo = emu.read((cur + k) * 2, VR)
        local hi = emu.read((cur + k) * 2 + 1, VR)
        if hi == 0x21 and claimed[lo] then curViol = curViol + 1 end
        if not (hi == 0x01 and lo == 0xee) then veiled = false end
      end
      if veiled then veiled16 = veiled16 + 1 end
    end
  end
end

-- ------------------------------------------------------------ the ride --
local function rideStep()
  local phase, dlgN = 0, 0
  return H.driveUntil(function()
    return H.battleLoadStarted()
  end, 25000, {
    H.call(function()
      phase = (phase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if H.dialogWaiting() and H.readByte(CH_MAX) >= 2 then
        error("unexpected multiple choice on the river", 0)
      end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}) return end
      H.setPad({})
    end),
  }, "the forced river fight loads")
end

H.run({ maxFrames = 45000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(map(), 113, "rapids_start boots on map 113, the Lete River")
    claimed = claimedCharSet()
  end),
  rideStep(),
  H.call(function()
    H.setPad({})
    H.log("[hudtrail] battle loading; watching the entrance")
  end),

  -- the whole entrance plus the settle, no input: the flash is before
  -- any player turn
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      return n >= 700
    end, 760, {
      H.call(function()
        H.setPad({})
        watchFrame()
      end),
      H.waitFrames(1),
    }, "entrance watched")
  end)(),

  H.call(function()
    H.log(string.format(
      "[hudtrail] frames16=%d veiled16=%d veilFrames=%d abandonedIn16=%d "
      .. "trailViol=%d curViol=%d", frames16, veiled16, veilFrames,
      abandonedIn16, trailViol, curViol))
    -- the invariant first, so a pre-fix image fails ON the bug (805
    -- violations measured on it), not on a positive control
    H.assertEq(trailViol, 0,
      "no abandoned cell held a priority-set word on a 16x16 frame ("
      .. trailViol .. " violations) -- the white entrance band")
    H.assertEq(curViol, 0,
      "no live hud cell held a painted glyph on a 16x16 frame ("
      .. curViol .. " violations)")
    -- positive controls, thresholds from measurement: the entrance slide
    -- holds bg3-16x16 for 18 watch frames and abandons 84 cells inside it
    H.assertEq(shownEdge, true, "monsters were shown ($201e) -- the "
      .. "entrance actually ran")
    H.assertEq(veilFrames >= 10, true,
      "entry veil observed >= 10 frames (got " .. veilFrames .. ")")
    H.assertEq(frames16 >= 12, true,
      "sampled >= 12 bg3-16x16 frames (got " .. frames16 .. ") -- else the "
      .. "invariant never ran")
    H.assertEq(abandonedIn16 >= 20, true,
      "the slide abandoned >= 20 cells inside the 16x16 window (got "
      .. abandonedIn16 .. ") -- the trail actually existed to check")
    H.assertEq(veiled16 >= 1, true,
      "at least one live line read veiled inside the window")
  end),

  -- release edge: the hud must actually paint once the effect ends
  H.waitUntil(function()
    return H.readByte(0x896f) % 128 < 64 and H.readByte(0x57be) == 0
       and H.fieldHudPresent()
  end, 900, "hud painted after the entrance", 5),
  H.call(function()
    H.glyphCanary()
    H.screenshot("hudtrail_settled")
  end),
})
