-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_gogomimic.lua -- GOGO's Mimic at three of his points buys the copied
-- action's owner extra (#559; docs/design/kit-gogo.md section 4).
--
-- Since #547 the divines keyed on the owner's actor id answer for GOGO
-- (actor $0C) whatever command he uses, and a copy reads his own pending
-- boost where the copied action reads one (Ot6MimicFold, Ot6MimicKeep).  So a
-- Mimic of an owner's plain (0 BP) action, copied with three of GOGO's
-- points pending, is the owner's divine: battle_gogokits plays his own
-- commands; this suite plays the copies.
--
-- Played (battle_gogokits' machinery, one declared staging per arm that needs
-- it; state_write_waivers.txt): Continue wor-colosseum-v1 (beside the Falcon
-- by Maranda), board, and in the Falcon's cabin seat the round's party; lift
-- off, land again by Maranda, set GOGO's three commands in his Status menu
-- (row 0 stays Mimic; none of them the copied command, so only the Mimic
-- reaches it), and pace the world map into random battles.  In each battle,
-- through the real menu (H.kitBattle), the owner plays the plain action and
-- GOGO, his bank filled to 3 by real Defends, raises three points with R and
-- picks Mimic once that action has run (the others Defend; no Item care
-- while a copy is in flight, so the last action is the owner's).  Every copy
-- is read where the engine makes it (mimicreplace for his seat: the copied
-- command and attack, $3F20, and the pips pending, $3E9D) and where it runs
-- (ExecCmd for his seat).  A copy of another action, or one at another
-- boost, is not counted and the pair is played again in a later battle.
--   M1 (GOGO, EDGAR, CELES, SHADOW; GOGO's commands Steal, Blitz, Rage)
--     * overclock: a copy of EDGAR's 0-BP Debilitator, at 3 of GOGO's
--       points, fires twice (Ot6PassTargeted for his seat: 2 passes);
--     * blade: a copy of CELES's 0-BP Runic at 3 is a RunicBlade (his
--       OT6_RUNICBLADE bit when the copy ends);
--     * assassinate: a copy of SHADOW's 0-BP Shuriken at 3 marks Death on
--       the Broken non-boss it hits (Ot6AssassinateGate's write).  The
--       staging is battle_gogokits': every standing non-boss monster without
--       a Death ward is Broken (OT6_BROKEN_TICKS) as the copy begins; no
--       party here breaks one on cue.
--     The Rune Knight's rows (#563, ot6_rune.asm) are self-targeted, so a
--     copy runs on the copier, as a copy of Runic raises GOGO's own stance:
--     * rune: CELES plays a blade row of her list (an element her battle
--       spell list can cast, derived there); a copy of it at 0 of GOGO's
--       points arms GOGO's own rune with that element (Ot6RuneArm's write to
--       OT6_RUNE at his seat) at tier 1 (OT6_RUNETIER), free, and nothing is
--       written at hers;
--     * runetier: the tier is the copier's.  CELES plays a row that climbs a
--       line at 0 BP (tier 1 on her blade); a copy with one of GOGO's points
--       pending arms his at tier 2, free of MP, and spends his point;
--     * breakunder: CELES casts Break Blade at 3 BP; a copy with two of
--       GOGO's points pending does nothing and charges nothing (his
--       OT6_BREAKBLADE stays 0): the divine's gate is the copier's boost;
--     * breakblade: a copy of it with three pending starts his own
--       (OT6_BREAKBLADE at his seat reads 3 after the copy), free.
--   M2 (GOGO, TERRA, STRAGO, RELM; GOGO's commands Lore, Steal, Blitz)
--     * ultima: a copy of TERRA's 0-BP Fire at 3 runs as Ultima ($14; $B6 at
--       ExecCmd), TERRA's fourth fold, once she has rejoined (switch $00BF);
--     * study: a copy of STRAGO's 0-BP Scan at 3, GOGO carrying Lore, writes
--       exactly the lores the present species could teach that STRAGO lacks
--       (Ot6StudyOne's $3A84 writes).  The staging is battle_gogokits' (the
--       battle_study expedient): STRAGO knows every lore this plain's
--       casters cast, so those bits of $1D29 are cleared at the open of the
--       battle the study is played in, and put back if no study taught them.
-- Each assertion has its mutant, the arm's Gogo compare in its leaf
-- (build/attempts/wt/v051-tests/mutants/mutants.py): overclock
-- (Ot6Overclocks), blade (Ot6BladeRaise), assassin (Ot6AssassinateGate),
-- ultima (Ot6FoldSteps), study (Ot6StudyCaster); each is red at its own
-- check.  Runs: build/attempts/wt/v051-tests/gogomimic/.
--
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- GOGOMIMIC_BURN ahead of the file): the walker fights that many encounters
-- by the landing first, to vary the encounter history (TESTING.md).  A
-- second lever, GOGOMIMIC_ARMS (a string of arm tags, "rune breakblade"):
-- only those arms, and the rounds that hold one, are played (a lab's or a
-- mutant's run; the suite plays every arm).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, SHADOW, EDGAR, CELES, STRAGO, RELM, GOGO = 0x00, 0x03, 0x04, 0x06, 0x07, 0x08, 0x0C
local NAMES = { [TERRA] = "TERRA", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR", [CELES] = "CELES", [STRAGO] = "STRAGO",
  [RELM] = "RELM", [GOGO] = "GOGO" }
local CMD = { MAGIC = 0x02, STEAL = 0x05, THROW = 0x08, TOOLS = 0x09, BLITZ = 0x0A, RUNIC = 0x0B, LORE = 0x0C,
  RAGE = 0x10, MIMIC = 0x12 }
local FIRE, SCAN, ULTIMA = 0x00, 0x18, 0x14
local DEBIL, SHURIKEN = 0xA7, 0x41
local BREAK_TICKS = 16                                     -- a staged break's length (OT6_BROKEN_TICKS)
local RUNICBLADE = 0x7EEDD4                                -- OT6_RUNICBLADE (ot6_memory.inc)
local RUNE_AT, BREAKBLADE_AT = 0x7EED8F, 0x7EEDA2          -- OT6_RUNE, OT6_BREAKBLADE (+ seat * 2)
local TIER_AT = 0x7EEE3A                                   -- OT6_RUNETIER (+ seat * 2)
local RUNE_RUNIC, RUNE_BLADE, RUNE_BREAK = 0xD0, 0xD1, 0xD9 -- the Rune Knight's rows (ot6_rune.asm)
local BREAK_MP, BREAK_TURNS = 99, 3
local LANDING = { 69, 183 }                                 -- the Falcon's tile by Maranda (wor-colosseum-v1's)
local BURN = type(GOGOMIMIC_BURN) == "number" and GOGOMIMIC_BURN or 0
local ONLY = type(GOGOMIMIC_ARMS) == "string" and (" " .. GOGOMIMIC_ARMS .. " ") or nil
local MAX_BATTLES = 24
local ROUND_BATTLES = 10                                   -- a round's arms all played within this many
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

