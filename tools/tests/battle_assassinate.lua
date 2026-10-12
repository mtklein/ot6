-- @suite slow savestate=camp_escaped
-- battle_assassinate.lua -- Shadow's divine: the hit that breaks a non-boss
-- kills it.
--
--   tools/tests/run.sh tools/tests/battle_assassinate.lua
--
-- The rule (#239, owner ruling 2026-09-21; the 3-BP gate, owner 2026-10-11,
-- kits.md "Divines").  When Shadow's own hit, on an action he boosted with
-- all three points, breaks a non-boss body, the divine kills it on that
-- hit; such a hit on a body already Broken kills it too.  Under three
-- points there is no divine; there is no once-a-battle limit; never a boss
-- ($3aa1 bit 2, the instant-death protection ScimitarEffect reads).
--
-- Where the kill lives, against the action's order in battle_main.asm.
-- ExecAttack -> CalcAttackEffect: ChooseTarget, then Ot6Oblivion and
-- Ot6Assassinate (the hook point: before the hit roll, the primary target's
-- Broken read); CheckHit fills $a4 with the targets that landed (@33b1);
-- the per-target loop (@3440) calls CalcTargetDmg for each of those, whose
-- @0c0e Ot6Chip (element) and @0c1e Ot6HitJoin (Ot6ClassChip, then
-- Ot6AssassinateGate, then the shielded and broken multipliers) run at
-- damage calc; _c262ef ApplyDmg then takes the damage off the HP; and back
-- in ExecAttack, UpdateStatus applies every $3dd4 Death mark.  So the gate
-- on the chip path reads the break the same hit just wrote, marks Death
-- before the HP moves and before UpdateStatus kills: one action.  The
-- ledger below records the ROM's own order of those writes (a sequence
-- number across every callback, plus the frame and the cpu's x at the break
-- store) instead of trusting that paragraph.
--
-- Why the older instrument could never fire here.  The breaking hit is not
-- attenuated and is doubled (ot6_break.asm, Ot6ShieldedMulW and
-- Ot6BrokenDmg), and the divine used to resolve at the hook point only, before
-- that hit's chip, so it could only take a body still standing AFTER its
-- own break: ~280 hp against the back-row Imperial, and every PIERCE-weak
-- body this pool deals (CrassHoppr, 243) died on its own break, four fights
-- running (build/attempts/wt/harness-faults/lab/harness-faults/repro/
-- assassinate_fixed_s0.log).  The instrument asked for two 280-hp
-- PIERCE-weak bodies and the pool could not deal them.  That floor is gone:
-- the divine now fires at the chip, whatever the doubled hit then does to
-- the HP, so any PIERCE-weak non-boss body with shields is a suitable one.
--
-- Boots camp_escaped, the input-driven post-Magitek savestate at world
-- (179,71), party SABIN + SHADOW + CYAN, Shadow's own record carrying Fight
-- and his Imperial ($25, PIERCE per Ot6WeapClassTbl), and walks into the
-- real local pool.  Shadow Fights the PIERCE-weak body his chips are
-- furthest along on (the target cursor steered, not left at its default)
-- from the back row (H.setRows, the real Order screen), while the bench
-- answers its windows with real Defends: Right opens the Def. window
-- (btlgfx UpdateMenuState_27, state $27), A takes it.  Interceptor is in
-- the party with Shadow (battle_main.asm @4cd6: a monster's physical on
-- Shadow is blocked and countered half the time, $fc/$fd), and his counters
-- kill these bodies outright, so they are on the ledger; a fight that ends
-- without the property is pressed out of its spoils and the next encounter
-- taken, up to FIGHTS of them.  A suitable draw has at least two PIERCE-weak
-- shielded non-boss bodies and at least three bodies in all (arm 2 needs
-- hits to keep landing after the kill); the rest are fled.
--
--   1. battle 1: at 3 BP SHADOW's hits kill two bodies in one battle (no
--      once-a-battle limit); at least one is the breaking hit itself, whose
--      ledger order is checked: the chip path's break store with x =
--      SHADOW, then the in-proc $3dd4 Death mark inside Ot6AssassinateGate,
--      reached from Ot6HitJoin -- the caller read off the stack -- then the
--      body's HP write and its Death status, the frame counter ticking at
--      most once inside the action.  SHADOW's pending boost is read at every
--      break and mark.
--   2. battle 2, the gate: unboosted, his breaking hit and his hits on the
--      body it broke draw no mark.
--   3. the boss check: no boss shares a battle with Shadow anywhere in the
--      generated tree, so the negative is an isolation arm, played at 3 BP
--      (so the gate the boss check guards is open).  A fresh battle, a
--      PIERCE-weak body given $3aa1.2 -- the bit a boss
--      carries -- and STAGED_HP hit points before any chip (this file's two
--      writes), then Shadow breaks it by real chips: the break write comes,
--      no mark.  Then his next attack on it reaches the hook
--      point (Ot6Assassinate puts the Broken body to the gate before the hit
--      roll, read off the gate's entry: caller, x = Shadow, y = the body,
--      its OT6_BROKEN_TICKS nonzero) and draws no mark either.  The HP is
--      staged because no PIERCE-weak body this pool deals outlives its
--      doubled break: the hook point half was never reached in 23 runs
--      (#296; CrassHoppr, 243 HP, 143 left at the breaking hit, which does
--      ~200), so it claimed a check it did not make.  It is required now.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- ASSASSINATE_BURN ahead of the file): run from that many encounters on the
-- paced stretch before battle 1, to vary the encounter history (TESTING.md:
-- the draw moves with encounters used up, not seeds).
local BURN = type(ASSASSINATE_BURN) == "number" and ASSASSINATE_BURN or 0
-- The walk paces one pool's stretch of the boot row (H.newPacer, #306): the
-- clock pattern this file used (down, down, left, left, up, up, right,
-- right, 25 frames each) left the pool its budget was decoded from -- main
-- at 995d4a28: "battle 1 draw 1 was dealt by group 1, the pool its budget
-- was decoded from (8)" (build/attempts/main/qual-995d4a28-px13/).
-- The stretch is one whose pool can deal a suitable formation within the
-- draws built (want): camp_escaped boots on Doma's x 179..180, group 1,
-- whose pool never does ("group 1 deals a suitable formation within the 40
-- draws built (worst counter state: 1024)",
-- build/attempts/wt/v026-pacer/new_assassinate_suite.log), so the walk
-- first goes to the nearest stretch of a pool that does (P.findStart).
local worstFor              -- defined with the budget below
local MAXDRAWS = 40          -- draws built per fight; the decoded budget must fit
local P = H.newPacer({ tag = "pace",
  want = function(g) return worstFor(g) <= MAXDRAWS end })

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD, ST_DEF, ST_TGT = 0x01, 0x05, 0x27, 0x38
local SHADOW = 0x03
local OT6_PIERCE = 0x02
local BREAK_TICKS = 0x10   -- OT6_BREAK_TICKS (ot6_break.asm:1): the value
                           -- the "shields down: break" store writes; the
                           -- timer's own ticks write less
