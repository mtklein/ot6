-- @suite savestate=tentacles_entry slow
-- battle_tentacles.lua -- the Tentacles under the boss contract (docs/design/bosses-wor.md block 1, wt/v052-tg-wor1):
-- the Seize is announced, a break in the fuse cancels it, and a break frees the member a Tentacle holds.
--
-- Each body's script (ai_script.asm AIScript::_283, _316, _317, _318; species $11B, $13C, $13D, $13E): on its first
-- turn that finds a Slowed member (Entwine, its rotation's), with no hostage of its own, it says "It coils to seize!"
-- (battle dialogue $A0) and glows, a turn of its own, and sets the monster switch of that member's seat (0-3); its
-- next turn's fire block, which stands first, Seizes that seat (attack $C8, command $0C), whatever its Slow reads
-- then.  Under the contract (Ot6FuseTbl's rows, one a body a seat) a break while it is lit cancels it: the seat's
-- switch goes and the script forgets its `wait`; the next turn that finds a Slowed member announces again.  And every
-- break of a Tentacle, lit or not, frees the member it holds (OT6_FUSE_RELEASE, Ot6FuseRelease: Discard's release),
-- so the member acts again.
--
-- Boots tentacles_entry (gen_wor_edgar: the Tentacles' battle, event battle 84, as it comes up; CELES, SABIN and
-- EDGAR).  Each case plays from a snapshot at the battle's open; the party Defends, and Entwine's Slow comes in the
-- Tentacles' own time.
--   landed    nothing staged and nothing held: a body's line once a member is Slowed; its lit bit and its mark; the
--             Seize on its next turn, on that member's seat, and the member held (its seize attacker is that body,
--             the body's hold switch set).
--   broken    (DECLARED: every body's gauge held at 63, and each standing member's HP at 9,999) at a body's line its
--             gauge staged to 1 with every class and an aimed Fight once its mark is up breaks it: the cancel fires,
--             the seat's switch is clear, its script waits nowhere and the mark goes; it Seizes nothing on its turns
--             back before it announces again, and when it does (a Slowed member found again) the Seize follows.
--   outside   (DECLARED as broken) a body broken before any line of its own: nothing is cancelled and its cells stand.
--   release   (DECLARED as broken) once a body holds a member, that body's gauge staged to 1 with every class and
--             another member's aimed Fight breaks it: Ot6FuseRelease runs, the member's seize attacker is cleared,
--             its seized bit ($3403) is back and the body's hold switch is clear; the freed member then acts (a
--             command of its own is dispatched).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "broken: the break during the fuse cancels it"; tent_no_release (the four $11B rows' flags 0 ... every Tentacle
-- row's RELEASE flag off) at "release: the member's seize attacker is cleared"; tent_seize_now (the announce blocks'
-- `wait` -> end_if: no fuse) at "landed: the lit-fuse mark".  A mechanism test, not play (the landed case writes
-- nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (the gauges and the party's held HP; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/tentacles_entry.mss.lua"

local SPECIES = { 0x11B, 0x13C, 0x13D, 0x13E }
local SEIZE, LINE = 0xC8, 0xA0
local Ws = {}
for _, sp in ipairs(SPECIES) do Ws[#Ws + 1] = H.fuseWatch(sp, WRITE) end
local S, C = {}, {}
local function say(s) H.log(string.format("[tentacles] f%d %s: %s", H.frame, C.name or "-", s)) end
local function up() return H.battleLoadStarted() end

-- every party command dispatched, by seat: { f, seat, cmd }
local acts = {}
local releases = {}
local holdGauges = false
local function watchers()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 then acts[#acts + 1] = { f = H.frame, seat = x // 2, cmd = H.readByte(0xB5) } end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    releases[#releases + 1] = { f = H.frame, ent = y, held = H.readByte(0x3358 + y) }
    H.log(string.format("[tentacles] f%d Ot6FuseRelease for the body at $%02X (it holds $%02X)", H.frame, y,
      H.readByte(0x3358 + y)))
  end, emu.callbackType.exec, H.sym("Ot6FuseRelease"), H.sym("Ot6FuseRelease"))
  -- (DECLARED: every standing body's gauge held at 63 in the staged cases, but the one a case breaks)
  emu.addEventCallback(function()
    if not holdGauges then return end
    for _, W in ipairs(Ws) do
      local e = W.ent()
      if e and e ~= C.breaking and H.readByte(0x3E88 + e) == 0 and H.readByte(0x3E38 + e) ~= 63 then
        WRITE.byte(0x3E38 + e, 63)
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
local function heldBy(seat) return H.readByte(0x3359 + 2 * seat) end

local function defendUntil(pred, max)
  return H.lazy(function()
    local t0 = H.frame
    return H.kitBattle({}, { idle = "defend", care = true, maxFrames = max + 600,
      giveUp = function() return not up() or pred() or H.frame - t0 >= max end })
  end)
end
local function aimedFight(W, when, notSeat, max)
  return H.lazy(function()
    local who, plain = nil, nil
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if id ~= 0xFF and i ~= notSeat and H.readWord(0x3BF4 + 2 * i) > 0
         and (H.readByte(0x3EE4 + 2 * i) & 0xC2) == 0 and heldBy(i) == 0xFF then
        who = who or id
        -- (one whose hands carry no element first: an absorbed hit takes no shield; readyBreak, below)
        if plain == nil and (H.weaponElement(H.readByte(0x1600 + 37 * id + 0x1F))
            | H.weaponElement(H.readByte(0x1600 + 37 * id + 0x20))) == 0 then plain = id end
      end
    end
    who = plain or who
    H.assertEq(who ~= nil, true, C.name .. ": a free member stands to aim the breaking Fight")
    C.nBreaks = #W.breaks
    local t0 = H.frame
    return H.kitBattle({ { who = who, cmd = 0x00, boost = 0, slot = W.slot(), confirmWhen = when } },
      { idle = "defend", care = false, maxFrames = max + 600,
        giveUp = function() return not up() or #W.breaks > C.nBreaks or H.frame - t0 >= max end })
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
      C = { name = name }
      for _, W in ipairs(Ws) do W.reset(); W.on = true; W.pin = staged and { party = true } or nil end
      holdGauges = staged
      acts, releases = {}, {}
      say("from the battle's open")
    end),
    H.waitUntil(function() return H.battleActive() and Ws[1].ent() ~= nil end, 3000, name .. ": the Tentacles up", 2),
  })
end

-- to a line: the party Defends until one body announces; C.W the body, C.seat the seat its switch names
local function toLine(name)
  return H.seqStep({
    defendUntil(function() return firstLine(C.from) ~= nil end, 40000),
    H.call(function()
      local lc, W, li = firstLine(C.from)
      H.assertEq(lc ~= nil, true, name .. ": a Tentacle announced (\"It coils to seize!\") once a member was Slowed")
      C.W, C.li, C.lc = W, li, lc
    end),
    -- (the seat's switch is set when the announce turn's commands run, after the line: wait for it too)
    defendUntil(function()
      return C.W.litBit() and C.W.vramMark() == C.W.FUSE_WORD and (H.readByte(0x3DAC + C.W.ent()) & 0x0F) ~= 0
    end, 900),
    H.call(function()
      local W = C.W
      local sw = H.readByte(0x3DAC + W.ent()) & 0x0F
      C.seat = sw == 1 and 0 or sw == 2 and 1 or sw == 4 and 2 or sw == 8 and 3 or nil
      say(string.format("$%03X announced on its turn %d; its seat switches $%X (seat %s); seat statuses 3: %s",
        W.species, C.lc.turn, sw, tostring(C.seat), (function()
          local t = {}
          for i = 0, 3 do t[#t + 1] = string.format("$%02X", H.readByte(0x3EF8 + 2 * i)) end
          return table.concat(t, " ")
        end)()))
      H.assertEq(C.seat ~= nil, true, name .. ": the announce set exactly one seat's switch (0-3)")
      H.assertEq(W.litBit(), true, name .. ": OT6_FUSE's lit bit is set for the announcing body's slot")
      H.assertEq(W.vramMark(), W.FUSE_WORD, name .. ": the lit-fuse mark stands before the announcing body's emblem")
    end),
  })
end

-- (the Seize's dispatch on the body's next turn, on the announced seat, is the contract's; whether it holds the
-- member is the game's hit roll: on wt/v052-tg-wor1's replay the broken case's second Seize missed,
-- build/attempts/wt/v052-tg-wor1/regen1/red/battle_tentacles-red.log, so C.held says which, and a case that needs a
-- hold plays on to the next announce: landedTry)
local function seizeLands(name)
  return H.seqStep({
    defendUntil(function() return seizeFrom(C.W, C.li) ~= nil end, 12000),
    defendUntil(function() return heldBy(C.seat) == C.W.ent() end, 600),
    H.call(function()
      local W = C.W
      local si, sc = seizeFrom(W, C.li)
      H.assertEq(si ~= nil, true, name .. ": the Seize was dispatched after the announce")
      say(string.format("Seize on its turn %d, targets $%02X; seat %d held by $%02X; $%03X's switches $%02X", sc.turn,
        sc.tchars, C.seat, heldBy(C.seat), W.species, H.readByte(0x3DAC + W.ent())))
      H.assertEq(sc.turn - C.lc.turn, 1, name .. ": the Seize came on the body's next turn after the announce")
      H.assertEq(sc.tchars & 0x0F, 1 << C.seat, name .. ": the Seize was queued on the announced seat")
      H.assertEq(H.readByte(0x3DAC + W.ent()) & 0x0F, 0, name .. ": the seat's switch is clear after the Seize")
      C.held = heldBy(C.seat) == W.ent()
      if C.held then
        H.assertEq(H.readByte(0x3DAC + W.ent()) & 0x80, 0x80, name .. ": the body holds (switch 7) the member it "
          .. "Seized")
      else
        say("the Seize missed (the game's hit roll): no member held")
      end
      C.si = si
    end),
  })
end

-- landed: up to three announces, until a Seize holds its member
local function landedTry(k)
  return H.cond(function() return C.done == nil end, {
    H.call(function() C.from = marks(); say(string.format("try %d: the next announce", k)) end),
    toLine("landed"),
    seizeLands("landed"),
    H.call(function() if C.held then C.done = true end end),
  }, {})
end
local landed = H.seqStep({
  open("landed", false),
  H.call(function() C.done = nil end),
  landedTry(1), landedTry(2), landedTry(3),
  H.call(function()
    H.assertEq(C.done, true, "landed: an announced Seize held the member in the announced seat (that body its seize "
      .. "attacker) in one of three announces")
    say("PASS")
  end),
})

-- the seats held, and by whom: { [seat] = holder entity }
local function heldSeats()
  local t = {}
  for i = 0, 3 do if H.readByte(0x3ED8 + 2 * i) ~= 0xFF and heldBy(i) ~= 0xFF then t[i] = heldBy(i) end end
  return t
end
local function allBreaks() local n = 0; for _, W in ipairs(Ws) do n = n + #W.breaks end; return n end
-- a breaker ready before its moment: a free member (not Slowed where one can be, so no Tentacle seizes it first)
-- waits at its command window (kitBattle's openWhen: the battle runs on) until pick() names the body to break; that
-- body's gauge is then staged (stageBreak) and the Fight aimed at it (slotFn).  Ends once that body is broken, or
-- giveUp() says the moment has passed.
-- (and one whose hands carry no element where one stands: each Tentacle absorbs elements -- $11B fire, $13C ice and
-- water, $13D and $13E bolt, earth and water -- and an absorbed hit heals, taking no shield: on wt/v052-tg-wor1's
-- replay CELES's fire blades took nothing off $11B's staged gauge, build/attempts/wt/v052-tg-wor1/regen1/red/
-- battle_tentacles-release-red.log)
local function readyBreak(pick, giveUp, max)
  return H.lazy(function()
    local best, bestRank = nil, -1
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and (H.readByte(0x3EE4 + 2 * i) & 0xC2) == 0
         and heldBy(i) == 0xFF then
        local el = H.weaponElement(H.readByte(0x1600 + 37 * id + 0x1F)) | H.weaponElement(H.readByte(0x1600 + 37 * id + 0x20))
        local rank = (el == 0 and 2 or 0) + ((H.readByte(0x3EF8 + 2 * i) & 0x04) == 0 and 1 or 0)
        say(string.format("breaker candidate char $%02X (seat %d): hand elements $%02X, status 3 $%02X: rank %d", id, i,
          el, H.readByte(0x3EF8 + 2 * i), rank))
        if rank > bestRank then best, bestRank = id, rank end
      end
    end
    local who = best
    H.assertEq(who ~= nil, true, C.name .. ": a free member stands to be the breaker")
    C.breakerSeat = nil
    for i = 0, 3 do if H.readByte(0x3ED8 + 2 * i) == who then C.breakerSeat = i end end
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
          stageBreak(W)
          return true
        end } },
      { idle = "defend", care = false, maxFrames = max + 600,
        giveUp = function()
          return not up() or (C.W ~= nil and #C.W.breaks > C.nBreaks) or (giveUp ~= nil and giveUp())
            or (C.breakerSeat ~= nil and heldBy(C.breakerSeat) ~= 0xFF) or H.frame - t0 >= max
        end })
  end)
end

-- (up to three tries: a draw can bring the announcing body's Seize before the breaker's Fight -- the four bodies' turns
-- can come back to back before the party's first window, all four announcing on one Slowed member; the case then
-- aims at the next announce, which the other bodies bring: build/attempts/wt/v052-tg-wor1/dev/)
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
  H.call(function() for _, W in ipairs(Ws) do W.cmdsAtBreak = nil end end),
  brokenTry(1), brokenTry(2), brokenTry(3),
  H.call(function()
    H.assertEq(C.done, true, "broken: a break landed inside a body's fuse in one of three tries")
    local W = C.W
    local post = W.cells()
    say(string.format("broken: $%03X, %d cancel(s); %s", W.species, #W.snuffs, W.cellsLine(post)))
    H.assertEq(#W.snuffs >= 1 and W.snuffs[#W.snuffs].f >= C.brk.f, true, "broken: the break during the fuse cancels "
      .. "it (Ot6FuseSnuff fired at the break)")
    H.assertEq(post.blk, 0xFF, "broken: its script waits nowhere after the cancel ($3240 = $FF)")
    H.assertEq(post.mvar & 0x0F, 0, "broken: the seat's switch is clear after the cancel")
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
  end),
  defendUntil(function() return (H.readByte(0x3DAC + C.W.ent()) & 0x0F) ~= 0 or seizeFrom(C.W, C.li) ~= nil end, 900),
  H.call(function()
    local sw = H.readByte(0x3DAC + C.W.ent()) & 0x0F
    C.seat = sw == 1 and 0 or sw == 2 and 1 or sw == 4 and 2 or sw == 8 and 3 or nil
    H.assertEq(C.seat ~= nil, true, "broken: the second announce set one seat's switch")
  end),
  seizeLands("broken (after the second announce)"),
  H.call(function() say("PASS") end),
})

local outside = H.seqStep({
  open("outside", true),
  H.call(function()
    -- the body to break: one with no line yet (any, at the open)
    C.W = Ws[1]
    C.pre = C.W.cells()
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
      "outside: the break left its script's cells and its seat switches as they were")
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
  H.call(function() C.relAt = #releases; C.keepW = nil end),
  releaseTry(1), releaseTry(2), releaseTry(3),
  H.waitFrames(2),
  H.call(function()
    local W = C.W
    H.assertEq(W ~= nil and #W.breaks > C.nBreaks, true, "release: the aimed Fight broke the holding body")
    C.breaking = nil
    C.brkF = W.breaks[#W.breaks].f
    local rel = releases[#releases]
    say(string.format("$%03X held seat %d; after the break: the seat's seize attacker $%02X, $3403 $%02X, the body's "
      .. "switches $%02X; Ot6FuseRelease ran %d time(s) since the open", W.species, C.heldSeat, heldBy(C.heldSeat),
      H.readByte(0x3403), H.readByte(0x3DAC + W.ent()), #releases - C.relAt))
    H.assertEq(#releases > C.relAt and rel.ent == W.ent() and rel.held == 2 * C.heldSeat, true,
      "release: Ot6FuseRelease ran for the broken body, which held the member")
    H.assertEq(heldBy(C.heldSeat), 0xFF, "release: the member's seize attacker is cleared")
    H.assertEq(H.readByte(0x3403) & (1 << C.heldSeat), 1 << C.heldSeat, "release: the member is no longer seized "
      .. "($3403's bit back)")
    H.assertEq(H.readByte(0x3DAC + W.ent()) & 0x80, 0, "release: the body's hold switch (7) is clear")
    C.actsAt = #acts
  end),
  defendUntil(function()
    for k = C.actsAt + 1, #acts do if acts[k].seat == C.heldSeat then return true end end
    return false
  end, 4000),
  H.call(function()
    local a = nil
    for k = C.actsAt + 1, #acts do if acts[k].seat == C.heldSeat and a == nil then a = acts[k] end end
    H.assertEq(a ~= nil, true, "release: the freed member acts again (a command of its own is dispatched)")
    say(string.format("the freed member (seat %d) dispatched command $%02X at f%d, %d frames after the break",
      C.heldSeat, a.cmd, a.f, a.f - C.brkF))
    say("PASS")
  end),
})

-- The cap: four cases of up to 20,000 frames (Entwine comes in the Tentacles' own time); 160,000 is 2x.
H.run({ maxFrames = 160000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Tentacles' battle is up", 2),
  H.call(function()
    for _, W in ipairs(Ws) do
      H.assertEq(W.slot() ~= nil, true, string.format("the Tentacle $%03X stands at the open (tentacles_entry)",
        W.species))
      local at = H.aiAttacks(W.species, SEIZE)
      H.assertEq(#at, 8, string.format("the Tentacle $%03X's turn script names Seize eight times: a fire block and "
        .. "an announce block a seat (no Seize unannounced)", W.species))
    end
    watchers()
  end),
  landed, broken, outside, release,
  H.logStep("[tentacles] PASS: the Seize announced and landed, the cancel, a break outside, and the release"),
})