-- ---- GOGO's commands (battle_gogokits' field-menu walk) ----------------------
local REC = 0x1600 + 37 * GOGO
local function gogoCmdByte(row) return H.readByte(REC + 0x16 + row) end
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
            H.log(string.format("[gogomimic] %s: GOGO's command list (%d): %s", what, n, hx(t)))
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
      H.log(string.format("[gogomimic] %s: GOGO's commands %02X %02X %02X %02X", what, gogoCmdByte(0),
        gogoCmdByte(1), gogoCmdByte(2), gogoCmdByte(3)))
      H.assertEq(gogoCmdByte(0), CMD.MIMIC, what .. ": GOGO's first command is Mimic")
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
local function runeAt(s) return H.readByte(RUNE_AT + s * 2) end
local function tierAt(s) return H.readByte(TIER_AT + s * 2) end
-- The tier a copy of blade row e arms on the copier (Ot6RuneBlade), m his
-- model at his own pending boost `pend`: his own row's when he can cast the
-- element (a row that climbs reaches the line's spell at his boost, one
-- that does not arms tier 1); when he cannot, the element's line by his
-- boost if it has one.
local function copyTier(m, e, pend)
  if m.spell[e] ~= nil then return m.tier[e] end
  if e < 4 then return runeTierOf(lineSpell(e, math.min(pend, 2))) end
  return 1
end
local function breakBladeAt(s) return H.readByte(BREAKBLADE_AT + s * 2) end
local function fourOf(fn) return { [0] = fn(0), fn(1), fn(2), fn(3) } end