-- Arm 1's fights: battle 1 wants two kills in one fight (the divine has no
-- once-a-battle limit), and a fight falls short when Interceptor's counters
-- or the others' turns empty it first -- a matter of play, not the pool.
-- Measured at 9d364dc1 on this branch's own camp_escaped, over 0-7
-- encounters used up first (ASSASSINATE_BURN, the history lever): 8
-- successes in 25 fights, the fight counts 1, 3, 2, 10, 4, 2, 1, 2
-- (build/attempts/wt/v027-kits/budgets/battle_assassinate_*.out).  The rate
-- is 0.32; its one-sided 95% lower bound is 0.17, and at it FIGHTS = 50
-- misses with 0.83^50 = 9.0e-5, under 1e-4 (at the measured rate,
-- 0.68^50 = 4e-9).  A fight is paid for only when it is needed.
-- Arm 3 needs one: its staged body cannot fall before it breaks.
local FIGHTS = 50
-- the isolation arm's staged HP (header): enough that the bitted body
-- outlives its doubled break and the hits after it (Shadow's back-row
-- blows on this pool are ~50 shielded, ~200 on the break)
local STAGED_HP = 9999

local function ent(m) return 8 + m * 2 end
local function brk(m) return H.readByte(0x3E88 + ent(m)) end
local function sh(m) return H.readByte(0x3E38 + ent(m)) end
local function weak(m) return H.readByte(0x3E9C + ent(m)) end
local function aa1(m) return H.readByte(0x3AA1 + ent(m)) end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return H.readByte(0x3AA8 + m * 2) % 2 == 1 end
local function alive(m) return present(m) and mhp(m) > 0 end
local function dead(m) return H.readByte(0x3EE4 + ent(m)) & 0x80 ~= 0 end

local shadowSlot, msPresent = nil, {}
local function shadowPend() return shadowSlot and H.readByte(0x3E9D + shadowSlot * 2) or -1 end

-- ---- the ledger: the ROM's writes, in the ROM's order -------------------
-- One sequence counter across every callback below, so two writes in the
-- same frame still say which came first.
local GATE, SITE = H.sym("Ot6AssassinateGate"), H.sym("Ot6Assassinate")
local CLASSCHIP, ELEMCHIP = H.sym("Ot6ClassChip"), H.sym("Ot6Chip")
local seq = 0
local function stamp() seq = seq + 1; return seq end
local function cpu()
  local s = emu.getState()
  return (s["cpu.k"] << 16) | s["cpu.pc"], s["cpu.x"] & 0xFF
end
local divineKills = {}   -- { m, f, seq, pc, via }: $3dd4 Death marks from the gate
local brokeAt = {}       -- m -> { f, seq, atk, pc }: the ROM's first break
                         -- store for the body this ledger (the chip's
                         -- "shields down: break", ot6_break.asm)
local hpWrite = {}       -- m -> { f, seq }: the first HP write after its mark
local deathAt = {}       -- m -> { f, seq }: the first Death status after its mark
local killPending = {}   -- m -> true between the mark and its HP/Death writes
local watching = false
-- The gate has two callers and one mark, so the mark's pc alone cannot say
-- which rule fired: the hook point, on a later swing of one multi-swing action,
-- marks a body the first swing broke in the same frame (measured with the
-- Ot6HitJoin jsr NOP'd: build/attempts/wt/assassinate-break/negctl_nop.log
-- f35355, break seq6 then mark seq7, three shields in one action).  So the
-- caller is read off the stack at the gate's entry: jsr pushed the address
-- of its own last byte, and the two jsr sites are found in the ROM's bytes.
local function findJsr(from, to)
  for a = from, to - 3 do
    if H.readRomByte(a & 0x3FFFFF) == 0x20
      and H.readRomWord((a + 1) & 0x3FFFFF) == (GATE & 0xFFFF) then return a end
  end
  return nil
