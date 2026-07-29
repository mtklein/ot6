-- @suite slow
-- battle_trueknight.lua -- issue #37 (playtester @TimRahaim): a True Knight
-- cover pays the BLOCKER +1 BP, once per round, on the block frame.
--
--   tools/tests/run.sh tools/tests/battle_trueknight.lua
--
-- VANILLA'S COVER PATH (battle_main.asm):
--   CalcAttackEffect calls CoverEffect (:8325).  CoverEffect (:2855) drops out
--   unless the attack can crit ($b2.1 clear, :2859-2861), has targets (:2862),
--   and the target is NEAR FATAL and not vanished ($3ee4,y bits $0200 / $0010,
--   :2875-2879).  It then builds the candidate mask -- every character except
--   the target and the attacker (:2882-2889) -- and walks all ten entities
--   looking for the True Knight relic bit, $3c58,x & $0040 (:2891-2893).
--   Survivors of CheckCoverTarget (:2931: presence, control, seize and status
--   gates, keeping the HIGHEST-hp candidate in $f2/$f4) reach SetCoverTarget
--   (:2911), which COMMITS the cover: past its `bmi` (no candidate) and its
--   `cpy $f8 / bne` (the original target moved), $f8/$a8/$b8 are retargeted
--   onto the blocker (:2916-2922).  That commit IS the block, and it is where
--   OT6 hooks Ot6CoverBP -- the same shape as Ot6RunicBP at RunicEffect's
--   enrolment instruction.
--
-- THE FIXTURE IS LABELLED, NOT NATURAL.  Nobody in the doorstep party wears
-- True Knight, so the blocker's relic-effect word is STAGED: $3c58,slot |= $40,
-- the bit LoadCharProp would have written from the relic (:6868).  The rest of
-- the staging only makes covers HAPPEN often enough to measure:
--   - VICTIM: hp 10 against a 3000 max AND status-2 bit 1 written directly.
--     Vanilla only recomputes NEAR FATAL inside a status update (:11444-11452)
--     and the whole point of the fixture is that this victim never takes a hit
--     to trigger one, so the flag is pinned rather than inferred.  Stopped, so
--     his own menu never opens.
--   - ATTACKER: a MUDDLED ally with a Fight-only command list (battle_runic's
--     idiom) -- swings arrive on a character ATB rather than monster AI, and
--     roughly one in three lands on the near-fatal victim.  The monsters are
--     left alive and unstopped and contribute covers too.
--   - BLOCKER: never stopped (CheckCoverTarget rejects $3ef8,x & $3210, :2944,
--     so stopping him would delete the mechanic under test -- battle_runic's
--     lesson) and held off the turn order by his ATB byte instead ($3219,x),
--     except in phase 4 where taking a turn is the point.
--   MEASURED DEAD END, recorded so it is not re-tried: marking every character
--   but the victim un-targettable ($2f4c) to force every swing into a cover
--   FREEZES the action queue -- 20949 frames, ATB full on four entities, zero
--   CalcAttackEffect calls (probe_cover).  Cover frequency is bought with
--   patience here, not with $2f4c.
--
-- The cover DETECTOR is the ROM's own commit condition, evaluated at
-- SetCoverTarget's ENTRY out of CPU state: $f4 valid (not $ff) and Y still ==
-- $f8.  H.sym() resolves the entry from ff6-en.dbg per build, so the same
-- script reads the pre-change and post-change ROMs.
--
-- Asserted, in order, so a fixture failure never masquerades as a product one:
--   1. the cover really commits, onto OUR knight;
--   2. the bank rises by exactly 1, in the SAME FRAME as the commit;
--   3. the party-window pip cell shows the new bank within a few frames --
--      #33's clockwork rule, through the OT6_PIPTAIL / OT6_PIPSLOT machinery
--      Ot6ActionEnd already uses;
--   4. ONCE PER ROUND: further covers in the same round still redirect the hit
--      but bank nothing;
--   5. and the round boundary is REAL -- after the blocker takes his own turn
--      (Ot6ActionEnd), the next cover pays again.  Without 5, "once per round"
--      and "once per battle" would both pass 4.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local TRUE_KNIGHT = 0x40          -- $3c58 bit 6 (relic effects 4)
local STOP, MUDDLE, MAGITEK = 0x10, 0x20, 0x08
local NEAR_FATAL = 0x02           -- status 2 bit 1
local PIP = { [0] = 0x72, 0x73, 0x75, 0x76, 0x77, 0x79 }