-- ---- observers ---------------------------------------------------------------
-- acts: every action GOGO runs: { copy = { cmd, atk, pend } (mimicreplace, or
-- nil for his own command), cmd, atk ($b5/$b6 at ExecCmd), pend, mp0, mp1,
-- passes (Ot6PassTargeted), marks (Ot6AssassinateGate's Death writes), staged,
-- studied (Ot6StudyOne's $3A84 writes), want, blade, f; runes0/runes1 and
-- bbs0/bbs1 (every seat's OT6_RUNE and OT6_BREAKBLADE as it begins and once
-- it has ended), tiers0/tiers1 (OT6_RUNETIER likewise), armed and armedTier
-- (the values Ot6RuneArm wrote to OT6_RUNE and OT6_RUNETIER at his seat
-- during it), armedElse (its writes at any other seat), model (runeModel
-- for his seat at his pending boost, for a Runic command's action), tgt
-- (a throw's monster targets, $b9), src (the owners' last actions as it
-- begins) }
-- src: the last action each owner ran, { cmd, atk, f, pend, seat, mp0 } at
-- its ExecCmd, and { mp1, rune1, tier1, bb1, armed, armedTier } once it has
-- ended
local acts, cur, copyAt, src = {}, nil, nil, {}
local srcOpen = nil    -- the owner's action now running
local inflight = nil   -- the arm whose copy is queued or running (no Item care meanwhile)
local awaiting = nil   -- the arm whose owner's action has run, its copy still to come (no Item care either)
local round = nil
local function closeAct()
  if cur == nil or not cur.ended or H.frame <= cur.ended + 1 then return false end
  cur.mp1 = mpOf(cur.seat)
  cur.runes1, cur.bbs1, cur.bank1 = fourOf(runeAt), fourOf(breakBladeAt), H.readByte(0x3E9C + cur.seat * 2)
  cur.tiers1 = fourOf(tierAt)
  acts[#acts + 1] = cur
  local c = cur.copy
  H.log(string.format("[gogomimic] GOGO's action %d (f%d): %s; ran cmd $%02X atk $%02X at %d BP: MP %d -> %d, "
    .. "passes %d, marks %d (staged $%02X), studied $%06X (want $%06X), blade %s; rune $%02X -> $%02X (armed %s, "
    .. "%d write(s) at other seats), tier %d -> %d (armed %s), break blade %d -> %d, bank %d -> %d", #acts, cur.f,
    c and string.format("a Mimic's copy of cmd $%02X atk $%02X at %d BP", c.cmd, c.atk, c.pend) or "his own command",
    cur.cmd, cur.atk, cur.pend, cur.mp0, cur.mp1, cur.passes, cur.marks, cur.staged or 0, cur.studied, cur.want,
    tostring(cur.blade), cur.runes0[cur.seat], cur.runes1[cur.seat],
    cur.armed and string.format("$%02X", cur.armed) or "none", cur.armedElse, cur.tiers0[cur.seat],
    cur.tiers1[cur.seat], tostring(cur.armedTier or "none"), cur.bbs0[cur.seat], cur.bbs1[cur.seat], cur.bank0,
    cur.bank1))
  if c ~= nil then inflight, awaiting = nil, nil end
  cur = nil
  return true
end
-- an owner's action, closed as GOGO's is: its MP, rune and Break Blade read
-- once its end has passed (`now`: at once, when another action begins)
local function closeSrc(now)
  local r = srcOpen
  if r == nil or not (now or (r.ended and H.frame > r.ended + 1)) then return end
  r.mp1, r.rune1, r.bb1, r.tier1 = mpOf(r.seat), runeAt(r.seat), breakBladeAt(r.seat), tierAt(r.seat)
  if r.cmd == CMD.RUNIC then
    H.log(string.format("[gogomimic] f%d %s's cmd $%02X atk $%02X at %d BP has ended: MP %d -> %d, rune $%02X -> "
      .. "$%02X (armed %s), tier %d -> %d (armed %s), break blade %d -> %d", H.frame, NAMES[r.who] or "?", r.cmd,
      r.atk, r.pend, r.mp0, r.mp1, r.rune0, r.rune1, r.armed and string.format("$%02X", r.armed) or "none",
      r.tier0, r.tier1, tostring(r.armedTier or "none"), r.bb0, r.bb1))
  end
  srcOpen = nil
end

local installed = false
local function install()
  if installed then return end
  installed = true
  local function cpu() return emu.getState() end
  local function pc(st) return (st["cpu.k"] << 16) | st["cpu.pc"] end
  local mr = H.sym("mimicreplace")
  emu.addMemoryCallback(function()
    local s = gseat()
    if s == nil or (cpu()["cpu.x"] & 0xFF) ~= s * 2 then return end
    copyAt = { cmd = H.readByte(0x3F20), atk = H.readByte(0x3F21), pend = H.readByte(0x3E9D + s * 2), f = H.frame }
    H.log(string.format("[gogomimic] f%d GOGO's Mimic copies cmd $%02X atk $%02X with %d BP pending", H.frame,
      copyAt.cmd, copyAt.atk, copyAt.pend))
  end, emu.callbackType.exec, mr, mr)
  emu.addMemoryCallback(function()
    local x = cpu()["cpu.x"] & 0xFF
    if x >= 8 or (H.readByte(0xB1) & 1) == 1 then return end
    local id = H.readByte(0x3ED8 + x)
    if id ~= GOGO then
      -- (a Defend or a Row change runs here too and is never mimicked)
      if H.readByte(0xB5) == 0x15 or H.readByte(0xB5) == 0x14 then return end
      closeSrc(true)
      src[id] = { cmd = H.readByte(0xB5), atk = H.readByte(0xB6), f = H.frame, pend = H.readByte(0x3E9D + x),
        who = id, seat = x // 2, mp0 = mpOf(x // 2), rune0 = runeAt(x // 2), bb0 = breakBladeAt(x // 2),
        tier0 = tierAt(x // 2) }
      -- the model's prices and tiers for a Rune Knight's row at its pending boost, read while the seat's list
      -- and relics are the battle's
      if src[id].cmd == CMD.RUNIC then src[id].model = runeModel(x // 2, src[id].pend) end
      srcOpen = src[id]
      H.log(string.format("[gogomimic] f%d %s runs cmd $%02X atk $%02X at %d BP ($3A7C/D $%02X $%02X)", H.frame,
        NAMES[id] or string.format("$%02X", id), src[id].cmd, src[id].atk, src[id].pend, H.readByte(0x3A7C),
        H.readByte(0x3A7D)))
      for _, arm in ipairs(round and round.arms or {}) do
        if arm.owner == id and arm.cmd == src[id].cmd and (arm.atk == nil or arm.atk == src[id].atk) then
          awaiting = arm.tag
        end
      end
      return
    end
    local s = x // 2
    local want = 0
    for m = 0, 5 do if present(m) then want = want | studyRow(species(m)) end end
    closeSrc(true)
    cur = { copy = copyAt, cmd = H.readByte(0xB5), atk = H.readByte(0xB6), pend = H.readByte(0x3E9D + x),
      seat = s, mp0 = mpOf(s), passes = 0, marks = 0, studied = 0, want = want & ~lores() & 0xFFFFFF, f = H.frame,
      planned = copyAt and inflight, runes0 = fourOf(runeAt), bbs0 = fourOf(breakBladeAt), armedElse = 0, src = {},
      bank0 = H.readByte(0x3E9C + x), tiers0 = fourOf(tierAt) }
    for id2, r in pairs(src) do cur.src[id2] = r end
    -- the copier's own model at his pending boost: a copied row runs on his list and his points
    if cur.cmd == CMD.RUNIC then cur.model = runeModel(s, cur.pend) end
    copyAt = nil
    if cur.copy ~= nil and cur.cmd == CMD.THROW and cur.pend >= 3 then
      -- the declared staging (state_write_waivers.txt; battle_gogokits'):
      -- every standing non-boss monster without a Death ward is Broken as
      -- GOGO's 3-BP copy of a throw begins, so the divine has a body it may
      -- kill; OT6_BROKEN_TICKS is what Ot6AssassinateGate reads
      cur.staged = 0
      for m = 0, 5 do
        local e = 8 + m * 2
        if present(m) and H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3AA1 + e) & 0x04) == 0 then
          H.writeByte(0x3E88 + e, BREAK_TICKS)
          cur.staged = cur.staged | (1 << m)
        end
      end
      -- the body the copy is aimed at ($b9, the action's monster targets): a
      -- throw at a body that could not be staged (it wards Death) is not the
      -- divine's to judge
      cur.tgt = H.readByte(0xB9)
      if cur.staged == 0 then
        H.log(string.format("[gogomimic] f%d GOGO's copied throw: no standing monster without a Death ward to "
          .. "stage: not counted, played again next battle", H.frame))
      elseif (cur.tgt & cur.staged) == 0 then
        H.log(string.format("[gogomimic] f%d GOGO's copied throw is aimed at monsters $%02X, none of the staged "
          .. "$%02X: not counted, played again next battle", H.frame, cur.tgt, cur.staged))
      end
    end
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  -- the copy's source is stored once the action has run (SaveForMimic, after ExecCmd's animation)
  local sm = H.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    local x = cpu()["cpu.x"] & 0xFF
    if x >= 8 then return end
    local r = src[H.readByte(0x3ED8 + x)]
    if r ~= nil and r.saved == nil then r.saved = H.frame end
  end, emu.callbackType.exec, sm, sm)
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if cur and not cur.ended and (cpu()["cpu.x"] & 0xFF) == cur.seat * 2 then cur.passes = cur.passes + 1 end
  end, emu.callbackType.exec, pt, pt)
  local ag = H.sym("Ot6AssassinateGate")
  emu.addMemoryCallback(function(_, v)
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
  -- every arming of a blade (Ot6RuneArm's write to OT6_RUNE; the battle's clear writes 0): during GOGO's action
  -- it is that action's, at his seat or (counted) at another; during an owner's, the owner's
  emu.addMemoryCallback(function(addr, v)
    local off = addr - RUNE_AT
    if off % 2 ~= 0 or v == 0 then return end
    if cur and not cur.ended then
      if off == cur.seat * 2 then cur.armed = v else cur.armedElse = cur.armedElse + 1 end
    elseif srcOpen and not srcOpen.ended and off == srcOpen.seat * 2 then
      srcOpen.armed = v
    end
  end, emu.callbackType.write, RUNE_AT, RUNE_AT + 6)
  -- and its tier (Ot6RuneArm's second store, OT6_RUNETIER), by the same rule
  emu.addMemoryCallback(function(addr, v)
    local off = addr - TIER_AT
    if off % 2 ~= 0 or v == 0 then return end
    if cur and not cur.ended then
      if off == cur.seat * 2 then cur.armedTier = v end
    elseif srcOpen and not srcOpen.ended and off == srcOpen.seat * 2 then
      srcOpen.armedTier = v
    end
  end, emu.callbackType.write, TIER_AT, TIER_AT + 6)
  emu.addEventCallback(function()
    if cur ~= nil then closeAct() end
    closeSrc()
  end, emu.eventType.endFrame)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local x = cpu()["cpu.x"] & 0xFF
    if srcOpen and not srcOpen.ended and x == srcOpen.seat * 2 then srcOpen.ended = H.frame end
    if cur == nil or cur.ended or (cpu()["cpu.x"] & 0xFF) ~= cur.seat * 2 then return end
    local s = cur.seat
    cur.ended = H.frame
    cur.blade = (emu.read(RUNICBLADE, emu.memType.snesMemory) & H.readByte(0x3018 + s * 2)) ~= 0
  end, emu.callbackType.exec, ae, ae)
end

-- ---- the arms ---------------------------------------------------------------------
-- Each arm: the owner's plain action (`src`, a kitBattle entry at 0 BP), the
-- copy it wants (cmd, atk), and `check(a)` on GOGO's action that copied it.
-- `pend` is the points GOGO copies with (3 unless given); `prepare(arm, s)`,
-- run as a battle opens (s the owner's seat), says whether the pair can be
-- played in it, and sets the src and atk of an arm whose action is chosen
-- from the battle.
local got = {}         -- tag -> GOGO's action that counted
-- the slot a throw is aimed at so that the staging can break its body: the
-- first standing monster without a Death ward ($3AA1 bit 2), read as the
-- target select opens
local function throwSlot()
  for m = 0, 5 do
    local e = 8 + m * 2
    if present(m) and H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3AA1 + e) & 0x04) == 0 then return m end
  end
  return nil
end
local function copyOf(arm, from)
  for i = #acts, from or 1, -1 do
    local a = acts[i]
    if a.copy and a.planned == arm.tag and a.copy.cmd == arm.cmd and (arm.atk == nil or a.copy.atk == arm.atk)
       and a.copy.pend == (arm.pend or 3) and (arm.counts == nil or arm.counts(a)) then
      return a
    end
  end
  return nil
end

local ROUNDS = {
  { tag = "M1", party = { GOGO, EDGAR, CELES, SHADOW }, cmds = { { 1, CMD.STEAL }, { 2, CMD.BLITZ }, { 3, CMD.RAGE } },
    arms = {
      { tag = "overclock", owner = EDGAR, cmd = CMD.TOOLS, atk = DEBIL,
        src = { who = EDGAR, cmd = CMD.TOOLS, row = DEBIL, boost = 0 },
        pre = function()
          H.assertEq(sw(0x68), 1, "M1 precondition: Overclock is learned (switch $0068, the Magitek factory in "
            .. "gen_esper_tubes)")
        end,
        check = function(a)
          H.assertEq(a.passes, 2, string.format("M1: GOGO's Mimic of EDGAR's 0-BP Debilitator, copied at 3 of his "
            .. "points, fires twice (Overclock; EDGAR's own ran at %d BP)", got.overclockSrc or -1))
        end },
      { tag = "blade", owner = CELES, cmd = CMD.RUNIC,
        src = { who = CELES, cmd = CMD.RUNIC, boost = 0, self = true },
        pre = function()
          H.assertEq(sw(0x68), 1, "M1 precondition: RunicBlade is learned (switch $0068)")
        end,
        check = function(a)
          H.assertEq(a.blade, true, "M1: GOGO's Mimic of CELES's 0-BP Runic, copied at 3 of his points, is a "
            .. "RunicBlade (his OT6_RUNICBLADE bit)")
        end },
      -- SHADOW aims at a body the staging can break (throwSlot: one without
      -- a Death ward), which the copy is aimed at in turn; a copy aimed at
      -- any other body is not counted (battle_gogokits' R3 drew such a throw
      -- on formation 00D2 0087 00B0 00B0: 0 marks with $02 staged)
      { tag = "assassinate", owner = SHADOW, cmd = CMD.THROW, atk = SHURIKEN,
        counts = function(a) return a.staged ~= nil and (a.tgt & a.staged) ~= 0 end,
        src = { who = SHADOW, cmd = CMD.THROW, row = SHURIKEN, boost = 0, slotFn = throwSlot },
        check = function(a)
          H.assertEq(a.marks > 0, true, string.format("M1: GOGO's Mimic of SHADOW's 0-BP Shuriken, copied at 3 of "
            .. "his points, marks Death on the Broken non-boss it hits (Assassinate; %d mark(s), staged $%02X)",
            a.marks, a.staged))
        end },
      -- the Rune Knight's rows (#563): each is self-targeted, so its copy
      -- runs on GOGO.  CELES's row is the first blade row her list holds
      -- (an element her own battle spell list can cast in this battle).
      { tag = "rune", owner = CELES, cmd = CMD.RUNIC, pend = 0,
        prepare = function(arm, s)
          local row = runeModel(s, 0).rows[2]
          H.assertEq(row ~= nil and row[1] >= RUNE_BLADE and row[1] < RUNE_BREAK, true, "M1 precondition: CELES's "
            .. "Rune Knight's list holds a blade row (her battle spell list holds an elemental spell)")
          arm.atk, arm.src = row[1], { who = CELES, cmd = CMD.RUNIC, row = row[1], boost = 0, self = true }
          return true
        end,
        check = function(a)
          local r, bit = a.src[CELES], 1 << (a.copy.atk - RUNE_BLADE)
          H.assertEq(r ~= nil and r.atk == a.copy.atk and r.armed == bit and r.rune1 == bit, true, string.format(
            "M1 precondition: CELES's own blade row $%02X armed her blade with its element $%02X (her action: row "
            .. "$%02X, armed %s)", a.copy.atk, bit, r and r.atk or 0xFF, tostring(r and r.armed)))
          H.assertEq(r.mp0 - r.mp1, r.model.price[r.atk - RUNE_BLADE], "M1 precondition: and cost her the cheapest "
            .. "spell of that element in her list")
          H.assertEq(a.armed, bit, string.format("M1: GOGO's Mimic of CELES's blade row $%02X, copied at 0 of his "
            .. "points, arms GOGO's own rune with its element (Ot6RuneArm's write to OT6_RUNE at his seat; it held "
            .. "$%02X)", a.copy.atk, a.runes0[a.seat]))
          H.assertEq(a.runes1[a.seat], bit, "M1: and OT6_RUNE at his seat holds that element once the copy has ended")
          H.assertEq(a.armedTier, 1, "M1: at tier 1, with none of his points pending (Ot6RuneArm's write to "
            .. "OT6_RUNETIER at his seat)")
          H.assertEq(a.tiers1[a.seat], 1, "M1: and OT6_RUNETIER at his seat reads 1 once the copy has ended")
          H.assertEq(a.mp1, a.mp0, "M1: the copy is free (his MP is unchanged)")
          H.assertEq(a.armedElse, 0, "M1: the copy writes no other seat's rune")
          H.assertEq(a.runes1[r.seat], bit, "M1: and CELES's rune is hers still, the element she armed")
        end },
      -- the tier is the copier's: CELES plays a row that climbs a line at 0
      -- BP (her blade at tier 1), and the copy, with one of GOGO's points
      -- pending, arms his at tier 2, the line's second spell, free of MP; the
      -- point is spent as any boosted copy's is (Ot6ActionEnd)
      { tag = "runetier", owner = CELES, cmd = CMD.RUNIC, pend = 1,
        prepare = function(arm, s)
          local m, pick = runeModel(s, 0), nil
          for e = 7, 0, -1 do if m.climbs[e] then pick = RUNE_BLADE + e end end
          H.assertEq(pick ~= nil, true, "M1 precondition: CELES's Rune Knight's list holds a row that climbs a "
            .. "line (her cheapest spell of the element is its line's head: Ice)")
          arm.atk, arm.src = pick, { who = CELES, cmd = CMD.RUNIC, row = pick, boost = 0, self = true }
          return true
        end,
        check = function(a)
          local r, e = a.src[CELES], a.copy.atk - RUNE_BLADE
          H.assertEq(r ~= nil and r.atk == a.copy.atk and r.pend == 0 and r.armed == 1 << e and r.armedTier == 1, true,
            string.format("M1 precondition: CELES's own row $%02X at 0 BP armed her blade at tier 1 (her action: "
            .. "row $%02X at %s BP, tier %s)", a.copy.atk, r and r.atk or 0xFF, tostring(r and r.pend),
            tostring(r and r.armedTier)))
          H.assertEq(copyTier(a.model, e, a.pend), 2, string.format("M1 precondition: one point reaches the second "
            .. "spell of row $%02X's line for the copier (Ot6FoldTbl; he casts the element: %s)", a.copy.atk,
            tostring(a.model.spell[e] ~= nil)))
          H.assertEq(a.armed, 1 << e, string.format("M1: GOGO's Mimic of CELES's row $%02X, copied with one of his "
            .. "points pending, arms GOGO's own rune with its element", a.copy.atk))
          H.assertEq(a.armedTier, 2, string.format("M1: at tier 2, the tier his own boost reaches (Ot6RuneArm's "
            .. "write to OT6_RUNETIER at his seat; it held %d)", a.tiers0[a.seat]))
          H.assertEq(a.tiers1[a.seat], 2, "M1: and OT6_RUNETIER at his seat reads 2 once the copy has ended")
          H.assertEq(a.mp1, a.mp0, "M1: the copy is free (his MP is unchanged)")
          H.assertEq(a.bank1, a.bank0 - 1, string.format("M1: and his point is spent, as a boosted copy's is (bank "
            .. "%d, then %d)", a.bank0, a.bank1))
          H.assertEq(a.tiers1[r.seat], 1, "M1: CELES's blade keeps the tier she armed")
        end },
      -- Break Blade's control comes first, so GOGO has none running when it
      -- is read; each of the two pairs has CELES cast her own at 3 BP
      { tag = "breakunder", owner = CELES, cmd = CMD.RUNIC, atk = RUNE_BREAK, pend = 2,
        src = { who = CELES, cmd = CMD.RUNIC, row = RUNE_BREAK, boost = 3, self = true },
        prepare = function(_, s)
          if mpOf(s) >= 2 * BREAK_MP then return true end
          H.log(string.format("[gogomimic] CELES opens with %d MP: Break Blade's pairs wait for another battle",
            mpOf(s)))
          return false
        end,
        counts = function(a) return a.bbs0[a.seat] == 0 end,
        pre = function()
          H.assertEq(sw(0x266) == 1 or sw(0xA4) == 1, true, "M1 precondition: Break Blade is learned (switch "
            .. "$0266, or $00A4: the World of Ruin)")
        end,
        check = function(a)
          local r = a.src[CELES]
          H.assertEq(r ~= nil and r.atk == RUNE_BREAK and r.pend == 3 and r.mp0 - r.mp1 == BREAK_MP, true,
            "M1 precondition: CELES's own Break Blade ran at 3 BP, for 99 MP")
          H.assertEq(a.bbs1[a.seat], 0, "M1: GOGO's Mimic of CELES's Break Blade, copied with two of his points "
            .. "pending, starts none: OT6_BREAKBLADE at his seat stays 0 (the divine's gate is the copier's boost)")
          H.assertEq(a.mp1, a.mp0, "M1: and nothing is charged (his MP is unchanged)")
          H.assertEq(a.bank1 >= a.bank0, true, string.format("M1: nor his points (the two he raised are not spent: "
            .. "bank %d, then %d)", a.bank0, a.bank1))
        end },
      { tag = "breakblade", owner = CELES, cmd = CMD.RUNIC, atk = RUNE_BREAK,
        src = { who = CELES, cmd = CMD.RUNIC, row = RUNE_BREAK, boost = 3, self = true },
        prepare = function(_, s) return mpOf(s) >= 2 * BREAK_MP end,
        counts = function(a) return a.bbs0[a.seat] == 0 end,
        check = function(a)
          local r = a.src[CELES]
          H.assertEq(a.bbs1[a.seat], BREAK_TURNS, "M1: GOGO's Mimic of CELES's Break Blade, copied with three of "
            .. "his points pending, starts his own: OT6_BREAKBLADE at his seat reads 3 after the copy")
          H.assertEq(a.mp1, a.mp0, "M1: and the copy is free (his MP is unchanged)")
          H.assertEq(r ~= nil and r.atk == RUNE_BREAK and r.pend == 3 and r.mp0 - r.mp1 == BREAK_MP
            and r.bb1 == BREAK_TURNS, true, "M1: the Break Blade it copied was CELES's own at 3 BP: 99 MP of hers, "
            .. "and her OT6_BREAKBLADE 3 after it")
        end },
    } },
  { tag = "M2", party = { GOGO, TERRA, STRAGO, RELM }, cmds = { { 1, CMD.LORE }, { 2, CMD.STEAL }, { 3, CMD.BLITZ } },
    arms = {
      { tag = "ultima", owner = TERRA, cmd = CMD.MAGIC, atk = FIRE,
        src = { who = TERRA, cmd = CMD.MAGIC, spell = FIRE, boost = 0 },
        pre = function()
          H.assertEq(sw(0xBF), 1, "M2 precondition: TERRA has rejoined in the World of Ruin (switch $00BF, "
            .. "gen_wor_terra)")
        end,
        check = function(a)
          H.assertEq(a.atk, ULTIMA, "M2: GOGO's Mimic of TERRA's 0-BP Fire, copied at 3 of his points, runs as "
            .. "Ultima ($14), TERRA's fourth fold")
        end },
      { tag = "study", owner = STRAGO, cmd = CMD.MAGIC, atk = SCAN,
        counts = function(a) return a.want ~= 0 end,
        src = { who = STRAGO, cmd = CMD.MAGIC, spell = SCAN, boost = 0 },
        pre = function()
          local carries = false
          for r = 1, 3 do if gogoCmdByte(r) == CMD.LORE then carries = true end end
          H.assertEq(carries, true, "M2 precondition: GOGO carries Lore")
        end,
        check = function(a)
          H.assertEq(a.studied, a.want, string.format("M2: GOGO's Mimic of STRAGO's 0-BP Scan, copied at 3 of his "
            .. "points with Lore carried, studies: it adds exactly the lores the present species could teach that "
            .. "STRAGO lacks (want $%06X, wrote $%06X)", a.want, a.studied))
        end },
    } },
}

-- the GOGOMIMIC_ARMS lever: only the arms it names, and the rounds that hold one
if ONLY ~= nil then
  for i = #ROUNDS, 1, -1 do
    local arms = ROUNDS[i].arms
    for j = #arms, 1, -1 do
      if not ONLY:find(" " .. arms[j].tag .. " ", 1, true) then table.remove(arms, j) end
    end
    if #arms == 0 then table.remove(ROUNDS, i) end
  end
end

-- ---- the battle loop -------------------------------------------------------------
local battles, roundBattles = 0, 0
local plan, entryArm = {}, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function armDone(arm) return got[arm.tag] ~= nil end
local function roundDone(r)
  for _, arm in ipairs(r.arms) do if not armDone(arm) then return false end end
  return true
end
-- an arm's copy counted: record it (the check runs at the round's end)
local function settle()
  if cur ~= nil then closeAct() end
  for _, arm in ipairs(round.arms) do
    if not armDone(arm) then
      local a = copyOf(arm, got.battleActs)
      if a ~= nil then
        got[arm.tag] = a
        H.log(string.format("[gogomimic] %s: counted (GOGO's action at f%d)", arm.tag, a.f))
      end
    end
  end
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
local skipStudy = false
local function decide()
  battles, roundBattles = battles + 1, roundBattles + 1
  H.assertEq(battles <= MAX_BATTLES, true, string.format("the two rounds within %d battles", MAX_BATTLES))
  if roundBattles > ROUND_BATTLES then
    local left = {}
    for _, arm in ipairs(round.arms) do if not armDone(arm) then left[#left + 1] = arm.tag end end
    H.assertEq(#left, 0, string.format("%s: every arm played within %d battles (never counted: %s)", round.tag,
      ROUND_BATTLES, table.concat(left, ", ")))
  end
  findSeats()
  handed, plan, entryArm, inflight, awaiting = nil, {}, {}, nil, nil
  got.battleActs = #acts + 1
  got.battleF0 = H.frame
  H.assertEq(gseat() ~= nil, true, "GOGO is seated")
  local s = gseat()
  local fw = H.formationWords()
  H.log(string.format("[gogomimic] battle %d, round %s (formation %04X %04X %04X %04X %04X %04X; $BE $%02X): GOGO "
    .. "seat %d, L%d, MP %d, bank %d", battles, round.tag, fw[1], fw[2], fw[3], fw[4], fw[5], fw[6],
    H.readByte(0xBE), s, K.lv(GOGO), mpOf(s), H.readByte(0x3E9C + s * 2)))
  skipStudy = false
  local study = nil
  for _, arm in ipairs(round.arms) do if arm.tag == "study" then study = arm end end
  if study ~= nil and not armDone(study) then
    -- the lores the present species cast (Ot6StudyTbl rows): STRAGO knows
    -- every one this plain's casters know, so the declared staging
    -- (state_write_waivers.txt, the battle_study expedient) unlearns them
    -- for the study to teach again
    local rows = 0
    for m = 0, 5 do if present(m) then rows = rows | studyRow(species(m)) end end
    if rows == 0 then
      skipStudy = true
      H.log("[gogomimic] no present species casts a lore: the study waits for another battle")
    elseif rows & ~lores() & 0xFFFFFF == 0 then
      got.studyCleared = rows & lores()
      for b = 0, 2 do
        H.writeByte(0x1D29 + b, H.readByte(0x1D29 + b) & ~((got.studyCleared >> (8 * b)) & 0xFF))
      end
      H.log(string.format("[gogomimic] staged: lores $%06X unlearned for the study -> $1D29 $%06X", got.studyCleared,
        lores()))
    end
  end
  for _, arm in ipairs(round.arms) do
    if not armDone(arm) and seatOf[arm.owner] ~= nil and not (arm.tag == "study" and skipStudy)
       and (arm.prepare == nil or arm.prepare(arm, seatOf[arm.owner])) then
      local p = {}
      for k, v in pairs(arm.src) do p[k] = v end
      -- the throw a copy repeats is aimed at a body the staging Breaks (no
      -- Death ward, $3AA1 bit 2), and the Mimic copies its target; unaimed,
      -- it went to a warded body beside the staged one on the six-class
      -- replay: "0 mark(s), staged $02" (battle_gogokits had the same)
      if arm.tag == "assassinate" then
        for m = 0, 5 do
          local e = 8 + m * 2
          if p.slot == nil and present(m) and H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3AA1 + e) & 0x04) == 0 then
            p.slot = m
          end
        end
      end
      plan[#plan + 1] = p
      entryArm[p] = arm
      -- the owner's action this pair's own entry played: the last one the
      -- owner ran, once it has run after kitBattle recorded that entry's
      -- confirm and SaveForMimic has stored it.  (Two pairs of one battle can
      -- share an owner, CELES's three here: an earlier pair's action is not
      -- this pair's.)
      local srcAt = #plan
      local function played()
        local r, at = src[arm.owner], nil
        for _, kr in ipairs(H.vars.kit or {}) do if kr.entry == srcAt then at = kr.frame end end
        if r == nil or at == nil or r.f < at or r.saved == nil or H.frame <= r.saved then return nil end
        return r
      end
      -- GOGO's Mimic, once the owner's action has run in this battle and is
      -- the last one (the copy's source: SaveForMimic's $3F20)
      local m = { who = GOGO, cmd = CMD.MIMIC, boost = arm.pend or 3, self = true }
      m.openWhen = function()
        local r = played()
        local ok = r ~= nil and r.cmd == arm.cmd and H.readByte(0x3F20) == arm.cmd
          and (arm.atk == nil or H.readByte(0x3F21) == arm.atk)
        if ok and inflight ~= arm.tag then
          inflight = arm.tag
          got[arm.tag .. "Src"] = r.pend
        end
        return ok
      end
      -- the owner's action ran but is no longer the last one (another
      -- member's action, or a counter -- SHADOW's Interceptor -- ran since):
      -- the copy would be of that, so this pair waits for another battle
      m.skip = function()
        local r = played()
        if r == nil or inflight == arm.tag then
          return false
        end
        local gone = r.cmd ~= arm.cmd or H.readByte(0x3F20) ~= arm.cmd
          or (arm.atk ~= nil and H.readByte(0x3F21) ~= arm.atk)
        if gone then
          awaiting = nil
          H.log(string.format("[gogomimic] f%d %s: the owner's action is no longer the last one ($3F20 $%02X $%02X): "
            .. "played again next battle", H.frame, arm.tag, H.readByte(0x3F20), H.readByte(0x3F21)))
        end
        return gone
      end
      plan[#plan + 1] = m
      entryArm[m] = arm
    end
  end
  local tags = {}
  for _, p in ipairs(plan) do tags[#tags + 1] = (p.who == GOGO and "mimic:" or "") .. entryArm[p].tag end
  H.log(string.format("[gogomimic] battle %d plan: %s", battles, table.concat(tags, ", ")))
end
-- the plan has resolved: as many of GOGO's copies have run this battle as
-- it planned Mimics (a copy that did not count is played again next battle)
local function planDone()
  if cur ~= nil then return false end
  local want, ran = 0, 0
  for _, p in ipairs(plan) do if p.who == GOGO then want = want + 1 end end
  for i = got.battleActs, #acts do if acts[i].copy ~= nil then ran = ran + 1 end end
  return ran >= want
end

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
      H.log(string.format("[gogomimic] pacing world (%d,%d) <-> (%d,%d)", A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle on the world map"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
  })
end

local function playRound(r, first)
  return H.seqStep({
    H.call(function() roundBattles, round = 0, r end),
    regroup(r.party),
    liftOff(),
    H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
    H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon back by Maranda", fight = FIGHT }),
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 6000, "world control on the landing", 5),
    H.call(function() A, B = nil, nil end),
    H.lazy(function()
      local t = {}
      for i = 1, first and BURN or 0 do
        t[#t + 1] = worldBattle("BURN " .. i)
        t[#t + 1] = H.fightBattleByMenu(60000)
        t[#t + 1] = H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
          "BURN: back on the world map", 5)
        t[#t + 1] = H.call(function()
          H.log(string.format("[gogomimic] BURN %d: encounters used up; $1FA1-5 = %02X %02X %02X %02X %02X", i,
            H.readByte(0x1FA1), H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
        end)
      end
      return H.seqStep(t)
    end),
    H.release(),
    H.waitFrames(10),
    gogoCommands(r.cmds, r.tag .. ": GOGO's commands"),
    H.call(function()
      for _, arm in ipairs(r.arms) do
        if arm.pre then arm.pre() end
        for i = 1, 3 do
          H.assertEq(gogoCmdByte(i) ~= arm.cmd, true, string.format("%s precondition: GOGO's own commands hold no "
            .. "$%02X (%s's copy comes from Mimic alone)", r.tag, arm.cmd, arm.tag))
        end
      end
    end),
    H.driveUntil(function()
      return roundDone(r) and not H.battleLoadStarted() and H.worldMode() and H.worldHasControl()
    end, 900000, {
      H.cond(function() return not H.battleLoadStarted() end, {
        H.fieldCare({ tag = r.tag .. ": care", threshold = 0.95, mpBand = 0.95 }),
        worldBattle(r.tag),
      }, {}),
      H.call(decide),
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 90000, planDone = planDone,
        -- no new Item care while a copy is in flight: an Item is mimicked too
        care = function() return inflight == nil and awaiting == nil end,
        giveUp = function()
          if handed == nil then handed = danger() end
          return handed ~= nil
        end }),
      H.call(function()
        settle()
        if handed then H.log(string.format("[gogomimic] battle %d handed to the fight driver: %s", battles, handed)) end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(60000) }, {}),
      H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
        "back on the world map", 5),
      H.call(function()
        settle()
        -- the study's settlement: lores the staging cleared that no study
        -- taught this battle are put back
        if got.studyCleared ~= nil and (lores() & got.studyCleared) ~= got.studyCleared then
          for b = 0, 2 do
            H.writeByte(0x1D29 + b, H.readByte(0x1D29 + b) | ((got.studyCleared >> (8 * b)) & 0xFF))
          end
          H.log(string.format("[gogomimic] lores $%06X put back", got.studyCleared))
        end
        got.studyCleared = nil
      end),
    }, r.tag .. ": every arm played"),
    H.call(function()
      for _, arm in ipairs(r.arms) do arm.check(got[arm.tag]) end
      H.log(string.format("[gogomimic] %s PASS", r.tag))
    end),
  })
end

local body = {
  H.bootCheckpoint("wor-colosseum-v1"),
  H.call(function()
    say("wor", "boot")
    install()
    H.assertEq(H.invCountOf(SHURIKEN) >= 2, true, "the bag holds two Shuriken (SHADOW's throw and the copy's)")
    H.assertEq(H.invCountOf(DEBIL) >= 1, true, "the bag holds a Debilitator (EDGAR's Tools)")
  end),
}
for i, r in ipairs(ROUNDS) do body[#body + 1] = playRound(r, i == 1) end
body[#body + 1] = H.call(function()
  if ONLY ~= nil then
    H.log("[gogomimic] GOGOMIMIC_ARMS: only" .. ONLY .. "played (a lab's run, not the suite's)")
  end
  H.log(string.format("[gogomimic] PASS: GOGO's 3-BP Mimic of Tools, Runic, Throw, Fire and Scan buys Overclock, "
    .. "RunicBlade, Assassinate, Ultima and Study, and his copy of a blade row or of Break Blade runs on his own "
    .. "blade, in %d battles", battles))
end)
H.run({ maxFrames = 1500000 }, body)
