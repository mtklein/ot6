-- @suite
-- battle_breakvector.lua -- the v0.6 Vector / Magitek Factory break section,
-- asserted against the REAL encounter chain in ROM.
-- (school.lua / battle_breaktbl.lua pattern: pure ROM bytes, no savestate.)
--
-- Issue #11 asks for authored, encounter-aware rows to replace the generated
-- floor one route section at a time, and its acceptance criteria are explicit
-- that "tests cover encounter/party reachability, not only nonzero table
-- bytes".  So this test does not merely read back the twelve bytes the pass
-- wrote.  It walks
--
--   SubBattleGroup[map] -> RandBattleGroup[group*8] -> BattleMonsters[form*15]
--
-- out of the shipped ROM, plus the minecart's five forced formations, and
-- asserts properties OF THE SECTION: that every body in it is authored rather
-- than falling through to the floor, that every formation is answerable by
-- some buildable party, that the one formation which demands a blunt weapon
-- is exactly the one the design says it is, and that slash has stopped being
-- the automatic answer.  Those are the claims that were false before the pass
-- and that a byte-equality check alone would not notice going false again.
--
-- Survey, arithmetic and per-formation reading: docs/design/break-band-vector.md.
--
-- ROM addressing.  HiROM PRG file offset = SNES addr - $C00000 (school.lua
-- documents the same mapping).  From the link map:
--   monster_prop    CF0000  -> $0F0000   (32-byte records; +23 absorb, +25 weak)
--   battle_groups   CF4800  -> $0F4800   RandBattleGroup at the segment start,
--                                        SubBattleGroup at CF5600 -> $0F5600
--   battle_prop     CF5900             ; BattleMonsters CF6200 -> $0F6200
--   ot6_code        F00000  -> $300000   (Ot6ShieldTbl, self-located below)

local PRG = emu.memType.snesPrgRom
local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WATER = 0x01, 0x02, 0x04, 0x08, 0x80

local MPROP, MREC = 0x0F0000, 32
local OFF_ABSORB, OFF_WEAK = 23, 25
local RANDGRP = 0x0F4800
local SUBGRP  = 0x0F5600
local BMON, BREC = 0x0F6200, 15

local fails = 0
local function rb(off) return emu.read(off, PRG) end
local function rw(off) return rb(off) + rb(off + 1) * 256 end

local function check(cond, msg)
  if not cond then fails = fails + 1 end
  emu.log(string.format("breakvector: %s %s", cond and "OK  " or "FAIL", msg))
  print(string.format("breakvector: %s %s", cond and "OK  " or "FAIL", msg))
end

local function classStr(m)
  if m == 0 then return "(none)" end
  local s = ""
  if m & SLASH   ~= 0 then s = s .. "slash "  end
  if m & PIERCE  ~= 0 then s = s .. "pierce " end
  if m & BLUDG   ~= 0 then s = s .. "bludg "  end
  if m & SPECIAL ~= 0 then s = s .. "special " end
  return (s:gsub("%s+$", ""))
end

-- ------------------------------------------------------------- Ot6ShieldTbl
-- Self-located by its opening anchor (guard/lobo/whelk-shell), so row
-- insertions anywhere below it cannot break this test -- same technique
-- battle_breaktbl.lua uses.
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

local shieldBase = find(
  { 0x00, 0x00, 0x02, 0x02, 0x19, 0x00, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00 },
  0x300000, 0x310000)
if not shieldBase then
  emu.log("breakvector: FAIL Ot6ShieldTbl not located")
  print("breakvector: FAIL Ot6ShieldTbl not located")
  emu.stop(1)
  return
end

local S, shieldRows = {}, 0
do
  local o = shieldBase
  for _ = 1, 400 do
    local id = rw(o)
    if id == 0xffff then break end
    S[id] = { rb(o + 2), rb(o + 3) }
    shieldRows = shieldRows + 1
    o = o + 4
  end
end
check(shieldRows >= 70, string.format(
  "Ot6ShieldTbl walk saw %d rows (a mislocated base would prove nothing)",
  shieldRows))