end
local HITJOIN = H.sym("Ot6HitJoin")
local jsrHit, jsrSite = findJsr(HITJOIN, HITJOIN + 0x10), findJsr(SITE, SITE + 0x20)
H.log(string.format("[gate] Ot6AssassinateGate $%06x; jsr in Ot6HitJoin: %s; "
  .. "jsr in Ot6Assassinate (hook point): %s", GATE,
  jsrHit and string.format("$%06x", jsrHit) or "NONE (the chip-path hook is not there)",
  jsrSite and string.format("$%06x", jsrSite) or "NONE"))
local gateVia = nil
local hookReads = {}     -- { f, y, broken }: the hook point put a Broken body to the gate
                         -- under Shadow's attack (x = Shadow), read at the gate's entry
emu.addMemoryCallback(function()
  if not watching then return end
  pcall(function()
    local st = emu.getState()
    local sp = st["cpu.sp"] & 0xFFFF
    local ret = H.readWord(sp + 1)
    if jsrHit and ret == ((jsrHit + 2) & 0xFFFF) then gateVia = "Ot6HitJoin"
    elseif jsrSite and ret == ((jsrSite + 2) & 0xFFFF) then gateVia = "site"
    else gateVia = string.format("$%04x", ret) end
    local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
    if gateVia == "site" and shadowSlot and x == shadowSlot * 2 and y >= 8
      and H.readByte(0x3E88 + y) ~= 0 then
      hookReads[#hookReads + 1] = { f = H.frame, y = y, seq = stamp(), pend = shadowPend() }
      H.log(string.format("[hook] f%d seq%d the hook point puts Broken body %d to the gate "
        .. "under SHADOW's attack ($3aa1=$%02x)", H.frame, seq, (y - 8) // 2,
        H.readByte(0x3AA1 + y)))
    end
  end)
end, emu.callbackType.exec, GATE, GATE)
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  pcall(function()
    local pc = cpu()
    if pc >= GATE and pc < SITE then
      local m = ((addr - 0x7E0000 - 0x3DD4) - 8) // 2
      local k = { m = m, f = H.frame, seq = stamp(), pc = pc, via = gateVia, pend = shadowPend() }
      divineKills[#divineKills + 1] = k
      killPending[m] = true
      H.log(string.format("[divine] f%d seq%d body %d: Death marked in "
        .. "Ot6AssassinateGate (pc=$%06x) via %s", k.f, k.seq, m, pc,
        tostring(gateVia)))
    end
  end)
end, emu.callbackType.write, 0x7E3DD4 + 8, 0x7E3DD4 + 0x13)
emu.addMemoryCallback(function(addr, v)
  if not watching or v ~= BREAK_TICKS then return end
  pcall(function()
    local m = ((addr - 0x7E0000 - 0x3E88) - 8) // 2
    if brokeAt[m] ~= nil then return end
    local pc, atk = cpu()
    brokeAt[m] = { f = H.frame, seq = stamp(), atk = atk, pc = pc, pend = shadowPend() }
    local site = (pc >= CLASSCHIP and pc < CLASSCHIP + 0x80) and "Ot6ClassChip"
      or ((pc >= ELEMCHIP and pc < ELEMCHIP + 0x80) and "Ot6Chip" or "?")
    H.log(string.format("[break] f%d seq%d body %d broke: %s store, "
      .. "attacker x=$%02x%s (pc=$%06x)", H.frame, brokeAt[m].seq, m, site,
      atk, (shadowSlot and atk == shadowSlot * 2) and " = SHADOW" or "", pc))
  end)
end, emu.callbackType.write, 0x7E3E88 + 8, 0x7E3E88 + 0x13)
emu.addMemoryCallback(function(addr, v)
  if not watching then return end
  local m = (addr - 0x7E3BFC) // 2
  if killPending[m] and hpWrite[m] == nil then
    hpWrite[m] = { f = H.frame, seq = stamp() }
  end
end, emu.callbackType.write, 0x7E3BFC, 0x7E3C07)
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  local m = ((addr - 0x7E0000 - 0x3EE4) - 8) // 2
  if killPending[m] and deathAt[m] == nil then
    deathAt[m] = { f = H.frame, seq = stamp() }
    killPending[m] = nil
    H.log(string.format("[death] f%d seq%d body %d: Death status applied "
      .. "(hp write at f%s seq%s)", H.frame, deathAt[m].seq, m,
      hpWrite[m] and hpWrite[m].f or "-", hpWrite[m] and hpWrite[m].seq or "-"))
  end
end, emu.callbackType.write, 0x7E3EE4 + 8, 0x7E3EE4 + 0x13)

-- ---- Interceptor's counters, on the ledger (read-only) -------------------
-- battle_main.asm @4cd6 stores the counter's attack, $fc + a coin flip
-- (Takedown / Wild Fang), into $3a7b before CreateRetalAction.
local counters = 0
emu.addMemoryCallback(function(_, v)
  if v == 0xFC or v == 0xFD then
    counters = counters + 1
    H.log(string.format("[interceptor] f%d counter $%02x (%d this ledger)",
      H.frame, v, counters))
  end
end, emu.callbackType.write, 0x7E3A7B, 0x7E3A7B)

-- monster HP drops per body: Shadow's chips and Interceptor's counters (the
-- bench Defends).  brokenHits counts drops on a body whose Broken state
-- was live.
local hpDrops, brokenHits = 0, 0
local lastBrk, lastHp = {}, {}
local function scanBodies()
  for _, m in ipairs(msPresent) do
    local hp = mhp(m)
    if lastHp[m] ~= nil and hp < lastHp[m] then
      hpDrops = hpDrops + 1
      if (lastBrk[m] or 0) ~= 0 then brokenHits = brokenHits + 1 end
    end
    lastHp[m] = hp
    lastBrk[m] = brk(m)
  end
