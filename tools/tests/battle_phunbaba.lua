-- @suite savestate=phunbaba_entry slow
-- battle_phunbaba.lua -- Phunbaba's second visit under the boss contract (docs/design/bosses-wor.md block 4,
-- wt/v052-tg-wor1): his BabaBreath is announced a turn ahead, and a break denies it for the fight.
--
-- His script (ai_script.asm AIScript::_364): on his first turn under 20,480 HP he says "He fills his lungs!" (battle
-- dialogue $A2) and glows, a turn of its own, and sets battle switch 1; on his next turn the fire block, the script's
-- first, takes that turn whatever his HP reads then: two BabaBreaths (attack $EA, command $0C, each blowing a member
-- out of the party for the fight after) and the battle's end.  Every break of him, lit or not, denies the breath for
-- the fight (Ot6FuseTbl's row $016C, OT6_FUSE_HOLD: battle switch 0 set, switch 1 cleared), and a break in the fuse
-- cancels it besides ($3240 forgotten).  Once denied, the blow that takes him under 15,360 ends the battle with no
-- breath (his counter's block, a story block: it runs while he is Broken); not denied, that blow ends nothing.  His
-- dying BabaBreath is vanilla's (the dying-attack rule is a later unit's; not played here).  The first visit's two
-- records ($16A, $16B) and TERRA's fight ($16D) are vanilla's byte for byte (read from the ROM against vanilla's bytes
-- below).
--
-- Boots phunbaba_entry (gen_wor_terra: the second visit's battle, event battle 130, as it comes up).  Each case
-- plays from a snapshot at the battle's open.  The party's own blows are Fights aimed at him by the members whose
-- hands chip nothing on his row (no class key of his, no poison: read from the ROM and the party's kit), so that only
-- a case's own staged break breaks him; the others Defend.
--   landed    nothing staged and nothing held: the Fights bring him under 20,480; his next turn says the line, the
--             lit-fuse mark stands and the lit bit is set; the party Defends, and his next turn brings the two
--             BabaBreaths (his turn's, not a counter's) and the battle's end; then the story plays on (the route's
--             tactical driver) into TERRA's fight, which opens with the two the breaths left and TERRA, and is won.
--             The breath's effect: the two members it took, absent from TERRA's fight.  (Three tries from the open,
--             each with one more round of Defends before the Fights: a member's counter can break him in the fuse on
--             a draw, which denies the breath -- then the next try.)
--   broken    (DECLARED: his gauge to 1 with every class at the line, the party's HP held at 9,999) a break in the
--             fuse: the cancel fires, battle switch 1 clear, battle switch 0 set (denied), the mark goes; his turns
--             after he recovers say no line and bring no breath; his HP then staged to 15,500 (DECLARED) and an aimed
--             Fight crosses the line: the battle ends with no BabaBreath, and the story plays on into TERRA's fight,
--             which opens with all four and TERRA's seat and is won.
--   outside   (DECLARED as broken) above the band his gauge staged to 1 and an aimed Fight breaks him before any line:
--             nothing is cancelled, the breath is denied (battle switch 0); under the band his turns say no line, and
--             the crossing ends the battle with no breath (breaking him before he ever announces skips it).
--   burst     (DECLARED: his HP staged to 15,000 as a member's Fight is dispatched, no line said, so the blow takes him
--             from above the band to under the line in one) the battle does not end; his next turn says the line and
--             the one after brings the two BabaBreaths and the end.
--   heal      (DECLARED: at the line his HP staged to 25,000, above the band, the heal his bolt-absorbing would give)
--             his next turn brings the breath anyway.
-- DECLARED SYNTHETIC SETUP (tools/state_write_waivers.txt): the gauge and HP stagings above, through the suite's two
-- writers, and each standing member's HP held at 9,999 in the staged cases (none in landed).  A mechanism test, not
-- play (the landed case writes nothing).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "broken: the break while lit cancels it"; phun_no_hold (his row's flags 0: no denial) at "broken: battle switch 0
-- is set"; phun_cross_ends (his crossing block's denial test -> always) at "burst: the crossing blow ends nothing";
-- phun_fire_late (the fire block's clear after the breaths) at battle_fuse's "the trigger's clears come before the
-- move".
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (the gauge, his HP, the party's held HP; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/phunbaba_entry.mss.lua"

local PHUN, TERRA_PHUN, BREATH, LINE, BAND, CROSS = 0x16C, 0x16D, 0xEA, 0xA2, 20480, 15360
local TERRA = 0x00
-- vanilla's bytes (Final Fantasy III (USA), the scripts at $CF8700 by the pointers at $CF8400): the first visit's
-- two records and TERRA's fight, turn script and counter
local VANILLA = {
  [0x16A] = "fc150000fb0136f9010000fef0eeeeeffdf007070bfdf00790effffc120000f50c01fffeff",
  [0x16B] = "f0eeeeeffdf007070bfdf00790effffc120000f50c01fffefc050000fc0636a0f136c2feff",
  [0x16D] = "f0eeeeeffdf007070bfdf00790effffc120000f50c01fffefc050000f007fefeff",
}

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
local function denied() return (H.readByte(0x3EB0) & 0x01) ~= 0 end
local function markOn() return W.vramMark() == W.FUSE_WORD end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end

-- the script bytes of a species' two scripts (turn, counter), as hex
local function scriptHex(sp)
  local SIZE = { [0] = 4, 2, 4, 3, 4, 4, 4, 2, 3, 4, 4, 3, 4, 1, 1, 1 }
  local AI, PTRS = H.sym("AIScript") & 0x3FFFFF, H.sym("AIScriptPtrs") & 0x3FFFFF
  local x = H.readRomByte(PTRS + 2 * sp) | (H.readRomByte(PTRS + 2 * sp + 1) << 8)
  local t, ends = {}, 0
  while ends < 2 do
    local b = H.readRomByte(AI + x)
    local n = b >= 0xF0 and SIZE[b - 0xF0] or 1
    for k = 0, n - 1 do t[#t + 1] = string.format("%02x", H.readRomByte(AI + x + k)) end
    x = x + n
    if b == 0xFF then ends = ends + 1 end
  end
  return table.concat(t)
end

-- the members whose Fight chips nothing on his row (M.quietMembers: no class key of his, no poison)
local quiet = nil
local function sortParty()
  quiet = H.quietMembers(PHUN, 0x08)
  H.assertEq(#quiet >= 1, true, "a member whose Fight chips nothing on Phunbaba's row (the precondition the cases' "
    .. "own blows need: the route's CELES swings a sword, no key of his)")
end

local function quietFights(pred, max, boost)
  return H.lazy(function()
    local t0 = H.frame
    local plan = {}
    for k = 1, 30 do
      for _, id in ipairs(quiet) do plan[#plan + 1] = { who = id, cmd = 0x00, boost = boost or 0, slot = W.slot() } end
    end
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

-- TERRA's fight, as it opens: its seats (char ids), read once a battle with $16D is up
local terraFight = nil
local function watchTerraFight()
  emu.addEventCallback(function()
    if terraFight ~= nil and terraFight.seats ~= nil then return end
    if terraFight == nil or not H.battleActive() then return end
    for s = 0, 5 do
      if H.readWord(0x57C0 + 2 * s) == TERRA_PHUN and (H.readByte(0x3AA8 + 2 * s) & 1) == 1 then
        local seats = {}
        for i = 0, 3 do seats[i] = H.readByte(0x3ED8 + 2 * i) end
        terraFight.seats, terraFight.f = seats, H.frame
        H.log(string.format("[phunbaba] f%d TERRA's fight ($16D) is up: seats $%02X $%02X $%02X $%02X", H.frame,
          seats[0], seats[1], seats[2], seats[3]))
        return
      end
    end
  end, emu.eventType.endFrame)
end
-- the story after the second visit: on into TERRA's fight (the route's tactical driver) and through it, to TERRA
-- in the party ($00BF)
local function onToTerra(what, wantSeated, blown)
  return H.seqStep({
    H.call(function()
      terraFight = { what = what }
      C.outAt = #H.outcomes
      W.on, W.pin = false, nil
    end),
    H.advanceStory(function() return sw(0x00BF) == 1 and inParty(TERRA) and H.hasControl() end, 120000,
      { playBattles = "tactical", fight = {} }),
    H.call(function()
      H.assertEq(terraFight.seats ~= nil, true, what .. ": TERRA's fight ($16D) came up after the second visit")
      local seated, ids = 0, {}
      for i = 0, 3 do
        local id = terraFight.seats[i]
        if id ~= 0xFF then seated = seated + 1; ids[id] = true end
      end
      local won = nil
      for k = C.outAt + 1, #H.outcomes do
        local o = H.outcomes[k]
        say(string.format("outcome: battle $%03X %s, %d seated", o.form & 0x3FF, o.kind, o.seatedN or -1))
        if o.kind == "won" then won = o end
      end
      say(string.format("TERRA's fight opened with %d seated (TERRA %s); won: %s; TERRA joined: %s", seated,
        ids[TERRA] and "among them" or "absent", tostring(won ~= nil), tostring(inParty(TERRA))))
      H.assertEq(seated, wantSeated, string.format("%s: TERRA's fight opens with %d seated", what, wantSeated))
      H.assertEq(ids[TERRA], true, what .. ": TERRA is seated in her fight")
      for _, b in ipairs(blown or {}) do
        H.assertEq(ids[b] == nil, true, string.format("%s: char $%02X, whom a BabaBreath took, is not in TERRA's fight",
          what, b))
      end
      H.assertEq(won ~= nil, true, what .. ": TERRA's fight is won")
      H.assertEq(sw(0x00BF) == 1 and inParty(TERRA), true, what .. ": TERRA joins after it ($00BF)")
    end),
  })
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
    quietFights(function() return lineFrom(C.from or 1) ~= nil end, 40000),
    H.call(function()
      local li, lc = lineFrom(C.from or 1)
      H.assertEq(li ~= nil, true, string.format("%s: the line came once he was under 20,480 HP (%s)", C.name, what))
      C.li, C.lc = li, lc
      say(string.format("the line on his turn %d at his HP %d", lc.turn, hp()))
      H.assertEq(hp() < BAND, true, C.name .. ": his HP is under 20,480 at the line")
    end),
    defendUntil(function() return lit() and markOn() end, 900),
    H.call(function()
      C.preSeats = {}
      for i = 0, 3 do C.preSeats[i] = { id = H.readByte(0x3ED8 + 2 * i), hp = H.readWord(0x3BF4 + 2 * i) } end
      H.assertEq(lit(), true, C.name .. ": battle switch 1 (the breath announced) is set after the line")
      H.assertEq(W.litBit(), true, C.name .. ": OT6_FUSE's lit bit is set for his slot")
      H.assertEq(markOn(), true, C.name .. ": the lit-fuse mark stands before his shield emblem")
    end),
  })
end

-- the breath on his next turn: two BabaBreaths, his turn's, and the battle's end
local function breathNext(what)
  return H.seqStep({
    H.call(function()
      if C.preSeats == nil then
        C.preSeats = {}
        for i = 0, 3 do C.preSeats[i] = { id = H.readByte(0x3ED8 + 2 * i), hp = H.readWord(0x3BF4 + 2 * i) } end
      end
    end),
    defendUntil(function() return #breaths(C.li) >= 2 or #W.snuffs > (C.snuffAt or 0) or denied() end, 12000),
    defendUntil(function() return false end, 900),
    H.call(function()
      local b = breaths(C.li)
      say(string.format("%d BabaBreath(s) after the line (turns %s); the battle %s", #b, (function()
        local t = {}
        for _, c in ipairs(b) do t[#t + 1] = tostring(c.turn) .. (c.retal and "c" or "") end
        return table.concat(t, ",")
      end)(), up() and "is still up" or "ended"))
      H.assertEq(#b, 2, what .. ": two BabaBreaths came after the line")
      H.assertEq(not b[1].retal and not b[2].retal, true, what .. ": both are his turn's (the fire block), not a "
        .. "counter's")
      H.assertEq(b[1].turn - C.lc.turn, 1, what .. ": the breath came on his next turn after the line")
      H.assertEq(up(), false, what .. ": the battle ended after them (end_battle)")
      -- the breath's effect: whom it took (absent from the party's seats after the battle; read in TERRA's fight)
      C.blown = {}
      for _, c in ipairs(b) do
        local t = c.tchars
        for i = 0, 3 do
          if t & (1 << i) ~= 0 and C.preSeats[i].id ~= 0xFF then C.blown[#C.blown + 1] = C.preSeats[i].id end
        end
      end
      say(string.format("[effect] the breaths took chars %s (each BabaBreath one member: targets $%02X, $%02X)",
        (function() local t = {}; for _, x in ipairs(C.blown) do t[#t + 1] = string.format("$%02X", x) end
          return table.concat(t, " ") end)(), b[1].tchars, b[2].tchars))
    end),
  })
end

local function landedTry(k)
  return H.cond(function() return C.landed == nil end, {
    open("landed", false),
    H.call(function()
      C.try, C.from, C.t0 = k, 1, H.frame
      say(string.format("try %d: %d frames of Defends first", k, 360 * (k - 1)))
    end),
    defendUntil(function() return H.frame >= C.t0 + 360 * (k - 1) end, 360 * k),
    toLine("landed"),
    H.call(function() C.snuffAt = #W.snuffs end),
    defendUntil(function() return #breaths(C.li) >= 2 or denied() end, 12000),
    H.cond(function() return denied() and #breaths(C.li) == 0 end, {
      H.call(function() say(string.format("try %d: a break of the party's own play in the fuse denied the breath; "
        .. "the next try", k)) end),
    }, {
      breathNext("landed"),
      H.call(function() C.landed = true end),
    }),
  }, {})
end
local landed = H.seqStep({
  H.call(function() C = {}; C.landed = nil end),
  landedTry(1),
  H.cond(function() return C.landed == nil end, { landedTry(2) }, {}),
  H.cond(function() return C.landed == nil end, { landedTry(3) }, {}),
  H.call(function()
    H.assertEq(C.landed, true, "landed: the two BabaBreaths came on his turn after the line, in one of three tries")
    local nRead = 0
    for _, r in ipairs(D.ptrReads) do if r.f >= C.lc.f and r.id == LINE then nRead = nRead + 1 end end
    local at, want = D.textAt(C.lc.f), D.tableAt(LINE)
    say(string.format("the line's text: %d read(s) of its table word; the window read $%06X (the table gives $%06X): %q",
      nRead, at or 0, want, at and D.decode(at) or "(nothing read)"))
    H.assertEq(nRead >= 1 and at == want, true, "landed: the window read the line's text where the table points")
    H.assertEq(D.decode(want), "He fills his lungs!{wait}", "landed: the line reads \"He fills his lungs!\"")
  end),
  H.lazy(function() return onToTerra("landed", 3, C.blown) end),
  H.call(function() say("PASS") end),
})

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
      H.assertEq(denied(), true, C.name .. ": battle switch 0 is set: the breath is denied for the fight")
    end),
    defendUntil(function() return not W.litBit() and not markOn() end, 900),
    H.call(function() H.assertEq(markOn(), false, C.name .. ": the mark is gone after the breaking hit") end),
  })
end
-- his turns after he recovers: n of them, no line and no breath
local function quietTurns(n, what)
  return H.seqStep({
    defendUntil(function() local c = W.cells(); return c ~= nil and c.ticks == 0 end, 4000),
    H.call(function() C.recTurn = #W.turns; C.recCmds = #W.cmds end),
    defendUntil(function() return #W.turns >= C.recTurn + n end, 12000),
    H.call(function()
      H.assertEq(#W.turns >= C.recTurn + n, true, string.format("%s: %d of his turns came after he recovered", what, n))
      H.assertEq(lineFrom(C.recCmds + 1), nil, what .. ": no line on his turns after the denial")
      H.assertEq(#breaths(C.recCmds + 1), 0, what .. ": no BabaBreath on his turns after the denial")
    end),
  })
end
local function crossNoBreath(what)
  return H.seqStep({
    H.call(function()
      WRITE.word(0x3BF4 + W.ent(), CROSS + 140)   -- (DECLARED: his HP just above the line, so one blow crosses it)
      say(string.format("his HP staged to %d", CROSS + 140))
    end),
    aimedFight(function() return true end, 3000),
    defendUntil(function() return false end, 900),
    H.call(function()
      local b = breaths(1)
      say(string.format("after the crossing: %d BabaBreath(s); the battle %s", #b, up() and "is still up" or "ended"))
      H.assertEq(#b, 0, what .. ": no BabaBreath: the breath was denied")
      H.assertEq(up(), false, what .. ": the crossing ended the battle (the denied breath's end)")
    end),
  })
end

local broken = H.seqStep({
  open("broken", true),
  toLine("to be broken"),
  breakInFuse(),
  quietTurns(3, "broken"),
  crossNoBreath("broken"),
  onToTerra("broken", 4, nil),
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
  end),
  aimedFight(function() return true end, 4000),
  H.waitFrames(2),
  H.call(function()
    WRITE.byte(0x3E9C + W.ent(), C.row)     -- (his own row back)
    H.assertEq(#W.breaks >= 1, true, "outside: the aimed Fight broke him")
    H.assertEq(lineFrom(1), nil, "outside: the break came before any line (the case's precondition)")
    H.assertEq(#W.snuffs, 0, "outside: a break before the line cancels nothing")
    H.assertEq(denied(), true, "outside: the break denies the breath (battle switch 0 set)")
  end),
  defendUntil(function() local c = W.cells(); return c ~= nil and c.ticks == 0 end, 4000),
  quietFights(function() return hp() < BAND end, 40000),
  quietTurns(2, "outside"),
  crossNoBreath("outside"),
  H.call(function() say("PASS") end),
})

-- burst: above the band, no line said, his HP staged under the line as a member's Fight is dispatched
local stageOnFight = nil
local burst = H.seqStep({
  open("burst", true),
  H.call(function()
    H.assertEq(hp() >= BAND and lineFrom(1) == nil, true, "burst: he stands above the band, no line said (the "
      .. "case's precondition)")
    stageOnFight = function()
      if H.readByte(0xB5) ~= 0x00 or (emu.getState()["cpu.x"] & 0xFF) >= 8 then return end
      stageOnFight = nil
      C.stagedAt = H.frame
      C.from = #W.cmds + 1
      WRITE.word(0x3BF4 + W.ent(), CROSS - 360)  -- (DECLARED: under the line, as if one burst had taken him there)
      say(string.format("his HP staged to %d as a member's Fight is dispatched", CROSS - 360))
    end
  end),
  aimedFight(function() return true end, 4000),
  defendUntil(function() return false end, 600),
  H.call(function()
    H.assertEq(C.stagedAt ~= nil, true, "burst: the staging rode a member's Fight")
    say(string.format("after the blow: his HP %d, the battle %s", hp(), up() and "is still up" or "ended"))
    H.assertEq(up(), true, "burst: the crossing blow ends nothing (the breath not denied, not yet announced)")
  end),
  defendUntil(function() return lineFrom(C.from) ~= nil end, 8000),
  H.call(function()
    local li, lc = lineFrom(C.from)
    H.assertEq(li ~= nil, true, "burst: his next turn says the line")
    H.assertEq(#breaths(C.from), 0, "burst: no BabaBreath before the line")
    C.li, C.lc = li, lc
    C.snuffAt = #W.snuffs
  end),
  breathNext("burst"),
  H.call(function() say("PASS") end),
})

-- heal: at the line, his HP staged above the band
local heal = H.seqStep({
  open("heal", true),
  toLine("to be healed"),
  H.call(function()
    WRITE.word(0x3BF4 + W.ent(), 25000)           -- (DECLARED: above the band, as a bolt he absorbs would heal him)
    say("his HP staged to 25,000 in the fuse")
    C.snuffAt = #W.snuffs
  end),
  breathNext("heal"),
  H.call(function() say("PASS") end),
})

-- The cap: five cases of about 10,000 frames, and two of TERRA's fights; 300,000 is about 2x.
H.run({ maxFrames = 300000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "Phunbaba's battle is up", 2),
  H.call(function()
    H.assertEq(W.slot() ~= nil, true, "Phunbaba ($16C, the second visit) stands at the open (phunbaba_entry)")
    local at = H.aiAttacks(PHUN, BREATH)
    H.assertEq(#at, 2, "BabaBreath is named twice in his turn script: the fire block's two (none unannounced)")
    for sp, hex in pairs(VANILLA) do
      H.assertEq(scriptHex(sp), hex, string.format("Phunbaba $%03X's scripts are vanilla's byte for byte (the first "
        .. "visit's two records, TERRA's fight)", sp))
    end
    sortParty()
    watchTerraFight()
    emu.addMemoryCallback(function() if stageOnFight then stageOnFight() end end, emu.callbackType.exec,
      H.sym("_dispatcher"), H.sym("_dispatcher"))
  end),
  landed, broken, outside, burst, heal,
  H.logStep("[phunbaba] PASS: the lungs filled under 20,480, the breath on his next turn and TERRA's fight after it, "
    .. "the break that denies it, a break before any line, a burst past both lines, and a heal in the fuse"),
})
