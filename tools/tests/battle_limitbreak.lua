-- @suite slow
-- battle_limitbreak.lua -- Bahamut's signature, Limit Break (#550; docs/design/esper-rework.md "Limit Break";
-- ot6_esper.asm Ot6DmgCap, ot6_numeral.asm): the holder's damage caps at 42,069 instead of 9999, everyone else's
-- and every heal stay at 9999, and the damage numerals draw every value up to the cap, five digits looking like four.
--
-- Continue wor-ragnarok-v1 (the play's save outside Narshe; one member wears Ragnarok, so can cast Ultima: H below).
-- A snapshot on the world map; then one branch per case from it, each staging H's count on Bahamut (the live esper
-- page, SRAM $317C00: 500, the signature, or 499, one short) and walking into a random battle (the same one every
-- branch: the same snapshot, the same steps), where every present monster's HP and max HP are staged to 60,000 (so a
-- hit lands whole in HP rather than past it), and H casts Ultima at 2 BP through the real menu while the others
-- Defend.  Ultima from Ragnarok's list takes the boost's multiplier (battle_ragnarok): x4 at 2 BP, about 11,600 a
-- monster at this save's levels (at 3 BP this save's cast landed on nobody: build/attempts/wt/v049-limitbreak/);
-- the precondition, asserted per hit, is that the amount reaching the cap is past 9999.  The staging (the
-- count, the HP; the synthetic arms' bytes below) is declared in state_write_waivers.txt: a mechanism test, not play.
--   holder      count 500: each monster's total is the amount (or 42,069), its HP falls by exactly that, and its
--               numeral carries that value; four numerals take the single path, one on each thread, thread 3's too;
--               a five-digit numeral's four tiles are the condensed digits pixel for pixel (a reference rendering
--               here, from the strokes tools/numeral_font.py holds), in the same two sprites, B 16 pixels right of A
--   other       count 499: each total is 9999 and the HP falls by 9999; vanilla's glyphs; the busiest scanline at
--               the same moment carries exactly as many 8-pixel slivers as the holder's five-digit numerals
--   multi       count 500, and at the pass's display (_c262ef) each seated member gets a heal entry (2345, 9999, 88,
--               1): the multi-target path draws the monsters' five digits condensed and the heals green, vanilla's
--   fonts       count 500, the monsters' entries set at the display to 9999 and 12345 in turn (synthetic): both
--               fonts side by side
--   right       count 500, and at H's pass's display the monsters' entries dropped and the first seated member's set
--               to 12345 (synthetic): one five-digit single numeral on the party's side of the screen
--   broken      count 500; the first present monster is marked Broken (OT6_BROKEN_TICKS) and its amount set to
--               33,333 where Ot6BrokenDmg doubles it: 42,069 (x2 saturates and the cap takes it; vanilla's skip left
--               33,333)
--   weak        count 500; the first monster made weak to the pass's element and its amount set to 33,333 where
--               Ot6WeakDouble doubles it: 32,767 (the saturated double, then an unbroken body's half)
--   heal        count 500; the first monster's pass is turned to the heal side ($F2 bit 0 at CalcMaxDmg): a holder's
--               heal of ~12,000 caps at 9999
--   formula     count 500, H's level and Mag.Pwr staged at 99 and 255 (the character record, before the battle) and the
--               Ultima cast at 0 BP: power x MagPwr x level is past 2^21, where vanilla's base wrapped; in every branch
--               each magic pass's base (Ot6MagBase's result) must be power x 4 + the product / 32, saturated at 65,535
-- Screenshots (3x for the report): the four monsters' five-digit numerals, the same four at 9999, multi-target with
-- heals, the two fonts side by side, a five-digit numeral on the party's side.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local RAGNAROK, BAHAMUT_SLOT = 16, 12
local CMD_MAGIC, ULTIMA = 0x02, 0x14
local LIVE = 0x317C00
local LIMIT, STD = 42069, 9999
local HP = 60000
local HEAL, MISS = 0xC000, 0xF000
local function hex(v) return string.format("$%02X", v) end
local function rom(a) return emu.read(a & 0x3FFFFF, emu.memType.snesPrgRom) end
local function vram(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end
local function wram7f(a) return emu.read(0x7F0000 + a, emu.memType.snesMemory) end
local function stageCount(who, n)
  local a = LIVE + 0x10 + (who * 26 + BAHAMUT_SLOT) * 2
  emu.write(a, n & 0xFF, emu.memType.snesMemory)
  emu.write(a + 1, n >> 8, emu.memType.snesMemory)
end

local who, seat                         -- H (Ragnarok's wearer) and its battle slot
local snap, A0, B0, A, B
local cur                               -- the case being recorded
local inj                               -- the synthetic arm's injection, per case

-- the numeral layout (vanilla's): single thread k's four tiles from $C0 + 4k, its sprites A and B on the first and
-- third; a multi-target numeral's four from its slot's tile
local MULTI = { [0] = 0x60, 0x64, 0x68, 0x6C, 0x80, 0x84, 0x88, 0x8C, 0xA0, 0xA4 }
local function tileWord(t) return 0x2000 + t * 16 end
-- the condensed digits' reference: tools/numeral_font.py's strokes, drawn here (outline 12 around fill 13), five at
-- x = 1, 7, 13, 19, 25 of the 32-pixel row; a tile's VRAM words are rows of (plane 0 | plane 1 << 8), then 2/3
local STROKES = {
  [0] = { "####", "#..#", "#..#", "#..#", "#..#", "####" }, { "..#.", ".##.", "..#.", "..#.", "..#.", ".###" },
  { "####", "...#", "...#", "####", "#...", "####" }, { "####", "...#", ".###", "...#", "...#", "####" },
  { "#..#", "#..#", "####", "...#", "...#", "...#" }, { "####", "#...", "####", "...#", "...#", "####" },
  { "####", "#...", "####", "#..#", "#..#", "####" }, { "####", "...#", "...#", "..#.", "..#.", "..#." },
  { "####", "#..#", "####", "#..#", "#..#", "####" }, { "####", "#..#", "#..#", "####", "...#", "####" },
}
local function condensedWords(v)
  local px = {}
  for y = 0, 7 do px[y] = {} for x = 0, 31 do px[y][x] = 0 end end
  local s = tostring(v)
  for p = 0, 4 do
    local d = tonumber(s:sub(p + 1, p + 1))
    local g = {}
    for y = 0, 7 do g[y] = {} for x = 0, 5 do g[y][x] = 0 end end
    for y = 1, 6 do for x = 1, 4 do if STROKES[d][y]:sub(x, x) == "#" then g[y][x] = 13 end end end
    for y = 0, 7 do for x = 0, 5 do
      if g[y][x] == 0 then
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local xx, yy = x + o[1], y + o[2]
          if xx >= 0 and xx < 6 and yy >= 0 and yy < 8 and g[yy][xx] == 13 then g[y][x] = 12 end
        end
      end
    end end
    local x0 = ({ [0] = 1, 7, 13, 19, 25 })[p]
    for y = 0, 7 do for x = 0, 5 do if g[y][x] ~= 0 then px[y][x0 + x] = g[y][x] end end end
  end
  local words = {}
  for t = 0, 3 do
    words[t] = {}
    for y = 0, 7 do
      local p = { 0, 0, 0, 0 }
      for x = 0, 7 do
        local c = px[y][t * 8 + x]
        for b = 0, 3 do if (c >> b) & 1 == 1 then p[b + 1] = p[b + 1] | (0x80 >> x) end end
      end
      words[t][y] = p[1] | (p[2] << 8)
      words[t][8 + y] = p[3] | (p[4] << 8)
    end
  end
  return words
end
-- the glyph for digit d, from the battle's decompressed status graphics ($7F:BC40, 32 bytes a digit)
local function glyphIs(w, d)
  for b = 0, 15 do
    local g = wram7f(0xBC40 + d * 32 + b * 2) | (wram7f(0xBC40 + d * 32 + b * 2 + 1) << 8)
    if vram(w + b) ~= g then return false end
  end
  return true
end
local function blankIs(w)
  for b = 0, 15 do if vram(w + b) ~= 0 then return false end end
  return true
end
-- do the four tiles from t hold v as drawn: five digits condensed (the reference above), one to four vanilla's
-- glyphs left-aligned, the rest blank.  Returns ok, and a description of the first mismatch.
local function tilesHold(t, v)
  local sv = tostring(v)
  if #sv == 5 then
    local ref = condensedWords(v)
    for i = 0, 3 do
      for w = 0, 15 do
        if vram(tileWord(t + i) + w) ~= ref[i][w] then
          return false, string.format("tile %d word %d is %04X, the reference %04X", i, w, vram(tileWord(t + i) + w),
            ref[i][w])
        end
      end
    end
    return true, "condensed"
  end
  for i = 0, 3 do
    local d = tonumber(sv:sub(i + 1, i + 1))
    local ok = d and glyphIs(tileWord(t + i), d) or (not d and blankIs(tileWord(t + i)))
    if not ok then return false, string.format("tile %d is not %s", i, d and ("vanilla's " .. d) or "blank") end
  end
  return true, "vanilla's glyphs"
end
local function digits(v)
  local s = tostring(v)
  local t = {}
  for i = 1, #s do t[i] = tonumber(s:sub(i, i)) end
  return t
end

-- the OAM buffer as the battle NMI found it last (the frame's sprites, complete), and the entries (y < $E0) on a
-- tile, with x (9 bits, signed: past 255 wraps to the left edge) and attribute
local OAM = nil
local function oamSnap()
  local t = {}
  for i = 0, 0x21F do t[i] = H.readByte(0x0300 + i) end
  OAM = t
end
local function oamOn(tile)
  local out = {}
  if not OAM then return out end
  for e = 0, 127 do
    local o = e * 4
    if OAM[o + 1] < 0xE0 and OAM[o + 2] == tile and (OAM[o + 3] & 1) == 0 then
      local hi = (OAM[0x200 + (e >> 2)] >> ((e & 3) * 2)) & 1
      local x = OAM[o] + hi * 256
      if x >= 256 then x = x - 512 end
      out[#out + 1] = { e = e, x = x, y = OAM[o + 1], a = OAM[o + 3] }
    end
  end
  return out
end

local function arm()
  local CAP = H.sym("Ot6DmgCap")
  -- the store after Ot6DmgCap: CalcMaxDmg's `jsl Ot6DmgCap / bra / .res 7 / sta $33d0,y`, found by its bytes
  local maxd = H.sym("CalcMaxDmg") & 0x3FFFFF
  local store
  for o = 0, 0x80 do
    if rom(maxd + o) == 0x22 and rom(maxd + o + 1) == (CAP & 0xFF) and rom(maxd + o + 2) == ((CAP >> 8) & 0xFF)
       and rom(maxd + o + 3) == (CAP >> 16) then store = (H.sym("CalcMaxDmg") & 0xFF0000) | ((maxd + o + 13) & 0xFFFF) end
  end
  H.assertEq(store ~= nil and rom(store) == 0x99, true, "CalcMaxDmg's jsl Ot6DmgCap, and its sta $33d0,y 13 bytes on")
  local pendCap = nil
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    local s = emu.getState()
    local x, y = s["cpu.x"] & 0xFF, s["cpu.y"] & 0xFF
    pendCap = { x = x, y = y, pre = (s["cpu.a"] & 0xFFFF) + H.readWord(0xF0) }
  end, emu.callbackType.exec, CAP, CAP)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not pendCap then return end
    local s = emu.getState()
    local p = pendCap
    pendCap = nil
    p.total = s["cpu.a"] & 0xFFFF
    if p.x ~= seat * 2 then return end
    cur.caps[#cur.caps + 1] = p
  end, emu.callbackType.exec, store, store)
  -- the magic formula's base, every pass: CalcMagicDmg's `jsl Ot6MagBase / sta $11b0`, found by its bytes
  local MB = H.sym("Ot6MagBase")
  local cmd_ = H.sym("CalcMagicDmg") & 0x3FFFFF
  local mbStore
  for o = 0, 0x40 do
    if rom(cmd_ + o) == 0x22 and rom(cmd_ + o + 1) == (MB & 0xFF) and rom(cmd_ + o + 2) == ((MB >> 8) & 0xFF)
       and rom(cmd_ + o + 3) == (MB >> 16) then mbStore = (H.sym("CalcMagicDmg") & 0xFF0000) | ((cmd_ + o + 4) & 0xFFFF) end
  end
  H.assertEq(mbStore ~= nil and rom(mbStore) == 0x8D, true, "CalcMagicDmg's jsl Ot6MagBase, then sta $11b0")
  local pendMB
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    pendMB = { pow = H.readByte(0x11A6), mag = H.readByte(0x11AE), lvl = H.readByte(0x11AF) }
  end, emu.callbackType.exec, MB, MB)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not pendMB then return end
    local p = pendMB
    pendMB = nil
    p.out = emu.getState()["cpu.a"] & 0xFFFF
    p.prod = p.pow * p.mag * p.lvl
    -- CalcMagicDmg: power x 4 (power alone at level 0) + the product / 32
    p.want = math.min(0xFFFF, (p.lvl >= 1 and p.pow * 4 or p.pow) + (p.prod >> 5))
    cur.bases[#cur.bases + 1] = p
  end, emu.callbackType.exec, mbStore, mbStore)
  -- the synthetic arms
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.broken then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == inj.broken then emu.write(0x7E00F0, 33333 & 0xFF, emu.memType.snesMemory)
      emu.write(0x7E00F1, 33333 >> 8, emu.memType.snesMemory); inj.brokenHit = true end
  end, emu.callbackType.exec, H.sym("Ot6BrokenDmg"), H.sym("Ot6BrokenDmg"))
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.weak then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == inj.weak then emu.write(0x7E00F0, 33333 & 0xFF, emu.memType.snesMemory)
      emu.write(0x7E00F1, 33333 >> 8, emu.memType.snesMemory); inj.weakHit = true end
  end, emu.callbackType.exec, H.sym("Ot6WeakDouble"), H.sym("Ot6WeakDouble"))
  -- the weak arm: the spell's element and the target's weakness, at the pass's start (CalcTargetDmg)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if inj.weak and y == inj.weak then
      inj.elem = inj.elem or H.readByte(0x11A1)
      emu.write(0x7E11A1, 0x01, emu.memType.snesMemory)
      emu.write(0x7E3BE0 + y, H.readByte(0x3BE0 + y) | 0x01, emu.memType.snesMemory)
      emu.write(0x7E3BCC + y, H.readByte(0x3BCC + y) & 0xFE, emu.memType.snesMemory)
      emu.write(0x7E3BCD + y, H.readByte(0x3BCD + y) & 0xFE, emu.memType.snesMemory)
    elseif inj.elem then
      emu.write(0x7E11A1, inj.elem, emu.memType.snesMemory)
    end
  end, emu.callbackType.exec, H.sym("CalcTargetDmg"), H.sym("CalcTargetDmg"))
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.heal then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == inj.heal then emu.write(0x7E00F2, H.readByte(0xF2) | 0x01, emu.memType.snesMemory); inj.healHit = true end
  end, emu.callbackType.exec, H.sym("CalcMaxDmg"), H.sym("CalcMaxDmg"))
  -- the fonts arm: the monsters' entries at H's pass's display set to 9999 and 12345 in turn
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.fonts or inj.fontsDone or #cur.caps == 0 then return end
    for i, e in ipairs(cur.mons) do
      local v = (i % 2 == 1) and 9999 or 12345
      emu.write(0x7E33D0 + e, v & 0xFF, emu.memType.snesMemory)
      emu.write(0x7E33D1 + e, v >> 8, emu.memType.snesMemory)
      inj.vals[e] = v
    end
    inj.fontsDone = true
  end, emu.callbackType.exec, H.sym("_c262ef"), H.sym("_c262ef"))
  -- the right arm: at H's pass's display, the monsters' entries dropped and the first seated member's set to 12345:
  -- one single numeral, on the party's side of the screen
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.right or inj.rightAt or #cur.caps == 0 then return end
    for _, e in ipairs(cur.mons) do
      emu.write(0x7E33D0 + e, 0xFF, emu.memType.snesMemory)
      emu.write(0x7E33D1 + e, 0xFF, emu.memType.snesMemory)
    end
    for s2 = 0, 3 do
      if not inj.rightAt and H.readByte(0x3ED8 + s2 * 2) ~= 0xFF then
        emu.write(0x7E33D0 + s2 * 2, 12345 & 0xFF, emu.memType.snesMemory)
        emu.write(0x7E33D1 + s2 * 2, 12345 >> 8, emu.memType.snesMemory)
        inj.rightAt = s2
      end
    end
  end, emu.callbackType.exec, H.sym("_c262ef"), H.sym("_c262ef"))
  -- the multi arm: heal entries for the seated members, at the display of H's pass
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.multi or inj.multiDone then return end
    if #cur.caps == 0 then return end
    local hv = { 2345, 9999, 88, 1 }
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
        emu.write(0x7E33E4 + s * 2, hv[s + 1] & 0xFF, emu.memType.snesMemory)
        emu.write(0x7E33E5 + s * 2, hv[s + 1] >> 8, emu.memType.snesMemory)
        inj.heals[s * 2] = hv[s + 1]
      end
    end
    inj.multiDone = true
  end, emu.callbackType.exec, H.sym("_c262ef"), H.sym("_c262ef"))
  -- the single numerals: the value each command carries, then its tiles and sprites once drawn
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    local p = H.readWord(0x76)
    local n = { tgt = H.readByte(p + 1), v = H.readWord(p + 2), k = H.readByte(0x632E) & 3, f = H.frame }
    cur.nums[#cur.nums + 1] = n
  end, emu.callbackType.exec, H.sym("Ot6NumSingle_ext"), H.sym("Ot6NumSingle_ext"))
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    local y = emu.getState()["cpu.y"] & 0xFFFF
    cur.mnums[#cur.mnums + 1] = { t = H.readByte(0x20), v = H.readWord(0x2BCE + y), f = H.frame }
  end, emu.callbackType.exec, H.sym("Ot6NumMulti_ext"), H.sym("Ot6NumMulti_ext"))
