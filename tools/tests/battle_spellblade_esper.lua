-- @suite slow
-- battle_spellblade_esper.lua -- the Rune Knight's list follows the esper
-- CELES wears (#563).
--
-- ot6_rune.asm: the Runic command opens a list (the Tools shell, w7e6168 =
-- 7) of Runic ($D0), one blade row per element she can cast in this battle
-- ($D1 + the element's bit: fire, ice, bolt, poison, wind, pearl, earth,
-- water) priced, with no boost pending, at the cheapest spell of that element
-- she holds (a pending boost climbs the row up its element's line, and its
-- price with it: battle_spellblade's), and Break
-- Blade ($D9, 99 MP) once it is learned (event switch $0266 or $00A4).  "Can
-- cast" is her battle Magic list (Ot6BladeSpell walks it: the pointer at
-- $302C + her entity offset, row 0 the esper, rows 1-54 the spells, four
-- bytes each), which holds her own spells and what her worn esper lends, so
-- the rows change with the stone and keep no state of their own.
--
-- Played: Continue the wor-tomb-v1 battery (Darill's Tomb's save point;
-- CELES seated, Ifrit owned and on a seated member), and three times walk
-- the east room into a random battle, open her list through the real menu
-- (H.kitBattle's peek: A on the command, the cells read, B) and fight the
-- battle out with the route's fight driver; between the battles the stones
-- move through the field's Skills menu (H.equipEsper: a stone comes off its
-- wearer with A on an empty row of their list).  Nothing is written.
--   1. with the esper she boots with;
--   2. Ifrit on her (off its wearer first): Fire Blade ($D1) is listed, at
--      Fire's price;
--   3. Ifrit handed to another seated member, so she wears none: Fire Blade
--      is gone, Ice Blade ($D2) is listed at Ice's price, and the rows are
--      those of the spells she holds by herself (the learned table $1A6E,
--      Break from level 13, Ot6CelesBreak, and what her gear grants,
--      Ot6ItemGrantTbl).
-- In each the list is read with no boost pending, and its rows are the same
-- with Imp left out of her spells (Break took Imp's place at 13 in her
-- natural magic; a save from before still holds Imp, which has no element).
-- Asserted in each: the list's cells ($4005 + 3i: id, price, flags $02; read
-- down the left column, then the right) are exactly the rows the suite
-- computes from her live battle Magic list and the ROM's MagicProp (+1 the
-- elements, +5 the MP, through her Gold Hairpin or Economizer as Ot6SpellMP
-- does), in element bit order, Runic first and Break Blade last, the blades
-- cut off where the shell's eight cells end.  A screenshot of each list:
-- spellblade_esper_<n>.
-- Mutant red (every spell counts for every element):
-- build/attempts/wt/v051-spellblade/sb2/C/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, RUNIC = 0x06, 0x0B
local IFRIT = 1                      -- esper index: $1A69 bit 1, +$1E of a record
local FIRE, ICE, BREAK, IMP = 0x00, 0x01, 0x0C, 0x23   -- spell ids
local ROW_RUNIC, ROW_BLADE, ROW_BREAK, BREAK_MP = 0xD0, 0xD1, 0xD9, 99
local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF
local ITEM_GRANTS = H.sym("Ot6ItemGrantTbl") & 0x3FFFFF
local BLADE = { [0] = "Fire", "Ice", "Bolt", "Poison", "Wind", "Pearl", "Earth", "Water" }

local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function worn(c) return H.readByte(0x1600 + 37 * c + 0x1E) end
local function posOf(c) return (H.readByte(0x1850 + c) >> 3) & 3 end
local function seated(c)
  local pb = H.readByte(0x1850 + c)
  return (pb & 7) ~= 0 and (pb & 7) == (H.readByte(0x1A6D) & 7)
end
local function wearerOf(esper)
  for c = 0, 15 do if worn(c) == esper then return c end end
end
local function elements(spell) return H.readRomByte(MAGIC_PROP + spell * 14 + 1) end
local function breakLearned() return sw(0x0266) == 1 or sw(0x00A4) == 1 end

-- a spell's price for the member in battle seat `seat` (Ot6SpellMP: the
-- Economizer's 1 beats the Gold Hairpin's half, rounded up)
local function price(seat, spell)
  local mp, relic = H.readRomByte(MAGIC_PROP + spell * 14 + 5), H.readByte(0x3C45 + seat * 2)
  if (relic & 0x40) ~= 0 then return 1 end
  if (relic & 0x20) ~= 0 then return (mp + 1) // 2 end
  return mp