local function bp(s)    return H.readByte(0x3E9C + s * 2) end
local function pend(s)  return H.readByte(0x3E9D + s * 2) end
local function hp(s)    return H.readWord(0x3BF4 + s * 2) end
local function st2(s)   return H.readByte(0x3EE5 + s * 2) end
local function alive(s) return H.readByte(0x3AA0 + s * 2) % 2 == 1 end

local knight, victim, attacker = nil, nil, nil
local msPresent = {}
local holdKnight = true

-- ---------------------------------------------------------------- staging --
local function pinField()
  if not knight then return end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      H.writeWord(0x3C1C + s * 2, 3000)                            -- real max hp
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & ~MAGITEK & 0xFF)
      if s == attacker then
        H.writeWord(0x3BF4 + s * 2, 2000)
        H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | MUDDLE)
        H.writeByte(0x202E + s * 12, 0x00)                         -- Fight, alone
        H.writeByte(0x2031 + s * 12, 0xFF)
        H.writeByte(0x2034 + s * 12, 0xFF)
        H.writeByte(0x2037 + s * 12, 0xFF)
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)
      elseif s == victim then
        H.writeWord(0x3BF4 + s * 2, 10)
        H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | NEAR_FATAL)
        H.writeByte(0x3EF8 + s * 2, H.readByte(0x3EF8 + s * 2) | STOP)
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)
      elseif s == knight then
        H.writeWord(0x3BF4 + s * 2, 2000)                          -- survives covers
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) | TRUE_KNIGHT)                -- the staged relic
        H.writeByte(0x3EF8 + s * 2,
          H.readByte(0x3EF8 + s * 2) & ~STOP & 0xFF)               -- never stopped
        if holdKnight then H.writeByte(0x3219 + s * 2, 0x60) end
      else
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)        -- exactly one knight
      end
    end
  end
  for _, m in ipairs(msPresent) do
    if H.readWord(0x3BFC + m * 2) ~= 3000 then H.writeWord(0x3BFC + m * 2, 3000) end
    H.writeWord(0x3C24 + m * 2, 3000)
  end
end

-- ------------------------------------------------------------- instruments --
local covers = {}        -- { f = frame, blocker = entity } per COMMITTED cover
local bpWrites = {}      -- { f = frame, v = value } for the knight's bank

