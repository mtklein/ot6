-- @suite savestate=icedragon_entry slow
-- battle_icedragon.lua -- the Ice Dragon under the boss contract (docs/design/bosses-wor.md block 7, wt/v052-tg-wor2's
-- review round): freeze and thaw.  Absolute 0 is its telegraph, armed by a Frozen member, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_329): its rotation of three (Battle, N. Cross or N. Cross; Battle, Battle or
-- Surge; Battle, Surge or Battle) casts no Absolute 0.  On a turn when a seated member is Frozen (N. Cross freezes those
-- it hits) one of four arming blocks (a seat each, `if_status_set CHAR_SLOT_n, FROZEN`, the Red Dragon's Eraser idiom)
-- takes the turn: Battle, Battle or Surge, and monster switch 0 set.  Its next turn, the fuse block (the script's first,
-- conditioned on the switch alone), says "The air goes still!" (battle dialogue $A7) and glows; the turn after casts
-- Absolute 0 (attack $BB, command $0C).  A member thawed before the dragon's turn arms nothing; one thawed after the
-- arming does not stop the line or the move.  Under the contract (Ot6FuseTbl's row $0149) a break while it is lit
-- cancels it: switch 0 cleared, the `wait` forgotten.  Its counters (a Battle for a hit, Surge at its death) and its
-- dying Surge are vanilla's.
--
-- Boots icedragon_entry (gen_wor_icedragon: the Ice Dragon's battle, event battle 132, as it comes up).  From a
-- snapshot at the battle's open:
--   landed    (M.fuseLanded) nothing staged and nothing held: the party Defends and thaws no one; a member is frozen,
--             the line comes, and Absolute 0 on its next turn, and lands: a member's HP falls (each member's effect
--             logged).
--   thaw      nothing staged and nothing held: the party Defends until a member is Frozen, then a standing member who
--             knows Fire casts it on the frozen seat (kitBattle's allySeat).  Tried until both of these are seen (six
--             freezes at most, Absolute 0 waited out between):
--               thawed     the Fire thawed the member before the dragon's next turn was read, no one else Frozen: that
--                          turn arms nothing (switch 0 still clear after it) and no line comes on the turn after;
--               armed      the dragon's turn came first and armed (switch 0 set): the member thawed after it, and the
--                          line still comes and Absolute 0 after it.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, the party's HP held; the dragon's is not held):
--   unbroken, broken (the cancel clears switch 0; the line returns only after another arming), outside (a break with
--   nothing armed: nothing is cancelled).
--   and over the whole suite: on every pair of the dragon's consecutive turns with no break between, the earlier turn
--   arms (switch 0 read set at the later turn) exactly when it was read with switch 0 clear and a member Frozen; and
--   Absolute 0 comes only announced; the script names Absolute 0 once.
-- A mechanism test, not play (the landed and thaw cases write nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge and the row's classes, and holds the party's HP, through
-- them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local NOWRITE = { byte = function() error("icedragon: no writes here") end, word = function() error("no writes") end }
local STATE = "build/states/icedragon_entry.mss.lua"

local ICEDRAGON, ABS0, LINE, FIRE = 0x149, 0xBB, 0xA7, 0x00

local function slotOf()
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == ICEDRAGON then return s end
  end
  return nil
end
local function ent() local s = slotOf(); return s and 8 + 2 * s end
local function frozenMask()
  local m = 0
  for i = 0, 3 do
    if H.readByte(0x3ED8 + 2 * i) ~= 0xFF and (H.readByte(0x3EF9 + 2 * i) & 0x02) ~= 0 then m = m | (1 << i) end
  end
  return m
end

local S = {}
local gen = 0
-- every dispatch of the line or of Absolute 0, over the suite
local seen, unannounced = {}, 0
-- the dragon's turns as its script is read: { f, frozen, sw (monster switch 0), gen }; its breaks
local turns, brks = {}, {}
local function watchAll()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 or x > 18 or H.readWord(0x57C0 + (x - 8)) ~= ICEDRAGON then return end
    local cmd, arg = H.readByte(0xB5), H.readByte(0xB6)
    if cmd == 0x21 and arg == LINE then seen[#seen + 1] = { f = H.frame, move = false } end
    if cmd == 0x0C and arg == ABS0 then
      local ok = #seen > 0 and not seen[#seen].move
      seen[#seen + 1] = { f = H.frame, move = true }
      if not ok then unannounced = unannounced + 1 end
      H.log(string.format("[icedragon] f%d Absolute 0 dispatched: %s", H.frame, ok
        and "its line came since the Absolute 0 before" or "UNANNOUNCED (no line since the Absolute 0 before)"))
    end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x ~= ent() then return end
    turns[#turns + 1] = { f = H.frame, frozen = frozenMask(), sw = H.readByte(0x3DAC + x) & 0x01, gen = gen }
    H.log(string.format("[icedragon] f%d its turn is read: Frozen seats $%X, monster switch 0 %d", H.frame,
      frozenMask(), H.readByte(0x3DAC + x) & 0x01))
  end, emu.callbackType.exec, H.sym("ExecMonsterAction"), H.sym("ExecMonsterAction"))
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == ent() then brks[#brks + 1] = { f = H.frame, gen = gen } end
  end, emu.callbackType.exec, H.sym("Ot6HitBroke"), H.sym("Ot6HitBroke"))
end
local function effect(tag, m)
  local t, fell = {}, 0
  for i = 0, 3 do
    local id = H.readByte(0x3ED8 + 2 * i)
    if id ~= 0xFF then
      local now, mx = H.readWord(0x3BF4 + 2 * i), H.readWord(0x3C1C + 2 * i)
      local hit = m.tchars & (1 << i) ~= 0
      if hit and now < m.hp[i] then fell = fell + 1 end
      t[#t + 1] = string.format("seat %d char $%02X %s: %d -> %d of %d (%d%% of max), status $%02X/$%02X", i, id,
        hit and "a target" or "NOT a target", m.hp[i], now, mx, mx > 0 and (m.hp[i] - now) * 100 // mx or 0,
        H.readByte(0x3EE4 + 2 * i), H.readByte(0x3EF8 + 2 * i))
    end
  end
  H.log(string.format("[%s] effect: the move ($%02X/$%02X, targets $%02X) on the party: %s", tag, m.cmd, m.arg,
    m.tchars, table.concat(t, "; ")))
  return fell
end

-- ---- the thaw case ----
local T = { thawed = nil, armed = nil, tries = 0 }
local W = nil
local function lineAfter(f) for _, x in ipairs(seen) do if not x.move and x.f > f then return x end end return nil end
local function moveAfter(f) for _, x in ipairs(seen) do if x.move and x.f > f then return x end end return nil end
local function turnAfter(f) for _, t in ipairs(turns) do if t.gen == gen and t.f > f then return t end end return nil end
local function nTurnsAfter(f)
  local n = 0
  for _, t in ipairs(turns) do if t.gen == gen and t.f > f then n = n + 1 end end
  return n
end
local function oneTry()
  local try = {}
  return H.cond(function() return (T.thawed == nil or T.armed == nil) and T.tries < 6 and ent() ~= nil end, {
    H.call(function()
      T.tries = T.tries + 1
      try = { from = H.frame }
      H.log(string.format("[icedragon] thaw try %d: the party Defends until a member is Frozen", T.tries))
    end),
    -- (a fuse already lit or armed burns out first: its move)
    H.lazy(function()
      local t0 = H.frame
      return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 20600, giveUp = function()
        local e = ent()
        return e == nil or H.frame - t0 >= 20000
          or (frozenMask() ~= 0 and (H.readByte(0x3DAC + e) & 0x01) == 0 and not W.litBit())
      end })
    end),
    H.call(function()
      local e = ent()
      H.assertEq(e ~= nil and frozenMask() ~= 0, true, "icedragon thaw: a member was Frozen by the dragon's play "
        .. "within 20,000 frames (N. Cross)")
      try.mask, try.f = frozenMask(), H.frame
      for i = 0, 3 do if try.mask & (1 << i) ~= 0 then try.seat = i; break end end
      for i = 0, 3 do
        local id = H.readByte(0x3ED8 + 2 * i)
        if i ~= try.seat and id ~= 0xFF and (try.mask & (1 << i)) == 0 and H.readWord(0x3BF4 + 2 * i) > 0
           and (H.readByte(0x3EE4 + 2 * i) & 0xC2) == 0 and H.knowsSpell(id, FIRE) and try.caster == nil then
          try.caster = id
        end
      end
      H.log(string.format("[icedragon] f%d seat %d is Frozen (mask $%X); char %s casts Fire on it", H.frame, try.seat,
        try.mask, try.caster and string.format("$%02X", try.caster) or "NONE"))
      -- (no one to cast it -- the casters down or Frozen too -- skips the try; the case's own assertions below say
      -- whether enough tries were judged)
      if try.caster == nil then try.skip = true; H.log("[icedragon] no one stands to cast Fire: the try is skipped") end
      -- the mode: thaw at once until a thaw in time has been seen; then wait for the dragon's turn (it arms) and thaw
      -- after it
      try.late = T.thawed ~= nil
      H.log(string.format("[icedragon] this try thaws %s", try.late and "after the dragon's next turn (armed, then "
        .. "thawed)" or "at once"))
    end),
    H.lazy(function()
      if try.skip then return H.waitFrames(1) end
      return H.kitBattle({ { who = try.caster, cmd = 0x02, spell = FIRE, boost = 0, allySeat = try.seat,
          openWhen = try.late and function() return turnAfter(try.f) ~= nil end or nil } },
        { idle = "defend", care = false, maxFrames = 6000, untilPlanDone = true,
          giveUp = function() return ent() == nil or (frozenMask() & (1 << try.seat)) == 0 end })
    end),
    -- (the Fire confirmed, the others Defend until it resolves: 600 frames at most)
    H.lazy(function()
      local t0 = H.frame
      return H.kitBattle({}, { idle = "defend", care = false, maxFrames = 1200, giveUp = function()
        return ent() == nil or (frozenMask() & (1 << try.seat)) == 0 or H.frame - t0 >= 600
      end })
    end),
    H.call(function()
      try.thawF = H.frame
      if try.skip then return end
      local thawed = (frozenMask() & (1 << try.seat)) == 0
      H.log(string.format("[icedragon] f%d the Fire: seat %d %s", H.frame, try.seat, thawed and "thawed" or
        "STILL Frozen"))
      H.assertEq(thawed, true, "icedragon thaw: a Fire cast on a Frozen member thaws it")
    end),
    -- three of the dragon's turns after the thaw, the party Defending (no one thaws anyone)
    H.lazy(function()
      local t0 = H.frame
      return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 9600, giveUp = function()
        return ent() == nil or nTurnsAfter(try.thawF) >= 3 or H.frame - t0 >= 9000
      end })
    end),
    H.call(function()
      -- the dragon's turn read between the freeze and the thaw, if any (it armed then), and the first after the thaw
      local before = nil
      for _, t in ipairs(turns) do if t.gen == gen and t.f > try.f and t.f <= try.thawF and before == nil then before = t end end
      local after = turnAfter(try.thawF)
      if try.skip then return end
      local broke = false
      for _, b in ipairs(brks) do if b.gen == gen and b.f > try.f then broke = true end end
      if broke then H.log("[icedragon] a break came in this try; it judges nothing"); return end
      if before == nil and after ~= nil and after.frozen == 0 and after.sw == 0 then
        -- thawed in time: the turn after the thaw arms nothing, and no line on the turn after it
        local nxt = turnAfter(after.f)
        H.assertEq(nxt ~= nil, true, "icedragon thawed: the dragon took two turns after the thaw")
        local l = lineAfter(try.thawF)
        H.log(string.format("[icedragon] thawed: its turn at f%d read no one Frozen; at its next (f%d) monster switch 0 "
          .. "%d; a line %s", after.f, nxt.f, nxt.sw, l and ("at f" .. l.f) or "none"))
        if nxt.frozen == 0 then
          H.assertEq(nxt.sw, 0, "icedragon thawed: the member thawed before the dragon's turn, and that turn armed "
            .. "nothing (monster switch 0 clear at its next)")
          H.assertEq(l == nil or l.f > nxt.f, true, "icedragon thawed: no line on the turn after the thawed turn")
          T.thawed = T.thawed or { f = try.thawF }
        end
      elseif before ~= nil and before.sw == 0 then
        -- the dragon's turn came first and armed on the frozen member; it thawed after
        local l = lineAfter(before.f)
        local m = l and moveAfter(l.f)
        H.log(string.format("[icedragon] armed: its turn at f%d read seat(s) $%X Frozen; the thaw at f%d; the line %s, "
          .. "Absolute 0 %s", before.f, before.frozen, try.thawF, l and ("at f" .. l.f) or "none",
          m and ("at f" .. m.f) or "none"))
        if before.frozen ~= 0 then
          H.assertEq(l ~= nil and m ~= nil, true, "icedragon armed then thawed: the member thawed after the arming, "
            .. "and the announced Absolute 0 still comes (the line, then the move)")
          T.armed = T.armed or { f = before.f }
        end
      end
    end),
    -- (Absolute 0 waited out if a fuse is lit)
    H.lazy(function()
      local t0 = H.frame
      return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 6600, giveUp = function()
        local e = ent()
        return e == nil or H.frame - t0 >= 6000 or ((H.readByte(0x3DAC + e) & 0x01) == 0 and not W.litBit())
      end })
    end),
  }, {})
