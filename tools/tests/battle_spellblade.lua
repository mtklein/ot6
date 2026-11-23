-- @suite slow
-- battle_spellblade.lua -- Celes's kit: the rune on her blade, the Rune
-- Knight's list and Break Blade (#563; ot6_rune.asm; docs/design/kits.md,
-- "Celes").
--
-- CELES's Runic command opens a list (w7e6168 = 7): Runic, the stance as it
-- always was; a blade row for each element she can cast in this battle,
-- priced at her cheapest spell of it, which arms her blade with that element
-- for the rest of the battle; and Break Blade, the divine (3 BP, 99 MP),
-- learned with the World of Ruin or at the stab on the Floating Continent.
-- A boost climbs a blade row's spell line as it does in the Magic list (Fire,
-- Fire 2, Fire 3; Poison to Bio), at the tier's own MP, and the rune keeps
-- that tier.  A Runic absorb of an elemental spell arms the blade too, at
-- the tier of the spell absorbed.  The rune joins her weapon's swings only
-- on a body that is weak to it and neither absorbs, nulls nor halves it;
-- there the hit is multiplied by the tier (x2, x3, x4), chips one shield and
-- is drawn in the element's colours.  While Break Blade runs (three of her
-- turns) every landed hit of her weapon takes one shield, whatever the
-- body's keys, and the rune waits.
--
-- Played: Continue the wor-tomb-v1 battery (CELES wears Maduin and holds
-- two blades, one a ThunderBlade; EDGAR wears Ramuh), walk Darill's Tomb's
-- east room into random battles and play through the real menu
-- (H.kitBattle).  In each battle the party first Fights until one monster
-- stands alone (the others Defend from then on, with their usual care);
-- that body is what the checks are made on.  A battle that ends early, or
-- that turns dangerous (CELES down or under a third of her max HP, or two
-- of her allies out of the fight: it is handed to the route's fight driver,
-- battle_runicblade's hand-over), leaves its unfinished checks to the next
-- battle; every check stands alone and reaches its own precondition (her
-- blade armed by a blade row, the bank filled by Defends).
--
-- Staged (a synthetic mechanism test; state_write_waivers.txt), since the
-- formation is whatever the tomb deals and no body there is weak to, drinks,
-- nulls and halves one element on cue:
--   * the standing body: its weak, absorb, null and half bytes as each check
--     needs them, no class weakness (her sword's slash would chip through
--     it), nine shields, no element revealed, and 30,000 HP so that it
--     outlasts the checks; put back as dealt before the battle is fought out;
--   * the two event switches that teach Break Blade ($0266, $00A4), cleared
--     and set one at a time under one open list, then put back;
--   * CELES Muddled with only Runic in her command list, held until the
--     engine picks Runic for her (RandCharAction), then put back;
--   * her pending boost, lowered from three to two as a Break Blade picked
--     at three begins: the state Ot6RuneExec's own gate is there for (a
--     Mimic's copy short of three).  Her menu cannot reach it: since #555 L
--     at the target select of a pick made in a list is refused, which check
--     10's cast plays;
--   * her MP, set one under the price of the blade row's top tier while R is
--     pressed on the row (a level-33 pool pays every tier), then put back.
-- Everything asserted is read at the ROM's own routines (exec hooks on
-- Ot6RunicBP, Ot6RuneArm, Ot6TargetPre, Ot6Chip, Ot6RuneWeakMul, Ot6HitJoin,
-- Ot6SwingPal_ext, LoadSpriteAnimPal, Ot6BpBegin, Ot6ActionEnd, Cmd_0b) and
-- from RAM around her own action (its begin and its end), so a monster's
-- turn in between is not counted to her.
--
-- Checks:
--   1. the list: mode 7; Runic, a blade row for each element computed here
--      from her battle spell list and the ROM's MagicProp, in bit order,
--      each at the cheapest price, then Break Blade at 99;
--   2. an ally's elemental spell absorbed by her Runic arms the blade with
--      its element, at tier 1 (2), and the same spell cast at one and at two
--      points (Bolt 2, Bolt 3) at tiers 2 and 3 (2t2, 2t3); a blade row
--      replaces element and tier together, for exactly the row's price; the
--      sign beside her name shows the element within 8 frames;
--   3. a spell without an element, absorbed, leaves the rune and its tier;
--   4. a blade row takes a boost: in the list its price and its name are the
--      line's spell at the boost pending, on the command window or raised by
--      R on the row itself, and a third point adds nothing (4a); R adds no
--      point her MP cannot pay for (4b); confirmed at one and at two points
--      it arms tiers 2 and 3 for the tier spell's MP, spends the boost and
--      shows the tier's banner (4c1, 4c2);
--   5. the rune joins a swing only on a body weak to it: (a) weak: the bit,
--      x2, a chip a swing, the reveal and the element's colours; at tier 2
--      x3 and at tier 3 x4, still one chip a swing (5t2, 5t3); a hit the
--      rune does not bite is x2 at most, whatever the tier (5w: weak to the
--      weapon's own element); (b) not weak, (c) weak and absorbing, (d) weak
--      and nulling, (e) weak and halving: nothing joins, and the body is
--      hurt, never healed;
--   6. every swing of a 2-BP Fight chips;
--   7. the rune lasts: through two more rounds, to the battle's last frame,
--      and is gone (with its tier and its sign) as the next battle opens;
--   8. a 3-BP Runic (RunicBlade) arms the blade too;
--   9. Break Blade under three points is refused in the list, and one that
--      finds itself under three as it runs does nothing and costs nothing;
--  10. Break Blade: L at its target select takes nothing back; 99 MP, three
--      of her turns, the sword beside her name; each landed hit takes exactly
--      one shield from an unkeyed body, from a body weak to her weapon's own
--      element, and from one weak to the waiting rune (which joins nothing
--      meanwhile); when it ends the rune bites again;
--  11. either switch alone teaches Break Blade, neither leaves no row;
--  12. a Runic the engine chooses (Muddle) queues attack $00: the plain
--      stance, never a blade row or the divine.
-- A blade row with no line (Pearl's, Quake's) takes no boost; CELES casts
-- none here, so that is the Gogo suite's.
-- Mutants (one per arm, each red at its own check) and the draws the suite
-- was run over: build/attempts/wt/v051-spellblade/suite/.
--
-- Levers, for evidence only (off in the suite; a lab sets the global ahead
-- of the file): PACE_BURN flees that many encounters first, to vary the
-- encounter history (TESTING.md); SPELLBLADE_SPLIT = n leaves each battle
-- once n checks are made in it, so that every check is also made as the
-- first of a later battle (the resuming this header promises).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, RUNIC, FIGHT, MAGIC = 0x06, 0x0B, 0x00, 0x02
local ROW_RUNIC, ROW_BLADE, ROW_BREAK, ROW_TIERED = 0xD0, 0xD1, 0xD9, 0xC8
local BREAK_MP = 99
-- ot6_memory.inc
local RUNE, RUNETIER, BREAKBLADE, RUNESWING, RUNEADD, BLADESWING = 0xED8F, 0xEE3A, 0xEDA2, 0x57BB, 0xEF1F, 0xEE38
local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF
local SW_STAB, SW_RUIN = 0x0266, 0x00A4
-- the spell lines a blade row climbs, by element bit: Fire, Ice, Bolt (three tiers) and Poison (Bio, twice).
-- Written out here, and the sign's icons and colours below (ot6_icons.asm), so that the ROM's tables are checked
-- and not echoed
local LINES = { [0] = { 0x00, 0x05, 0x09 }, { 0x01, 0x06, 0x0A }, { 0x02, 0x07, 0x0B }, { 0x03, 0x08, 0x08 } }
local GLYPH = { [0] = 0xEB, 0xEC, 0xED, 0x64, 0xEF, 0xFB, 0xFC, 0xFD }
local GLYPH_PAL = { [0] = 7, 3, 2, 6, 0, 2, 1, 3 }
local SWORD = 0x21D9
local ELEM = { [0] = "fire", "ice", "bolt", "poison", "wind", "pearl", "earth", "water" }
local BURN = type(PACE_BURN) == "number" and PACE_BURN or 0
local SPLIT = type(SPELLBLADE_SPLIT) == "number" and SPELLBLADE_SPLIT or nil
-- battles the checks may take.  Measured (build/attempts/wt/v051-spellblade/suite/summary.txt): over 19 draws
-- (seed shifts 0-14, 0-8 encounters fled first, four of both) every check was made by the second battle in 18
-- and by the third in one; with SPELLBLADE_SPLIT at 3, 6 and 10 the 32 checks took 12, 7 and 4 battles, two of
-- those 23 battles making none (the body fell, or the battle was handed over, before a check).  Each battle's
-- care spends some twenty Potions, so the budget is no deeper than the bag: four times the worst natural draw
local BATTLES = 12
local PASSES = 3      -- times one battle is asked for what is still open

local S = { battles = 0, tick = 0, acts = {}, hits = {}, pals = {}, absorbs = {}, arms = {}, casts = {}, settle = {},
  shots = {}, starts = {}, signLags = {}, runeViol = {}, armedNow = 0, ching = 0, buzz = 0 }
local D = {}          -- checks made
local NEED = { "1", "2", "2t2", "2t3", "3", "4a", "4b", "4c1", "4c2", "5a", "5t2", "5t3", "5w", "5b", "5c", "5d", "5e",
  "6", "7a", "7b", "7c", "8", "9a", "9b", "10a", "10b", "10c", "10d", "10e", "10f", "11", "12" }
local IN_BATTLE = {}  -- (all but 7c, which the next battle's first frame makes)
for _, k in ipairs(NEED) do if k ~= "7c" then IN_BATTLE[#IN_BATTLE + 1] = k end end

local function say(...) H.log("[spellblade] " .. string.format(...)) end
local function allMade()
  for _, k in ipairs(NEED) do if not D[k] then return false end end
  return true
end
local function inBattle() return H.battleLoadStarted() end
local function ent() return S.celes * 2 end
local function rune() return H.readByte(RUNE + ent()) end
local function tier() return H.readByte(RUNETIER + ent()) end
local function bblade() return H.readByte(BREAKBLADE + ent()) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function stance() return (H.readByte(0x3E4C + ent()) & 0x04) ~= 0 end
local function sw(n) return (H.readByte(0x1E80 + (n >> 3)) >> (n & 7)) & 1 end
local function monY() return 8 + S.slot * 2 end
local function shields() return H.readByte(0x3E38 + monY()) end
local function monHp() return H.readWord(0x3BF4 + monY()) end
local function bitIndex(b)
  local e = 0
  while e < 8 and (b >> e) & 1 == 0 do e = e + 1 end
  return e
end
local function seatOf(id)
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == id then return s end end
end
local function standing(s)
  return H.readWord(0x3BF4 + s * 2) > 0 and (H.readByte(0x3EE4 + s * 2) & 0xC2) == 0
end
local function liveMask() return H.readByte(0x3A75) end
local function count(t, fits)
  local n = 0
  for _, v in ipairs(t) do if fits(v) then n = n + 1 end end
  return n
end

-- ---- what the suite computes for itself, from her spell list and the ROM ----
local function magicProp(id, off) return H.readRomByte(MAGIC_PROP + id * 14 + off) end
-- the spells a seat can cast in this battle: its battle Magic list ($302c), rows 1-54 (row 0 is the esper)
local function spellRows(seat)
  local p, t = H.readWord(0x302C + seat * 2), {}
  for i = 1, 54 do
    local id = H.readByte(p + i * 4)
    if id < 0x36 then t[#t + 1] = { id = id, mp = H.readByte(p + i * 4 + 3) } end
  end
  return t
end
-- MagicProp's cost through the caster's Economizer or Gold Hairpin (CalcMPCost's order)
local function spellPrice(seat, id)
  local raw, relic = magicProp(id, 5), H.readByte(0x3C45 + seat * 2)
  if relic & 0x40 ~= 0 then return 1 end
  if relic & 0x20 ~= 0 then return (raw + 1) // 2 end
  return raw
end
-- a spell's tier: its place in its line (the second column 2, the third 3; Bio, in both, 2), else 1
local function tierOf(id)
  for e = 0, 3 do if LINES[e][2] == id then return 2 end end
  for e = 0, 3 do if LINES[e][3] == id then return 3 end end
  return 1
end
-- the line a spell heads, or nil; and what a spell is cast as at a boost (its line's spell, two steps at most)
local function lineOf(id)
  for e = 0, 3 do if LINES[e][1] == id then return e end end
end
local function foldOf(id, boost)
  local e = lineOf(id)
  return e ~= nil and LINES[e][1 + math.min(boost, 2)] or id
end
-- a blade row per castable element, in bit order, at the cheapest spell of it; `climbs` when that spell heads
-- the element's line
local function bladeRows(seat)
  local t, rows = {}, spellRows(seat)
  for e = 0, 7 do
    local best, via = nil, nil
    for _, sp in ipairs(rows) do
      if magicProp(sp.id, 1) & (1 << e) ~= 0 then
        local c = spellPrice(seat, sp.id)
        if best == nil or c < best then best, via = c, sp.id end
      end
    end
    if best ~= nil then
      t[#t + 1] = { e = e, bit = 1 << e, id = ROW_BLADE + e, price = best, via = via,
        climbs = LINES[e] ~= nil and LINES[e][1] == via }
    end
  end
  return t
end
-- the spell a blade row stands for with n points pending; its price; the record of Ot6RuneName it is named by
-- (ten tiles; the tiered names first, $C8 + line * 2 + (tier - 2), then the rows' own from $D0)
local function rowSpell(b, n) return b.climbs and foldOf(b.via, n) or b.via end
local function rowPrice(b, n) return spellPrice(S.celes, rowSpell(b, n)) end
local function rowTier(b, n) return tierOf(rowSpell(b, n)) end
local function rowNameId(b, n)
  local t = rowTier(b, n)
  return t == 1 and b.id or (ROW_TIERED + b.e * 2 + (t - 2))
end
local function nameRecord(id)
  local t = {}
  for i = 0, 9 do t[#t + 1] = H.readRomByte((H.sym("Ot6RuneName") & 0x3FFFFF) + (id - ROW_TIERED) * 10 + i) end
  return t
end
local function tilesText(t)
  local s = ""
  for _, b in ipairs(t) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9A and b <= 0xB3 then s = s .. string.char(97 + b - 0x9A)
    elseif b >= 0xB4 and b <= 0xBD then s = s .. string.char(48 + b - 0xB4)
    elseif b == 0xD9 then s = s .. "(sword)"
    elseif b == 0xFF or b == 0xFE then s = s .. " "
    else s = s .. string.format("<%02X>", b) end
  end
  return s
end
local function sameTiles(a, b)
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
-- where ten tiles stand in a row in the battle's BG3 maps (VRAM words), and the ten tiles at a place
local function tilesAt(w)
  local t = {}
  for i = 0, 9 do t[#t + 1] = emu.readWord((w + i) * 2, emu.memType.snesVideoRam) & 0xFF end
  return t
end
local function findTiles(seq)
  local vr, out = emu.memType.snesVideoRam, {}
  for w = 0x6000, 0x7FF0 do
    if (emu.readWord(w * 2, vr) & 0xFF) == seq[1] and sameTiles(seq, tilesAt(w)) then out[#out + 1] = w end
  end
  return out
end
local function learned() return sw(SW_STAB) == 1 or sw(SW_RUIN) == 1 end
local function wantList(seat)
  local rows, room = { { id = ROW_RUNIC, price = 0 } }, learned() and 7 or 8
  for _, b in ipairs(bladeRows(seat)) do
    if #rows < room then rows[#rows + 1] = { id = b.id, price = b.price } end
  end
  if learned() then rows[#rows + 1] = { id = ROW_BREAK, price = BREAK_MP } end
  return rows
end
-- the open list, in row order: the k-th row sits in cell (k & 3) * 2 + k // 4 (down the left column, then the right)
local function readList()
  local t = {}
  for k = 0, 7 do
    local c = (k & 3) * 2 + (k >> 2)
    t[#t + 1] = { id = H.readByte(0x4005 + c * 3), price = H.readByte(0x4006 + c * 3),
      flags = H.readByte(0x4007 + c * 3) }
  end
  return t
end
local function listText(rows)
  local t = {}
  for k = 1, 8 do
    local r = rows[k]
    t[#t + 1] = (r == nil or r.id == 0xFF) and "--" or string.format("%02X/%d/%02X", r.id, r.price, r.flags or 0x02)
  end
  return table.concat(t, " ")
end
local function rowOf(rows, id)
  for _, r in ipairs(rows) do if r.id == id then return r end end
end
local function hasRow(rows, id) return rowOf(rows, id) ~= nil end
-- an ally's spell to cast into her stance, the cheapest it can pay for at `boost`: Runic can absorb it (MagicProp
-- +3 bit 3), its cursor opens on the monsters (+0 bit 6), it neither kills nor petrifies (+10), and it carries
-- one element (not `avoid`; the head of its line when `head`) or none
local function allySpell(elemental, avoid, boost, head)
  local best
  boost = boost or 0
  for s = 0, 3 do
    local who = H.readByte(0x3ED8 + s * 2)
    local magicRow = false
    for r = 0, 3 do
      if H.readByte(0x202E + s * 12 + r * 3) == MAGIC and (H.readByte(0x202E + s * 12 + r * 3 + 1) & 0x80) == 0 then
        magicRow = true
      end
    end
    if s ~= S.celes and who ~= 0xFF and standing(s) and magicRow and bank(s) >= boost then
      for _, sp in ipairs(spellRows(s)) do
        local el = magicProp(sp.id, 1)
        local fits
        if elemental then fits = el ~= 0 and (el & (el - 1)) == 0 and el ~= avoid else fits = el == 0 end
        if head and lineOf(sp.id) == nil then fits = false end
        local cast = foldOf(sp.id, boost)
        local cost = spellPrice(s, cast)
        if fits and (magicProp(sp.id, 3) & 0x08) ~= 0 and (magicProp(sp.id, 0) & 0x40) ~= 0
           and (magicProp(sp.id, 10) & 0xC0) == 0 and cost <= mp(s) and (best == nil or cost < best.mp) then
          best = { who = who, seat = s, spell = sp.id, cast = cast, el = magicProp(cast, 1), mp = cost, boost = boost,
            tier = tierOf(cast) }
        end
      end
    end
  end
  return best
end

-- ---- the sign beside her name ----
local function signWant(r, b)
  if b ~= 0 then return SWORD end
  if r == 0 then return false end   -- blank
  local e = bitIndex(r)
  return ((0x21 | (GLYPH_PAL[e] << 2)) << 8) | GLYPH[e]
end
-- the staged cell (the name buffer's sixth cell) and the cell on screen (VRAM, one left of the row's boost cell)
local function signCells(seat)
  for row = 0, 3 do
    if H.readByte(0x64D6 + row) == seat then
      local staged = H.readByte(0x5B95 + row * 28 + 24) | (H.readByte(0x5B95 + row * 28 + 25) << 8)
      local vram = emu.readWord((0x7834 + row * 0x40 - 1) * 2, emu.memType.snesVideoRam)
      return staged, vram, row
    end
  end
end
local function signShows(want, staged, vram)
  if staged == nil then return false end
  if want == false then return (staged & 0xFF) == 0xFF and (vram & 0xFF) == 0xFF end
  return staged == want and vram == want
end

-- ---- staging (declared writes; the header says why) ----
local STAGED = { 0x3BE0, 0x3BCC, 0x3BCD, 0x3BE1, 0x3E9C, 0x3E38, 0x3E39, 0x3E88, 0x3E89 }
local function stage(weak, absorb, null, half)
  local y = monY()
  if S.orig == nil then
    S.orig = { hp = H.readWord(0x3BF4 + y), max = H.readWord(0x3C1C + y), pendEl = H.readByte(0xED45 + S.slot * 2) }
    for _, a in ipairs(STAGED) do S.orig[a] = H.readByte(a + y) end
    say("the body in slot %d as dealt: HP %d/%d, weak %02X absorb %02X null %02X half %02X, class keys %02X, "
      .. "shields %d/%d", S.slot, S.orig.hp, S.orig.max, S.orig[0x3BE0], S.orig[0x3BCC], S.orig[0x3BCD],
      S.orig[0x3BE1], S.orig[0x3E9C], S.orig[0x3E38], S.orig[0x3E39])
  end
  -- weak, absorb, null, half; no class weakness; nine shields, not Broken; no element revealed or about to be
  for _, c in ipairs({ { 0x3BE0 + y, weak }, { 0x3BCC + y, absorb }, { 0x3BCD + y, null }, { 0x3BE1 + y, half },
      { 0x3E9C + y, 0 }, { 0x3E38 + y, 9 }, { 0x3E39 + y, 9 }, { 0x3E88 + y, 0 }, { 0x3E89 + y, 0 },
      { 0xED45 + S.slot * 2, 0 } }) do
    H.writeByte(c[1], c[2])
  end
  for _, a in ipairs({ 0x3BF4 + y, 0x3C1C + y }) do H.writeWord(a, 30000) end
  S.staged = { weak = weak, absorb = absorb, null = null, half = half }
end
-- the body as the tomb dealt it, before the battle is fought out
local function unstage()
  if S.orig == nil or S.slot == nil or not inBattle() then return end
  local y = monY()
  for _, a in ipairs(STAGED) do H.writeByte(a + y, S.orig[a]) end
  local hp = math.min(S.orig.hp, H.readWord(0x3BF4 + y))
  for _, c in ipairs({ { 0x3BF4 + y, hp }, { 0x3C1C + y, S.orig.max } }) do H.writeWord(c[1], c[2]) end
  say("the body in slot %d put back as dealt (HP %d/%d)", S.slot, hp, S.orig.max)
  S.orig = nil
end
-- the two switches that teach Break Blade
local SWITCHES = { { addr = 0x1E80 + (SW_STAB >> 3), bit = 1 << (SW_STAB & 7) },
  { addr = 0x1E80 + (SW_RUIN >> 3), bit = 1 << (SW_RUIN & 7) } }
local function setSwitches(stab, ruin)
  for i, on in ipairs({ stab, ruin }) do
    local c = SWITCHES[i]
    H.writeByte(c.addr, (H.readByte(c.addr) & ~c.bit & 0xFF) | (on and c.bit or 0))
  end
end
-- CELES Muddled, Runic her one command: held every frame (a blow cures Muddle) until the engine has picked
local function holdMuddle()
  local e = ent()
  for _, c in ipairs({ { 0x3EE5 + e, H.readByte(0x3EE5 + e) | 0x20 }, { 0x202E + S.celes * 12, RUNIC },
      { 0x2031 + S.celes * 12, 0xFF }, { 0x2034 + S.celes * 12, 0xFF }, { 0x2037 + S.celes * 12, 0xFF } }) do
    H.writeByte(c[1], c[2])
  end
end
local function releaseMuddle(h)
  if not inBattle() then return end
  local e = ent()
  for _, c in ipairs({ { 0x3EE5 + e, H.readByte(0x3EE5 + e) & 0xDF }, { 0x202E + S.celes * 12, h.cmds[1] },
      { 0x2031 + S.celes * 12, h.cmds[2] }, { 0x2034 + S.celes * 12, h.cmds[3] },
      { 0x2037 + S.celes * 12, h.cmds[4] } }) do
    H.writeByte(c[1], c[2])
  end
end
-- her MP pool, for check 4b (and put back after it)
local function setMp(v) H.writeWord(0x3C08 + ent(), v) end

-- ---- observers ----
-- A value its routine has yet to write when the hook at the routine's head fires is read two frame callbacks
-- on: the battle code does not keep to frames, so the routine can finish after the next frame has begun
-- (measured: Ot6ActionEnd entered on f18754, Break Blade's turn written on f18755, suite/dev03-trace)
local function later(fn) S.settle[#S.settle + 1] = { at = S.tick + 2, fn = fn } end
local function arm()
  local function on(addr, fn) emu.addMemoryCallback(fn, emu.callbackType.exec, addr, addr) end
  local function reg(r) return emu.getState()["cpu." .. r] & 0xFF end
  local function her() return S.celes ~= nil and S.celes * 2 or -1 end

  -- her action, from its begin (ExecCmd's head) to its end: what it was and what it moved
  on(H.sym("Ot6BpBegin"), function()
    if reg("x") ~= her() or (H.readByte(0xB1) & 1) == 1 then return end
    if S.cur ~= nil then S.cur.begins = S.cur.begins + 1; return end
    local e = her()
    S.cur = { f0 = H.frame, cmd = H.readByte(0xB5), b6 = H.readByte(0xB6), mp0 = mp(S.celes), bank0 = bank(S.celes),
      pend0 = pend(S.celes), rune0 = rune(), tier0 = tier(), bb0 = bblade(), stance0 = stance(),
      st2 = H.readByte(0x3EE5 + e), begins = 1, passes = 0, hit0 = #S.hits + 1, pal0 = #S.pals + 1,
      arm0 = #S.arms + 1 }
    -- the body as the check's Fight needs it, staged again as the Fight begins: between the plan's start and
    -- her swing an ally out of control can have hit it (a Zombied SABIN's eight blows took eight shields,
    -- suite/dev07)
    if S.restage ~= nil and S.cur.cmd == FIGHT and S.slot ~= nil then
      stage(S.restage[1], S.restage[2], S.restage[3], S.restage[4])
    end
    if S.slot ~= nil then S.cur.hp0, S.cur.sh0 = monHp(), shields() end
    S.acts[#S.acts + 1] = S.cur
    -- check 9b's staging: Break Blade, picked at three points, finds two as its action begins
    if S.lower and S.cur.cmd == RUNIC and S.cur.b6 == ROW_BREAK and S.cur.pend0 == 3 then
      S.lower = nil
      H.writeByte(0x3E9D + e, 2)
      S.cur.lowered = pend(S.celes)
    end
  end)
  on(H.sym("Ot6ActionEnd"), function()
    if reg("x") ~= her() then return end
    local a = S.cur
    if a == nil then
      a = { bare = true, f0 = H.frame, hit0 = #S.hits + 1, pal0 = #S.pals + 1, arm0 = #S.arms + 1, bb0 = bblade(),
        rune0 = rune(), tier0 = tier() }
      S.acts[#S.acts + 1] = a
    end
    S.cur, S.hit = nil, nil
    a.f1, a.mp1, a.bbEnd, a.runeEnd, a.stance1 = H.frame, mp(S.celes), bblade(), rune(), stance()
    a.hit1, a.pal1, a.arm1 = #S.hits, #S.pals, #S.arms
    if S.slot ~= nil then a.hp1, a.sh1 = monHp(), shields() end
    -- the charge and Break Blade's turn are taken inside Ot6ActionEnd: read once it has run (later())
    later(function()
      a.bank2, a.pend2, a.bb2, a.rune2, a.tier2, a.settled = bank(S.celes), pend(S.celes), bblade(), rune(), tier(),
        true
    end)
  end)
  -- Cmd_0b: tyx, jsr, jsl Ot6RuneExec, bcs.  The attack byte as the command begins (an engine-chosen Runic's
  -- $00), and at the bcs the banner id Ot6RuneExec leaves there
  local cmd0b = H.sym("Cmd_0b")
  local shape = {}
  for _, o in ipairs({ 0, 1, 4, 8 }) do
    shape[#shape + 1] = string.format("%02X", H.readRomByte((cmd0b & 0x3FFFFF) + o))
  end
  H.assertEq(table.concat(shape, " "), "BB 20 22 B0", "Cmd_0b is tyx, jsr, jsl Ot6RuneExec, bcs: the banner id is "
    .. "read at the bcs")
  on(cmd0b, function()
    if reg("y") ~= her() or S.cur == nil then return end
    S.cur.cmd0b = H.readByte(0xB6)
    if S.hold ~= nil and S.hold.on and S.hold.seen == nil then S.hold.seen = S.cur end
  end)
  on(cmd0b + 8, function()
    if reg("x") == her() and S.cur ~= nil then S.cur.banner = H.readByte(0xB6) end
  end)
  on(H.sym("Ot6RuneExec"), function()
    if reg("x") == her() and S.cur ~= nil then S.cur.exec = H.readByte(0xB6) end
  end)
  -- Ot6RuneArm: A the element bits, B the tier
  on(H.sym("Ot6RuneArm"), function()
    if reg("y") ~= her() then return end
    local a16 = emu.getState()["cpu.a"]
    S.arms[#S.arms + 1] = { f = H.frame, a = a16 & 0xFF, tier = (a16 >> 8) & 0xFF, tick = S.tick }
    S.armedNow = a16 & 0xFF
    S.ranOut = nil   -- (armed anew: no longer the rune a Break Blade ended over)
  end)

  -- a Runic absorb of hers: the spell's element byte, and the rune and its tier before and after
  emu.addMemoryCallback(function(_, v)
    S.casts[#S.casts + 1] = { v = v, cmd = H.readByte(0x3A7C), counter = (H.readByte(0xB1) & 1) == 1,
      b8 = H.readByte(0xB8), b9 = H.readByte(0xB9), f = H.frame }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  on(H.sym("Ot6RunicBP"), function()
    if reg("y") ~= her() then return end
    local ab = { f = H.frame, el = H.readByte(0x11A1), b6 = H.readByte(0xB6), rune0 = rune(), tier0 = tier(),
      cast = S.casts[#S.casts], arm0 = #S.arms + 1 }
    S.absorbs[#S.absorbs + 1] = ab
    later(function() ab.rune1, ab.tier1, ab.arm1, ab.settled = rune(), tier(), #S.arms, true end)
    say("f%d CELES absorbs spell $%02X (element byte %02X); her rune was %02X at tier %d", ab.f, ab.b6, ab.el,
      ab.rune0, ab.tier0)
  end)

  -- her hits: which pass (a weapon swing, or a spell or item pass), and per target the element byte, the
  -- damage before the weak branch's multiplier (Ot6RuneWeakMul, entered only on that branch) and after it
  -- (Ot6HitJoin), Ot6Chip, and the shields the hit took
  on(H.sym("Ot6WeaponClass"), function()
    local x = reg("x")
    S.cls = { swing = x < 8, ent = x & 0xFE, hand = x & 1 }
    if S.cur ~= nil and (x & 0xFE) == her() then S.cur.passes = S.cur.passes + 1 end
  end)
  on(H.sym("Ot6SkillClass"), function() S.cls = { swing = false } end)
  on(H.sym("Ot6ItemClass"), function() S.cls = { swing = false } end)
  on(H.sym("Ot6TargetPre"), function()
    S.hit = nil
    local x, y = reg("x"), reg("y")
    if x ~= her() then return end
    S.hit = { f = H.frame, y = y, swing = S.cls ~= nil and S.cls.swing and S.cls.ent == x, hand = S.cls and S.cls.hand,
      s0 = y >= 8 and H.readByte(0x3E38 + y) or 0, bb = bblade(), chip = false, weak = false, joined = false }
    S.hits[#S.hits + 1] = S.hit
  end)
  on(H.sym("Ot6Chip"), function() if S.hit ~= nil and reg("y") == S.hit.y then S.hit.chip = true end end)
  on(H.sym("Ot6RuneWeakMul"), function()
    if S.hit ~= nil and reg("y") == S.hit.y then S.hit.weak, S.hit.pre = true, H.readWord(0xF0) end
  end)
  on(H.sym("Ot6HitJoin"), function()
    local h = S.hit
    if h == nil or reg("x") ~= her() or reg("y") ~= h.y then return end
    h.joined, h.el, h.dmg, h.f2 = true, H.readByte(0x11A1), H.readWord(0xF0), H.readByte(0xF2)
    h.rs, h.add, h.bs = H.readByte(RUNESWING), H.readByte(RUNEADD), H.readByte(BLADESWING)
  end)
  emu.addMemoryCallback(function(a, v)
    local h = S.hit
    if h ~= nil and (a & 0xFFFF) == 0x3E38 + h.y then h.sLast = v end
  end, emu.callbackType.write, 0x7E3E40, 0x7E3E4B)

  -- her swing's colours: the weapon's own as InitWeaponAnim hands them over, and what was loaded
  local pal = nil
  on(H.sym("Ot6SwingPal_ext"), function()
    pal = { f = H.frame, own = reg("a"), ownHit = H.readByte(0x626F), flags = H.readByte(0x2C6E),
      who = H.readByte(0x2C6F) & 3, other = H.readByte(0x62D0), mask = H.readByte(0x613E) }
  end)
  on(H.sym("LoadSpriteAnimPal"), function()
    local p = pal
    pal = nil
    if p == nil or p.f ~= H.frame or p.other ~= 0 or (p.flags & 0x80) ~= 0 or p.who ~= S.celes then return end
    p.used, p.usedHit = reg("a"), H.readByte(0x626F)
    S.pals[#S.pals + 1] = p
    if S.wantShot ~= nil and p.used ~= p.own and S.slot ~= nil and p.mask == (1 << S.slot) then
      S.shots[#S.shots + 1] = { at = S.tick + 20, tag = S.wantShot }
      S.wantShot = nil
    end
  end)

  -- Ot6Boost's sounds: the ching of a point taken ($6281) and the buzz of one refused ($95, a direct-page
  -- store, so both views are watched: battle_spellboost_mp's attribution)
  emu.addMemoryCallback(function(_, v) if v ~= 0 then S.ching = S.ching + 1 end end, emu.callbackType.write,
    0x7E6281, 0x7E6281)
  for _, page in ipairs({ 0x000000, 0x7E0000 }) do
    emu.addMemoryCallback(function(_, v) if v ~= 0 then S.buzz = S.buzz + 1 end end, emu.callbackType.write,
      page + 0x95, page + 0x95)
  end
end

-- once a frame: the values that settle after their hook, the rune's life (it changes only where Ot6RuneArm
-- set it; what it read on the battle's last frame and on the next battle's first), the sign's cells against
-- the rune, the sounds as R is first pressed on a list row, the standing body staged the moment it stands
-- alone, and the Muddle hold
local function pump()
  S.tick = S.tick + 1
  if #S.settle > 0 then
    local t = S.settle
    S.settle = {}
    for _, e in ipairs(t) do
      if e.at <= S.tick then e.fn() else S.settle[#S.settle + 1] = e end
    end
  end
  if not inBattle() then S.out = true end
  local active = H.battleActive()
  local seat = active and seatOf(CELES) or nil
  if seat ~= nil then
    S.celes = seat
    local r, b, t = H.readByte(RUNE + seat * 2), H.readByte(BREAKBLADE + seat * 2), H.readByte(RUNETIER + seat * 2)
    if S.out ~= false then
      -- the battle's first lit frame (the field stood between it and the battle before)
      S.out = false
      S.starts[#S.starts + 1] = { f = H.frame, rune = r, tier = t, bb = b, prev = S.lastActive,
        prevArmed = S.armedNow }
      S.runeSeen, S.sign, S.armedNow, S.lastActive = r, nil, 0, nil
    end
    if r ~= S.runeSeen then
      -- (Ot6RuneArm entered within the last frames, with this value)
      local last = S.arms[#S.arms]
      if last == nil or last.a ~= r or S.tick - last.tick > 3 then
        S.runeViol[#S.runeViol + 1] = string.format("f%d %02X -> %02X", H.frame, S.runeSeen, r)
      end
      S.runeSeen = r
    end
    if b == 0 and S.bbSeen ~= nil and S.bbSeen ~= 0 and r ~= 0 then S.ranOut = r end   -- Break Blade ended, rune held
    S.bbSeen = b
    S.lastActive = { f = H.frame, rune = r, tier = t, bb = b }
    local want = signWant(r, b)
    local sg = S.sign
    if sg == nil or sg.want ~= want then
      sg = { want = want, since = S.tick, f = H.frame, miss = 0 }
      S.sign = sg
    end
    local staged, vram = signCells(seat)
    if signShows(want, staged, vram) then
      if not sg.shown then
        sg.shown, sg.lag = true, S.tick - sg.since
        S.signLags[#S.signLags + 1] = sg
      end
    elseif sg.shown then
      sg.miss = sg.miss + 1
    end
  end
  if S.plan ~= nil then
    for _, q in ipairs(S.plan) do
      if q.listR ~= nil and q.listRn ~= nil and q.snd0 == nil then q.snd0 = { S.ching, S.buzz } end
    end
  end
  if S.thinning and S.slot == nil and active then
    local m, n, at = liveMask(), 0, nil
    for s = 0, 5 do if (m >> s) & 1 == 1 then n, at = n + 1, s end end
    if n == 1 then
      S.slot = at
      stage(0, 0, 0, 0)
      say("f%d one monster stands alone, in slot %d: the body the checks are made on", H.frame, at)
    end
  end
  if S.hold ~= nil and S.hold.on and inBattle() then holdMuddle() end
  for i = #S.shots, 1, -1 do
    if S.tick >= S.shots[i].at then
      H.screenshot(S.shots[i].tag)
      table.remove(S.shots, i)
    end
  end
end

-- ---- the walk, the hand-over and the fight-out (battle_runicblade's) ----
local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end
-- why the checks cannot go on in this battle, or nil: CELES down (Wound, Petrify, Zombie or 0 HP) or under a
-- third of her max HP, or two of her allies out of the fight.  One ally fallen or made a Zombie is the others'
-- care to raise (M.newSpinnerCare: a Fenix Down, a Revivify), with one monster left to hit them
local function danger()
  if not inBattle() or S.celes == nil then return nil end
  local out = 0
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local hp, mx, st1 = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2), H.readByte(0x3EE4 + s * 2)
      local down = hp == 0 or (st1 & 0xC2) ~= 0
      if s == S.celes and (down or (mx > 0 and hp < mx / 3)) then
        return string.format("CELES at %d/%d HP, status1 $%02X", hp, mx, st1)
      end
      if down then out = out + 1 end
    end
  end
  if out >= 2 then return string.format("%d of her allies are out of the fight", out) end
  return nil
end
local function fightOut(tag)
  local F = nil
  return H.withReset(H.driveUntil(function() return not inBattle() end, 60000, {
    H.call(function()
      if F == nil then
        F = H.newFightDriver(tag, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55,
          setzer = false })
      end
      F.frame()
    end),
  }, tag .. ": the battle fought out"), function() if F then F.idle() end; F = nil end)
end

-- the checks can go on: the battle is up and not handed over, CELES stands, and the body stands
local function usable()
  return inBattle() and S.handed == nil and S.celes ~= nil and S.slot ~= nil and standing(S.celes)
    and (liveMask() >> S.slot) & 1 == 1
end
local function mark()
  return { f = H.frame, acts = #S.acts, hits = #S.hits, pals = #S.pals, absorbs = #S.absorbs, arms = #S.arms,
    casts = #S.casts, mp = mp(S.celes), bank = bank(S.celes), rune = rune(), tier = tier(), bb = bblade() }
end
-- her action that followed the plan's last pick has ended (and its charge has settled)
local function lastActionDone()
  local k = H.vars.kit[#H.vars.kit]
  if k == nil then return false end
  for i = #S.acts, 1, -1 do
    local a = S.acts[i]
    if a.f0 < k.frame then return false end
    if a.settled then return true end
  end
  return false
end
-- her first action since the mark that fits
local function actSince(m, fits)
  for i = m.acts + 1, #S.acts do
    local a = S.acts[i]
    if not a.bare and a.settled and fits(a) then return a, i end
  end
end
-- one kit plan played in the battle that is up; ends when the plan is spent and opts.done() (default: at once),
-- when nothing has come of its last pick for 1500 frames, at its budget, when opts.giveUp() says so, or when the
-- party is in danger
local function play(tag, build, opts)
  opts = opts or {}
  local plan, ended, t0 = {}, false, 0
  local kitOpts = { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = opts.onList,
    others = opts.others, cureAllies = true,
    planDone = function()
      if opts.done == nil or opts.done() then return true end
      local last = H.vars.kit[#H.vars.kit]
      if last ~= nil and H.frame > last.frame + 1500 then
        say("f%d %s: nothing came of the last pick in 1500 frames", H.frame, tag)
        return true
      end
      return false
    end,
    giveUp = function()
      if opts.giveUp ~= nil and opts.giveUp() then return true end
      if H.frame > t0 + (opts.budget or 12000) then
        say("f%d %s: left after %d frames", H.frame, tag, H.frame - t0)
        return true
      end
      return false
    end }
  return H.cond(function() return S.handed == nil and inBattle() end, {
    H.call(function()
      for i = #plan, 1, -1 do plan[i] = nil end
      for _, e in ipairs(build()) do plan[#plan + 1] = e end
      S.plan, S.mark, t0 = plan, mark(), H.frame
    end),
    H.withReset(H.driveUntil(function()
      if ended then return true end
      S.handed = S.handed or danger()
      return S.handed ~= nil
    end, 70000, {
      H.kitBattle(plan, kitOpts),
      H.call(function() ended = true end),
    }, tag .. ", or the party in danger"), function() ended = false end),
    H.cond(function() return S.handed == nil and inBattle() end, { H.waitFrames(opts.settle or 30) }, {}),
  }, {})
end
local function check(fn) return H.call(function() if usable() then fn() end end) end
-- a check's steps, taken while it is open and its moment has come
local function block(key, when, steps)
  return H.cond(function() return not D[key] and usable() and (when == nil or when()) end, steps, {})
end
local function passed(key, ...)
  D[key] = true
  say("check %s made (battle %d): %s", key, S.battles, string.format(...))
  S.madeHere = (S.madeHere or 0) + 1
  if SPLIT ~= nil and S.madeHere >= SPLIT and key ~= "7c" and S.handed == nil then
    S.handed = string.format("the lab's split: %d check(s) made in this battle", S.madeHere)
  end
end

-- the blade row the checks arm her with (S.RB): the first element she can cast that neither of her weapons
-- carries and whose row climbs a three-tier line; picked with n points it arms tier 1 + min(n, 2)
local function bladeEntry(boost) return { who = CELES, cmd = RUNIC, row = S.RB.id, self = true, boost = boost or 0 } end
local function armedAt(t) return rune() == S.RB.bit and (t == nil or tier() == t) end
local function boostFor(t)
  for n = 0, 2 do if rowTier(S.RB, n) == t then return n end end
end

-- ---- reading one Fight of hers at the body ----
local function fightOf(m)
  local a = actSince(m, function(x) return x.cmd == FIGHT end)
  if a == nil then return nil end
  local r = { act = a, swings = {}, procs = {}, pals = {}, lost = 0 }
  for j = a.hit0, a.hit1 do
    local h = S.hits[j]
    if h.y == monY() and h.joined then
      h.loss = h.s0 - (h.sLast or h.s0)
      if h.swing then r.swings[#r.swings + 1] = h else r.procs[#r.procs + 1] = h end
      r.lost = r.lost + h.loss
    end
  end
  for j = a.pal0, a.pal1 do
    if S.pals[j].mask == (1 << S.slot) then r.pals[#r.pals + 1] = S.pals[j] end
  end
  return r
end
local function fightText(r)
  local function hits(t)
    local o = {}
    for _, h in ipairs(t) do
      o[#o + 1] = string.format("%02X/%s%d/-%d%s%s", h.el, h.weak and (h.pre .. ">") or "", h.dmg, h.loss,
        h.chip and "c" or "", (h.f2 & 1) == 1 and "H" or "")
    end
    return table.concat(o, " ")
  end
  local p = {}
  for _, v in ipairs(r.pals) do p[#p + 1] = string.format("%02X>%02X/%02X>%02X", v.own, v.used, v.ownHit, v.usedHit) end
  local a, y = r.act, monY()
  return string.format("f%d-%d at %d BP, rune %02X tier %d, Break Blade %d -> %d; body weak %02X absorb %02X null "
    .. "%02X half %02X; %d swing pass(es), swings landed [%s] (element/damage, before>after the weak branch's "
    .. "multiplier/shields/c=Ot6Chip H=heal), other passes [%s]; shields %d -> %d, HP %d -> %d, revealed %02X "
    .. "pending %02X; colours (own>used sprite/hit) [%s]", a.f0, a.f1, a.pend0, a.rune0, a.tier0, a.bb0, a.bb2,
    S.staged.weak, S.staged.absorb, S.staged.null, S.staged.half, a.passes, hits(r.swings), hits(r.procs), a.sh0,
    a.sh1, a.hp0, a.hp1, H.readByte(0x3E89 + y), H.readByte(0xED45 + S.slot * 2), table.concat(p, " "))
end
-- a Fight at the staged body, read and judged.  o.bytes() -> weak, absorb, null, half; o.boost; o.when();
-- o.judge(r) -> true when the check is made (it asserts); o.tier: her blade is armed at that tier first when
-- it is not (o.rune: at any tier)
local function fightCheck(key, o)
  return block(key, o.when, {
    play("check " .. key, function()
      S.restage = { o.bytes() }
      stage(S.restage[1], S.restage[2], S.restage[3], S.restage[4])
      local plan = {}
      if o.tier ~= nil and not armedAt(o.tier) then plan[#plan + 1] = bladeEntry(boostFor(o.tier))
      elseif o.rune and not armedAt(nil) then plan[#plan + 1] = bladeEntry(0) end
      plan[#plan + 1] = { who = CELES, cmd = FIGHT, boost = o.boost or 0, slot = S.slot }
      S.wantShot = o.shot
      return plan
    end, { done = lastActionDone, budget = 20000 }),
    H.call(function() S.restage = nil end),
    check(function()
      S.wantShot = nil
      local r = fightOf(S.mark)
      if r == nil then say("check %s: her Fight did not come; asked again", key); return end
      say("check %s: %s", key, fightText(r))
      if #r.swings == 0 then say("check %s: no swing landed; asked again", key); return end
      if o.tier ~= nil and (r.act.rune0 ~= S.RB.bit or r.act.tier0 ~= o.tier) then
        say("check %s: her blade was not armed at tier %d as she swung; asked again", key, o.tier)
        return
      end
      if o.judge(r) then passed(key, "%s", o.what) end
    end),
  })
end
local function palTables(i)
  return H.readRomByte((H.sym("Ot6SwingPalTbl") & 0x3FFFFF) + i),
    H.readRomByte((H.sym("Ot6SwingHitPalTbl") & 0x3FFFFF) + i)
end
-- the swings of a Fight the rune bites: every one carries the bit, takes the weak branch at the tier's
-- multiplier (x2, x3, x4: the damage word after Ot6RuneWeakMul against before it) and chips one shield
local function bites(tag, r, t)
  local bit, n = S.RB.bit, #r.swings
  H.assertEq(r.act.rune0, bit, tag .. ": her blade held the rune as she swung")
  H.assertEq(count(r.swings, function(h) return (h.el & bit) ~= 0 end), n, tag .. ": every swing's hit carries "
    .. "the rune's bit (Ot6HitJoin's $11A1)")
  H.assertEq(count(r.swings, function(h) return h.weak end), n, tag .. ": every swing took the weak branch "
    .. "(Ot6RuneWeakMul ran once a swing)")
  H.assertEq(count(r.swings, function(h) return h.weak and h.pre > 0 and h.dmg == h.pre * (t + 1) end), n,
    string.format("%s: a tier-%d rune's hit is x%d (the damage after the weak branch's multiplier against "
      .. "before it)", tag, t, t + 1))
  H.assertEq(count(r.swings, function(h) return h.chip and h.loss == 1 end), n, tag .. ": Ot6Chip ran once a swing "
    .. "and took one shield, whatever the tier")
  H.assertEq(count(r.procs, function(h) return (h.el & bit) ~= 0 end), 0, tag .. ": a pass that is no swing (her "
    .. "weapon's own spell) carries no rune")
  H.assertEq(r.act.sh0 - r.act.sh1, n, tag .. ": the shields fell by the number of swings")
end
-- the swings of a Fight the rune does not bite: no bit joined, no weak branch, the weapon's own colours
local function noBite(tag, r)
  local bit = S.RB.bit
  H.assertEq(r.act.rune0, bit, tag .. ": her blade held the rune as she swung")
  H.assertEq(count(r.swings, function(h) return (h.el & bit) ~= 0 end), 0, tag .. ": no swing carried the rune's bit "
    .. "(Ot6HitJoin's $11A1)")
  H.assertEq(count(r.swings, function(h) return h.chip or h.weak end), 0, tag .. ": no swing took the weak branch "
    .. "(Ot6Chip, Ot6RuneWeakMul)")
  H.assertEq(r.act.sh0 - r.act.sh1, 0, tag .. ": no shield was chipped")
  H.assertEq(#r.pals >= 1, true, tag .. ": her swing was drawn")
  H.assertEq(count(r.pals, function(p) return p.used ~= p.own or p.usedHit ~= p.ownHit end), 0, tag .. ": the swing "
    .. "is drawn in the weapon's own colours")
end
local function hurt(tag, r)
  H.assertEq(count(r.swings, function(h) return (h.f2 & 1) == 1 end), 0, tag .. ": no swing resolved as a heal")
  H.assertEq(count(r.swings, function(h) return h.dmg > 0 end), #r.swings, tag .. ": every landed swing did damage "
    .. "(Ot6HitJoin's $F0)")
  H.assertEq(r.act.hp1 < r.act.hp0, true, string.format("%s: the body's HP went down over her action (%d -> %d)", tag,
    r.act.hp0, r.act.hp1))
end

-- ---- the steps of one battle ----
local body = {}
local function add(t) for _, s in ipairs(t) do body[#body + 1] = s end end

-- the walk in, and the battle's own setup: who sits where, what she can cast, who casts into her stance
add({
  H.cond(function() return not inBattle() end, {
    H.call(function() S.ready = false end),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "control before the walk", 5),
    H.fieldCare({ tag = "spellblade: care before the walk", threshold = 0.95, mpBand = 0.5 }),
    walkToBattle(),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    H.waitFrames(30),
  }, {}),
  H.cond(function() return not S.ready end, {
    -- the party window has been drawn once (OT6_PIPLIVE), so the sign's cells are this battle's
    H.waitUntilSoft(function() return H.readByte(0xEEFC) ~= 0 or not inBattle() end, 600, "spellbladeWindow", 1),
    H.waitFrames(12),
    H.call(function()
      S.ready = true
      S.battles = S.battles + 1
      local budget = BATTLES + (SPLIT ~= nil and 40 or 0)
      H.assertEq(S.battles <= budget, true, string.format("every check made within %d battles (open: %s)", budget,
        (function() local t = {}; for _, k in ipairs(NEED) do if not D[k] then t[#t + 1] = k end end
          return table.concat(t, " ") end)()))
      S.celes = seatOf(CELES)
      H.assertEq(S.celes ~= nil and standing(S.celes), true, "CELES is seated and stands (the care before the walk saw "
        .. "to it)")
      S.handed, S.slot, S.orig, S.passes, S.leave, S.ranOut, S.hold = nil, nil, nil, 0, false, nil, nil
      S.madeHere, S.lower, S.restage = 0, nil, nil
      local e = ent()
      S.blades = bladeRows(S.celes)
      S.wElems = H.readByte(0x3B90 + e) | H.readByte(0x3B91 + e)
      S.RB = nil
      for _, b in ipairs(S.blades) do
        if S.RB == nil and (b.bit & S.wElems) == 0 and b.climbs and LINES[b.e][3] ~= LINES[b.e][2] then
          S.RB = b
        end
      end
      local t = {}
      for _, b in ipairs(S.blades) do
        t[#t + 1] = string.format("%s %d MP (spell $%02X%s)", ELEM[b.e], b.price, b.via,
          b.climbs and ", its line's head" or "")
      end
      say("battle %d (f%d): CELES seat %d, MP %d, bank %d, weapons' elements %02X %02X; she can cast %s; live "
        .. "monsters %02X; switches $0266 %d $00A4 %d", S.battles, H.frame, S.celes, mp(S.celes), bank(S.celes),
        H.readByte(0x3B90 + e), H.readByte(0x3B91 + e), table.concat(t, ", "), liveMask(), sw(SW_STAB), sw(SW_RUIN))
      H.assertEq(S.RB ~= nil, true, "CELES can cast the head of a three-tier spell line whose element neither of "
        .. "her weapons carries (Maduin's Fire, her own Ice): the blade row the checks arm")
      if S.battles == 1 then
        local ids, rom = {}, {}
        for _, sp in ipairs(spellRows(S.celes)) do ids[#ids + 1] = string.format("%02X", sp.id) end
        say("her battle spell list: %s (Break, $0C, %s)", table.concat(ids, " "),
          count(spellRows(S.celes), function(sp) return sp.id == 0x0C end) > 0 and "is in it" or "is not in it")
        for e2 = 0, 3 do
          for c = 0, 2 do
            rom[#rom + 1] = string.format("%02X", H.readRomByte((H.sym("Ot6FoldTbl") & 0x3FFFFF) + e2 * 3 + c))
          end
        end
        H.assertEq(table.concat(rom, " "), "00 05 09 01 06 0A 02 07 0B 03 08 08", "Ot6FoldTbl's first rows are the "
          .. "four lines a blade row climbs: Fire, Ice, Bolt (three tiers), Poison to Bio")
        H.assertEq(S.wElems ~= 0, true, "one of CELES's weapons carries an element (wor-tomb-v1's ThunderBlade): "
          .. "checks 5w and 10c's body weak to the weapon's own element")
        H.assertEq(allySpell(true, S.RB.bit, 0, true) ~= nil, true, "an ally can cast the head of a spell line that "
          .. "Runic absorbs (wor-tomb-v1's EDGAR wears Ramuh: Bolt)")
        H.assertEq(allySpell(false) ~= nil, true, "an ally can cast a spell without an element that Runic absorbs "
          .. "(EDGAR's Rasp, from Ramuh)")
      end
      -- 7c: the rune a battle ended holding is gone as the next opens, and so are its tier and its sign
      local st = S.starts[#S.starts]
      if st ~= nil and st.prev ~= nil and st.prevArmed ~= 0 then
        local staged, vram = signCells(S.celes)
        say("check 7c: the battle before ended at f%d with rune %02X at tier %d (last armed %02X, Break Blade %d); "
          .. "this one opened at f%d with rune %02X, tier %d, Break Blade %d; now rune %02X, sign cells staged %04X, "
          .. "VRAM %04X", st.prev.f, st.prev.rune, st.prev.tier, st.prevArmed, st.prev.bb, st.f, st.rune, st.tier,
          st.bb, rune(), staged or 0xFFFF, vram or 0xFFFF)
        H.assertEq(st.prev.rune, st.prevArmed, "7. the rune was still set on the battle's last frame, as last armed")
        H.assertEq(st.rune, 0, "7. the rune reads 0 on the next battle's first frame")
        H.assertEq(st.tier, 0, "7. its tier reads 0 on the next battle's first frame")
        H.assertEq(st.bb, 0, "7. Break Blade reads 0 on the next battle's first frame")
        H.assertEq(rune(), 0, "7. the rune is still 0 once the battle is up")
        H.assertEq(signShows(false, staged, vram), true, "7. the sign cell is blank as the next battle opens (staged "
          .. "and on screen)")
        if not D["7c"] then passed("7c", "the rune, its tier and its sign are gone as the next battle opens") end
      end
      S.thinning = not allMade()
    end),
    -- everyone Fights until one monster stands alone (the pump stages it that frame); then CELES Defends
    play("the formation thinned to one body", function()
      return { { who = CELES, defend = true, when = function() return S.slot ~= nil end } }
    end, { others = "thin", budget = 30000 }),
    H.call(function()
      S.thinning = false
      if inBattle() and S.handed == nil and S.slot == nil then S.handed = "no monster came to stand alone" end
    end),
  }, {}),
})

-- 11. the story switch, under one open command window (three peeks at the list)
do
  local seen, orig = {}, nil
  local function peek(i, stab, ruin)
    return {
      H.call(function()
        if i == 1 then
          seen, orig = {}, { H.readByte(SWITCHES[1].addr), H.readByte(SWITCHES[2].addr) }
        end
        if orig ~= nil then setSwitches(stab, ruin) end
      end),
      play("check 11, peek " .. i, function() return { { who = CELES, cmd = RUNIC, peek = true } } end, {
        onList = function()
          seen[i] = { rows = readList(), stab = sw(SW_STAB), ruin = sw(SW_RUIN) }
          say("check 11: switches $0266 %d $00A4 %d: the list reads %s", seen[i].stab, seen[i].ruin,
            listText(seen[i].rows))
        end }),
    }
  end
  local steps = {}
  for i, c in ipairs({ { false, false }, { true, false }, { false, true } }) do
    for _, s in ipairs(peek(i, c[1], c[2])) do steps[#steps + 1] = s end
  end
  steps[#steps + 1] = H.call(function()
    if orig == nil then return end
    for i = 1, 2 do H.writeByte(SWITCHES[i].addr, orig[i]) end
    say("check 11: the switch bytes put back (%02X %02X)", orig[1], orig[2])
    orig = nil
    if not (seen[1] and seen[2] and seen[3]) then
      say("check 11: the three peeks were not all made; asked again")
      return
    end
    H.assertEq(seen[1].stab + seen[1].ruin, 0, "11. both switches read clear under the first peek")
    H.assertEq(hasRow(seen[1].rows, ROW_BREAK), false, "11. with neither switch set the list has no Break Blade row")
    H.assertEq(seen[2].stab == 1 and seen[2].ruin == 0, true, "11. only $0266 reads set under the second peek")
    H.assertEq(hasRow(seen[2].rows, ROW_BREAK), true, "11. switch $0266 alone (the stab on the Floating Continent) "
      .. "teaches Break Blade")
    H.assertEq(seen[3].stab == 0 and seen[3].ruin == 1, true, "11. only $00A4 reads set under the third peek")
    H.assertEq(hasRow(seen[3].rows, ROW_BREAK), true, "11. switch $00A4 alone (the World of Ruin) teaches Break Blade")
    passed("11", "neither switch: no row; $0266 alone: the row; $00A4 alone: the row")
  end)
  add({ block("11", nil, steps) })
end

-- 1. the list
do
  local got = nil
  add({ block("1", nil, {
    H.call(function() got = nil end),
    play("check 1", function() return { { who = CELES, cmd = RUNIC, peek = true } } end, {
      onList = function()
        got = { mode = H.readByte(0x6168), rows = readList(), want = wantList(S.celes), pend = pend(S.celes) }
        H.screenshot("spellblade_list")
      end }),
    check(function()
      if got == nil then say("check 1: the list did not open; asked again"); return end
      say("check 1: mode %d, pending %d; the list reads %s; computed from her spell list and MagicProp: %s", got.mode,
        got.pend, listText(got.rows), listText(got.want))
      H.assertEq(got.pend, 0, "1. the list was opened with no boost pending")
      H.assertEq(got.mode, 7, "1. Runic opens the Rune Knight's list (w7e6168 = 7)")
      H.assertEq(listText(got.rows), listText(got.want), "1. the rows (id/price/flags): Runic, a blade row for each "
        .. "element she can cast, in bit order, at her cheapest spell of it, then Break Blade at 99 when learned")
      H.assertEq(hasRow(got.rows, ROW_BREAK), true, "1. Break Blade is listed (the World of Ruin's party has "
        .. "learned it)")
      passed("1", "%s", listText(got.rows))
    end),
  }) })
end

-- 2. an ally's elemental spell, absorbed, arms the blade at the spell's tier; a blade row replaces element and
--    tier (and 7b, the sign)
-- 3. a spell without an element, absorbed, leaves the rune
-- 8. a 3-BP Runic (RunicBlade) arms it too
local function ownCast(from, z)
  for i = from, #S.casts do
    local c = S.casts[i]
    if c.v == z.cast and c.cmd == MAGIC and not c.counter and c.b9 ~= 0 and c.b8 == 0 then return c end
  end
end
local function absorbOf(c)
  for i = #S.absorbs, 1, -1 do
    if S.absorbs[i].cast == c then return S.absorbs[i] end
  end
end
-- CELES raises Runic at `boost`, the ally casts z (pick()) into it.  Her blade is armed by a blade row first
-- when the absorb would otherwise arm what it already holds (so that the arming is seen), or, for a spell
-- without an element (bare = false), when it holds nothing to leave
local function intoStance(tag, boost, pick, bare)
  local z = nil
  return play(tag, function()
    z = pick()
    S.z = z
    if z == nil then say("%s: no ally can cast the spell now; asked again", tag); return {} end
    say("%s: seat %d (char $%02X) casts spell $%02X at %d BP (cast as $%02X: element byte %02X, tier %d, %d MP) "
      .. "into her stance", tag, z.seat, z.who, z.spell, z.boost, z.cast, z.el, z.tier, z.mp)
    local plan = {}
    if (z.el ~= 0 and rune() == z.el and tier() == z.tier) or (bare == false and rune() == 0) then
      plan[#plan + 1] = bladeEntry(0)
    end
    plan[#plan + 1] = { who = CELES, cmd = RUNIC, row = ROW_RUNIC, self = true, boost = boost }
    plan[#plan + 1] = { who = z.who, cmd = MAGIC, spell = z.spell, boost = z.boost, slot = S.slot }
    return plan
  end, { budget = 20000, done = function()
    if z == nil then return true end
    local c = ownCast(S.mark.casts + 1, z)
    if c == nil then return false end
    local ab = absorbOf(c)
    if ab ~= nil then return ab.settled == true end
    return H.frame > c.f + 240
  end })
end
-- the absorb of the ally's cast, with the arming Ot6RuneArm made of it (nil: none)
local function absorbed(tag)
  if S.z == nil then return nil end
  local c = ownCast(S.mark.casts + 1, S.z)
  local ab = c and absorbOf(c)
  if ab == nil then
    say("%s: the ally's spell was %s; asked again", tag, c and "cast, but her stance did not absorb it" or "not cast")
    return nil
  end
  ab.arm = S.arms[ab.arm1]
  if ab.arm1 < ab.arm0 then ab.arm = nil end
  say("%s: Ot6RunicBP ran for CELES at f%d on spell $%02X: element byte %02X; Ot6RuneArm %s; her rune %02X at tier "
    .. "%d -> %02X at tier %d", tag, ab.f, c.v, ab.el, ab.arm and string.format("took element %02X, tier %d",
      ab.arm.a, ab.arm.tier) or "did not run", ab.rune0, ab.tier0, ab.rune1, ab.tier1)
  return ab
end
-- an absorb at a tier: the ally's line head cast at `allyBoost` points
local function absorbTier(key, tag, allyBoost)
  return {
    intoStance(tag, 0, function() return allySpell(true, S.RB.bit, allyBoost, true) end),
    check(function()
      local ab = absorbed(tag)
      if ab == nil then return end
      local z = S.z
      H.assertEq(z.cast, LINES[lineOf(z.spell)][1 + allyBoost], string.format("%s. the ally's spell at %d BP is "
        .. "cast as its line's spell at that boost", key, allyBoost))
      H.assertEq(ab.b6, z.cast, key .. ". the spell absorbed is the one cast ($B6 at Ot6RunicBP)")
      H.assertEq(ab.el, z.el, key .. ". the absorbed spell's element byte is the ROM's (MagicProp +1)")
      H.assertEq(ab.rune0 ~= ab.el or ab.tier0 ~= z.tier, true, key .. ". her blade did not hold that element at "
        .. "that tier before the absorb")
      H.assertEq(ab.arm ~= nil and ab.arm.a == z.el and ab.arm.tier == z.tier, true, string.format("%s. the absorb "
        .. "arms the spell's element at the spell's tier (%d: Ot6RuneArm's A and B)", key, z.tier))
      H.assertEq(ab.rune1, z.el, key .. ". OT6_RUNE holds the absorbed element")
      H.assertEq(ab.tier1, z.tier, string.format("%s. OT6_RUNETIER holds the absorbed spell's tier (%d)", key, z.tier))
      S.absorbMade = { key = key, el = z.el, tier = z.tier }
    end),
  }
end
do
  local steps = { H.call(function() S.absorbMade = nil end) }
  for _, s in ipairs(absorbTier("2", "check 2", 0)) do steps[#steps + 1] = s end
  for _, s in ipairs({
    H.cond(function() return S.absorbMade ~= nil and S.absorbMade.key == "2" and usable() end, {
      play("check 2, the blade row", function() return { bladeEntry(0) } end, { done = lastActionDone }),
      check(function()
        local a = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == S.RB.id end)
        if a == nil then say("check 2: the blade row's action did not come; asked again"); return end
        local price = rowPrice(S.RB, 0)
        say("check 2: the %s blade row ($%02X, %d MP) at f%d-%d: rune %02X tier %d -> %02X tier %d, MP %d -> %d, bank "
          .. "%d -> %d, pending %d -> %d, banner id $%02X", ELEM[S.RB.e], S.RB.id, price, a.f0, a.f1, a.rune0,
          a.tier0, a.rune2, a.tier2, a.mp0, a.mp1, a.bank0, a.bank2, a.pend0, a.pend2, a.banner or 0xFF)
        H.assertEq(a.rune0, S.absorbMade.el, "2. her blade still held the absorbed element as the row began")
        H.assertEq(a.rune2, S.RB.bit, "2. a blade row replaces the rune with its own element")
        H.assertEq(a.tier2, 1, "2. picked with no boost it arms tier 1")
        H.assertEq(a.mp0 - a.mp1, price, "2. the blade row costs exactly its price (her cheapest spell of the "
          .. "element)")
        H.assertEq(a.pend0, 0, "2. the row was picked with no boost")
        H.assertEq(a.bank2, math.min(a.bank0 + 1, 5), "2. the bank is not charged (the turn's own point is earned)")
        H.assertEq(a.banner, S.RB.id, "2. at tier 1 the banner is the row's own ($B6 after Ot6RuneExec)")
        passed("2", "an ally's spell absorbed armed %02X at tier 1, the %s blade row replaced it with %02X for %d MP",
          S.absorbMade.el, ELEM[S.RB.e], S.RB.bit, price)
        -- 7b: the sign, within 8 frames of the arming, staged and on screen
        local want = signWant(S.RB.bit, 0)
        local sg = S.sign
        local staged, vram, row = signCells(S.celes)
        say("check 7b: the rune %02X wants sign %04X (menu row %d); it showed %s frame(s) after the rune changed "
          .. "(f%d); now staged %04X, VRAM %04X", S.RB.bit, want, row or -1, sg and tostring(sg.lag) or "?",
          sg and sg.f or 0, staged or 0, vram or 0)
        H.assertEq(sg ~= nil and sg.want == want and sg.f >= a.f0, true, "7. the sign watch followed this arming")
        H.assertEq(sg.shown == true and sg.lag <= 8, true, "7. the element's icon stands beside her name within 8 "
          .. "frames of the arming (the name buffer's sixth cell, and the cell in VRAM)")
        H.assertEq(staged, want, "7. the staged sign cell holds the element's icon in its colour")
        H.assertEq(vram, want, "7. the sign cell on screen holds the element's icon in its colour")
        H.screenshot("spellblade_sign")
        passed("7b", "sign %04X %d frame(s) after the arming", want, sg.lag)
      end),
    }, {}),
  }) do steps[#steps + 1] = s end
  add({ block("2", function() return bblade() == 0 end, steps) })
end

-- 5. the weak-only rule, one 0-BP Fight each, the rune at tier 1
add({
  fightCheck("5a", { tier = 1, when = function() return bblade() == 0 end, shot = "spellblade_swing",
    what = "weak: every swing carries the rune, is x2 and chips, in the element's colours",
    bytes = function() return S.RB.bit, 0, 0, 0 end,
    judge = function(r)
      local bit = S.RB.bit
      local sp, hp = palTables(S.RB.e)
      say("check 5a: the %s colours are sprite %02X, hit %02X (Ot6SwingPalTbl, Ot6SwingHitPalTbl)", ELEM[S.RB.e], sp,
        hp)
      bites("5a. weak", r, 1)
      local y = monY()
      H.assertEq((H.readByte(0x3E89 + y) | H.readByte(0xED45 + S.slot * 2)) & bit, bit, "5a. weak: the weakness is "
        .. "revealed (or pending its numeral)")
      H.assertEq(#r.pals >= 1, true, "5a. her swing was drawn")
      H.assertEq(count(r.pals, function(p) return p.used == sp end), #r.pals, "5a. weak: the swing is drawn in the "
        .. "element's palette (Ot6SwingPalTbl)")
      H.assertEq(count(r.pals, function(p) return p.usedHit == hp end), #r.pals, "5a. weak: the hit is drawn in the "
        .. "element's palette (Ot6SwingHitPalTbl)")
      return true
    end }),
  fightCheck("5b", { rune = true, when = function() return bblade() == 0 end,
    what = "not weak: the rune joins nothing",
    bytes = function() return 0, 0, 0, 0 end,
    judge = function(r) noBite("5b. not weak", r); return true end }),
  fightCheck("5c", { rune = true, when = function() return bblade() == 0 end,
    what = "weak and absorbing: nothing joins, and the body is hurt",
    bytes = function() return S.RB.bit, S.RB.bit, 0, 0 end,
    judge = function(r) noBite("5c. weak and absorbing", r); hurt("5c. weak and absorbing", r); return true end }),
  fightCheck("5d", { rune = true, when = function() return bblade() == 0 end,
    what = "weak and nulling: nothing joins, and the body is hurt",
    bytes = function() return S.RB.bit, 0, S.RB.bit, 0 end,
    judge = function(r) noBite("5d. weak and nulling", r); hurt("5d. weak and nulling", r); return true end }),
  fightCheck("5e", { rune = true, when = function() return bblade() == 0 end,
    what = "weak and halving: nothing joins",
    bytes = function() return S.RB.bit, 0, 0, S.RB.bit end,
    judge = function(r) noBite("5e. weak and halving", r); return true end }),
})

-- 3.
add({ block("3", function() return bblade() == 0 end, {
  intoStance("check 3", 0, function() return allySpell(false) end, false),
  check(function()
    local ab = absorbed("check 3")
    if ab == nil then return end
    H.assertEq(magicProp(S.z.spell, 1), 0, "3. the spell carries no element (MagicProp +1)")
    H.assertEq(ab.el, 0, "3. the absorbed spell's element byte is 0")
    H.assertEq(ab.rune0 ~= 0, true, "3. her blade held a rune before the absorb")
    H.assertEq(ab.arm, nil, "3. Ot6RuneArm did not run for it")
    H.assertEq(ab.rune1, ab.rune0, "3. a Runic absorb of a spell without an element leaves the rune")
    H.assertEq(ab.tier1, ab.tier0, "3. and its tier")
    passed("3", "spell $%02X absorbed, rune %02X at tier %d kept", S.z.spell, ab.rune1, ab.tier1)
  end),
}) })

-- 4. a blade row takes a boost
-- what the list shows for the blade row under the cursor, in VRAM: its name, where the row's own name stood
-- when the list was first read, and the price drawn after it (the digits in the cells that follow the name).
-- The list's own price cell (wItemList's Qty) is written when the list opens, at the boost then pending; an R
-- on the row redraws the row through Ot6RuneRowCost and leaves that cell, so the drawn price is what is read
local function rowShown(p)
  local b = S.RB
  local row = rowOf(readList(), b.id)
  local o = { pend = pend(S.celes), cell = row and row.price, r0 = p.listR0, r1 = p.listR1, mp = mp(S.celes),
    ching = p.snd0 and S.ching - p.snd0[1] or 0, buzz = p.snd0 and S.buzz - p.snd0[2] or 0, names = {}, tails = {} }
  if S.namePos == nil then S.namePos = findTiles(nameRecord(b.id)) end
  for _, w in ipairs(S.namePos) do
    o.names[#o.names + 1] = tilesAt(w)
    local tail, digits = {}, ""
    for i = 10, 14 do
      local c = emu.readWord((w + i) * 2, emu.memType.snesVideoRam) & 0xFF
      tail[#tail + 1] = c
      if c >= 0xB4 and c <= 0xBD then digits = digits .. string.char(48 + c - 0xB4) end
    end
    o.tails[#o.tails + 1] = tail
    if o.price == nil and digits ~= "" then o.price = tonumber(digits) end
  end
  return o
end
local function shownText(o)
  local t = {}
  for i, n in ipairs(o.names) do
    t[#t + 1] = string.format("\"%s|%s\" at VRAM $%04X", tilesText(n), tilesText(o.tails[i]), S.namePos[i])
  end
  return string.format("%d pending, price drawn %s (the list's cell %s), row %s", o.pend, tostring(o.price),
    tostring(o.cell), #t > 0 and table.concat(t, ", ") or "not found")
end
-- the row as it must read with o.pend points pending
local function rowJudge(tag, o)
  local b, n = S.RB, o.pend
  local want = nameRecord(rowNameId(b, n))
  H.assertEq(#o.names >= 1, true, tag .. ": the row's name was found in VRAM as the list opened")
  H.assertEq(o.price, rowPrice(b, n), string.format("%s: with %d point(s) pending the row's price is drawn as its "
    .. "line's spell's ($%02X: MagicProp's MP)", tag, n, rowSpell(b, n)))
  H.assertEq(count(o.names, function(t) return sameTiles(want, t) end) >= 1, true, string.format("%s: with %d "
    .. "point(s) pending the row is named \"%s\" (Ot6RuneName's record $%02X)", tag, n, tilesText(want),
    rowNameId(b, n)))
end
do
  local obs, onRow = {}, nil
  add({
    block("4a", function() return bblade() == 0 and mp(S.celes) >= rowPrice(S.RB, 2) end, {
      H.call(function() obs, onRow, S.namePos = {}, nil, nil end),
      play("check 4a", function()
        local function e(boost, listR) return { who = CELES, cmd = RUNIC, row = S.RB.id, peek = true, boost = boost,
          bank = 3, listR = listR } end
        return { e(0), e(0, 3), e(1), e(2), e(3) }
      end, { budget = 20000, onList = function(p)
        local o = rowShown(p)
        say("check 4a: the %s blade row with %d on the command window%s: %s", ELEM[S.RB.e], p.boost,
          p.listR and string.format(", then R x%d on the row (pending %s -> %s, %d ching(s), %d buzz(es))", p.listR,
            tostring(o.r0), tostring(o.r1), o.ching, o.buzz) or "", shownText(o))
        if p.listR ~= nil then
          onRow = o
          H.assertEq(o.buzz, 0, "4a. no R on a row that climbs is refused (her MP pays every tier)")
          H.assertEq(o.r1 - o.r0, o.ching, "4a. each R taken on the row raises the pending boost by one")
          if o.ching == 0 then return end   -- (no press reached the game: asked again)
        else
          H.assertEq(o.pend, p.boost, "4a. the list was opened at the boost raised on the command window")
          H.assertEq(o.cell, rowPrice(S.RB, o.pend), "4a. the list opens with the row priced at the boost pending "
            .. "(its price cell)")
          obs[o.pend] = o
        end
        rowJudge("4a", o)
        if o.pend == 2 and p.listR == nil then H.screenshot("spellblade_tier") end
      end }),
      check(function()
        if not (obs[0] and obs[1] and obs[2] and obs[3]) then
          say("check 4a: the list was not read at 0, 1, 2 and 3 points; asked again")
          return
        end
        if onRow == nil or onRow.ching == 0 then
          say("check 4a: no R on the row reached the game; asked again")
          return
        end
        H.assertEq(rowPrice(S.RB, 1) > rowPrice(S.RB, 0), true, "4a. the line's second spell costs more than its head")
        H.assertEq(obs[3].price, obs[2].price, "4a. a third point adds nothing: the price stays the top tier's")
        passed("4a", "prices %d/%d/%d/%d at 0-3 points; R on the row took %d point(s) and redrew it", obs[0].price,
          obs[1].price, obs[2].price, obs[3].price, onRow.ching)
      end),
    }),
  })
end
-- 4b. R adds no point her MP cannot pay for (#555): her pool one under the price of the first step that costs
-- more than the one before it, from the top
do
  local got, had, gate, staged = nil, nil, nil, false
  local function putBack()
    if staged and inBattle() then
      setMp(had)
      say("check 4b: her MP put back (%d)", had)
    end
    staged = false
  end
  add({ block("4b", function() return bblade() == 0 end, {
    H.call(function()
      got, had, gate, staged = nil, mp(S.celes), nil, false
      local p0, p1, p2 = rowPrice(S.RB, 0), rowPrice(S.RB, 1), rowPrice(S.RB, 2)
      if p2 > p1 then gate = { stop = 1, mp = p2 - 1 } elseif p1 > p0 then gate = { stop = 0, mp = p1 - 1 } end
      if gate == nil or had <= gate.mp then gate = nil; return end
      say("check 4b: the row costs %d/%d/%d at 0/1/2 points: with %d MP (she has %d) R must stop at %d", p0, p1, p2,
        gate.mp, had, gate.stop)
    end),
    play("check 4b", function()
      if gate == nil then return {} end
      -- (staged as her cursor rests on Runic, the bank filled, and put back as soon as the row is read)
      return { { who = CELES, cmd = RUNIC, row = S.RB.id, peek = true, boost = 0, bank = 2, listR = 3,
        openWhen = function()
          if not staged then
            had, staged = mp(S.celes), true
            setMp(gate.mp)
          end
          return true
        end } }
    end, { onList = function(p)
      got = rowShown(p)
      putBack()
    end }),
    H.call(function()
      putBack()
      if gate == nil then return end
      if got == nil or not usable() then say("check 4b: the row was not reached; asked again"); return end
      say("check 4b: R x3 on the row with %d MP: pending %s -> %s, %d ching(s), %d buzz(es); %s", got.mp,
        tostring(got.r0), tostring(got.r1), got.ching, got.buzz, shownText(got))
      if got.ching + got.buzz < gate.stop + 1 then
        say("check 4b: too few presses reached the game; asked again")
        return
      end
      H.assertEq(got.mp, gate.mp, "4b. her MP stood one under the next tier's price as R was pressed")
      H.assertEq(got.r0, 0, "4b. no boost was pending as the list opened")
      H.assertEq(got.ching, gate.stop, "4b. R takes the point(s) her MP pays for")
      H.assertEq(got.buzz >= 1, true, "4b. and the next is refused (a buzz)")
      H.assertEq(got.r1, gate.stop, string.format("4b. R adds no point her MP cannot pay for: the pending boost "
        .. "stops at %d (#555)", gate.stop))
      H.assertEq(got.price, rowPrice(S.RB, gate.stop), "4b. and the row keeps the price of the tier she can pay")
      passed("4b", "with %d MP R stopped at %d point(s)", gate.mp, gate.stop)
    end),
  }) })
end
-- 4c. confirmed at a boost: the tier, its price, the boost spent, the tier's banner
local function confirmAt(key, boost)
  return block(key, function() return bblade() == 0 end, {
    play("check " .. key, function()
      local plan = {}
      -- (her blade already holds this very tier: tier 1 first, so that the row is seen to arm)
      if armedAt(rowTier(S.RB, boost)) then plan[#plan + 1] = bladeEntry(0) end
      plan[#plan + 1] = bladeEntry(boost)
      return plan
    end, { done = lastActionDone, budget = 20000 }),
    check(function()
      local b = S.RB
      local a = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == b.id and x.pend0 == boost end)
      if a == nil then say("check %s: the blade row's action did not come; asked again", key); return end
      local t, price, arming = rowTier(b, boost), rowPrice(b, boost), S.arms[a.arm1]
      if a.arm1 < a.arm0 then arming = nil end
      local banner = ROW_TIERED + b.e * 2 + (t - 2)
      say("check %s: the %s blade row picked at %d BP (f%d-%d): Ot6RuneArm %s; rune %02X tier %d -> %02X tier %d, MP "
        .. "%d -> %d (spell $%02X costs %d), bank %d -> %d, pending -> %d, banner id $%02X (\"%s\")", key, ELEM[b.e],
        a.pend0, a.f0, a.f1, arming and string.format("took element %02X, tier %d", arming.a, arming.tier)
        or "did not run", a.rune0, a.tier0, a.rune2, a.tier2, a.mp0, a.mp1, rowSpell(b, boost), price, a.bank0,
        a.bank2, a.pend2, a.banner or 0xFF, a.banner and a.banner >= ROW_TIERED and a.banner <= ROW_BREAK
        and tilesText(nameRecord(a.banner)) or "?")
      H.assertEq(t, 1 + boost, string.format("%s. the line has a tier %d (the row at %d BP)", key, 1 + boost, boost))
      H.assertEq(a.rune0 ~= b.bit or a.tier0 ~= t, true, key .. ". her blade did not hold that tier before")
      H.assertEq(arming ~= nil and arming.a == b.bit and arming.tier == t, true, string.format("%s. a blade row "
        .. "confirmed at %d BP arms tier %d (Ot6RuneArm's A and B)", key, boost, t))
      H.assertEq(a.rune2, b.bit, key .. ". OT6_RUNE holds the row's element")
      H.assertEq(a.tier2, t, string.format("%s. OT6_RUNETIER holds tier %d", key, t))
      H.assertEq(a.mp0 - a.mp1, price, key .. ". it costs exactly the tier spell's MP")
      H.assertEq(a.bank2, a.bank0 - boost, key .. ". it spends the boost (and the turn earns no point)")
      H.assertEq(a.pend2, 0, key .. ". nothing is left pending")
      H.assertEq(a.banner, banner, key .. ". the banner is the tier's ($B6 after Ot6RuneExec: $C8 + line * 2 + "
        .. "(tier - 2))")
      passed(key, "%d BP: tier %d for %d MP, the boost spent, banner $%02X", boost, t, price, banner)
    end),
  })
end
-- 5t2, 5t3: what the tier buys; 5w: a hit the rune does not bite is x2 at most
local function tierFight(key, t)
  return fightCheck(key, { tier = t, when = function() return bblade() == 0 and boostFor(t) ~= nil end,
    what = string.format("a tier-%d rune's hit is x%d, and chips one shield", t, t + 1),
    bytes = function() return S.RB.bit, 0, 0, 0 end,
    judge = function(r) bites(key .. ". weak", r, t); return true end })
end
add({
  confirmAt("4c1", 1),
  tierFight("5t2", 2),
  confirmAt("4c2", 2),
  tierFight("5t3", 3),
  fightCheck("5w", { tier = 3, when = function() return bblade() == 0 and boostFor(3) ~= nil end,
    what = "weak to the weapon's own element only: x2, whatever the rune's tier",
    bytes = function() return S.wElems, 0, 0, 0 end,
    judge = function(r)
      local own = count(r.swings, function(h) return (h.el & S.wElems) ~= 0 end)
      if own == 0 then say("check 5w: no swing of the elemental hand landed; asked again"); return false end
      H.assertEq(count(r.swings, function(h) return (h.el & S.RB.bit) ~= 0 or (h.bs & 0x02) ~= 0 end), 0, "5w. the "
        .. "rune joins no swing on a body that is not weak to it (no bit, OT6_BLADESWING bit 1 clear)")
      H.assertEq(count(r.swings, function(h) return h.weak and (h.el & S.wElems) ~= 0 end), own, "5w. the hand that "
        .. "carries the body's weakness takes the weak branch")
      H.assertEq(count(r.swings, function(h) return h.weak and h.pre > 0 and h.dmg == h.pre * 2 end), own, "5w. a hit "
        .. "the rune does not bite is x2, whatever the rune's tier (3 here)")
      H.assertEq(count(r.swings, function(h) return h.weak end), own, "5w. the other hand's hit takes no weak branch")
      H.assertEq(r.act.sh0 - r.act.sh1, own + count(r.procs, function(h) return h.chip end), "5w. one shield a hit "
        .. "the weapon's own element chips")
      return true
    end }),
})

-- 6. each hit of a boosted Fight
add({ fightCheck("6", { rune = true, boost = 2, when = function() return bblade() == 0 end,
  what = "every swing of a 2-BP Fight chips",
  bytes = function() return S.RB.bit, 0, 0, 0 end,
  judge = function(r)
    local n = #r.swings
    H.assertEq(r.act.pend0, 2, "6. the Fight ran at 2 BP")
    H.assertEq(r.act.passes >= 3, true, "6. a 2-BP Fight swings at least three times (Ot6WeaponClass ran for her)")
    if n < 3 then say("check 6: fewer than three swings landed; asked again"); return false end
    H.assertEq(count(r.swings, function(h) return h.rs ~= 0 end), n, "6. every landed swing carried the rune "
      .. "(OT6_RUNESWING at Ot6HitJoin)")
    H.assertEq(count(r.swings, function(h) return h.chip end), n, "6. every landed swing of the boosted Fight chips "
      .. "(Ot6Chip ran once a swing)")
    H.assertEq(r.act.sh0 - r.act.sh1, n, "6. the shields fell by the number of swings")
    return true
  end }) })

-- 2t2, 2t3: the absorbed spell's tier; and a tier-1 arming after it replaces element and tier together
do
  local steps = { H.call(function() S.absorbMade = nil end) }
  for _, s in ipairs(absorbTier("2t2", "check 2t2", 1)) do steps[#steps + 1] = s end
  steps[#steps + 1] = check(function()
    if S.absorbMade ~= nil and S.absorbMade.key == "2t2" then
      passed("2t2", "the ally's spell at 1 BP, absorbed, armed %02X at tier %d", S.absorbMade.el, S.absorbMade.tier)
    end
  end)
  add({ block("2t2", function() return bblade() == 0 end, steps) })
  steps = { H.call(function() S.absorbMade = nil end) }
  for _, s in ipairs(absorbTier("2t3", "check 2t3", 2)) do steps[#steps + 1] = s end
  steps[#steps + 1] = H.cond(function() return S.absorbMade ~= nil and S.absorbMade.key == "2t3" and usable() end, {
    play("check 2t3, the blade row", function() return { bladeEntry(0) } end, { done = lastActionDone }),
    check(function()
      local a = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == S.RB.id end)
      if a == nil then say("check 2t3: the blade row's action did not come; asked again"); return end
      say("check 2t3: the %s blade row at 0 BP after it: rune %02X tier %d -> %02X tier %d", ELEM[S.RB.e], a.rune0,
        a.tier0, a.rune2, a.tier2)
      H.assertEq(a.rune0 == S.absorbMade.el and a.tier0 == S.absorbMade.tier, true, "2t3. her blade still held the "
        .. "absorbed element and tier as the row began")
      H.assertEq(a.rune2 == S.RB.bit and a.tier2 == 1, true, "2t3. a later tier-1 arming replaces element and tier "
        .. "together")
      passed("2t3", "the ally's spell at 2 BP, absorbed, armed %02X at tier %d; a blade row then replaced both",
        S.absorbMade.el, S.absorbMade.tier)
    end),
  }, {})
  add({ block("2t3", function() return bblade() == 0 end, steps) })
end

-- 7a. two more rounds
add({ block("7a", nil, {
  H.cond(function() return usable() and rune() == 0 end, {
    play("check 7a, her blade armed", function() return { bladeEntry(0) } end, { done = lastActionDone }),
  }, {}),
  play("check 7a", function()
    return { { who = CELES, defend = true }, { who = CELES, defend = true } }
  end, { done = lastActionDone }),
  check(function()
    local n = #S.acts - S.mark.acts
    say("check 7a: %d action(s) of hers ended, %d arming(s) since f%d: rune %02X tier %d -> %02X tier %d", n,
      #S.arms - S.mark.arms, S.mark.f, S.mark.rune, S.mark.tier, rune(), tier())
    if n < 2 or #S.arms ~= S.mark.arms or S.mark.rune == 0 then
      say("check 7a: not two quiet rounds with a rune held; asked again")
      return
    end
    H.assertEq(rune(), S.mark.rune, "7. the rune is unchanged after two more rounds")
    H.assertEq(tier(), S.mark.tier, "7. and so is its tier")
    passed("7a", "rune %02X at tier %d through two more rounds", rune(), tier())
  end),
}) })

-- 9. Break Blade's gate
do
  local at = nil
  add({
    block("9a", function() return bblade() == 0 and mp(S.celes) >= BREAK_MP end, {
      H.call(function() at = nil end),
      play("check 9a", function()
        return { { who = CELES, cmd = RUNIC, row = ROW_BREAK, boost = 2, refused = "list" } }
      end, { onList = function() if at == nil then at = { mp = mp(S.celes), pend = pend(S.celes) } end end,
        -- (an A the list did not refuse opens her target select: the step ends there, for the check to say so)
        giveUp = function()
          if at ~= nil and H.readByte(0x7BC2) == 0x38 and (H.readByte(0x62CA) & 3) == S.celes then
            at.opened = true
          end
          return at ~= nil and at.opened == true
        end }),
      check(function()
        local k = H.vars.kit[#H.vars.kit]
        if at == nil or (k == nil and not at.opened) then
          say("check 9a: the row was not reached; asked again")
          return
        end
        say("check 9a: A on Break Blade at %d BP pending, %d MP: refused %s, target select opened %s; now MP %d, "
          .. "OT6_BREAKBLADE %d, pending %d", at.pend, at.mp, tostring(k ~= nil and k.refusedSeen),
          tostring(at.opened == true), mp(S.celes), bblade(), pend(S.celes))
        H.assertEq(at.pend, 2, "9. two points were pending on the Break Blade row")
        H.assertEq(at.opened == true, false, "9. Break Blade under three points is refused in the list (its A opens "
          .. "no target select)")
        H.assertEq(k ~= nil and k.refusedSeen, true, "9. Break Blade under three points is refused in the list")
        H.assertEq(mp(S.celes), at.mp, "9. the refused row spent no MP")
        H.assertEq(bblade(), 0, "9. and set no Break Blade")
        passed("9a", "refused at 2 BP pending")
      end),
    }),
    block("9b", function() return bblade() == 0 and mp(S.celes) >= BREAK_MP end, {
      play("check 9b", function()
        S.lower = true
        return { { who = CELES, cmd = RUNIC, row = ROW_BREAK, boost = 3, self = true } }
      end, { done = lastActionDone }),
      check(function()
        S.lower = nil
        local a = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == ROW_BREAK end)
        if a == nil then say("check 9b: Break Blade's action did not come; asked again"); return end
        say("check 9b: Break Blade picked at %d BP, its pending boost staged to %s as the action began: "
          .. "OT6_BREAKBLADE %d -> %d at the action's end -> %d after it, MP %d -> %d, bank %d -> %d, pending -> %d",
          a.pend0, tostring(a.lowered), a.bb0, a.bbEnd, a.bb2, a.mp0, a.mp1, a.bank0, a.bank2, a.pend2)
        H.assertEq(a.pend0 == 3 and a.lowered == 2, true, "9. the pick was made at three points and found two as "
          .. "its action began (staged)")
        H.assertEq(a.bbEnd, 0, "9. Break Blade under three points does nothing (OT6_BREAKBLADE stays 0)")
        H.assertEq(a.bb2, 0, "9. and it reads 0 after the action")
        H.assertEq(a.mp1, a.mp0, "9. it costs no MP")
        H.assertEq(a.pend2, 0, "9. the two points left pending are dropped")
        H.assertEq(a.bank2, math.min(a.bank0 + 1, 5), "9. and the bank is not charged")
        passed("9b", "under three points at its action: nothing done, nothing paid")
      end),
    }),
  })
end

-- 10. Break Blade
local function bbOpen() return not (D["10b"] and D["10c"] and D["10d"]) end
local function brokeHit(tag, r, n)
  H.assertEq(count(r.swings, function(h) return h.bb ~= 0 end), n, tag .. ": Break Blade was running at every swing")
  H.assertEq(count(r.swings, function(h) return h.rs == 0 end), n, tag .. ": no rune rides a Break Blade swing "
    .. "(OT6_RUNESWING is 0 at every Ot6HitJoin)")
  H.assertEq(count(r.swings, function(h) return h.loss == 1 end), n, tag .. ": every landed hit of her weapon took "
    .. "exactly one shield")
end
add({
  -- 10a: the cast
  block("10a", function() return bblade() == 0 and mp(S.celes) >= BREAK_MP end, {
    play("check 10a", function()
      local plan = {}
      if not armedAt(nil) then plan[#plan + 1] = bladeEntry(0) end
      plan[#plan + 1] = { who = CELES, cmd = RUNIC, row = ROW_BREAK, boost = 3, bank = 5, self = true, lowerTo = 2 }
      return plan
    end, { done = lastActionDone, budget = 20000 }),
    H.cond(function() return usable() end, { H.waitFrames(12) }, {}),
    check(function()
      local a, at = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == ROW_BREAK end)
      if a == nil then say("check 10a: Break Blade's action did not come; asked again"); return end
      local staged, vram = signCells(S.celes)
      say("check 10a: Break Blade cast at %d BP pending (f%d-%d): MP %d -> %d, OT6_BREAKBLADE %d -> %d at the action's "
        .. "end -> %d after it, bank %d -> %d, rune %02X; sign cells staged %04X, VRAM %04X", a.pend0, a.f0, a.f1,
        a.mp0, a.mp1, a.bb0, a.bbEnd, a.bb2, a.bank0, a.bank2, a.rune2, staged or 0, vram or 0)
      local p = S.plan[#S.plan]
      say("check 10a: L twice at Break Blade's target select left %s point(s) pending", tostring(p.raised))
      H.assertEq(p.raised, 3, "10. L at the target select takes nothing back from a pick made in the list (#555)")
      H.assertEq(a.pend0, 3, "10. Break Blade was cast with three points pending")
      H.assertEq(a.mp0 - a.mp1, BREAK_MP, "10. Break Blade costs exactly 99 MP")
      H.assertEq(a.bb2, 3, "10. OT6_BREAKBLADE reads 3 once the cast has resolved (three of her turns)")
      H.assertEq(a.bank2, a.bank0 - 3, "10. the three points are spent")
      H.assertEq(staged, SWORD, "10. the staged sign cell is the sword while Break Blade runs")
      H.assertEq(vram, SWORD, "10. the sign cell on screen is the sword while Break Blade runs")
      H.screenshot("spellblade_breaksign")
      S.cast = { act = at, battle = S.battles, rune = a.rune2 }
      passed("10a", "99 MP, OT6_BREAKBLADE 3, the sword beside her name")
    end),
  }),
  -- a cast to make the open Break Blade checks under, when a battle before made 10a
  H.cond(function()
    local here = S.cast ~= nil and S.cast.battle == S.battles
    return D["10a"] and usable() and bblade() == 0 and mp(S.celes) >= BREAK_MP
      and (bbOpen() or (not D["10e"] and not here) or (not D["10f"] and S.ranOut ~= S.RB.bit))
  end, {
    play("check 10, Break Blade cast again", function()
      local plan = {}
      -- (her blade armed first, as in 10a: 10d and 10f are about the rune that waits under Break Blade)
      if not armedAt(nil) then plan[#plan + 1] = bladeEntry(0) end
      plan[#plan + 1] = { who = CELES, cmd = RUNIC, row = ROW_BREAK, boost = 3, bank = 5, self = true }
      return plan
    end, { done = lastActionDone, budget = 20000 }),
    check(function()
      local a, at = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == ROW_BREAK and x.bb2 == 3 end)
      if a ~= nil then S.cast = { act = at, battle = S.battles, rune = a.rune2 } end
    end),
  }, {}),
  -- 10b: an unkeyed body, a 2-BP Fight
  fightCheck("10b", { boost = 2, when = function() return bblade() ~= 0 end, shot = "spellblade_breakswing",
    what = "each hit of a 2-BP Fight takes one shield from an unkeyed body, in Break Blade's colours",
    bytes = function() return 0, 0, 0, 0 end,
    judge = function(r)
      local n = #r.swings
      local sp, hp = palTables(8)
      say("check 10b: Break Blade's colours are sprite %02X, hit %02X (the tables' ninth entries)", sp, hp)
      if r.act.bb0 == 0 then say("check 10b: Break Blade had ended; asked again"); return false end
      H.assertEq(r.act.pend0, 2, "10. the Fight ran at 2 BP")
      H.assertEq(r.act.passes >= 3, true, "10. a 2-BP Fight swings at least three times")
      if n < 3 then say("check 10b: fewer than three swings landed; asked again"); return false end
      brokeHit("10. unkeyed body", r, n)
      H.assertEq(count(r.swings, function(h) return h.chip end), 0, "10. unkeyed body: Ot6Chip did not run")
      H.assertEq(r.act.sh0 - r.act.sh1, n, "10. unkeyed body: the shields fell by exactly the number of swings")
      H.assertEq(#r.pals >= 1, true, "10. her swing was drawn")
      H.assertEq(count(r.pals, function(p) return p.used == sp and p.usedHit == hp end), #r.pals, "10. a Break Blade "
        .. "swing is drawn in Break Blade's colours")
      return true
    end }),
  -- 10c: a body weak to her weapon's own element: one shield a hit, not two
  fightCheck("10c", { when = function() return bblade() ~= 0 end,
    what = "a hit the weapon's own element chips takes no second shield",
    bytes = function() return S.wElems, 0, 0, 0 end,
    judge = function(r)
      local n = #r.swings
      if r.act.bb0 == 0 then say("check 10c: Break Blade had ended; asked again"); return false end
      if count(r.swings, function(h) return h.chip end) == 0 then
        say("check 10c: no swing of the elemental hand landed; asked again")
        return false
      end
      brokeHit("10. body weak to her weapon's element", r, n)
      -- (her weapon's own spell, when it comes, is a spell of that element: Ot6Chip's one shield, as any spell's)
      H.assertEq(r.act.sh0 - r.act.sh1, n + count(r.procs, function(h) return h.chip end), "10. body weak to her "
        .. "weapon's element: the shields fell by one a landed hit, not two")
      return true
    end }),
  -- 10d: a body weak to the waiting rune: nothing joins, and still one shield a hit
  fightCheck("10d", { when = function() return bblade() ~= 0 and rune() == S.RB.bit end,
    what = "the rune waits while Break Blade runs",
    bytes = function() return S.RB.bit, 0, 0, 0 end,
    judge = function(r)
      local n = #r.swings
      if r.act.bb0 == 0 then say("check 10d: Break Blade had ended; asked again"); return false end
      H.assertEq(count(r.swings, function(h) return (h.el & S.RB.bit) ~= 0 end), 0, "10. no swing carries the rune "
        .. "while Break Blade runs, on a body weak to it")
      brokeHit("10. body weak to the waiting rune", r, n)
      return true
    end }),
  -- the turns Break Blade has left once its hits have had their Fights, judged or not: Defended away, so that
  -- it never runs on under the checks that follow (and a check still open gets a cast of its own next pass)
  H.cond(function() return usable() and bblade() ~= 0 end, { play("check 10, Break Blade's turns left", function()
    local t = {}
    for i = 1, bblade() do t[i] = { who = CELES, defend = true } end
    return t
  end, { done = lastActionDone }) }, {}),
  -- 10e: its turns: 3 after the cast, then 2, 1, 0 at her next three action ends
  block("10e", function() return S.cast ~= nil and S.cast.battle == S.battles end, {
    check(function()
      if #S.acts < S.cast.act + 3 then return end
      local t, seq = {}, {}
      for i = S.cast.act, S.cast.act + 3 do
        local a = S.acts[i]
        if not a.settled then return end
        t[#t + 1] = string.format("f%d %s: %d -> %d", a.f1, a.bare and "(no action)" or string.format("command $%02X",
          a.cmd), a.bb0, a.bb2)
        seq[#seq + 1] = tostring(a.bb2)
      end
      say("check 10e: OT6_BREAKBLADE at the cast and her next three action ends: %s", table.concat(t, "; "))
      H.assertEq(table.concat(seq, " "), "3 2 1 0", "10. OT6_BREAKBLADE reads 3 after the cast and 2, 1, 0 after "
        .. "each of her next three actions")
      passed("10e", "three of her turns")
    end),
  }),
  -- 10f: Break Blade over, the rune she held bites again
  fightCheck("10f", { when = function() return bblade() == 0 and S.ranOut == S.RB.bit and rune() == S.RB.bit end,
    what = "the rune returns when Break Blade ends",
    bytes = function() return S.RB.bit, 0, 0, 0 end,
    judge = function(r)
      local n = #r.swings
      H.assertEq(r.act.bb0, 0, "10. Break Blade has ended")
      H.assertEq(r.act.rune0, S.RB.bit, "10. her blade still holds the rune it held before Break Blade")
      H.assertEq(count(r.swings, function(h) return (h.el & S.RB.bit) ~= 0 and h.chip end), n, "10. with Break Blade "
        .. "over the rune joins her swings again, on a body weak to it")
      return true
    end }),
})

-- 12. a Runic the engine chooses
add({ block("12", function()
  return not stance() and H.readByte(0xED8E + ent()) == 0 and (H.readByte(0x3EE5 + ent()) & 0x20) == 0
end, {
  H.call(function()
    local c = S.celes * 12
    S.hold = { on = true, f = H.frame, mark = mark(), cmds = { H.readByte(0x202E + c), H.readByte(0x2031 + c),
      H.readByte(0x2034 + c), H.readByte(0x2037 + c) } }
    say("check 12: CELES Muddled, her commands %02X %02X %02X %02X reduced to Runic", S.hold.cmds[1], S.hold.cmds[2],
      S.hold.cmds[3], S.hold.cmds[4])
  end),
  play("check 12", function() return {} end, { budget = 9000, done = function()
    local h = S.hold
    if h.seen ~= nil and h.seen.settled and h.on then
      -- the engine has picked Runic and the action has ended: let go at once
      h.on = false
      releaseMuddle(h)
    end
    return not h.on
  end }),
  H.call(function()
    local h = S.hold
    if h == nil then return end
    if h.on then h.on = false; releaseMuddle(h) end
    S.hold = nil
    local a, fights = h.seen, 0
    for i = h.mark.acts + 1, #S.acts do if S.acts[i].cmd == FIGHT then fights = fights + 1 end end
    say("check 12: Muddle and the command list put back; the engine chose Fight %d time(s) first", fights)
    if a == nil or not a.settled or not usable() then
      say("check 12: the engine did not pick Runic; asked again")
      return
    end
    say("check 12: the engine's Runic at f%d-%d (status 2 %02X): $B5 %02X, $B6 %02X at ExecCmd, %02X at Cmd_0b, %s "
      .. "at Ot6RuneExec; stance %s -> %s, rune %02X -> %02X, OT6_BREAKBLADE %d -> %d (before its turn is counted), MP "
      .. "%d -> %d, %d arming(s)", a.f0, a.f1, a.st2, a.cmd, a.b6, a.cmd0b, a.exec and string.format("%02X", a.exec)
      or "not reached", tostring(a.stance0), tostring(a.stance1), a.rune0, a.runeEnd, a.bb0, a.bbEnd, a.mp0, a.mp1,
      a.arm1 - a.arm0 + 1)
    H.assertEq((a.st2 & 0x20) ~= 0, true, "12. she was Muddled as the action began (the engine chose it)")
    H.assertEq(a.cmd0b, 0x00, "12. an engine-chosen Runic reaches Cmd_0b with attack byte $00")
    H.assertEq(a.exec, 0x00, "12. and Ot6RuneExec reads $00")
    H.assertEq(a.stance0, false, "12. no stance stood before it")
    H.assertEq(a.stance1, true, "12. it raises the plain stance ($3E4C bit 2)")
    H.assertEq(a.arm1 - a.arm0 + 1, 0, "12. it arms no blade")
    H.assertEq(a.runeEnd, a.rune0, "12. the rune is unchanged")
    H.assertEq(a.bbEnd, a.bb0, "12. Break Blade is not set")
    H.assertEq(a.mp1, a.mp0, "12. it costs no MP")
    passed("12", "the engine's Runic queued $00: the stance, nothing else")
  end),
}) })

-- 8.
add({ block("8", function() return bblade() == 0 end, {
  intoStance("check 8", 3, function() return allySpell(true, S.RB.bit, 0) end),
  check(function()
    local ab = absorbed("check 8")
    if ab == nil then return end
    local a = actSince(S.mark, function(x) return x.cmd == RUNIC and x.b6 == ROW_RUNIC end)
    say("check 8: her Runic was raised at %d BP pending", a and a.pend0 or -1)
    H.assertEq(a ~= nil and a.pend0 == 3, true, "8. her Runic was raised with three points (RunicBlade)")
    H.assertEq(ab.rune0 ~= ab.el or ab.tier0 ~= S.z.tier, true, "8. her blade did not hold that element at that tier "
      .. "before the absorb")
    H.assertEq(ab.rune1, S.z.el, "8. a RunicBlade's absorb arms her blade with the spell's element too")
    H.assertEq(ab.tier1, S.z.tier, "8. at the spell's tier")
    passed("8", "a 3-BP Runic's absorb armed %02X at tier %d", ab.rune1, ab.tier1)
  end),
}) })

-- the pass is over: what is still open, and whether the battle is left
add({
  H.call(function()
    if not inBattle() then return end
    S.passes = S.passes + 1
    local open = {}
    for _, k in ipairs(IN_BATTLE) do if not D[k] then open[#open + 1] = k end end
    if #open == 0 then
      say("battle %d, pass %d: every in-battle check is made; the rune reads %02X", S.battles, S.passes, rune())
      S.leave = true
    elseif S.handed ~= nil then
      say("battle %d handed to the fight driver (%s); open: %s", S.battles, S.handed, table.concat(open, " "))
      S.leave = true
    elseif not usable() then
      say("battle %d cannot go on (CELES or the body is down); open: %s", S.battles, table.concat(open, " "))
      S.leave = true
    elseif S.passes >= PASSES then
      say("battle %d left after %d passes; open: %s", S.battles, S.passes, table.concat(open, " "))
      S.leave = true
    else
      say("battle %d, pass %d: open: %s", S.battles, S.passes, table.concat(open, " "))
    end
  end),
  H.cond(function() return inBattle() and S.leave end, {
    H.call(function()
      if S.hold ~= nil and S.hold.on then S.hold.on = false; releaseMuddle(S.hold) end
      unstage()
    end),
    fightOut("spellblade: fought out"),
  }, {}),
})

local steps = {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    arm()
    emu.addEventCallback(pump, emu.eventType.startFrame)
  end),
  -- PACE_BURN (a lab's global, 0 here): flee that many encounters first, to vary the encounter history
  (function()
    local burned = 0
    return H.driveUntil(function() return burned >= BURN end, 400000, {
      walkToBattle(),
      H.waitUntil(function() return H.battleActive() end, 1200, "a battle to burn is up", 2),
      H.fleeBattle(9000, { onCantRun = "fight" }),
      H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "control after the burn", 5),
      H.fieldCare({ tag = "spellblade: care after a burned encounter", threshold = 0.95 }),
      H.call(function() burned = burned + 1; say("burned encounter %d of %d", burned, BURN) end),
    }, "the encounters PACE_BURN uses up")
  end)(),
  H.driveUntil(allMade, 1500000, body, "every check made"),
  H.call(function()
    -- every absorb of hers followed the rule, and nothing but Ot6RuneArm moved the rune
    local el, none = 0, 0
    for _, ab in ipairs(S.absorbs) do
      if ab.settled then
        if ab.el ~= 0 then
          el = el + 1
          H.assertEq(ab.rune1, ab.el, string.format("every elemental absorb armed its element (f%d)", ab.f))
          H.assertEq(ab.tier1, tierOf(ab.b6), string.format("every elemental absorb armed its spell's tier (f%d, "
            .. "spell $%02X)", ab.f, ab.b6))
        else
          none = none + 1
          H.assertEq(ab.rune1, ab.rune0, string.format("every absorb without an element left the rune (f%d)", ab.f))
        end
      end
    end
    say("the rune moved outside Ot6RuneArm %d time(s)%s", #S.runeViol, #S.runeViol > 0 and (": "
      .. table.concat(S.runeViol, ", ")) or "")
    H.assertEq(#S.runeViol, 0, "7. within a battle the rune changes only where Ot6RuneArm sets it")
    local n, worst, miss = 0, 0, 0
    for _, sg in ipairs(S.signLags) do
      if sg.want ~= false then n, worst, miss = n + 1, math.max(worst, sg.lag), miss + sg.miss end
    end
    say("the sign showed a rune or the sword %d time(s), at worst %d frame(s) after the change; %d frame(s) in all "
      .. "on which a sign once shown was not in both cells", n, worst, miss)
    say("PASS: the Rune Knight's list, the rune armed by an absorb (%d elemental, %d not) and by a blade row, at "
      .. "the spell's tier; a blade row's boost; the weak-only rule and the tier's multiplier; Break Blade's gate, "
      .. "hits, turns and colours; the story switches and the engine's plain Runic: %d checks in %d battle(s)", el,
      none, #NEED, S.battles)
  end),
}
H.run({ maxFrames = 2000000 }, steps)