end
local function resetLedger()
  lastBrk, lastHp = {}, {}
  hpDrops, brokenHits, counters = 0, 0, 0
  divineKills, brokeAt, hpWrite, deathAt, killPending = {}, {}, {}, {}, {}
  hookReads = {}
  scanBodies()
  watching = true
end
-- break stores recorded after sequence number s
local function breaksAfter(s)
  local n = 0
  for _, b in pairs(brokeAt) do if b.seq > s then n = n + 1 end end
  return n
end

-- ---- Shadow's target ------------------------------------------------------
-- The PIERCE-weak body his chips are furthest along on: the fewest shields,
-- else the most HP.  nil when no PIERCE-weak body stands, which takes the
-- default.  `forced` names one body for the isolation arm.
local forced = nil
local function pickTarget()
  if forced ~= nil and alive(forced) then return forced end
  local best, bs, bh = nil, nil, nil
  for _, m in ipairs(msPresent) do
    if alive(m) and (weak(m) & OT6_PIERCE) ~= 0 then
      local s, h = sh(m), mhp(m)
      if best == nil or s < bs or (s == bs and h > bh) then
        best, bs, bh = m, s, h
      end
    end
  end
  return best
end

-- ---- the action driver: SHADOW Fights, the bench Defends, the spoils are
-- pressed out (one call per frame) ------------------------------------------
local T = H.targetCursor()
local mf, hb, aPhase = 0, -1200, 0
local tapNo, tapAt = -1, 0   -- the steer's tap being pressed, and since when
local function fightPulse()
  scanBodies()
  T.observe()
  if H.readByte(MSTATE) ~= ST_TGT then tapNo = -1 end
  if H.frame - hb >= 600 then
    hb = H.frame
    local parts = {}
    for _, m in ipairs(msPresent) do
      parts[#parts + 1] = string.format("m%d:%d/sh%d%s", m, mhp(m), sh(m),
        brk(m) ~= 0 and "B" or "")
    end
    H.log(string.format("[pulse f%d] menu=%02x act=%d st=%02x drops=%d "
      .. "broken=%d ic=%d kills=%d shadow bp=%d pend=%d want=%d tgt=%s %s", H.frame,
      H.readByte(MENU), H.readByte(ACTOR) & 3, H.readByte(MSTATE), hpDrops,
      brokenHits, counters, #divineKills, shadowSlot and H.readByte(0x3E9C + shadowSlot * 2) or -1,
      shadowPend(), H.vars.shadowBoost or 0, tostring(pickTarget()),
      table.concat(parts, " ")))
  end
  if H.readByte(MENU) == 0 then
    -- no window up: an animation, or the spoils.  battleLoadStarted()
    -- reads true through the victory boxes and A alone advances them
    -- (M.fleeBattle's finding), so a fight nobody stands in is pressed out.
    if #H.activeSlots() == 0 then
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { a = true } or {})
    else
      H.setPad({})
    end
    return
  end
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  local btn
  if act ~= shadowSlot then
    -- a real Defend: Right opens the Def. window, A takes it.  The
    -- states between (the window sliding open, $25/$26) get nothing: a B
    -- there cancels the Right (measured: `right` and `b` one frame apart,
    -- build/attempts/wt/harness-faults/lab/harness-faults/repro/
    -- assassinate_fixed_s0.log f7314-7315).  A target window the bench
    -- never asked for is backed out of.
    if st == ST_CMD then btn = "right"
    elseif st == ST_DEF then btn = "a"
    elseif st == ST_TGT then btn = "b"
    else btn = nil end
    if not edge then btn = nil end
  elseif st == ST_CMD then
    -- the boost the arm wants (H.vars.shadowBoost, 0 or 3): Defend while the
    -- bank is short of it, then R (or L) to exactly it, then Fight
    local want = H.vars.shadowBoost or 0
    local e = shadowSlot * 2
    local pend, bank = H.readByte(0x3E9D + e), H.readByte(0x3E9C + e)
    local cur = H.readByte(0x890F + shadowSlot) & 3
    if want > 0 and bank < want and pend == 0 then btn = "right"
    elseif pend < want and bank >= want then btn = "r"
    elseif pend > want then btn = "l"
    else btn = (cur == 0) and "a" or "up" end   -- Fight is row 0
    if not edge then btn = nil end
  elseif st == ST_DEF then
    btn = edge and "a" or nil           -- SHADOW's own Defend, banking
  elseif st == ST_TGT then
    -- H.targetCursor: "a" once the cursor sits on the wanted body, else a
    -- direction, decided once per 16-frame cycle at whatever phase the
    -- window lit and returned through the cycle's first half.  Each
    -- decided tap (T.press counts them) is pressed for four frames from
    -- its decision.  Pressing only on the cycle's own first four frames
    -- lost a tap decided at phase 4-7, and the steer then booked that
    -- direction as one that moves nothing and never tried it again
    -- (preview sweep shifts 28 and 35: LEFT from slot 3 was decided but
    -- never on the pad, build/attempts/wt/assassinate-break/
    -- probe_tgt_s28b.log f2942-2955, and the body two cells left was
    -- "never lit" after 24 taps).
    btn = T.steer(pickTarget(), mf)
    if btn == "a" then
      if not edge then btn = nil end
    else
      if btn ~= nil and T.press ~= tapNo then tapNo, tapAt = T.press, mf end
      btn = (tapNo >= 0 and mf - tapAt < 4) and T.dir or nil
    end
  elseif st == ST_TRANS then
    btn = nil   -- NOTHING in transitional $01: an A held here is still
                -- down when the command window goes live and confirms row 0
  else
    btn = edge and "b" or nil   -- B elsewhere: advances messages, confirms
                                -- nothing
  end
  H.setPad(btn and { [btn] = true } or {})