end

-- The cap: landed ~6,000 frames, thaw up to ~60,000, three cases ~10,000 each; 140,000 is about 1.5x.
H.run({ maxFrames = 140000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Ice Dragon's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(ICEDRAGON, ABS0)
    H.log(string.format("[icedragon] its turn script names Absolute 0 at %d place(s)", #at))
    H.assertEq(#at, 1, "the Ice Dragon's turn script names Absolute 0 once: the fuse's move (not its rotation)")
    watchAll()
  end),
  H.fuseSnap(S),
  H.call(function() gen = gen + 1 end),
  H.fuseLanded({
    tag = "icedragon", species = ICEDRAGON, line = LINE, move = { cmd = 0x0C, atk = ABS0 }, turns = 1,
    landed = function(Wl, l, m)
      local fell = effect("icedragon", m)
      H.assertEq(fell >= 1, true, "icedragon landed: Absolute 0 landed (a target's HP fell within 420 frames)")
    end,
  }),
  H.fuseRestore(S, "icedragon landed"),
  H.call(function()
    gen = gen + 1
    W = H.fuseWatch(ICEDRAGON, NOWRITE)
    W.reset(); W.on = true
    H.log("[icedragon] case thaw, from the battle's open; nothing staged, nothing held")
  end),
  oneTry(), oneTry(), oneTry(), oneTry(), oneTry(), oneTry(),
  H.call(function()
    W.on = false
    H.log(string.format("[icedragon] thaw: %d tries; thawed in time %s; armed then thawed %s", T.tries,
      T.thawed and ("at f" .. T.thawed.f) or "not seen", T.armed and ("at f" .. T.armed.f) or "not seen"))
    H.assertEq(T.thawed ~= nil, true, "icedragon thaw: a member thawed before the dragon's turn was seen (in six "
      .. "freezes)")
    H.assertEq(T.armed ~= nil, true, "icedragon thaw: an arming before the thaw was seen (in six freezes)")
  end),
  H.fuseRestore(S, "icedragon thaw"),
  H.call(function() gen = gen + 1 end),
  H.fuseCases({
    tag = "icedragon", species = ICEDRAGON, write = WRITE,
    line = LINE, move = { cmd = 0x0C, atk = ABS0 }, turns = 1, glows = 1,
    lineText = "The air goes still!{wait}",
    arm = "idle", aim = true, plainBreaker = true,
    onOpen = function() gen = gen + 1 end,
    -- nothing armed or lit, and no one Frozen
    partway = function(Wc)
      local c = Wc.cells()
      return c ~= nil and not Wc.litBit() and (c.mvar & 0x01) == 0 and frozenMask() == 0
    end,
    earned = function(C, Wc)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x01, 1, "icedragon: monster switch 0 stood at the break (a Frozen member had armed it)")
      H.assertEq(post.mvar & 0x01, 0, "icedragon: monster switch 0 is clear after the cancel (a Frozen member must arm "
        .. "it again)")
      H.assertEq(post.blk, 0xFF, "icedragon: the script waits nowhere after the cancel ($3240 = $FF)")
    end,
  }),
  H.call(function()
    -- arms exactly when a member is Frozen: every pair of consecutive turns of one case with no break between
    local npairs, armed, bad = 0, 0, {}
    for k = 1, #turns - 1 do
      local a, b = turns[k], turns[k + 1]
      if a.gen == b.gen and a.sw == 0 then
        local broke = false
        for _, br in ipairs(brks) do if br.gen == a.gen and br.f > a.f and br.f <= b.f then broke = true end end
        if not broke then
          npairs = npairs + 1
          local want = a.frozen ~= 0 and 1 or 0
          if want == 1 then armed = armed + 1 end
          if b.sw ~= want then bad[#bad + 1] = string.format("f%d (Frozen $%X) -> switch %d", a.f, a.frozen, b.sw) end
        end
      end
    end
    H.log(string.format("[icedragon] arming: %d unarmed turns judged, %d with a member Frozen; mismatches: %s", npairs,
      armed, #bad > 0 and table.concat(bad, "; ") or "none"))
    H.assertEq(armed >= 2 and table.concat(bad, "; "), "", "icedragon: a turn arms (monster switch 0 set) exactly "
      .. "when it is read with a member Frozen (two or more armed turns seen)")
    local n = 0
    for _, x in ipairs(seen) do if x.move then n = n + 1 end end
    H.log(string.format("[icedragon] Absolute 0 dispatched %d time(s) over the suite, %d unannounced", n, unannounced))
    H.assertEq(n >= 3 and unannounced, 0, "Absolute 0 comes only announced (every Absolute 0 has its line since the "
      .. "one before; three or more seen)")
  end),
  H.logStep("[icedragon] PASS: armed by a Frozen member, the announce, Absolute 0, a thaw in time arms nothing, a "
    .. "thaw after the arming stops nothing, the cancel"),
})
