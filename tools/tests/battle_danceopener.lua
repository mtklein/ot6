-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_danceopener.lua -- a boosted Dance opens on its rare step (owner,
-- 2026-11-23: "have boosted dances guarantee the 1/16th move as a starter").
--
-- Each dance has four steps (DanceProp).  Vanilla's RandDance picks one a
-- turn from one draw of the battle RNG against DanceRateTbl ($10, $30, $90;
-- C2/05CE in the retail ROM): the fourth step below $10, the third below
-- $30, the second below $90, else the first.  RNGTbl is a permutation of
-- 0-255, so the fourth, the rare step, comes exactly 16 draws in 256.
-- The boost a Dance start is bought with loads that roll for the turn the
-- dance starts (Ot6DanceOpener, ot6_dance.asm; docs/design/kits.md, Mog):
--   0 BP   vanilla's RandDance, untouched            rare 16 of 256
--   1 BP   the row $40, $59, $A6                     rare 64 of 256
--   2 BP   the row $80, $91, $C4                     rare 128 of 256
--   3 BP   the rare step, whatever the draw          rare 256 of 256
-- Every level takes the one draw RandDance takes, the next RNGTbl entry, so
-- the draw a start's opener reads is RNGTbl[$be + 1], $be read as
-- Ot6DanceOpener begins (the menu's confirm).  Each start's opener is
-- predicted from that draw by its level's row: an exact check of the rule
-- on every draw the branches meet, not a sample of the odds.  The rows are
-- read from the built ROM and counted against RNGTbl, which are the odds.
-- The opener is danced only if the start lands: off its terrain Cmd_13's
-- roll (Ot6DanceTerrain, #473) still stumbles at 1 and 2 BP, predicted from
-- its own draw (RNGTbl[$be + 1], $be as Cmd_13 begins; battle_danceodds).
-- Later steps and a dance the engine starts are RandDance's: their draw is
-- read in A after RandDance's `jsr Rand`, and the step it returns must be
-- vanilla's for that draw.
--
-- Played, nothing written outside arm D: Continue wor-gogo-v1 (beside the
-- Falcon by Thamasa), board, and in the Falcon's cabin seat MOG, GOGO, TERRA
-- and CELES; in the field menu give GOGO Dance in his second row; lift off,
-- land by Ebot's Rock and walk into a world-map encounter
-- (battle_dancestep's walk-in).  The battle's first command window is
-- snapshotted and branched; everyone but the branch's dancer Defends.
--   A(who, level, dance): the dancer (MOG or GOGO) Defends until his bank
--      holds the level's pips (and 0-2 turns more: the draw's variation),
--      raises the boost to the level with R and starts the dance from his
--      real Dance list.  A MOG branch at 1 BP or more runs on until two of
--      his locked-in steps have resolved.
--   M: MOG starts a dance that must land (the background's own unboosted
--      if he knows it, else any at 3 BP); once he is dancing GOGO Mimics,
--      at a point if his bank holds one.
--   D (SYNTHETIC, waivered: no battle Muddles MOG on cue; battle_waterrondo's
--      staging): MOG is Muddled (STATUS2 bit 5, put back if a hit clears
--      it, his HP topped up under half) until the engine starts a Dance for
--      him (RandCharAction; no menu, so no boost).
-- A seat is the encounter walked into again from its world-map snapshot, s
-- frames later (another $be, the same formation); a branch idles 7k frames
-- more.  An encounter that keeps ending before an outcome (LOST_RUN) is
-- fought out by the walker and the next is taken, at most MAX_ENCOUNTERS.
-- A dance action in flight is given GRACE frames to end its turn before the
-- branch is called lost, so a step that wins the wave is still checked.
-- The checks run as each branch ends, and a failed rule ends the run.
--
-- Asserted, per menu start whose turn resolved (MOG's and GOGO's alike):
--   1. it was confirmed and reached Cmd_13 at the branch's level, on the
--      branch's dance;
--   2. the queued opener is the step its level's row gives for its draw:
--      at 3 BP the dance's fourth step, at 0 BP vanilla's step (and there
--      RandDance was the one that rolled it, on that same draw); a boosted
--      start did not consult RandDance;
--   3. off its terrain it stumbled exactly when the stumble ladder says
--      from the terrain roll's draw; at 3 BP never;
--   4. a start that landed danced its opener (Cmd_02 ran that attack),
--      locked the dance in and charged H.boostPrice(8, level); a start that
--      stumbled danced no step (Cmd_02 never ran), locked nothing in,
--      charged no MP, whatever opener was queued;
--   5. the boost's multiplier covers the opener as it covers every step
--      (today's rule, battle_danceboost): each Ot6BoostDmg call of the
--      start turn with damage came back times 2 per point.
-- Checks 1 and 2 need only the start's Cmd_13, so a start whose turn the
-- battle's end cut short is still checked for its opener.
-- Per locked-in step of a boosted dance, and per engine start (arm D): the
-- step RandDance returned is vanilla's for the draw it read, it is the step
-- that reached Cmd_13, and (arm D) no start passed Ot6DanceOpener and MOG
-- held no pending boost.
-- Per Mimic (arm M): a Mimic copies the action, so the copy queued the
-- copied action's own attack ($3F20/$3F21 as its Cmd_13 begins) and rolled
-- no step (neither Ot6DanceOpener nor RandDance), whatever GOGO's boost;
-- the copy is free and its damage is multiplied by his own pending boost.
-- Coverage: a 3-BP start on every dance MOG knows, each landed on its rare
-- step; MOG at 0, 1 and 2 BP MIN_M starts each, at 1 and 2 BP one that
-- opened rare, one that did not (the negative: the lower points leave the
-- gamble), and one whose draw tells the level's row from vanilla's; at 0 BP
-- one that did not open rare; a boosted start that stumbled; GOGO at 3 BP
-- on GOGO3 dances and at 0, 1 and 2 BP once each, one of them telling;
-- MIN_LATER locked-in steps of boosted dances, one of them not the rare
-- step; a boosted opener with damage; a boosted Mimic of a Dance; MIN_E
-- engine starts.
-- From the ROM: DanceRateTbl is vanilla's and the opener rows are the
-- design's, with their odds over RNGTbl.
--
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- DANCEOPENER_BURN ahead of the file): the walker fights that many
-- encounters on the landing's tiles first, to vary the encounter history
-- (TESTING.md).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CELES, MOG, GOGO = 0x00, 0x06, 0x0A, 0x0C
local NAMES = { [TERRA] = "TERRA", [CELES] = "CELES", [MOG] = "MOG", [GOGO] = "GOGO" }
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE, ST_DEF, ST_TGT = 0x05, 0x21, 0x27, 0x38
local CMD_DANCE, CMD_MIMIC = 0x13, 0x12
local CMDTBL, CMDROW = 0x202E, 0x890F
local DANCES = 0x1D4C
local LANDING = { 250, 224 }            -- gen_wor_ebot's landing by Ebot's Rock
local BURN = type(DANCEOPENER_BURN) == "number" and DANCEOPENER_BURN or 0
local MIN_M, GOGO3, MIN_LATER, LATER, MIN_E, MIN_MIM = 3, 2, 3, 2, 2, 1
local GRACE = 900                       -- frames a dance action in flight is given to end its turn
local SEATS, MAX_BRANCHES, LOST_RUN, MAX_ENCOUNTERS = 8, 24, 4, 3
local BRANCH_FRAMES = 30000             -- a branch's budget once it starts
-- the design (docs/design/kits.md, Mog): DanceRateTbl's shape, a draw below
-- the first byte is the fourth step, below the second the third, below the
-- third the second, else the first
local RATE0 = { 0x10, 0x30, 0x90 }                                        -- vanilla
local ROWS = { [1] = { 0x40, 0x59, 0xA6 }, [2] = { 0x80, 0x91, 0xC4 } }   -- 1 and 2 BP
local RARE_OF_256 = { [0] = 16, [1] = 64, [2] = 128 }
local STUMBLE = { [1] = 0x40, [2] = 0x10, [3] = 0x00 }                    -- #473's ladder
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, names = NAMES })
local regroup, liftOff, say = K.regroup, K.liftOff, K.say