end
local function drive(pred, maxFrames, what)
  return H.driveUntil(pred, maxFrames, { H.call(fightPulse) }, what)
end

-- ---- encounter selection --------------------------------------------------
-- suitable: at least two PIERCE-weak shielded non-boss bodies (one for the
-- kill, one for the fight to go on with) and at least three bodies in all
-- (arm 2's control needs hits to land after the kill); else flee.
local function suitableDraw()
  local pierce, bodies = 0, 0
  for _, m in ipairs(msPresent) do
    if alive(m) then
      bodies = bodies + 1
      if (weak(m) & OT6_PIERCE) ~= 0 and sh(m) > 0 and (aa1(m) & 0x04) == 0 then
        pierce = pierce + 1
      end
    end
  end
  return pierce >= 2 and bodies >= 3
end
local function walkSteps(n)
  return {
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 4000, "world control (draw " .. n .. ")", 5),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        H.setPad(P.pad())
      end),
    }, "a real world encounter fires (draw " .. n .. ")"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200,
      "battle active (draw " .. n .. ")", 5),
    H.waitFrames(120),
    H.call(function()
      msPresent = {}
      for m = 0, 5 do if present(m) then msPresent[#msPresent + 1] = m end end
      H.vars.suitable = suitableDraw()
      local parts = {}
      for _, m in ipairs(msPresent) do
        parts[#parts + 1] = string.format("m%d hp=%d sh=%d weak=%02x aa1=%02x",
          m, mhp(m), sh(m), weak(m), aa1(m))
      end
      H.log(string.format("draw %d: %s -> %s", n, table.concat(parts, " | "),
        H.vars.suitable and "FIGHT" or "flee"))
    end),
    H.cond(function() return not H.vars.suitable end, {
      H.fleeBattle(9000, { onCantRun = "fight" }),
      H.waitFrames(30),
    }, {}),
  }
end
-- How many draws a fight may take to be dealt a suitable formation (#299).
-- Which slot of the pool comes next is fixed by the save's encounter counter
-- ($1fa2/$1fa3, lib/ot6_field.lua above M.worstCaseEncounters), and every
-- regeneration of the chain deals camp_escaped a different one, so the
-- budget is the most encounters ANY counter state needs to deal a slot whose
-- every formation suits (suitableDraw's test, decoded from the ROM: three or
-- more bodies, two of them PIERCE-weak by their class row,
-- H.speciesClassRow, with shields -- an authored Ot6ShieldTbl count, else
-- the level formula's 2 or more), over the group the paced stretch rolls
-- (P.group).  Every draw asserts CheckBattleWorld rolled that group
-- (P.assertGroup).  The six draws this file used to build were a bare
-- number.
local budgets = {}
local function speciesShields(sp)
  local t = H.sym("Ot6ShieldTbl") & 0x3FFFFF
  for i = 0, 1023 do
    local id = H.readRomWord(t + i * 4)
    if id == 0xFFFF then break end
    if id == sp then return H.readRomByte(t + i * 4 + 2) end
  end
  return 2                   -- the formula: 2 + level / 8, capped at 6
end
worstFor = function(group)
  if budgets[group] then return budgets[group] end
  local pool = H.encounterPool(group)
  local ok, parts = {}, {}
  for slot = 1, 4 do
    ok[slot] = true
    local names = {}
    for _, f in ipairs(pool[slot].formations) do
      local pierce = 0
      for _, sp in ipairs(f.species) do
        if (H.speciesClassRow(sp) & OT6_PIERCE) ~= 0 and speciesShields(sp) > 0 then
          pierce = pierce + 1
        end
      end
      ok[slot] = ok[slot] and pierce >= 2 and #f.species >= 3
      names[#names + 1] = string.format("%d (%d bodies, %d PIERCE-weak shielded)", f.id,
        #f.species, pierce)
    end
    parts[#parts + 1] = string.format("slot %d (%d/256) %s%s", slot, pool[slot].odds,
      table.concat(names, ", "), ok[slot] and " suits" or "")
  end
  local worst, hist = H.worstCaseEncounters(function()
    return function(slot) return ok[slot] end
  end)
  H.log(string.format("[budget] group %d: %s -- the worst of the 65536 encounter-counter "
    .. "states needs %d draw(s); %.1f%% need no more than 6", group, table.concat(parts, "; "),
    worst, 100 * H.encounterShare(hist, 6)))
  budgets[group] = worst
  return worst
end
local function budgetFor(group)
  local worst = worstFor(group)
  H.assertEq(worst <= MAXDRAWS, true, string.format("group %d deals a suitable formation "
    .. "within the %d draws built (worst counter state: %d)", group, MAXDRAWS, worst))
  return worst
end
local function encounter(tag)
  local group, budget = nil, nil
  local steps = { H.call(function() H.vars.suitable = false end) }
  for n = 1, MAXDRAWS do
    local w = walkSteps(n)
    table.insert(w, 5, H.call(function()
      group, budget = P.group, budgetFor(P.group)
      P.assertGroup(string.format("%s draw %d", tag, n))
    end))
    if n == 1 then
      for _, s in ipairs(w) do steps[#steps + 1] = s end
    else
      steps[#steps + 1] = H.cond(function()
        return not H.vars.suitable and n <= budget
      end, w, {})
    end
  end
  steps[#steps + 1] = H.call(function()
    H.assertEq(H.vars.suitable, true, string.format("%s: the pool dealt two PIERCE-weak "
      .. "shielded bodies among three or more within %d draws, the most any "
      .. "encounter-counter state needs from group %d", tag, budget, group))
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == SHADOW then shadowSlot = s end
    end
    H.assertEq(shadowSlot ~= nil, true, tag .. ": SHADOW is really here")
    for _, m in ipairs(msPresent) do
      H.assertEq(aa1(m) & 0x04, 0, string.format(
        "%s: body %d is a non-boss (no $3aa1.2) -- the pool precondition",
        tag, m))
    end
    mf = 0
    resetLedger()
  end)
  return H.repeatN(1, steps)
end
-- the next fight, when this one is over
local function nextFight(tag)
  return H.cond(function() return not H.battleLoadStarted() end,
    { encounter(tag) }, {})
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  -- SHADOW to the back row, through the real Order screen (H.setRows): the
  -- back row halves his physical damage, so the bodies outlive more of
  -- his chips (arm 2's second break, arm 3's hook point half).
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row" }),
  H.waitUntil(function() return H.worldSettled() end, 1500, "the world map settled", 5),
  (function()
    local sx, sy
    return H.seqStep({
      H.call(function() sx, sy = P.findStart(8) end),
      H.worldNavTo(function() return sx end, function() return sy end,
        { maxFrames = 4000, playBattles = "mustflee", care = false }),
      H.waitUntil(function() return H.worldSettled() end, 1500, "settled on the stretch", 5),
      H.call(function() P.plan() end),
    })
  end)(),
})
for i = 1, BURN do
  add({
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function() H.setPad(P.pad()) end),
    }, "BURN encounter " .. i),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, "BURN battle " .. i .. " active", 5),
    H.call(function() P.assertGroup("BURN encounter " .. i) end),
    H.fleeBattle(9000, { onCantRun = "fight" }),
    H.waitUntil(function() return H.worldSettled() end, 1500, "settled after BURN " .. i, 5),
  })