end
-- the spells of seat's battle Magic list
local function battleSpells(seat)
  local ptr, t = H.readWord(0x302C + seat * 2), {}
  for r = 1, 54 do
    local id = H.readByte(ptr + r * 4)
    if id < 0x36 then t[#t + 1] = id end
  end
  return t, H.readByte(ptr)
end
-- the spells CELES holds by herself: the learned table, Break from level 13
-- whatever the table says (Ot6CelesBreak: a save from before Break took
-- Imp's place in her natural magic), and her gear's grants
local function ownSpells()
  local t, actor = {}, H.charActor(CELES)
  for id = 0, 0x35 do
    if H.readByte(0x1A6E + 54 * actor + id) == 0xFF then t[#t + 1] = id end
  end
  if H.readByte(0x1600 + 37 * CELES + 8) >= 13 then t[#t + 1] = BREAK end
  for i = 0, 63 do
    local item = H.readRomByte(ITEM_GRANTS + i * 2)
    if item == 0xFF then break end
    for s = 0, 5 do
      if H.readByte(0x1600 + 37 * CELES + 0x1F + s) == item then t[#t + 1] = H.readRomByte(ITEM_GRANTS + i * 2 + 1) end
    end
  end
  return t
end
-- the list's rows for a set of spells: { id, price }, Runic, the blades in
-- element bit order, Break Blade; the shell holds eight cells and Break
-- Blade keeps the last (Ot6RuneListOpen)
local function rowsFor(seat, spells)
  local cheapest = {}
  for _, id in ipairs(spells) do
    local el, p = elements(id), price(seat, id)
    for b = 0, 7 do
      if (el & (1 << b)) ~= 0 and (cheapest[b] == nil or p < cheapest[b]) then cheapest[b] = p end
    end
  end
  local rows, limit = { { ROW_RUNIC, 0 } }, breakLearned() and 7 or 8
  for b = 0, 7 do
    if cheapest[b] ~= nil and #rows < limit then rows[#rows + 1] = { ROW_BLADE + b, cheapest[b] } end
  end
  if breakLearned() then rows[#rows + 1] = { ROW_BREAK, BREAK_MP } end
  return rows
end
local function said(rows)
  local t = {}
  for _, r in ipairs(rows) do t[#t + 1] = string.format("%02X:%d", r[1], r[2]) end
  return table.concat(t, " ")
end
local function has(rows, id)
  for _, r in ipairs(rows) do if r[1] == id then return r end end
end
local function hexes(t)
  local s = {}
  for _, b in ipairs(t) do s[#s + 1] = string.format("%02X", b) end
  return table.concat(s, " ")
end

-- one reading of the open list, taken by kitBattle's peek
local read = {}
local stage = 0
local function onList(_, seat)
  if read[stage] ~= nil then return end
  local got, flags = {}, {}
  -- the cells in the order the list packs them: the left column, then the right
  for _, i in ipairs({ 0, 2, 4, 6, 1, 3, 5, 7 }) do
    local id = H.readByte(0x4005 + i * 3)
    if id ~= 0xFF then
      got[#got + 1] = { id, H.readByte(0x4006 + i * 3) }
      flags[#flags + 1] = H.readByte(0x4007 + i * 3)
    end
  end
  local spells, esperRow = battleSpells(seat)
  local noImp = {}
  for _, id in ipairs(spells) do if id ~= IMP then noImp[#noImp + 1] = id end end
  read[stage] = { got = got, flags = flags, mode = H.readByte(0x6168), seat = seat, spells = spells,
    esperRow = esperRow, want = rowsFor(seat, spells), own = rowsFor(seat, ownSpells()),
    noImp = rowsFor(seat, noImp), pend = H.readByte(0x3E9D + seat * 2),
    fire = price(seat, FIRE), ice = price(seat, ICE), mp = H.readWord(0x3C08 + seat * 2), f = H.frame }
  local r = read[stage]
  H.log(string.format("[sbe] %d: f%d CELES (seat %d, stone $%02X, MP %d, %d BP pending) opens her list: mode %d, rows "
    .. "%s; her battle Magic list holds %s (esper row $%02X); learned Imp $%02X, Break $%02X, level %d", stage, r.f,
    seat, worn(CELES), r.mp, r.pend, r.mode, said(got), hexes(spells), esperRow,
    H.readByte(0x1A6E + 54 * H.charActor(CELES) + IMP), H.readByte(0x1A6E + 54 * H.charActor(CELES) + BREAK),
    H.readByte(0x1600 + 37 * CELES + 8)))
  H.screenshot("spellblade_esper_" .. stage)
end

-- the tomb's east room (battle_runicblade's walk)
local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "sbe: a random battle in the east room")
end
-- the route's fight driver fights the battle out from wherever it stands
local function fightOut(tag)
  local F = nil
  return H.withReset(H.driveUntil(function() return not H.battleLoadStarted() end, 60000, {
    H.call(function()
      if F == nil then
        F = H.newFightDriver(tag, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55,
          setzer = false })
      end
      F.frame()
    end),
  }, tag .. ": the battle fought out"), function() if F then F.idle() end; F = nil end)
end
-- a battle in which CELES opens her list (one she cannot act in is fought
-- out and the next taken: BATTLES bounds them), fought out after the read
local BATTLES = 6
local function listed(n)
  local tries = 0
  return H.seqStep({
    H.call(function() stage, tries = n, 0 end),
    H.driveUntil(function() return read[n] ~= nil and not H.battleLoadStarted() end, 400000, {
      H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "sbe: control before the walk", 5),
      H.fieldCare({ tag = "sbe: care before the walk", threshold = 0.95 }),
      H.call(function()
        tries = tries + 1
        H.assertEq(tries <= BATTLES, true, string.format("%d: CELES opened her list within %d battles", n, BATTLES))
      end),
      walkToBattle(),
      H.waitUntil(function() return H.battleActive() end, 1200, "sbe: the battle is up", 2),
      H.waitFrames(30),
      H.kitBattle({ { who = CELES, cmd = RUNIC, peek = true } }, { untilPlanDone = true, idle = "defend",
        maxFrames = 20000, onList = onList, planDone = function() return read[n] ~= nil end }),
      fightOut("sbe " .. n),
    }, "sbe: " .. n .. ": the list read and the battle over"),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "sbe: control after the battle", 5),
  })
end
-- the checks every reading passes: the Rune Knight's list, its rows exactly
-- the computed ones
local function common(n, what)
  local r = read[n]
  H.assertEq(r.mode, 7, string.format("%d (%s): the window is the Rune Knight's list (w7e6168 = 7)", n, what))
  H.assertEq(r.pend, 0, string.format("%d (%s): the list was read with no boost pending (a pending boost climbs a "
    .. "blade row's line, and its price cell with it)", n, what))
  H.assertEq(said(r.noImp), said(r.want), string.format("%d (%s): the rows do not turn on Imp (the spell Break "
    .. "replaced at 13 in her natural magic, which an older save still holds): the same without it", n, what))
  H.assertEq(said(r.got), said(r.want), string.format("%d (%s): the rows are Runic, a blade for each element of her "
    .. "battle Magic list at its cheapest spell's price, in bit order, and Break Blade when learned (switch $0266 %d, "
    .. "$00A4 %d)", n, what, sw(0x0266), sw(0x00A4)))
  for i, f in ipairs(r.flags) do
    H.assertEq(f, 0x02, string.format("%d (%s): row %d ($%02X) takes the caster's own cursor (flags $02)", n, what, i,
      r.got[i][1]))
  end
  local names = {}
  for _, row in ipairs(r.got) do
    if row[1] >= ROW_BLADE and row[1] < ROW_BREAK then names[#names + 1] = BLADE[row[1] - ROW_BLADE] .. " " .. row[2] end
  end
  H.log(string.format("[sbe] %d (%s) OK: %s; blades: %s", n, what, said(r.got), table.concat(names, ", ")))
end

local start, other = nil, nil
local steps = {
  H.bootCheckpoint("wor-tomb-v1"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "sbe: control", 5),
  H.call(function()
    H.assertEq(seated(CELES), true, "CELES is seated (gen_wor_tomb's party at Darill's Tomb's save point)")
    H.assertEq(H.readByte(0x1A69) & (1 << IFRIT), 1 << IFRIT, "the party owns Ifrit ($1A69 bit 1): gen_ifrit_magicite, "
      .. "the Magitek factory's leg, takes its magicite")
    local w = wearerOf(IFRIT)
    H.assertEq(w == nil or seated(w), true, string.format("Ifrit is in the bag or on a seated member (char %s wears "
      .. "it): the field's Skills menu reaches only the seated (gen_wor_sabin puts it on SABIN)", tostring(w)))
    -- who takes Ifrit off her again: its wearer now, else any other seated member
    if w ~= nil and w ~= CELES then other = w end
    for c = 0, 13 do if other == nil and c ~= CELES and seated(c) then other = c end end
    H.assertEq(other ~= nil, true, "another member is seated, to hand Ifrit to")
    start = worn(CELES)
    H.assertEq(elements(FIRE), 0x01, "MagicProp: Fire's element byte is fire ($01)")
    H.assertEq(elements(ICE), 0x02, "MagicProp: Ice's element byte is ice ($02)")
    H.assertEq(H.readByte(0x1A6E + 54 * H.charActor(CELES) + ICE), 0xFF, "CELES knows Ice by herself (her natural "
      .. "magic, the learned table)")
    H.log(string.format("[sbe] CELES wears stone $%02X; Ifrit is on char %s; char %d takes it back in step 3; Break "
      .. "Blade learned: %s", start, tostring(w), other, tostring(breakLearned())))
  end),

  -- PACE_BURN (a lab's global, 0 here): flee that many encounters first, to
  -- vary the encounter history (battle_runicblade's lever)
  (function()
    local burned, burn = 0, type(PACE_BURN) == "number" and PACE_BURN or 0
    return H.driveUntil(function() return burned >= burn end, 400000, {
      walkToBattle(),
      H.waitUntil(function() return H.battleActive() end, 1200, "sbe: a battle to burn is up", 2),
      H.fleeBattle(9000, { onCantRun = "fight" }),
      H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "sbe: control after the burn", 5),
      H.fieldCare({ tag = "sbe: care after a burned encounter", threshold = 0.95 }),
      H.call(function() burned = burned + 1; H.log(string.format("[sbe] burned encounter %d of %d", burned, burn)) end),
    }, "sbe: the encounters PACE_BURN uses up")
  end)(),

  -- 1. the esper she boots with
  listed(1),
  H.call(function()
    common(1, string.format("stone $%02X, as booted", start))
    H.assertEq(worn(CELES), start, "1: she still wears the stone she booted with")
  end),

  -- 2. Ifrit on her
  H.equipEsper(function() return posOf(CELES) end, IFRIT, { tag = "sbe: Ifrit -> CELES" }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "sbe: control after the menu", 5),
  listed(2),
  H.call(function()
    common(2, "Ifrit")
    local r = read[2]
    H.assertEq(worn(CELES), IFRIT, "2: CELES wears Ifrit")
    H.assertEq(r.esperRow, IFRIT, "2: her battle Magic list's esper row is Ifrit")
    local lent = false
    for _, id in ipairs(r.spells) do if id == FIRE then lent = true end end
    H.assertEq(lent, true, "2: Ifrit lends Fire: it is in her battle Magic list")
    local row = has(r.got, ROW_BLADE + 0)
    H.assertEq(row ~= nil, true, "2: Fire Blade ($D1) is listed with Ifrit on her")
    H.assertEq(row[2], r.fire, string.format("2: Fire Blade costs what Fire costs her (%d MP)", r.fire))
  end),

  -- 3. no esper on her
  H.equipEsper(function() return posOf(other) end, IFRIT, { tag = "sbe: Ifrit off CELES" }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "sbe: control after the menu", 5),
  H.call(function() H.assertEq(worn(CELES), 0xFF, "3: CELES wears no esper (Ifrit went to another member)") end),
  listed(3),
  H.call(function()
    common(3, "no esper")
    local r = read[3]
    H.assertEq(worn(CELES), 0xFF, "3: CELES wears no esper")
    H.assertEq(r.esperRow, 0xFF, "3: her battle Magic list's esper row is empty")
    H.assertEq(has(r.got, ROW_BLADE + 0), nil, "3: Fire Blade ($D1) is gone with the stone that lent Fire")
    local row = has(r.got, ROW_BLADE + 1)
    H.assertEq(row ~= nil, true, "3: Ice Blade ($D2) is listed: Ice is her own")
    H.assertEq(row[2], r.ice, string.format("3: Ice Blade costs what Ice costs her (%d MP)", r.ice))
    H.assertEq(said(r.got), said(r.own), "3: the rows are those of the spells she holds by herself (the learned "
      .. "table and her gear's grants)")
    H.assertEq(said(read[2].got) ~= said(r.got), true, "the list with Ifrit and the list without differ")
    H.log(string.format("[sbe] PASS: the Rune Knight's list followed the esper: %s | Ifrit %s | none %s",
      said(read[1].got), said(read[2].got), said(r.got)))
  end),
}
H.run({ maxFrames = 900000 }, steps)
