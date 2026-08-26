-- @suite
-- battle_leo.lua -- Leo is playable at the massacre.
-- Asserts the authored break data for the massacre's one real fight, Kefka
-- vs. a solo General Leo (formation 388 = KEFKA_VS_LEO $173, L1 HP5001),
-- straight out of the assembled ROM.  Pure ROM bytes, no savestate, exit
-- 0 = pass.

-- Source-verified, not re-asserted here (no byte to pin without the fight):
--   * Shock charges 0 MP.  It is battle command $1b, which is in neither
--     vanilla GetMPCost's costed set (magic/lore/summon/x-magic) nor
--     Ot6AbilityCost's (steal/dance/rage/swdtech/tools/blitz), so it falls
--     through at 0 -- a free guest verb.
--   * The win exits through battle_event $17.  AIScript::_371 (kefka vs leo)
--     ends `if_self_dead -> hide_monsters, battle_event $17, end_battle`
--     (ai_script.asm), and a LOSS is a GAME OVER (the battle tail calls
--     _ca5ea9 = `if_b_switch $40 return; call GameOver`).
local H = dofile("tools/tests/lib/ot6.lua")   -- only for H.sym if needed

local PRG = emu.memType.snesPrgRom
local SLASH, PIERCE, BLUDG = 0x01, 0x02, 0x04
local KEFKA_VS_LEO = 0x0173
local fails = 0

local function rb(off) return emu.read(off, PRG) end
local function rw(off) return rb(off) + rb(off + 1) * 256 end

-- MonsterProp .incbin at SNES $CF0000 -> PRG $0F0000; 32-byte records;
-- +23 absorb, +24 null, +25 weak (battle_breaktbl.lua).
local MPROP, MREC = 0x0F0000, 32
-- BattleMonsters at SNES $CF6200 -> PRG $0F6200 (rom/ff6-en.map); 15-byte
-- records: +1 present mask, +2+slot species low, +14 species-high bits
-- (audit_encounters.py).
local BMON, BREC = 0x0F6200, 15

local function walk(base)   -- 4-byte rows {word id, b1, b2}; $ffff ends
  local t, o = {}, base
  for _ = 1, 400 do
    local id = rw(o)
    if id == 0xffff then break end
    t[id] = { rb(o + 2), rb(o + 3) }
    o = o + 4
  end
  return t
end

local function find(seq, lo, hi)
  for o = lo, hi do
    local hit = true
    for i = 1, #seq do
      if rb(o + i - 1) ~= seq[i] then hit = false; break end
    end
    if hit then return o end
  end
  return nil
end

local function check(cond, msg)
  if not cond then fails = fails + 1 end
  local line = string.format("leo: %s %s", cond and "OK  " or "FAIL", msg)
  emu.log(line); print(line)
end

-- locate both tables by their opening anchor runs:
-- ShieldTbl opens guard/lobo/whelk-shell; ElemAddTbl opens whelk-head/vargas.
local shieldBase = find(
  { 0x00, 0x00, 0x02, 0x02, 0x19, 0x00, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00 },
  0x300000, 0x310000)
local elemBase = find(
  { 0x34, 0x01, 0x01, 0x00, 0x03, 0x01, 0x20, 0x00 },
  0x300000, 0x310000)

if not shieldBase or not elemBase then
  emu.log(string.format("leo: FAIL tables not located (shield=%s elem=%s)",
    tostring(shieldBase), tostring(elemBase)))
  emu.stop(1)
  return
end
emu.log(string.format("leo: Ot6ShieldTbl @%06X  Ot6ElemAddTbl @%06X",
  shieldBase, elemBase))

local S = walk(shieldBase)
local E = walk(elemBase)

-- 1. the authored shield row: 4 shields, slash class.
local r = S[KEFKA_VS_LEO]
check(r ~= nil and r[1] == 4 and r[2] == SLASH, string.format(
  "Ot6ShieldTbl $0173 = shields 4, class OT6_SLASH (got %s/%s) -- the gauge "
  .. "renders 4, not the formula floor 2",
  r and tostring(r[1]) or "MISSING",
  r and string.format("$%02X", r[2]) or "-"))
-- the class byte is exactly slash: no stray pierce/bludg that a solo Leo,
-- who holds only a slashing sword, could not field.
check(r ~= nil and (r[2] & (PIERCE | BLUDG)) == 0,
  "the class key is slash-only -- Leo's Crystal is the only tool here")

check(E[KEFKA_VS_LEO] == nil, string.format(
  "Ot6ElemAddTbl has NO $0173 row (got %s) -- Leo's kit is non-elemental, so "
  .. "a hidden element would be an unreachable '?'",
  E[KEFKA_VS_LEO] and string.format("$%02X", E[KEFKA_VS_LEO][1]) or "nil"))

-- 3. Kefka $173 carries no vanilla element either.
local ab = rb(MPROP + KEFKA_VS_LEO * MREC + 23)
local nu = rb(MPROP + KEFKA_VS_LEO * MREC + 24)
local wk = rb(MPROP + KEFKA_VS_LEO * MREC + 25)
check(ab == 0 and nu == 0 and wk == 0, string.format(
  "$0173 monster_prop absorb/null/weak all $00 (got $%02X/$%02X/$%02X) -- "
  .. "slash stands alone", ab, nu, wk))

-- 4. formation 388 fields a solo $173.
local frec = BMON + 388 * BREC
local present = rb(frec + 1)
local bodies = {}
for slot = 0, 5 do
  if (present & (1 << slot)) ~= 0 then
    bodies[#bodies + 1] = rb(frec + 2 + slot)
       | (((rb(frec + 14) >> slot) & 1) << 8)
  end
end
check(#bodies == 1 and bodies[1] == KEFKA_VS_LEO, string.format(
  "formation 388 fields a SOLO $0173 (present=$%02X bodies=%d first=$%03X)",
  present, #bodies, bodies[1] or 0))

-- ----------------------------------------------------------------- verdict
-- exit code is the verdict (no H.run, so no spoken PASS/FAIL line; run.sh
-- falls back to the process code).
if fails == 0 then
  emu.log("leo: authored $173 row + fight data all present - PASS")
  emu.stop(0)
else
  emu.log(string.format("leo: %d assertion(s) FAILED", fails))
  emu.stop(1)
end
