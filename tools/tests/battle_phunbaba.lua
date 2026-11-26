-- @suite savestate=phunbaba_entry slow
-- battle_phunbaba.lua -- Phunbaba's second visit under the boss contract (docs/design/bosses-wor.md block 4,
-- wt/v052-tg-wor1): his BabaBreath is announced, and a break while it is lit takes his breath away.
--
-- His script (ai_script.asm AIScript::_364): on his first turn under 20,480 HP he says "He fills his lungs!" (battle
-- dialogue $A2) and glows, a turn of its own, and sets battle switch 1: the fuse is lit (Ot6FuseTbl's switch row
-- $016C, mask $02) until a blow takes him under 15,360 HP, and that blow brings his counter's fire block: two
-- BabaBreaths (attack $EA, command $0C, each blowing a member out of the party for the fight after) and the battle's
-- end.  A break while it is lit cancels it (the switch goes): the blow that crosses the line then ends the battle
-- with no breath, and if he is still above the line on his next turn after the break he fills his lungs again.  A
-- blow that crosses the line with no breath held -- none announced yet, or a break since -- ends the battle with
-- none: BabaBreath comes only announced.  His dying BabaBreath is vanilla's (the dying-attack rule is a later unit's;
-- not played here).
--
-- Boots phunbaba_entry (gen_wor_terra: the second visit's battle, event battle 130, as it comes up).  Each case
-- plays from a snapshot at the battle's open and ends with the battle.  The party's own blows are Fights aimed at
-- him by the members whose hands chip nothing on his row (no class key of his, no poison: read from the ROM and the
-- party's kit), so that only a case's own staged break breaks him; the others Defend.
--   landed    nothing staged and nothing held: the Fights bring him under 20,480; his next turn says the line, the
--             lit-fuse mark stands and the lit bit is set (battle switch 1); the Fights go on, and the blow that
--             takes him under 15,360 brings two BabaBreaths, his counter's, with the switch cleared first; the
--             battle ends; the line reads "He fills his lungs!" where the relocated dialogue table points.
--   broken    the same to the line; then his gauge staged to 1 with every class (DECLARED) and an aimed Fight once
--             the mark is up breaks him: the cancel fires, battle switch 1 reads clear, the mark goes; his HP is then
--             staged to 15,500 (DECLARED) and an aimed Fight takes him under the line while he is Broken: the battle
--             ends with no BabaBreath.
--   refill    the same break, then the party Defends through it: on his first turn back (still in the band) he fills
--             his lungs again (the trigger earned again: a turn in the band), and the crossing then brings the two
--             BabaBreaths.
--   outside   above the band his gauge staged to 1 (DECLARED) and an aimed Fight breaks him before any line: nothing
--             is cancelled and battle switch 1 stays clear; then the line, and the crossing brings the breath.
--   no breath (below) above the band, no line said, his HP staged to 15,500 (DECLARED) as a member's Fight is
--             dispatched, before its damage (no turn of his can come between): the blow crosses the line and the
--             battle ends with no BabaBreath.  (A first cut staged it after one of his turns and Fought after: his
--             next turn, and his line, came first on three tries of one draw: build/attempts/wt/v052-tg-wor1/dev/
--             dev_battle_phunbaba-2.log.)
-- DECLARED SYNTHETIC SETUP (tools/state_write_waivers.txt): the gauge and HP stagings above, through the suite's two
-- writers, and each standing member's HP held at 9,999 in the staged cases (none in landed).  A mechanism test, not
-- play (the landed case writes nothing).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "broken: the break while lit cancels it"; phun_row_keeps (his row keeps battle switch 1: +6 = $FF) at "broken:
-- battle switch 1 is clear after the cancel"; phun_breath_always (his no-breath block's end_battle -> his fire
-- block's breath) at "no breath: the battle ends with no BabaBreath".
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (the gauge, his HP, the party's held HP; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/phunbaba_entry.mss.lua"

local PHUN, BREATH, LINE, BAND, CROSS = 0x16C, 0xEA, 0xA2, 20480, 15360

local W = H.fuseWatch(PHUN, WRITE)
local D = H.monsterDlgReads()
local S = {}
local C = {}
local function say(s) H.log(string.format("[phunbaba] f%d %s: %s", H.frame, C.name or "-", s)) end
local function up() return H.battleLoadStarted() end
local function hp() local e = W.ent(); return e and H.readWord(0x3BF4 + e) or -1 end
local function lineFrom(i) return W.find(0x21, LINE, i) end
local function breaths(from)
  local t = {}
  for k = from or 1, #W.cmds do
    local c = W.cmds[k]
    if c.cmd == 0x0C and c.arg == BREATH then t[#t + 1] = c end
  end
  return t
end
local function lit() return (H.readByte(0x3EB0) & 0x02) ~= 0 end
local function markOn() return W.vramMark() == W.FUSE_WORD end

-- the members whose Fight chips nothing on his row (M.quietMembers: no class key of his, no poison)
local quiet = nil
local function sortParty()
  quiet = H.quietMembers(PHUN, 0x08)
  H.assertEq(#quiet >= 1, true, "a member whose Fight chips nothing on Phunbaba's row (the precondition the cases' "
    .. "own blows need: the route's CELES swings a sword, no key of his)")
end

-- the quiet members Fight him, aimed, until pred(); the others Defend
local function quietFights(pred, max)
  return H.lazy(function()
    local t0 = H.frame
    local plan = {}
    for k = 1, 30 do for _, id in ipairs(quiet) do plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = W.slot() } end end
    return H.kitBattle(plan, { idle = "defend", care = true, maxFrames = max + 600,
      giveUp = function() return not up() or pred() or H.frame - t0 >= max end })
  end)
end
local function defendUntil(pred, max)
  return H.lazy(function()
    local t0 = H.frame
    return H.kitBattle({}, { idle = "defend", care = true, maxFrames = max + 600,
      giveUp = function() return not up() or pred() or H.frame - t0 >= max end })
  end)
end
-- one aimed Fight by the first standing member (who need not be quiet), confirmed when when() is true
local function aimedFight(when, max)
  return H.lazy(function()
    local who = nil
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if who == nil and id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and (H.readByte(0x3EE4 + 2 * i) & 0xC2) == 0 then
        who = id
      end
    end
    C.nBreaks, C.nParty = #W.breaks, #W.party
    local t0 = H.frame
    return H.kitBattle({ { who = who, cmd = 0x00, boost = 0, slot = W.slot(), confirmWhen = when } },
      { idle = "defend", care = false, maxFrames = max + 600,
        giveUp = function() return not up() or #W.party > C.nParty or H.frame - t0 >= max end })
  end)
end

-- the case's open: the snapshot restored (the first case takes it), the watch reset
local function open(name, pinParty)
  return H.seqStep({
    H.cond(function() return S.req == nil end, { H.fuseSnap(S), H.waitFrames(1) }, { H.fuseRestore(S, name) }),
    H.call(function()
      C = { name = name }
      W.reset(); W.on = true
      W.pin = pinParty and { party = true } or nil
      say("from the battle's open: " .. W.cellsLine(W.cells()))
    end),
    H.waitUntil(function() return W.ent() ~= nil and H.battleActive() end, 3000, name .. ": Phunbaba on the field", 2),
  })
end

-- to the line: the quiet Fights bring him under the band and his next turn says it
local function toLine(what)
  return H.seqStep({
    quietFights(function() return lineFrom(1) ~= nil end, 40000),
    H.call(function()
      local li, lc = lineFrom(1)
      H.assertEq(li ~= nil, true, string.format("%s: the line came once he was under 20,480 HP (%s)", C.name, what))
      C.li, C.lc = li, lc
      say(string.format("the line on his turn %d at his HP %d", lc.turn, hp()))
      H.assertEq(hp() < BAND, true, C.name .. ": his HP is under 20,480 at the line")
    end),
    defendUntil(function() return lit() and markOn() end, 900),
    H.call(function()
      H.assertEq(lit(), true, C.name .. ": battle switch 1 (the breath held) is set after the line: the fuse is lit")
      H.assertEq(W.litBit(), true, C.name .. ": OT6_FUSE's lit bit is set for his slot")
      H.assertEq(markOn(), true, C.name .. ": the lit-fuse mark stands before his shield emblem")
    end),
  })
end

-- the crossing with the breath held: the quiet Fights take him under 15,360, and his counter brings two BabaBreaths
local function crossBreath(from)
  return H.seqStep({
    quietFights(function() return #breaths(C[from] or 1) >= 2 end, 40000),
    defendUntil(function() return false end, 900),
    H.call(function()
      local b = breaths(C[from] or 1)
      say(string.format("%d BabaBreath(s) after the line; the battle %s", #b, up() and "is still up" or "ended"))
      H.assertEq(#b, 2, C.name .. ": two BabaBreaths came on the crossing")
      H.assertEq(b[1].retal and b[2].retal, true, C.name .. ": both are his counter's (the crossing blow's)")
      H.assertEq(up(), false, C.name .. ": the battle ended after them (end_battle)")
    end),
  })
end

local function breakInFuse()
  return H.seqStep({
    H.call(function()
      W.pin = { party = true }
      local e = W.ent()
      C.row = H.readByte(0x3E9C + e)
      WRITE.byte(0x3E9C + e, 0x3F)
      WRITE.byte(0x3E38 + e, 1)     -- (DECLARED: his gauge to 1, every class a key, for the breaking Fight)
      say("the gauge staged to 1, every class a key")
    end),
    aimedFight(function() return markOn() end, 6000),
    H.waitFrames(2),
    H.call(function()
      WRITE.byte(0x3E9C + W.ent(), C.row)   -- (his own row back: the quiet Fights after chip nothing again)
      H.assertEq(#W.breaks > C.nBreaks, true, C.name .. ": the aimed Fight took his last shield")
      C.brk = W.breaks[#W.breaks]
      say(string.format("broken at his HP %d: %d cancel(s); battle switches $%02X", hp(), #W.snuffs,
        H.readByte(0x3EB0)))
      H.assertEq(#W.snuffs, 1, C.name .. ": the break while lit cancels it (Ot6FuseSnuff fired once)")
      H.assertEq(lit(), false, C.name .. ": battle switch 1 is clear after the cancel")
    end),
    defendUntil(function() return not W.litBit() and not markOn() end, 900),
    H.call(function()
      H.assertEq(markOn(), false, C.name .. ": the mark is gone after the breaking hit")
    end),
  })
end

local landed = H.seqStep({
  open("landed", false),
  toLine("nothing staged"),
  crossBreath("li"),
  H.call(function()
    local nRead = 0
    for _, r in ipairs(D.ptrReads) do if r.f >= C.lc.f and r.id == LINE then nRead = nRead + 1 end end
    local at, want = D.textAt(C.lc.f), D.tableAt(LINE)
    say(string.format("the line's text: %d read(s) of its table word; the window read $%06X (the table gives $%06X): %q",
      nRead, at or 0, want, at and D.decode(at) or "(nothing read)"))
    H.assertEq(nRead >= 1 and at == want, true, "landed: the window read the line's text where the table points")
    H.assertEq(D.decode(want), "He fills his lungs!{wait}", "landed: the line reads \"He fills his lungs!\"")
    say("PASS")
  end),
})

local broken = H.seqStep({
  open("broken", true),
  toLine("to be broken"),
  breakInFuse(),
  H.call(function()
    WRITE.word(0x3BF4 + W.ent(), CROSS + 140)   -- (DECLARED: his HP just above the line, so one blow crosses it)
    say(string.format("his HP staged to %d while he is Broken", CROSS + 140))
  end),
  aimedFight(function() return true end, 3000),
  defendUntil(function() return false end, 900),
  H.call(function()
    local b = breaths(1)
    say(string.format("after the crossing: %d BabaBreath(s); the battle %s", #b, up() and "is still up" or "ended"))
    H.assertEq(#b, 0, "broken: no BabaBreath: the crossing after the cancel holds no breath")
    H.assertEq(up(), false, "broken: the crossing while Broken ended the battle")
    say("PASS")
  end),
})

local refill = H.seqStep({
  open("refill", true),
  toLine("to be broken, then earned again"),
  breakInFuse(),
  H.call(function() C.cmdsAt = #W.cmds end),
  defendUntil(function() local c = W.cells(); return c ~= nil and c.ticks == 0 end, 4000),
  H.call(function()
    C.recTurn = #W.turns
    say(string.format("recovered at his HP %d after turn %d", hp(), C.recTurn))
    H.assertEq(hp() >= CROSS, true, "refill: he is still above the line when he recovers")
  end),
  defendUntil(function() return lineFrom(C.cmdsAt + 1) ~= nil end, 8000),
  H.call(function()
    local li, lc = lineFrom(C.cmdsAt + 1)
    H.assertEq(li ~= nil, true, "refill: the line returns after the cancel (he fills his lungs again)")
    say(string.format("the second line on his turn %d (recovered after turn %d)", lc.turn, C.recTurn))
    H.assertEq(lc.turn, C.recTurn + 1, "refill: the line returns on his first turn back (a turn in the band earns it)")
    H.assertEq(#breaths(1), 0, "refill: no BabaBreath before the second line")
    C.li2 = li
  end),
  crossBreath("li2"),
  H.call(function() say("PASS") end),
})

local outside = H.seqStep({
  open("outside", true),
  H.call(function()
    H.assertEq(hp() >= BAND, true, "outside: he stands above the band at the open (the case's precondition)")
    local e = W.ent()
    C.row = H.readByte(0x3E9C + e)
    WRITE.byte(0x3E9C + e, 0x3F)
    WRITE.byte(0x3E38 + e, 1)       -- (DECLARED: his gauge to 1, every class a key)
    C.bswPre = H.readByte(0x3EB0)
  end),
  aimedFight(function() return true end, 4000),
  H.waitFrames(2),
  H.call(function()
    WRITE.byte(0x3E9C + W.ent(), C.row)     -- (his own row back)
    H.assertEq(#W.breaks >= 1, true, "outside: the aimed Fight broke him")
    H.assertEq(lineFrom(1), nil, "outside: the break came before any line (the case's precondition)")
    H.assertEq(#W.snuffs, 0, "outside: a break before the line cancels nothing")
    H.assertEq(H.readByte(0x3EB0), C.bswPre, "outside: the battle switches stand as they were")
  end),
  defendUntil(function() local c = W.cells(); return c ~= nil and c.ticks == 0 end, 4000),
  toLine("after a break outside the fuse"),
  crossBreath("li"),
  H.call(function() say("PASS") end),
})

-- no breath: above the band, with no line said, his HP is staged just above the line at the moment a member's Fight is
-- dispatched (before its damage is reckoned: no turn of his can come between), and that blow crosses the line
local stageOnFight = nil
local noBreath = H.seqStep({
  open("no breath", true),
  H.call(function()
    H.assertEq(hp() >= BAND and lineFrom(1) == nil, true, "no breath: he stands above the band, no line said (the "
      .. "case's precondition)")
    stageOnFight = function()
      if H.readByte(0xB5) ~= 0x00 or (emu.getState()["cpu.x"] & 0xFF) >= 8 then return end
      stageOnFight = nil
      C.stagedAt = H.frame
      WRITE.word(0x3BF4 + W.ent(), CROSS + 140)  -- (DECLARED: his HP just above the line, no line said)
      say(string.format("his HP staged to %d as a member's Fight is dispatched", CROSS + 140))
    end
  end),
  aimedFight(function() return true end, 4000),
  defendUntil(function() return false end, 900),
  H.call(function()
    H.assertEq(C.stagedAt ~= nil, true, "no breath: the staging rode a member's Fight")
    H.assertEq(lineFrom(1), nil, "no breath: no line was said before the crossing")
    local b = breaths(1)
    say(string.format("the blow crossed with no line: %d BabaBreath(s); the battle %s", #b, up() and "is still up"
      or "ended"))
    H.assertEq(#b, 0, "no breath: the battle ends with no BabaBreath when no breath is held")
    H.assertEq(up(), false, "no breath: the crossing ended the battle")
    say("PASS")
  end),
})

-- The cap: six cases of about 10,000 frames; 140,000 is about 2x.
H.run({ maxFrames = 140000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "Phunbaba's battle is up", 2),
  H.call(function()
    H.assertEq(W.slot() ~= nil, true, "Phunbaba ($16C, the second visit) stands at the open (phunbaba_entry)")
    H.assertEq(#H.aiAttacks(PHUN, BREATH), 0, "BabaBreath is no move of his turns (his counter's and his death's)")
    sortParty()
    emu.addMemoryCallback(function() if stageOnFight then stageOnFight() end end, emu.callbackType.exec,
      H.sym("_dispatcher"), H.sym("_dispatcher"))
  end),
  landed, broken, refill, outside, noBreath,
  H.logStep("[phunbaba] PASS: the lungs filled under 20,480, the breath on the crossing, the cancel that takes it, "
    .. "the refill, and no breath unannounced"),
})
