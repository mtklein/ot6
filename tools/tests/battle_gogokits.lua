-- @suite slow savestate=wor_leo
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_gogokits.lua -- each command GOGO picks opens its owner's whole kit
-- (#547; docs/design/kit-gogo.md).
--
-- The owner (2026-11-15): "he should be able to get full kits as much as
-- possible ... we basically want to let him have access to everything cool
-- about each character."  The pieces keyed on the owner's actor id now take
-- GOGO too (ot6_gogo.asm); the rest were keyed on the command already.  This
-- suite gives GOGO the commands through the field Status menu, as a player
-- does, and plays them through the real battle menu (H.kitBattle).
--
-- Played, with three declared stagings (state_write_waivers.txt; below):
-- Continue wor-colosseum-v1 (beside the Falcon by
-- Maranda), board, and in the Falcon's cabin seat GOGO, TERRA, RELM and
-- SHADOW (no STRAGO and no CELES: both cast Scan, and the Lore round reads
-- whether GOGO's own Lore brings it); in the Equip menu put the SwordBreaker
-- the Colosseum won (gen_wor_colosseum) in GOGO's hand, the one weapon of
-- his whose SwdTech bit lets SwdTech open (UpdateCmd_02: vanilla greys
-- SwdTech under any other weapon, Cyan's too) and whose Runic bit lets
-- Runic open; lift off, land again and pace the world map by Maranda into
-- random battles.  Four rounds, each its three commands
-- set in GOGO's Status menu (row 0 stays Mimic) and then played in whatever
-- battles come; the others Defend while GOGO banks his points, a battle
-- that turns dangerous (a seated member down or under a third of max HP)
-- is handed to the route's fight driver, and what it did not finish is
-- played in the next battle.  Asserted:
--   R1 Magic, Slot, Tools
--     * his Magic list holds TERRA's Fire and neither Scan nor Bserk (no
--       Lore yet: the negative for R2), and no other seated member's does;
--     * Slot opens SETZER's table (w7e6168 = 4): Slot, Coin Toss, Hired Help
--       and Jackpot, learned (switch $00CA);
--     * Fire at 3 BP is Ultima (TERRA's fourth fold, switch $00BF), priced
--       as Ultima;
--     * Jackpot at 3 BP throws two rolls for 99 MP; the third staging
--       raises every present monster's HP to 30,000 as the Jackpot begins
--       (battle_hireimp's expedient): a roll lands at most 9,999, so the
--       body aimed at outlasts the first and the second is thrown at it (a
--       pass stays on its aim, #545);
--     * Debilitator at 3 BP fires twice (Overclock, switch $0068) for the
--       two firings' price (H.toolPrice, 80 MP),
--       and its Ot6AssassinateGate visits stop at the command test (the
--       Throw negative).
--   R2 Magic, Lore, Runic
--     * his Magic list holds Scan, and Bserk once STRAGO has learned it;
--     * his Lore rows are STRAGO's loadout (H.loreList) and Aqua Rake;
--     * Scan at 3 BP on a monster is Study: 99 MP, and Ot6StudyOne adds
--       exactly the present species' lores STRAGO lacks, and the victory
--       teaches them.  STRAGO already knows every lore this plain's casters
--       cast (the Crawler's, the Sprinter's Pearl Wind), so the first
--       staging unlearns those in $1D29 at the open of the battle GOGO
--       studies in (battle_study's expedient), and puts them back if no
--       study taught them; a battle with no caster present waits;
--     * Runic opens the Rune Knight's list (#563, ot6_rune.asm; w7e6168 = 7)
--       with GOGO's own rows: Runic, a blade row for each element his battle
--       spell list holds a spell of (the seated party's union, read from
--       $302C and the ROM's MagicProp: bit order, the cheapest spell's price
--       through his relics, cut to the cells the shell has), and Break Blade,
--       learned (switch $0266 or $00A4), 99;
--     * Runic at 3 BP is a RunicBlade: TERRA's Fire cast into it comes back
--       at her as a counter, and the absorb arms GOGO's rune with Fire's
--       element (Ot6RuneAbsorb's GOGO gate; OT6_RUNE at his seat) at tier 1
--       (OT6_RUNETIER); her Fire at 1 BP, cast as Fire 2, arms tier 2;
--     * a blade row he picks takes his turn at 0 BP, arms OT6_RUNE at his
--       seat with its element at tier 1 and costs him that spell's MP;
--     * a row whose element has a line (Fire's), with one point: the list
--       prices each climbing row at its line's second spell (Ot6FoldTbl), and
--       the row arms tier 2 for that spell's MP and spends the point;
--     * a row with no line (Pearl's or W Wind's): R on it is refused, and a
--       point raised on the command window before it is dropped, not
--       charged; it arms tier 1;
--     * Break Blade under three points is refused (three A presses leave the
--       list up, with 99 MP in hand, nothing started and nothing charged); at
--       3 BP it costs 99 MP and OT6_BREAKBLADE at his seat reads 3 once the
--       cast has resolved.
--   R3 Throw, TresHnt (Steal), Blitz
--     * Steal opens LOCKE's list (w7e6168 = 3) with exactly the rows his
--       story has taught (Ot6ThiefRowTbl's switches);
--     * Blitz opens SABIN's list with Bum Rush, and Bum Rush at 3 BP is four
--       blows for 99 MP;
--     * a Shuriken thrown at 3 BP passes Ot6AssassinateGate's actor and
--       command test (SHADOW's divine on GOGO's Throw) and marks Death on
--       the Broken non-boss it hits; at 2 BP it marks none.  The second
--       staging breaks every standing non-boss monster (OT6_BROKEN_TICKS) as
--       GOGO's 2- or 3-BP throw begins: no party here breaks one on cue.  The
--       throw is aimed at a body the staging can break (one without a Death
--       ward), and counted only when it was.
--   R4 SwdTech, Rage, Dance
--     * SwdTech opens CYAN's window with Cleave on its 3 BP row, and Cleave
--       at 3 BP runs Cleave for 99 MP;
--     * his Rage list is GAU's loadout; his dances are MOG's.
--   R5 from gen_wor_leo's state after Leo's reveal (#552: the slot keeps
--     actor $0C, so every kit stays his): Slot, Tools, Throw -- SETZER's
--     table, Overclock, and Assassinate on his Throw (staged as in R3).
-- And: BattleCmdName's record $0D reads "Painter" (the owner, 2026-11-21:
-- Relm's command is Painter; GOGO's Painter list is battle_relmwor's).
-- Old-ROM red and mutants: build/attempts/wt/v050-gogo-kits/.
--
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- GOGOKITS_BURN ahead of the file): the walker fights that many encounters
-- by the landing first, and again after R5's state loads, to vary the
-- encounter history (TESTING.md).  A second lever, GOGOKITS_ROUNDS (a
-- string of round tags, "R2"): only those rounds are played (a lab's or a
-- mutant's run of one round; the suite plays all five).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, SHADOW, RELM, GOGO, STRAGO = 0x00, 0x03, 0x08, 0x0C, 0x07
local NAMES = { [TERRA] = "TERRA", [SHADOW] = "SHADOW", [RELM] = "RELM", [GOGO] = "GOGO", [STRAGO] = "STRAGO" }
local CMD = { MAGIC = 0x02, STEAL = 0x05, SWDTECH = 0x07, THROW = 0x08, TOOLS = 0x09, BLITZ = 0x0A, RUNIC = 0x0B,
  LORE = 0x0C, SLOT = 0x0F, RAGE = 0x10, DANCE = 0x13 }
local FIRE, SCAN, BSERK, ULTIMA = 0x00, 0x18, 0x21, 0x14
local SLOT_ROWS = { 0x5C, 0x59, 0x5A, 0x5B }              -- Slot, Coin Toss, Hired Help, Jackpot
local JACKPOT, DEBIL, SHURIKEN, BUMRUSH, CLEAVE = 0x5B, 0xA7, 0x41, 0x64, 0x5C
local SWORDBREAKER = 0x07
local BREAK_TICKS = 16                                     -- a staged break's length (OT6_BROKEN_TICKS)
local ITEMLIST, MODE = 0x4005, 0x6168
local LISTPTR = { [0] = 0x208E, [1] = 0x21CA, [2] = 0x2306, [3] = 0x2442 }
local RUNICBLADE = 0x7EEDD4                                -- OT6_RUNICBLADE (ot6_memory.inc)
local RUNE_AT, BREAKBLADE_AT = 0x7EED8F, 0x7EEDA2          -- OT6_RUNE, OT6_BREAKBLADE (+ seat * 2)
local TIER_AT = 0x7EEE3A                                   -- OT6_RUNETIER (+ seat * 2)
local MSTATE = 0x7BC2                                      -- the battle menu's state ($30: a Tools-shell list, up)
local RUNE_RUNIC, RUNE_BLADE, RUNE_BREAK = 0xD0, 0xD1, 0xD9 -- the Rune Knight's rows (ot6_rune.asm)
local BREAK_MP, BREAK_TURNS = 99, 3
local LANDING = { 69, 183 }                                 -- the Falcon's tile by Maranda (wor-colosseum-v1's)
local BURN = type(GOGOKITS_BURN) == "number" and GOGOKITS_BURN or 0
local ONLY = type(GOGOKITS_ROUNDS) == "string" and GOGOKITS_ROUNDS or nil
local MAX_BATTLES = 30
local ROUND_BATTLES = 8                                    -- a round's entries all played within this many
local DANGER = 1 / 3
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, names = NAMES })
local regroup, liftOff, say = K.regroup, K.liftOff, K.say

local function sw(n) return (H.readByte(0x1E80 + (n >> 3)) >> (n & 7)) & 1 end
local function hx(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = string.format("%02X", v) end
  return table.concat(s, " ")
end

-- ---- GOGO's commands (gen_wor_gogo's field-menu walk) ----------------------
-- $05 main (Status row 4) -A-> $06 character select -A-> $0c status (the
-- command row) -A-> $6a the command list ($7E9D8A + row, $7E9D89 the count;
-- MenuState_6a writes the row's id to $1616 + 37*GOGO + row)
local function gogoCmdByte(row) return H.readByte(0x1600 + 37 * GOGO + 0x16 + row) end
local function gogoCommands(want, what)
  local ph, idx, listLogged = 0, 1, false
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, row)
    if cur == row then return { "a" } end
    return { [cur < row and "down" or "up"] = true }
  end
  local function gogoPos()
    local b = H.readByte(0x1850 + GOGO)
    if (b & 7) == H.activeParty() then return (b >> 3) & 3 end
    return nil
  end
  local function allSet()
    for _, w in ipairs(want) do if gogoCmdByte(w[1]) ~= w[2] then return false end end
    return true
  end
  -- control on a field map or on the world map (the later rounds start there)
  local function ctl() return H.hasControl() or (H.worldMode() and H.worldHasControl()) end
  return H.withReset(H.seqStep({
    H.driveUntil(function() return allSet() and not H.menuRunning() and ctl() end, 9000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s = st()
        local held = {}
        while idx <= #want and gogoCmdByte(want[idx][1]) == want[idx][2] do idx = idx + 1 end
        if allSet() then
          if s ~= -1 then held = { "b" } end
        elseif s == -1 then
          if ctl() then held = { "x" } end
        elseif s == 0x05 then
          held = steer(H.readByte(0x4B), 4)
        elseif s == 0x06 then
          local p = gogoPos()
          if p == nil then error(what .. ": GOGO is not in the active party", 0) end
          held = steer(H.readByte(0x4B), p)
        elseif s == 0x0C then
          held = steer(H.readByte(0x4B), want[idx][1])
        elseif s == 0x6A then
          local n = H.readByte(0x7E9D89)
          if not listLogged then
            local t = {}
            for r = 0, n - 1 do t[#t + 1] = H.readByte(0x7E9D8A + r) end
            H.log(string.format("[gogokits] %s: GOGO's command list (%d): %s", what, n, hx(t)))
            listLogged = true
          end
          local row = nil
          for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == want[idx][2] then row = r end end
          if row == nil then error(string.format("%s: command $%02X is not in GOGO's list", what, want[idx][2]), 0) end
          held = steer(H.readByte(0x4B), row)
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, what),
    H.call(function()
      H.log(string.format("[gogokits] %s: GOGO's commands %02X %02X %02X %02X", what, gogoCmdByte(0),
        gogoCmdByte(1), gogoCmdByte(2), gogoCmdByte(3)))
    end),
  }), function() ph, idx, listLogged = 0, 1, false end)
end

-- ---- the battle's seats --------------------------------------------------------
local seatOf = {}
local function findSeats()
  seatOf = {}
  for s = 0, 3 do
    local id = H.readByte(0x3ED8 + s * 2)
    if id ~= 0xFF then seatOf[id] = s end
  end
end
local function gseat() return seatOf[GOGO] end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end

-- the spell ids in a seat's Magic list (the window's own cells, battle_denselists' read)
local function magicSet(s)
  local set = {}
  for r = 1, 54 do
    local id = H.readByte(LISTPTR[s] + r * 4)
    if id ~= 0xFF then set[id] = true end
  end
  return set
end
local function loreRows(s)
  local set = {}
  for r = 55, 78 do
    local id = H.readByte(LISTPTR[s] + r * 4)
    if id ~= 0xFF then set[id] = true end
  end
  return set
end
local function keys(set)
  local t = {}
  for k in pairs(set) do t[#t + 1] = k end
  table.sort(t)
  return t
end

-- ---- the Rune Knight's list, as ot6_rune.asm builds it for seat s (#563) ------
-- Ot6RuneListOpen: Runic; a blade row $D1 + e for each element bit e (0 fire,
-- 1 ice, 2 bolt, 3 poison, 4 wind, 5 pearl, 6 earth, 7 water) that a spell of
-- the seat's battle spell list carries (the list $302C + seat*2 points at,
-- rows 1-54, ids under $36; MagicProp +1); then Break Blade, 99, once it is
-- learned (switch $0266 or $00A4).  A row's spell is the cheapest of its
-- element the seat can cast (Ot6BladeSpell: MagicProp +5 through the seat's
-- Gold Hairpin or Economizer, the list's first at a tie).  When that is the
-- head of the element's line in Ot6FoldTbl (fire, ice, bolt, poison:
-- three-byte rows, the head and the spells one and two boosts reach) the row
-- climbs (Ot6BladeClimbs): with `boost` points pending it stands for the
-- line's spell min(boost, 2) steps up (Ot6BladeRow).  The row's price is its
-- spell's MP, and the tier it arms that spell's place in its line
-- (Ot6RuneTierOf: 2 for a line's second spell, 3 for its third, else 1); a
-- row that climbs nothing arms tier 1 and takes no boost.  The shell has
-- eight cells: a blade is listed while a cell is free for it (the last is
-- Break Blade's once learned), so the last elements in bit order are cut.
-- The k-th row sits in cell (k & 3) * 2 + (k >> 2): down the left column,
-- then the right.  `cells` is the eight cells as the list holds them
-- (id.price.flags, FF for an empty one); price, tier, spell and climbs are
-- by element bit.
local function spellElem(id) return H.readRomByte((H.sym("MagicProp") & 0x3FFFFF) + id * 14 + 1) end
local function lineSpell(e, col) return H.readRomByte((H.sym("Ot6FoldTbl") & 0x3FFFFF) + e * 3 + col) end
local function runeTierOf(id)
  for e = 0, 3 do if id == lineSpell(e, 1) then return 2 end end
  for e = 0, 2 do if id == lineSpell(e, 2) then return 3 end end
  return 1
end
local function runeModel(s, boost)
  local MP = H.sym("MagicProp") & 0x3FFFFF
  local relic, list = H.readByte(0x3C45 + s * 2), H.readWord(0x302C + s * 2)
  local function spellMp(id) return H.casterSpellMp(H.readRomByte(MP + id * 14 + 5), relic) end
  local cheap = {}
  for r = 1, 54 do
    local id = H.readByte(list + r * 4)
    if id < 0x36 then
      local el, mp = H.readRomByte(MP + id * 14 + 1), spellMp(id)
      for e = 0, 7 do
        if (el >> e) & 1 == 1 and (cheap[e] == nil or mp < cheap[e].mp) then cheap[e] = { id = id, mp = mp } end
      end
    end
  end
  local m = { price = {}, tier = {}, spell = {}, climbs = {}, learned = sw(0x266) == 1 or sw(0xA4) == 1 }
  for e = 0, 7 do
    if cheap[e] ~= nil then
      m.climbs[e] = e < 4 and cheap[e].id == lineSpell(e, 0)
      m.spell[e] = m.climbs[e] and lineSpell(e, math.min(boost or 0, 2)) or cheap[e].id
      m.price[e] = spellMp(m.spell[e])
      m.tier[e] = m.climbs[e] and runeTierOf(m.spell[e]) or 1
    end
  end
  m.rows = { { RUNE_RUNIC, 0 } }
  for e = 0, 7 do
    if m.spell[e] ~= nil and #m.rows < (m.learned and 7 or 8) then
      m.rows[#m.rows + 1] = { RUNE_BLADE + e, m.price[e] }
    end
  end
  if m.learned then m.rows[#m.rows + 1] = { RUNE_BREAK, BREAK_MP } end
  local cells = {}
  for c = 0, 7 do cells[c] = "FF" end
  for k, row in ipairs(m.rows) do
    cells[((k - 1) & 3) * 2 + ((k - 1) >> 2)] = string.format("%02X.%02X.02", row[1], row[2])
  end
  m.cells = table.concat(cells, " ", 0, 7)
  return m
end
-- the open list's eight cells: id.price.flags for a listed cell, FF for an empty one
local function runeCells()
  local t = {}
  for c = 0, 7 do
    local id = H.readByte(ITEMLIST + c * 3)
    t[#t + 1] = id == 0xFF and "FF"
      or string.format("%02X.%02X.%02X", id, H.readByte(ITEMLIST + c * 3 + 1), H.readByte(ITEMLIST + c * 3 + 2))
  end
  return table.concat(t, " ")
end
local function runeAt(s) return H.readByte(RUNE_AT + s * 2) end
local function tierAt(s) return H.readByte(TIER_AT + s * 2) end
local function bankAt(s) return H.readByte(0x3E9C + s * 2) end
local function breakBladeAt(s) return H.readByte(BREAKBLADE_AT + s * 2) end

-- ---- observers ---------------------------------------------------------------
-- every action GOGO runs: { cmd, atk ($b5/$b6 at ExecCmd, after the queue's
-- fold), pend, mp0, mp1, passes (Ot6PassTargeted), dice (Ot6JackpotDice
-- entries), gate (Ot6AssassinateGate past its actor and command test),
-- marks (its Death mark), studied (Ot6StudyOne's $3A84 writes), want (the
-- lores the present species could teach that STRAGO lacks), blade (his
-- OT6_RUNICBLADE bit at the end), rune0/rune1 and bb0/bb1 (OT6_RUNE and
-- OT6_BREAKBLADE at his seat as it begins and once it has ended), tier0/tier1
-- (OT6_RUNETIER) and bank0/bank1 (his banked points) likewise, armed and
-- armedTier (the values Ot6RuneArm wrote to his OT6_RUNE and OT6_RUNETIER
-- during it), model (runeModel at its pending boost, for a Runic command's
-- action) }
local acts, cur = {}, nil
local casts = {}         -- every $3410 <- Fire by TERRA: { counter, b8, b9, f }
-- every Runic absorb by GOGO's stance (Ot6RunicBP for his seat): { f, spell
-- ($b6), elem ($11a1), caster (the character id), rune0, armed and armedTier
-- (Ot6RuneArm's writes to his OT6_RUNE and OT6_RUNETIER that followed), rune1
-- and tier1 (his rune and its tier a frame later) }
local absorbs = {}
local function present(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 end
local function species(m) return H.readWord(0x57C0 + m * 2) end
local function lores() return H.readByte(0x1D29) | H.readByte(0x1D2A) << 8 | H.readByte(0x1D2B) << 16 end
local function studyRow(sp)
  local a = H.sym("Ot6StudyTbl") & 0x3FFFFF
  while true do
    local s = H.readRomByte(a) | H.readRomByte(a + 1) << 8
    if s == 0xFFFF then return 0 end
    if s == sp then return H.readRomByte(a + 2) | H.readRomByte(a + 3) << 8 | H.readRomByte(a + 4) << 16 end
    a = a + 5
  end
end
-- Ot6AssassinateGate's boost test, `lda OT6_BOOST_REVEALED,x / cmp #$03 /
-- bcc`: reached only past the actor and command test
local function findGateBoost()
  local base = H.sym("Ot6AssassinateGate") & 0x3FFFFF
  local pat = { 0xBD, 0x9D, 0x3E, 0xC9, 0x03, 0x90 }
  for off = 0, 0x40 do
    local hit = true
    for i = 1, #pat do
      if H.readRomByte(base + off + i - 1) ~= pat[i] then hit = false; break end
    end
    if hit then return H.sym("Ot6AssassinateGate") + off end
  end
  error("Ot6AssassinateGate's boost test (lda $3e9d,x / cmp #$03 / bcc) not found")
end
-- close GOGO's action once its end has passed (the MP settles after the charge)
local function closeAct()
  if cur == nil or not cur.ended or H.frame <= cur.ended + 1 then return false end
  cur.mp1 = mpOf(gseat())
  cur.rune1, cur.bb1 = runeAt(gseat()), breakBladeAt(gseat())
  cur.tier1, cur.bank1 = tierAt(gseat()), bankAt(gseat())
  acts[#acts + 1] = cur
  H.log(string.format("[gogokits] GOGO's action %d: cmd $%02X atk $%02X at %d BP (f%d): MP %d -> %d, passes %d, "
    .. "dice %d, gate %d, marks %d, studied $%06X (want $%06X), blade %s, monsters after $%02X; rune $%02X -> $%02X "
    .. "(armed %s), tier %d -> %d (armed %s), break blade %d -> %d, bank %d -> %d", #acts, cur.cmd, cur.atk,
    cur.pend, cur.f, cur.mp0, cur.mp1, cur.passes, cur.dice, cur.gate, cur.marks, cur.studied, cur.want,
    tostring(cur.blade), cur.liveEnd, cur.rune0, cur.rune1, cur.armed and string.format("$%02X", cur.armed) or "none",
    cur.tier0, cur.tier1, tostring(cur.armedTier or "none"), cur.bb0, cur.bb1, cur.bank0, cur.bank1))
  cur = nil
  return true
end
-- an absorb's rune, read once the frame it happened in has passed
local function closeAbsorbs()
  local ab = absorbs[#absorbs]
  if ab == nil or ab.rune1 ~= nil or H.frame <= ab.f or gseat() == nil then return end
  ab.rune1, ab.tier1 = runeAt(gseat()), tierAt(gseat())
  H.log(string.format("[gogokits] f%d GOGO's stance absorbed spell $%02X (element $%02X) cast by %s: his rune $%02X "
    .. "-> $%02X (armed %s), tier %d -> %d (armed %s)", ab.f, ab.spell, ab.elem,
    NAMES[ab.caster] or string.format("$%02X", ab.caster), ab.rune0, ab.rune1,
    ab.armed and string.format("$%02X", ab.armed) or "none", ab.tier0, ab.tier1, tostring(ab.armedTier or "none")))
end

local installed = false
local function install()
  if installed then return end
  installed = true
  local function cpu() return emu.getState() end
  local function pc(st) return (st["cpu.k"] << 16) | st["cpu.pc"] end
  emu.addMemoryCallback(function()
    local s = gseat()
    if s == nil or (cpu()["cpu.x"] & 0xFF) ~= s * 2 or (H.readByte(0xB1) & 1) == 1 then return end
    local want = 0
    for m = 0, 5 do if present(m) then want = want | studyRow(species(m)) end end
    cur = { cmd = H.readByte(0xB5), atk = H.readByte(0xB6), pend = H.readByte(0x3E9D + s * 2), mp0 = mpOf(s),
      passes = 0, dice = 0, gate = 0, marks = 0, studied = 0, want = want & ~lores() & 0xFFFFFF, f = H.frame,
      rune0 = runeAt(s), bb0 = breakBladeAt(s), tier0 = tierAt(s), bank0 = bankAt(s) }
    -- the model's rows, prices and tiers at this action's pending boost, read while the seat's list and relics
    -- are the battle's
    if cur.cmd == CMD.RUNIC then cur.model = runeModel(s, cur.pend) end
    if cur.cmd == CMD.SLOT and cur.atk == JACKPOT and cur.pend >= 3 then
      -- the third declared staging: every present monster's HP raised to
      -- 30,000 as the Jackpot begins (battle_hireimp's expedient), so the
      -- first roll (at most 9,999) never fells the body and the second roll
      -- is always thrown at it (a pass stays on its aim, #545)
      for m = 0, 5 do
        if present(m) and H.readWord(0x3BF4 + 8 + m * 2) > 0 then H.writeWord(0x3BF4 + 8 + m * 2, 30000) end
      end
    end
    if cur.cmd == CMD.TOOLS then
      cur.toolPrice = H.toolPrice(s, H.abilityCost(cur.atk), cur.pend, cur.atk)
    end
    if cur.cmd == CMD.THROW and cur.pend >= 2 then
      -- the declared staging (state_write_waivers.txt): every standing
      -- non-boss monster is Broken as GOGO's 2- or 3-BP throw begins, so the
      -- divine has a body it may kill (no draw on this plain lets the party
      -- break one on cue); OT6_BROKEN_TICKS is what Ot6AssassinateGate reads
      cur.staged = 0
      for m = 0, 5 do
        local e = 8 + m * 2
        if present(m) and H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3AA1 + e) & 0x04) == 0 then
          H.writeByte(0x3E88 + e, BREAK_TICKS)
          cur.staged = cur.staged | (1 << m)
        end
      end
      -- the body the throw is aimed at ($b9, the action's monster targets):
      -- a throw at a body that could not be staged (it wards Death) is not
      -- the divine's to judge
      cur.tgt = H.readByte(0xB9)
      if cur.staged == 0 then
        H.log(string.format("[gogokits] f%d GOGO's %d-BP throw: no standing monster without a Death ward to "
          .. "stage: not counted, played again next battle", H.frame, cur.pend))
      elseif (cur.tgt & cur.staged) == 0 then
        H.log(string.format("[gogokits] f%d GOGO's %d-BP throw is aimed at monsters $%02X, none of the staged "
          .. "$%02X: not counted, played again next battle", H.frame, cur.pend, cur.tgt, cur.staged))
      end
    end
    if cur.cmd == CMD.MAGIC then
      -- the model's prices, read while the seat's relics are the battle's
      cur.fire3, cur.ultima0 = H.battleSpellPrice(s, FIRE, 3), H.battleSpellPrice(s, ULTIMA, 0)
    end
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if cur and not cur.ended and (cpu()["cpu.x"] & 0xFF) == gseat() * 2 then cur.passes = cur.passes + 1 end
  end, emu.callbackType.exec, pt, pt)
  local jd = H.sym("Ot6JackpotDice")
  emu.addMemoryCallback(function()
    if cur and not cur.ended and (cpu()["cpu.y"] & 0xFF) == gseat() * 2 then
      cur.dice = cur.dice + 1
      cur.aim = cur.aim or H.readByte(0xB9)       -- the first roll's monster mask: the body aimed at
    end
  end, emu.callbackType.exec, jd, jd)
  local gb = findGateBoost()
  emu.addMemoryCallback(function()
    if cur and not cur.ended and (cpu()["cpu.x"] & 0xFF) == gseat() * 2 then cur.gate = cur.gate + 1 end
  end, emu.callbackType.exec, gb, gb)
  local ag = H.sym("Ot6AssassinateGate")
  emu.addMemoryCallback(function(a, v)
    local p = pc(cpu())
    if cur and not cur.ended and p >= ag and p < ag + 0x60 and (v & 0x80) ~= 0 then cur.marks = cur.marks + 1 end
  end, emu.callbackType.write, 0x7E3DD4, 0x7E3DE7)
  local so = H.sym("Ot6StudyOne")
  emu.addMemoryCallback(function(addr, v)
    local p = pc(cpu())
    if cur and not cur.ended and p >= so and p < so + 96 then
      cur.studied = cur.studied | (v << (8 * (addr - 0x7E3A84)))
    end
  end, emu.callbackType.write, 0x7E3A84, 0x7E3A86)
  emu.addMemoryCallback(function(_, v)
    local t = seatOf[TERRA]
    if v ~= FIRE or t == nil or H.readByte(0x3A7C) ~= CMD.MAGIC then return end
    casts[#casts + 1] = { counter = (H.readByte(0xB1) & 1) == 1, b8 = H.readByte(0xB8), b9 = H.readByte(0xB9),
      f = H.frame }
    local c = casts[#casts]
    H.log(string.format("[gogokits] f%d Fire: counter=%s targets chars $%02X mons $%02X", c.f, tostring(c.counter),
      c.b8, c.b9))
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  -- every Runic absorb by GOGO's stance (Ot6RunicBP: y = the absorber, x = the caster, $b6 = the spell, $11a1 its
  -- element byte, which Ot6RuneAbsorb reads there)
  local rb = H.sym("Ot6RunicBP")
  emu.addMemoryCallback(function()
    local s, st = gseat(), cpu()
    if s == nil or (st["cpu.y"] & 0xFF) ~= s * 2 then return end
    local x = st["cpu.x"] & 0xFF
    absorbs[#absorbs + 1] = { f = H.frame, spell = H.readByte(0xB6), elem = H.readByte(0x11A1),
      caster = x < 8 and H.readByte(0x3ED8 + x) or 0x100 + x, rune0 = runeAt(s), tier0 = tierAt(s) }
  end, emu.callbackType.exec, rb, rb)
  -- every arming of GOGO's blade (Ot6RuneArm's write to OT6_RUNE at his seat; the battle's clear writes 0): one
  -- that follows an absorb at once is the absorb's (Ot6RuneAbsorb, in Ot6RunicBP; his own spell caught by his own
  -- stance too), any other made while his own action runs is that action's
  emu.addMemoryCallback(function(addr, v)
    local s = gseat()
    if s == nil or addr - RUNE_AT ~= s * 2 or v == 0 then return end
    local ab = absorbs[#absorbs]
    if ab ~= nil and ab.armed == nil and H.frame - ab.f <= 1 then ab.armed = v
    elseif cur and not cur.ended then cur.armed = v end
  end, emu.callbackType.write, RUNE_AT, RUNE_AT + 6)
  -- and its tier (Ot6RuneArm's second store, OT6_RUNETIER at his seat), by the same rule
  emu.addMemoryCallback(function(addr, v)
    local s = gseat()
    if s == nil or addr - TIER_AT ~= s * 2 or v == 0 then return end
    local ab = absorbs[#absorbs]
    if ab ~= nil and ab.armedTier == nil and H.frame - ab.f <= 1 then ab.armedTier = v
    elseif cur and not cur.ended then cur.armedTier = v end
  end, emu.callbackType.write, TIER_AT, TIER_AT + 6)
  emu.addEventCallback(function()
    if cur ~= nil then closeAct() end
    closeAbsorbs()
  end, emu.eventType.endFrame)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local s = gseat()
    if cur == nil or cur.ended or s == nil or (cpu()["cpu.x"] & 0xFF) ~= s * 2 then return end
    cur.ended = H.frame
    cur.liveEnd = H.readByte(0x3A75)
    cur.blade = (emu.read(RUNICBLADE, emu.memType.snesMemory) & H.readByte(0x3018 + s * 2)) ~= 0
  end, emu.callbackType.exec, ae, ae)
end
-- ---- the rounds ----------------------------------------------------------------
-- Each entry: a kitBattle plan entry (`e`, GOGO's unless it names another), a
-- `done()` that says it has been played, and `check()` run once it has.
local got = {}         -- tag -> what its peek or action left for the checks
local function lastAct(cmd, atk, pend, from)
  for i = #acts, from or 1, -1 do
    local a = acts[i]
    if a.cmd == cmd and (atk == nil or a.atk == atk) and (pend == nil or a.pend == pend) then return a end
  end
  return nil
end
-- his last Runic-command action whose queued row ($b6 at ExecCmd) is one of
-- lo..hi: a blade row ($D1-$D8) or Break Blade ($D9); stanceAct is the
-- stance, the Runic row ($D0) or the byte a Runic no list queued carries
local function runeAct(lo, hi, pend, from)
  for i = #acts, from or 1, -1 do
    local a = acts[i]
    if a.cmd == CMD.RUNIC and a.atk >= lo and a.atk <= hi and (pend == nil or a.pend == pend) then return a end
  end
  return nil
end
local function stanceAct(pend, from)
  for i = #acts, from or 1, -1 do
    local a = acts[i]
    if a.cmd == CMD.RUNIC and (a.atk < RUNE_BLADE or a.atk > RUNE_BREAK) and (pend == nil or a.pend == pend) then
      return a
    end
  end
  return nil
end
-- his last throw at `pend` points that the divine can be judged on: aimed
-- at a body the staging broke (cur.tgt, cur.staged); and the slot such a
-- throw is aimed at, the first standing monster without a Death ward
-- ($3AA1 bit 2), read as the target select opens
local function throwAct(pend, from)
  for i = #acts, from or 1, -1 do
    local a = acts[i]
    if a.cmd == CMD.THROW and a.pend == pend and a.staged ~= nil and (a.tgt & a.staged) ~= 0 then return a end
  end
  return nil
end
local function throwSlot()
  for m = 0, 5 do
    local e = 8 + m * 2
    if present(m) and H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3AA1 + e) & 0x04) == 0 then return m end
  end
  return nil
end
-- his last blade-row action ($D1-$D8): at `pend` points pending (nil: any),
-- of a row that climbs a line or not (`climbs`; nil: either), with at least
-- `least` pending
local function bladeAct(pend, climbs, least)
  for i = #acts, 1, -1 do
    local a = acts[i]
    if a.cmd == CMD.RUNIC and a.atk >= RUNE_BLADE and a.atk < RUNE_BREAK and (pend == nil or a.pend == pend)
       and (climbs == nil or (a.model.climbs[a.atk - RUNE_BLADE] == true) == climbs)
       and (least == nil or a.pend >= least) then
      return a
    end
  end
  return nil
end
-- the Break Blades of his that ran with fewer than three points pending
local function underThree()
  local n = 0
  for _, a in ipairs(acts) do
    if a.cmd == CMD.RUNIC and a.atk == RUNE_BREAK and a.pend < 3 then n = n + 1 end
  end
  return n
end
-- GOGO's stance's last absorb of spell `id` cast by character `who`
local function absorbOf(who, id)
  for i = #absorbs, 1, -1 do
    if absorbs[i].caster == who and absorbs[i].spell == id then return absorbs[i] end
  end
  return nil
end

local function thiefRows()
  local base = H.sym("Ot6ThiefRowTbl") & 0x3FFFFF
  local set = {}
  for r = 0, 7 do
    local o = base + r * 5
    local id, off, bit = H.readRomByte(o), H.readRomByte(o + 3), H.readRomByte(o + 4)
    if bit == 0 or (H.readByte(0x1E80 + off) & bit) ~= 0 then set[id] = true end
  end
  return set
end
local function listIds()
  local set = {}
  for c = 0, 7 do
    local id = H.readByte(ITEMLIST + c * 3)
    if id ~= 0xFF then set[id] = true end
  end
  return set
end
local function setEq(a, b) return hx(keys(a)) == hx(keys(b)) end

local ROUNDS = {
  { tag = "R1", cmds = { { 1, CMD.MAGIC }, { 2, CMD.SLOT }, { 3, CMD.TOOLS } }, entries = {
    { tag = "magic1", e = { cmd = CMD.MAGIC, peek = true }, onList = function(s)
        got.magic1 = { gogo = magicSet(s), others = {} }
        for id, os in pairs(seatOf) do if id ~= GOGO then got.magic1.others[id] = magicSet(os) end end
      end, check = function()
        local g = got.magic1
        H.log("[gogokits] R1 GOGO's Magic list: " .. hx(keys(g.gogo)))
        H.assertEq(g.gogo[FIRE] == true, true, "R1: GOGO's Magic list holds TERRA's Fire")
        for id, set in pairs(g.others) do
          H.assertEq(set[SCAN] == nil and set[BSERK] == nil, true, string.format(
            "R1 precondition: %s's Magic list holds neither Scan nor Bserk (the party lends GOGO neither)", NAMES[id]))
        end
        H.assertEq(g.gogo[SCAN], nil, "R1: without Lore GOGO's Magic list holds no Scan")
        H.assertEq(g.gogo[BSERK], nil, "R1: without Lore GOGO's Magic list holds no Bserk")
      end },
    { tag = "slot", e = { cmd = CMD.SLOT, peek = true }, onList = function()
        got.slot = { mode = H.readByte(MODE), rows = listIds() }
      end, check = function()
        local g = got.slot
        H.log(string.format("[gogokits] R1 GOGO's Slot: mode %d, rows %s", g.mode, hx(keys(g.rows))))
        H.assertEq(sw(0xCA), 1, "R1 precondition: Jackpot is learned (switch $00CA, SETZER's return in gen_wor_kohlingen)")
        H.assertEq(g.mode, 4, "R1: GOGO's Slot opens SETZER's table (w7e6168 = 4), not the bare reels")
        local want = {}
        for _, id in ipairs(SLOT_ROWS) do want[id] = true end
        H.assertEq(setEq(g.rows, want), true, "R1: the table's rows are Slot, Coin Toss, Hired Help and Jackpot")
      end },
    { tag = "ultima", e = { cmd = CMD.MAGIC, spell = FIRE, boost = 3 },
      done = function() return lastAct(CMD.MAGIC, nil, 3) ~= nil end, check = function()
        local a = lastAct(CMD.MAGIC, nil, 3)
        H.assertEq(sw(0xBF), 1, "R1 precondition: TERRA has rejoined in the World of Ruin (switch $00BF, gen_wor_terra)")
        H.assertEq(a.atk, ULTIMA, "R1: GOGO's Fire at 3 BP folds into Ultima ($14), TERRA's fourth fold")
        H.assertEq(a.mp0 - a.mp1, a.ultima0, "R1: and costs Ultima's own price")
        H.assertEq(a.fire3, a.ultima0, "R1: as the driver's model prices GOGO's 3-BP Fire")
      end },
    { tag = "jackpot", e = { cmd = CMD.SLOT, row = JACKPOT, boost = 3 },
      done = function() return lastAct(CMD.SLOT, JACKPOT, 3) ~= nil end, check = function()
        local a = lastAct(CMD.SLOT, JACKPOT, 3)
        -- two rolls at the body aimed at, which the staging keeps standing
        H.assertEq(a.dice, 2, string.format("R1: GOGO's Jackpot at 3 BP throws two rolls (at monsters $%02X; "
          .. "standing after: $%02X)", a.aim or 0, a.liveEnd))
        H.assertEq(a.mp0 - a.mp1, 99, "R1: and costs 99 MP")
      end },
    { tag = "overclock", e = { cmd = CMD.TOOLS, row = DEBIL, boost = 3 },
      done = function() return lastAct(CMD.TOOLS, DEBIL, 3) ~= nil end, check = function()
        local a = lastAct(CMD.TOOLS, DEBIL, 3)
        H.assertEq(sw(0x68), 1, "R1 precondition: Overclock is learned (switch $0068, the Magitek factory in gen_esper_tubes)")
        H.assertEq(a.passes, 2, "R1: GOGO's Debilitator at 3 BP fires twice (Overclock)")
        H.assertEq(a.mp0 - a.mp1, a.toolPrice, string.format(
          "R1: and costs the two firings, the model's price (H.toolPrice: %d MP)", a.toolPrice))
        H.assertEq(a.gate, 0, "R1: a 3-BP Tool of GOGO's stops at Ot6AssassinateGate's command test")
      end },
  } },
  { tag = "R2", cmds = { { 1, CMD.MAGIC }, { 2, CMD.LORE }, { 3, CMD.RUNIC } }, entries = {
    -- Break Blade under the full boost: with two points pending the row's A
    -- is refused.  The entry is an ordinary pick of the row (a ROM that takes
    -- it goes on to cast it, and the check below fails on that cast); the
    -- list calls onList before each A press, so its fourth call has seen
    -- three presses leave the list up, and backs out of it there.
    { tag = "breakshort", e = { cmd = CMD.RUNIC, row = RUNE_BREAK, boost = 2, self = true },
      onList = function(s, p)
        local at = got.breakshortAt
        if at == nil then
          at = { presses = -1, pend = H.readByte(0x3E9D + s * 2), mp = mpOf(s), bb = breakBladeAt(s) }
          got.breakshortAt = at
        end
        at.presses = at.presses + 1
        if at.presses >= 3 and got.breakshort == nil then
          got.breakshort = { at = at, presses = at.presses, state = H.readByte(MSTATE), mode = H.readByte(MODE),
            pend = H.readByte(0x3E9D + s * 2), bb = breakBladeAt(s), mp = mpOf(s) }
          p.peek = true
          H.log(string.format("[gogokits] f%d Break Blade's row at %d BP pending (MP %d): %d A presses, the menu "
            .. "state $%02X, list mode %d; OT6_BREAKBLADE %d, MP %d", H.frame, at.pend, at.mp, at.presses,
            got.breakshort.state, got.breakshort.mode, got.breakshort.bb, got.breakshort.mp))
        end
      end,
      done = function() return got.breakshort ~= nil or underThree() > 0 end, check = function()
        local g = got.breakshort
        H.assertEq(g ~= nil, true, string.format("R2: Break Blade's row confirmed with two points pending is refused: "
          .. "three A presses leave the list up (Break Blades of his that ran under three points: %d)", underThree()))
        H.assertEq(g.at.pend, 2, "R2 precondition: GOGO stood on Break Blade with two points pending")
        H.assertEq(g.at.mp >= BREAK_MP, true, string.format("R2 precondition: and its 99 MP in hand (%d), so the "
          .. "refusal is the boost gate's", g.at.mp))
        H.assertEq(g.at.bb, 0, "R2 precondition: and no Break Blade running")
        H.assertEq(g.state == 0x30 and g.mode == 7, true, string.format("R2: the Rune Knight's list is still open "
          .. "after the three presses (menu state $%02X, list mode %d)", g.state, g.mode))
        H.assertEq(g.pend, 2, "R2: his two points still pending")
        H.assertEq(underThree(), 0, "R2: no Break Blade of his ran under three points")
        H.assertEq(g.bb, 0, "R2: OT6_BREAKBLADE at his seat stays 0")
        H.assertEq(g.mp, g.at.mp, "R2: and his MP is unchanged")
      end },
    { tag = "magic2", e = { cmd = CMD.MAGIC, peek = true }, onList = function(s)
        -- STRAGO's battle Lore list as the save holds it now (a study
        -- later in the round teaches more)
        local load = {}
        for i = 1, 5 do load[i] = H.readByte(0x1E27 + i - 1) end
        got.magic2 = { gogo = magicSet(s), lore = loreRows(s), others = {},
          loreWant = H.loreList(got.openLores or lores(), load),
          bserk = H.readByte(0x1A6E + STRAGO * 0x36 + BSERK) == 0xFF }
        for id, os in pairs(seatOf) do if id ~= GOGO then got.magic2.others[id] = magicSet(os) end end
      end, check = function()
        local g = got.magic2
        H.log("[gogokits] R2 GOGO's Magic list: " .. hx(keys(g.gogo)) .. "; Lore rows: " .. hx(keys(g.lore)))
        for id, set in pairs(g.others) do
          H.assertEq(set[SCAN] == nil and set[BSERK] == nil, true, string.format(
            "R2 precondition: %s's Magic list holds neither Scan nor Bserk", NAMES[id]))
        end
        H.assertEq(g.gogo[SCAN], true, "R2: with Lore GOGO's Magic list holds Scan (STRAGO's Analyze)")
        H.assertEq(g.gogo[BSERK] == true, g.bserk, string.format(
          "R2: GOGO's Magic list holds Bserk exactly when STRAGO has learned it (%s)", tostring(g.bserk)))
        H.assertEq(hx(keys(g.lore)), hx(keys(g.loreWant)), "R2: GOGO's Lore rows are STRAGO's loadout and Aqua Rake")
      end },
    { tag = "study", e = { cmd = CMD.MAGIC, spell = SCAN, boost = 3 },
      done = function() return got.studyLearned ~= nil end, check = function()
        local a = lastAct(CMD.MAGIC, SCAN, 3)
        H.assertEq(a.want ~= 0, true, string.format("R2 precondition: a present species could teach a lore "
          .. "STRAGO lacks when GOGO studied (want $%06X; the staging cleared $%06X)", a.want, got.studyCleared or 0))
        H.assertEq(a.mp0 - a.mp1, 99, "R2: GOGO's Scan at 3 BP is Study, at the shared ceiling, 99 MP")
        H.assertEq(got.studyLearned & a.want, a.want, string.format(
          "R2: the victory taught them ($1D29 holds $%06X of $%06X)", got.studyLearned & a.want, a.want))
        H.assertEq(a.studied & a.want, a.want, string.format(
          "R2: the study added every lore the present species could teach (want $%06X, wrote $%06X)", a.want,
          a.studied))
        H.assertEq(a.studied & ~a.want & 0xFFFFFF, 0, "R2: and no other")
      end },
    { tag = "runeknt", e = { cmd = CMD.RUNIC, peek = true }, onList = function(s)
        got.runeknt = { mode = H.readByte(MODE), cells = runeCells(), want = runeModel(s, 0),
          pend = H.readByte(0x3E9D + s * 2) }
        H.screenshot("gogokits_runeknt")
      end, check = function()
        local g = got.runeknt
        H.log(string.format("[gogokits] R2 GOGO's Runic: mode %d, cells %s; the model's, from his spell list and "
          .. "MagicProp: %s", g.mode, g.cells, g.want.cells))
        H.assertEq(g.mode, 7, "R2: GOGO's Runic opens the Rune Knight's list (w7e6168 = 7)")
        H.assertEq(g.pend, 0, "R2 precondition: the list was read with no boost pending")
        H.assertEq(g.want.learned, true, "R2 precondition: Break Blade is learned (switch $0266, or $00A4: the "
          .. "World of Ruin)")
        H.assertEq(#g.want.rows > 2, true, "R2 precondition: GOGO's battle spell list holds an elemental spell (the "
          .. "seated party's union: TERRA's Fire)")
        H.assertEq(g.cells, g.want.cells, "R2: its rows are Runic, a blade row for each element GOGO's own spell "
          .. "list can cast (bit order, the cheapest spell's price, cut to the cells the shell has), then Break "
          .. "Blade for 99")
      end },
    { tag = "blade", e = { cmd = CMD.RUNIC, boost = 3, self = true },
      done = function() return stanceAct(3) ~= nil end, check = function()
        local a = stanceAct(3)
        H.assertEq(a.blade, true, "R2: GOGO's Runic at 3 BP is a RunicBlade (his OT6_RUNICBLADE bit)")
      end },
    { tag = "bounce", who = TERRA, stance = true, e = { who = TERRA, cmd = CMD.MAGIC, spell = FIRE, boost = 0 },
      after = "blade", done = function() return got.bounce ~= nil end, check = function()
        H.assertEq(got.bounce, true, "R2: TERRA's Fire into GOGO's RunicBlade came back at her as a counter")
        -- the absorb arms his blade (#563: Ot6RuneAbsorb answers for a GOGO, #547)
        local ab, el = absorbOf(TERRA, FIRE), spellElem(FIRE)
        H.assertEq(el ~= 0, true, "R2 precondition: Fire carries an element (MagicProp +1)")
        H.assertEq(ab ~= nil, true, "R2 precondition: GOGO's stance absorbed TERRA's Fire (Ot6RunicBP for his seat)")
        H.assertEq(ab.elem, el, "R2 precondition: the absorbed Fire's element byte ($11A1) is MagicProp's")
        H.assertEq(ab.armed, el, string.format("R2: GOGO's Runic absorbing TERRA's Fire arms his rune with its "
          .. "element (Ot6RuneArm's write to OT6_RUNE at his seat; it held $%02X)", ab.rune0))
        H.assertEq(ab.rune1, el, "R2: and OT6_RUNE at his seat holds Fire's element after the absorb")
        H.assertEq(ab.armedTier, 1, "R2: at tier 1, Fire's place in its line (Ot6RuneArm's write to OT6_RUNETIER)")
      end },
    -- TERRA's Fire at 1 BP is cast as Fire 2 (her fold), and the stance that
    -- absorbs it arms the rune at Fire 2's tier
    { tag = "fire2", who = TERRA, stance = true, e = { who = TERRA, cmd = CMD.MAGIC, spell = FIRE, boost = 1 },
      after = "blade", done = function() return absorbOf(TERRA, lineSpell(0, 1)) ~= nil end,
      -- (cast into no stance, the blade's turns spent: the battle's plan is over, and the pair is played again)
      playedHere = function() return got.confirmed.fire2 ~= nil and H.frame - got.confirmed.fire2 >= 900 end,
      check = function()
        local ab, el = absorbOf(TERRA, lineSpell(0, 1)), spellElem(FIRE)
        H.assertEq(lineSpell(0, 0), FIRE, "R2 precondition: Fire heads Ot6FoldTbl's first line")
        H.assertEq(ab.elem, el, string.format("R2 precondition: GOGO's stance absorbed TERRA's 1-BP Fire as spell "
          .. "$%02X, the line's second, of Fire's element", ab.spell))
        H.assertEq(ab.armed, el, "R2: GOGO's Runic absorbing TERRA's boosted Fire arms his rune with its element")
        H.assertEq(ab.armedTier, 2, string.format("R2: at tier 2, the absorbed spell's place in its line "
          .. "(Ot6RuneArm's write to OT6_RUNETIER at his seat; it held %d)", ab.tier0))
        H.assertEq(ab.tier1, 2, "R2: and OT6_RUNETIER at his seat reads 2 after the absorb")
      end },
    -- a listed blade row at 0 BP, of another element than the Fire his stance
    -- absorbs where his list has one (so each arming shows as a change)
    { tag = "bladerow", eFn = function(s)
        local pick = nil
        for _, row in ipairs(runeModel(s, 0).rows) do
          if row[1] >= RUNE_BLADE and row[1] < RUNE_BREAK
             and (pick == nil or (1 << (pick - RUNE_BLADE)) == spellElem(FIRE)) then
            pick = row[1]
          end
        end
        H.assertEq(pick ~= nil, true, "R2 precondition: GOGO's list holds a blade row (the seated party lends him "
          .. "an elemental spell: TERRA's Fire)")
        return { cmd = CMD.RUNIC, row = pick, boost = 0, self = true }
      end,
      done = function() return bladeAct(0) ~= nil end, check = function()
        local a = bladeAct(0)
        local e = a.atk - RUNE_BLADE
        local price = a.model.price[e]
        H.assertEq(a.pend, 0, "R2: the blade row was played at 0 BP")
        H.assertEq(price ~= nil and price > 0, true, string.format("R2 precondition: GOGO's spell list holds a "
          .. "spell of row $%02X's element, at a price (%s MP)", a.atk, tostring(price)))
        H.assertEq(a.armed, 1 << e, string.format("R2: GOGO's blade row $%02X arms OT6_RUNE at his seat with its "
          .. "element (Ot6RuneArm's write during his action; it held $%02X)", a.atk, a.rune0))
        H.assertEq(a.rune1, 1 << e, "R2: and his rune holds that element once the action has ended")
        H.assertEq(a.armedTier, 1, "R2: at tier 1, with no boost (Ot6RuneArm's write to OT6_RUNETIER)")
        H.assertEq(a.mp0 - a.mp1, price, string.format("R2: and it costs him the cheapest spell of that element in "
          .. "his list (%d MP)", price))
      end },
    -- a row whose element has a line (the first his list holds: Fire's), with
    -- one point: the list prices every climbing row at its line's second
    -- spell, and the row arms tier 2 for that spell's MP and spends the point
    { tag = "linerow", eFn = function(s)
        local m, pick = runeModel(s, 0), nil
        for e = 7, 0, -1 do if m.climbs[e] then pick = RUNE_BLADE + e end end
        H.assertEq(pick ~= nil, true, "R2 precondition: GOGO's list holds a row that climbs a line (his cheapest "
          .. "spell of the element is its line's head: TERRA's Fire)")
        return { cmd = CMD.RUNIC, row = pick, boost = 1, self = true }
      end,
      onList = function(s)
        local pend = H.readByte(0x3E9D + s * 2)
        got.linerowAt = { pend = pend, cells = runeCells(), want = runeModel(s, pend).cells,
          base = runeModel(s, 0).cells }
      end,
      done = function() return bladeAct(1, true) ~= nil end, check = function()
        local a, g = bladeAct(1, true), got.linerowAt
        local e = a.atk - RUNE_BLADE
        local price = a.model.price[e]
        H.log(string.format("[gogokits] R2 GOGO's Runic at %d BP pending: cells %s; the model's %s (at no boost %s)",
          g.pend, g.cells, g.want, g.base))
        H.assertEq(g.pend, 1, "R2 precondition: the list was read with one point pending")
        H.assertEq(g.want ~= g.base, true, "R2 precondition: a point moves a price of his list (a line's second "
          .. "spell costs more than its head)")
        H.assertEq(g.cells, g.want, "R2: with a point pending each row that climbs is priced at its line's second "
          .. "spell (Ot6FoldTbl, MagicProp's MP), the others as before")
        H.assertEq(a.model.spell[e], lineSpell(e, 1), string.format("R2 precondition: at 1 BP row $%02X stands for "
          .. "its line's second spell ($%02X)", a.atk, lineSpell(e, 1)))
        H.assertEq(a.armed, 1 << e, string.format("R2: GOGO's row $%02X at 1 BP arms OT6_RUNE at his seat with its "
          .. "element", a.atk))
        H.assertEq(a.armedTier, 2, string.format("R2: at tier 2 (Ot6RuneArm's write to OT6_RUNETIER at his seat; "
          .. "it held %d)", a.tier0))
        H.assertEq(a.tier1, 2, "R2: and OT6_RUNETIER at his seat reads 2 once the action has ended")
        H.assertEq(a.mp0 - a.mp1, price, string.format("R2: it costs him the line's second spell's MP (%d MP)", price))
        H.assertEq(a.bank1, a.bank0 - 1, string.format("R2: and the point is spent, none earned that turn (bank %d, "
          .. "then %d)", a.bank0, a.bank1))
      end },
    -- a row whose element has no line (the cheapest his list holds: Pearl's or
    -- W Wind's), a point raised on the command window and a second in the
    -- bank: R on the row is refused (the pending boost stays), and the point
    -- raised is dropped, not charged, by a row that arms tier 1
    { tag = "flatrow", eFn = function(s)
        local m, pick = runeModel(s, 0), nil
        for _, row in ipairs(m.rows) do
          local e = row[1] - RUNE_BLADE
          if e >= 0 and e < 8 and not m.climbs[e] and (pick == nil or row[2] < m.price[pick - RUNE_BLADE]) then
            pick = row[1]
          end
        end
        H.assertEq(pick ~= nil, true, "R2 precondition: GOGO's list holds a row with no line to climb (the seated "
          .. "party lends him W Wind or Pearl)")
        return { cmd = CMD.RUNIC, row = pick, boost = 1, bank = 2, listR = 2, self = true }
      end,
      onList = function(s, p)
        got.flatrowAt = { r0 = p.listR0, r1 = p.listR1, bank = bankAt(s), row = p.row }
      end,
      done = function() return bladeAct(nil, false, 1) ~= nil end, check = function()
        local a, g = bladeAct(nil, false, 1), got.flatrowAt
        local e = a.atk - RUNE_BLADE
        H.log(string.format("[gogokits] R2 R twice on row $%02X: pending %s -> %s with %d banked", g.row,
          tostring(g.r0), tostring(g.r1), g.bank))
        H.assertEq(g.r0 == 1 and g.bank >= 2, true, string.format("R2 precondition: GOGO stood on row $%02X with "
          .. "one point pending and another banked (pending %s, bank %d)", g.row, tostring(g.r0), g.bank))
        H.assertEq(g.r1, g.r0, "R2: R on a blade row with no line to climb is refused: the pending boost is "
          .. "unchanged after two presses")
        H.assertEq(a.pend, 1, "R2 precondition: the row was confirmed with the point raised on the command window")
        H.assertEq(a.armed, 1 << e, string.format("R2: GOGO's row $%02X arms OT6_RUNE at his seat with its element",
          a.atk))
        H.assertEq(a.armedTier, 1, "R2: at tier 1, boost or no (Ot6RuneArm's write to OT6_RUNETIER)")
        H.assertEq(a.mp0 - a.mp1, a.model.price[e], string.format("R2: for the cheapest spell of that element in "
          .. "his list (%d MP)", a.model.price[e]))
        H.assertEq(a.bank1 >= a.bank0, true, string.format("R2: and the point is dropped, not charged (bank %d, "
          .. "then %d)", a.bank0, a.bank1))
      end },
    { tag = "breakblade", e = { cmd = CMD.RUNIC, row = RUNE_BREAK, boost = 3, self = true },
      done = function() return runeAct(RUNE_BREAK, RUNE_BREAK, 3) ~= nil end, check = function()
        local a = runeAct(RUNE_BREAK, RUNE_BREAK, 3)
        H.assertEq(a.bb0, 0, "R2 precondition: no Break Blade was running when GOGO cast his")
        H.assertEq(a.mp0 - a.mp1, BREAK_MP, "R2: GOGO's Break Blade at 3 BP costs 99 MP")
        H.assertEq(a.bb1, BREAK_TURNS, "R2: and OT6_BREAKBLADE at his seat reads 3 once the cast has resolved")
      end },
  } },
  { tag = "R3", cmds = { { 1, CMD.THROW }, { 2, CMD.STEAL }, { 3, CMD.BLITZ } }, entries = {
    { tag = "steal", e = { cmd = CMD.STEAL, peek = true }, onList = function()
        got.steal = { mode = H.readByte(MODE), rows = listIds() }
      end, check = function()
        local g, want = got.steal, thiefRows()
        H.log(string.format("[gogokits] R3 GOGO's Steal: mode %d, rows %s; LOCKE's learned rows %s", g.mode,
          hx(keys(g.rows)), hx(keys(want))))
        H.assertEq(g.mode, 3, "R3: GOGO's Steal opens LOCKE's list (w7e6168 = 3)")
        H.assertEq(setEq(g.rows, want), true, "R3: with exactly the rows LOCKE's story has taught")
      end },
    { tag = "blitz", e = { cmd = CMD.BLITZ, peek = true }, onList = function()
        got.blitz = { mode = H.readByte(MODE), rows = listIds() }
      end, check = function()
        local g = got.blitz
        H.log(string.format("[gogokits] R3 GOGO's Blitz: mode %d, rows %s; $1D28 $%02X", g.mode, hx(keys(g.rows)),
          H.readByte(0x1D28)))
        H.assertEq(H.readByte(0x1D28) & 0x80, 0x80, "R3 precondition: SABIN has learned Bum Rush ($1D28 bit 7, Duncan in gen_wor_gau)")
        H.assertEq(g.mode, 1, "R3: GOGO's Blitz opens SABIN's list (w7e6168 = 1)")
        H.assertEq(g.rows[BUMRUSH], true, "R3: and it holds Bum Rush ($64)")
      end },
    { tag = "bumrush", e = { cmd = CMD.BLITZ, row = BUMRUSH, boost = 3, direct = true },
      done = function() return lastAct(CMD.BLITZ, nil, 3) ~= nil end, check = function()
        local a = lastAct(CMD.BLITZ, nil, 3)
        H.assertEq(a.atk, BUMRUSH, "R3: GOGO's Blitz at 3 BP ran Bum Rush")
        H.assertEq(a.mp0 - a.mp1, 99, "R3: for 99 MP")
      end },
    -- a throw where no standing monster could be staged (every one wards
    -- Death, $3AA1 bit 2: v0.50's replay drew formation 00D2 0087 00B0 00B0,
    -- 'R3 staging: a standing non-boss monster was Broken as the throw began:
    -- got false', build/attempts/wt/v050-multihit-anim/
    -- qual8_battle_gogokits_red.log) is not counted: the entry is played
    -- again in the round's next battle.  Nor is one aimed at a body the
    -- staging could not break: the same formation with one unwarded body
    -- standing beside a warded one drew the throw onto the warded one ('R3:
    -- and marks Death on the Broken non-boss it hits (0 mark(s), staged $02)',
    -- build/attempts/wt/v051-spellblade/sb3/gogokits2/full_asis/run.log), so
    -- the throw is aimed at a body the staging will break (throwSlot).
    { tag = "assassinate", e = { cmd = CMD.THROW, row = SHURIKEN, boost = 3, slotFn = throwSlot },
      done = function() return throwAct(3) ~= nil end,
      playedHere = function() local a = lastAct(CMD.THROW, nil, 3); return a ~= nil and a.f >= got.battleF0 end,
      check = function()
        local a = throwAct(3)
        H.assertEq(a.staged ~= 0, true, "R3 staging: a standing non-boss monster was Broken as the throw began")
        H.assertEq(a.gate > 0, true, "R3: GOGO's 3-BP Throw passes Ot6AssassinateGate's actor and command test "
          .. "(SHADOW's divine)")
        H.assertEq(a.marks > 0, true, string.format("R3: and marks Death on the Broken non-boss it hits (%d mark(s), "
          .. "staged $%02X)", a.marks, a.staged))
      end },
    { tag = "assassinate2", e = { cmd = CMD.THROW, row = SHURIKEN, boost = 2, slotFn = throwSlot },
      done = function() return throwAct(2) ~= nil end,
      playedHere = function() local a = lastAct(CMD.THROW, nil, 2); return a ~= nil and a.f >= got.battleF0 end,
      check = function()
        local a = throwAct(2)
        H.assertEq(a.staged ~= 0, true, "R3 staging: a standing non-boss monster was Broken as the 2-BP throw began")
        H.assertEq(a.gate > 0, true, "R3: the 2-BP throw reaches the gate's boost test too")
        H.assertEq(a.marks, 0, "R3: and under the full boost it marks no Death (the divine's one gate)")
      end },
  } },
  { tag = "R4", cmds = { { 1, CMD.SWDTECH }, { 2, CMD.RAGE }, { 3, CMD.DANCE } }, entries = {
    { tag = "swdtech", e = { cmd = CMD.SWDTECH, boost = 3, peek = true }, onList = function()
        got.swdtech = { mode = H.readByte(MODE), r2 = H.readByte(ITEMLIST + 2 * 6) }
      end, check = function()
        local g = got.swdtech
        H.assertEq(H.readByte(0x1CF7) & 0x80, 0x80, "R4 precondition: CYAN has learned Cleave ($1CF7 bit 7, the Phantom Train farewell in gen_sabin_train)")
        H.assertEq(g.mode, 2, "R4: GOGO's SwdTech opens CYAN's window (w7e6168 = 2)")
        H.assertEq(g.r2, CLEAVE, "R4: its 3 BP row is Cleave ($5C)")
      end },
    { tag = "cleave", e = { cmd = CMD.SWDTECH, row = CLEAVE, boost = 3, direct = true },
      done = function() return lastAct(CMD.SWDTECH, nil, nil) ~= nil end, check = function()
        local a = lastAct(CMD.SWDTECH, nil, nil)
        H.assertEq(a.atk, CLEAVE, "R4: GOGO's SwdTech at 3 BP ran Cleave")
        H.assertEq(a.mp0 - a.mp1, 99, "R4: for 99 MP")
      end },
  } },
  { tag = "R5", leo = true, cmds = { { 1, CMD.SLOT }, { 2, CMD.TOOLS }, { 3, CMD.THROW } }, entries = {
    { tag = "slot5", e = { cmd = CMD.SLOT, peek = true }, onList = function()
        got.slot5 = { mode = H.readByte(MODE), rows = listIds() }
      end, check = function()
        local g = got.slot5
        H.log(string.format("[gogokits] R5 LEO's Slot: mode %d, rows %s", g.mode, hx(keys(g.rows))))
        H.assertEq(g.mode, 4, "R5: the revealed LEO's Slot opens SETZER's table")
      end },
    { tag = "overclock5", e = { cmd = CMD.TOOLS, row = DEBIL, boost = 3 },
      done = function() return got.r5from and lastAct(CMD.TOOLS, DEBIL, 3, got.r5from) ~= nil end, check = function()
        local a = lastAct(CMD.TOOLS, DEBIL, 3, got.r5from)
        H.assertEq(a.passes, 2, "R5: the revealed LEO's Debilitator at 3 BP fires twice")
        H.assertEq(a.mp0 - a.mp1, a.toolPrice, string.format("R5: for the two firings' price (%d MP)", a.toolPrice))
      end },
    { tag = "assassinate5", e = { cmd = CMD.THROW, row = SHURIKEN, boost = 3, slotFn = throwSlot },
      done = function() return got.r5from and throwAct(3, got.r5from) ~= nil end,
      playedHere = function()
        local a = got.r5from and lastAct(CMD.THROW, nil, 3, got.r5from)
        return a ~= nil and a ~= false and a.f >= got.battleF0
      end,
      check = function()
        local a = throwAct(3, got.r5from)
        H.assertEq(a.gate > 0, true, "R5: the revealed LEO's 3-BP Throw passes Ot6AssassinateGate's actor test")
        H.assertEq(a.marks > 0, true, string.format("R5: and marks Death on the Broken non-boss it hits (%d)", a.marks))
      end },
  } },
}

-- the R4 data checks, read in a battle with the round's commands set: the
-- Rage window's list (one list for every rager, $257E) and the dances
local function r4Data()
  local list = {}
  for i = 0, 255 do
    local r = H.readByte(0x257E + i)
    if r == 0xFF then break end
    list[#list + 1] = r
  end
  local load, manual = {}, false
  for i = 0, 7 do
    load[i + 1] = H.readByte(0x1E1F + i)
    if load[i + 1] ~= 0 then manual = true end
  end
  H.log(string.format("[gogokits] R4 the Rage list %s; GAU's loadout %s; dances $%02X", hx(list), hx(load),
    H.readByte(0x1D4C)))
  local s = gseat()
  local cmds = {}
  for r = 0, 3 do cmds[#cmds + 1] = H.readByte(0x202E + s * 12 + r * 3) end
  H.assertEq(hx(cmds):find("10") ~= nil and hx(cmds):find("13") ~= nil, true,
    "R4: GOGO's battle commands hold Rage and Dance (" .. hx(cmds) .. ")")
  if manual then
    local want = {}
    for _, b in ipairs(load) do if b ~= 0 then want[#want + 1] = b - 1 end end
    H.assertEq(hx(list), hx(want), "R4: GOGO's Rage list is GAU's loadout, in its order")
  else
    H.assertEq(#list > 0 and #list <= 8, true, "R4: GOGO's Rage list is GAU's AUTO window (one to eight rages)")
  end
  H.assertEq(H.readByte(0x1D4C) ~= 0, true, "R4: GOGO's dances are MOG's ($1D4C), and MOG knows some")
end

-- ---- the battle loop -------------------------------------------------------------
local round, battles, entryOf, roundBattles = nil, 0, {}, 0
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function entryDone(en)
  if en.done then return en.done() end
  return got[en.tag] ~= nil
end
local function roundDone(r)
  for _, en in ipairs(r.entries) do if not entryDone(en) then return false end end
  return true
end
local handed = nil
local function danger()
  if not H.battleActive() then return nil end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local hp, mx, st1 = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2), H.readByte(0x3EE4 + s * 2)
      if mx > 0 and mx < 10000 and (hp == 0 or (st1 & 0xC2) ~= 0 or hp < mx * DANGER) then
        return string.format("seat %d at %d/%d HP, status1 $%02X", s, hp, mx, st1)
      end
    end
  end
  return nil
end
local castsAt = 0
local function decide()
  battles, roundBattles = battles + 1, roundBattles + 1
  H.assertEq(battles <= MAX_BATTLES, true, string.format("the five rounds within %d battles", MAX_BATTLES))
  -- a round whose entries a ROM never lets him play (the old ROM's Slot opens
  -- the bare reels: no table, no Jackpot row) fails here, naming them
  if roundBattles > ROUND_BATTLES then
    local left = {}
    for _, en in ipairs(round.entries) do if not entryDone(en) then left[#left + 1] = en.tag end end
    H.assertEq(#left, 0, string.format("%s: every entry played within %d battles (never played: %s)", round.tag,
      ROUND_BATTLES, table.concat(left, ", ")))
  end
  -- a Runic at 3 BP that raised no RunicBlade fails at once: the bounce
  -- that would follow it can never come
  local ra = stanceAct(3, got.r5from)
  if round.tag == "R2" and ra ~= nil then
    H.assertEq(ra.blade, true, "R2: GOGO's Runic at 3 BP is a RunicBlade (his OT6_RUNICBLADE bit)")
  end
  findSeats()
  handed, plan, entryOf = nil, {}, {}
  got.battleF0, got.confirmed = H.frame, {}
  if got.breakshort == nil then got.breakshortAt = nil end
  H.assertEq(gseat() ~= nil, true, "GOGO is seated")
  local s = gseat()
  local fw = H.formationWords()
  H.log(string.format("[gogokits] battle %d, round %s (formation %04X %04X %04X %04X %04X %04X): GOGO seat %d, "
    .. "L%d, MP %d, bank %d", battles, round.tag, fw[1], fw[2], fw[3], fw[4], fw[5], fw[6], s, K.lv(GOGO), mpOf(s),
    H.readByte(0x3E9C + s * 2)))
  if round.tag == "R4" and not got.r4data then r4Data(); got.r4data = true end
  local skip = {}
  got.openLores = lores()
  if round.tag == "R2" and got.studyLearned == nil then
    -- the lores the present species cast (Ot6StudyTbl rows): STRAGO knows
    -- every one this plain's casters know (the Crawler's, the Sprinter's
    -- Pearl Wind), so the declared staging (state_write_waivers.txt, the
    -- battle_study expedient) unlearns them for the study to teach again
    local rows = 0
    for m = 0, 5 do if present(m) then rows = rows | studyRow(species(m)) end end
    if rows == 0 then
      skip.study = true
      H.log("[gogokits] no present species casts a lore: the study waits for another battle")
    elseif rows & ~lores() & 0xFFFFFF == 0 then
      got.studyCleared, got.studyBattle, got.studyFrame = rows & lores(), battles, H.frame
      for b = 0, 2 do
        H.writeByte(0x1D29 + b, H.readByte(0x1D29 + b) & ~((got.studyCleared >> (8 * b)) & 0xFF))
      end
      H.log(string.format("[gogokits] staged: lores $%06X unlearned for the study -> $1D29 $%06X", got.studyCleared,
        lores()))
    end
  end
  local function entryTagged(tag)
    for _, x in ipairs(round.entries) do if x.tag == tag then return x end end
  end
  -- Break Blade's rows wait for a battle GOGO opens with the MP for the
  -- round's dearest casts beside it (the study's 99 and Break Blade's own
  -- 99, and a blade row): its refusal is read with 99 MP in hand, and a row
  -- he cannot pay would be refused for its price.  Field care tops his MP up
  -- between battles.
  if round.tag == "R2" and mpOf(s) < 3 * BREAK_MP then
    skip.breakshort, skip.breakblade = true, true
    H.log(string.format("[gogokits] GOGO opens with %d MP: Break Blade's rows wait for another battle", mpOf(s)))
  end
  for _, en in ipairs(round.entries) do
    if not entryDone(en) and not skip[en.tag] and (en.after == nil or entryDone(entryTagged(en.after))) then
      local p = {}
      for k, v in pairs(en.eFn and en.eFn(s) or en.e) do p[k] = v end
      p.who = p.who or GOGO
      plan[#plan + 1] = p
      entryOf[p] = en
    end
  end
  -- an entry cast into his stance (`stance`: the bounce, the boosted Fire)
  -- is TERRA's spell played after the blade in the same battle: if the
  -- blade is still to come it rides this battle's plan, else those entries
  -- wait for a fresh blade (the stance lasts three turns)
  local blade = entryTagged("blade")
  if blade ~= nil and entryDone(blade) then
    local has, at = false, nil
    for i, p in ipairs(plan) do
      if entryOf[p] == blade then has = true end
      if at == nil and entryOf[p].stance then at = i end
    end
    if at ~= nil and not has then
      -- the blade was raised in an earlier battle: raise it again, right
      -- before the first of them
      local p = {}
      for k, v in pairs(blade.e) do p[k] = v end
      p.who = GOGO
      table.insert(plan, at, p)
      entryOf[p] = blade
    end
  end
  castsAt = #casts + 1
  local tags = {}
  for _, p in ipairs(plan) do tags[#tags + 1] = entryOf[p].tag end
  H.log(string.format("[gogokits] battle %d plan: %s", battles, table.concat(tags, ", ")))
end
local function onList(p, a)
  local en = entryOf[p]
  if en and en.onList then en.onList(a, p) end
end
-- the bounce: a counter Fire at TERRA alone after the blade
local function bounceSeen()
  local t = seatOf[TERRA]
  for i = castsAt, #casts do
    local c = casts[i]
    if t and c.counter and c.b8 == (1 << t) and c.b9 == 0 then return true end
  end
  return false
end

-- the frame kitBattle confirmed each of this battle's entries (its record),
-- by tag: got.confirmed, for an entry whose playedHere reads it
local function noteConfirms()
  for _, rec in ipairs(H.vars.kit or {}) do
    local p = plan[rec.entry]
    if p ~= nil and entryOf[p] ~= nil then got.confirmed[entryOf[p].tag] = rec.frame end
  end
end
-- the plan's last action has resolved: every entry this battle planned is
-- done (an action is done once its record has closed)
local function planDone()
  if got.bounce == nil and bounceSeen() then got.bounce = true end
  noteConfirms()
  for _, p in ipairs(plan) do
    local en = entryOf[p]
    if not entryDone(en) and not (en.playedHere and en.playedHere()) then return false end
  end
  return cur == nil
end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local A, B = nil, nil
local function worldBattle(tag)
  return H.seqStep({
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldSettled() end, 6000,
      tag .. ": world control", 5),
    H.call(function()
      if A ~= nil then return end
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) then A, B = { x, y }, { bx, by } end
      end
      H.assertEq(B ~= nil, true, string.format("%s: a passable world tile beside (%d,%d)", tag, x, y))
      H.log(string.format("[gogokits] pacing world (%d,%d) <-> (%d,%d)", A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle on the world map"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
  })
end

local REC = 0x1600 + 37 * GOGO
local function playRound(r)
  return H.seqStep({
    H.call(function() roundBattles = 0 end),
    H.cond(function() return r.leo end, {
      H.loadState("build/states/wor_leo.mss.lua"),
      H.waitFrames(30),
      H.call(function()
        A, B = nil, nil
        got.r5from = #acts + 1
        H.assertEq(sw(0xE0), 1, "R5: Leo has been revealed (switch $00E0, gen_wor_leo)")
        H.assertEq(H.readByte(REC), GOGO, "R5: slot 12 keeps actor $0C")
        H.assertEq(H.readByte(REC + 1), 0x10, "R5: slot 12 wears Leo's sprite")
        H.assertEq((H.readByte(0x1850 + GOGO) & 7) ~= 0, true, "R5: LEO is in the party")
      end),
      H.lazy(function()
        local t = {}
        for i = 1, BURN do
          t[#t + 1] = worldBattle("R5 BURN " .. i)
          t[#t + 1] = H.fightBattleByMenu(60000)
          t[#t + 1] = H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
            "R5 BURN: back on the world map", 5)
        end
        return H.seqStep(t)
      end),
    }, {}),
    H.call(function() round = r end),
    H.release(),
    H.waitFrames(10),
    gogoCommands(r.cmds, r.tag .. ": GOGO's commands"),
    H.driveUntil(function()
      return roundDone(r) and not H.battleLoadStarted() and H.worldMode() and H.worldHasControl()
    end, 900000, {
      H.cond(function() return not H.battleLoadStarted() end, {
        H.fieldCare({ tag = r.tag .. ": care", threshold = 0.95, mpBand = 0.95 }),
        worldBattle(r.tag),
      }, {}),
      H.call(decide),
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 90000, onList = onList,
        planDone = planDone, giveUp = function()
          if got.bounce == nil and bounceSeen() then got.bounce = true end
          noteConfirms()
          if handed == nil then handed = danger() end
          return handed ~= nil
        end }),
      H.call(function()
        if cur ~= nil then closeAct() end
        if got.bounce == nil and bounceSeen() then got.bounce = true end
        noteConfirms()
        if handed then H.log(string.format("[gogokits] battle %d handed to the fight driver: %s", battles, handed)) end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(60000) }, {}),
      H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
        "back on the world map", 5),
      H.call(function()
        if cur ~= nil then closeAct() end
        if got.bounce == nil and bounceSeen() then got.bounce = true end
        -- the study's settlement: a 3-BP Scan this battle taught the staged
        -- lores at the victory, or (no study, or no victory) they are put back
        if got.studyCleared ~= nil and got.studyLearned == nil and got.studyBattle == battles then
          local a = lastAct(CMD.MAGIC, SCAN, 3)
          if a ~= nil and a.want ~= 0 and a.f >= got.studyFrame then
            -- the cast itself, judged now: a Scan that did not study fails
            -- here, not at the round's budget
            H.assertEq(a.mp0 - a.mp1, 99, "R2: GOGO's Scan at 3 BP is Study, at the shared ceiling, 99 MP")
            H.assertEq(a.studied, a.want, string.format(
              "R2: the study added exactly the lores the present species could teach (want $%06X, wrote $%06X)",
              a.want, a.studied))
          end
          if a ~= nil and a.want ~= 0 and a.f >= got.studyFrame and (lores() & a.want) == a.want then
            got.studyLearned = lores()
            H.log(string.format("[gogokits] the victory taught the studied lores: $1D29 $%06X", lores()))
          elseif (lores() & got.studyCleared) ~= got.studyCleared then
            for b = 0, 2 do
              H.writeByte(0x1D29 + b, H.readByte(0x1D29 + b) | ((got.studyCleared >> (8 * b)) & 0xFF))
            end
            H.log(string.format("[gogokits] no study taught them this battle: lores $%06X put back", got.studyCleared))
          end
        end
      end),
    }, r.tag .. ": every entry played"),
    H.call(function()
      for _, en in ipairs(r.entries) do en.check() end
      H.log(string.format("[gogokits] %s PASS", r.tag))
    end),
  })
end

local body = {
  H.bootCheckpoint("wor-colosseum-v1"),
  H.call(function()
    say("wor", "boot")
    install()
  end),
  H.call(function()
    H.assertEq(H.invCountOf(SWORDBREAKER) >= 1, true,
      "the bag holds a SwordBreaker (gen_wor_colosseum's prize for the Assassin)")
  end),
  regroup({ GOGO, TERRA, RELM, SHADOW }),
  H.lazy(function()
    local pos = (H.readByte(0x1850 + GOGO) >> 3) & 3
    return H.equipWeapon(pos, SWORDBREAKER, { tag = "GOGO takes the SwordBreaker" })
  end),
  H.call(function()
    H.assertEq(H.readByte(REC + 0x1F), SWORDBREAKER, "GOGO holds the SwordBreaker")
  end),
  liftOff(),
  H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
  H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon back by Maranda", fight = FIGHT }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 6000, "world control on the landing", 5),
}
for i = 1, BURN do
  body[#body + 1] = H.seqStep({
    worldBattle("BURN " .. i),
    H.fightBattleByMenu(60000),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
      "BURN: back on the world map", 5),
    H.call(function()
      H.log(string.format("[gogokits] BURN %d: encounters used up; $1FA1-5 = %02X %02X %02X %02X %02X", i,
        H.readByte(0x1FA1), H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    end),
  })
end
for _, r in ipairs(ROUNDS) do
  if ONLY == nil or ONLY:find(r.tag, 1, true) then body[#body + 1] = playRound(r) end
end
body[#body + 1] = H.call(function()
  if ONLY ~= nil then H.log("[gogokits] GOGOKITS_ROUNDS: only " .. ONLY .. " played (a lab's run, not the suite's)") end
  -- the command window's name for Relm's command (the owner, 2026-11-21)
  local base = (H.sym("BattleCmdName") & 0x3FFFFF) + 0x0D * 7
  local t = {}
  for i = 0, 6 do t[#t + 1] = H.readRomByte(base + i) end
  H.assertEq(hx(t), "8F 9A A2 A7 AD 9E AB", "BattleCmdName's record $0D reads \"Painter\"")
  H.log(string.format("[gogokits] PASS: GOGO's Slot, Tools, Magic, Lore, Runic, Steal, Blitz, Throw and SwdTech "
    .. "open their owners' kits, in %d battles", battles))
end)
H.run({ maxFrames = 1500000 }, body)
