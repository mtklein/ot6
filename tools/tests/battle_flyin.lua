-- battle_flyin: the under-enemy hud must not paint a monster that has not
-- entered yet.
--
-- THE BUG (v0.3-rc1 playtest, Figaro<->South Figaro cave): "a bunch of
-- characters overdrawn on the screen in white text ... when there are a bunch
-- of enemies".  At battle entry a monster is flagged present ($3AA8) from
-- init, but its sprite is not drawn until its fly-in animation runs; the
-- "monsters shown" mask $201E (notes/battle-ram.txt:422; the sprite drawers
-- gate on it, btlgfx_main.asm:5639/:5772) stays 0 for that whole fade-in
-- window.  Ot6BgHudLine gated only on $3AA8, so it painted each entering
-- monster's shield/'?' cells into empty space -- a scatter of white glyphs on
-- the still-dark battlefield, worst with the cave's 3-5 fly-in trash.  The
-- entry ANIMATION was already veiled (Ot6EntryExitVeil, battle_whelkwipe's
-- gate); the gap this closes is the window BEFORE it.  Fix: gate the hud on
-- $201E, the same mask the sprites use.
--
-- The coverage gap was "nobody ever fought fly-in enemies under instruments":
-- the suite's other fights either enter behind the veil (the whelk) or do not
-- fly in.  kolts_cave's map-96 pool is 93.75% Cirpius x3 (gen_kolts_cave),
-- three birds that fly in together -- so the natural encounter here spends
-- ~45 frames with every monster present-but-not-shown, exactly the window the
-- bug lived in.  Frontier-gated on kolts_cave.mss (make frontier), the
-- battle_vargas pattern.
--
-- Assert, every frame of that window: any present-but-unshown monster's hud
-- line is DISABLED (shadow cur == 0), and while ALL present monsters are
-- unshown the bg3 field map holds ZERO OT6 glyph chars (cell-level, the
-- battle_whelkwipe technique).  Positive controls so a quiet pass cannot hide
-- a real regression: the window must actually be sampled (>= 12 frames with a
-- present-but-unshown monster), AND once the birds enter the hud must come
-- back (fieldHudPresent + glyphCanary).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/kolts_cave.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom
local DANGER = 0x1f6e

local function map() return H.mapId() & 0x1ff end

-- OT6-claimed field-map glyph chars, read from rom (battle_whelkwipe's scan):
-- 8 element icons + 16 hud glyphs + '?' -- the whole set the hud may draw.
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
local claimed = nil

local function fieldMapBaseWord()
  local reg = H.readByte(0x897b)
  return (reg - (reg % 4)) * 256
end

-- count OT6 glyph cells anywhere in the bg3 field map (attr text-palette bit)
local function fieldGlyphCount()
  local baseW = fieldMapBaseWord()
  local n = 0
  for w = 0, 0x3ff do
    local lo = emu.read((baseW + w) * 2, VR)
    local hi = emu.read((baseW + w) * 2 + 1, VR)
    if (hi & 0x01) == 1 and claimed[lo] then n = n + 1 end
  end
  return n
end

-- present ($3AA8 bit0 per slot, 2-byte stride) vs shown ($201E bitmask)
local function presentMask()
  local m = 0
  for s = 0, 5 do if H.readByte(0x3aa8 + s * 2) % 2 == 1 then m = m | (1 << s) end end
  return m
end
local function shownMask() return H.readByte(0x201e) end

local gateFrames, pureFrames = 0, 0

-- one entry-window frame: hold the invariant
local function checkEntryFrame()
  local present = presentMask()
  local shown = shownMask()
  local unshown = present & (~shown & 0x3f)
  if unshown == 0 then return end
  gateFrames = gateFrames + 1
  -- every present-but-unshown monster's hud line must be OFF
  for s = 0, 5 do
    if (unshown & (1 << s)) ~= 0 then
      local cur = H.readWord(H.shadowLine(s))
      H.assertEq(cur, 0, string.format(
        "slot %d present but not shown ($201E bit clear): hud line must be "
        .. "disabled, cur=%04x", s, cur))
    end
  end
  -- while the WHOLE field is still entering, the bg3 map must be glyph-free
  if (present & shown & 0x3f) == 0 then
    pureFrames = pureFrames + 1
    local g = fieldGlyphCount()
    H.assertEq(g, 0, string.format(
      "battlefield still entering (present=%02x shown=%02x) but %d OT6 glyph "
      .. "cell(s) painted in the bg3 field map", present, shown, g))
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until an encounter loads (gen_kolts_cave)
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        H.writeWord(DANGER, 0xff00)
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),

  -- battle is loading: catch the fly-in window from the very first live frame
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(function()
    claimed = claimedCharSet()
    local fw = H.formationWords()
    H.log(string.format("[flyin] formation %04X %04X %04X %04X %04X %04X present=%02x",
      fw[1], fw[2], fw[3], fw[4], fw[5], fw[6], presentMask()))
  end),

  -- Phase A: hold the invariant every frame until every present monster is
  -- shown (the fly-in has completed for all of them).
  H.driveUntil(function()
    local p = presentMask()
    return p ~= 0 and (p & (~shownMask() & 0x3f)) == 0
  end, 600, {
    H.call(checkEntryFrame),
  }, "all present monsters shown"),

  -- Phase C: let the entry animation + its veil finish, then the hud must be
  -- back for real -- the positive control that this isn't a vacuous pass.
  H.waitUntil(function() return H.readByte(0x57be) == 0 end, 600, "entry veil clears", 5),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("[flyin] gateFrames=%d pureFrames=%d", gateFrames, pureFrames))
    H.assertEq(gateFrames >= 12, true,
      "sampled the fly-in window (present-but-unshown) -- else the invariant "
      .. "above never ran (gateFrames=" .. gateFrames .. ")")
    H.assertEq(pureFrames >= 8, true,
      "sampled the fully-entering window -- the cell-level scan actually ran "
      .. "(pureFrames=" .. pureFrames .. ")")
    H.assertEq(H.fieldHudPresent(), true,
      "hud repaints once the monsters have entered")
    H.glyphCanary()
    H.screenshot("flyin_settled")
  end),
})