end

-- read a numeral's drawn state a few frames after it is enabled: its four tiles against what its value should draw,
-- and its sprites
local function readSingle(n)
  if n.seen then return end
  local k = n.k
  if (H.readByte(0x631A + k) & 0x7F) == 0 then return end          -- not up yet
  n.up = n.up or H.frame
  if H.frame < n.up + 4 then return end
  n.seen = H.frame
  local v = n.v >= HEAL and n.v - HEAL or n.v
  n.ok, n.why = tilesHold(0xC0 + 4 * k, v)
  n.sprA, n.sprB = oamOn(0xC0 + 4 * k), oamOn(0xC2 + 4 * k)
  n.green = (H.readByte(0x631A + k) & 0x80) ~= 0
end

local function readMulti(m)
  if m.seen or H.readByte(0x7B3E) == 0 then return end
  m.up = m.up or H.frame
  if H.frame < m.up + 4 then return end
  m.seen = H.frame
  local v = m.v >= HEAL and m.v - HEAL or m.v
  m.ok, m.why = tilesHold(MULTI[m.t], v)
  m.sprA, m.sprB = oamOn(MULTI[m.t]), oamOn(MULTI[m.t] + 2)
  m.green = (H.readByte(0x7B3F + m.t) & 0x80) ~= 0