-- --------------------------------------------------------- the authored rows
-- Exact shields AND class: a missing row reads nil, a drifted one reads a
-- different byte, and both fail.  Rationale for each is in ot6_hud.asm beside
-- the row and in break-band-vector.md §8.1.
local want = {
  { 0x00cb, 2, PIERCE | BLUDG, "garm (magitek quadruped, entrance)" },
  { 0x00c7, 2, PIERCE,         "commando (imperial line keeps pierce)" },
  { 0x0165, 2, BLUDG,          "protoarmor (sealed suit, no seam)" },
  { 0x0041, 2, PIERCE,         "pipsqueak (the x5 swarm; AutoCrossbow)" },
  { 0x0047, 2, BLUDG,          "flan (you cannot cut an ooze)" },
  { 0x0066, 2, PIERCE | BLUDG, "general (officer in plate)" },
  { 0x002d, 2, BLUDG,          "trapper (a device; you smash it)" },
  { 0x00a0, 2, PIERCE | BLUDG, "chaser (1202 hp, on the escape map)" },
  { 0x0088, 2, SLASH | PIERCE, "gobbler (the area's deliberate slash target)" },
  { 0x0075, 2, BLUDG,          "rhinox (THE FLAGSHIP: bludgeon alone)" },
  { 0x0006, 2, BLUDG,          "mag roader $006 (minecart)" },
  { 0x00af, 2, BLUDG,          "mag roader $0af (minecart)" },
}
for _, w in ipairs(want) do
  local r = S[w[1]]
  check(r ~= nil and r[1] == w[2] and r[2] == w[3],
    string.format("$%04X %s: shields=%s class=%s (want %d/%s)", w[1], w[4],
      r and tostring(r[1]) or "MISSING",
      r and classStr(r[2]) or "-", w[2], classStr(w[3])))
end

-- -------------------------------------------------- the encounter chain, live
-- Seven encounter-bearing maps (break-band-vector.md §1.1).  Map 275 carries
-- group 106 and the enable bit but no entrance record targets it, so it is
-- excluded; 270/272/274 carry a group with the enable bit CLEAR.
local BAND_MAPS = { 262, 263, 264, 269, 271, 273, 240 }
local WANT_GROUP = { [262] = 80, [263] = 81, [264] = 104, [269] = 105,
                     [271] = 106, [273] = 106, [240] = 108 }
local SLOT_P = { 0.3125, 0.3125, 0.3125, 0.0625 }

