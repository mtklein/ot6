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
-- Old-ROM control (vanilla Break: passes) and reds: the branch's ROM before
-- the gate, and a mutant that lets a monster's Break through the gate
-- (build/attempts/wt/v027-kits/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local BREAK, CMD_MAGIC, CASTS = 0x0C, 0x02, 8
local PETRIFY = 0x40

local staged, casts, stoned, target, armed = nil, 0, false, nil, false

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
    H.assertEq(hp >= staged.hp or (s1 & PETRIFY) ~= 0, true, "a monster's Break took no HP")
    if (s1 & PETRIFY) ~= 0 then stoned, target = true, t end
    staged = nil
  end, emu.callbackType.exec, ae, ae)
end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("mbreak"),
  H.call(function()
    H.assertEq(pickTarget() ~= nil, true, "a party member Petrify can reach (no Ribbon or stone ward)")
    armed = true
  end),
  H.kitBattle({}, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
    planDone = function() return stoned or (casts >= CASTS and staged == nil) end }),
  H.call(function()
    H.log(string.format("[mbreak] %d Break(s) cast by monsters; seat %s turned to stone", casts, tostring(target)))
    H.assertEq(stoned, true, string.format("a monster's Break petrified a party member within %d casts", CASTS))
    H.log("[mbreak] PASS: a monster's Break keeps vanilla's petrify")
  end),
})