end

-- the sprite load per scanline in the last NMI's OAM: the busiest line's 8-pixel slivers and sprites above the menu
-- window (the PPU draws at most 34 and 32 a line)
local function busiest()
  local sl, sp, worst, wl = {}, {}, 0, nil
  for e = 0, 127 do
    local y = OAM[e * 4 + 1]
    local big = ((OAM[0x200 + (e >> 2)] >> ((e & 3) * 2 + 1)) & 1) == 1
    local h = big and 32 or 16
    if y < 0xE0 then
      for l = y, y + h - 1 do
        local ll = l & 0xFF
        sl[ll] = (sl[ll] or 0) + h // 8
        sp[ll] = (sp[ll] or 0) + 1
      end
    end
  end
  -- above line $97: FF6 parks nine 32x32 sprites from there down to hide what goes behind the menu window
  for l = 0, 0x96 do if (sl[l] or 0) > worst then worst, wl = sl[l], l end end
  return worst, wl, sp[wl or 0] or 0
end

local function open(tag)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.waitFrames(30),
  })
end

local results = {}
local CASES = {
  { name = "holder", count = 500, shot = "limitbreak_frogs" },
  { name = "other", count = 499, shot = "limitbreak_frogs_9999" },
  { name = "multi", count = 500, multi = true, shot = "limitbreak_multi" },
  { name = "fonts", count = 500, fonts = true, shot = "limitbreak_fonts" },
  { name = "right", count = 500, right = true, shot = "limitbreak_right" },
  { name = "broken", count = 500, broken = true },
  { name = "weak", count = 500, weak = true },
  { name = "heal", count = 500, heal = true },
  { name = "formula", count = 500, formula = true },
}

