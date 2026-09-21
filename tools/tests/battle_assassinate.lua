-- @manual isolation instrument for Shadow's assassinate divine; becomes a @suite member when a boss+Shadow entry fixture exists (see header)
-- battle_assassinate.lua -- Shadow's divine: instant-kill a Broken non-boss.
--
--   tools/tests/run.sh tools/tests/battle_assassinate.lua
--
-- Status: evidence scaffold, not in suite.sh.
--
-- Ot6Assassinate (ot6_divine.asm:174) is hooked at the same seam Oblivion
-- uses, just after ChooseTarget in CalcAttackEffect, and fires when
-- SHADOW (char id $03) lands an attack on a Broken (OT6_BROKEN_TICKS $3e88
-- nonzero) non-boss ($3aa1 bit 2 clear) while his once-per-battle divine
-- (OT6_DIVINE_USED, $3ecb) is unspent.  It marks Death in the target's
-- $3dd4 and spends the latch.
--
-- Boots camp_escaped, the input-driven post-Magitek savestate at world
-- (179,71), party SABIN + SHADOW + CYAN, with Shadow's own record carrying
-- Fight and his Imperial ($25, PIERCE per Ot6WeapClassTbl), and walks into
-- the real local pool.  On a suitable draw (below) Shadow Fights the
-- PIERCE-weak body his chips are furthest along on (the target cursor
-- steered, not left at its default) while the bench answers its windows
-- with real Defends: Right opens the Def. window (btlgfx
-- UpdateMenuState_27, state $27), A takes it.
--
-- WHAT A SUITABLE DRAW IS, and why the floor is BODY_HP.  The breaking hit
-- is not attenuated and is doubled (ot6_break.asm, Ot6ShieldedMulW: "the
-- breaking hit itself is not attenuated: both chip procs run before this
-- tail ... and Ot6BrokenDmg doubles it instead"), and Ot6Assassinate runs
-- at ChooseTarget, before that hit's chip, so the divine can only take a
-- body that is still standing AFTER its own break.  Measured with the
-- back-row Imperial (build/attempts/wt/harness-faults/lab/harness-faults/repro/assassinate_fixed_s0.log):
-- a shielded chip reads 243->197->151 (~46) and the breaking hit "149"
-- (frames/f7552.png) to ~184, so a body needs more than two chips plus
-- the doubled hit, ~280 hp, and every PIERCE-weak body this pool deals
-- (CrassHoppr, 243) died on its own break in four fights running -- the
-- one divine in five fights came off a berserked Shadow's #236 pip dump,
-- a multi-swing action that broke and killed inside one frame, which is
-- luck, not the property.  Boost buys a Fight extra swings, not damage
-- (Ot6BoostDmg: "$00 fight: boost = extra swings"), each swing chips once
-- and its breaking swing is the same doubled hit, so no pip count changes
-- the floor; and the camp_escaped bag holds no weaker dagger.  So the
-- draw asks for at least two PIERCE-weak bodies of BODY_HP or more and
-- flees the rest, and a pool that never deals one fails here, at the
-- precondition, saying so.
--
-- What else the pool did to the old drive, measured (#239,
-- build/attempts/wt/harness-faults/lab/harness-faults/repro/assassinate_s0.log): the bench drive read
-- $27 as an unknown state and pressed B in it, so SABIN sat at
-- "Fight/Def." for 1200 frames (frames/f1152.png) and Shadow's turn waited
-- behind him; Interceptor is in the party with Shadow (vanilla:
-- battle_main.asm @4cd6, a monster's physical on Shadow is blocked and
-- countered half the time with Takedown/Wild Fang, $fc/$fd), whose
-- counters kill these bodies outright ("418" on the 290-hp Stray Cat,
-- frames/f1408.png); every body was dead by f3492 with nothing Broken, the
-- victory boxes came up (attempt1_timeout_f30492.png, "Got 218 Exp.
-- point(s)"), and the drive -- which released the pad with no window up,
-- while battleLoadStarted() reads true through the spoils -- idled its
-- whole 30000-frame budget there.  So the ledger names Interceptor's
-- counters (a $3a7b write watch), a fight that ends without the property
-- is pressed out of its spoils and the next encounter is taken, up to
-- FIGHTS of them, and the arm asserts the property was reached within
-- them.  Nothing about the divine itself is assumed: the kill is the
-- pc-gated $3dd4 write from inside Ot6Assassinate, and the break behind it
-- is the ROM's own first nonzero write to that body's OT6_BROKEN_TICKS,
-- not a frame-earlier HP or shield reading.
--
--   1. Broken non-boss: Shadow chips a body to Broken, and his next landed
--      attack on it divine-kills, giving exactly one in-proc Death mark on a
--      body whose Broken state was live, with the latch set.
--   2. once per battle: the same battle continues, Shadow breaks
--      and strikes further bodies, and monster HP keeps falling (the control
--      showing he still acts and lands), yet the in-proc kill count
--      stays 1 and the latch byte never changes again.
--   3. the boss check: no boss shares a battle with Shadow anywhere in the
--      generated tree, so the non-boss check's negative is an isolation
--      arm: a fresh battle, a body chipped Broken by real play, then one
--      write sets its $3aa1 bit 2, the bit a boss carries (ScimitarEffect
--      reads the same bit, battle_main.asm:9147), and Shadow's next landed
--      hit on it must fire no divine and spend no latch.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD, ST_DEF, ST_TGT = 0x01, 0x05, 0x27, 0x38
local DIVINE_USED = 0x3ECB
local SHADOW = 0x03
local OT6_PIERCE = 0x02
local FIGHTS = 6
local BODY_HP = 280   -- see the header: two shielded chips and the doubled break

local function ent(m) return 8 + m * 2 end
local function brk(m) return H.readByte(0x3E88 + ent(m)) end
local function sh(m) return H.readByte(0x3E38 + ent(m)) end
local function weak(m) return H.readByte(0x3E9C + ent(m)) end
local function aa1(m) return H.readByte(0x3AA1 + ent(m)) end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return H.readByte(0x3AA8 + m * 2) % 2 == 1 end
local function alive(m) return present(m) and mhp(m) > 0 end
local function latchByte() return H.readByte(DIVINE_USED) end

local shadowSlot, msPresent = nil, {}

-- ---- the in-proc kill watch: Death marks written by the divine ----------
local ASSN = H.sym("Ot6Assassinate")
local divineKills = {}   -- { m = body, f = frame, brokeAt = the body's break frame }
local lastBrk, lastHp = {}, {}
local brokeAt = {}       -- body -> frame of the ROM's first nonzero
                         -- OT6_BROKEN_TICKS write this ledger (the chip's
                         -- "shields down: break" store, ot6_break.asm)
local watching = false
emu.addMemoryCallback(function(addr, v)
  if not watching or (v & 0x80) == 0 then return end
  pcall(function()
    local s = emu.getState()
    local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
    if pc >= ASSN and pc < ASSN + 0x60 then
      local m = ((addr - 0x7E0000 - 0x3DD4) - 8) // 2
      divineKills[#divineKills + 1] = { m = m, f = H.frame, brokeAt = brokeAt[m] }
    end
  end)
end, emu.callbackType.write, 0x7E3DD4 + 8, 0x7E3DD4 + 0x13)
emu.addMemoryCallback(function(addr, v)
  if not watching or v == 0 then return end
  local m = ((addr - 0x7E0000 - 0x3E88) - 8) // 2
  if brokeAt[m] == nil then brokeAt[m] = H.frame end
end, emu.callbackType.write, 0x7E3E88 + 8, 0x7E3E88 + 0x13)

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
  lastBrk, lastHp, brokeAt = {}, {}, {}
  hpDrops, brokenHits, counters = 0, 0, 0
  divineKills = {}
  scanBodies()
  watching = true
end

-- ---- Shadow's target ------------------------------------------------------
-- The PIERCE-weak body his chips are furthest along on: a Broken one first
-- (the divine's), else the fewest shields, else the most HP (it has to
-- survive the chips).  nil when no PIERCE-weak body stands, which takes the
-- default.  `forced` names one body for the isolation arm.
local forced = nil
local function pickTarget()
  if forced ~= nil and alive(forced) then return forced end
  local best, bb, bs, bh = nil, nil, nil, nil
  for _, m in ipairs(msPresent) do
    if alive(m) and (weak(m) & OT6_PIERCE) ~= 0 then
      local b, s, h = brk(m) ~= 0, sh(m), mhp(m)
      local better = best == nil
        or (b and not bb)
        or (b == bb and s < bs)
        or (b == bb and s == bs and h > bh)
      if better then best, bb, bs, bh = m, b, s, h end
    end
  end
  return best
end

-- ---- the action driver: SHADOW Fights, the bench Defends, the spoils are
-- pressed out (one call per frame) ------------------------------------------
local T = H.targetCursor()
local mf, hb, aPhase = 0, -1200, 0
local function fightPulse()
  scanBodies()
  T.observe()
  if H.frame - hb >= 600 then
    hb = H.frame
    local parts = {}
    for _, m in ipairs(msPresent) do
      parts[#parts + 1] = string.format("m%d:%d/sh%d%s", m, mhp(m), sh(m),
        brk(m) ~= 0 and "B" or "")
    end
    H.log(string.format("[pulse f%d] menu=%02x act=%d st=%02x drops=%d "
      .. "broken=%d ic=%d tgt=%s %s", H.frame, H.readByte(MENU),
      H.readByte(ACTOR) & 3, H.readByte(MSTATE), hpDrops, brokenHits,
      counters, tostring(pickTarget()), table.concat(parts, " ")))
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
    -- repro/assassinate_fixed_s0.log f7314-7315).  A target window the
    -- bench never asked for is backed out of.
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
    -- H.targetCursor: "a" once the cursor sits on the wanted body, a
    -- direction to tap on the first half of its 16-frame cycle, nil while
    -- the tap settles; the tap itself is a 4-on/4-off edge
    btn = T.steer(pickTarget(), mf)
    if btn == "a" then
      if not edge then btn = nil end
    elseif btn ~= nil and (mf - 1) % 16 >= 4 then
      btn = nil
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
        if (weak(m) & OT6_PIERCE) ~= 0 and mhp(m) >= BODY_HP then good = good + 1 end
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
    H.assertEq(H.vars.suitable, true, string.format(
      "%s: the pool dealt two PIERCE-weak bodies of %d+ hp within six draws "
      .. "(bodies that survive their own break; see the header)", tag, BODY_HP))
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == SHADOW then shadowSlot = s end
    end
    H.assertEq(shadowSlot ~= nil, true, tag .. ": SHADOW is really here")
    H.assertEq(latchByte(), 0, tag .. ": divine latch clear at battle start")
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
  -- SHADOW to the back row, through the real Order screen (H.setRows). The
  -- back row halves his physical damage: three chips leave the body alive,
  -- Broken, and the fourth hit is the divine's.
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row" }),
})

-- ===================== battle 1: arms 1 and 2 ==============================
-- arm 1: chip to Broken and let the next landed hit assassinate.  A fight
-- Interceptor empties before a break is pressed out and the next one is
-- taken, up to FIGHTS of them; the arm asserts the divine fired within
-- them, with the ledger of every fight in the log.
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
      end, 30000, "Shadow chips a gauge to Broken and his divine kills it"),
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
  H.call(function()
    local k = divineKills[1]
    H.log(string.format("divine kill: body %d at f%d, broke at f%s, "
      .. "latch=$%02x, hpDrops=%d interceptor=%d", k.m, k.f,
      tostring(k.brokeAt), latchByte(), hpDrops, counters))
    H.assertEq(k.brokeAt ~= nil and k.brokeAt <= k.f, true,
      "the divine fired on a body the ROM's own chip path had broken -- "
      .. "the gauge was chipped by real play, not painted on")
    H.assertEq(latchByte() ~= 0, true,
      "Shadow's once-per-battle latch is SET by the kill")
    H.vars.latchAfterKill = latchByte()
    H.vars.brokenHits0 = brokenHits
    H.screenshot("assassinate_kill")
  end),
  -- arm 2: the battle continues; more breaks, more landed hits, no 2nd spend
  drive(function()
    -- done when a hit landed on a live-Broken body after the kill, or the
    -- battle ended (all bodies damage-killed)
    if brokenHits > H.vars.brokenHits0 then return true end
    return not H.battleLoadStarted()
  end, 30000, "the once-per-battle window rides out"),
  H.call(function()
    H.log(string.format("after the kill: divineKills=%d latch=$%02x "
      .. "hpDrops=%d brokenHits=%d (was %d) interceptor=%d", #divineKills,
      latchByte(), hpDrops, brokenHits, H.vars.brokenHits0, counters))
    H.assertEq(#divineKills, 1,
      "ONCE PER BATTLE: the divine's in-proc Death mark happened exactly "
      .. "once, though hits kept landing (hpDrops is the loud control)")
    H.assertEq(hpDrops > 2, true,
      "loud control: monster HP really kept falling beyond the kill ("
      .. hpDrops .. " monster HP drops)")
    if H.battleLoadStarted() then
      H.assertEq(latchByte(), H.vars.latchAfterKill,
        "and the latch byte never changed again")
    end
    watching = false
  end),
})

