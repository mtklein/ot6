-- @manual isolation instrument for Shadow's assassinate divine; becomes a @suite member when a boss+Shadow entry fixture exists (see header)
-- battle_assassinate.lua -- Shadow's divine: instant-kill a Broken non-boss.
--
--   tools/tests/run.sh tools/tests/battle_assassinate.lua
--
-- Status: evidence scaffold, not in suite.sh (unchanged by the #75
-- conversion; promoting it is a separate decision).
--
-- Ot6Assassinate (ot6_divine.asm:174) is hooked at the same seam Oblivion
-- uses, just after ChooseTarget in CalcAttackEffect, and fires when
-- SHADOW (char id $03) lands an attack on a Broken (OT6_BROKEN_TICKS $3e88
-- nonzero) non-boss ($3aa1 bit 2 clear) while his once-per-battle divine
-- (OT6_DIVINE_USED, $3ecb) is unspent.  It marks Death in the target's
-- $3dd4 and spends the latch.
--
-- Issue #75 conversion: a real Shadow, and the break is earned.  The old
-- scaffold installed CHAR::SHADOW into every slot of the entry-point
-- fixture, forged command rows, pinned guard HP to $F000, and wrote the
-- Broken and boss states directly.
-- It now boots camp_escaped, the input-driven post-Magitek savestate at
-- world (179,71), party SABIN + SHADOW + CYAN, with Shadow's own record
-- carrying Fight and his Imperial ($25, PIERCE per Ot6WeapClassTbl), and walks
-- into the real local pool (measured 2026-08-10: species $2f 243hp
-- PIERCE-weak x3, and $29+$18 SLASH-weak mixes, all 3 shields, none
-- death-protected).  Draws without at least two PIERCE-weak 200+hp bodies are
-- fled; on a suitable draw Shadow chips a real gauge to Broken
-- with his own weapon class while the bench answers its menus with real
-- Defends (slotsboot's idiom; they deal no damage, so every monster HP drop
-- is Shadow's).
--
-- The observation is read-only and mechanism-exact: a pc-gated write watch on
-- the monster $3dd4 cells counts Death marks written from inside
-- Ot6Assassinate (the divine's own kill), and the $3ecb latch byte is
-- read.  That replaces the old check on whether the guard's wound bit set,
-- which a plain 4x-broken damage kill would also satisfy, since 243hp bodies
-- die to plain damage too.
--
--   1. Broken non-boss: Shadow chips a body to Broken, and his next landed
--      attack on it divine-kills, giving exactly one in-proc Death mark on a
--      body whose Broken state was live, with the latch set.
--   2. once per battle: the same battle continues, Shadow breaks
--      and strikes further bodies, and monster HP keeps falling (the control
--      showing he still acts and lands), yet the in-proc kill count
--      stays 1 and the latch byte never changes again.
--
-- One labeled isolation arm (issue #75); one write site stays.
-- 3. the boss check.  No boss shares a battle with Shadow anywhere
--    in the generated tree (the camp pursuit is four troops; the Ghost Train
--    boss has no entry-point fixture; the local pool carries no $3aa1.2
--    species, measured), so the non-boss check's negative is an isolation
--    arm: a fresh battle, a body chipped Broken by real play, then the one
--    write, setting its $3aa1 bit 2, the bit a boss carries
--    (ScimitarEffect reads the same bit, battle_main.asm:9147), and
--    Shadow's next landed hit on it must fire no divine and spend no
--    latch.  It must never produce fixtures; it converts organically when
--    a chain step generates a boss-with-Shadow entry point.  This is the file's
--    only surviving write (.writeByte( waiver line).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT = 0x05, 0x38
local DIVINE_USED = 0x3ECB
local SHADOW = 0x03
local OT6_PIERCE = 0x02

local function ent(m) return 8 + m * 2 end
local function brk(m) return H.readByte(0x3E88 + ent(m)) end
local function sh(m) return H.readByte(0x3E38 + ent(m)) end
local function weak(m) return H.readByte(0x3E9C + ent(m)) end
local function aa1(m) return H.readByte(0x3AA1 + ent(m)) end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return H.readByte(0x3AA8 + m * 2) % 2 == 1 end
local function latchByte() return H.readByte(DIVINE_USED) end

local shadowSlot, msPresent = nil, {}

-- ---- the in-proc kill watch: Death marks written by the divine ----------
local ASSN = H.sym("Ot6Assassinate")
local divineKills = {}          -- { m = body, brkAtKill = its last-seen brk }
local lastBrk, lastHp = {}, {}
local watching = false
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  pcall(function()
    local s = emu.getState()
    local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
    if pc >= ASSN and pc < ASSN + 0x60 then
      local m = ((addr - 0x7E0000 - 0x3DD4) - 8) // 2
      divineKills[#divineKills + 1] = { m = m, brkAtKill = lastBrk[m] }
    end
  end)
end, emu.callbackType.write, 0x7E3DD4 + 8, 0x7E3DD4 + 0x13)

-- monster HP drops attributed per body (bench Defends, so every drop is
-- Shadow's); brokenHits counts drops on a body whose Broken state was live
local hpDrops, brokenHits = 0, 0
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

-- ---- the action driver: SHADOW Fights, the bench Defends ---------------
local mf, hb = 0, -1200
local function fightPulse()
  scanBodies()
  if H.frame - hb >= 600 then
    hb = H.frame
    local parts = {}
    for _, m in ipairs(msPresent) do
      parts[#parts + 1] = string.format("m%d:%d/sh%d", m, mhp(m), sh(m))
    end
    H.log(string.format("[pulse f%d] menu=%02x act=%d st=%02x drops=%d "
      .. "cur=%d %s", H.frame, H.readByte(MENU), H.readByte(ACTOR) & 3,
      H.readByte(MSTATE), hpDrops,
      H.readByte(0x890F + (H.readByte(ACTOR) & 3)) & 3,
      table.concat(parts, " ")))
  end
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  local step = mf % 40
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if act ~= shadowSlot then
    -- a real Defend: right swaps Fight->Def, then A (slotsboot's idiom)
    if st ~= ST_CMD then H.setPad(step < 4 and { b = true } or {}); return end
    if step < 4 then H.setPad({ right = true })
    elseif step >= 20 and step < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  if (mf - 1) % 10 >= 5 then H.setPad({}); return end
  local btn
  if st == ST_CMD then
    local cur = H.readByte(0x890F + shadowSlot) & 3
    btn = (cur == 0) and "a" or (cur < 4 and "up" or nil)   -- Fight is row 0
  elseif st == ST_TGT then
    btn = "a"                       -- default monster target
  elseif st == 0x01 then
    btn = nil   -- #90: NOTHING in transitional $01 -- an A held here is
                -- still down when the command window goes live and
                -- confirms row 0 (the battle_levelup race)
  else
    btn = "b"   -- #90: B in unrecognised states -- advances messages,
                -- confirms nothing
  end
  H.setPad(btn and { [btn] = true } or {})
end

-- ---- encounter selection: >= 2 PIERCE-weak 200+hp bodies, else flee -----
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
      local good = 0
      for _, m in ipairs(msPresent) do
        if (weak(m) & OT6_PIERCE) ~= 0 and mhp(m) >= 200 then good = good + 1 end
      end
      H.vars.suitable = good >= 2
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
    H.assertEq(H.vars.suitable, true,
      tag .. ": the pool dealt a suitable formation within six draws")
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == SHADOW then shadowSlot = s end
    end
    H.assertEq(shadowSlot ~= nil, true, tag .. ": SHADOW is really here")
    lastBrk, lastHp = {}, {}
    hpDrops, brokenHits = 0, 0
    divineKills = {}
    mf = 0
    scanBodies()
    watching = true
  end)
  return steps
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  -- SHADOW to the back row, through the real Order screen (H.setRows).
  -- Measured: his front-row Fight lands ~110 on a shielded 243-hp body, so
  -- a 3-shield gauge (chips are -1 per landed weak-class hit) damage-kills
  -- at shield 1 and nothing ever breaks.  The back row halves his physical
  -- damage (~55): three chips leave the body alive at ~78 hp, Broken, and
  -- the fourth hit is the divine's.  A player picking a smaller stick is
  -- play, not staging.
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row" }),
})

-- ===================== battle 1: arms 1 and 2 ==============================
add(encounter("battle 1"))
add({
  H.call(function()
    H.assertEq(latchByte(), 0, "divine latch clear at battle start")
    for _, m in ipairs(msPresent) do
      H.assertEq(aa1(m) & 0x04, 0, string.format(
        "body %d is a non-boss (no $3aa1.2) -- the pool precondition", m))
    end
  end),
  -- arm 1: chip to Broken and let the next landed hit assassinate.  The
  -- drive also exits on battle end, so a fight that damage-kills everything
  -- before a break fails on the assert below with the ledger in the log
  -- rather than on a silent timeout.
  H.driveUntil(function()
    return #divineKills >= 1 or not H.battleLoadStarted()
  end, 30000, { H.call(fightPulse), H.waitFrames(2) },
    "Shadow chips a gauge to Broken and his divine kills it"),
  H.call(function()
    H.assertEq(#divineKills >= 1, true,
      "the divine fired before the battle ended (hpDrops=" .. hpDrops .. ")")
    local k = divineKills[1]
    H.log(string.format("divine kill: body %d, brk-at-kill=%02x, latch=$%02x, "
      .. "hpDrops=%d", k.m, k.brkAtKill or 0, latchByte(), hpDrops))
    H.assertEq((k.brkAtKill or 0) ~= 0, true,
      "the divine fired on a body whose BROKEN state was live -- the gauge "
      .. "was chipped by real play, not painted on")
    H.assertEq(latchByte() ~= 0, true,
      "Shadow's once-per-battle latch is SET by the kill")
    H.vars.latchAfterKill = latchByte()
    H.vars.brokenHits0 = brokenHits
    H.screenshot("assassinate_kill")
  end),
  -- arm 2: the battle continues; more breaks, more landed hits, no 2nd spend
  (function()
    local budget = 0
    return H.driveUntil(function()
      budget = budget + 1
      -- done when Shadow landed >= 1 more hit on a live-Broken body after
      -- the kill, or the battle ended (all bodies damage-killed)
      if brokenHits > H.vars.brokenHits0 then return true end
      return not H.battleLoadStarted()
    end, 30000, { H.call(fightPulse), H.waitFrames(2) },
      "the once-per-battle window rides out")
  end)(),
  H.call(function()
    H.log(string.format("after the kill: divineKills=%d latch=$%02x "
      .. "hpDrops=%d brokenHits=%d (was %d)", #divineKills, latchByte(),
      hpDrops, brokenHits, H.vars.brokenHits0))
    H.assertEq(#divineKills, 1,
      "ONCE PER BATTLE: the divine's in-proc Death mark happened exactly "
      .. "once, though Shadow kept landing (hpDrops is the loud control)")
    H.assertEq(hpDrops > 2, true,
      "loud control: Shadow's attacks really landed beyond the kill ("
      .. hpDrops .. " monster HP drops)")
    if H.battleLoadStarted() then
      H.assertEq(latchByte(), H.vars.latchAfterKill,
        "and the latch byte never changed again")
    end
    watching = false
  end),
})

-- ============== battle 3: the labeled isolation arm (issue #75)
-- The boss check, with the one injected bit; see the header.  A fresh
-- battle (fresh latch), a body Broken by real chips, then $3aa1.2 is set on
-- it and Shadow's next landed hit must decline: no in-proc Death mark and no
-- latch spend.  The write below is this file's only one and may never
-- produce fixtures.
add({
  H.loadState(STATE),
  H.waitFrames(20),
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row (arm 3)" }),
})
add(encounter("isolation arm"))
add({
  H.call(function()
    H.assertEq(latchByte(), 0, "fresh battle: latch clear (the gate reads "
      .. "in order shadow -> latch -> broken -> boss, so an unspent latch "
      .. "is what routes execution to the boss check)")
    H.vars.bossBody = nil
  end),
  -- chip until some body is Broken.  The divine would fire on the first
  -- post-break hit, so the injection must land in the same frame the break is
  -- first seen.  The pulse's per-frame scan gives that window: inject as soon
  -- as brk != 0 and before the next landed hit resolves (hit resolution takes
  -- whole action rounds, so one frame is well inside it).
  H.driveUntil(function()
    for _, m in ipairs(msPresent) do
      if present(m) and brk(m) ~= 0 and mhp(m) > 0 then
        H.vars.bossBody = m
        return true
      end
    end
    return false
  end, 30000, { H.call(fightPulse), H.waitFrames(2) },
    "a body breaks by real chips (isolation arm)"),
  H.call(function()
    local m = H.vars.bossBody
    H.writeByte(0x3AA1 + ent(m), aa1(m) | 0x04)   -- the arm's one write (header)
    lastBrk, lastHp = {}, {}
    hpDrops, brokenHits = 0, 0
    divineKills = {}
    scanBodies()
    watching = true
    H.log(string.format("[isolation arm] body %d Broken by play; $3aa1.2 "
      .. "SET -- the bit a boss carries", m))
  end),
  H.driveUntil(function() return brokenHits >= 1 end, 30000,
    { H.call(fightPulse), H.waitFrames(2) },
    "Shadow lands on the Broken 'boss' (isolation arm)"),
  H.call(function()
    H.log(string.format("[isolation arm] brokenHits=%d divineKills=%d "
      .. "latch=$%02x", brokenHits, #divineKills, latchByte()))
    H.assertEq(#divineKills, 0,
      "a Broken BOSS is never assassinated: the landed hit fired no "
      .. "in-proc Death mark")
    H.assertEq(latchByte(), 0, "and no divine was spent on it")
    watching = false
    H.screenshot("assassinate_boss")
  end),
})

H.run({ maxFrames = 300000 }, steps)
