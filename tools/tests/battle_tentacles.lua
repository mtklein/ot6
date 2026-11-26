-- @suite savestate=tentacles_entry slow
-- battle_tentacles.lua -- the Tentacles under the boss contract (docs/design/bosses-wor.md block 1, wt/v052-tg-wor1):
-- the Seize is announced, one body a member, a break in the fuse cancels it, the member falling cancels it, and a
-- break frees the member a Tentacle holds.
--
-- Each body's script (ai_script.asm AIScript::_283, _316, _317, _318; species $11B, $13C, $13D, $13E): on its first
-- turn that finds a Slowed member (Entwine, its rotation's), with no hostage of its own, it claims that member's seat
-- (if_seize_free's claim, conditional $00, Ot6SeizeCond: the seat's monster switch 0-3, set as the turn's script is
-- read), says "It coils to seize!" (battle dialogue $A0) and glows, a turn of its own; its next turn's fire block,
-- which stands first, Seizes that seat (attack $C8, command $0C) whatever its Slow reads then.  No body claims a seat
-- another standing body has claimed, or one whose member cannot be held (dead, stone, a zombie, gone, out of the
-- fight, held already: Ot6SeatHoldable).  Seize is not physical and never misses (MagicProp $C8: no hit roll), so an
-- announced Seize holds.  A break while it is lit cancels it (Ot6FuseTbl's rows, one a body a seat: the claim goes,
-- the script forgets its `wait`); so does the member falling or leaving while it is lit (Ot6SeizeFell from the
-- HUD's poll, and the fire block's own test on the move's turn: the one cancel that is not a break, as the body's own
-- death is the one loss).  Every break of a Tentacle, lit or not, frees the member it holds (OT6_FUSE_RELEASE,
-- Ot6FuseRelease: Discard's release), so the member acts again.
--
-- Boots tentacles_entry (gen_wor_edgar: the Tentacles' battle, event battle 84, as it comes up; CELES, SABIN and
-- EDGAR in seats 1-3, seat 4 empty; seat 4 with a fourth member is battle_tentacles4's).  Each case plays from a
-- snapshot at the battle's open; the party Defends, and Entwine's Slow comes in the Tentacles' own time unless a case
-- stages it.  Watched in every case (and asserted at the end):
--   the claim tests: every test Ot6SeizeCond makes (its entry: seat, mode, the body) against the state it reads (the
--             seat's member holdable; another standing body's claim on it) and its answer (the carry at
--             Ot6AICondSeize's return): every answer the rule's, and a claim refused for a seat another standing body
--             holds the claim on met at least once (the refusals for a member held, dead or gone are logged: on this
--             fixture such a member fails the block's Slow test first);
--   one claim a seat: on no frame do two standing bodies claim one seat;
--   the holds: every Seize dispatched holds its seat's member, that body its seize attacker (holds counted, not
--             dispatches).
--   landed    nothing staged and nothing held: a body's line once a member is Slowed; its claim, lit bit and mark;
--             the Seize on its next turn, on that member's seat, and the member held.  Then the hold's effect over
--             the next 900 frames: the member's HP drain per tick and the body's gain (the drain, vanilla's).
--   broken    (DECLARED: every body's gauge held at 63, and each standing member's HP at 9,999) at a body's line its
--             gauge staged to 1 with every class and an aimed Fight once its mark is up breaks it: the cancel fires,
--             the claim is clear, its script waits nowhere and the mark goes; it Seizes nothing on its turns back
--             before it announces again, and when it does the Seize follows and holds.
--   outside   (DECLARED as broken) a body broken before any line of its own: nothing is cancelled and its cells stand;
--             and the release on a body that holds no one is a no-op (Ot6FuseRelease ran; every seat's seize attacker
--             and $3403 as they were).
--   release   (DECLARED as broken, and CELES's Slow written in seat 1, the others' cleared) once a body holds a member, that body's gauge staged to 1 with every class and
--             another member's aimed Fight breaks it: Ot6FuseRelease runs and the Broken body's own Discard on that
--             member is dispatched (queued as a counter at the break, Ot6QueueDiscard): the member's seize attacker
--             is cleared, its seized bit ($3403) is back and the body's hold switch is clear; the freed member then
--             acts (a command of its own is dispatched).  Screenshots at the break, at the release, 120 and 600 frames
--             after it, and as the freed member acts (tentacles_release_*.png: the freed member's sprite back in its
--             place).
--   one seat  (DECLARED as broken, and CELES's Slow written in seat 1 each frame until a body claims it) the first
--             claim on seat 1, and at least one other body's claim test on it while it stands: refused, and no line
--             of that body follows; the claimant's Seize holds.
--   fell      (DECLARED as one seat, then at the line the claimed member's HP to 0 and Wound set: the engine's own
--             corpse shape) the fuse is snuffed within frames (Ot6SeizeFell -> Ot6FuseSnuff), the claim clear, the
--             mark gone, and no Seize from that body on that seat; the dead member, still Slowed, is claimed by no
--             body after.  Seat 4 (empty) Slowed by the staging too: no body claims it.
--   dies      (DECLARED as one seat, then at the line the claimant's HP to 1) an aimed Fight kills the claimant in
--             its fuse: no Seize from it, and another body's claim on that seat follows (a body that dies with a claim
--             claims nothing).
-- DECLARED SYNTHETIC SETUP (tools/state_write_waivers.txt): the writes above, through the suite's two writers.  A
-- mechanism test, not play (the landed case writes nothing).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "broken: the break during the fuse cancels it"; tent_no_release (every Tentacle row's RELEASE flag off) at
-- "release: the member's seize attacker is cleared"; claim_never (Ot6SeizeCond's claim store skipped) at "one seat: no
-- two standing bodies claim one seat"; claim_dead (the claim test counts a dead body's claim) at "dies: another body
-- claims the seat"; fell_never (Ot6SeizeFell keeps every claim) at "fell: the fuse is snuffed"; holdable_dead (the
-- holdable test skips the status test) at "the claim tests: every answer is the rule's".
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (the gauges, the party's held HP, the stagings named above; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/tentacles_entry.mss.lua"

local SPECIES = { 0x11B, 0x13C, 0x13D, 0x13E }
local IS_TENT = { [0x11B] = true, [0x13C] = true, [0x13D] = true, [0x13E] = true }
local SEIZE, LINE = 0xC8, 0xA0
local Ws = {}
for _, sp in ipairs(SPECIES) do Ws[#Ws + 1] = H.fuseWatch(sp, WRITE) end
local S, C = {}, {}
local function say(s) H.log(string.format("[tentacles] f%d %s: %s", H.frame, C.name or "-", s)) end
local function up() return H.battleLoadStarted() end
local function rb(a) return H.readByte(a) end

-- every party command dispatched, by seat: { f, seat, cmd }
local acts = {}
local releases = {}
local holdGauges = false
-- (DECLARED) per-frame stagings: Slow written on these seats (seat index 0-3 -> true)
local slowSeats = {}
-- the claim tests: { f, ent, seat, mode, hold, other, why, got }
local tests, pending = {}, nil
local claimClash = 0           -- frames on which two standing bodies claimed one seat
local seizes = {}              -- { f, ent, seat, held }

local function standingBody(e)
  return IS_TENT[H.readWord(0x57C0 + (e - 8))] and (rb(0x3AA0 + e) & 1) == 1 and (rb(0x3EE4 + e) & 0xC2) == 0
end
-- Ot6SeatHoldable, read from RAM: seat i (0-3)
local function holdable(i)
  local m = rb(0x3018 + 2 * i)
  local why = nil
  if (rb(0x3AA0 + 2 * i) & 1) == 0 then why = "absent"
  elseif (rb(0x3EE4 + 2 * i) & 0xC2) ~= 0 then why = "dead"
  elseif (m & rb(0x3A74)) == 0 then why = "not standing"
  elseif (m & rb(0x3F2C)) ~= 0 then why = "out of the fight"
  elseif (m & rb(0x3403)) == 0 then why = "held" end
  return why == nil, why
end
local function heldBy(seat) return rb(0x3359 + 2 * seat) end

local function watchers()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 then acts[#acts + 1] = { f = H.frame, seat = x // 2, cmd = rb(0xB5) } end
    if x >= 8 and rb(0xB5) == 0x0C and rb(0xB6) == SEIZE then
      local t = rb(0xB8)
      local seat = t == 1 and 0 or t == 2 and 1 or t == 4 and 2 or t == 8 and 3 or nil
      -- (a body that holds already: its turn's Seize on its hostage is the drain, vanilla's, not a new hold)
      seizes[#seizes + 1] = { f = H.frame, ent = x, seat = seat, tchars = t, drain = rb(0x3358 + x) ~= 0xFF }
    end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    releases[#releases + 1] = { f = H.frame, ent = y, held = rb(0x3358 + y), r3403 = rb(0x3403), att = (function()
      local t = {}
      for i = 0, 3 do t[i] = heldBy(i) end
      return t
    end)() }
    H.log(string.format("[tentacles] f%d Ot6FuseRelease for the body at $%02X (it holds $%02X)", H.frame, y,
      rb(0x3358 + y)))
  end, emu.callbackType.exec, H.sym("Ot6FuseRelease"), H.sym("Ot6FuseRelease"))
  -- the claim tests: the state at Ot6SeizeCond's entry, the answer at Ot6AICondSeize's return (the `rts` after its
  -- four-byte jsl)
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    local seat, mode = rb(0x3A2E), rb(0x3A2F)
    if seat < 1 or seat > 4 then pending = nil; return end
    local i = seat - 1
    local h, why = holdable(i)
    local other = nil
    for e = 8, 18, 2 do
      if e ~= y and standingBody(e) and (rb(0x3DAC + e) & (1 << i)) ~= 0 then other = e end
    end
    pending = { f = H.frame, ent = y, seat = seat, mode = mode, hold = h, why = why, other = other,
      case = C.name }
  end, emu.callbackType.exec, H.sym("Ot6SeizeCond"), H.sym("Ot6SeizeCond"))
  local ret = H.sym("Ot6AICondSeize") + 4
  emu.addMemoryCallback(function()
    if pending == nil then return end
    pending.got = (emu.getState()["cpu.ps"] & 0x01) == 1
    local t = pending
    pending = nil
    t.want = t.hold and (t.mode == 1 or t.other == nil)
    tests[#tests + 1] = t
    H.log(string.format("[claim] f%d body $%02X tests seat %d (%s): member %s%s -> %s (the rule: %s)", t.f, t.ent,
      t.seat, t.mode == 0 and "the announce's claim" or "the fire block's",
      t.hold and "holdable" or ("not holdable: " .. t.why),
      t.other and string.format(", claimed by the body at $%02X", t.other) or "", t.got and "continue" or "refused",
      t.want and "continue" or "refused"))
  end, emu.callbackType.exec, ret, ret)
  emu.addEventCallback(function()
    -- (DECLARED) the gauges held at 63 in the staged cases, but the one a case breaks
    if holdGauges then
      for _, W in ipairs(Ws) do
        local e = W.ent()
        if e and e ~= C.breaking and rb(0x3E88 + e) == 0 and rb(0x3E38 + e) ~= 63 then WRITE.byte(0x3E38 + e, 63) end
      end
    end
    -- (DECLARED) the release case: CELES's Slow written in seat 1 and the other members' Slow cleared, so one member
    -- is held and the others stay free to break its holder (the replay's draw had three bodies claim three seats and
    -- seize all three before the break, build/attempts/wt/v052-tg-wor1/r2/gate1.log)
    if C.unslow then
      for i = 0, 3 do
        if not slowSeats[i] and heldBy(i) == 0xFF and (rb(0x3EF8 + 2 * i) & 0x04) ~= 0 then WRITE.byte(0x3EF8 + 2 * i, rb(0x3EF8 + 2 * i) & 0xFB) end
      end
    end
    -- (DECLARED) a staged Slow
    for i, on in pairs(slowSeats) do
      if on and (rb(0x3EF8 + 2 * i) & 0x04) == 0 then WRITE.byte(0x3EF8 + 2 * i, rb(0x3EF8 + 2 * i) | 0x04) end
    end
    -- one claim a seat
    if up() then
      for i = 0, 3 do
        local n = 0
        for e = 8, 18, 2 do if standingBody(e) and (rb(0x3DAC + e) & (1 << i)) ~= 0 then n = n + 1 end end
        if n > 1 then
          claimClash = claimClash + 1
          if claimClash <= 5 then H.log(string.format("[claim] f%d seat %d claimed by %d standing bodies", H.frame,
            i + 1, n)) end
        end
      end
    end
    -- each Seize: held by its body within 600 frames, or not
    for _, s in ipairs(seizes) do
      if s.held == nil and s.drain then s.held = true
      elseif s.held == nil then
        if s.seat ~= nil and heldBy(s.seat) == s.ent then
          s.held = true
          H.log(string.format("[hold] f%d the Seize of f%d by $%02X holds seat %d", H.frame, s.f, s.ent, s.seat + 1))
        elseif H.frame - s.f > 600 or not up() then
          s.held = false
          H.log(string.format("[hold] f%d the Seize of f%d by $%02X on targets $%02X holds no one", H.frame, s.f,
            s.ent, s.tchars))
        end
      end
    end
  end, emu.eventType.endFrame)
end

-- the first line since index set `from` (one start index a watcher), and its watcher
local function firstLine(from)
  local best, bw, bi = nil, nil, nil
  for k, W in ipairs(Ws) do
    local i, c = W.find(0x21, LINE, from and from[k] or 1)
    if i and (best == nil or c.f < best.f) then best, bw, bi = c, W, i end
  end
  return best, bw, bi
end
local function seizeFrom(W, i)
  for k = i or 1, #W.cmds do
    local c = W.cmds[k]
    if c.cmd == 0x0C and c.arg == SEIZE then return k, c end
  end
  return nil
end
local function marks() local t = {}; for k, W in ipairs(Ws) do t[k] = #W.cmds + 1 end; return t end
local function claimOf(W)
  local e = W.ent()
  if not e then return nil end
  local sw = rb(0x3DAC + e) & 0x0F
  return sw == 1 and 0 or sw == 2 and 1 or sw == 4 and 2 or sw == 8 and 3 or nil
end
local function lineOnSeat(seat, fromF)
  for _, W in ipairs(Ws) do
    for _, c in ipairs(W.cmds) do
      if c.cmd == 0x21 and c.arg == LINE and c.f >= fromF and c.seat == seat then return W, c end
    end
  end
  return nil
end

local function defendUntil(pred, max, noCare)
  return H.lazy(function()
    local t0 = H.frame
    return H.kitBattle({}, { idle = "defend", care = not noCare, maxFrames = max + 600,
      giveUp = function() return not up() or pred() or H.frame - t0 >= max end })
  end)
end
local function freeMember(notSeat)
  local who, plain = nil, nil
  for i = 0, 3 do
    local id = rb(0x3ED8 + 2 * i)
    if id ~= 0xFF and i ~= notSeat and H.readWord(0x3BF4 + 2 * i) > 0
       and (rb(0x3EE4 + 2 * i) & 0xC2) == 0 and heldBy(i) == 0xFF then
      who = who or id
      -- (one whose hands carry no element first: an absorbed hit takes no shield; readyBreak, below)
      if plain == nil and (H.weaponElement(rb(0x1600 + 37 * id + 0x1F))
          | H.weaponElement(rb(0x1600 + 37 * id + 0x20))) == 0 then plain = id end
    end
  end
  return plain or who
end
local function aimedFight(W, when, notSeat, max, done)
  return H.lazy(function()
    local who = freeMember(notSeat)
    H.assertEq(who ~= nil, true, C.name .. ": a free member stands to aim the Fight")
    C.nBreaks = #W.breaks
    local t0 = H.frame
    return H.kitBattle({ { who = who, cmd = 0x00, boost = 0, slot = W.slot(), confirmWhen = when } },
      { idle = "defend", care = false, maxFrames = max + 600,
        giveUp = function()
          return not up() or (done and done()) or (done == nil and #W.breaks > C.nBreaks) or H.frame - t0 >= max
        end })
  end)
end
local function stageBreak(W)
  local e = W.ent()
  C.breaking = e
  WRITE.byte(0x3E9C + e, 0x3F)
  WRITE.byte(0x3E38 + e, 1)         -- (DECLARED: the gauge to 1, every class a key)
  say(string.format("$%03X's gauge staged to 1, every class a key", W.species))
end

local function open(name, staged)
  return H.seqStep({
    H.cond(function() return S.req == nil end, { H.fuseSnap(S), H.waitFrames(1) }, { H.fuseRestore(S, name) }),
    H.call(function()
      C = { name = name, f0 = H.frame }
      for _, W in ipairs(Ws) do W.reset(); W.on = true; W.pin = staged and { party = true } or nil end
      holdGauges = staged
      slowSeats = {}
      acts, releases = {}, {}
      say("from the battle's open")
    end),
    H.waitUntil(function() return H.battleActive() and Ws[1].ent() ~= nil end, 3000, name .. ": the Tentacles up", 2),
  })
end

-- the first line since index set `from` whose body's claim stands on `seat` (nil: any)
local function lineClaiming(from, seat)
  local best, bw, bi = nil, nil, nil
  for k, W in ipairs(Ws) do
    local i, c = W.find(0x21, LINE, from and from[k] or 1)
    while i ~= nil do
      if claimOf(W) ~= nil and (seat == nil or claimOf(W) == seat) and seizeFrom(W, i) == nil
         and (best == nil or c.f < best.f) then best, bw, bi = c, W, i end
      i, c = W.find(0x21, LINE, i + 1)
    end
  end
  return best, bw, bi
end
-- to a line: the party Defends until one body announces; C.W the body, C.seat the seat it claimed
local function toLine(name, pickSeat)
  return H.seqStep({
    defendUntil(function() return lineClaiming(C.from, pickSeat) ~= nil end, 40000),
    H.call(function()
      local lc, W, li = lineClaiming(C.from, pickSeat)
      H.assertEq(lc ~= nil, true, name .. ": a Tentacle announced (\"It coils to seize!\") once a member was Slowed")
      C.W, C.li, C.lc = W, li, lc
    end),
    defendUntil(function() return C.W.litBit() and C.W.vramMark() == C.W.FUSE_WORD end, 900),
    H.call(function()
      local W = C.W
      C.seat = claimOf(W)
      C.lc.seat = C.seat
      say(string.format("$%03X announced on its turn %d; its claim: seat %s; seat statuses 3: %s", W.species,
        C.lc.turn, tostring(C.seat and C.seat + 1), (function()
          local t = {}
          for i = 0, 3 do t[#t + 1] = string.format("$%02X", rb(0x3EF8 + 2 * i)) end
          return table.concat(t, " ")
        end)()))
      H.assertEq(C.seat ~= nil, true, name .. ": the announce claimed exactly one seat (monster switch 0-3)")
      H.assertEq(W.litBit(), true, name .. ": OT6_FUSE's lit bit is set for the announcing body's slot")
      H.assertEq(W.vramMark(), W.FUSE_WORD, name .. ": the lit-fuse mark stands before the announcing body's emblem")
    end),
  })
end

-- (Seize never misses: MagicProp $C8 is not physical and has no hit roll, and the claim refuses a member that cannot
-- be held, so the announced Seize holds its member)
local function seizeLands(name)
  return H.seqStep({
    defendUntil(function() return seizeFrom(C.W, C.li) ~= nil or #C.W.snuffs > (C.snuffAt or 0) end, 12000),
    defendUntil(function() return heldBy(C.seat) == C.W.ent() or #C.W.snuffs > (C.snuffAt or 0) end, 600),
    H.call(function()
      local W = C.W
      local si, sc = seizeFrom(W, C.li)
      H.assertEq(si ~= nil, true, name .. ": the Seize was dispatched after the announce")
      say(string.format("Seize on its turn %d, targets $%02X; seat %d held by $%02X; $%03X's switches $%02X", sc.turn,
        sc.tchars, C.seat + 1, heldBy(C.seat), W.species, rb(0x3DAC + W.ent())))
      H.assertEq(sc.turn - C.lc.turn, 1, name .. ": the Seize came on the body's next turn after the announce")
      H.assertEq(sc.tchars & 0x0F, 1 << C.seat, name .. ": the Seize was queued on the announced seat")
      H.assertEq(rb(0x3DAC + W.ent()) & 0x0F, 0, name .. ": the claim is clear after the Seize")
      H.assertEq(heldBy(C.seat), W.ent(), name .. ": the Seize holds the member (that body its seize attacker)")
      H.assertEq(rb(0x3DAC + W.ent()) & 0x80, 0x80, name .. ": the body holds (switch 7) the member it Seized")
      C.si = si
    end),
  })
end

-- landed: the first announce, its Seize holds; then the hold's effect
local landed = H.seqStep({
  open("landed", false),
  H.call(function() C.from = marks() end),
  toLine("landed"),
  seizeLands("landed"),
  H.call(function()
    local e = C.W.ent()
    C.eff = { f = H.frame, hp = H.readWord(0x3BF4 + 2 * C.seat), mhp = H.readWord(0x3BF4 + e), drops = {}, last =
      H.readWord(0x3BF4 + 2 * C.seat), gains = 0 }
  end),
  H.lazy(function()
    -- the hold's effect, read each frame for 900 frames: each fall of the member's HP while held is a tick
    local E = C.eff
    local e, seat = C.W.ent(), C.seat
    local id = emu.addEventCallback(function()
      if E.done then return end
      local hp = H.readWord(0x3BF4 + 2 * seat)
      if hp < E.last and heldBy(seat) == e then E.drops[#E.drops + 1] = { f = H.frame, d = E.last - hp } end
      E.last = hp
    end, emu.eventType.endFrame)
    E.cb = id
    return defendUntil(function() return H.frame - E.f >= 900 or heldBy(seat) ~= e end, 1000)
  end),
  H.call(function()
    local E = C.eff
    E.done = true
    local t = {}
    for k = 1, math.min(#E.drops, 12) do t[#t + 1] = string.format("f%d -%d", E.drops[k].f, E.drops[k].d) end
    local mhp = C.W.ent() and H.readWord(0x3BF4 + C.W.ent()) or -1
    say(string.format("[effect] the hold of seat %d by $%03X over %d frames: the member's HP %d -> %d (%d falls: %s); "
      .. "the body's HP %d -> %d; still held: %s", C.seat + 1, C.W.species, H.frame - E.f, E.hp, E.last, #E.drops,
      table.concat(t, ", "), E.mhp, mhp, tostring(heldBy(C.seat) == C.W.ent())))
    say("PASS")
  end),
})

-- the seats held, and by whom: { [seat] = holder entity }
local function heldSeats()
  local t = {}
  for i = 0, 3 do if rb(0x3ED8 + 2 * i) ~= 0xFF and heldBy(i) ~= 0xFF then t[i] = heldBy(i) end end
  return t
end
-- a breaker ready before its moment: a free member (not Slowed where one can be, so no Tentacle seizes it first)
-- waits at its command window (kitBattle's openWhen: the battle runs on) until pick() names the body to break; that
-- body's gauge is then staged (stageBreak) and the Fight aimed at it (slotFn).  Ends once that body is broken, or
-- giveUp() says the moment has passed.
-- (and one whose hands carry no element where one stands: each Tentacle absorbs elements -- $11B fire, $13C ice and
-- water, $13D and $13E bolt, earth and water -- and an absorbed hit heals, taking no shield: on wt/v052-tg-wor1's
-- replay CELES's fire blades took nothing off $11B's staged gauge, build/attempts/wt/v052-tg-wor1/regen1/red/
-- battle_tentacles-release-red.log)
local function readyBreak(pick, giveUp, max, stage, done)
  return H.lazy(function()
    local best, bestRank = nil, -1
    for i = 0, 3 do
      local id = rb(0x3ED8 + 2 * i)
      if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and (rb(0x3EE4 + 2 * i) & 0xC2) == 0
         and heldBy(i) == 0xFF then
        local el = H.weaponElement(rb(0x1600 + 37 * id + 0x1F)) | H.weaponElement(rb(0x1600 + 37 * id + 0x20))
        local rank = (el == 0 and 2 or 0) + ((rb(0x3EF8 + 2 * i) & 0x04) == 0 and 1 or 0)
        say(string.format("breaker candidate char $%02X (seat %d): hand elements $%02X, status 3 $%02X: rank %d", id,
          i + 1, el, rb(0x3EF8 + 2 * i), rank))
        if rank > bestRank then best, bestRank = id, rank end
      end
    end
    local who = best
    H.assertEq(who ~= nil, true, C.name .. ": a free member stands to be the breaker")
    C.breakerSeat = nil
    for i = 0, 3 do if rb(0x3ED8 + 2 * i) == who then C.breakerSeat = i end end
    if C.keepW == nil then C.W, C.staged = nil, false end
    say(string.format("char $%02X waits at its command window to break the body", who))
    local t0 = H.frame
    return H.kitBattle({ { who = who, cmd = 0x00, boost = 0,
        slotFn = function() return C.W and C.W.slot() end,
        openWhen = function()
          if C.staged then return true end
          local W = pick()
          if W == nil then return false end
          C.W, C.staged = W, true
          C.nBreaks = #W.breaks
          ;(stage or stageBreak)(W)
          return true
        end } },
      { idle = "defend", care = false, maxFrames = max + 600,
        giveUp = function()
          return not up() or (C.W ~= nil and C.staged and (done and done() or (done == nil and #C.W.breaks > C.nBreaks)))
            or (giveUp ~= nil and giveUp())
            or (C.breakerSeat ~= nil and heldBy(C.breakerSeat) ~= 0xFF) or H.frame - t0 >= max
        end })
  end)
end

-- (up to three tries: a draw can bring the announcing body's Seize before the breaker's Fight; the case then aims at
-- the next announce, which the other bodies bring: build/attempts/wt/v052-tg-wor1/dev/)
local function brokenTry(k)
  return H.cond(function() return C.done == nil end, {
    H.call(function()
      C.from = C.from or marks()
      C.tries = k
      say(string.format("try %d: the breaker waits for a body's line", k))
    end),
    readyBreak(function()
      local lc, W, li = firstLine(C.from)
      if lc == nil or not W.litBit() or seizeFrom(W, li) ~= nil then return nil end
      C.li, C.lc = li, lc
      return W
    end, nil, 40000),
    H.waitFrames(2),
    H.call(function()
      local W = C.W
      H.assertEq(W ~= nil and #W.breaks > C.nBreaks, true, "broken: the aimed Fight took the announcing body's last "
        .. "shield")
      C.brk = W.breaks[#W.breaks]
      C.breaking = nil
      local si, sc = seizeFrom(W, C.li)
      if sc ~= nil and sc.f <= C.brk.f then
        say(string.format("try %d: $%03X's Seize came before the break; the case aims at the next announce", k,
          W.species))
        C.from = marks()
        return
      end
      C.done = true
    end),
  }, {})
end
local broken = H.seqStep({
  open("broken", true),
  H.call(function() C.done = nil; C.from = nil end),
  brokenTry(1), brokenTry(2), brokenTry(3),
  H.call(function()
    H.assertEq(C.done, true, "broken: a break landed inside a body's fuse in one of three tries")
    local W = C.W
    local post = W.cells()
    say(string.format("broken: $%03X, %d cancel(s); %s", W.species, #W.snuffs, W.cellsLine(post)))
    H.assertEq(#W.snuffs >= 1 and W.snuffs[#W.snuffs].f >= C.brk.f, true, "broken: the break during the fuse cancels "
      .. "it (Ot6FuseSnuff fired at the break)")
    H.assertEq(post.blk, 0xFF, "broken: its script waits nowhere after the cancel ($3240 = $FF)")
    H.assertEq(post.mvar & 0x0F, 0, "broken: the claim is clear after the cancel")
    C.cmdsAt = #W.cmds
  end),
  defendUntil(function() return not C.W.litBit() and C.W.vramMark() ~= C.W.FUSE_WORD end, 1500),
  H.call(function() H.assertEq(C.W.vramMark() ~= C.W.FUSE_WORD, true, "broken: the mark is gone after the break") end),
  defendUntil(function() local c = C.W.cells(); return c == nil or c.ticks == 0 end, 4000),
  -- earned again: its next line, then its Seize; no Seize before that line
  defendUntil(function() return C.W.find(0x21, LINE, C.cmdsAt + 1) ~= nil end, 40000),
  H.call(function()
    local W = C.W
    local li = W.find(0x21, LINE, C.cmdsAt + 1)
    local si = seizeFrom(W, C.cmdsAt + 1)
    H.assertEq(li ~= nil, true, "broken: the body announced again (a Slowed member found again)")
    H.assertEq(si == nil or si > li, true, "broken: no Seize between the cancel and its next announce")
    C.li, C.lc = li, W.cmds[li]
    C.snuffAt = #W.snuffs
  end),
  defendUntil(function() return claimOf(C.W) ~= nil or seizeFrom(C.W, C.li) ~= nil end, 900),
  H.call(function()
    C.seat = claimOf(C.W)
    H.assertEq(C.seat ~= nil, true, "broken: the second announce claimed one seat")
  end),
  seizeLands("broken (after the second announce)"),
  H.call(function() say("PASS") end),
})

local outside = H.seqStep({
  open("outside", true),
  H.call(function()
    -- the body to break: one with no line yet (any, at the open), holding no one
    C.W = Ws[1]
    C.pre = C.W.cells()
    C.relAt = #releases
    stageBreak(C.W)
  end),
  H.lazy(function() return aimedFight(C.W, function() return true end, nil, 6000) end),
  H.waitFrames(2),
  H.call(function()
    local W = C.W
    H.assertEq(#W.breaks > C.nBreaks, true, "outside: the aimed Fight broke the body")
    C.breaking = nil
    H.assertEq(W.find(0x21, LINE, 1) == nil, true, "outside: the break came before any line of its own")
    local pre, post = W.breaks[#W.breaks].pre, W.cells()
    H.assertEq(#W.snuffs, 0, "outside: a break before the line cancels nothing")
    H.assertEq(string.format("%02X %04X %02X", post.blk, post.at, post.mvar & 0x0F),
      string.format("%02X %04X %02X", pre.blk, pre.at, pre.mvar & 0x0F),
      "outside: the break left its script's cells and its claims as they were")
    -- the release on a body that holds no one: a no-op
    local rel = releases[#releases]
    H.assertEq(#releases > C.relAt and rel.ent == W.ent(), true, "outside: Ot6FuseRelease ran for the broken body")
    H.assertEq(rel.held, 0xFF, "outside: the broken body held no one (its seize target $FF)")
    local after = {}
    for i = 0, 3 do after[i] = heldBy(i) end
    H.assertEq(string.format("%02X %02X %02X %02X / %02X", after[0], after[1], after[2], after[3], rb(0x3403)),
      string.format("%02X %02X %02X %02X / %02X", rel.att[0], rel.att[1], rel.att[2], rel.att[3], rel.r3403),
      "outside: the release on a body that holds no one changed nothing (every seat's seize attacker, $3403)")
    say("PASS")
  end),
})

-- the release's breaker: its moment is the first member held (whichever body holds it).  (A breaker who is the one
-- seized cannot act -- on wt/v052-tg-wor1's replay the Seize took CELES, the breaker waiting at her window, and her
-- Fight was dropped, build/attempts/wt/v052-tg-wor1/regen1/red/battle_tentacles-release-red.log -- so a held breaker
-- hands the break to a free member, the same holder still staged)
local function releasePick()
  if C.W ~= nil and C.staged then return C.W end
  for seat, ent in pairs(heldSeats()) do
    for _, W in ipairs(Ws) do
      if W.ent() == ent then C.heldSeat = seat; return W end
    end
  end
  return nil
end
local function releaseTry(k)
  return H.cond(function() return C.W == nil or #C.W.breaks <= (C.nBreaks or 0) end, {
    H.call(function()
      if k > 1 then
        say(string.format("try %d: the breaker was seized; a free member breaks the holder", k))
        C.keepW = true
      end
    end),
    readyBreak(releasePick, nil, 60000),
  }, {})
end
local release = H.seqStep({
  open("release", true),
  H.call(function() C.relAt = #releases; C.keepW = nil; C.unslow = true; slowSeats = { [0] = true } end),
  releaseTry(1), releaseTry(2), releaseTry(3), releaseTry(4), releaseTry(5),
  H.waitFrames(2),
  H.call(function()
    local W = C.W
    H.assertEq(W ~= nil and #W.breaks > C.nBreaks, true, "release: the aimed Fight broke the holding body")
    C.breaking = nil
    C.brkF = W.breaks[#W.breaks].f
    H.screenshot("tentacles_release_break")
    local rel = releases[#releases]
    say(string.format("$%03X held seat %d; after the break: the seat's seize attacker $%02X, $3403 $%02X, the body's "
      .. "switches $%02X; Ot6FuseRelease ran %d time(s) since the open", W.species, C.heldSeat + 1, heldBy(C.heldSeat),
      rb(0x3403), rb(0x3DAC + W.ent()), #releases - C.relAt))
    H.assertEq(#releases > C.relAt and rel.ent == W.ent() and rel.held == 2 * C.heldSeat, true,
      "release: Ot6FuseRelease ran for the broken body, which held the member")
    C.cmdsAtBreak = #W.cmds
  end),
  -- the release is the body's own Discard, queued as a counter at the break (Ot6QueueDiscard): its stores and its
  -- animation, which carries the member back to its place
  defendUntil(function() return heldBy(C.heldSeat) == 0xFF end, 600),
  H.call(function()
    local W = C.W
    local di, dc = W.find(0x0C, 0xDB, C.cmdsAtBreak + 1)
    say(string.format("the Discard: %s; the seat's seize attacker $%02X, $3403 $%02X, the body's switches $%02X",
      di and string.format("dispatched at f%d (%d frames after the break), targets $%02X, a counter: %s", dc.f,
        dc.f - C.brkF, dc.tchars, tostring(dc.retal)) or "NOT dispatched", heldBy(C.heldSeat), rb(0x3403),
      rb(0x3DAC + W.ent())))
    H.assertEq(di ~= nil and dc.tchars == (1 << C.heldSeat), true, "release: the broken body's Discard is dispatched "
      .. "on the member it held (the release, with its animation)")
    H.assertEq(heldBy(C.heldSeat), 0xFF, "release: the member's seize attacker is cleared")
    H.assertEq(rb(0x3403) & (1 << C.heldSeat), 1 << C.heldSeat, "release: the member is no longer seized "
      .. "($3403's bit back)")
    H.assertEq(rb(0x3DAC + W.ent()) & 0x80, 0, "release: the body's hold switch (7) is clear")
    C.actsAt = #acts
    H.screenshot("tentacles_release_discard")
  end),
  H.waitFrames(120),
  H.call(function() H.screenshot("tentacles_release_after120") end),
  H.waitFrames(480),
  H.call(function() H.screenshot("tentacles_release_after600") end),
  H.waitFrames(3),
  defendUntil(function()
    for k = C.actsAt + 1, #acts do if acts[k].seat == C.heldSeat then return true end end
    return false
  end, 4000),
  H.call(function()
    local a = nil
    for k = C.actsAt + 1, #acts do if acts[k].seat == C.heldSeat and a == nil then a = acts[k] end end
    H.assertEq(a ~= nil, true, "release: the freed member acts again (a command of its own is dispatched)")
    say(string.format("the freed member (seat %d) dispatched command $%02X at f%d, %d frames after the break",
      C.heldSeat + 1, a.cmd, a.f, a.f - C.brkF))
    H.screenshot("tentacles_release_acts")
  end),
  H.waitFrames(3),
  H.call(function() say("PASS") end),
})

-- one seat: CELES's Slow written in seat 1 until a body claims it; another body's claim test on it while it stands
-- is refused
local function testsOn(seat, fromF, filter)
  local t = {}
  for _, x in ipairs(tests) do if x.seat == seat and x.f >= fromF and (filter == nil or filter(x)) then t[#t + 1] = x end end
  return t
end
local oneSeat = H.seqStep({
  open("one seat", true),
  H.call(function() slowSeats = { [0] = true }; C.from = marks() end),
  toLine("one seat", 0),
  H.call(function() C.claimF = C.lc.f; C.snuffAt = #C.W.snuffs; slowSeats = {} end),
  defendUntil(function()
    return #testsOn(1, C.claimF, function(x) return x.mode == 0 and x.other ~= nil end) >= 1
      or seizeFrom(C.W, C.li) ~= nil
  end, 12000),
  H.call(function()
    local refused = testsOn(1, C.claimF, function(x) return x.mode == 0 and x.other ~= nil end)
    say(string.format("%d other bodies' claim test(s) on seat 1 while $%03X's claim stood", #refused, C.W.species))
    C.refused = refused
  end),
  H.cond(function() return #C.refused == 0 end, {
    -- (the draw brought the claimant's Seize before another body's turn: the hold then refuses them as held)
    H.call(function() say("no other body's turn came inside the fuse; the held member's tests are read instead") end),
  }, {}),
  seizeLands("one seat"),
  defendUntil(function() return #testsOn(1, C.claimF, function(x) return x.mode == 0 and x.ent ~= C.W.ent() end)
    >= 1 end, 12000),
  H.call(function()
    local t = testsOn(1, C.claimF, function(x) return x.mode == 0 and x.ent ~= C.W.ent() end)
    H.assertEq(#t >= 1, true, "one seat: another body tested a claim on seat 1 after the claimant's")
    for _, x in ipairs(t) do
      H.assertEq(x.got, false, string.format("one seat: the body at $%02X's claim on seat 1 at f%d is refused (%s)",
        x.ent, x.f, x.other and "claimed by another" or (x.why or "?")))
    end
    for _, W in ipairs(Ws) do
      if W ~= C.W then
        for _, c in ipairs(W.cmds) do
          if c.cmd == 0x21 and c.arg == LINE and c.f > C.claimF and c.f < H.frame then
            H.assertEq(heldBy(0) ~= W.ent(), true, "one seat: no other body's line ended in a hold on seat 1")
          end
        end
      end
    end
    H.assertEq(claimClash, 0, "one seat: no two standing bodies claim one seat (on any frame so far)")
    say("PASS")
  end),
})

-- fell: at the line, the claimed member is felled (DECLARED: HP 0, Wound): the fuse is snuffed
local fell = H.seqStep({
  open("fell", true),
  H.call(function() slowSeats = { [0] = true, [3] = true }; C.from = marks() end),
  toLine("fell", 0),
  H.call(function()
    C.snuffAt = #C.W.snuffs
    C.fellF = H.frame
    WRITE.word(0x3BF4, 0)
    WRITE.byte(0x3EE4, rb(0x3EE4) | 0x80)       -- (DECLARED: the engine's own corpse shape, battle_healerdown's)
    say(string.format("seat 1's member felled (HP 0, Wound) inside $%03X's fuse", C.W.species))
  end),
  H.waitUntil(function() return #C.W.snuffs > C.snuffAt end, 60, "fell: the snuff", 1),
  H.call(function()
    local W = C.W
    H.assertEq(#W.snuffs > C.snuffAt, true, "fell: the fuse is snuffed once the member falls (Ot6SeizeFell -> "
      .. "Ot6FuseSnuff)")
    say(string.format("snuffed %d frame(s) after the fall: %s", W.snuffs[#W.snuffs].f - C.fellF,
      W.cellsLine(W.cells())))
    H.assertEq(claimOf(W), nil, "fell: the claim is clear after the snuff")
    H.assertEq(W.cells().blk, 0xFF, "fell: its script waits nowhere ($3240 = $FF)")
  end),
  defendUntil(function() return not C.W.litBit() and C.W.vramMark() ~= C.W.FUSE_WORD end, 60, true),
  H.call(function()
    H.assertEq(C.W.vramMark() ~= C.W.FUSE_WORD, true, "fell: the mark is gone")
    C.cmdsAt = #C.W.cmds
  end),
  -- the dead member, still Slowed (staged), and the empty seat 4: no claim on either through 6,000 frames
  defendUntil(function() return H.frame - C.fellF >= 6000 end, 6600, true),
  H.call(function()
    for _, s in ipairs(seizes) do
      if s.f > C.fellF then
        H.assertEq(s.seat ~= 0 and s.seat ~= 3, true, string.format("fell: no Seize on seat 1 (dead) or 4 (empty) "
          .. "after the fall (the Seize at f%d on seat %s)", s.f, tostring(s.seat and s.seat + 1)))
      end
    end
    local d = testsOn(1, C.fellF + 1, function(x) return x.mode == 0 end)
    local e = testsOn(4, C.fellF + 1, function(x) return x.mode == 0 end)
    say(string.format("claim tests after the fall: seat 1 (dead, Slowed) %d, seat 4 (empty, Slowed) %d", #d, #e))
    for _, x in ipairs(d) do H.assertEq(x.got, false, "fell: a claim on the dead member is refused") end
    for _, x in ipairs(e) do H.assertEq(x.got, false, "fell: a claim on the empty seat 4 is refused") end
    say("PASS")
  end),
})

-- dies: a member waits at its command window; at a body's line (its claim standing) the claimant's HP goes to 1
-- (DECLARED) and the Fight is aimed at it, killing it inside its fuse; the seat it claimed is kept Slowed (DECLARED),
-- and another body's claim on it follows.  (Up to three tries: the claimant's Seize can come before the Fight; the
-- case then reads on to the next announce)
-- (a body that has fallen: gone from its slot, or standing there dead -- the death's own frames)
local function fallen(e)
  return (rb(0x3AA0 + e) & 1) == 0 or H.readWord(0x3BF4 + e) == 0 or (rb(0x3EE4 + e) & 0xC2) ~= 0
end
local function diesTry(k)
  return H.cond(function() return C.done == nil end, {
    H.call(function()
      C.from = marks()
      C.W, C.staged, C.keepW = nil, false, nil
      say(string.format("try %d: a member waits for a body's line", k))
    end),
    readyBreak(function()
      local lc, W, li = lineClaiming(C.from, nil)
      if lc == nil then return nil end
      C.li, C.lc, C.seat = li, lc, claimOf(W)
      return W
    end, nil, 40000, function(W)
      C.deadEnt = W.ent()
      slowSeats = { [C.seat] = true }
      WRITE.word(0x3BF4 + C.deadEnt, 1)          -- (DECLARED: the claimant's HP to 1)
      say(string.format("$%03X (the claimant of seat %d) staged to 1 HP", W.species, C.seat + 1))
    end, function() return fallen(C.deadEnt) or seizeFrom(C.W, C.li) ~= nil end),
    H.call(function()
      local W = C.W
      if W ~= nil and fallen(C.deadEnt) and seizeFrom(W, C.li) == nil then
        C.done, C.dead, C.deadF = true, W, H.frame
        say(string.format("$%03X died with its claim on seat %d, no Seize from it", W.species, C.seat + 1))
      else
        say(string.format("try %d: the claimant's Seize came first (or the Fight missed it): the next announce", k))
        if W and not fallen(C.deadEnt) then WRITE.word(0x3BF4 + C.deadEnt, 4000) end
        slowSeats = {}
      end
    end),
  }, {})
end
local dies = H.seqStep({
  open("dies", true),
  H.call(function() C.done = nil end),
  diesTry(1), diesTry(2), diesTry(3),
  H.call(function()
    H.assertEq(C.done, true, "dies: a claimant fell to an aimed Fight inside its fuse, no Seize from it, in one of "
      .. "three tries")
  end),
  defendUntil(function()
    return #testsOn(C.seat + 1, C.deadF, function(x) return x.mode == 0 and x.got end) >= 1
  end, 30000),
  H.call(function()
    local t = testsOn(C.seat + 1, C.deadF, function(x) return x.mode == 0 and x.got end)
    H.assertEq(#t >= 1, true, "dies: another body claims the seat after the claimant's death (a dead body's claim "
      .. "is no claim)")
    say(string.format("the body at $%02X claimed seat %d at f%d, %d frames after the claimant died", t[1].ent,
      C.seat + 1, t[1].f, t[1].f - C.deadF))
    say("PASS")
  end),
})

-- The cap: seven cases of up to 20,000 frames; 280,000 is 2x.
H.run({ maxFrames = 280000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Tentacles' battle is up", 2),
  H.call(function()
    for _, W in ipairs(Ws) do
      H.assertEq(W.slot() ~= nil, true, string.format("the Tentacle $%03X stands at the open (tentacles_entry)",
        W.species))
      local at = H.aiAttacks(W.species, SEIZE)
      H.assertEq(#at, 4, string.format("the Tentacle $%03X's turn script names Seize four times: a fire block a seat "
        .. "(no Seize unannounced, and no copy after an announce's label)", W.species))
    end
    watchers()
  end),
  landed, broken, outside, release, oneSeat, fell, dies,
  H.call(function()
    local bad, cats = 0, { other = 0, held = 0, dead = 0, absent = 0 }
    for _, x in ipairs(tests) do
      if x.got ~= x.want then
        bad = bad + 1
        H.log(string.format("[claim] MISMATCH at f%d: body $%02X seat %d mode %d: got %s, the rule %s", x.f, x.ent,
          x.seat, x.mode, tostring(x.got), tostring(x.want)))
      end
      if x.mode == 0 and not x.got then
        if x.hold and x.other then cats.other = cats.other + 1
        elseif x.why == "held" then cats.held = cats.held + 1
        elseif x.why == "dead" then cats.dead = cats.dead + 1
        elseif x.why == "absent" then cats.absent = cats.absent + 1 end
      end
    end
    local nh, nd, ndr = 0, 0, 0
    for _, s in ipairs(seizes) do
      if s.drain then ndr = ndr + 1 else nd = nd + 1; if s.held then nh = nh + 1 end end
    end
    H.log(string.format("[tentacles] the claim tests: %d, %d against the rule; refused claims: %d claimed by another "
      .. "body, %d on a member held, %d on a member dead, %d on an empty seat; one-claim clashes %d frame(s); Seizes "
      .. "dispatched by a body holding no one %d, holds %d (and %d drain turns of a body holding)", #tests, bad,
      cats.other, cats.held, cats.dead, cats.absent, claimClash, nd, nh, ndr))
    H.assertEq(bad, 0, "the claim tests: every answer is the rule's (holdable, and no other standing body's claim)")
    H.assertEq(claimClash, 0, "no two standing bodies claim one seat on any frame")
    H.assertEq(nh, nd, "every Seize dispatched holds its member (holds counted, not dispatches)")
    -- (a member held, dead or gone fails the announce block's own Slow test before the claim is read, on this
    -- fixture: the categories below other's are logged, and the fell case asserts the dead and empty seats unclaimed)
    H.assertEq(cats.other >= 1, true, "the claim tests met a seat another standing body had claimed, and refused it")
  end),
  H.logStep("[tentacles] PASS: the Seize announced and held, one body a member, the cancel, a break outside, the "
    .. "release, the fall and the claimant's death"),
})