local function armCover()
  local addr = H.sym("SetCoverTarget")
  emu.addMemoryCallback(function()
    local f4, f8 = H.readByte(0x00F4), H.readByte(0x00F8)
    if f4 == 0xFF then return end                     -- the `bmi` bail
    if (emu.getState()["cpu.y"] & 0xFF) ~= f8 then return end   -- the `bne` bail
    covers[#covers + 1] = { f = H.frame, blocker = f4 }
  end, emu.callbackType.exec, addr, addr)
  H.log(string.format("cover detector armed at SetCoverTarget $%06X", addr))
end

-- lastBp is sampled at every frame START, so a write recorded during the frame
-- carries the value the bank held going into it: an earn is v == prev + 1 no
-- matter what the absolute bank happens to be.
local lastBp = nil
local function armBank()
  emu.addMemoryCallback(function(_, v)
    bpWrites[#bpWrites + 1] = { f = H.frame, v = v, prev = lastBp }
  end, emu.callbackType.write, 0x7E3E9C + knight * 2, 0x7E3E9C + knight * 2)
end

-- the blocker's party-window pip cell (both bands), battle_clockwork's reader
local function pipCells()
  local reg = H.readByte(0x897F)
  local base = ((reg - (reg % 4)) * 256) * 2
  local row
  for r = 0, 3 do if H.readByte(0x64D6 + r) == knight then row = r end end
  if not row then return nil end
  return emu.readWord(base + (1 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam),
         emu.readWord(base + (9 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam)
end

local watchGlyph, glyphFirstF = nil, nil
local function sample()
  pinField()
  if knight then lastBp = bp(knight) end
  if watchGlyph and not glyphFirstF then
    local lo, hi = pipCells()
    if lo and ((lo & 0xFF) == watchGlyph or (hi & 0xFF) == watchGlyph) then
      glyphFirstF = H.frame
    end
  end
end

-- SERVICE FOREIGN MENUS: a ready character's open menu parks the whole action
-- queue (battle_runic's measurement).  Never the knight's own, except when
-- phase 4 wants his turn.
local serviceKnight = false
local function service()
  if H.readByte(MENU) ~= 0
     and (serviceKnight or H.readByte(ACTOR) ~= knight) then
    H.setPad({ "a" })
  else
    H.setPad({})
  end
end
local DRIVE = {
  H.call(service), H.waitFrames(4),
  H.call(function() H.setPad({}) end), H.waitFrames(13),
}

local function coversSince(n) return #covers - n end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),

  -- --------------------------------------------------------------- install --
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    H.assertEq(#msPresent > 0, true, "monsters on the field")
    local live = {}
    for s = 0, 3 do if alive(s) and hp(s) > 0 then live[#live + 1] = s end end
    H.assertEq(#live >= 3, true, "three live characters (attacker/victim/knight)")
    attacker, victim, knight = live[1], live[2], live[3]
    H.log(string.format("attacker=slot %d (muddled) victim=slot %d (near fatal) "
      .. "knight=slot %d (staged True Knight); %d monsters",
      attacker, victim, knight, #msPresent))
    pinField()
    armCover()
    armBank()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
  end),
  H.waitFrames(120),
  H.call(function()
    -- the fixture's own preconditions, named before anything leans on them
    H.assertEq(st2(victim) & NEAR_FATAL, NEAR_FATAL,
      "the victim is NEAR FATAL (the gate CoverEffect reads at :2875)")
    H.assertEq(H.readByte(0x3C58 + knight * 2) & TRUE_KNIGHT, TRUE_KNIGHT,
      "the blocker carries the True Knight relic bit ($3c58.6)")
    H.assertEq(H.readByte(0x3EF8 + knight * 2) & STOP, 0,
      "and is NOT stopped (CheckCoverTarget would drop him)")
    H.assertEq(H.readByte(0x3C58 + attacker * 2) & TRUE_KNIGHT, 0,
      "and he is the ONLY True Knight on the field")
    H.writeByte(0x3E9C + knight * 2, 1)          -- a bank with room to grow
    H.writeByte(0x3E9D + knight * 2, 0)
    covers, bpWrites = {}, {}
    watchGlyph = PIP[2]                          -- the glyph a +1 must produce
  end),

  -- ------------------------------------ 1/2/3. the first cover of a round --
  H.driveUntil(function() return #covers > 0 end, 24000, DRIVE,
    "a True Knight cover commits"),
  H.waitFrames(60),                              -- let the vram flush land
  H.call(function()
    local c = covers[1]
    H.log(string.format("first cover at f%d, blocker entity $%02x (knight is $%02x); "
      .. "bank writes: %s", c.f, c.blocker, knight * 2,
      (function() local t = {} for _, w in ipairs(bpWrites) do
        t[#t + 1] = string.format("f%d=%d", w.f, w.v) end
        return table.concat(t, " ") end)()))
    H.assertEq(c.blocker, knight * 2,
      "the cover committed onto OUR knight (the only True Knight on the field)")
    -- 2. the bank
    H.assertEq(bp(knight), 2, "the cover banked exactly +1 bp")
    H.assertEq(pend(knight), 0, "with nothing pending to spend")
    H.assertEq(#bpWrites, 1, "exactly one bank write")
    H.assertEq(bpWrites[1].f, c.f,
      "and it lands on the COMMIT frame -- the block frame, not near it")
    -- 3. the pip
    H.assertEq(glyphFirstF ~= nil, true,
      "the party-window pip cell showed the new bank (OT6_PIPTAIL armed it)")
    H.assertEq(glyphFirstF >= c.f and glyphFirstF - c.f <= 12, true,
      string.format("and within the flush latency of that frame (commit %d, pip %s)",
        c.f, tostring(glyphFirstF)))
    H.log(string.format("pip glyph $%02x first seen at f%s (commit f%d)",
      watchGlyph, tostring(glyphFirstF), c.f))
    H.screenshot("trueknight_covered")
  end),

  -- --------------------------------------------- 4. the once-per-round cap --
  H.call(function() H.vars.mark = #covers end),
  H.driveUntil(function() return coversSince(H.vars.mark) >= 2 end, 30000, DRIVE,
    "two more covers in the same round (the knight never acted)"),
  H.call(function()
    H.log(string.format("covers so far: %d; bank %d; bank writes %d",
      #covers, bp(knight), #bpWrites))
    H.assertEq(bp(knight), 2,
      "further covers in the SAME round protect but bank nothing (the cap)")
    H.assertEq(#bpWrites, 1,
      "and the bank was written exactly once across the whole round")
  end),

  -- ------------------------------------------ 5. the round boundary is real --
  H.call(function()
    holdKnight = false
    serviceKnight = true
    H.vars.acted = false
  end),
  H.driveUntil(function()
    -- his action goes live in $32cc (battle_main.asm:254: $ff = nothing queued)
    if H.readByte(0x32CC + knight * 2) ~= 0xFF then H.vars.acted = true end
    return H.vars.acted and H.readByte(0x32CC + knight * 2) == 0xFF
  end, 20000, DRIVE, "the blocker takes his own turn and it resolves"),
  H.waitFrames(150),
  H.call(function()
    holdKnight = true
    serviceKnight = false
    H.writeByte(0x3E9C + knight * 2, 1)          -- re-baseline the bank
    H.writeByte(0x3E9D + knight * 2, 0)
    H.vars.mark2 = #covers
    bpWrites = {}
    H.log("the blocker took a turn (Ot6ActionEnd ran); bank re-baselined to 1")
  end),
  H.driveUntil(function() return coversSince(H.vars.mark2) >= 1 end, 30000, DRIVE,
    "a cover in the NEXT round"),
  H.waitFrames(30),
  H.call(function()
    local c = covers[H.vars.mark2 + 1]
    H.log(string.format("next-round cover at f%d; bank %d; writes since the turn: %s",
      c.f, bp(knight),
      (function() local t = {} for _, w in ipairs(bpWrites) do
        t[#t + 1] = string.format("f%d:%s->%d", w.f, tostring(w.prev), w.v) end
        return table.concat(t, " ") end)()))
    -- assert on the WRITE, not the absolute bank: the blocker's own turn also
    -- pays him a regen tick, and a settle long enough to guarantee that landed
    -- first would be a timing bet.  prev+1 on the commit frame is the earn.
    local w = nil
    for _, x in ipairs(bpWrites) do if x.f == c.f then w = x end end
    H.assertEq(w ~= nil, true,
      "the earn re-arms at the blocker's own turn end -- a bank write lands on "
      .. "the NEXT round's commit frame (once per ROUND, not once per battle)")
    H.assertEq(w.v, (w.prev or -99) + 1,
      "and it is exactly +1 on that frame")
    H.screenshot("trueknight_next_round")
  end),
  H.logStep(function()
    return string.format("battle_trueknight complete (%d committed covers)", #covers)
  end),
})