local function formationSpecies(f)
  local base = BMON + f * BREC
  local mask, hi = rb(base + 1), rb(base + 14)
  local out = {}
  for i = 0, 5 do
    if (mask >> i) & 1 == 1 then
      out[#out + 1] = rb(base + 2 + i) | (((hi >> i) & 1) << 8)
    end
  end
  return out
end

-- Every section map must still point at the group this pass was authored against.
-- If a map is ever repointed, every distribution claim below is stale and the
-- test says so rather than quietly measuring a different dungeon.
for _, m in ipairs(BAND_MAPS) do
  local g = rb(SUBGRP + m)
  check(g == WANT_GROUP[m], string.format(
    "map %d -> battle group %d (want %d)", m, g, WANT_GROUP[m]))
end

-- Collect the section's random formations, each with its draw weight.
local randForms = {}
for _, m in ipairs(BAND_MAPS) do
  local g = rb(SUBGRP + m)
  for i = 0, 3 do
    local f = rw(RANDGRP + g * 8 + i * 2)
    randForms[#randForms + 1] = { f = f, w = SLOT_P[i + 1] / #BAND_MAPS }
  end
end
check(#randForms == 28, string.format(
  "walked %d random formation slots (7 maps x 4 slots = 28)", #randForms))

-- The minecart's five forced fights: train_script.asm items 3/14 -> battle 41
-- ($06f/$075) and items 9/24/31 -> battle 144 ($196/$197).  These are
-- invisible to any event-script scan, which is exactly why they are listed.
local MINECART_FORMS = { 0x06f, 0x075, 0x196, 0x197 }

-- ------------------------------------------------------ authored, not floored
-- Acceptance criterion: the section's encounter groups have REVIEWED rows.  Any
-- body in it still falling through to the generated floor fails here.
do
  local unauthored = {}
  local seen = {}
  local function sweep(f)
    for _, sp in ipairs(formationSpecies(f)) do
      if not seen[sp] then
        seen[sp] = true
        if S[sp] == nil then unauthored[#unauthored + 1] = sp end
      end
    end
  end
  for _, e in ipairs(randForms) do sweep(e.f) end
  for _, f in ipairs(MINECART_FORMS) do sweep(f) end
  local list = ""
  for _, sp in ipairs(unauthored) do list = list .. string.format(" $%03X", sp) end
  check(#unauthored == 0,
    "every body in the area has an Ot6ShieldTbl row (unauthored:" ..
    (list == "" and " none" or list) .. ")")
end

-- ------------------------------------------------------------- party model
-- Fixed core Locke + Celes, two free picks from Edgar/Sabin/Cyan/Gau
-- (break-band-vector.md §6.1; Terra is not yet active and Setzer is flying the
-- getaway).  These are the classes each brings for FREE -- joining kit and
-- abilities only, no shop trip:
--   Locke  swords + daggers            slash|pierce
--   Celes  swords + daggers            slash|pierce
--   Edgar  spears + Tools, Chain Saw   slash|pierce
--   Sabin  claws / fists + Blitz       slash|bludg
--   Cyan   katanas + all 8 SwdTechs    slash
--   Gau    bare fists ($ff -> BLUDG)   bludg
-- Classes from ot6_class.asm:10-13, weapon bytes Ot6WeapClassTbl:46, ability
-- bytes Ot6SkillClassTbl:184-196.
local LOCKE, CELES = SLASH | PIERCE, SLASH | PIERCE
local PICKS = {
  { "Edgar", SLASH | PIERCE }, { "Sabin", SLASH | BLUDG },
  { "Cyan",  SLASH },          { "Gau",   BLUDG },
}
local parties = {}
for a = 1, #PICKS do
  for b = a + 1, #PICKS do
    parties[#parties + 1] = {
      name = PICKS[a][1] .. "+" .. PICKS[b][1],
      cls  = LOCKE | CELES | PICKS[a][2] | PICKS[b][2],
    }
  end
end
check(#parties == 6, string.format("enumerated %d free four-parties (C(4,2)=6)",
  #parties))

local function formationKeys(f)
  local m = 0
  for _, sp in ipairs(formationSpecies(f)) do
    if S[sp] then m = m | S[sp][2] end
  end
  return m
end

-- ------------------------------------------------- reachability, the real one
-- "No encounter chippable only by a class no party can field."  Setzer's Cards
-- are the game's only ¤ source and he is flying the getaway, so a formation
-- whose ONLY key is ¤ would be unbreakable for this whole section.
do
  local bad = 0
  local function sweep(f, where)
    local keys = formationKeys(f)
    if keys == 0 or keys == SPECIAL then
      bad = bad + 1
      emu.log(string.format(
        "breakvector: formation $%03X (%s) keys=%s -- no fieldable class",
        f, where, classStr(keys)))
    end
  end
  for _, e in ipairs(randForms) do sweep(e.f, "random") end
  for _, f in ipairs(MINECART_FORMS) do sweep(f, "minecart") end
  check(bad == 0, "no area formation is keyed only by a class no party can field")
end

-- Every formation is answerable by SOME buildable four-party.
do
  local uncovered = 0
  local function sweep(f, where)
    local keys = formationKeys(f)
    local ok = false
    for _, p in ipairs(parties) do
      if keys & p.cls ~= 0 then ok = true; break end
    end
    if not ok then
      uncovered = uncovered + 1
      emu.log(string.format("breakvector: formation $%03X (%s) answered by NO "
        .. "free party (keys=%s)", f, where, classStr(keys)))
    end
  end
  for _, e in ipairs(randForms) do sweep(e.f, "random") end
  for _, f in ipairs(MINECART_FORMS) do sweep(f, "minecart") end
  check(uncovered == 0,
    "every area formation is answerable by at least one free four-party")
end

-- --------------------------------------------------- the one deliberate cost
-- Formation $168 (Rhinox x2) is the section's single hard demand: bludgeon or
-- nothing.  Asserted from BOTH sides so it stays deliberate --
--   * it really is bludgeon-only on the class axis, and
--   * no element substitutes, because Rhinox has no vanilla weakness at all
--     AND absorbs bolt, the element the rest of the facility teaches.
-- If someone ever softens Rhinox, this is the assertion that objects.
do
  local keys = formationKeys(0x168)
  check(keys == BLUDG, string.format(
    "formation $168 (Rhinox x2) is bludgeon-only on the class axis (keys=%s)",
    classStr(keys)))
  check(rb(MPROP + 0x0075 * MREC + OFF_WEAK) == 0x00,
    "rhinox $075 has NO vanilla element weakness -- the class row is its "
    .. "entire break axis")
  check(rb(MPROP + 0x0075 * MREC + OFF_ABSORB) & BOLT ~= 0,
    "rhinox $075 ABSORBS bolt -- the area's taught element would heal it, "
    .. "which is why bludgeon alone is legitimate here")
  -- and that a party CAN pay it: Sabin or Gau bring bludgeon for free.
  local payable = 0
  for _, p in ipairs(parties) do
    if p.cls & BLUDG ~= 0 then payable = payable + 1 end
  end
  check(payable == 5, string.format(
    "%d of the 6 free four-parties already hold bludgeon (the sixth, "
    .. "Edgar+Cyan, buys a Flail or Full Moon in any of four towns)", payable))
end

-- ------------------------------------------- slash is no longer the A button
-- The failure this pass exists to fix: under the generated floor, SLASH
-- answered 100% of the draws in group 106, the deepest third of the facility
-- (Gobbler by outright default, Rhinox by a `rhino` keyword on the wrong
-- body), and the dungeon hands the player four swords on the way in.
do
  local slashW, bludgW, pierceW, total = 0, 0, 0, 0
  for _, e in ipairs(randForms) do
    local keys = formationKeys(e.f)
    total = total + e.w
    if keys & SLASH  ~= 0 then slashW  = slashW  + e.w end
    if keys & PIERCE ~= 0 then pierceW = pierceW + e.w end
    if keys & BLUDG  ~= 0 then bludgW  = bludgW  + e.w end
  end
  emu.log(string.format(
    "breakvector: key share (equal-map) slash %.2f%% pierce %.2f%% bludg %.2f%%",
    100 * slashW, 100 * pierceW, 100 * bludgW))
  print(string.format(
    "breakvector: key share (equal-map) slash %.2f%% pierce %.2f%% bludg %.2f%%",
    100 * slashW, 100 * pierceW, 100 * bludgW))
  check(math.abs(total - 1.0) < 1e-6, string.format(
    "draw weights sum to 1.0 (got %.6f)", total))
  -- The inversion the section was authored to produce.  Before the pass this read
  -- slash 67.86%, bludgeon 14.29%.
  check(bludgW > slashW, string.format(
    "bludgeon (%.2f%%) outranks slash (%.2f%%) as an area key -- slash is no "
    .. "longer the automatic answer", 100 * bludgW, 100 * slashW))
  check(slashW < 0.35, string.format(
    "slash keys only %.2f%% of draws (was 67.86%% under the generated floor)",
    100 * slashW))
end

-- Group 106 specifically: the deep pool must NOT be uniformly slash again.
do
  local slashAll = true
  for i = 0, 3 do
    local f = rw(RANDGRP + 106 * 8 + i * 2)
    if formationKeys(f) & SLASH == 0 then slashAll = false end
  end
  check(not slashAll,
    "group 106 (maps 271/273, the deep facility) is not 100% slash-keyed -- "
    .. "the exact monoculture the generated floor produced there")
end

-- ------------------------------------------------- the minecart's element puzzle
-- Both Mag Roaders are named "Mag Roader", so the name-keyed floor generator
-- could not tell them apart even in principle.  They are OPPOSED: $006 is
-- fire-weak and ABSORBS ice, $0af is ice-weak, and formation $075 puts them in
-- one fight, so the wrong splash heals half the screen.  The class rows are
-- deliberately identical so the class axis does not flatten that puzzle.
do
  check(rb(MPROP + 0x0006 * MREC + OFF_WEAK) & FIRE ~= 0
    and rb(MPROP + 0x0006 * MREC + OFF_ABSORB) & ICE ~= 0,
    "mag roader $006 is fire-weak and absorbs ice (the trap half)")
  check(rb(MPROP + 0x00af * MREC + OFF_WEAK) & ICE ~= 0,
    "mag roader $0af is ice-weak (the other half)")
  check(S[0x0006] ~= nil and S[0x00af] ~= nil
    and S[0x0006][2] == S[0x00af][2],
    "both mag roaders carry the SAME class row -- the element is what "
    .. "distinguishes the pair, and the class axis must not flatten it")
  local both = formationSpecies(0x075)
  check(#both == 2, string.format(
    "formation $075 still puts both mag roaders in one fight (%d bodies)",
    #both))
end

if fails == 0 then
  emu.log("breakvector: Vector area authored, reachable and no longer slash-led - PASS")
  print("breakvector: PASS")
  emu.stop(0)
else
  emu.log(string.format("breakvector: %d assertion(s) FAILED", fails))
  print(string.format("breakvector: %d assertion(s) FAILED", fails))
  emu.stop(1)
end