local function branch(cs, restore)
  local r = { name = cs.name, count = cs.count, shot = cs.shot, multi = cs.multi, formula = cs.formula, bases = {},
    right = cs.right, fonts = cs.fonts,
    caps = {}, nums = {}, mnums = {}, hp0 = {}, hp1 = {}, mons = {} }
  results[#results + 1] = r
  local steps = {}
  if restore then
    local req
    steps[#steps + 1] = H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end)
    steps[#steps + 1] = H.waitFrames(2)
    steps[#steps + 1] = H.call(function() H.checkReq(req, "the snapshot on the map"); H.rearmInputInjection() end)
  end
  steps[#steps + 1] = H.call(function()
    A, B = A0, B0
    stageCount(who, cs.count)
    if cs.formula then                  -- level 99, Mag.Pwr 255: power x MagPwr x level past 2^21
      emu.write(0x7E1600 + 37 * who + 0x08, 99, emu.memType.snesMemory)
      emu.write(0x7E1600 + 37 * who + 0x1D, 255, emu.memType.snesMemory)
    end
    H.log(string.format("[limit] %s: $%02X's count on Bahamut staged at %d", cs.name, who, cs.count))
  end)
  steps[#steps + 1] = open(cs.name)
  steps[#steps + 1] = H.call(function()
    seat = nil
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == who then seat = s end end
    H.assertEq(seat ~= nil, true, cs.name .. ": H is in the battle")
    r.mask = H.readByte(H.sym("OT6_LIMITBREAK") & 0xFFFF)
    for s = 0, 5 do
      if H.monStanding(s) then
        local e = 8 + s * 2
        r.mons[#r.mons + 1] = e
        H.writeWord(0x3BF4 + e, HP)
        H.writeWord(0x3C1C + e, HP)
      end
    end
    H.assertEq(#r.mons >= 1, true, cs.name .. ": a monster stands")
    inj = { heals = {} }
    if cs.broken then
      inj.broken = r.mons[1]
      emu.write(0x7E0000 + H.sym("OT6_BROKEN_TICKS") + inj.broken, 8, emu.memType.snesMemory)
    end
    if cs.weak then inj.weak = r.mons[1] end
    if cs.heal then inj.heal = r.mons[1] end
    if cs.multi then inj.multi = true end
    if cs.fonts then inj.fonts = true; inj.vals = {} end
    if cs.right then inj.right = true end
    H.log(string.format("[limit] %s: seat %d, OT6_LIMITBREAK %s, monsters %s staged at %d HP", cs.name, seat,
      hex(r.mask), table.concat(r.mons, ","), HP))
    cur = r
  end)
  steps[#steps + 1] = H.kitBattle({ { who = who, cmd = CMD_MAGIC, spell = ULTIMA, boost = cs.formula and 0 or 2 } }, {
    untilPlanDone = true, idle = "defend", maxFrames = 60000,
    planDone = function() return r.ended ~= nil end,
  })
  -- the kit's step ends once the cast is confirmed; the cast resolves and its numerals draw after
  steps[#steps + 1] = H.driveUntil(function() return r.ended ~= nil end, 9000, {
    H.call(function() H.setPad({}) end), H.waitFrames(1),
  }, cs.name .. ": H's Ultima resolved and its numerals drawn")
  steps[#steps + 1] = H.call(function()
    for _, e in ipairs(r.mons) do r.hp1[e] = H.readWord(0x3BF4 + e) end
    r.heals = inj.heals
    r.injHit = inj.brokenHit or inj.weakHit or inj.healHit
    r.injBroken = inj.broken
    r.vals = inj.vals
    r.rightAt = inj.rightAt
    cur = nil
  end)
  return H.seqStep(steps)
end

-- the window around H's action: live from H's turn (its command executes) to its end, then 90 frames for the
-- numerals to draw
local function watch()
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not cur or cur.live or seat == nil then return end
    if H.readByte(0x3A7C) == CMD_MAGIC and H.readByte(0x3A7D) == ULTIMA then
      cur.live = true
      for _, e in ipairs(cur.mons) do cur.hp0[e] = H.readWord(0x3BF4 + e) end
    end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or cur.endF then return end
    if (emu.getState()["cpu.x"] & 0xFF) == seat * 2 then cur.endF = H.frame end
  end, emu.callbackType.exec, ae, ae)
  local nmi = H.sym("BattleNMI")
  emu.addMemoryCallback(function()
    if cur and cur.live then oamSnap() end
  end, emu.callbackType.exec, nmi, nmi)
  emu.addEventCallback(function()
    if not cur or not cur.live then return end
    for _, n in ipairs(cur.nums) do readSingle(n) end
    for _, m in ipairs(cur.mnums) do readMulti(m) end
    if cur.shot and not cur.shotDone then
      local up
      if cur.right then
        for _, n in ipairs(cur.nums) do if n.tgt < 4 and n.v == 12345 and n.seen then up = true end end
      elseif cur.multi then
        up = #cur.mnums > 0 and cur.mnums[1].seen ~= nil
      else
        local seenMon = 0
        for _, n in ipairs(cur.nums) do if n.tgt >= 4 and n.seen then seenMon = seenMon + 1 end end
        up = seenMon >= #cur.mons
      end
      if up then cur.shotAt = cur.shotAt or (H.frame + 6) end
      if cur.shotAt and H.frame >= cur.shotAt then
        H.screenshot(cur.shot); cur.shotDone = true
        if OAM then
          cur.slivers, cur.sline, cur.sprites = busiest()
          H.log(string.format("[limit] %s: the shot's busiest line, %s: %d slivers, %d sprites (the PPU's limits: 34, "
            .. "32)", cur.name, tostring(cur.sline), cur.slivers, cur.sprites))
        end
      end
    end
    if cur.endF and H.frame > cur.endF + 90 and not cur.ended and (not cur.shot or cur.shotDone
        or H.frame > cur.endF + 600) then          -- (a shot whose numerals never came: the claims say so)
      cur.ended = H.frame
    end
  end, emu.eventType.endFrame)
end

local function claims()
  local bad = 0
  local function claim(ok, what)
    H.log(string.format("[limit] %s %s", ok and "ok:" or "NOT:", what))
    if not ok then bad = bad + 1 end
  end
  -- a numeral's drawing: its tiles, its two sprites, its colour
  local function drawn(r, kind, n, what, green)
    claim(n.ok == true, string.format("%s: %s draws %s (%s numeral, %s)", r.name, what,
      tostring(n.v >= HEAL and n.v - HEAL or n.v), kind, tostring(n.why)))
    local a, b = n.sprA and n.sprA[1], n.sprB and n.sprB[1]
    claim(a ~= nil and b ~= nil and b.x - a.x == 16 and b.y == a.y, string.format("%s: %s's sprites A x%s, B x%s", r.name,
      what, a and a.x or "-", b and b.x or "-"))
    claim(n.green == green, string.format("%s: %s is %s", r.name, what, n.green and "green" or "white"))
  end
  local byName = {}
  for _, r in ipairs(results) do byName[r.name] = r end
  for _, r in ipairs(results) do
    local holder = r.count >= 500
    claim(((r.mask >> seat) & 1) == (holder and 1 or 0), string.format("%s: OT6_LIMITBREAK %s at the open (H's bit %s)",
      r.name, hex(r.mask), holder and "set" or "clear"))
    local byY = {}
    for _, p in ipairs(r.caps) do byY[p.y] = p end
    for _, e in ipairs(r.right and {} or r.mons) do
      local side = byY[e] or byY[e + 0x14]
      claim(side ~= nil, string.format("%s: H's Ultima reached the cap for entity %d", r.name, e))
      if side then
        local pre, total = side.pre, side.total
        local heal = side.y >= 0x14
        local want
        if r.name == "broken" and e == r.injBroken then want = LIMIT
        elseif r.name == "weak" and e == r.mons[1] then want = 0x7FFF   -- x2 saturated at $FFFF, then an unbroken
                                                                          --   body's half (vanilla's skip: 16,666)
        elseif heal then want = math.min(pre, STD)
        elseif holder then want = math.min(pre, LIMIT) else want = math.min(pre, STD) end
        claim(pre > STD, string.format("%s: entity %d's amount %d is past 9999 (the precondition)", r.name, e, pre))
        claim(total == want, string.format("%s: entity %d's %s total %d (amount %d; want %d)", r.name, e,
          heal and "heal" or "damage", total, pre, want))
        local shown = (r.vals and r.vals[e]) or total
        if not r.vals then
          if heal then
            claim(r.hp1[e] == math.min(HP, r.hp0[e] + total), string.format("%s: entity %d's HP %d -> %d, healed %d",
              r.name, e, r.hp0[e], r.hp1[e], total))
          else
            claim(r.hp0[e] - r.hp1[e] == total, string.format("%s: entity %d's HP %d -> %d, down %d (the total %d)",
              r.name, e, r.hp0[e], r.hp1[e], r.hp0[e] - r.hp1[e], total))
          end
        end
        local code = heal and (HEAL + shown) or shown
        local found = false
        for _, n in ipairs(r.nums) do
          if n.tgt == e // 2 and n.v == code and n.seen then
            found = true
            drawn(r, "single", n, string.format("entity %d's numeral (thread %d)", e, n.k), heal)
          end
        end
        for _, m in ipairs(r.mnums) do
          if m.t == e // 2 and m.v == code and m.seen then
            found = true
            drawn(r, "multi-target", m, string.format("entity %d's multi-target numeral", e), heal)
          end
        end
        claim(found, string.format("%s: a numeral for entity %d carries %s", r.name, e, hex(code)))
      end
    end
    if r.name == "holder" then
      local single, t3 = 0, false
      for _, n in ipairs(r.nums) do
        if n.tgt >= 4 then single = single + 1 end
        if n.k == 3 and n.v >= 10000 and n.v < HEAL and n.ok then t3 = true end
      end
      claim(#r.mnums == 0 and single == #r.mons, string.format("holder: %d monster numerals take the single path, %d "
        .. "the multi-target one (vanilla: fewer than five numerals go single)", single, #r.mnums))
      claim(#r.mons < 4 or t3, "holder: thread 3 draws a five-digit numeral")
    end
    if r.name == "other" and byName.holder and byName.holder.slivers then
      claim(r.slivers == byName.holder.slivers, string.format("the busiest scanline at the shot: %d slivers with "
        .. "five-digit numerals, %d with 9999 (the same sprites)", byName.holder.slivers, r.slivers or -1))
    end
    if r.name == "fonts" then
      local f4, f5 = 0, 0
      for _, n in ipairs(r.nums) do
        if n.v == 9999 and n.ok then f4 = f4 + 1 end
        if n.v == 12345 and n.ok then f5 = f5 + 1 end
      end
      claim(f4 >= 1 and f5 >= 1, string.format("fonts: %d 9999s in vanilla's glyphs and %d 12345s condensed", f4, f5))
    end
    if r.name == "right" then
      local n0
      for _, n in ipairs(r.nums) do if r.rightAt and n.tgt == r.rightAt and n.v == 12345 and n.seen then n0 = n end end
      claim(n0 ~= nil, string.format("right: a party member's numeral shows 12345 (seat %s)", tostring(r.rightAt)))
      if n0 then drawn(r, "single", n0, "the party member's numeral", false) end
    end
    if r.name == "multi" then
      claim(#r.mnums >= 5, string.format("multi: %d multi-target numerals (five or more)", #r.mnums))
      for s2 = 0, 3 do
        local hv = r.heals and r.heals[s2 * 2]
        if hv then
          local seen = false
          for _, m in ipairs(r.mnums) do
            if m.t == s2 and m.v == HEAL + hv and m.seen then
              seen = true
              drawn(r, "multi-target", m, string.format("seat %d's heal", s2), true)
            end
          end
          claim(seen, string.format("multi: seat %d's heal %d has its numeral", s2, hv))
        end
      end
    end
    for _, b in ipairs(r.bases) do
      claim(b.out == b.want, string.format("%s: the magic base for power %d, Mag.Pwr %d, level %d (product %d) is %d "
        .. "(want %d: power x 4 + product / 32, saturated at 65535)", r.name, b.pow, b.mag, b.lvl, b.prod, b.out, b.want))
    end
    claim(#r.bases >= 1, string.format("%s: %d magic base(s) observed", r.name, #r.bases))
    if r.formula then
      local past = false
      for _, b in ipairs(r.bases) do if b.prod >= 2 ^ 21 then past = true end end
      claim(past, "formula: a base whose product is past 2^21 (vanilla wrapped it)")
    end
    if r.name == "broken" then claim(r.injHit == true, "broken: Ot6BrokenDmg doubled the staged 33,333") end
    if r.name == "weak" then claim(r.injHit == true, "weak: Ot6WeakDouble doubled the staged 33,333") end
    if r.name == "heal" then claim(r.injHit == true, "heal: the pass went to the heal side") end
  end
  H.assertEq(bad, 0, "every claim above holds")
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("wor-ragnarok-v1"),
  H.call(function()
    for ch = 0, 15 do
      if H.readByte(0x1600 + 37 * ch + 0x1E) == RAGNAROK then who = ch end
    end
    H.assertEq(who ~= nil and who < 12, true, "precondition: a member who can hold espers wears Ragnarok")
    local x, y = H.worldX(), H.worldY()
    A0 = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
      if B0 == nil and H.worldPassable(x + d[1], y + d[2]) then B0 = { x + d[1], y + d[2] } end
    end
    H.assertEq(B0 ~= nil, true, "a passable world tile beside the save")
    H.log(string.format("[limit] H = $%02X; pacing (%d,%d) <-> (%d,%d)", who, A0[1], A0[2], B0[1], B0[2]))
    arm()
    watch()
  end),
  H.call(function() H.setPad({}); snap = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the snapshot on the map") end),
  H.lazy(function()
    local steps = {}
    for i, cs in ipairs(CASES) do
      steps[#steps + 1] = branch(cs, i > 1)
    end
    return H.seqStep(steps)
  end),
  H.call(claims),
  H.logStep("[limit] PASS: a holder's damage passes 9999 to 42,069, everyone else's and every heal stay at 9999, "
    .. "and five-digit numerals draw condensed in the same two sprites"),
})
