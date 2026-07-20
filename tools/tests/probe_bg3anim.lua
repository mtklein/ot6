-- probe_bg3anim.lua -- measurement instrument: what happens to the bg3
-- battlefield MAP region ($5400-$57FF words) and the OT6-borrowed font tiles
-- during a BG3-scripted attack animation (Fire Beam, attack $83: sprite
-- $14D / bg1 $14B / bg3 $14C in AttackAnimProp) in a plain fight with no
-- dialogue.
--
-- Per frame through the cast it logs:
--   $896F ($2105 battlefield: bg3 tile size bit $40), $898D ($212C main
--   screen), $800E (bg3 scroll hdma type), $62C9 (anim tile quadrant),
--   $7B21 (bg3 anim tile upload pending), bg3 scroll $4AF5/$4AF7,
--   OT6_SCRIPTBUSY $57BF, dialog latch $64D5,
--   a census of the $400 map words: fill($01EE) / hud(attr $21 + claimed
--   glyph) / zero / other (+ first three "other" samples with addresses),
--   and a 16-byte canary compare of the fire-icon font cell ($EB) vs ROM.
-- Screenshots every 8 frames through the effect window.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/first_battle.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom

-- OT6-claimed glyph chars (fieldGlyphCount's set, battle_flyin technique)
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
  local icons = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,
                         0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  H.assertEq(icons ~= nil, true, "Ot6FontIcons found in rom")
  local set = { [0xbf] = true }
  for _, c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do set[c] = true end
  for k = 1, 16 do set[emu.read(bg - 17 + k, ROM)] = true end
  return set, icons
end
local iconsBase = nil

local function fireIconIntact()
  -- font cell $EB (fire icon) vs its ROM source, first mismatch offset or -1
  for i = 0, 15 do
    if emu.read(0xB000 + 0xEB*16 + i, VR) ~= emu.read(iconsBase + i, ROM) then
      return i
    end
  end
  return -1
end

local function census()
  local fill, hud, zero, other, oth = 0, 0, 0, 0, {}
  for w = 0, 0x3ff do
    local lo = emu.read((0x5400 + w) * 2, VR)
    local hi = emu.read((0x5400 + w) * 2 + 1, VR)
    local word = hi * 256 + lo
    if word == 0x01ee then fill = fill + 1
    elseif hi == 0x21 and claimed[lo] then hud = hud + 1
    elseif word == 0x0000 then zero = zero + 1
    else
      other = other + 1
      if #oth < 3 then oth[#oth+1] = string.format("%04x@%04x", word, 0x5400 + w) end
    end
  end
  return fill, hud, zero, other, table.concat(oth, ",")
end

local function shadowCurs()
  local t = {}
  for s = 0, 5 do t[#t+1] = string.format("%04x", H.readWord(H.shadowLine(s))) end
  return table.concat(t, " ")
end

local frameN = 0
local function report(tag)
  local fill, hud, zero, other, oth = census()
  H.log(string.format(
    "[bg3] f=%d %s 2105=%02x main=%02x scrT=%02x quad=%02x up=%02x " ..
    "scroll=%04x,%04x busy=%02x dlg=%02x canary=%d " ..
    "map[fill=%d hud=%d zero=%d other=%d %s] cur[%s]",
    frameN, tag,
    H.readByte(0x896f), H.readByte(0x898d), H.readByte(0x800e),
    H.readByte(0x62c9), H.readByte(0x7b21),
    H.readWord(0x4af5), H.readWord(0x4af7),
    H.readByte(0x57bf), H.readByte(0x64d5),
    fireIconIntact(),
    fill, hud, zero, other, oth, shadowCurs()))
end

local shotN = 0
local function maybeShot(prefix)
  local ok, png = pcall(emu.takeScreenshot)
  if ok and type(png) == "string" and #png > 0 then
    H.emitBlob(string.format("%s_%03d.png", prefix, frameN), png)
    shotN = shotN + 1
  end
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(0x7bca) ~= 0 end, 1200, "battle menu open", 10),
  H.call(function()
    claimed, iconsBase = claimedCharSet()
    report("pre")
    maybeShot("bg3pre")
  end),
  -- A: MagiTek command -> submenu
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  -- A: Fire Beam
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.call(function() report("target") end),
  -- A: confirm target; then record every frame until the script goes quiet
  H.pressButtons({ "a" }, 6),
  -- wait for the animation script to begin (SCRIPTBUSY rises)
  H.waitUntil(function() return H.readByte(0x57bf) ~= 0 end, 600, "anim script begins", 1),
  (function()
    local quiet = 0
    return H.driveUntil(function()
      quiet = (H.readByte(0x57bf) == 0) and quiet + 1 or 0
      return quiet >= 90
    end, 1800, {
      H.call(function()
        frameN = frameN + 1
        report("anim")
        if frameN % 8 == 0 then maybeShot("bg3fx") end
      end),
      H.waitFrames(1),
    }, "anim script over + 90 quiet frames")
  end)(),
  H.call(function()
    report("post")
    maybeShot("bg3post")
    H.log("[bg3] done shots=" .. shotN)
  end),
})
