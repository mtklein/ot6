-- @suite slow
-- battle_breakmonster.lua -- a monster's Break still petrifies (#398).
--
-- OT6's Break (no damage, no status, shields taken) is a character's own
-- cast: Magic, X-Magic or a Mimic of one, or the Break Blade's on-hit spell
-- (Ot6BreakOurs, ot6_breakspell.asm).  A monster's Break -- and Control,
-- Sketch and a Rage, which cast as the monster does -- keeps vanilla's
-- petrify roll: the MagicProp record is vanilla's, and only an OT6 cast has
-- its loaded copy edited (Ot6BreakProps).  The Life 3 precedent
-- (magicite.md): characters' casts get OT6 behaviour, monsters keep vanilla.
--
-- The monsters whose scripts cast Break (Karkass, L.20 Magic, L.40 Magic)
-- live in the World of Ruin, past the chain's end, so the cast is staged, a
-- declared expedient: Continue fc-alcove-v1, walk onto the continent into a
-- random battle, the party Defends, and as a monster's next action is queued
-- (RecoveryQueueStored, CreateAction's store) it is rewritten to Break ($02,
-- $0C) at one party member whose status-1 block byte ($331C) lets Petrify
-- through, at no MP.  The engine does the rest: the vanilla record loaded at
-- execution, the hit roll, the status.  Vanilla Break can miss (hit 120,
-- the stamina check), so up to CASTS are staged, one at a time, each waited
-- out (the monster's Ot6ActionEnd).
--
-- Asserted: within CASTS Breaks, one turns its target to stone ($3EE4 bit
-- 6), and every Break took no HP off its target.
--
-- Then Rage and Sketch (#424).  A character's Rage or Sketch casts the
-- monster's attack as the monster does: Cmd_10 / Cmd_0d hand $b6 to
-- _c21554, whose GetCmdForAI dispatches a spell through Cmd_02, while $3A7C
-- keeps the queued command InitPlayerAction copied out of the queue ($10 or
-- $0D) for the whole action.  Ot6BreakOurs reads that byte, so such a Break
-- is vanilla's.  (Control is the monster's own action, x >= 8: the arm
-- above.)  No route character learns a Break rage or sketch, so the context
-- is staged, a declared expedient: TERRA casts Break through the real menu
-- at a monster Petrify can reach ($331C), and as Cmd_02 begins her action
-- $3A7C is rewritten to Rage ($10), then in the second arm to Sketch ($0D),
-- what those commands leave there.  Asserted per arm, within CASTS Breaks:
-- every one took no shield and no HP off its target, and one turned it to
-- stone ($3EEC bit 6).
-- Old-ROM control (vanilla Break: passes) and reds: the branch's ROM before
-- the gate, and a mutant that lets a monster's Break through the gate
-- (build/attempts/wt/v027-kits/final-matrix/<rom>__battle_breakmonster.out; the
-- branch's ROM before the gate: build/attempts/wt/v027-kits/mx8/
-- mut2_real__battle_breakmonster.out).
--
-- The battles are whatever the continent deals (#468).  A battle the
-- staging does not need is fought out by the route's fight driver
-- (tactical, boost, items, its heals), not by a bare Fight: v0.36's sweep
-- (shift 13 after one and three encounters used up) lost the whole party
-- to the Ninja pincer (formation monsters $0003 $0003) in such a battle,
-- every seat at 4-5 BP unspent (build/attempts/wt/v036-fragile/K/logs/
-- battle_breakmonster__s13__k1.log.gz).  And the party Defends through a
-- staging only while it holds: once a seated member falls under a third of their
-- max HP (or down, a stone the staging made aside), that battle is handed
-- to the fight driver and the arm goes on in the next one, its Breaks
-- counted across battles against the same CASTS.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local BREAK, CMD_MAGIC, CASTS = 0x0C, 0x02, 8
local PETRIFY = 0x40

local staged, casts, stoned, target, armed = nil, 0, false, nil, false
-- what a callback saw that the run must fail on: an error raised inside a
-- memory callback does not stop the run, so the verdict is asserted in the
-- step after it (#424: the break_cmd mutant's twenty shield-taking Breaks
-- went past a callback's assertion)
local bad = {}

-- why the party can no longer Defend through a staging, or nil: a seated
-- member down (Wound, Zombie or 0 HP; the stone a staged Break makes is the
-- property, not a danger) or under DANGER of max HP
local DANGER = 1 / 3
local function danger()
  if not H.battleLoadStarted() then return nil end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local hp, mx, st1 = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2), H.readByte(0x3EE4 + s * 2)
      if (st1 & 0x40) == 0 and (hp == 0 or (st1 & 0x82) ~= 0 or (mx > 0 and hp < mx * DANGER)) then
        return string.format("seat %d at %d/%d HP, status1 $%02X", s, hp, mx, st1)
      end
    end
  end
  return nil
end
local handed = nil
-- Lab lever (#468 review): MBREAK_FORCE_HANDOVER = "monster", "Rage" or
-- "Sketch" hands that arm's first guarded battle over once, 600 frames in,
-- as if danger() had fired, so the hand-over path and the arm's resumption
-- in the next battle can be shown on a draw that never endangers the party.
local FORCE = rawget(_G, "MBREAK_FORCE_HANDOVER")
local forced = false
-- step, run until it ends or danger() hands the battle over (handed)
local function guarded(step, what, arm)
  local ended, inBattle = false, 0
  return H.withReset(H.driveUntil(function()
    if ended then return true end
    if handed == nil then
      if H.battleLoadStarted() then inBattle = inBattle + 1 end
      handed = danger()
      if handed == nil and FORCE ~= nil and FORCE == arm and not forced and inBattle >= 600 then
        forced, handed = true, "forced by MBREAK_FORCE_HANDOVER (lab)"
      end
      if handed then H.log(string.format("[mbreak] f%d %s: handed to the fight driver (%s)", H.frame, what, handed)) end
    end
    return handed ~= nil
  end, 70000, { step, H.call(function() ended = true end) }, what), function() ended, inBattle = false, 0 end)
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

local function pickTarget()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF and H.readWord(0x3BF4 + s * 2) > 0
        and (H.readByte(0x3EE4 + s * 2) & 0xC2) == 0 and (H.readByte(0x331C + s * 2) & PETRIFY) ~= 0 then
      return s
    end
  end
end

local function arm()
  local q = H.sym("RecoveryQueueStored")
  emu.addMemoryCallback(function()
    if not armed or staged ~= nil or stoned or casts >= CASTS then return end
    local st = emu.getState()
    local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
    if x < 8 then return end
    local t = pickTarget()
    if t == nil then return end
    H.writeByte(0x3420 + y, CMD_MAGIC)
    H.writeByte(0x3421 + y, BREAK)
    H.writeWord(0x3520 + y, 1 << t)
    H.writeByte(0x3620 + y, 0)
    staged = { x = x, t = t, hp = H.readWord(0x3BF4 + t * 2), f = H.frame }
    H.log(string.format("[mbreak] f%d monster slot %d's queued action -> Break at seat %d (HP %d)", H.frame,
      (x - 8) // 2, t, staged.hp))
  end, emu.callbackType.exec, q, q)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if staged == nil or (emu.getState()["cpu.x"] & 0xFF) ~= staged.x then return end
    local t = staged.t
    if H.readByte(0xB6) ~= BREAK then return end   -- an earlier action of the monster's ($b6: the attack)
    casts = casts + 1
    local s1, hp = H.readByte(0x3EE4 + t * 2), H.readWord(0x3BF4 + t * 2)
    H.log(string.format("[mbreak] f%d Break %d resolved: seat %d status1 $%02X, HP %d -> %d", H.frame, casts, t, s1,
      staged.hp, hp))
    if not (hp >= staged.hp or (s1 & PETRIFY) ~= 0) then
      bad[#bad + 1] = string.format("a monster's Break took HP off seat %d (%d -> %d)", t, staged.hp, hp)
    end
    if (s1 & PETRIFY) ~= 0 then stoned, target = true, t end
    staged = nil
  end, emu.callbackType.exec, ae, ae)
end

-- the Rage / Sketch arms: TERRA's Break, cast in that command's context
local TERRA, RAGE, SKETCH = 0x00, 0x10, 0x0D
local ctx, tseat, crec, ccasts, cstone, ctxEnd = nil, nil, nil, 0, false, -1
local function monPetrifiable()
  for s = 0, 5 do
    local x = 8 + s * 2
    if (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0
        and (H.readByte(0x3EEC + s * 2) & 0xC2) == 0 and (H.readByte(0x331C + x) & PETRIFY) ~= 0 then
      return s
    end
  end
end
local function armCtx()
  local c2 = H.sym("Cmd_02")
  emu.addMemoryCallback(function()
    if ctx == nil or crec ~= nil or tseat == nil then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y ~= tseat * 2 or H.readByte(0x3A7C) ~= CMD_MAGIC or H.readByte(0x3A7D) ~= BREAK then return end
    H.writeByte(0x3A7C, ctx)
    local t = nil
    for s = 0, 5 do if (H.readByte(0xB9) >> s) & 1 == 1 then t = s end end
    crec = { t = t, sh = t and H.readByte(0x3E40 + t * 2), hp = t and H.readWord(0x3BFC + t * 2), f = H.frame }
    H.log(string.format("[mbreak] f%d TERRA's Break enters Cmd_02: $3A7C -> $%02X (target slot %s)", H.frame, ctx,
      tostring(t)))
  end, emu.callbackType.exec, c2, c2)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if crec == nil or tseat == nil or (emu.getState()["cpu.x"] & 0xFF) ~= tseat * 2 then return end
    local t = crec.t
    ccasts = ccasts + 1
    local st, sh, hp = H.readByte(0x3EEC + t * 2), H.readByte(0x3E40 + t * 2), H.readWord(0x3BFC + t * 2)
    H.log(string.format("[mbreak] f%d %s-context Break %d resolved: slot %d status1 $%02X, shields %d -> %d, HP %d -> %d",
      H.frame, ctx == RAGE and "Rage" or "Sketch", ccasts, t, st, crec.sh, sh, crec.hp, hp))
    if sh ~= crec.sh then
      bad[#bad + 1] = string.format("a %s-context Break took a shield off slot %d (%d -> %d): OT6's, not vanilla's",
        ctx == RAGE and "Rage" or "Sketch", t, crec.sh, sh)
    elseif not (hp >= crec.hp or (st & PETRIFY) ~= 0) then
      bad[#bad + 1] = string.format("a %s-context Break took HP off slot %d (%d -> %d)",
        ctx == RAGE and "Rage" or "Sketch", t, crec.hp, hp)
    elseif (st & PETRIFY) ~= 0 then
      cstone = true
    end
    crec, ctxEnd = nil, H.frame
  end, emu.callbackType.exec, ae, ae)
end
local function ctxArm(c, name)
  local plan = {}
  local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
  return H.seqStep({
    H.call(function() ctx, ccasts, cstone, crec = c, 0, false, nil end),
    H.driveUntil(function() return cstone end, 300000, {
      H.cond(function() return not H.battleLoadStarted() end, { H.fcPace("mbreak") }, {}),
      H.call(function()
        handed, crec = nil, nil
        H.assertEq(bad[1], nil, "every staged Break was vanilla's (no shield, no HP)")
        H.assertEq(ccasts < CASTS, true, string.format("a %s-context Break petrified within %d casts", name, CASTS))
        tseat = nil
        for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then tseat = s end end
        H.assertEq(tseat ~= nil, true, "TERRA is seated")
        local t, e = monPetrifiable(), tseat * 2
        plan = {}
        if t == nil or H.readWord(0x3BF4 + e) == 0 or (H.readByte(0x3EE4 + e) & 0xE2) ~= 0
            or (H.readByte(0x3EE5 + e) & 0xB8) ~= 0 then
          H.log("[mbreak] no monster Petrify can reach, or TERRA cannot cast: this battle is fought out")
          return
        end
        plan = { { who = TERRA, cmd = CMD_MAGIC, spell = BREAK, boost = 0, slot = t } }
      end),
      H.cond(function() return #plan == 0 end, { fightOut("mbreak: " .. name .. " arm, no cast here") }, {
        guarded(H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
          planDone = function()
            local k = H.vars.kit[#H.vars.kit]
            return k ~= nil and ctxEnd > k.frame
          end }), "the " .. name .. "-context Break", name),
        H.cond(function() return handed ~= nil end, { fightOut("mbreak: " .. name .. " arm, handed over") }, {}),
      }),
    }, "a " .. name .. "-context Break that petrifies"),
    H.call(function()
      H.assertEq(bad[1], nil, "every staged Break was vanilla's (no shield, no HP)")
      H.log(string.format("[mbreak] PASS: %s-context Break: vanilla's (no shield taken), petrified within %d cast(s)",
        name, ccasts))
    end),
  })
end

local function monsterArmDone() return stoned or (casts >= CASTS and staged == nil) end
H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("mbreak"),
  H.driveUntil(monsterArmDone, 400000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.fcPace("mbreak") }, {}),
    H.call(function()
      -- a Break staged in a battle that ended unresolved never resolves
      staged, handed = nil, nil
      H.assertEq(pickTarget() ~= nil, true, "a party member Petrify can reach (no Ribbon or stone ward)")
      armed = true
    end),
    guarded(H.kitBattle({}, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
      planDone = monsterArmDone }), "a monster's staged Break", "monster"),
    H.cond(function() return handed ~= nil end, {
      H.call(function() armed, staged = false, nil end),
      fightOut("mbreak: monster arm, handed over"),
    }, {}),
  }, "a monster's Break that petrifies"),
  H.call(function()
    H.log(string.format("[mbreak] %d Break(s) cast by monsters; seat %s turned to stone", casts, tostring(target)))
    H.assertEq(bad[1], nil, "every staged Break was vanilla's (no HP)")
    H.assertEq(stoned, true, string.format("a monster's Break petrified a party member within %d casts", CASTS))
    H.log("[mbreak] PASS: a monster's Break keeps vanilla's petrify")
    armed = false
    armCtx()
  end),
  H.cond(function() return H.battleLoadStarted() end, { fightOut("mbreak: after the monster arm") }, {}),
  ctxArm(RAGE, "Rage"),
  H.cond(function() return H.battleLoadStarted() end, { fightOut("mbreak: after the Rage arm") }, {}),
  ctxArm(SKETCH, "Sketch"),
  H.call(function()
    H.log("[mbreak] PASS: a monster's Break, and a Break cast in Rage's or Sketch's context, keep vanilla's petrify")
  end),
})