local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end
local function muddled(s) return (H.readByte(0x3EE5 + s * 2) & 0x20) ~= 0 end
local function rng(i) return H.readRomByte((H.sym("RNGTbl") & 0x3FFFFF) + (i & 0xFF)) end
local function bgDance(bg) return H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg) end
local function prop(id, step) return H.readRomByte((H.sym("DanceProp") & 0x3FFFFF) + id * 4 + step) end
local function stepOfAtk(id, atk)
  for i = 0, 3 do if prop(id, i) == atk then return i end end
  return nil
end

-- the rules under test
local function stepBy(row, d)
  if d < row[1] then return 3 end
  if d < row[2] then return 2 end
  if d < row[3] then return 1 end
  return 0
end
local function vanillaStep(d) return stepBy(RATE0, d) end
local function openerStep(level, d)
  if level == 0 then return vanillaStep(d) end
  if level >= 3 then return 3 end
  return stepBy(ROWS[level], d)
end
local function stumbles(level, d)
  if level == 0 then return (d & 1) == 0 end       -- RandCarry: carry clear
  return d < STUMBLE[level]
end
local function multiplied(base, n)
  local v = base
  for _ = 1, n do
    v = v << 1
    if v > 0xFFFF then return 0xFFFF end           -- #359: saturates at $ffff
  end
  return v
end

-- ---- GOGO's commands (gen_wor_gogo's field-menu walk; battle_dancestep's) --
local function gogoCmdByte(row) return H.readByte(0x1600 + 37 * GOGO + 0x16 + row) end
local function gogoCommands(want, what)
  local ph, idx = 0, 1
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, row)
    if cur == row then return { "a" } end
    return { [cur < row and "down" or "up"] = true }
  end
  local function gogoPos()
    for p = 0, 3 do
      local b = H.readByte(0x1850 + GOGO)
      if (b & 7) == H.activeParty() and ((b >> 3) & 3) == p then return p end
    end
    return nil
  end
  local function allSet()
    for _, w in ipairs(want) do if gogoCmdByte(w[1]) ~= w[2] then return false end end
    return true
  end
  return H.withReset(H.seqStep({
    H.driveUntil(function() return allSet() and not H.menuRunning() and H.hasControl() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s = st()
        local held = {}
        while idx <= #want and gogoCmdByte(want[idx][1]) == want[idx][2] do idx = idx + 1 end
        if allSet() then
          if s ~= -1 then held = { "b" } end
        elseif s == -1 then
          if H.hasControl() then held = { "x" } end
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
          local row = nil
          for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == want[idx][2] then row = r end end
          if row == nil then error(string.format("%s: command $%02X is not in GOGO's list", what, want[idx][2]), 0) end
          held = steer(H.readByte(0x4B), row)
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, what),
    H.call(function()
      H.log(string.format("[opener] %s: GOGO's commands %02X %02X %02X %02X", what, gogoCmdByte(0),
        gogoCmdByte(1), gogoCmdByte(2), gogoCmdByte(3)))
    end),
  }), function() ph, idx = 0, 1 end)
end

-- ---- the battle's seats -----------------------------------------------------
local mogS, gogoS = nil, nil
local function findSeats()
  mogS, gogoS = nil, nil
  for s = 0, 3 do
    local id = H.readByte(0x3ED8 + s * 2)
    if id == MOG then mogS = s end
    if id == GOGO then gogoS = s end
  end
  H.assertEq(mogS ~= nil and gogoS ~= nil, true, "MOG and GOGO are in the battle party")
end
local function seatOfChar(who) return who == MOG and mogS or gogoS end