-- ============== battle 3: the labeled isolation arm ========================
-- The boss check, with the one injected bit; see the header.  A fresh
-- battle (fresh latch), a body Broken by real chips, then $3aa1.2 is set on
-- it and Shadow's next landed hit must decline: no in-proc Death mark and no
-- latch spend.  The write below is this file's only one and may never
-- produce fixtures.  A bitted body Interceptor kills before Shadow lands,
-- or a fight that empties before a break, is followed by another body or
-- another fight, up to FIGHTS of them.
add({
  H.loadState(STATE),
  H.waitFrames(20),
  H.setRows({ [SHADOW] = true }, { tag = "shadow back row (arm 3)" }),
  (function()
    local landed, fights = false, 0
    local pass = {
      nextFight("isolation arm"),
      H.call(function()
        fights = fights + 1
        forced = nil
        H.vars.bossBody = nil
        H.assertEq(latchByte(), 0, "isolation arm: latch clear (the gate "
          .. "reads in order shadow -> latch -> broken -> boss, so an unspent "
          .. "latch is what routes execution to the boss check)")
        resetLedger()
      end),
      -- chip until some body is Broken.  The divine would fire on the first
      -- post-break hit, so the injection must land in the same frame the
      -- break is first seen.  The per-frame scan gives that window: inject
      -- as soon as brk != 0 and before the next landed hit resolves (hit
      -- resolution takes whole action rounds, so one frame is well inside
      -- it).
      drive(function()
        if not H.battleLoadStarted() then return true end
        for _, m in ipairs(msPresent) do
          if alive(m) and brk(m) ~= 0 and (aa1(m) & 0x04) == 0 then
            H.vars.bossBody = m
            return true
          end
        end
        return false
      end, 30000, "a body breaks by real chips (isolation arm)"),
      H.cond(function()
        return H.battleLoadStarted() and H.vars.bossBody ~= nil
      end, {
        H.call(function()
          local m = H.vars.bossBody
          H.writeByte(0x3AA1 + ent(m), aa1(m) | 0x04)   -- the arm's one write (header)
          forced = m
          resetLedger()
          H.log(string.format("[isolation arm] body %d Broken by play; $3aa1.2 "
            .. "SET -- the bit a boss carries", m))
        end),
        drive(function()
          return brokenHits >= 1 or not alive(H.vars.bossBody)
            or not H.battleLoadStarted()
        end, 30000, "Shadow lands on the Broken 'boss' (isolation arm)"),
        H.call(function()
          if brokenHits >= 1 then
            landed = true
          else
            H.log(string.format("[isolation arm] body %d went (hp=%d, "
              .. "interceptor=%d) before Shadow landed on it -- another",
              H.vars.bossBody, mhp(H.vars.bossBody), counters))
          end
        end),
      }, {
        H.call(function()
          H.log(string.format("[isolation arm] fight %d ended before a body "
            .. "broke (hpDrops=%d interceptor=%d) -- the next encounter",
            fights, hpDrops, counters))
        end),
      }),
    }
    return H.repeatN(1, {
      H.repeatN(FIGHTS, {
        H.cond(function() return not landed end, pass, {}),
      }),
      H.call(function()
        H.assertEq(landed, true, string.format(
          "Shadow landed on a Broken body carrying the boss bit within %d "
          .. "fight(s) (fought %d)", FIGHTS, fights))
        H.log(string.format("[isolation arm] brokenHits=%d divineKills=%d "
          .. "latch=$%02x interceptor=%d", brokenHits, #divineKills,
          latchByte(), counters))
        H.assertEq(#divineKills, 0,
          "a Broken BOSS is never assassinated: the landed hit fired no "
          .. "in-proc Death mark")
        H.assertEq(latchByte(), 0, "and no divine was spent on it")
        watching = false
        H.screenshot("assassinate_boss")
      end),
    })
  end)(),
})

H.run({ maxFrames = 300000 }, steps)
