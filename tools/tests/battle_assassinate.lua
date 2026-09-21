-- @suite slow savestate=camp_escaped
-- battle_assassinate.lua -- Shadow's divine: the hit that breaks a non-boss
-- kills it.
--
--   tools/tests/run.sh tools/tests/battle_assassinate.lua
--
-- The rule (#239, owner ruling 2026-09-21).  When Shadow's own hit breaks a
-- non-boss body, the divine kills it on that hit; a hit of his on a body
-- already Broken kills it too.  Once per battle (OT6_DIVINE_USED $3ecb,
-- Shadow's entity bit), never a boss ($3aa1 bit 2, the instant-death
-- protection ScimitarEffect reads).
--
-- Where the kill lives, against the action's order in battle_main.asm.
-- ExecAttack -> CalcAttackEffect: ChooseTarget, then Ot6Oblivion and
-- Ot6Assassinate (the seam: before the hit roll, the primary target's
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
-- Ot6BrokenDmg), and the divine used to resolve at the seam only, before
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
--   1. the breaking hit: Shadow's Fight empties a PIERCE-weak non-boss
--      body's last shield.  On that hit the ROM's chip path writes
--      OT6_BROKEN_TICKS for the body with x = Shadow's entity offset; the
--      in-proc $3dd4 Death mark inside Ot6AssassinateGate follows in the
--      same frame with a later sequence number; the body's HP write and its
--      Death status come after that; and the latch is set.
--   2. once per battle: the same battle continues, Shadow breaks or strikes
--      further bodies, monster HP keeps falling (hpDrops, the loud control),
--      and no second in-proc mark comes; the latch byte never changes again.
--   3. the boss check: no boss shares a battle with Shadow anywhere in the
--      generated tree, so the negative is an isolation arm.  A fresh battle
--      (fresh latch), a PIERCE-weak body given $3aa1.2 -- the bit a boss
--      carries -- before any chip (this file's one write), then Shadow
--      breaks it by real chips: the break write comes, no mark, no latch
--      spent.  When the body outlives its doubled break, his next landed hit
--      on it (the seam's Broken read) draws no mark either.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD, ST_DEF, ST_TGT = 0x01, 0x05, 0x27, 0x38
local DIVINE_USED = 0x3ECB
local SHADOW = 0x03
local OT6_PIERCE = 0x02
local BREAK_TICKS = 0x10   -- OT6_BREAK_TICKS (ot6_break.asm:1): the value
                           -- the "shields down: break" store writes; the
                           -- timer's own ticks write less
local FIGHTS = 6

local function ent(m) return 8 + m * 2 end
local function brk(m) return H.readByte(0x3E88 + ent(m)) end
local function sh(m) return H.readByte(0x3E38 + ent(m)) end
local function weak(m) return H.readByte(0x3E9C + ent(m)) end
local function aa1(m) return H.readByte(0x3AA1 + ent(m)) end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return H.readByte(0x3AA8 + m * 2) % 2 == 1 end
local function alive(m) return present(m) and mhp(m) > 0 end
local function dead(m) return H.readByte(0x3EE4 + ent(m)) & 0x80 ~= 0 end
local function latchByte() return H.readByte(DIVINE_USED) end

local shadowSlot, msPresent = nil, {}
local function shadowBit() return 1 << shadowSlot end

-- ---- the ledger: the ROM's writes, in the ROM's order -------------------
-- One sequence counter across every callback below, so two writes in the
-- same frame still say which came first.
local GATE, SEAM = H.sym("Ot6AssassinateGate"), H.sym("Ot6Assassinate")
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
-- which rule fired: the seam, on a later swing of one multi-swing action,
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
local jsrHit, jsrSeam = findJsr(HITJOIN, HITJOIN + 0x10), findJsr(SEAM, SEAM + 0x20)
H.log(string.format("[gate] Ot6AssassinateGate $%06x; jsr in Ot6HitJoin: %s; "
  .. "jsr in Ot6Assassinate (seam): %s", GATE,
  jsrHit and string.format("$%06x", jsrHit) or "NONE (the chip-path hook is not there)",
  jsrSeam and string.format("$%06x", jsrSeam) or "NONE"))
local gateVia = nil
emu.addMemoryCallback(function()
  if not watching then return end
  pcall(function()
    local sp = emu.getState()["cpu.sp"] & 0xFFFF
    local ret = H.readWord(sp + 1)
    if jsrHit and ret == ((jsrHit + 2) & 0xFFFF) then gateVia = "Ot6HitJoin"
    elseif jsrSeam and ret == ((jsrSeam + 2) & 0xFFFF) then gateVia = "seam"
    else gateVia = string.format("$%04x", ret) end
  end)
end, emu.callbackType.exec, GATE, GATE)
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  pcall(function()
    local pc = cpu()
    if pc >= GATE and pc < SEAM then
      local m = ((addr - 0x7E0000 - 0x3DD4) - 8) // 2
      local k = { m = m, f = H.frame, seq = stamp(), pc = pc, via = gateVia }
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
    brokeAt[m] = { f = H.frame, seq = stamp(), atk = atk, pc = pc }
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
      .. "broken=%d ic=%d kills=%d latch=$%02x tgt=%s %s", H.frame,
      H.readByte(MENU), H.readByte(ACTOR) & 3, H.readByte(MSTATE), hpDrops,
      brokenHits, counters, #divineKills, latchByte(), tostring(pickTarget()),
      table.concat(parts, " ")))
  end
  if H.readByte(MENU) == 0 then
    -- no window up: an animation, or the spoils.  battleLoadStarted()
    -- reads true through the victory boxes and A alone advances them
    -- (M.fleeBattle's finding), so a fight nobody stands in is pressed out.
    if #H.stageSlots() == 0 then
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
    local cur = H.readByte(0x890F + shadowSlot) & 3
    btn = (cur == 0) and "a" or "up"   -- Fight is row 0
    if not edge then btn = nil end
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
  local ph = 0
  local pattern = { "down", "down", "left", "left", "up", "up",
                    "right", "right" }
  return {
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 4000, "world control (draw " .. n .. ")", 5),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        ph = ph + 1
        local dir = pattern[(math.floor(ph / 25) % #pattern) + 1]
        H.setPad({ [dir] = true })
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
      H.fleeBattle(9000),
      H.waitFrames(30),
    }, {}),
  }
end
local function encounter(tag)
  local steps = { H.call(function() H.vars.suitable = false end) }
  for n = 1, 6 do
    local w = walkSteps(n)
    if n == 1 then
      for _, s in ipairs(w) do steps[#steps + 1] = s end
    else
      steps[#steps + 1] = H.cond(function() return not H.vars.suitable end, w, {})
    end
  end
  steps[#steps + 1] = H.call(function()
    H.assertEq(H.vars.suitable, true, tag .. ": the pool dealt two PIERCE-weak "
      .. "shielded bodies among three or more within six draws")
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == SHADOW then shadowSlot = s end
    end
    H.assertEq(shadowSlot ~= nil, true, tag .. ": SHADOW is really here")
    H.assertEq(latchByte() & shadowBit(), 0,
      tag .. ": Shadow's divine latch clear at battle start")
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
  -- his chips (arm 2's second break, arm 3's seam half).
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row" }),
})

-- ===================== battle 1: arms 1 and 2 ==============================
-- arm 1: the breaking hit.  A fight Interceptor empties before Shadow
-- breaks anything is pressed out and the next one is taken, up to FIGHTS
-- of them; the arm asserts the divine fired within them, with the ledger
-- of every fight in the log.
add({
  (function()
    local fights = 0
    local fight = {
      nextFight("battle 1"),
      H.call(function()
        fights = fights + 1
        H.log(string.format("[arm 1] fight %d of up to %d", fights, FIGHTS))
      end),
      drive(function()
        return #divineKills >= 1 or not H.battleLoadStarted()
      end, 30000, "Shadow's hit breaks a body and the divine kills it"),
      H.call(function()
        if #divineKills == 0 then
          H.log(string.format("[arm 1] fight %d ended with no divine: "
            .. "hpDrops=%d brokenHits=%d interceptor=%d -- the next encounter",
            fights, hpDrops, brokenHits, counters))
        end
      end),
    }
    return H.repeatN(1, {
      H.repeatN(FIGHTS, {
        H.cond(function() return #divineKills == 0 end, fight, {}),
      }),
      H.call(function()
        H.assertEq(#divineKills >= 1, true, string.format(
          "the divine fired within %d fight(s) (fought %d; this fight's "
          .. "hpDrops=%d)", FIGHTS, fights, hpDrops))
      end),
    })
  end)(),
  -- the mark's action finishes (ApplyDmg, UpdateStatus) inside the same
  -- main-loop pass; a few frames let the ledger's HP and Death entries land
  -- before they are read
  H.waitFrames(8),
  H.call(function()
    local k = divineKills[1]
    local b = brokeAt[k.m]
    H.log(string.format("divine kill: body %d marked at f%d seq%d; break %s; "
      .. "hp write %s; death %s; latch=$%02x hp=%d dead=%s hpDrops=%d "
      .. "interceptor=%d", k.m, k.f, k.seq,
      b and string.format("f%d seq%d x=$%02x", b.f, b.seq, b.atk) or "none",
      hpWrite[k.m] and string.format("f%d seq%d", hpWrite[k.m].f, hpWrite[k.m].seq) or "none",
      deathAt[k.m] and string.format("f%d seq%d", deathAt[k.m].f, deathAt[k.m].seq) or "none",
      latchByte(), mhp(k.m), tostring(dead(k.m)), hpDrops, counters))
    H.assertEq(b ~= nil, true,
      "the ROM's own chip path broke the body (a nonzero OT6_BROKEN_TICKS "
      .. "store) -- the gauge was chipped by real play, not painted on")
    H.assertEq(b.atk, shadowSlot * 2,
      "the break store's attacker (cpu x at the store) is SHADOW: his own "
      .. "hit broke it")
    H.assertEq(b.f == k.f and b.seq < k.seq, true, string.format(
      "the break write precedes the Death mark on the SAME action: break "
      .. "f%d seq%d, mark f%d seq%d", b.f, b.seq, k.f, k.seq))
    H.assertEq(k.via, "Ot6HitJoin",
      "the mark came through Ot6HitJoin, the chip path of the hit that "
      .. "broke the body -- not the seam on a later swing (the pre-#239 "
      .. "rule, which a multi-swing action can still reach)")
    H.assertEq(hpWrite[k.m] ~= nil and hpWrite[k.m].f == k.f
      and hpWrite[k.m].seq > k.seq, true,
      "the mark precedes the hit's HP write (ApplyDmg), same frame")
    H.assertEq(deathAt[k.m] ~= nil and deathAt[k.m].f == k.f
      and deathAt[k.m].seq > hpWrite[k.m].seq, true,
      "and UpdateStatus applied the Death after the HP write, same frame: "
      .. "the breaking hit and the kill are one action")
    H.assertEq(dead(k.m), true, "the body is dead")
    H.assertEq(latchByte() & shadowBit() ~= 0, true,
      "Shadow's once-per-battle latch is SET by the kill")
    H.vars.latchAfterKill = latchByte()
    H.vars.brokenHits0 = brokenHits
    H.vars.hpDrops0 = hpDrops
    H.vars.killSeq = k.seq
    H.screenshot("assassinate_kill")
  end),
  -- arm 2: the battle continues; more breaks, more landed hits, no 2nd spend
  drive(function()
    -- done when Shadow (or anyone) broke another body, a hit landed on a
    -- live-Broken body, a second mark came (the failure, caught below), or
    -- the battle ended
    if #divineKills >= 2 then return true end
    if breaksAfter(H.vars.killSeq) >= 1 then return true end
    if brokenHits > H.vars.brokenHits0 then return true end
    return not H.battleLoadStarted()
  end, 30000, "the once-per-battle window rides out"),
  H.call(function()
    local later = {}
    for m, b in pairs(brokeAt) do
      if b.seq > H.vars.killSeq then
        later[#later + 1] = string.format("body %d f%d x=$%02x%s", m, b.f,
          b.atk, b.atk == shadowSlot * 2 and " (SHADOW)" or "")
      end
    end
    H.log(string.format("after the kill: divineKills=%d latch=$%02x "
      .. "hpDrops=%d (was %d) brokenHits=%d (was %d) interceptor=%d "
      .. "later breaks: %s", #divineKills, latchByte(), hpDrops,
      H.vars.hpDrops0, brokenHits, H.vars.brokenHits0, counters,
      #later > 0 and table.concat(later, ", ") or "none"))
    H.assertEq(#divineKills, 1,
      "ONCE PER BATTLE: the divine's in-proc Death mark happened exactly "
      .. "once, though hits kept landing (hpDrops is the loud control)")
    H.assertEq(hpDrops > H.vars.hpDrops0, true, string.format(
      "loud control: monster HP kept falling after the kill (%d drops, "
      .. "was %d at the kill)", hpDrops, H.vars.hpDrops0))
    if H.battleLoadStarted() then
      H.assertEq(latchByte(), H.vars.latchAfterKill,
        "and the latch byte never changed again")
    end
    watching = false
  end),
})

-- ============== battle 3: the labeled isolation arm ========================
-- The boss check, with the one injected bit; see the header.  A fresh
-- battle (fresh latch), the PIERCE-weak body with the most HP given
-- $3aa1.2 before any chip, then Shadow's chips break it: the break write
-- comes with no in-proc Death mark and no latch spend.  The write below is
-- this file's only one and may never produce fixtures.  A bitted body
-- Interceptor kills before Shadow breaks it, or a fight that empties
-- first, is followed by another fight, up to FIGHTS of them.
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
        H.assertEq(latchByte() & shadowBit(), 0, "isolation arm: latch clear "
          .. "(the gate reads in order shadow -> latch -> target -> broken -> "
          .. "boss, so an unspent latch is what routes execution to the boss "
          .. "check)")
        local best, bh = nil, nil
        for _, m in ipairs(msPresent) do
          if alive(m) and (weak(m) & OT6_PIERCE) ~= 0 and sh(m) > 0
            and (best == nil or mhp(m) > bh) then best, bh = m, mhp(m) end
        end
        H.vars.bossBody = best
        H.writeByte(0x3AA1 + ent(best), aa1(best) | 0x04)   -- the arm's one write (header)
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
            .. "x=$%02x%s: divineKills=%d latch=$%02x hp=%d alive=%s", m, b.f,
            b.seq, b.atk, b.atk == shadowSlot * 2 and " (SHADOW)" or "",
            #divineKills, latchByte(), mhp(m), tostring(alive(m))))
          H.assertEq(b.atk, shadowSlot * 2,
            "isolation arm: SHADOW's own hit broke the bitted body")
          H.assertEq(#divineKills, 0,
            "a bitted body is NOT assassinated on its break: the breaking "
            .. "hit fired no in-proc Death mark")
          H.assertEq(latchByte() & shadowBit(), 0,
            "and no divine was spent on it")
        else
          H.log(string.format("[isolation arm] body %d went (hp=%d, "
            .. "interceptor=%d, battle=%s) before Shadow broke it -- another",
            m, mhp(m), counters, tostring(H.battleLoadStarted())))
        end
      end),
      -- the seam half, when the body outlived its doubled break: Shadow's
      -- next landed hit on the Broken 'boss' draws no mark either
      H.cond(function()
        return broke and alive(H.vars.bossBody) and H.battleLoadStarted()
      end, {
        H.call(function() H.vars.brokenHits0 = brokenHits end),
        drive(function()
          return brokenHits > H.vars.brokenHits0 or not alive(H.vars.bossBody)
            or not H.battleLoadStarted()
        end, 30000, "Shadow lands on the Broken 'boss' (isolation arm)"),
        H.call(function()
          H.log(string.format("[isolation arm] seam half: brokenHits=%d (was "
            .. "%d) divineKills=%d latch=$%02x hp=%d alive=%s", brokenHits,
            H.vars.brokenHits0, #divineKills, latchByte(),
            mhp(H.vars.bossBody), tostring(alive(H.vars.bossBody))))
          if brokenHits > H.vars.brokenHits0 then
            H.assertEq(#divineKills, 0,
              "a Broken BOSS is never assassinated: the landed hit fired no "
              .. "in-proc Death mark")
            H.assertEq(latchByte() & shadowBit(), 0,
              "and no divine was spent on it")
            H.vars.seamHalf = true
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
        H.log(string.format("[isolation arm] done: fights=%d seam half %s "
          .. "divineKills=%d latch=$%02x interceptor=%d", fights,
          H.vars.seamHalf and "reached" or "not reached (the body died on "
          .. "its doubled break)", #divineKills, latchByte(), counters))
        H.assertEq(#divineKills, 0, "no in-proc Death mark in the whole arm")
        watching = false
        H.screenshot("assassinate_boss")
      end),
    })
  end)(),
})

H.run({ maxFrames = 300000 }, steps)
