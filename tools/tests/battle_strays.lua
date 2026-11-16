-- @suite savestate=gau_joined
-- battle_strays.lua -- nothing OT6 paints in battle lands where it does not
-- belong (#544).
--
-- The owner, v0.45: "stray black squares in combat starting in the veldt?
-- two, one top right, second bottom near center".  The cause was the old
-- one-cell pip painter: OT6_PIPPREV and OT6_PIPCUR ($57ce/$57cc) were never
-- cleared at battle entry, so the first nmi of a battle "blanked" whatever
-- word the field or world map had left there ($21ff into VRAM $5fbd and its
-- "band twin" $60bd, BG2's landscape map, row 5 col 29: an 8x8 hole to the
-- black backdrop at px 232,39), and painted into the menu map besides
-- (diagnosis: build/attempts/wt/v046-break-feel/544/).  It needed a junk
-- PREV nonzero and unlike CUR, which the Veldt's world map left behind.
-- #540 replaced that painter: each name row's cell is written at a fixed
-- address from a word staged this battle (OT6_PIPROWW, gated on
-- OT6_PIPLIVE), and nothing reads PIPCUR/PIPPREV any more.
--
-- Played: from gau_joined (SABIN, CYAN, GAU on the Veldt), walk the world
-- map into a random battle, let it settle, then act a little.  Asserted:
--   1. every VRAM word the HUD's nmi code writes (Ot6BgHudFlush_ext and the
--      glyph uploads it calls) lies in BG3's font and field map
--      ($5000-$5fff) or the menu maps ($7800-$7fff): none in BG1's or BG2's
--      maps, where the landscape and the animations live;
--   2. the battlefield shows no stray (the #544 detector: HUD blanks in
--      BG1/BG2, holes in BG2's landscape, BG3 cells no HUD line owns, black
--      sprites), once settled and once after acting.
-- Old-ROM red: v0.45's ROM writes VRAM $60bd and shows the hole at px 232,39.
-- Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")
local Det = (function()
-- stray_detector.lua (#544): after a battle's HUD has settled, account for every cell and sprite on the
-- battlefield and report what nothing owns.  Read-only.  Spliced into a harness script (it expects `H`
-- and `emu`); Det.arm() once, wait >= 2 frames, then Det.scan(tag) -> number of strays (lines logged
-- "[stray] ...").  Battle shape it relies on (v0.45, verified in #544):
--   battlefield region = scanlines 0..~150; PPU regs for it come from HDMA at scanline 0..~60:
--   BG1SC $0C (animation layer), BG2SC $61 (landscape, 64x32), BG3SC $54 (field map, HUD lines),
--   BG3 chr $5000 words; menu region from scanline 151 (not scanned here, only the pip pseudo-line
--   variables that write into it).
local Det = {}
local armed, regs = false, {}
local V, C, S = emu.memType.snesVideoRam, emu.memType.snesCgRam, emu.memType.snesSpriteRam

function Det.arm()
  regs = {}
  if not Det.cb then
    local function cb(addr, val)
      if not armed then return end
      local sl = emu.getState()["ppu.scanline"]
      if sl <= 60 or addr == 0x212C then
        local r = regs[addr]
        if not r then r = {}; regs[addr] = r end
        r[#r + 1] = val
        r.last = val
      end
    end
    emu.addMemoryCallback(cb, emu.callbackType.write, 0x2105, 0x2114)
    Det.cb = true
  end
  armed = true
end

local function reg(a) return regs[a] and regs[a].last or 0 end
local function scroll(a)   -- last two writes: lo then hi
  local r = regs[a]
  if not r or #r < 2 then return 0 end
  return ((r[#r] & 3) << 8) | r[#r - 1]
end

local function word(a) return emu.read(a, V) | (emu.read(a + 1, V) << 8) end
local function tileBlank(chrWords, bpp, t)
  local b = chrWords * 2 + t * bpp * 8
  for i = 0, bpp * 8 - 1 do if emu.read(b + i, V) ~= 0 then return false end end
  return true
end

-- cell word at layer pixel (px,py), per the layer's SC register
local function cell(sc, px, py)
  local base = (sc & 0xFC) << 8
  local sx, sy = sc & 1, (sc >> 1) & 1
  local w = sx == 1 and 512 or 256
  local h = sy == 1 and 512 or 256
  px, py = px % w, py % h
  local scr = 0
  if px >= 256 then scr = scr + 1; px = px - 256 end
  if py >= 256 then scr = scr + (sx == 1 and 2 or 1); py = py - 256 end
  local a = base + scr * 0x400 + (py >> 3) * 32 + (px >> 3)
  return word(a * 2), a
end

function Det.scan(tag)
  armed = false
  local out = {}
  local function stray(kind, fmt, ...) out[#out + 1] = string.format("[stray] %s %s " .. fmt, tag, kind, ...) end
  local sc1, sc2, sc3 = reg(0x2107), reg(0x2108), reg(0x2109)
  local chr12, chr3 = reg(0x210B), reg(0x210C)
  local chr1, chr2, chr3w = (chr12 & 0xF) << 12, (chr12 >> 4) << 12, (chr3 & 0xF) << 12
  local mode = reg(0x2105)
  local tm = reg(0x212C)
  if tm == 0 then tm = 0x17 end
  local sl = { { sc1, chr1, 4, scroll(0x210D), scroll(0x210E) }, { sc2, chr2, 4, scroll(0x210F), scroll(0x2110) },
               { sc3, chr3w, 2, scroll(0x2111), scroll(0x2112) } }
  -- a battle dialog (w7e64d5) or an animation script (OT6_SCRIPTBUSY $57bf) owns BG3 while it runs
  local dialog = H.readByte(0x7e64d5) ~= 0 or H.readByte(0x7e57bf) ~= 0
  Det.info = string.format("mode=%02X TM=%02X SC=%02X/%02X/%02X chr=%02X/%02X scroll1=%d,%d scroll2=%d,%d scroll3=%d,%d", mode, tm, sc1, sc2, sc3,
    chr12, chr3, sl[1][4], sl[1][5], sl[2][4], sl[2][5], sl[3][4], sl[3][5])
  -- 1. HUD words that belong only in the BG3 field map, found anywhere in the BG1/BG2 maps
  for L = 1, 2 do
    local sc = sl[L][1]
    local nscr = ((sc & 1) + 1) * (((sc >> 1) & 1) + 1)
    for scr = 0, nscr - 1 do
      for i = 0, 1023 do
        local a = (((sc & 0xFC) << 8) + scr * 0x400 + i)
        local w = word(a * 2)
        if (w == 0x21FF or w == 0x01EE) then
          stray("HUDWORD", "BG%d map word %04X at vram %04X (screen %d row %d col %d) -- a HUD blank/fill in a layer it does not own",
            L, w, a, scr, i >> 5, i & 31)
        end
      end
    end
  end
  -- 2. transparent holes in the landscape (BG2) over the battlefield: the backdrop shows through
  do
    local sc, chr, bpp, hs, vs = table.unpack(sl[2])
    if (tm & 2) ~= 0 then
      for cy = 0, 18 do
        for cx = 0, 31 do
          local w, a = cell(sc, cx * 8 + hs, cy * 8 + vs + 1)
          if tileBlank(chr, bpp, w & 0x3FF) then
            stray("BG2HOLE", "BG2 cell col %d row %d (screen px %d,%d) word %04X tile %03X pal %d vram %04X is all-transparent",
              cx, cy, cx * 8, cy * 8 - 1, w, w & 0x3FF, (w >> 10) & 7, a)
          end
        end
      end
    end
  end
  -- 3. BG3 field map: every non-blank cell must belong to a live HUD line (anchor-1 .. anchor+4)
  do
    local sc, chr, bpp, hs, vs = table.unpack(sl[3])
    local own = {}
    for s = 0, 5 do
      local cur = H.readWord(0x7eecf1 + 14 * s)
      if cur ~= 0 then for k = -1, 4 do own[cur + k] = true end end
    end
    for cy = 0, 18 do
      for cx = 0, 31 do
        local w, a = cell(sc, cx * 8 + hs, cy * 8 + vs + 1)
        local t = w & 0x3FF
        if not tileBlank(chr, bpp, t) and not own[a] and not dialog then
          stray("BG3CELL", "BG3 cell col %d row %d (screen px %d,%d) word %04X tile %03X pal %d vram %04X owned by no HUD line",
            cx, cy, cx * 8, cy * 8 - 1, w, t, (w >> 10) & 7, a)
        end
      end
    end
  end
  -- 4. sprites: count on-screen opaque ones; flag solid-black ones
  do
    local st = emu.getState()
    local base, gap, omode = st["ppu.oamBaseAddress"], st["ppu.oamAddressOffset"], st["ppu.oamMode"]
    local small = ({ [0] = 8, 8, 8, 16, 16, 32 })[omode] or 8
    local large = ({ [0] = 16, 32, 64, 32, 64, 64 })[omode] or 16
    local n = 0
    for i = 0, 127 do
      local x, y, t, a = emu.read(i * 4, S), emu.read(i * 4 + 1, S), emu.read(i * 4 + 2, S), emu.read(i * 4 + 3, S)
      local hi = emu.read(512 + (i >> 2), S)
      local sh = (i & 3) * 2
      local X = x + (((hi >> sh) & 1) * 256); if X >= 256 then X = X - 512 end
      local size = (((hi >> (sh + 1)) & 1) == 1) and large or small
      local Y = y + 1
      if Y >= 225 then Y = Y - 256 end
      if X > -size and X < 256 and Y > -size and Y < 224 then
        local tn = t + ((a & 1) * 256)
        local pal = (a >> 1) & 7
        local opaque, black = 0, 0
        for ty = 0, size // 8 - 1 do
          for tx = 0, size // 8 - 1 do
            local tt = (tn + ty * 16 + tx) & 0x1FF
            local words = base + (tt & 0xFF) * 16 + ((tt >= 256) and gap or 0)
            local b = words * 2
            for row = 0, 7 do
              local b0, b1 = emu.read(b + row * 2, V), emu.read(b + row * 2 + 1, V)
              local b2, b3 = emu.read(b + 16 + row * 2, V), emu.read(b + 17 + row * 2, V)
              for px = 0, 7 do
                local m = 7 - px
                local idx = ((b0 >> m) & 1) | (((b1 >> m) & 1) << 1) | (((b2 >> m) & 1) << 2) | (((b3 >> m) & 1) << 3)
                if idx ~= 0 then
                  opaque = opaque + 1
                  local ci = 128 + pal * 16 + idx
                  if (emu.read(ci * 2, C) | (emu.read(ci * 2 + 1, C) << 8)) == 0 then black = black + 1 end
                end
              end
            end
          end
        end
        if opaque > 0 then
          n = n + 1
          if black * 10 >= opaque * 9 and opaque >= 16 then
            stray("BLACKSPR", "OAM %d x=%d y=%d size=%d tile=%03X pal=%d: %d/%d opaque pixels are black", i, X, Y, size, tn, pal, black, opaque)
          end
        end
      end
    end
    Det.nsprites = n
  end
  -- 5. the pip pseudo-line's cursor words ($57cc/$57ce) must be 0 or inside the menu BG3 map ($7800-$7bff)
  for _, v in ipairs({ { "PIPCUR", 0x57cc }, { "PIPPREV", 0x57ce } }) do
    local w = H.readWord(0x7e0000 + v[2])
    if w ~= 0 and (w < 0x7800 or w >= 0x7c00) then
      stray("PIPVAR", "OT6_%s ($%04X) = %04X, outside the menu map $7800-$7bff (its blank/paint goes to a random VRAM word)", v[1], v[2], w)
    end
  end
  for _, l in ipairs(out) do H.log(l) end
  return #out
end

return Det

end)()

local ranges = {
  { H.sym("Ot6LoadBgGlyphsA"), H.sym("Ot6ScriptBegin_ext") },
  { H.sym("Ot6BgHudFlush_ext"), H.sym("Ot6Boost") },
}
local bad, writes, armed, phase = {}, 0, false, 0
local function ours(pc)
  for _, r in ipairs(ranges) do if pc >= r[1] and pc < r[2] then return true end end
  return false
end
local function okAddr(va) return (va >= 0x5000 and va < 0x6000) or (va >= 0x7800 and va < 0x8000) end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/gau_joined.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    for _, r in ipairs(ranges) do H.assertEq(r[1] < r[2], true, "the HUD's code ranges are in source order") end
    emu.addMemoryCallback(function(_, v)
      if not armed then return end
      local s = emu.getState()
      local pc = s["cpu.k"] * 65536 + s["cpu.pc"]
      if ours(pc) then
        writes = writes + 1
        local va = s["ppu.vramAddress"]
        if not okAddr(va) and #bad < 20 then
          bad[#bad + 1] = string.format("f%d vram %04X <- %02X (pc %06X)", H.frame, va, v, pc)
        end
      end
    end, emu.callbackType.write, 0x2118, 0x2119)
    armed = true
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      phase = (phase + 1) % 32
      if H.worldHasControl() then H.setPad(phase < 16 and { "down" } or { "up" }) else H.setPad({}) end
    end),
  }, "a random battle on the Veldt"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 4),
  H.waitFrames(380),
  H.call(function() Det.arm() end),
  H.waitFrames(3),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("[strays] formation %04X %04X %04X %04X %04X %04X; the HUD wrote %d VRAM bytes so far",
      w[1], w[2], w[3], w[4], w[5], w[6], writes))
    H.vars.settled = Det.scan("settled")
    H.screenshot("strays_settled")
  end),
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.pressButtons({ "a" }, 6), H.waitFrames(150),
  H.call(function() Det.arm() end),
  H.waitFrames(3),
  H.call(function()
    H.vars.acted = H.battleLoadStarted() and Det.scan("acted") or 0
    armed = false
    for _, b in ipairs(bad) do H.log("[strays] HUD write outside its maps: " .. b) end
    H.assertEq(writes > 0, true, "the HUD wrote VRAM (the watch saw it)")
    H.assertEq(#bad, 0, "every VRAM word the HUD's nmi code wrote lies in BG3's font and map or the menu maps (#544)")
    H.assertEq(H.vars.settled, 0, "no stray on the battlefield once settled (#544)")
    H.assertEq(H.vars.acted, 0, "and none after acting")
  end),
})