local function cmdRow(s, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local rec = nil            -- the live branch
local recs = {}
local function down(s)
  local hp, st1 = H.readWord(0x3BF4 + s * 2), H.readByte(0x3EE4 + s * 2)
  return hp == 0 or (st1 & 0xC2) ~= 0
end
-- why the branch can no longer resolve, or nil
local function lostWhy()
  if not H.battleLoadStarted() then return "the battle ended" end
  if down(mogS) then return "MOG is down" end
  if down(gogoS) then return "GOGO is down" end
  local present, standing = 0, 0
  for e = 4, 9 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      present = present + 1
      if H.readWord(0x3BF4 + e * 2) > 0 then standing = standing + 1 end
    end
  end
  if present > 0 and standing == 0 then return "the wave was won" end
  return nil
end

-- ---- observers ----------------------------------------------------------------
local function findBytes(sym, span, pat, what)
  local base = sym & 0x3FFFFF
  for off = 0, span do
    local hit = true
    for i = 1, #pat do
      if H.readRomByte(base + off + i - 1) ~= pat[i] then hit = false; break end
    end
    if hit then return sym + off end
  end
  error(what .. " not found")
end

local BD = H.sym("Ot6BoostDmg")
local BD_EXIT = H.sym("Ot6FoldCmdTbl") - 1   -- `done: plp / rtl`, the rtl

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local function cy() return emu.getState()["cpu.y"] & 0xFF end
  local function cx() return emu.getState()["cpu.x"] & 0xFF end
  local function ca() return emu.getState()["cpu.a"] & 0xFF end
  local function on(addr, fn)
    emu.addMemoryCallback(function() if rec and not rec.over then fn(rec) end end,
      emu.callbackType.exec, addr, addr)
  end
  local function seatAt(off)
    local s = off // 2
    if off % 2 == 0 and (s == mogS or s == gogoS) then return s end
    return nil
  end
  local c13 = H.sym("Cmd_13")
  -- lda #$06 / sta $3401 ("Stumbled!!")
  local arm = findBytes(c13, 0x7F, { 0xA9, 0x06, 0x8D, 0x01, 0x34 }, "Cmd_13's stumble arm")
  local rd = H.sym("RandDance")
  local dp = H.sym("DanceProp")
  -- RandDance after its `jsr Rand`: `ldx #$02 / cmp f:DanceRateTbl,x`, A = the draw
  local rdDraw = findBytes(rd, 0x40, { 0xA2, 0x02, 0xDF }, "RandDance's ldx #$02 after its draw")
  -- its end: `lda f:DanceProp,x / plx / rts`; at the plx A = the step's attack
  local rdOut = findBytes(rd, 0x40, { 0xBF, dp & 0xFF, (dp >> 8) & 0xFF, (dp >> 16) & 0xFF, 0xFA, 0x60 },
    "RandDance's lda f:DanceProp,x / plx / rts") + 4
  H.assertEq(H.readRomByte(BD_EXIT & 0x3FFFFF), 0x6B, "the byte before Ot6FoldCmdTbl is Ot6BoostDmg's rtl")
  H.assertEq(H.readRomByte((BD_EXIT - 1) & 0x3FFFFF), 0x28, "...after its plp: the proc's one exit")

  -- the menu's start: the opener's roll
  on(H.sym("Ot6DanceOpener"), function(c)
    local s = seatAt(cy())
    if not s then return end
    local be = H.readByte(0xBE)
    c.opens = c.opens + 1
    c.open[s] = { f = H.frame, be = be, d = rng(be + 1), pend = pend(s), id = H.readByte(0x32E1 + s * 2) }
    c.rdLast[s] = nil
  end)
  -- every RandDance call: the draw it read, the step and attack it returned
  on(rdDraw, function(c)
    local s = seatAt(cy())
    if not s then return end
    c.rdCur[s] = { who = s, f = H.frame, d = ca(), locked = dancing(s) }
  end)
  on(rdOut, function(c)
    local s = seatAt(cy())
    local r = s and c.rdCur[s]
    if not r then return end
    c.rdCur[s] = nil
    local ee = H.readByte(0xEE)
    r.id, r.step, r.atk = ee >> 2, ee & 3, ca()
    c.rds[#c.rds + 1] = r
    c.rdLast[s] = r
  end)
  -- Cmd_13 begins: a start (not yet dancing) or a locked-in step
  on(c13, function(c)
    local s = seatAt(cy())
    if not s then return end
    local be = H.readByte(0xBE)
    local ev = { who = s, f = H.frame, be = be, d = rng(be + 1), bg = H.readByte(0x11E2),
      locked = dancing(s), pend = pend(s), mp = mpOf(s), atk = H.readByte(0xB6),
      open = c.open[s], rd = c.rdLast[s], dmg = {},
      mim = { cmd = H.readByte(0x3F20), atk = H.readByte(0x3F21) } }   -- what a Mimic copies
    c.open[s], c.rdLast[s] = nil, nil
    c.ev[#c.ev + 1] = ev
    c.cur[s] = ev
  end)
  on(H.sym("Ot6DanceTerrain"), function(c)
    local ev = c.cur[cy() // 2]
    if ev and ev.id == nil then ev.id = ca() end
  end)
  on(arm, function(c)
    local ev = c.cur[cy() // 2]
    if ev and not ev.done then ev.stumbled = true end
  end)
  -- the step is danced: Cmd_13 goes on to Cmd_02 with the attack in $b6
  on(H.sym("Cmd_02"), function(c)
    local ev = c.cur[cy() // 2]
    if ev and not ev.done and H.readByte(0x3A7C) == CMD_DANCE and ev.cast == nil then
      ev.cast = H.readByte(0xB6)
    end
  end)
  -- the multiplier, on a dancer's Dance action
  local dmgCur = nil
  on(BD, function(c)
    local ev = c.cur[cx() // 2]
    if not ev or ev.done or H.readByte(0x3A7C) ~= CMD_DANCE then dmgCur = nil return end
    dmgCur = { ev = ev, base = H.readWord(0x11B0) }
  end)
  on(BD_EXIT, function()
    if not dmgCur then return end
    dmgCur.ev.dmg[#dmgCur.ev.dmg + 1] = { base = dmgCur.base, final = H.readWord(0x11B0) }
    dmgCur = nil
  end)
  on(H.sym("Ot6ActionEnd"), function(c)
    local s = seatAt(cx())
    local ev = s and c.cur[s]
    if ev and not ev.done then
      ev.done = { f = H.frame, dancing = dancing(s), bg = H.readByte(0x11E2), mp = mpOf(s) }
    end
  end)
  H.log(string.format("[opener] observers: Ot6DanceOpener $%06X, RandDance $%06X (draw $%06X, out $%06X), "
    .. "Cmd_13 $%06X, stumble arm $%06X, Cmd_02 $%06X, Ot6BoostDmg $%06X-$%06X, Ot6ActionEnd $%06X",
    H.sym("Ot6DanceOpener"), rd, rdDraw, rdOut, c13, arm, H.sym("Cmd_02"), BD, BD_EXIT, H.sym("Ot6ActionEnd")))
end

-- ---- the menu policy ------------------------------------------------------------
local function defend(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  return "b"
end
local function toRow(s, cmd)
  local want = cmdRow(s, cmd)
  assert(want, string.format("seat %d's battle list has command $%02X", s, cmd))
  local cur = H.readByte(CMDROW + s) & 3
  if cur ~= want then return cur < want and "down" or "up" end
  return "a"
end
local function toPend(s, p)
  if pend(s) < p then return "r" end
  if pend(s) > p then return "l" end
  return nil
end
-- the cell a dance sits in: the Dance list is packed (#541's sequel), so a
-- dance's cell is its place in the list ($267E), read live, not its id
local function danceCell(id)
  for i = 0, 7 do if H.readByte(0x267E + i) == id then return i end end
  return nil
end
local function toDance(s, id)
  local cell = danceCell(id)
  assert(cell, string.format("the Dance list holds dance %d", id))
  local row, col = cell // 2, cell % 2
  local cr, cc = H.readByte(0x893B + s), H.readByte(0x8937 + s)
  if cr ~= row then return cr < row and "down" or "up" end
  if cc ~= col then return cc < col and "right" or "left" end
  return "a"
end
-- the dancer's start from his command window: pending p, Dance, the cell of id
local function danceStart(c, s, p, id)
  local st = H.readByte(MSTATE)
  if st == ST_CMD then
    if c.press and H.frame - c.press.f > 120 then c.press = nil end   -- a later window: start again
    local b = toPend(s, p)
    if b then return b end
    return toRow(s, CMD_DANCE)
  end
  if st == ST_DANCE then
    local b = toDance(s, id)
    if b == "a" then
      c.press = { f = H.frame, pend = pend(s), bank = bank(s), mp = mpOf(s) }
      c.presses = (c.presses or 0) + 1
      if c.presses <= 2 or c.presses % 50 == 0 then
        H.log(string.format("[opener] f%d seat %d confirms dance %d (press %d): pending %d, bank %d, MP %d",
          H.frame, s, id, c.presses, pend(s), bank(s), mpOf(s)))
      end
    end
    return b
  end
  if c.press and st == ST_TGT then return "a" end   -- the dance's target window
  if c.press then return nil end      -- the confirm is closing the list: let it
  return "b"
end

local function decide(c)
  if not H.battleLoadStarted() or H.readByte(MENU) == 0 then return "a" end   -- pages, victory
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if c.arm ~= "D" and a == c.s and not c.go then
    if bank(a) < c.level or c.defs < c.extra then
      if st == ST_CMD and pend(a) > 0 then return "l" end
      if st == ST_DEF then c.defPending = true end
      return defend(st)
    end
    return danceStart(c, a, c.level, c.dance)
  end
  -- arm M: once MOG is dancing, GOGO Mimics at a point if his bank holds one
  if c.arm == "M" and a == c.gs and c.go and dancing(c.s) and not c.mim then
    if st == ST_TGT and c.mimPress then return "a" end   -- Mimic's target window
    if st ~= ST_CMD then return "b" end
    local b = toPend(a, math.min(1, bank(a)))
    if b then return b end
    c.mimPress = H.frame
    return toRow(a, CMD_MIMIC)
  end
  if st == ST_CMD and pend(a) > 0 then return "l" end
  return defend(st)
end

local ph = 0
-- a confirm counts once its seat's command list holds the action (a buzzed or
-- dropped press leaves the list empty and the window open, and is pressed again)
local function queued(s) return H.readByte(0x32CC + s * 2) ~= 0xFF end
local function drive(c)
  if c.arm ~= "D" and c.press and not c.go and (queued(c.s) or c.cur[c.s]) then
    c.go = c.press
    H.log(string.format("[opener] f%d the dance is queued (confirmed f%d)", H.frame, c.press.f))
  end
  if c.arm == "M" and c.mimPress and not c.mim and queued(c.gs) then
    c.mim = true
    H.log(string.format("[opener] f%d GOGO's Mimic is queued (pending %d)", H.frame, pend(c.gs)))
  end
  ph = ph + 1
  if ph % 8 == 0 then c.btn = decide(c) end
  if ph % 8 < 4 and c.btn then H.setPad({ [c.btn] = true }) else H.setPad({}) end
end

-- ---- what a branch observed ---------------------------------------------------
-- the branch's menu start, once it reached Cmd_13 (its opener is queued)...
local function startSeen(r)
  if r.arm == "D" then return nil end
  for _, ev in ipairs(r.ev) do
    if ev.who == r.s and not ev.locked and ev.open then return ev end
  end
  return nil
end
-- ...and once its turn resolved
local function startOf(r)
  local ev = startSeen(r)
  return ev and ev.done and ev or nil
end
-- arm M: GOGO's starts, which no Dance pick of his made
local function mimicOf(r)
  local out = {}
  if r.arm ~= "M" then return out end
  for _, ev in ipairs(r.ev) do
    if ev.who == r.gs and not ev.locked and ev.done then out[#out + 1] = ev end
  end
  return out
end
-- the dancer's locked-in steps that resolved
local function laterOf(r)
  local out = {}
  if r.arm ~= "A" then return out end
  for _, ev in ipairs(r.ev) do
    if ev.who == r.s and ev.locked and ev.done then out[#out + 1] = ev end
  end
  return out
end
-- arm D: MOG's starts that no menu made
local function engineOf(r)
  local out = {}
  if r.arm ~= "D" then return out end
  for _, ev in ipairs(r.ev) do
    if ev.who == r.s and not ev.locked and ev.done then out[#out + 1] = ev end
  end
  return out
end

-- ---- the checks, run as each branch ends (a failed rule ends the run) ----------
local fails = {}
local function check(ok, msg)
  if not ok then
    fails[#fails + 1] = msg
    H.log("[opener] FAIL " .. msg)
  end
end
local function who(r) return NAMES[r.who] end
local function checkBranch(r)
  local ev = startSeen(r)
  local tag = string.format("branch %d (%s, %d BP, dance %d)", r.k, who(r), r.level, r.dance or -1)
  if ev then
    local o = ev.open
    -- 1. the start the branch meant
    check(o.pend == r.level and ev.pend == r.level, string.format(
      "%s: confirmed with pending %d, %d at Cmd_13 (want %d)", tag, o.pend, ev.pend, r.level))
    check(o.id == r.dance and ev.id == r.dance, string.format(
      "%s: the menu chose dance %d, Cmd_13 rolled dance %s", tag, o.id, tostring(ev.id)))
    -- 2. the opener, by its level's row
    local want = openerStep(r.level, o.d)
    check(ev.atk == prop(r.dance, want), string.format(
      "%s: opener draw $%02X: queued attack $%02X (step %s), the level's row says step %d ($%02X)", tag, o.d,
      ev.atk, tostring(stepOfAtk(r.dance, ev.atk)), want, prop(r.dance, want)))
    if r.level == 3 then
      check(ev.atk == prop(r.dance, 3), string.format(
        "%s: a three-point start queued attack $%02X, not the dance's rare step $%02X", tag, ev.atk,
        prop(r.dance, 3)))
    end
    if r.level == 0 then
      check(ev.rd ~= nil and ev.rd.atk == ev.atk and ev.rd.d == o.d and ev.rd.id == r.dance, string.format(
        "%s: an unboosted start is RandDance's own roll on the same draw (RandDance %s)", tag,
        ev.rd and string.format("draw $%02X attack $%02X dance %d", ev.rd.d, ev.rd.atk, ev.rd.id) or "not called"))
    else
      check(ev.rd == nil, string.format("%s: a boosted start rolled RandDance as well", tag))
    end
  end
  ev = startOf(r)
  if ev then
    local d = ev.done
    -- 3. the terrain roll (#473)
    local off = bgDance(ev.bg) ~= r.dance
    local wantSt = off and stumbles(r.level, ev.d)
    check((ev.stumbled or false) == wantSt, string.format(
      "%s: on bg $%02X (%s its terrain), terrain draw $%02X: stumbled=%s, the ladder says %s", tag, ev.bg,
      off and "off" or "on", ev.d, tostring(ev.stumbled or false), tostring(wantSt)))
    -- 4. the opener is danced exactly when the start lands
    if ev.stumbled then
      check(ev.cast == nil, string.format("%s: the start stumbled and still danced attack $%02X", tag, ev.cast or 0))
      check(not d.dancing, string.format("%s: the start stumbled and the dance is locked in", tag))
      check(d.mp == ev.mp, string.format("%s: the stumble charged %d MP (want 0)", tag, ev.mp - d.mp))
      for _, m in ipairs(ev.dmg) do
        check(m.base == 0, string.format("%s: the stumble dealt damage (Ot6BoostDmg %d -> %d)", tag, m.base, m.final))
      end
    else
      check(ev.cast == ev.atk, string.format("%s: the start landed and danced %s, not its opener $%02X", tag,
        ev.cast and string.format("$%02X", ev.cast) or "nothing", ev.atk))
      check(d.dancing, string.format("%s: the start landed and no dance is locked in", tag))
      check(ev.mp - d.mp == H.boostPrice(8, r.level), string.format("%s: charged %d MP (want %d)", tag,
        ev.mp - d.mp, H.boostPrice(8, r.level)))
      -- 5. the multiplier covers the opener
      for _, m in ipairs(ev.dmg) do
        if m.base > 0 then
          check(m.final == multiplied(m.base, r.level), string.format(
            "%s: the opener's damage %d came back %d (want %d: times 2 per point)", tag, m.base, m.final,
            multiplied(m.base, r.level)))
        end
      end
    end
  end
  -- later steps: RandDance's, at vanilla's odds
  for _, lv in ipairs(laterOf(r)) do
    check(lv.rd ~= nil and lv.rd.atk == lv.atk, string.format(
      "branch %d: %s's locked-in step f%d queued attack $%02X, RandDance returned %s", r.k, who(r), lv.f, lv.atk,
      lv.rd and string.format("$%02X", lv.rd.atk) or "nothing"))
  end
  -- arm M: a Mimic copies the step, whatever the copier's boost
  for _, e in ipairs(mimicOf(r)) do
    local mt = string.format("branch %d (GOGO's Mimic at %d BP)", r.k, e.pend)
    check(e.open == nil and e.rd == nil, mt .. ": the copy rolled a step of its own")
    check(e.mim.cmd == CMD_DANCE and e.mim.atk == e.atk, string.format(
      "%s: the copy queued attack $%02X; the copied action is command $%02X attack $%02X", mt, e.atk, e.mim.cmd,
      e.mim.atk))
    if not e.stumbled then
      check(e.cast == e.atk and e.done.dancing, string.format("%s: the copy landed and danced %s (dancing=%s)", mt,
        e.cast and string.format("$%02X", e.cast) or "nothing", tostring(e.done.dancing)))
      check(e.done.mp == e.mp, string.format("%s: the copy charged %d MP (a Mimic is free)", mt, e.mp - e.done.mp))
      for _, m in ipairs(e.dmg) do
        if m.base > 0 then
          check(m.final == multiplied(m.base, e.pend), string.format(
            "%s: the copy's damage %d came back %d (want %d)", mt, m.base, m.final, multiplied(m.base, e.pend)))
        end
      end
    end
  end
  for _, e in ipairs(engineOf(r)) do
    check(e.open == nil and r.opens == 0, string.format(
      "branch %d: the engine's start passed Ot6DanceOpener (%d opener roll(s))", r.k, r.opens))
    check(e.pend == 0, string.format("branch %d: the engine's start held pending boost %d", r.k, e.pend))
    check(e.rd ~= nil and e.rd.atk == e.atk, string.format(
      "branch %d: the engine's start queued attack $%02X, RandDance returned %s", r.k, e.atk,
      e.rd and string.format("$%02X", e.rd.atk) or "nothing"))
  end
  -- every RandDance call the branch saw: vanilla's step for its draw
  for _, q in ipairs(r.rds) do
    check(q.step == vanillaStep(q.d) and q.atk == prop(q.id, q.step), string.format(
      "branch %d: RandDance f%d (%s) draw $%02X returned step %d of dance %d (attack $%02X); vanilla's table "
      .. "says step %d ($%02X)", r.k, q.f, q.locked and "a locked-in step" or "a start", q.d, q.step, q.id, q.atk,
      vanillaStep(q.d), prop(q.id, vanillaStep(q.d))))
  end
end

local function tally()
  local t = { M = {}, G = {}, m3 = {}, g3 = {}, g3n = 0, later = 0, laterCommon = 0, eng = 0, stumble = 0, dmg = 0,
    mim = 0 }
  for l = 0, 3 do
    t.M[l] = { n = 0, rare = 0, common = 0, tell = 0 }
    t.G[l] = { n = 0, rare = 0, common = 0, tell = 0 }
  end
  for _, r in ipairs(recs) do
    local ev = startOf(r)
    if ev then
      local x = (r.who == MOG and t.M or t.G)[r.level]
      x.n = x.n + 1
      if stepOfAtk(r.dance, ev.atk) == 3 then x.rare = x.rare + 1 else x.common = x.common + 1 end
      if openerStep(r.level, ev.open.d) ~= vanillaStep(ev.open.d) then x.tell = x.tell + 1 end
      if r.level == 3 and not ev.stumbled then
        local set = r.who == MOG and t.m3 or t.g3
        if r.who == GOGO and not set[r.dance] then t.g3n = t.g3n + 1 end
        set[r.dance] = true
      end
      if r.level >= 1 and ev.stumbled then t.stumble = t.stumble + 1 end
      if r.level >= 1 and not ev.stumbled then
        for _, m in ipairs(ev.dmg) do if m.base > 0 then t.dmg = t.dmg + 1 end end
      end
    end
    if r.arm == "A" and r.level >= 1 then
      for _, lv in ipairs(laterOf(r)) do
        if lv.rd then
          t.later = t.later + 1
          if lv.rd.step ~= 3 then t.laterCommon = t.laterCommon + 1 end
        end
      end
    end
    t.eng = t.eng + #engineOf(r)
    for _, e in ipairs(mimicOf(r)) do if e.pend >= 1 then t.mim = t.mim + 1 end end
  end
  return t
end

local function knownDances()
  local mask, out = H.readByte(DANCES), {}
  for d = 0, 7 do if mask & (1 << d) ~= 0 then out[#out + 1] = d end end
  return out
end

-- what is still short, as branches to run, in order
local function goals(t)
  local g, known = {}, knownDances()
  local function add(arm, who, level, dance, why) g[#g + 1] = { arm = arm, who = who, level = level, dance = dance, why = why } end
  for _, d in ipairs(known) do
    if not t.m3[d] then add("A", MOG, 3, d, "MOG at 3 BP on dance " .. d) end
  end
  if t.g3n < math.min(GOGO3, #known) then
    for _, d in ipairs(known) do
      if not t.g3[d] then add("A", GOGO, 3, d, "GOGO at 3 BP on dance " .. d); break end
    end
  end
  for l = 1, 2 do
    local x = t.M[l]
    if x.n < MIN_M then add("A", MOG, l, nil, string.format("MOG at %d BP: %d of %d starts", l, x.n, MIN_M))
    elseif x.rare == 0 then add("A", MOG, l, nil, string.format("MOG at %d BP: no rare opener yet", l))
    elseif x.common == 0 then add("A", MOG, l, nil, string.format("MOG at %d BP: no common opener yet", l))
    elseif x.tell == 0 then add("A", MOG, l, nil, string.format("MOG at %d BP: no telling draw yet", l)) end
  end
  if t.stumble == 0 then add("A", MOG, 1, nil, "a boosted start that stumbles") end
  if t.M[0].n < MIN_M then add("A", MOG, 0, nil, string.format("MOG at 0 BP: %d of %d starts", t.M[0].n, MIN_M))
  elseif t.M[0].common == 0 then add("A", MOG, 0, nil, "MOG at 0 BP: no common opener yet") end
  for l = 0, 2 do
    if t.G[l].n < 1 then add("A", GOGO, l, nil, string.format("GOGO at %d BP", l)) end
  end
  if t.G[1].n >= 1 and t.G[2].n >= 1 and t.G[1].tell + t.G[2].tell == 0 then
    add("A", GOGO, 1 + t.G[1].n % 2, nil, "GOGO: no telling draw yet")
  end
  if #g == 0 and (t.later < MIN_LATER or t.laterCommon == 0) then
    add("A", MOG, 1, nil, string.format("locked-in steps of a boosted dance: %d of %d, %d common", t.later, MIN_LATER,
      t.laterCommon))
  end
  if #g == 0 and t.dmg == 0 then add("A", MOG, 1, nil, "a boosted opener with damage") end
  if t.mim < MIN_MIM then add("M", MOG, 0, nil, "GOGO's boosted Mimic of a Dance") end
  if t.eng < MIN_E then add("D", MOG, 0, nil, string.format("engine starts: %d of %d", t.eng, MIN_E)) end
  return g
end
local function needMore() return #fails == 0 and #goals(tally()) > 0 end

-- ---- a branch -------------------------------------------------------------------
local snap, enc, seat, lostRun, encLost = nil, 0, 0, 0, nil
local uses = {}            -- [who .. level] = branches so far (the dance rotation)
local function branch(bi)
  local req, c
  return H.cond(function() return needMore() and lostRun < LOST_RUN and encLost == nil end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, string.format("battle snapshot load (encounter %d seat %d branch %d)", enc, seat, bi))
      H.rearmInputInjection()
      local g = goals(tally())
      local pick = g[(bi - 1) % #g + 1]
      local key = pick.who .. ":" .. pick.level
      local n = uses[key] or 0
      uses[key] = n + 1
      local dance, level = pick.dance, pick.level
      if pick.arm == "M" then
        -- MOG's start must land for GOGO to copy it: the background's own
        -- dance unboosted (no roll) if he knows it, else any at 3 BP (never)
        local known = knownDances()
        local bgd = bgDance(H.readByte(0x11E2))
        dance, level = known[n % #known + 1], 3
        for _, d in ipairs(known) do if d == bgd then dance, level = d, 0 end end
      elseif dance == nil then
        -- a known dance, off the background's terrain where there is one (the
        -- stumble roll is live there), in rotation
        local known, off = knownDances(), {}
        local bgd = bgDance(H.readByte(0x11E2))
        for _, d in ipairs(known) do if d ~= bgd then off[#off + 1] = d end end
        local from = (#off > 0 and pick.level >= 1) and off or known
        dance = from[n % #from + 1]
      end
      c = { k = #recs + 1, enc = enc, seat = seat, bi = bi, arm = pick.arm, who = pick.who, level = level,
        dance = dance, why = pick.why, s = seatOfChar(pick.who), gs = gogoS, ev = {}, cur = {}, open = {}, rdCur = {},
        rdLast = {}, rds = {}, opens = 0, defs = 0, extra = n % 3, wait = (bi - 1) * 7,
        later = (pick.arm == "A" and pick.who == MOG and pick.level >= 1) and LATER or 0,
        known = H.readByte(DANCES), bg0 = H.readByte(0x11E2) }
      recs[#recs + 1] = c
      rec = c
      ph = 0
      if c.arm == "D" then
        H.writeByte(0x3EE5 + c.s * 2, H.readByte(0x3EE5 + c.s * 2) | 0x20)
      end
      H.log(string.format("[opener] branch %d (encounter %d seat %d #%d): %s, for: %s; %d idle frames, %d extra "
        .. "Defends; bg $%02X (its dance %d); MOG bank %d MP %d, GOGO bank %d MP %d", c.k, enc, seat, bi,
        c.arm == "D" and "D (MOG Muddled, synthetic)" or string.format("%s(%s, %d BP, dance %d)", c.arm,
          NAMES[c.who], c.level, c.dance), c.why, c.wait, c.extra, c.bg0, bgDance(c.bg0),
        bank(mogS), mpOf(mogS), bank(gogoS), mpOf(gogoS)))
    end),
    H.lazy(function() return H.waitFrames(c.wait + 1) end),
    H.call(function() c.f0 = H.frame end),
    H.driveUntil(function()
      -- a dance action in flight ends its turn first (the step that wins
      -- the wave still reaches Ot6ActionEnd), within GRACE frames
      local flying = false
      for _, s in ipairs({ mogS, gogoS }) do
        local ev = c.cur[s]
        if ev and not ev.done and H.frame - ev.f < GRACE and H.battleLoadStarted() then flying = true end
      end
      if not flying then c.lost = c.lost or lostWhy() end
      if not c.lost and H.frame - c.f0 > BRANCH_FRAMES then
        c.lost = string.format("the branch's %d frames ran out", BRANCH_FRAMES)
      end
      if c.lost then return true end
      if c.arm == "D" then return #engineOf(c) > 0 end
      local st = startOf(c)
      if not st then return false end
      if st.stumbled or not st.done.dancing then return true end
      if c.arm == "M" then return #mimicOf(c) > 0 end
      return #laterOf(c) >= c.later
    end, 40000, {
      H.call(function()
        if c.defPending and H.readByte(MSTATE) ~= ST_DEF then
          c.defPending = false
          c.defs = c.defs + 1
        end
        if c.arm == "D" and H.battleActive() then
          -- the staging: Muddle put back if a hit clears it, HP topped up
          local s = c.s
          if not muddled(s) and not dancing(s) and (H.readByte(0x3EE4 + s * 2) & 0xC2) == 0 then
            H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | 0x20)
          end
          local hp, mx = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
          if hp > 0 and hp < mx // 2 then H.writeWord(0x3BF4 + s * 2, mx) end
        end
        drive(c)
      end),
      H.waitFrames(1),
    }, "the branch resolves"),
    H.call(function()
      c.over = true
      H.setPad({})
      for _, ev in ipairs(c.ev) do
        local o, r = ev.open, ev.rd
        local dm = {}
        for _, m in ipairs(ev.dmg) do dm[#dm + 1] = string.format("%d->%d", m.base, m.final) end
        H.log(string.format("[opener] branch %d %s %s f%d: attack $%02X (step %s of dance %s)%s%s | Cmd_13 $be $%02X "
          .. "draw $%02X bg $%02X (its dance %d) pending %d MP %d | stumbled=%s cast %s%s%s", c.k,
          ev.who == mogS and "MOG" or "GOGO", ev.locked and "step" or (o and "menu start" or (c.arm == "M" and string.format(
            "MIMIC start (copies command $%02X attack $%02X)", ev.mim.cmd, ev.mim.atk) or "ENGINE start")), ev.f,
          ev.atk, tostring(ev.id and stepOfAtk(ev.id, ev.atk)), tostring(ev.id),
          o and string.format(" | opener roll f%d $be $%02X draw $%02X pending %d dance %d", o.f, o.be, o.d, o.pend,
            o.id) or "",
          r and string.format(" | RandDance f%d draw $%02X -> dance %d step %d attack $%02X", r.f, r.d, r.id, r.step,
            r.atk) or " | no RandDance call",
          ev.be, ev.d, ev.bg, bgDance(ev.bg), ev.pend, ev.mp, tostring(ev.stumbled or false),
          ev.cast and string.format("$%02X", ev.cast) or "none",
          ev.done and string.format(" -> dancing=%s bg $%02X MP %d", tostring(ev.done.dancing), ev.done.bg,
            ev.done.mp) or " (unresolved)",
          #dm > 0 and (" | Ot6BoostDmg " .. table.concat(dm, " ")) or ""))
      end
      checkBranch(c)
      local got = startOf(c) ~= nil
      if c.arm == "D" then got = #engineOf(c) > 0 elseif c.arm == "M" then got = #mimicOf(c) > 0 end
      if got then lostRun = 0 else lostRun = lostRun + 1 end
      H.log(string.format("[opener] branch %d: %s%s; %d RandDance call(s), %d opener roll(s)", c.k,
        got and "resolved" or "no outcome", c.lost and (", then " .. c.lost) or "", #c.rds, c.opens))
      rec = nil
    end),
  }, {})
end

-- ---- the world --------------------------------------------------------------------
local function worldControl(what)
  return H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, what)
end
local W = nil
local function walkIn()
  local wp = 1
  return H.seqStep({
    H.call(function()
      if W then return end
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) then W = { { x + d[1], y + d[2] }, { x, y } } end
      end
      assert(W, "a walkable tile beside the landing")
      H.log(string.format("[opener] walking (%d,%d) <-> (%d,%d)", W[1][1], W[1][2], W[2][1], W[2][2]))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() or not H.worldAligned() then
          if not H.worldHasControl() then H.setPad({}) end
          return
        end
        local x, y = H.worldX(), H.worldY()
        if x == W[wp][1] and y == W[wp][2] then wp = wp % 2 + 1 end
        local tx, ty = W[wp][1], W[wp][2]
        local dir = tx > x and "right" or tx < x and "left" or ty > y and "down" or "up"
        H.setPad({ [dir] = true })
      end),
      H.waitFrames(1),
    }, "a world-map encounter fires"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
  })
end
local function fightThrough(what)
  local o0, wp = nil, 1
  return H.withReset(H.driveUntil(function() return o0 ~= nil and #H.outcomes > o0 end, 200000, {
    H.call(function() if o0 == nil then o0 = #H.outcomes end end),
    H.worldNavTo(function() return W[wp][1] end, function() return W[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.call(function() wp = wp % 2 + 1 end),
  }, what), function() o0, wp = nil, 1 end)
end

local encs = {}
local function seatOf(e, s)
  local req
  local out = {
    H.cond(function() return s > 1 end, {
      H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(encs[e].blob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "world-map snapshot load (encounter " .. e .. " seat " .. s .. ")")
        H.rearmInputInjection()
      end),
      worldControl("world control (encounter " .. e .. " seat " .. s .. ")"),
    }, {}),
    H.call(function() seat, lostRun, encLost = s, 0, nil end),
    H.waitFrames(s),
    walkIn(),
    H.call(function()
      findSeats()
      H.log(string.format("[opener] encounter %d seat %d: formation group $%04X, $be $%02X, bg $%02X (its dance %d); "
        .. "MOG slot %d (L%d, %d MP), GOGO slot %d (L%d, %d MP); known dances $%02X", e, s, H.readWord(0x11E0),
        H.readByte(0xBE), H.readByte(0x11E2), bgDance(H.readByte(0x11E2)), mogS, K.lv(MOG), mpOf(mogS), gogoS,
        K.lv(GOGO), mpOf(gogoS), H.readByte(DANCES)))
    end),
    -- the battle's first command window, whoever's
    H.driveUntil(function()
      encLost = lostWhy()
      return encLost ~= nil or (H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD)
    end, 20000, {
      H.call(function() ph = ph + 1; H.setPad((H.readByte(MENU) == 0 and ph % 8 < 4) and { a = true } or {}) end),
      H.waitFrames(1),
    }, "the first command window"),
    H.cond(function() return encLost == nil end, {
      H.call(function()
        H.assertEq(#knownDances() >= 1, true, "MOG knows a dance")
        H.assertEq(mpOf(mogS) >= H.boostPrice(8, 3), true, string.format(
          "MOG's pool (%d) pays a three-point Dance start (%d)", mpOf(mogS), H.boostPrice(8, 3)))
        H.assertEq(mpOf(gogoS) >= H.boostPrice(8, 3), true, string.format(
          "GOGO's pool (%d) pays a three-point Dance start (%d)", mpOf(gogoS), H.boostPrice(8, 3)))
        H.assertEq(cmdRow(mogS, CMD_DANCE) ~= nil and cmdRow(gogoS, CMD_DANCE) ~= nil, true,
          "MOG's and GOGO's battle lists both carry Dance")
        H.setPad({})
        snap = H.requestSaveState()
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(snap, "battle snapshot") end),
    }, {}),
  }
  for bi = 1, MAX_BRANCHES do out[#out + 1] = branch(bi) end
  return H.seqStep(out)
end

local function encounter(e)
  local req
  local out = {
    H.cond(function() return e > 1 end, {
      H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(encs[e - 1].blob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "world-map snapshot load (encounter " .. (e - 1) .. ")")
        H.rearmInputInjection()
      end),
      worldControl("world control before encounter " .. (e - 1)),
      fightThrough("the walker fights encounter " .. (e - 1) .. " out"),
    }, {}),
    worldControl("world control before encounter " .. e),
    H.fieldCare({ tag = "care before encounter " .. e, threshold = H.CARE_BEFORE_FIGHTS }),
    worldControl("world control after the care (encounter " .. e .. ")"),
    H.call(function()
      enc = e
      encs[e] = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(encs[e], "world-map snapshot (encounter " .. e .. ")") end),
  }
  for s = 1, SEATS do
    out[#out + 1] = H.cond(function() return needMore() end, { seatOf(e, s) }, {})
  end
  return H.seqStep(out)
end

local body = {
  H.bootCheckpoint("wor-gogo-v1"),
  H.call(function() say("wor", "boot") end),
  regroup({ MOG, GOGO, TERRA, CELES }),
  gogoCommands({ { 1, CMD_DANCE } }, "GOGO: Dance in his second row"),
  liftOff(),
  H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon down by Ebot's Rock", fight = FIGHT }),
  worldControl("world control on the landing"),
  H.call(function()
    say("wor", "landed")
    installObservers()
  end),
}
for i = 1, BURN do
  body[#body + 1] = H.seqStep({
    H.call(function()
      if W then return end
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) then W = { { x + d[1], y + d[2] }, { x, y } } end
      end
    end),
    fightThrough("BURN: the walker fights encounter " .. i),
    worldControl("world control after BURN " .. i),
    H.call(function()
      H.log(string.format("[opener] BURN %d: encounters used up; $1FA1-5 = %02X %02X %02X %02X %02X", i,
        H.readByte(0x1FA1), H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    end),
  })
end
for e = 1, MAX_ENCOUNTERS do
  body[#body + 1] = H.cond(function() return needMore() end, { encounter(e) }, {})
end
body[#body + 1] = H.call(function()
  H.setPad({})
  local t = tally()
  for _, w in ipairs({ { "MOG", t.M }, { "GOGO", t.G } }) do
    for l = 0, 3 do
      local x = w[2][l]
      H.log(string.format("[opener] SUMMARY %s at %d BP: %d start(s) resolved, %d opened rare, %d common, %d draw(s) "
        .. "telling the row from vanilla's", w[1], l, x.n, x.rare, x.common, x.tell))
    end
  end
  local known = knownDances()
  local m3, g3 = {}, {}
  for _, d in ipairs(known) do
    m3[#m3 + 1] = d .. (t.m3[d] and ":rare" or ":MISSING")
    if t.g3[d] then g3[#g3 + 1] = d .. ":rare" end
  end
  H.log(string.format("[opener] SUMMARY 3 BP by dance: MOG %s; GOGO %s", table.concat(m3, " "), table.concat(g3, " ")))
  H.log(string.format("[opener] SUMMARY boosted starts that stumbled %d; boosted openers with damage %d; locked-in "
    .. "steps of boosted dances %d (%d not rare); GOGO's boosted Mimics of a Dance %d; engine starts %d; %d branches",
    t.stumble, t.dmg, t.later, t.laterCommon, t.mim, t.eng, #recs))

  -- the ROM's tables, as odds over RNGTbl (literal H.sym calls: compose.py
  -- injects only the names it sees)
  local romFails = {}
  local function row(base, i) return { H.readRomByte(base + i), H.readRomByte(base + i + 1), H.readRomByte(base + i + 2) } end
  local function odds(r)
    local n = { [0] = 0, 0, 0, 0 }
    for i = 0, 255 do local s = stepBy(r, rng(i)); n[s] = n[s] + 1 end
    return n
  end
  local function rowCheck(name, got, want, rare)
    local n = odds(got)
    H.log(string.format("[opener] ROM %s: $%02X $%02X $%02X; of 256 RNGTbl entries: fourth (rare) %d, third %d, "
      .. "second %d, first %d", name, got[1], got[2], got[3], n[3], n[2], n[1], n[0]))
    if got[1] ~= want[1] or got[2] ~= want[2] or got[3] ~= want[3] or n[3] ~= rare then
      romFails[#romFails + 1] = string.format("%s is $%02X $%02X $%02X (rare %d/256), want $%02X $%02X $%02X (%d/256)",
        name, got[1], got[2], got[3], n[3], want[1], want[2], want[3], rare)
    end
  end
  rowCheck("DanceRateTbl (0 BP, vanilla)", row(H.sym("DanceRateTbl") & 0x3FFFFF, 0), RATE0, RARE_OF_256[0])
  local ok, base = pcall(function() return H.sym("Ot6DanceOpenerOdds") end)
  if not ok then
    romFails[#romFails + 1] = "Ot6DanceOpenerOdds is not in this ROM: no opener ladder"
  else
    base = base & 0x3FFFFF
    for l = 1, 2 do
      rowCheck(string.format("Ot6DanceOpenerOdds row %d (%d BP)", l, l), row(base, (l - 1) * 3), ROWS[l], RARE_OF_256[l])
    end
  end
  H.log(string.format("[opener] %d rule failure(s) across %d branches", #fails, #recs))
  for _, m in ipairs(romFails) do H.log("[opener] FAIL ROM " .. m) end

  H.assertEq(#fails, 0, "every start opened by its level's row, danced it exactly when it landed, and every "
    .. "later step and engine start was vanilla's")
  for _, d in ipairs(known) do
    H.assertEq(t.m3[d] == true, true, string.format(
      "MOG's three-point start on dance %d landed on its rare step (every dance he knows: $%02X)", d,
      H.readByte(DANCES)))
  end
  H.assertEq(t.g3n >= math.min(GOGO3, #known), true, string.format(
    "GOGO's three-point start landed on the rare step on %d dance(s) (%d)", math.min(GOGO3, #known), t.g3n))
  for l = 0, 2 do
    H.assertEq(t.M[l].n >= MIN_M, true, string.format("MOG at %d BP: at least %d starts resolved (%d)", l, MIN_M,
      t.M[l].n))
    H.assertEq(t.G[l].n >= 1, true, string.format("GOGO at %d BP: a start resolved (%d)", l, t.G[l].n))
  end
  H.assertEq(t.M[0].common >= 1, true, "MOG at 0 BP: a start that did not open on the rare step")
  for l = 1, 2 do
    H.assertEq(t.M[l].rare >= 1, true, string.format("MOG at %d BP: a start opened on the rare step", l))
    H.assertEq(t.M[l].common >= 1, true, string.format(
      "MOG at %d BP: a start did not open on the rare step (the gamble is still there)", l))
    H.assertEq(t.M[l].tell >= 1, true, string.format(
      "MOG at %d BP: a draw that tells the level's row from vanilla's was met", l))
  end
  H.assertEq(t.G[1].tell + t.G[2].tell >= 1, true, "GOGO at 1 or 2 BP: a draw that tells the row from vanilla's was met")
  H.assertEq(t.stumble >= 1, true, "a boosted start stumbled (the opener it queued was not danced)")
  H.assertEq(t.later >= MIN_LATER, true, string.format(
    "at least %d locked-in steps of boosted dances resolved (%d)", MIN_LATER, t.later))
  H.assertEq(t.laterCommon >= 1, true, "a locked-in step of a boosted dance was not the rare step (vanilla's odds)")
  H.assertEq(t.dmg >= 1, true, "a boosted opener dealt damage (the multiplier was read)")
  H.assertEq(t.mim >= MIN_MIM, true, "GOGO's boosted Mimic of a Dance resolved (the copy is the copied step)")
  H.assertEq(t.eng >= MIN_E, true, string.format("at least %d engine starts resolved (%d)", MIN_E, t.eng))
  H.assertEq(#romFails, 0, "the ROM's opener rows are vanilla's at 0 BP and 1/4 and 1/2 at 1 and 2 BP")
  H.log("[opener] PASS")
end)

H.run({ maxFrames = 8000000 }, body)