end

-- ===================== battle 1: the divine, twice in one battle ==========
-- In one battle (a fight that ends before both is pressed out and the next
-- one is taken, up to FIGHTS of them, each starting over), SHADOW Defends
-- to 3 BP and Fights at 3 BP until a mark comes, then does it again until a
-- mark comes on another body: the divine again in the same battle.  Every
-- body's first mark is checked: SHADOW's pending boost was 3 when it was
-- written, the body was Broken before it, and one whose break was his own
-- 3-BP hit on the same action is the breaking hit itself, its ledger in
-- order (the break store, the mark, the HP write, the Death status, the
-- frame counter ticking at most once); and the body is dead.
local phase, fights = "b", 0
local function firstMarks()
  local t, seen = {}, {}
  for _, k in ipairs(divineKills) do
    if not seen[k.m] then seen[k.m] = true; t[#t + 1] = k end
  end
  return t
end
add({
  (function()
    local fight = {
      nextFight("battle 1"),
      H.call(function()
        fights = fights + 1
        phase = "b"
        H.vars.shadowBoost = 3
        H.log(string.format("[battle 1] fight %d of up to %d", fights, FIGHTS))
      end),
      drive(function() return #firstMarks() >= 2 or not H.battleLoadStarted() end, 40000,
        "SHADOW at 3 BP: the divine, twice"),
      H.call(function()
        if #firstMarks() < 2 then
          H.log(string.format("[battle 1] fight %d ended with %d body(ies) marked (marks %d, hpDrops %d, interceptor "
            .. "%d) -- the next encounter", fights, #firstMarks(), #divineKills, hpDrops, counters))
          divineKills, brokeAt, hookReads = {}, {}, {}
        end
      end),
    }
    return H.repeatN(1, {
      H.repeatN(FIGHTS, {
        H.cond(function() return #firstMarks() < 2 end, fight, {}),
      }),
      H.waitFrames(8),
      H.call(function()
        local marks = firstMarks()
        H.assertEq(#marks >= 2, true, string.format("SHADOW's divine killed two bodies in one battle within %d "
          .. "fight(s) (fought %d)", FIGHTS, fights))
        local breaking = 0
        for i, k in ipairs(marks) do
          local b = brokeAt[k.m]
          H.log(string.format("[battle 1] mark %d: body %d at f%d seq%d via %s, SHADOW's pending %d; break %s; hp "
            .. "write %s; death %s; dead=%s", i, k.m, k.f, k.seq, tostring(k.via), k.pend,
            b and string.format("f%d seq%d x=$%02x pend %d", b.f, b.seq, b.atk, b.pend) or "none",
            hpWrite[k.m] and string.format("f%d seq%d", hpWrite[k.m].f, hpWrite[k.m].seq) or "none",
            deathAt[k.m] and string.format("f%d seq%d", deathAt[k.m].f, deathAt[k.m].seq) or "none",
            tostring(dead(k.m))))
          H.assertEq(k.pend, 3, string.format("mark %d: SHADOW's action was boosted with all three points", i))
          H.assertEq(dead(k.m), true, string.format("mark %d: the body is dead", i))
          H.assertEq(b ~= nil and b.seq < k.seq, true, string.format("mark %d: the body was Broken before it "
            .. "(the ROM's chip path wrote OT6_BROKEN_TICKS)", i))
          if b.atk == shadowSlot * 2 and b.pend == 3 and k.via == "Ot6HitJoin" and b.seq + 1 == k.seq then
            breaking = breaking + 1
            H.assertEq(b.f == k.f, true, string.format("mark %d: the breaking hit's break write and Death mark "
              .. "are one frame: break f%d, mark f%d", i, b.f, k.f))
            local hw, da = hpWrite[k.m], deathAt[k.m]
            H.assertEq(hw ~= nil and hw.seq == k.seq + 1 and hw.f - k.f <= 1, true, string.format("mark %d: "
              .. "the mark precedes the hit's HP write (ApplyDmg), the next ledger event after it", i))
            H.assertEq(da ~= nil and da.seq == hw.seq + 1 and da.f - k.f <= 1, true, string.format("mark %d: "
              .. "UpdateStatus applied the Death right after the HP write: the breaking hit and the kill are "
              .. "one action", i))
          end
        end
        H.log(string.format("[battle 1] %d of the %d bodies' first marks were the breaking hit itself (%d marks "
          .. "in all: a later swing of one Fight re-marks a body it killed)", breaking, #marks, #divineKills))
        H.assertEq(breaking >= 1, true, "at least one kill was the breaking hit itself (#239)")
        watching = false
        H.screenshot("assassinate_kill")
      end),
    })
  end)(),
})

-- ===================== battle 2: the gate, under three points ==============
-- SHADOW Fights unboosted until his own hit breaks a PIERCE-weak body: the
-- break store comes (x = SHADOW, his pending boost 0) and no in-proc Death
-- mark; then he Fights on, unboosted, until another hit of his lands on the
-- Broken body (the hook point puts it to the gate): no mark either.
local control, controlFights = nil, 0
add({
  H.call(function()
    -- battle 1's fight may still be up: battle 2 continues it (nextFight
    -- draws only once it is over), with a fresh ledger
    divineKills, brokeAt, hookReads, hpWrite, deathAt, killPending = {}, {}, {}, {}, {}, {}
    watching = true
  end),
  (function()
    local fight = {
      nextFight("battle 2"),
      H.call(function()
        controlFights = controlFights + 1
        H.vars.shadowBoost = 0
        H.log(string.format("[battle 2] fight %d of up to %d (unboosted)", controlFights, FIGHTS))
      end),
      drive(function()
        for m, b in pairs(brokeAt) do
          if b.atk == shadowSlot * 2 and b.pend == 0 then control = { m = m, b = b }; return true end
        end
        return not H.battleLoadStarted()
      end, 30000, "SHADOW's unboosted hit breaks a body"),
      H.cond(function() return control ~= nil and H.battleLoadStarted() end, {
        H.call(function() H.vars.hookReads0 = #hookReads end),
        drive(function()
          for i = H.vars.hookReads0 + 1, #hookReads do
            if hookReads[i].y == ent(control.m) then return true end
          end
          return not alive(control.m) or brk(control.m) == 0 or not H.battleLoadStarted()
        end, 30000, "his next unboosted attack on the Broken body reaches the hook point"),
      }, {}),
      H.waitFrames(8),
      H.call(function()
        if control == nil then
          H.log(string.format("[battle 2] fight %d ended with no unboosted break by SHADOW", controlFights))
        end
      end),
    }
    return H.repeatN(1, {
      H.repeatN(FIGHTS, { H.cond(function() return control == nil end, fight, {}) }),
      H.call(function()
        H.assertEq(control ~= nil, true, string.format("SHADOW's unboosted hit broke a body within %d fight(s)",
          FIGHTS))
        local hooked = nil
        for i = (H.vars.hookReads0 or 0) + 1, #hookReads do
          if hookReads[i].y == ent(control.m) then hooked = hookReads[i] end
        end
        H.log(string.format("[battle 2] body %d broke at f%d seq%d by SHADOW at %d BP pending; hook point %s; marks %d",
          control.m, control.b.f, control.b.seq, control.b.pend, hooked and string.format("read it at f%d (pending %d)",
          hooked.f, hooked.pend) or "not reached", #divineKills))
        H.assertEq(#divineKills, 0, "under three points SHADOW's breaking hit, and his hits on the Broken body, "
          .. "drew no in-proc Death mark")
        watching = false
      end),
    })
  end)(),
})

-- ============== battle 3: the labeled isolation arm ========================
-- The boss check, with the injected bit and HP; see the header.  A fresh
-- battle, the PIERCE-weak body with the most HP given $3aa1.2 and
-- STAGED_HP before any chip, then Shadow's chips, at 3 BP, break it: the
-- break write comes with no in-proc Death mark; then his
-- next attack's hook point reads it Broken: no mark either.  The writes
-- below are this file's only ones and may never produce fixtures.  With
-- the staged HP neither Interceptor's counters nor the doubled break can
-- fell the body, so one fight is the expectation; a fight that still ends
-- unbroken is followed by another, up to FIGHTS of them.
add({
  H.loadState(STATE),
  H.waitFrames(20),
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row (arm 3)" }),
  (function()
    local broke, fights = false, 0
    local pass = {
      nextFight("isolation arm"),
      H.call(function()
        fights = fights + 1
        H.vars.shadowBoost = 3   -- the gate open, so the boss check is what refuses
        local best, bh = nil, nil
        for _, m in ipairs(msPresent) do
          if alive(m) and (weak(m) & OT6_PIERCE) ~= 0 and sh(m) > 0
            and (best == nil or mhp(m) > bh) then best, bh = m, mhp(m) end
        end
        H.assertEq(best ~= nil, true, string.format("isolation arm fight %d: a "
          .. "PIERCE-weak shielded body stands to wear the boss bit (a fresh "
          .. "battle's draw)", fights))
        H.vars.bossBody = best
        H.writeByte(0x3AA1 + ent(best), aa1(best) | 0x04)   -- the arm's writes (header)
        H.writeWord(0x3BF4 + ent(best), STAGED_HP)
        forced = best
        resetLedger()
        H.log(string.format("[isolation arm] fight %d: body %d (hp=%d sh=%d) "
          .. "wears $3aa1.2 -- the bit a boss carries -- before any chip",
          fights, best, mhp(best), sh(best)))
      end),
      drive(function()
        local m = H.vars.bossBody
        return brokeAt[m] ~= nil or not alive(m) or not H.battleLoadStarted()
      end, 30000, "Shadow's chips break the bitted body (isolation arm)"),
      H.call(function()
        local m = H.vars.bossBody
        local b = brokeAt[m]
        if b ~= nil then
          broke = true
          H.log(string.format("[isolation arm] body %d broke at f%d seq%d by "
            .. "x=$%02x%s at %d BP pending: divineKills=%d hp=%d alive=%s", m, b.f,
            b.seq, b.atk, b.atk == shadowSlot * 2 and " (SHADOW)" or "", b.pend,
            #divineKills, mhp(m), tostring(alive(m))))
          H.assertEq(b.atk, shadowSlot * 2,
            "isolation arm: SHADOW's own hit broke the bitted body")
          H.assertEq(b.pend, 3, "isolation arm: on an action boosted with all three points (the gate open)")
          H.assertEq(#divineKills, 0,
            "a bitted body is NOT assassinated on its break: the breaking "
            .. "hit fired no in-proc Death mark")
        else
          H.log(string.format("[isolation arm] body %d went (hp=%d, "
            .. "interceptor=%d, battle=%s) before Shadow broke it -- another",
            m, mhp(m), counters, tostring(H.battleLoadStarted())))
        end
      end),
      -- a fight whose bitted body went unbroken is fought to its end (the
      -- spoils pressed out) before the next one is drawn: nextFight only
      -- draws once the battle is over, and the bodies still standing here
      -- carry no bit.  Whatever this tail does to the ledger or the flag,
      -- the next fight is a fresh battle and resets both.
      H.cond(function() return not broke and H.battleLoadStarted() end, {
        H.call(function() forced = nil end),
        drive(function() return not H.battleLoadStarted() end, 30000,
          "the isolation arm's unbroken fight is fought out"),
        H.call(function()
          H.log(string.format("[isolation arm] fight %d fought out: hpDrops=%d "
            .. "interceptor=%d divineKills=%d (a body without the bit)", fights,
            hpDrops, counters, #divineKills))
          watching = false
        end),
      }, {}),
      -- the hook point half, when the body outlived its doubled break: Shadow's
      -- next landed hit on the Broken 'boss' draws no mark either
      H.cond(function()
        return broke and alive(H.vars.bossBody) and H.battleLoadStarted()
      end, {
        H.call(function() H.vars.hookReads0 = #hookReads end),
        drive(function()
          local m = H.vars.bossBody
          for i = H.vars.hookReads0 + 1, #hookReads do
            if hookReads[i].y == ent(m) then return true end
          end
          return not alive(m) or brk(m) == 0 or not H.battleLoadStarted()
        end, 30000, "Shadow's next attack on the Broken 'boss' reaches the hook point (isolation arm)"),
        H.waitFrames(8),
        H.call(function()
          local m, read = H.vars.bossBody, nil
          for i = H.vars.hookReads0 + 1, #hookReads do
            if hookReads[i].y == ent(m) then read = hookReads[i] end
          end
          H.log(string.format("[isolation arm] hook point half: %s divineKills=%d "
            .. "hp=%d alive=%s broken=%02x", read and string.format(
            "the hook point read it Broken at f%d seq%d (SHADOW pending %d);", read.f, read.seq, read.pend) or
            "NOT reached;", #divineKills, mhp(m), tostring(alive(m)), brk(m)))
          if read then
            H.assertEq(read.pend, 3, "the hook point read it on a 3-BP action (the gate open)")
            H.assertEq(#divineKills, 0,
              "a Broken BOSS is never assassinated: the hook point's gate fired no "
              .. "in-proc Death mark")
            H.vars.siteHalf = true
          end
        end),
      }, {}),
    }
    return H.repeatN(1, {
      H.repeatN(FIGHTS, {
        H.cond(function() return not broke end, pass, {}),
      }),
      H.call(function()
        H.assertEq(broke, true, string.format(
          "Shadow broke a body carrying the boss bit within %d fight(s) "
          .. "(fought %d)", FIGHTS, fights))
        H.log(string.format("[isolation arm] done: fights=%d hook point half %s "
          .. "divineKills=%d interceptor=%d", fights,
          H.vars.siteHalf and "reached" or "NOT reached", #divineKills, counters))
        H.assertEq(H.vars.siteHalf == true, true, "the hook point half was reached: "
          .. "Shadow's attack put the Broken 'boss' to the gate from the hook point (#296)")
        H.assertEq(#divineKills, 0, "no in-proc Death mark in the whole arm")
        watching = false
        H.screenshot("assassinate_boss")
      end),
    })
  end)(),
})

H.run({ maxFrames = 300000 }, steps)
